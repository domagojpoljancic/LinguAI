"""
Validation and reject logging for vocabulary rows.

Rejects: empty text, too long, number-only, symbol-only, bad level/source_type.
"""

import logging
import re
from pathlib import Path
from typing import Any, Optional

from app.vocab_schema import CEFR_LEVELS, SOURCE_TYPES
from scripts.ingestion.config import MAX_TEXT_LEN, MIN_TEXT_LEN, REJECT_LOG_DIR

logger = logging.getLogger(__name__)

REJECT_PATH = REJECT_LOG_DIR / "rejected.jsonl"


def _is_number_or_symbol_only(s: str) -> bool:
    if not s:
        return True
    return bool(re.match(r"^[\d\s\.\,\-\+\;\:\!\?\*]+$", s)) or s.isdigit()


def _too_long(s: str) -> bool:
    return len(s) > MAX_TEXT_LEN


def _too_short(s: str) -> bool:
    return len((s or "").strip()) < MIN_TEXT_LEN


def validate_row(row: dict[str, Any]) -> tuple[bool, Optional[str]]:
    """
    Validate a canonical row. Returns (ok, reason).
    reason is None if ok else short reason string.
    """
    default = (row.get("default_text") or "").strip()
    target = (row.get("target_text") or "").strip()
    if _too_short(default):
        return False, "default_text empty or too short"
    if _too_short(target):
        return False, "target_text empty or too short"
    if _too_long(default) or _too_long(target):
        return False, "text too long"
    if _is_number_or_symbol_only(default) or _is_number_or_symbol_only(target):
        return False, "number/symbol only"
    level = row.get("level")
    if level is not None and level not in CEFR_LEVELS:
        return False, f"invalid level {level!r}"
    st = row.get("source_type") or ""
    if st not in SOURCE_TYPES:
        return False, f"invalid source_type {st!r}"
    return True, None


def log_reject(row: dict[str, Any], reason: str) -> None:
    """Append a rejected row and reason to REJECT_PATH."""
    try:
        REJECT_PATH.parent.mkdir(parents=True, exist_ok=True)
        with open(REJECT_PATH, "a", encoding="utf-8") as f:
            import json
            f.write(json.dumps({"reason": reason, "row": row}, ensure_ascii=False) + "\n")
    except OSError:
        pass
