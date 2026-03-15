#!/usr/bin/env python3
"""
Offline vocabulary ingestion pipeline.

Builds or updates the SQLite vocabulary DB from:
- CEFR-tagged English vocabulary (Open Language Profiles CEFR-J)
- English -> German translations (kaikki.org Wiktionary English dictionary JSONL)

Usage:
  # From project root (recommended)
  python scripts/ingest_vocabulary.py --wiktionary-path data/raw/wiktionary/kaikki.org-dictionary-English.jsonl

  # Full rebuild and fetch CEFR from URL
  python scripts/ingest_vocabulary.py --rebuild --fetch-cefr --wiktionary-path data/raw/wiktionary/kaikki.org-dictionary-English.jsonl

  # Use local CEFR CSV only
  python scripts/ingest_vocabulary.py --cefr-path data/raw/cefr/cefrj-vocabulary-profile-1.5.csv --wiktionary-path data/raw/wiktionary/kaikki.org-dictionary-English.jsonl

Output DB: data/vocab.db (or VOCAB_DB_PATH).
"""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

# Ensure project root is on path
PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from scripts.ingestion import config as ingestion_config
from scripts.ingestion.cefr import load_cefr
from scripts.ingestion.join import join_cefr_and_translations
from scripts.ingestion.write_db import rebuild_db, write_rows
from scripts.ingestion.wiktionary import load_en_de_translations

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%SZ",
)
logger = logging.getLogger(__name__)


def run_ingestion(
    *,
    rebuild: bool = False,
    cefr_path: Path | None = None,
    fetch_cefr: bool = False,
    wiktionary_path: Path | None = None,
    wiktionary_line_limit: int | None = None,
) -> None:
    db_path = ingestion_config.get_db_path()
    logger.info("DB path: %s", db_path)

    if rebuild:
        logger.info("Rebuilding schema")
        rebuild_db(db_path)

    # 1) Load CEFR
    cefr_url = ingestion_config.CEFR_CSV_URL if fetch_cefr else None
    cefr = load_cefr(source_path=cefr_path, fetch_url=cefr_url)
    logger.info("CEFR headwords loaded: %d", len(cefr))

    if not cefr:
        logger.warning("No CEFR data; nothing to join. Provide --cefr-path or --fetch-cefr.")
        return

    # 2) Load translations (EN -> DE)
    wikt_path = wiktionary_path or ingestion_config.WIKTIONARY_JSONL_LOCAL
    if not Path(wikt_path).is_file():
        logger.warning(
            "Wiktionary JSONL not found at %s. Download from %s and pass --wiktionary-path.",
            wikt_path,
            ingestion_config.WIKTIONARY_EN_JSONL_URL,
        )
        return
    translations = load_en_de_translations(Path(wikt_path), line_limit=wiktionary_line_limit)
    logger.info("Wiktionary EN->DE headwords: %d", len(translations))

    if not translations:
        logger.warning("No translation data; nothing to write.")
        return

    # 3) Join and write
    rows = join_cefr_and_translations(cefr, translations, source_lang="en", target_lang="de")
    inserted, skipped, rejected = write_rows(rows, db_path=db_path, reject_log=True)
    logger.info("Written: inserted/replaced=%d, skipped_validation=%d, rejected_logged=%d", inserted, skipped, rejected)

    # 4) Sanity checks
    import sqlite3
    conn = sqlite3.connect(db_path)
    cur = conn.execute(
        "SELECT source_language, target_language, COUNT(*) FROM vocab_entries GROUP BY source_language, target_language"
    )
    by_pair = list(cur.fetchall())
    cur = conn.execute("SELECT level, COUNT(*) FROM vocab_entries GROUP BY level ORDER BY level")
    by_level = list(cur.fetchall())
    cur = conn.execute("SELECT topic, COUNT(*) FROM vocab_entries GROUP BY topic ORDER BY topic")
    by_topic = list(cur.fetchall())
    cur = conn.execute("SELECT default_text, target_text, level, topic FROM vocab_entries LIMIT 5")
    sample = list(cur.fetchall())
    conn.close()

    logger.info("Summary by language pair: %s", by_pair)
    logger.info("Summary by level: %s", by_level)
    logger.info("Summary by topic: %s", by_topic)
    logger.info("Sample rows: %s", sample)
    logger.info("Ingestion complete. DB: %s", db_path)


def main() -> int:
    ap = argparse.ArgumentParser(description="Ingest CEFR + Wiktionary EN->DE into vocabulary SQLite DB")
    ap.add_argument("--rebuild", action="store_true", help="Drop and recreate vocab_entries before ingest")
    ap.add_argument("--fetch-cefr", action="store_true", help="Fetch CEFR CSV from URL (Open Language Profiles)")
    ap.add_argument("--cefr-path", type=Path, default=None, help="Path to local CEFR CSV")
    ap.add_argument("--wiktionary-path", type=Path, default=None, help="Path to kaikki.org English dictionary JSONL")
    ap.add_argument("--wiktionary-line-limit", type=int, default=None, help="Max JSON lines to read (for testing)")
    args = ap.parse_args()
    run_ingestion(
        rebuild=args.rebuild,
        cefr_path=args.cefr_path,
        fetch_cefr=args.fetch_cefr,
        wiktionary_path=args.wiktionary_path,
        wiktionary_line_limit=args.wiktionary_line_limit,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
