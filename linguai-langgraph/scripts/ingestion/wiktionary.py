"""
Load English -> German translations from Wiktionary-derived data.

Source: kaikki.org English dictionary JSONL (one JSON object per line).
Each object has "word" or "head", and "senses" with "translations" (lang, word).
We extract (headword, target_word) for lang=de.
"""

import json
import logging
import unicodedata
from pathlib import Path
from typing import Iterator, Tuple

logger = logging.getLogger(__name__)


def _normalize(t: str) -> str:
    if not t:
        return ""
    s = unicodedata.normalize("NFKC", t.strip())
    return " ".join(s.split())


def stream_en_de_from_jsonl(path: Path, line_limit: int | None = None) -> Iterator[Tuple[str, str]]:
    """
    Stream a kaikki.org English dictionary JSONL file; yield (en_headword, de_translation).
    One headword can yield multiple pairs (multiple senses/translations).
    line_limit: if set, stop after reading this many JSON lines (for testing).
    """
    path = Path(path)
    if not path.is_file():
        logger.warning("Wiktionary JSONL not found: %s", path)
        return
    count = 0
    lines_read = 0
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            if line_limit is not None and lines_read >= line_limit:
                break
            line = line.strip()
            if not line:
                continue
            lines_read += 1
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            head = obj.get("word") or obj.get("head") or ""
            head = _normalize(head)
            if not head:
                continue
            senses = obj.get("senses") or []
            for sense in senses:
                for tr in sense.get("translations") or []:
                    lang = (tr.get("lang") or tr.get("lang_code") or "").lower()
                    if lang != "de" and lang != "deu":
                        continue
                    w = (tr.get("word") or "").strip()
                    w = _normalize(w)
                    if not w:
                        continue
                    count += 1
                    yield (head, w)
    logger.info("Wiktionary EN->DE pairs streamed: %d from %s (lines read: %d)", count, path, lines_read)


def load_en_de_translations(path: Path, line_limit: int | None = None) -> dict[str, list[str]]:
    """
    Load EN->DE from JSONL into headword -> list of German translations.
    We keep the first translation per sense to avoid explosion; caller can pick one.
    line_limit: if set, only read that many JSON lines from file (for testing).
    """
    result: dict[str, list[str]] = {}
    seen_pairs: set[Tuple[str, str]] = set()
    for head, de_word in stream_en_de_from_jsonl(path, line_limit=line_limit):
        if (head, de_word) in seen_pairs:
            continue
        seen_pairs.add((head, de_word))
        result.setdefault(head, []).append(de_word)
    logger.info("Wiktionary EN headwords with DE translation: %d (from %d pairs)", len(result), len(seen_pairs))
    return result
