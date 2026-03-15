"""Ingestion paths and config. No runtime dependency on app.request handlers."""

import os
from pathlib import Path

# Project root: scripts/ingestion/config.py -> ingestion -> scripts -> parent = project root
_INGESTION_DIR = Path(__file__).resolve().parent
SCRIPT_DIR = _INGESTION_DIR.parent
PROJECT_ROOT = SCRIPT_DIR.parent

DATA_DIR = PROJECT_ROOT / "data"
RAW_DIR = DATA_DIR / "raw"
CEFR_RAW_DIR = RAW_DIR / "cefr"
WIKTIONARY_RAW_DIR = RAW_DIR / "wiktionary"
REJECT_LOG_DIR = DATA_DIR / "ingestion_logs"

# DB path: same as runtime when not overridden
def get_db_path() -> Path:
    p = os.environ.get("VOCAB_DB_PATH")
    if p:
        return Path(p)
    return DATA_DIR / "vocab.db"

# CEFR source: Open Language Profiles CEFR-J (English vocabulary with CEFR levels)
CEFR_CSV_URL = "https://raw.githubusercontent.com/openlanguageprofiles/olp-en-cefrj/master/cefrj-vocabulary-profile-1.5.csv"
CEFR_CSV_LOCAL = CEFR_RAW_DIR / "cefrj-vocabulary-profile-1.5.csv"

# Wiktionary: kaikki.org English dictionary (one JSON object per line; includes translations to German)
# User can download and pass --wiktionary-path, or we document the URL for manual download
WIKTIONARY_EN_JSONL_URL = "https://kaikki.org/dictionary/English/kaikki.org-dictionary-English.jsonl"
WIKTIONARY_JSONL_LOCAL = WIKTIONARY_RAW_DIR / "kaikki.org-dictionary-English.jsonl"

# Limits for validation
MAX_TEXT_LEN = 500
MIN_TEXT_LEN = 1
