"""
Join CEFR vocabulary with translations to produce canonical bilingual rows.

Strategy: CEFR list is primary (level-bearing). Enrich with German translation.
If no translation found, skip (do not insert low-quality rows).
One headword -> one row per translation (we take first translation for MVP to avoid explosion).
"""

import logging
from typing import Iterator

from scripts.ingestion.normalize import canonical_row
from scripts.ingestion.topics import tag_topic

logger = logging.getLogger(__name__)


def join_cefr_and_translations(
    cefr_headword_to_level: dict[str, str],
    headword_to_translations: dict[str, list[str]],
    source_lang: str = "en",
    target_lang: str = "de",
    *,
    max_translations_per_head: int = 1,
    source_type: str = "cefr",
) -> Iterator[dict]:
    """
    Yield canonical rows: (source_lang, target_lang, default_text, target_text, level, topic, ...).
    Only yields rows where we have both CEFR level and at least one translation.
    """
    joined = 0
    skipped_no_translation = 0
    for headword, level in cefr_headword_to_level.items():
        translations = headword_to_translations.get(headword) or []
        if not translations:
            skipped_no_translation += 1
            continue
        topic = tag_topic(headword)
        for de_word in translations[:max_translations_per_head]:
            row = canonical_row(
                source_lang,
                target_lang,
                headword,
                de_word,
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
