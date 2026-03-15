#!/usr/bin/env python3
"""
C1/C2 checkup: trace where CEFR levels exist or are lost in the pipeline.

Stages:
  1. Raw CEFR CSV: count rows by CEFR column value
  2. Post-parse (load_cefr): distinct headwords by level after normalization/dedupe
  3. Final DB: count by level in vocab_entries

Answers: Does the source contain C1/C2? At which stage are they lost (if any)?

Usage (from project root):
  python scripts/audit_cefr_c1_c2.py
  python scripts/audit_cefr_c1_c2.py --cefr-path data/raw/cefr/cefrj-vocabulary-profile-1.5.csv --db data/vocab.db
"""

from __future__ import annotations

import argparse
import csv
import sys
from collections import Counter
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

import logging
logging.getLogger("scripts.ingestion.cefr").setLevel(logging.WARNING)

from scripts.ingestion.config import CEFR_RAW_DIR, get_db_path
from scripts.ingestion.cefr import load_cefr


def raw_cefr_level_counts(path: Path) -> Counter[str]:
    """Count rows in raw CSV by CEFR column value (no parsing/normalization)."""
    counts: Counter[str] = Counter()
    with open(path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            level_raw = (row.get("CEFR") or row.get("cefr") or "").strip()
            if level_raw:
                counts[level_raw] += 1
    return counts


def post_parse_level_counts(path: Path) -> Counter[str]:
    """Count distinct headwords by level after load_cefr (normalize + dedupe by min level)."""
    cefr = load_cefr(source_path=path)
    return Counter(cefr.values())


def db_level_counts(db_path: Path) -> Counter[str]:
    """Count rows in vocab_entries by level."""
    import sqlite3
    conn = sqlite3.connect(db_path)
    cur = conn.execute(
        "SELECT level, COUNT(*) FROM vocab_entries GROUP BY level"
    )
    counts = Counter()
    for level, n in cur.fetchall():
        if level:
            counts[level] = n
        else:
            counts["(null)"] = n
    conn.close()
    return counts


def main() -> int:
    ap = argparse.ArgumentParser(description="C1/C2 pipeline checkup")
    ap.add_argument("--cefr-path", type=Path, default=CEFR_RAW_DIR / "cefrj-vocabulary-profile-1.5.csv")
    ap.add_argument("--db", type=Path, default=None)
    args = ap.parse_args()
    db_path = args.db or get_db_path()

    print("=== C1/C2 checkup ===\n")

    # 1) Raw source
    cefr_path = args.cefr_path
    if not cefr_path.is_file():
        print("CEFR file not found:", cefr_path, file=sys.stderr)
        return 1
    raw = raw_cefr_level_counts(cefr_path)
    print("1) Raw CEFR CSV (column CEFR) — counts by value:")
    for lev in ["A1", "A2", "B1", "B2", "C1", "C2"]:
        print(f"   {lev}: {raw.get(lev, 0)}")
    other = {k: v for k, v in raw.items() if k not in ("A1", "A2", "B1", "B2", "C1", "C2")}
    if other:
        print("   Other values in CEFR column:", dict(other))
    c1_raw = raw.get("C1", 0)
    c2_raw = raw.get("C2", 0)
    print(f"\n   C1 in source: {c1_raw}; C2 in source: {c2_raw}")

    # 2) Post-parse (load_cefr)
    parsed = post_parse_level_counts(cefr_path)
    print("\n2) Post-parse (load_cefr) — distinct headwords by level:")
    for lev in ["A1", "A2", "B1", "B2", "C1", "C2"]:
        print(f"   {lev}: {parsed.get(lev, 0)}")
    c1_parse = parsed.get("C1", 0)
    c2_parse = parsed.get("C2", 0)
    print(f"\n   C1 after parse: {c1_parse}; C2 after parse: {c2_parse}")

    # 3) DB
    if db_path.is_file():
        db = db_level_counts(db_path)
        print("\n3) Final DB (vocab_entries) — rows by level:")
        for lev in ["A1", "A2", "B1", "B2", "C1", "C2"]:
            print(f"   {lev}: {db.get(lev, 0)}")
        if "(null)" in db:
            print(f"   (null): {db['(null)']}")
        print(f"\n   C1 in DB: {db.get('C1', 0)}; C2 in DB: {db.get('C2', 0)}")
    else:
        print("\n3) DB not found:", db_path)

    # Conclusion
    print("\n--- Conclusion ---")
    if c1_raw == 0 and c2_raw == 0:
        print("The CEFR source file does NOT contain C1 or C2. The Open Language Profiles")
        print("CEFR-J dataset (olp-en-cefrj) is A1–B2 only. C1/C2 absence is BY DESIGN")
        print("of the upstream source, not a pipeline bug.")
    elif c1_parse == 0 or c2_parse == 0:
        print("C1/C2 present in raw but lost at parse: check _normalize_level and column name.")
    elif db_path.is_file() and db.get("C1", 0) == 0 and db.get("C2", 0) == 0:
        print("C1/C2 present after parse but missing in DB: lost at join (no translation)")
        print("or at write (validation/constraint).")
    else:
        print("C1/C2 are present in the pipeline and DB.")
    print("\n=== checkup done ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
