"""
AI fallback vocabulary generator using OpenAI Responses API + structured JSON schema.

Produces validated single-word pairs. Does not persist to DB. Safe on failure (empty list + reason).
Driven by retrieval_route, prompt, topic metadata, level, languages — not by legacy "unsupported".
"""

from __future__ import annotations

import json
import logging
import os
import re
from dataclasses import dataclass, field
from typing import Any, List, Optional

from app.config import OPENAI_API_KEY
from app.config import openai_httpx_client
from app.prompts.word_generation import (
    SYSTEM_INSTRUCTIONS,
    WordGenerationContext,
    build_user_message,
)

logger = logging.getLogger(__name__)

MODEL = os.environ.get("OPENAI_WORD_GEN_MODEL", "gpt-4o-mini")
# Hard timeout for the API call (seconds)
# Interactive box flow: keep default low so POST /generate-boxes stays responsive (~18s cap per AI gen).
WORD_GEN_TIMEOUT = float(os.environ.get("WORD_GEN_TIMEOUT", "18"))
MIN_ITEM_CONFIDENCE = float(os.environ.get("WORD_GEN_MIN_CONFIDENCE", "0.72"))
MAX_WORD_LEN = 48

# Strict JSON schema for Responses API structured output
WORD_PAIRS_JSON_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "items": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "default": {"type": "string", "description": "Single word in source language"},
                    "target": {"type": "string", "description": "Single word in target language"},
                    "confidence": {
                        "type": "number",
                        "description": "Model confidence 0-1 for this pair",
                    },
                },
                "required": ["default", "target", "confidence"],
                "additionalProperties": False,
            },
        }
    },
    "required": ["items"],
    "additionalProperties": False,
}


@dataclass
class ValidatedWordPair:
    default: str
    target: str
    confidence: float
    source: str = "ai_generated"


@dataclass
class WordGenerationResult:
    """Result of AI word generation + validation."""

    validated: List[ValidatedWordPair] = field(default_factory=list)
    raw_count: int = 0
    validated_count: int = 0
    filtered_count: int = 0
    ai_failure_reason: Optional[str] = None
    ai_used: bool = True
    ai_candidate_count: int = 0
    ai_validated_count: int = 0

    def to_state_patch(self) -> dict[str, Any]:
        """Fields ready to merge into BoxWorkflowState (Prompt 3 integration)."""
        return {
            "ai_used": self.ai_used and len(self.validated) > 0,
            "ai_candidate_count": self.ai_candidate_count,
            "ai_validated_count": self.ai_validated_count,
            "ai_failure_reason": self.ai_failure_reason,
        }


def _is_single_token(s: str) -> bool:
    s = (s or "").strip()
    if not s:
        return False
    # one word: no internal whitespace; allow hyphenated compounds as single token for DE/ES
    parts = s.split()
    return len(parts) == 1 and len(s) <= MAX_WORD_LEN


def _looks_like_garbage(s: str) -> bool:
    if not s or len(s) > MAX_WORD_LEN:
        return True
    # reject obvious placeholders
    if re.match(r"^[\d\s\W]+$", s):
        return True
    if re.search(r"[<>{}[\]\\]|http|www\.|\.com", s, re.I):
        return True
    return False


def validate_and_filter_pairs(
    raw_items: List[dict[str, Any]],
    *,
    existing_pairs: set[tuple[str, str]],
    existing_defaults: set[str],
    min_confidence: float = MIN_ITEM_CONFIDENCE,
    max_output: int = 30,
) -> tuple[List[ValidatedWordPair], int, int]:
    """
    Returns (validated_list, raw_count, filtered_count).
    """
    raw_count = len(raw_items)
    seen_pairs: set[tuple[str, str]] = set(existing_pairs)
    seen_defaults = set(existing_defaults)
    out: List[ValidatedWordPair] = []
    filtered = 0

    for item in raw_items:
        if not isinstance(item, dict):
            filtered += 1
            continue
        d = str(item.get("default", "")).strip()
        t = str(item.get("target", "")).strip()
        try:
            conf = float(item.get("confidence", 0.0))
        except (TypeError, ValueError):
            conf = 0.0

        if not d or not t:
            filtered += 1
            continue
        if not _is_single_token(d) or not _is_single_token(t):
            filtered += 1
            continue
        if _looks_like_garbage(d) or _looks_like_garbage(t):
            filtered += 1
            continue
        if conf < min_confidence:
            filtered += 1
            continue
        dl, tl = d.lower(), t.lower()
        if (dl, tl) in seen_pairs:
            filtered += 1
            continue
        if dl in seen_defaults:
            filtered += 1
            continue
        seen_pairs.add((dl, tl))
        seen_defaults.add(dl)
        out.append(ValidatedWordPair(default=d, target=t, confidence=conf))
        if len(out) >= max_output:
            break

    return out, raw_count, filtered


