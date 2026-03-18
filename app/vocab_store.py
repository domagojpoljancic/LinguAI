"""
Local SQLite-backed vocabulary store and retrieval helpers.

Runtime responsibilities only:
- initialize a small normalized vocab table
- seed a tiny in-repo dataset for development
- provide structured retrieval for box creation

Offline ingestion / real datasets will plug into this module later by
populating the same table with primary (CEFR-tagged) and fallback sources.
"""

from __future__ import annotations

import logging
import os
import re
import sqlite3
import threading
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

from app.vocab_schema import default_db_path, ensure_schema_version

logger = logging.getLogger(__name__)


BASE_DIR = Path(__file__).resolve().parents[1]
DATA_DIR = BASE_DIR / "data"


def _db_path() -> Path:
    """DB path: VOCAB_DB_PATH env or default data/vocab.db."""
    p = os.environ.get("VOCAB_DB_PATH")
    if p:
        return Path(p)
    return default_db_path()


DB_PATH = None  # Resolved at runtime via _db_path() so ingestion can override

# SQLite connections are thread-bound by default in Python's sqlite3 module.
# This module is used in server runtime with concurrent request threads, so we
# must never reuse a connection across threads. We also avoid global connection
# caching and instead create a fresh connection per retrieval call.
_DB_INIT_LOCK = threading.Lock()

# CEFR ordering for level filtering / ranking
CEFR_ORDER: Sequence[str] = ("A1", "A2", "B1", "B2", "C1", "C2")
CEFR_RANK: Dict[str, int] = {lvl: i for i, lvl in enumerate(CEFR_ORDER)}


def _level_rank(level: str | None) -> int:
    """Return integer rank for CEFR level (unknown treated as easiest)."""
    if not level:
        return 0
    return CEFR_RANK.get(level.upper(), 0)


def _ensure_conn() -> sqlite3.Connection:
    """Get or create the SQLite connection, ensure schema + seed exists."""
    path = _db_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    # Ensure schema/seed are safe under concurrency (multiple threads may call
    # retrieve_candidates concurrently in server runtime).
    with _DB_INIT_LOCK:
        ensure_schema_version(conn)
        _seed_if_empty(conn)
    return conn


