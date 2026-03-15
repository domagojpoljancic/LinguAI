"""Canonical row format for vocab_entries. Same schema as runtime."""

from typing import Any

# Canonical field names (must match vocab_entries columns)
def canonical_row(
    source_language: str,
    target_language: str,
    default_text: str,
    target_text: str,
    *,
    level: str | None = None,
    topic: str | None = None,
    tags: str | None = None,
    score: float = 1.0,
    source_type: str = "primary",
    source_id: str | None = None,
) -> dict[str, Any]:
    return {
        "source_language": source_language.strip().lower()[:10],
        "target_language": target_language.strip().lower()[:10],
        "default_text": default_text.strip(),
        "target_text": target_text.strip(),
        "level": (level.strip().upper() if level else None),
        "topic": (topic.strip().lower() if topic else None),
        "tags": (tags.strip() if tags else None),
        "score": float(score),
        "source_type": source_type.strip().lower(),
        "source_id": (source_id.strip() if source_id else None),
    }
