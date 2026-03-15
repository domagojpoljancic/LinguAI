#!/usr/bin/env python3
"""
Lightweight data QA for vocab_entries.

Reports: total rows, by language pair, by CEFR level, null/empty topic and level,
by source_type, topic distribution, sample rows, duplicate-quality checks.

Usage (from project root):
  python scripts/audit_vocab.py
  python scripts/audit_vocab.py --db path/to/vocab.db
"""

from __future__ import annotations

import argparse
import os
import sqlite3
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from scripts.ingestion.config import get_db_path


def run_audit(db_path: Path) -> None:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    def scalar(q: str, *a: object) -> int:
        cur.execute(q, a)
        return int(cur.fetchone()[0])

    def rows(q: str, *a: object):
        cur.execute(q, a)
        return cur.fetchall()

    print("=== vocab_entries audit ===\n")
    print("DB:", db_path)
    total = scalar("SELECT COUNT(*) FROM vocab_entries")
    print("Total rows:", total)
    if total == 0:
        print("(empty DB)")
        conn.close()
        return

    print("\n--- By language pair ---")
    for r in rows(
        "SELECT source_language, target_language, COUNT(*) AS n FROM vocab_entries GROUP BY source_language, target_language ORDER BY source_language, target_language"
    ):
        print(f"  {r['source_language']} -> {r['target_language']}: {r['n']}")

    print("\n--- By CEFR level ---")
    for r in rows(
        "SELECT level, COUNT(*) AS n FROM vocab_entries GROUP BY level ORDER BY level"
    ):
        print(f"  {r['level']}: {r['n']}")

    null_level = scalar("SELECT COUNT(*) FROM vocab_entries WHERE level IS NULL OR trim(level) = ''")
    null_topic = scalar("SELECT COUNT(*) FROM vocab_entries WHERE topic IS NULL OR trim(topic) = ''")
    print("\n--- Null/empty ---")
    print("  level null or empty:", null_level)
    print("  topic null or empty:", null_topic)

    print("\n--- By source_type ---")
    for r in rows(
        "SELECT source_type, COUNT(*) AS n FROM vocab_entries GROUP BY source_type ORDER BY source_type"
    ):
        print(f"  {r['source_type']}: {r['n']}")

    print("\n--- Topic distribution ---")
    for r in rows(
        "SELECT topic, COUNT(*) AS n FROM vocab_entries GROUP BY topic ORDER BY n DESC"
    ):
        print(f"  {r['topic']}: {r['n']}")

    print("\n--- Representative EN->DE (5) ---")
    for r in rows(
        "SELECT default_text, target_text, level, topic, source_type FROM vocab_entries WHERE source_language='en' AND target_language='de' ORDER BY level, default_text LIMIT 5"
    ):
        print(f"  {r['default_text']} -> {r['target_text']}  [{r['level']}] topic={r['topic']}")

    print("\n--- Representative EN->ES (5) ---")
    for r in rows(
        "SELECT default_text, target_text, level, topic, source_type FROM vocab_entries WHERE source_language='en' AND target_language='es' ORDER BY level, default_text LIMIT 5"
    ):
        print(f"  {r['default_text']} -> {r['target_text']}  [{r['level']}] topic={r['topic']}")

    # Duplicate-quality: same (default_text, target_text) with different levels or topics?
    print("\n--- Duplicate-quality (same default_text + target_text, multiple rows) ---")
    dup = rows(
        """
        SELECT source_language, target_language, default_text, target_text, COUNT(*) AS n
        FROM vocab_entries
        GROUP BY source_language, target_language, default_text, target_text
        HAVING COUNT(*) > 1
        """
    )
    if dup:
        print(f"  Pairs with duplicate (default_text, target_text): {len(dup)}")
        for r in dup[:5]:
            print(f"    {r['default_text']} / {r['target_text']}: {r['n']} rows")
    else:
        print("  None (unique constraint holds).")

    conn.close()
    print("\n=== audit done ===")


def main() -> int:
    ap = argparse.ArgumentParser(description="Audit vocab_entries data quality")
    ap.add_argument("--db", type=Path, default=None, help="Path to vocab DB (default: data/vocab.db)")
    args = ap.parse_args()
    db_path = args.db or get_db_path()
    if not db_path.is_file():
        print("DB not found:", db_path, file=sys.stderr)
        return 1
    run_audit(db_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
