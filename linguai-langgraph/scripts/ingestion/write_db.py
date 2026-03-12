"""
Safe SQLite population: transactions, INSERT OR REPLACE, optional rebuild.
"""

import logging
import sqlite3
from pathlib import Path
from typing import Any, Iterable

from app.vocab_schema import VOCAB_SCHEMA_VERSION, ensure_schema_version, full_schema_sql
from scripts.ingestion.config import get_db_path
from scripts.ingestion.validate import log_reject, validate_row

logger = logging.getLogger(__name__)


def write_rows(
    rows: Iterable[dict[str, Any]],
    db_path: Path | None = None,
    *,
    reject_log: bool = True,
) -> tuple[int, int, int]:
    """
    Write canonical rows to SQLite. Uses INSERT OR REPLACE on unique (source_lang, target_lang, default_text, target_text).
    Returns (inserted_or_replaced, skipped_validation, rejected_logged).
    """
    db_path = db_path or get_db_path()
    db_path = Path(db_path)
    db_path.parent.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(db_path)
    ensure_schema_version(conn)

    inserted = 0
    skipped = 0
    rejected = 0
    params_list = []
    for row in rows:
        ok, reason = validate_row(row)
        if not ok:
            skipped += 1
            if reject_log:
                log_reject(row, reason or "validation failed")
                rejected += 1
            continue
        params_list.append((
            row.get("source_language") or "",
            row.get("target_language") or "",
            row.get("default_text") or "",
            row.get("target_text") or "",
            row.get("level"),
            row.get("topic"),
            row.get("tags"),
            row.get("score", 1.0),
            row.get("source_type") or "primary",
            row.get("source_id"),
        ))
    # Batch in a single transaction
    try:
        conn.executemany(
            """
            INSERT OR REPLACE INTO vocab_entries (
                source_language, target_language, default_text, target_text,
                level, topic, tags, score, source_type, source_id, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, strftime('%Y-%m-%dT%H:%M:%SZ','now'))
            """,
            params_list,
        )
        inserted = len(params_list)
        conn.commit()
    except Exception as e:
        conn.rollback()
        logger.exception("Write failed: %s", e)
        raise
    try:
        conn.execute("ANALYZE")
        conn.commit()
    except Exception:
        pass
    finally:
        conn.close()
    return inserted, skipped, rejected


def rebuild_db(db_path: Path | None = None) -> None:
    """Drop vocab_entries and recreate schema. Backs up existing DB to .bak if present."""
    db_path = db_path or get_db_path()
    db_path = Path(db_path)
    if db_path.exists():
        bak = db_path.with_suffix(db_path.suffix + ".bak")
        import shutil
        shutil.copy2(db_path, bak)
        logger.info("Backed up existing DB to %s", bak)
    conn = sqlite3.connect(db_path)
    conn.execute("DROP TABLE IF EXISTS vocab_entries")
    conn.executescript(full_schema_sql())
    conn.execute(
        "INSERT OR REPLACE INTO _vocab_schema (key, value) VALUES (?, ?)",
        ("version", str(VOCAB_SCHEMA_VERSION)),
    )
    conn.commit()
    conn.close()
    logger.info("Rebuilt schema at %s", db_path)
