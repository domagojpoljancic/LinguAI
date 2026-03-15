"""
AI-based topic classification for natural prompts.

Maps free-form user prompts to the internal topic enum only. Used as fallback
when deterministic keyword matching returns general or low confidence.
Retrieval and word selection remain deterministic.
"""

from __future__ import annotations

import json
import logging
import re
from typing import Any

logger = logging.getLogger(__name__)

# Internal topic enum. AI must never invent topics outside this set.
ALLOWED_TOPICS = frozenset({
    "restaurant", "travel", "shopping", "business", "health", "dating", "daily", "general",
})

# Map common AI outputs / synonyms to allowed topic. Used when model returns non-enum value.
TOPIC_NORMALIZE_MAP = {
    "hospital": "health",
    "doctor": "health",
    "medical": "health",
    "medicine": "health",
    "pharmacy": "health",
    "pregnancy": "health",
    "labor": "health",
    "midwife": "health",
    "childbirth": "health",
    "airport": "travel",
    "flight": "travel",
    "food": "restaurant",
    "cafe": "restaurant",
    "dining": "restaurant",
    "store": "shopping",
    "market": "shopping",
    "office": "business",
    "work": "business",
    "meeting": "business",
}


def normalize_topic(topic: str | None) -> str:
    """
    Ensure topic is one of ALLOWED_TOPICS. If not, map via TOPIC_NORMALIZE_MAP or return "general".
    """
    if not topic or not isinstance(topic, str):
        return "general"
    raw = topic.strip().lower()
    if raw in ALLOWED_TOPICS:
        return raw
    if raw in TOPIC_NORMALIZE_MAP:
        return TOPIC_NORMALIZE_MAP[raw]
    # Substring match for common phrasing (e.g. "health and safety" -> health)
    for key, value in TOPIC_NORMALIZE_MAP.items():
        if key in raw:
            return value
    return "general"


def _get_llm():
    """Lazy LLM for classification only."""
    import os
    from langchain_openai import ChatOpenAI
    from app.config import OPENAI_REQUEST_TIMEOUT
    model = os.environ.get("OPENAI_MODEL", "gpt-4o-mini")
    return ChatOpenAI(
        model=model,
        request_timeout=OPENAI_REQUEST_TIMEOUT,
        api_key=os.environ.get("OPENAI_API_KEY"),
    )


CLASSIFICATION_SYSTEM = """You are a classifier that maps user prompts to a small fixed vocabulary topic set.

Allowed topics (return EXACTLY one of these):
restaurant
travel
shopping
business
health
dating
daily
general

Return ONLY valid JSON, no other text.
Schema:
{
  "topic": "<one of the allowed topics>",
  "confidence": <number between 0 and 1>,
  "reason": "<short explanation in one phrase>"
}

Examples:
- "words for labor with my wife" -> topic: health, confidence: 0.9, reason: labor and childbirth context
- "phrases for talking to a midwife" -> topic: health, confidence: 0.95
- "vocabulary for a medical emergency" -> topic: health, confidence: 0.95
- "small talk at work" -> topic: business, confidence: 0.85
"""


def classify_with_ai(prompt: str, request_id: str) -> dict[str, Any]:
    """
    Call LLM to classify prompt into one of ALLOWED_TOPICS.
    Returns {"topic": str, "confidence": float, "reason": str}.
    Topic is always normalized to allowed enum.
    """
    from langchain_core.messages import SystemMessage, HumanMessage

    result: dict[str, Any] = {
        "topic": "general",
        "confidence": 0.0,
        "reason": "",
    }
    if not (prompt or "").strip():
        return result

    user_content = f"Input prompt: {prompt.strip()}\n\nReturn JSON only:"
    logger.info(
        "ai_topic_classifier.request id=%s len=%d",
        request_id, len(prompt),
        extra={"request_id": request_id, "call_type": "topic_classification"},
    )
    try:
        llm = _get_llm()
        msg = llm.invoke([
            SystemMessage(content=CLASSIFICATION_SYSTEM),
            HumanMessage(content=user_content),
        ])
        raw = (msg.content or "").strip()
        # Extract JSON (allow markdown code block)
        json_str = raw
        if "```" in raw:
            parts = re.split(r"```(?:json)?\s*", raw)
            for p in parts:
                p = p.strip()
                if p.startswith("{") and "topic" in p:
                    json_str = p
                    break
        try:
            data = json.loads(json_str)
        except json.JSONDecodeError:
            # Try to find {...} in raw
            match = re.search(r"\{[^{}]*\"topic\"[^{}]*\}", raw)
            if match:
                try:
                    data = json.loads(match.group(0))
                except json.JSONDecodeError:
                    data = {}
            else:
                data = {}

        topic = (data.get("topic") or "").strip().lower()
        confidence = float(data.get("confidence", 0.0))
        if confidence < 0.0:
            confidence = 0.0
        if confidence > 1.0:
            confidence = 1.0
        reason = (data.get("reason") or "").strip() or ""

        result["topic"] = normalize_topic(topic)
        result["confidence"] = confidence
        result["reason"] = reason[:200] if reason else ""

        logger.info(
            "ai_topic_classifier.response id=%s topic=%s confidence=%s",
            request_id, result["topic"], result["confidence"],
            extra={"request_id": request_id, "topic": result["topic"], "confidence": result["confidence"]},
        )
        return result
    except Exception:
        logger.exception("ai_topic_classifier.error id=%s", request_id)
        result["topic"] = "general"
        result["confidence"] = 0.0
        result["reason"] = "classification failed"
        return result
