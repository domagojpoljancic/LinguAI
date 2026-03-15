"""
Load English -> target-language translations from Wiktionary-derived data.

Source: kaikki.org English dictionary JSONL (one JSON object per line).
Each object has "word" or "head", and "senses" with "translations" (lang, word).
Supports multiple target languages (e.g. de, es) in one pass.
"""

import json
import logging
import unicodedata
from pathlib import Path
from typing import Iterator

logger = logging.getLogger(__name__)

# Normalize lang code: accept "de", "deu", "es", "spa", etc.
_LANG_ALIASES = {"de": "de", "deu": "de", "es": "es", "spa": "es", "fr": "fr", "fra": "fr"}


def _normalize(t: str) -> str:
    if not t:
        return ""
    s = unicodedata.normalize("NFKC", t.strip())
    return " ".join(s.split())


def _normalize_lang(lang: str) -> str | None:
    raw = (lang or "").strip().lower()
    return _LANG_ALIASES.get(raw) or (raw if len(raw) == 2 else None)


def stream_translations_to_langs(
    path: Path,
    target_langs: list[str],
    line_limit: int | None = None,
    *,
    include_sense: bool = False,
) -> Iterator[tuple[str, str, str] | tuple[str, str, str, str]]:
    """
    Stream kaikki.org English JSONL; yield (en_headword, target_lang, target_word)
    or when include_sense=True yield (en_headword, target_lang, target_word, sense_gloss).
    sense_gloss: from tr["sense"] (top-level) or parent sense["glosses"][0] (sense-level).
    """
    path = Path(path)
    if not path.is_file():
        logger.warning("Wiktionary JSONL not found: %s", path)
        return
    want = set(_normalize_lang(l) or l for l in target_langs)
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
            # Top-level translations: each has optional "sense"
            for tr in obj.get("translations") or []:
                if not isinstance(tr, dict):
                    continue
                raw_lang = (tr.get("lang_code") or tr.get("code") or tr.get("lang") or "").strip().lower()
                lang = _LANG_ALIASES.get(raw_lang) or (raw_lang if len(raw_lang) == 2 else None)
                if not lang or lang not in want:
                    continue
                w = (tr.get("word") or "").strip()
                w = _normalize(w)
                if not w:
                    continue
                count += 1
                sense = (tr.get("sense") or "").strip() if include_sense else ""
                if include_sense:
                    yield (head, lang, w, sense)
                else:
                    yield (head, lang, w)
            # Sense-level: attach parent sense's first gloss to each translation
            for sense in obj.get("senses") or []:
                gloss = ""
                if include_sense and sense.get("glosses"):
                    gloss = (sense["glosses"][0] or "").strip()
                for tr in sense.get("translations") or []:
                    if not isinstance(tr, dict):
                        continue
                    raw_lang = (tr.get("lang_code") or tr.get("code") or tr.get("lang") or "").strip().lower()
                    lang = _LANG_ALIASES.get(raw_lang) or (raw_lang if len(raw_lang) == 2 else None)
                    if not lang or lang not in want:
                        continue
                    w = (tr.get("word") or "").strip()
                    w = _normalize(w)
                    if not w:
                        continue
                    count += 1
                    if include_sense and not gloss and tr.get("sense"):
                        gloss = (tr.get("sense") or "").strip()
                    if include_sense:
                        yield (head, lang, w, gloss)
                    else:
                        yield (head, lang, w)
    logger.info(
        "Wiktionary EN->%s pairs streamed: %d from %s (lines read: %d)",
        "+".join(sorted(want)),
        count,
        path,
        lines_read,
    )


def load_en_translations_for_langs(
    path: Path,
    target_langs: list[str],
    line_limit: int | None = None,
    max_translations_per_head: int = 20,
) -> dict[str, dict[str, list[tuple[str, str]]]]:
    """
    Load EN->target translations with sense gloss for each target_lang in one pass.
    Returns: {target_lang: {headword: [(word, sense_gloss), ...]}}.
    Dedupes (headword, lang, word, sense); keeps up to max_translations_per_head per head per lang.
    Sense-aware selection in join uses sense_gloss to prefer topic-aligned translations.
    """
    result: dict[str, dict[str, list[tuple[str, str]]]] = {lang: {} for lang in target_langs}
    seen: set[tuple[str, str, str, str]] = set()
    for head, lang, word, sense in stream_translations_to_langs(
        path, target_langs, line_limit=line_limit, include_sense=True
    ):
        key = (head, lang, word, sense)
        if key in seen:
            continue
        seen.add(key)
        if head not in result[lang]:
            result[lang][head] = []
        if len(result[lang][head]) < max_translations_per_head:
            result[lang][head].append((word, sense))
    for lang in target_langs:
        n_heads = len(result[lang])
        n_pairs = sum(len(v) for v in result[lang].values())
        logger.info("Wiktionary EN->%s headwords: %d (pairs: %d)", lang, n_heads, n_pairs)
    return result


def stream_en_de_from_jsonl(path: Path, line_limit: int | None = None) -> Iterator[tuple[str, str]]:
    """
    Stream (en_headword, de_translation). Backward-compat wrapper (no sense).
    """
    for head, lang, w in stream_translations_to_langs(path, ["de"], line_limit=line_limit):
        yield (head, w)


def load_en_de_translations(path: Path, line_limit: int | None = None) -> dict[str, list[tuple[str, str]]]:
    """
    Load EN->DE from JSONL with (word, sense_gloss) per head. Backward-compat wrapper.
    """
    multi = load_en_translations_for_langs(path, ["de"], line_limit=line_limit)
    return multi.get("de", {})