def _parse_responses_output(response: Any) -> Optional[dict]:
    """Extract JSON object from Responses API output."""
    try:
        for block in getattr(response, "output", None) or []:
            if getattr(block, "type", None) != "message":
                continue
            for part in getattr(block, "content", None) or []:
                text = None
                if getattr(part, "type", None) == "output_text":
                    text = getattr(part, "text", None)
                if text:
                    return json.loads(text)
    except (json.JSONDecodeError, TypeError, AttributeError) as e:
        logger.warning("ai_word_generator.parse_output failed: %s", e)
    return None


def generate_word_pairs(ctx: WordGenerationContext, request_id: str = "") -> WordGenerationResult:
    """
    Call OpenAI Responses API with structured output; validate and return word pairs.

    On any failure: returns empty validated list and ai_failure_reason set; never raises.
    """
    result = WordGenerationResult()
    if not OPENAI_API_KEY or not str(OPENAI_API_KEY).strip():
        result.ai_failure_reason = "missing_api_key"
        result.ai_used = False
        return result

    user_msg = build_user_message(ctx)
    try:
        from openai import OpenAI

        client = OpenAI(
            api_key=OPENAI_API_KEY,
            timeout=WORD_GEN_TIMEOUT,
            http_client=openai_httpx_client(timeout=WORD_GEN_TIMEOUT),
        )
        resp = client.responses.create(
            model=MODEL,
            instructions=SYSTEM_INSTRUCTIONS,
            input=user_msg,
            text={
                "format": {
                    "type": "json_schema",
                    "name": "vocabulary_word_pairs",
                    "strict": True,
                    "schema": WORD_PAIRS_JSON_SCHEMA,
                }
            },
            temperature=0.35,
            max_output_tokens=4096,
        )
    except Exception as e:
        err = str(e).lower()
        if "timeout" in err or isinstance(e, TimeoutError):
            result.ai_failure_reason = "timeout"
        elif "rate" in err or "429" in err or "quota" in err:
            result.ai_failure_reason = "quota_or_rate_limit"
        elif "401" in err or "invalid" in err and "key" in err:
            result.ai_failure_reason = "api_key_invalid"
        else:
            result.ai_failure_reason = f"api_error:{type(e).__name__}"
        logger.warning("ai_word_generator request failed id=%s reason=%s", request_id, result.ai_failure_reason)
        return result

    data = _parse_responses_output(resp)
    if not data or not isinstance(data.get("items"), list):
        result.ai_failure_reason = "malformed_output"
        return result

    raw_items = data["items"]
    existing_pairs: set[tuple[str, str]] = {
        (a.strip().lower(), b.strip().lower()) for a, b in (ctx.existing_word_pairs or [])
    }
    existing_defaults: set[str] = {w.strip().lower() for w in ctx.existing_default_words if w and w.strip()}
    for a, b in existing_pairs:
        if a:
            existing_defaults.add(a)

    validated, raw_count, filtered = validate_and_filter_pairs(
        raw_items,
        existing_pairs=existing_pairs,
        existing_defaults=existing_defaults,
        max_output=ctx.max_pairs,
    )

    result.raw_count = raw_count
    result.ai_candidate_count = raw_count
    result.filtered_count = filtered
    result.validated = validated
    result.validated_count = len(validated)
    result.ai_validated_count = len(validated)
    if not validated and raw_count > 0:
        result.ai_failure_reason = result.ai_failure_reason or "all_items_filtered"
    elif not validated:
        result.ai_failure_reason = result.ai_failure_reason or "empty_model_output"

    logger.info(
        "ai_word_generator.done id=%s raw=%s validated=%s filtered=%s failure=%s",
        request_id,
        raw_count,
        len(validated),
        filtered,
        result.ai_failure_reason,
    )
    return result


def collect_existing_default_words_from_boxes(existing_boxes: List[dict]) -> List[str]:
    """Flatten default lemmas from existing_boxes for the prompt."""
    out: List[str] = []
    for box in existing_boxes or []:
        for w in box.get("words") or []:
            d = (w.get("default") or "").strip()
            if d:
                out.append(d)
    return out
