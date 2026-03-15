# Wiktionary raw data (English dictionary)

- **Source**: [kaikki.org English dictionary](https://kaikki.org/dictionary/English/) — JSONL, one JSON object per line. Each line has `word`, `senses[].translations[]` with `lang` (e.g. `de`, `es`) and `word`.
- **Sample**: `sample_en.jsonl` — 5 English headwords with DE and ES translations for quick seed without download.
- **Full file**: https://kaikki.org/dictionary/English/kaikki.org-dictionary-English.jsonl (≈2.7GB). Download: `python scripts/download_wiktionary.py` (writes to this dir), or save manually and pass `--wiktionary-path`.
- **Ingestion** supports multiple target languages in one pass: `--target-lang de,es`. For testing use `--wiktionary-line-limit 50000`.
