"""
Join CEFR vocabulary with translations to produce canonical bilingual rows.

Strategy: CEFR list is primary (level-bearing). Enrich with target translation.
Sense-aware: when multiple translation candidates exist, prefer the one whose
Wiktionary sense/gloss best matches the inferred topic (restaurant, travel, etc.).
"""

import logging
import re
from typing import Iterator

from scripts.ingestion.normalize import canonical_row
from scripts.ingestion.topics import TOPIC_KEYWORDS, TOPIC_SENSE_KEYWORDS, tag_topic

logger = logging.getLogger(__name__)


def pick_best_translation(
    translations: list[tuple[str, str]],
    topic: str,
) -> str:
    """
    Choose one translation from (word, sense_gloss) list using topic alignment.
    Scores each candidate by how many topic keywords appear as whole tokens in sense_gloss.
    Falls back to first candidate when topic is unknown or no sense overlap.
    """
    if not translations:
        return ""
    # Single candidate: no choice
    if len(translations) == 1:
        return translations[0][0]
    # Unknown/general topic: no disambiguation signal, use first (deterministic)
    if topic == "general" or topic not in TOPIC_SENSE_KEYWORDS:
        return translations[0][0]
    keywords = set(kw.lower() for kw in TOPIC_SENSE_KEYWORDS[topic])
    best_word = translations[0][0]
    best_score = -1
    for word, sense in translations:
        if not sense:
            score = 0
        else:
            tokens = set(re.split(r"\W+", sense.lower()))
            score = sum(1 for kw in keywords if kw in tokens)
        if score > best_score:
            best_score = score
            best_word = word
    return best_word


def join_cefr_and_translations(
    cefr_headword_to_level: dict[str, str],
    headword_to_translations: dict[str, list[tuple[str, str]]],
    source_lang: str = "en",
    target_lang: str = "de",
    *,
    max_translations_per_head: int = 1,
    source_type: str = "cefr",
) -> Iterator[dict]:
    """
    Yield canonical rows: (source_lang, target_lang, default_text, target_text, level, topic, ...).
    translations: list of (word, sense_gloss). One headword -> one row; translation chosen by
    pick_best_translation when multiple candidates exist.
    """
    joined = 0
    skipped_no_translation = 0
    for headword, level in cefr_headword_to_level.items():
        raw = headword_to_translations.get(headword) or []
        if not raw:
            skipped_no_translation += 1
            continue
        topic = tag_topic(headword)
        best_word = pick_best_translation(raw, topic)
        if not best_word:
            skipped_no_translation += 1
            continue
        row = canonical_row(
            source_lang,
            target_lang,
            headword,
            best_word,
            level=level,
            topic=topic,
            tags="",
            score=1.0,
            source_type=source_type,
        )
        joined += 1
        yield row
    logger.info(
        "Join: %d rows produced, %d CEFR headwords skipped (no translation)",
        joined,
        skipped_no_translation,
    )
