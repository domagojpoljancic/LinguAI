"""
Load CEFR-tagged English vocabulary.

Source: Open Language Profiles CEFR-J (olp-en-cefrj) CSV.
Columns: headword, pos, CEFR, CoreInventory 1, CoreInventory 2, Threshold.
We use headword + CEFR; for duplicate headwords we take the minimum (easiest) level.
"""

import csv
import logging
import re
import unicodedata
from pathlib import Path
from typing import Iterator, Tuple

from scripts.ingestion.config import CEFR_CSV_LOCAL, CEFR_CSV_URL

logger = logging.getLogger(__name__)

CEFR_NORM = {"A1", "A2", "B1", "B2", "C1", "C2"}
CEFR_ORDER = ("A1", "A2", "B1", "B2", "C1", "C2")


def _normalize_level(raw: str) -> str | None:
    raw = (raw or "").strip().upper()
    if raw in CEFR_NORM:
        return raw
    # map common variants
    m = re.match(r"^([A-C])(1|2)$", raw)
    if m:
        return m.group(1) + m.group(2)
    return None


def _normalize_headword(word: str) -> str:
    if not word:
        return ""
    s = unicodedata.normalize("NFKC", word.strip())
    return " ".join(s.split())


def load_cefr_from_path(path: Path) -> Iterator[Tuple[str, str]]:
    """Yield (headword_normalized, level) from a local CSV. Headword may repeat; caller can dedupe by min level."""
    path = Path(path)
    if not path.is_file():
        logger.warning("CEFR file not found: %s", path)
        return
    count = 0
    with open(path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        if not reader.fieldnames:
            return
        for row in reader:
            head = (row.get("headword") or "").strip()
            level_raw = (row.get("CEFR") or row.get("cefr") or "").strip()
            level = _normalize_level(level_raw)
            if not head or not level:
                continue
            head_norm = _normalize_headword(head)
            if not head_norm or len(head_norm) > 200:
                continue
            count += 1
            yield (head_norm, level)
    logger.info("CEFR loaded from %s: %d rows", path, count)


def load_cefr_from_url(url: str, save_to: Path | None = None) -> Iterator[Tuple[str, str]]:
    """Fetch CSV from URL and yield (headword, level). Optionally save to save_to."""
    import urllib.request
    save_to = Path(save_to) if save_to else None
    logger.info("Fetching CEFR from %s", url)
    req = urllib.request.Request(url, headers={"User-Agent": "LinguAI-Ingestion/1.0"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = resp.read().decode("utf-8")
    if save_to:
        save_to.parent.mkdir(parents=True, exist_ok=True)
        save_to.write_text(data, encoding="utf-8")
        logger.info("Saved CEFR CSV to %s", save_to)
    reader = csv.DictReader(data.splitlines())
    count = 0
    for row in reader:
        head = (row.get("headword") or "").strip()
        level_raw = (row.get("CEFR") or row.get("cefr") or "").strip()
        level = _normalize_level(level_raw)
        if not head or not level:
            continue
        head_norm = _normalize_headword(head)
        if not head_norm or len(head_norm) > 200:
            continue
        count += 1
        yield (head_norm, level)
    logger.info("CEFR loaded from URL: %d rows", count)


def load_cefr(source_path: Path | None = None, fetch_url: str | None = None) -> dict[str, str]:
    """
    Load CEFR vocabulary. Prefer source_path; else fetch_url; else config default local path.
    Returns dict headword_normalized -> level (one level per word; if duplicate we keep easiest).
    """
    if source_path and Path(source_path).is_file():
        it = load_cefr_from_path(Path(source_path))
    elif fetch_url:
        it = load_cefr_from_url(fetch_url, save_to=CEFR_CSV_LOCAL)
    elif CEFR_CSV_LOCAL.is_file():
        it = load_cefr_from_path(CEFR_CSV_LOCAL)
    else:
        it = load_cefr_from_url(CEFR_CSV_URL, save_to=CEFR_CSV_LOCAL)
    # Dedupe: keep minimum (easiest) level per headword
    level_rank = {l: i for i, l in enumerate(CEFR_ORDER)}
    result: dict[str, str] = {}
    for head, level in it:
        if head in result:
            if level_rank.get(level, 99) < level_rank.get(result[head], 99):
                result[head] = level
        else:
            result[head] = level
    logger.info("CEFR distinct headwords: %d", len(result))
    return result
