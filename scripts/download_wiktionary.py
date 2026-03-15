#!/usr/bin/env python3
"""
Download the full kaikki.org English dictionary JSONL for vocabulary ingestion.

Usage (from project root):
  python scripts/download_wiktionary.py
  python scripts/download_wiktionary.py -o /path/to/kaikki.org-dictionary-English.jsonl

Writes to data/raw/wiktionary/kaikki.org-dictionary-English.jsonl by default.
File is ~2.7GB; requires network.

If Python SSL fails (CERTIFICATE_VERIFY_FAILED), use curl instead:
  curl -L -o data/raw/wiktionary/kaikki.org-dictionary-English.jsonl \\
    https://kaikki.org/dictionary/English/kaikki.org-dictionary-English.jsonl
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from scripts.ingestion.config import WIKTIONARY_EN_JSONL_URL, WIKTIONARY_JSONL_LOCAL


def main() -> int:
    ap = argparse.ArgumentParser(description="Download kaikki.org English dictionary JSONL")
    ap.add_argument(
        "-o", "--output",
        type=Path,
        default=WIKTIONARY_JSONL_LOCAL,
        help="Output path (default: data/raw/wiktionary/kaikki.org-dictionary-English.jsonl)",
    )
    args = ap.parse_args()
    out = args.output.resolve()
    out.parent.mkdir(parents=True, exist_ok=True)

    try:
        import urllib.request
        req = urllib.request.Request(WIKTIONARY_EN_JSONL_URL, headers={"User-Agent": "LinguAI-Ingestion/1.0"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            total = int(resp.headers.get("Content-Length", 0))
            chunk_size = 1 << 20  # 1 MiB
            written = 0
            with open(out, "wb") as f:
                while True:
                    chunk = resp.read(chunk_size)
                    if not chunk:
                        break
                    f.write(chunk)
                    written += len(chunk)
                    if total and written % (100 * chunk_size) < chunk_size:
                        pct = 100 * written / total if total else 0
                        print(f"\rDownloaded {written // (1 << 20)} MiB ({pct:.1f}%)", end="", flush=True)
        print(f"\nSaved to {out} ({written // (1 << 20)} MiB)")
        return 0
    except Exception as e:
        print(f"Download failed: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