def _seed_if_empty(conn: sqlite3.Connection) -> None:
    """Insert a small EN->ES seed dataset if the table is empty."""
    cur = conn.execute("SELECT COUNT(1) FROM vocab_entries")
    (count,) = cur.fetchone()
    if count:
        return

    logger.info("vocab_store: seeding initial EN->ES dataset at %s", _db_path())

    rows: List[Tuple[str, str, str, str, str, str, str, float, str]] = []

    # Helper to append seed rows
    def add(
        default_text: str,
        target_text: str,
        *,
        level: str,
        topic: str,
        tags: str,
        score: float,
        source_type: str = "primary",
    ) -> None:
        rows.append(("en", "es", default_text, target_text, level, topic, tags, score, source_type))

    # Daily basics (A1)
    add("hello", "hola", level="A1", topic="daily", tags="greeting,daily", score=1.0)
    add("goodbye", "adiós", level="A1", topic="daily", tags="greeting,daily", score=1.0)
    add("please", "por favor", level="A1", topic="daily", tags="politeness,daily", score=1.0)
    add("thank you", "gracias", level="A1", topic="daily", tags="politeness,daily", score=1.0)
    add("sorry", "lo siento", level="A1", topic="daily", tags="apology,daily", score=0.9)
    add("yes", "sí", level="A1", topic="daily", tags="basic,daily", score=0.9)
    add("no", "no", level="A1", topic="daily", tags="basic,daily", score=0.9)

    # Numbers / misc daily
    add("one", "uno", level="A1", topic="daily", tags="number,daily", score=0.8)
    add("two", "dos", level="A1", topic="daily", tags="number,daily", score=0.8)
    add("three", "tres", level="A1", topic="daily", tags="number,daily", score=0.8)

    # Restaurant (A1–A2)
    add("menu", "el menú", level="A1", topic="restaurant", tags="restaurant,food", score=1.0)
    add("water", "el agua", level="A1", topic="restaurant", tags="restaurant,drink", score=0.9)
    add("bill", "la cuenta", level="A1", topic="restaurant", tags="restaurant,payment", score=1.0)
    add("table", "la mesa", level="A1", topic="restaurant", tags="restaurant,furniture", score=0.8)
    add("waiter", "el camarero", level="A2", topic="restaurant", tags="restaurant,people", score=0.9)
    add("reservation", "la reserva", level="A2", topic="restaurant", tags="restaurant,booking", score=0.9)
    add("fork", "el tenedor", level="A2", topic="restaurant", tags="restaurant,cutlery", score=0.8)
    add("knife", "el cuchillo", level="A2", topic="restaurant", tags="restaurant,cutlery", score=0.8)
    add("spoon", "la cuchara", level="A2", topic="restaurant", tags="restaurant,cutlery", score=0.8)

    # Travel (A1–B1)
    add("ticket", "el billete", level="A1", topic="travel", tags="travel,transport", score=0.9)
    add("train", "el tren", level="A1", topic="travel", tags="travel,transport", score=0.9)
    add("airport", "el aeropuerto", level="A2", topic="travel", tags="travel,place", score=0.9)
    add("flight", "el vuelo", level="A2", topic="travel", tags="travel,transport", score=0.9)
    add("hotel", "el hotel", level="A1", topic="travel", tags="travel,accommodation", score=0.9)
    add("passport", "el pasaporte", level="A2", topic="travel", tags="travel,document", score=0.9)
    add("luggage", "el equipaje", level="B1", topic="travel", tags="travel,airport", score=0.8)
    add("boarding pass", "la tarjeta de embarque", level="B1", topic="travel", tags="travel,airport", score=0.8)

    # Business (A2–B2)
    add("meeting", "la reunión", level="A2", topic="business", tags="business,work", score=0.9)
    add("office", "la oficina", level="A2", topic="business", tags="business,place", score=0.8)
    add("deadline", "la fecha límite", level="B1", topic="business", tags="business,time", score=0.9)
    add("invoice", "la factura", level="B1", topic="business", tags="business,finance", score=0.9)
    add("contract", "el contrato", level="B2", topic="business", tags="business,legal", score=0.8)
    add("negotiation", "la negociación", level="B2", topic="business", tags="business,meeting", score=0.8)

    # Shopping (A1–A2)
    add("price", "el precio", level="A1", topic="shopping", tags="shopping,money", score=0.9)
    add("shop", "la tienda", level="A1", topic="shopping", tags="shopping,place", score=0.9)
    add("discount", "el descuento", level="A2", topic="shopping", tags="shopping,money", score=0.8)
    add("cashier", "el cajero", level="A2", topic="shopping", tags="shopping,people", score=0.8)
    add("receipt", "el recibo", level="A2", topic="shopping", tags="shopping,payment", score=0.8)

    # Health (A1–B1)
    add("doctor", "el médico", level="A1", topic="health", tags="health,people", score=0.9)
    add("hospital", "el hospital", level="A1", topic="health", tags="health,place", score=0.9)
    add("pharmacy", "la farmacia", level="A1", topic="health", tags="health,place", score=0.9)
    add("medicine", "la medicina", level="A2", topic="health", tags="health,drug", score=0.9)
    add("appointment", "la cita", level="A2", topic="health", tags="health,time", score=0.8)
    add("symptom", "el síntoma", level="B1", topic="health", tags="health,condition", score=0.7)

    # Dating / social (A2–B1)
    add("date", "la cita", level="A2", topic="dating", tags="dating,meeting", score=0.8)
    add("relationship", "la relación", level="B1", topic="dating", tags="dating,relationship", score=0.8)
    add("partner", "la pareja", level="B1", topic="dating", tags="dating,people", score=0.8)
    add("flirt", "coquetear", level="B1", topic="dating", tags="dating,verb", score=0.7)

    # A few very general fallbacks
    add("word", "la palabra", level="A2", topic="general", tags="general", score=0.5, source_type="fallback")
    add("phrase", "la frase", level="A2", topic="general", tags="general", score=0.5, source_type="fallback")

    conn.executemany(
        """
        INSERT INTO vocab_entries (
            source_language,
            target_language,
            default_text,
            target_text,
            level,
            topic,
            tags,
            score,
            source_type
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        rows,
    )
    conn.commit()


def _normalized_existing_words(existing_words: Iterable[Tuple[str, str]]) -> Tuple[set[Tuple[str, str]], set[str]]:
    """Return (pairs, defaults) sets for duplicate filtering."""
    pairs: set[Tuple[str, str]] = set()
    defaults: set[str] = set()
    for default, target in existing_words:
        d = (default or "").strip().lower()
        t = (target or "").strip().lower()
        if d and t:
            pairs.add((d, t))
        if d:
            defaults.add(d)
    return pairs, defaults


# Topic-specific keys: do not widen to daily/general so we avoid padding with off-topic words.
TOPIC_SPECIFIC_KEYS = frozenset({"restaurant", "travel", "business", "shopping", "health", "dating"})

# Wrong-sense (default_text, topic, target_text) to skip: known bad translations for a topic.
# Sense-aware ingestion (scripts/ingestion) now prefers topic-aligned translations; these
# entries remain for any residual bad pairs or words not fixed by gloss scoring.
WRONG_SENSE_BLOCKLIST: frozenset[Tuple[str, str, str]] = frozenset({
    ("beat", "restaurant", "beat"),
    ("bombard", "restaurant", "bombarde"),
})


def _primary_and_widen_topics(display_topic: str | None) -> Tuple[str, List[str]]:
    """
    Map display box name (e.g. "Street Eats") to normalized topic key, plus widening list.
    For topic-specific requests we do NOT widen (no daily/general) so boxes stay on-topic.
    "unsupported" returns no topics so retrieval returns 0 words (defensive; box_workflow usually skips retrieval).
    """
    if not display_topic:
        primary = "daily"
    elif display_topic.strip().lower() == "unsupported":
        return "unsupported", []
    else:
        name = display_topic.strip().lower()
        if "street" in name or "restaurant" in name or "eat" in name or "menu" in name:
            primary = "restaurant"
        elif "city" in name or "travel" in name or "airport" in name or "trip" in name:
            primary = "travel"
        elif "office" in name or "business" in name or "meeting" in name:
            primary = "business"
        elif "date" in name or "romance" in name or "love" in name:
            primary = "dating"
        elif "shop" in name or "store" in name or "market" in name:
            primary = "shopping"
        elif "health" in name or "doctor" in name or "hospital" in name:
            primary = "health"
        elif "daily" in name or "basic" in name or "essentials" in name:
            primary = "daily"
        else:
            primary = "daily"

    if primary in TOPIC_SPECIFIC_KEYS:
        widened = [primary]
    else:
        widening_map: Dict[str, List[str]] = {
            "daily": ["daily", "general"],
            "general": ["daily", "general"],
        }
        widened = widening_map.get(primary, [primary, "daily"])
    return primary, widened


def _situation_tokens(situation_hint: str | None) -> set[str]:
    """Tokenize situation hint for ranking: lowercase, non-empty word tokens (min len 2)."""
    if not situation_hint or not situation_hint.strip():
        return set()
    tokens = set(re.findall(r"[a-z0-9]{2,}", situation_hint.lower()))
    return tokens


def retrieve_candidates(
    source_language: str,
    target_language: str,
    *,
    display_topic: str | None,
    level: str | None,
    existing_words: Iterable[Tuple[str, str]],
    max_items: int = 30,
    include_debug: bool = False,
    situation_hint: str | None = None,
) -> Tuple[List[Dict[str, str]], Dict[str, object], Optional[List[Dict[str, object]]], List[str]]:
    """
    Retrieve up to max_items vocabulary pairs for a box.

    - filters by source/target language
    - prefers entries whose topic matches the box topic
    - when situation_hint is set (e.g. from AI topic reason), ranks rows whose default_text
      contains any of the hint tokens first, so more situation-relevant words appear earlier
    - filters by CEFR level <= learner level when provided
    - removes duplicates against existing boxes
    - widens topic and uses fallback entries when needed

    When include_debug=True, returns (words, stats, debug_list, phases) with one debug dict per word.
    phases[i] is \"primary\" or \"widened\" for words[i] (DB quality signal).
    """
    conn = _ensure_conn()
    max_items = max(1, min(max_items, 30))
    learner_rank = _level_rank(level)
    primary_topic, widened_topics = _primary_and_widen_topics(display_topic)
    existing_pairs, existing_defaults = _normalized_existing_words(existing_words)

    all_selected: List[Tuple[sqlite3.Row, str]] = []
    used_ids: set[int] = set()
    duplicate_count = 0
    primary_candidate_count = 0
    widened_candidate_count = 0
    fallback_used = False

    def fetch_for_topics(topics: Sequence[str]) -> List[sqlite3.Row]:
        if not topics:
            return []
        placeholders = ",".join("?" for _ in topics)
        params: Tuple[object, ...] = (source_language, target_language, *topics)
        cur = conn.execute(
            f"""
            SELECT id, default_text, target_text, level, topic, score, source_type
            FROM vocab_entries
            WHERE source_language = ?
              AND target_language = ?
              AND topic IN ({placeholders})
            """,
            params,
        )
        return list(cur.fetchall())

    # Phase 1: primary topic only
    primary_rows = fetch_for_topics([primary_topic])
    primary_candidate_count = len(primary_rows)

    def consider_rows(rows: Sequence[sqlite3.Row], phase: str) -> None:
        nonlocal duplicate_count, fallback_used
        for row in rows:
            if len(all_selected) >= max_items:
                break
            row_id = int(row["id"])
            if row_id in used_ids:
                continue

            lvl = row["level"]
            if learner_rank and _level_rank(lvl) > learner_rank:
                continue

            d = (row["default_text"] or "").strip()
            t = (row["target_text"] or "").strip()
            d_norm = d.lower()
            t_norm = t.lower()
            row_topic = (row["topic"] or "").strip().lower()

            if (d_norm, row_topic, t_norm) in WRONG_SENSE_BLOCKLIST:
                continue
            if (d_norm, t_norm) in existing_pairs or d_norm in existing_defaults:
                duplicate_count += 1
                continue

            used_ids.add(row_id)
            all_selected.append((row, phase))
            if row["source_type"] != "primary":
                fallback_used = True

    consider_rows(primary_rows, "primary")

    # Phase 2: widen topic if needed
    if len(all_selected) < max_items and widened_topics:
        widened_rows = fetch_for_topics(widened_topics)
        widened_candidate_count = len(widened_rows)
        widened_rows_sorted = sorted(
            widened_rows,
            key=lambda r: (-float(r["score"] or 0.0), _level_rank(r["level"]), (r["default_text"] or "")),
        )
        consider_rows(widened_rows_sorted, "widened")

    # Sort: when situation_hint is set, prefer rows whose default_text contains any hint token
    # (so situation-relevant words rank first); then score desc, level asc, default_text asc.
    hint_tokens = _situation_tokens(situation_hint)

    def _rank_key(item: Tuple[sqlite3.Row, str]) -> Tuple[int, float, int, str]:
        row, _ = item
        default = (row["default_text"] or "").lower()
        score = float(row["score"] or 0.0)
        lvl = _level_rank(row["level"])
        text = (row["default_text"] or "")
        if hint_tokens and any(t in default for t in hint_tokens):
            situation_first = 0  # match first
        else:
            situation_first = 1
        return (situation_first, -score, lvl, text)

    try:
        final_pairs = sorted(all_selected, key=_rank_key)

        words = [{"default": r["default_text"], "target": r["target_text"]} for r, _ in final_pairs]
        phases = [str(phase) for _, phase in final_pairs]
        stats: Dict[str, object] = {
            "primary_topic": primary_topic,
            "widened_topics": widened_topics,
            "primary_candidate_count": primary_candidate_count,
            "widened_candidate_count": widened_candidate_count,
            "duplicate_count": duplicate_count,
            "final_count": len(words),
            "used_fallback_source": fallback_used,
            "partial": len(words) < max_items,
        }

        debug_list: Optional[List[Dict[str, object]]] = None
        if include_debug and final_pairs:
            debug_list = []
            for row, phase in final_pairs:
                row_topic = (row["topic"] or "").strip().lower()
                matched = row_topic == primary_topic
                from_widened = phase == "widened"
                reason = "primary_topic" if matched and not from_widened else ("widened_topic" if from_widened else "primary_topic")
                debug_list.append({
                    "default": row["default_text"],
                    "target": row["target_text"],
                    "topic": row["topic"],
                    "level": row["level"],
                    "source_type": row["source_type"],
                    "score": float(row["score"] or 0.0),
                    "matched_primary_topic": matched,
                    "from_widened": from_widened,
                    "selection_reason": reason,
                })
        return words, stats, debug_list, phases
    finally:
        conn.close()


def persist_ai_fallback_pairs(
    source_language: str,
    target_language: str,
    pairs: List[Tuple[str, str]],
    *,
    level: Optional[str],
    topic: Optional[str],
) -> int:
    """
    Persist validated AI pairs returned to the user. INSERT OR IGNORE on unique
    (source_language, target_language, default_text, target_text).
    source_type=ai_fallback. Uses a fresh connection (safe for background threads).
    Returns number of rows inserted.
    """
    if not pairs:
        return 0
    path = _db_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path)
    try:
        ensure_schema_version(conn)
        inserted = 0
        topic_val = (topic or "general").strip()[:64] or "general"
        lvl = level if level and level.upper() in CEFR_ORDER else None
        for d, t in pairs:
            da = (d or "").strip()
            ta = (t or "").strip()
            if not da or not ta:
                continue
            cur = conn.execute(
                """
                INSERT OR IGNORE INTO vocab_entries
                (source_language, target_language, default_text, target_text, level, topic, tags, score, source_type)
                VALUES (?, ?, ?, ?, ?, ?, 'ai_fallback', 0.82, 'ai_fallback')
                """,
                (source_language.lower(), target_language.lower(), da, ta, lvl, topic_val),
            )
            if cur.rowcount and cur.rowcount > 0:
                inserted += int(cur.rowcount)
        conn.commit()
        logger.info(
            "persist_ai_fallback_pairs inserted=%d pair_count=%d lang=%s-%s",
            inserted,
            len(pairs),
            source_language,
            target_language,
        )
        return inserted
    except Exception:
        logger.exception("persist_ai_fallback_pairs failed")
        try:
            conn.rollback()
        except Exception:
            pass
        return 0
    finally:
        conn.close()


def describe_schema() -> str:
    """Return a human-readable description of the vocab schema (for debug/docs)."""
    from app.vocab_schema import describe_schema as _schema_desc
    return _schema_desc()


# Offline ingestion boundary:
# In a follow-up step, a separate script/module should populate vocab_entries
# from real CEFR/core datasets and phrasebook-style fallbacks, writing into
# the same DB_PATH. This module deliberately only handles runtime retrieval.

