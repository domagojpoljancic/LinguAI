"""
Prompt builder for AI fallback vocabulary word-pair generation.

Driven by retrieval_route, user prompt, languages, level, topic metadata — not by legacy "unsupported" alone.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import List, Tuple


@dataclass
class WordGenerationContext:
    """Inputs for building the word-generation prompt."""

    user_prompt: str
    default_language: str
    target_language: str
    level: str  # CEFR
    topic: str  # interpreted topic key or label
    topic_keywords: List[str] = field(default_factory=list)
    situation_label: str = ""
    topic_reason: str = ""
    retrieval_route: str = ""  # db_first | ai_first | mixed
    existing_default_words: List[str] = field(default_factory=list)
    existing_word_pairs: List[Tuple[str, str]] = field(default_factory=list)
    max_pairs: int = 25


SYSTEM_INSTRUCTIONS = """You are a vocabulary assistant for a language-learning app.

Your task is to propose vocabulary word pairs only when you are highly confident each pair is:
- a single common word in the source (default) language
- a correct, common translation as a single word in the target language
- appropriate for the learner's CEFR level
- practical for the described situation

Rules:
- Output ONLY structured data matching the required schema. No prose.
- Each item must be exactly one word in "default" and exactly one word in "target" (no phrases, no multi-word entries).
- Use "confidence" per pair from 0.0 to 1.0 — only include pairs you would rate at least 0.85 if unsure use fewer items.
- Prefer fewer high-quality pairs over many weak ones.
- Do not invent obscure, archaic, or highly technical terms unless clearly requested.
- Avoid duplicates within your list.
"""


def build_user_message(ctx: WordGenerationContext) -> str:
    """Build the user message with full context for the model."""
    avoid = ", ".join(ctx.existing_default_words[:40]) if ctx.existing_default_words else "(none)"
    kw = ", ".join(ctx.topic_keywords[:15]) if ctx.topic_keywords else "(none)"
    lines = [
        "## User request",
        ctx.user_prompt.strip(),
        "",
        "## Routing",
        f"retrieval_route: {ctx.retrieval_route or 'unknown'}",
        "",
        "## Languages",
        f"default_language (source): {ctx.default_language}",
        f"target_language: {ctx.target_language}",
        f"CEFR level: {ctx.level}",
        "",
        "## Topic interpretation",
        f"topic: {ctx.topic}",
        f"topic_keywords: {kw}",
        f"situation_label: {ctx.situation_label or '(none)'}",
        f"topic_reason: {ctx.topic_reason or '(none)'}",
        "",
        "## Words to avoid (already in user's boxes)",
        avoid,
        "",
        f"## Task",
        f"Generate up to {ctx.max_pairs} single-word pairs (default in {ctx.default_language}, target in {ctx.target_language}) "
        f"that fit the user's request and level. Skip any word you are not confident about.",
    ]
    return "\n".join(lines)
