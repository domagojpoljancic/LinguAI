"""
Prompt builders for early request understanding (relevance + topic + routing hints).

This component must NOT generate any vocabulary words; it only returns structured
understanding to help downstream nodes.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import List, Optional


@dataclass(frozen=True)
class RequestUnderstandingContext:
    raw_prompt: str
    normalized_prompt: str
    default_language: str
    target_language: str
    explicit_cefr: Optional[str] = None


ALLOWED_TOPICS = [
    "restaurant",
    "travel",
    "shopping",
    "business",
    "health",
    "dating",
    "daily",
    "general",
    "unsupported",
]

ROUTE_HINTS = ["db_first", "ai_first", "mixed"]
CEFR_LEVELS = ["A1", "A2", "B1", "B2", "C1", "C2"]


SYSTEM_PROMPT = """You are a request understanding engine for a language-learning vocabulary app.

Goal: classify the user's prompt to structured request understanding so the app can later build
vocabulary boxes (DB and/or AI). You must NOT generate any vocabulary words.

Return ONLY strict JSON with exactly the schema keys below. No markdown, no extra text.

Schema:
{
  "is_relevant": boolean,
  "topic": string,                 // one of: restaurant, travel, shopping, business, health, dating, daily, general, unsupported
  "subtopic": string | null,      // optional more specific niche; null if none
  "situation_label": string | null, // short label describing the situation/topic for UX (e.g. "talking to a landlord")
  "topic_keywords": [string],     // keyword tokens for retrieval/ranking; empty list if none
  "route_hint": string,            // one of: db_first, ai_first, mixed
  "level_hint": string | null,   // CEFR only (A1/A2/B1/B2/C1/C2) or null
  "confidence": number,           // 0..1
  "reason": string                // short reason phrase
}

Relevance rules:
- Relevant if user wants vocabulary/words/phrases to learn or practice (even short topic nouns like "Basketball" or "Weather", or niche prompts like "Car parts words").
- Not relevant if greetings only or unrelated tasks (jokes, translations without word-list intent, etc.).

Topic rules:
- Use one of the allowed topics; for niche intents return "general" but fill situation_label/topic_keywords accurately.

Routing rules (db_first / ai_first / mixed):
- db_first: when the topic is one of the supported curated topics with high confidence (restaurant, travel, shopping, business, health, dating, daily).
- ai_first: for sports/weather/gym/landlord-like or broad niche intents that likely require AI to expand beyond the small DB seed.
- mixed: vague/general learning intent.

Level rules:
- If explicit CEFR appears in the prompt, set level_hint to that CEFR.
- Otherwise, you may guess a conservative CEFR for better downstream defaults, or set null if unsure.
""".strip()


def build_request_understanding_messages(ctx: RequestUnderstandingContext) -> List[object]:
    # Using "object" type here to avoid importing langchain message types.
    from langchain_core.messages import SystemMessage, HumanMessage

    explicit_cefr_text = ctx.explicit_cefr or None
    return [
        SystemMessage(content=SYSTEM_PROMPT),
        HumanMessage(
            content=(
                f"Default language: {ctx.default_language}\n"
                f"Target language: {ctx.target_language}\n"
                f"Explicit CEFR (if detected): {explicit_cefr_text}\n"
                f"Raw prompt: {ctx.raw_prompt}\n"
                f"Normalized prompt: {ctx.normalized_prompt}\n\n"
                f"Return strict JSON."
            )
        ),
    ]

