"""
Early structured request understanding:
- relevance / topic / niche signals
- situation label + topic keywords
- route hint for downstream DB/AI retrieval

This node must NOT generate any vocabulary words.
"""

from __future__ import annotations

import difflib
import json
import logging
import re
from typing import Any, Dict, List, Optional, Tuple

from pydantic import BaseModel, Field, ValidationError, field_validator

from app.config import OPENAI_API_KEY, OPENAI_MODEL, OPENAI_REQUEST_TIMEOUT, openai_httpx_client
from app.prompts.request_understanding import (
    ALLOWED_TOPICS,
    CEFR_LEVELS,
    RequestUnderstandingContext,
    ROUTE_HINTS,
    build_request_understanding_messages,
)
from app.schemas import STATUS_IRRELEVANT_REQUEST
from app.state import BoxWorkflowState

logger = logging.getLogger(__name__)


# ---------------------------
# Normalization pre-pass
# ---------------------------

try:
    # Reuse existing typo normalization from the workflow module.
    from app.box_workflow import _normalize_topic_typos as _workflow_normalize_typos
except Exception:  # pragma: no cover
    _workflow_normalize_typos = None


def _collapse_ws(s: str) -> str:
    return re.sub(r"\s+", " ", (s or "").strip())


CEFR_PATTERN = re.compile(r"\b(A1|A2|B1|B2|C1|C2)\b", re.IGNORECASE)


def _parse_explicit_cefr(prompt: str) -> Optional[str]:
    m = CEFR_PATTERN.search(prompt or "")
    return m.group(1).upper() if m else None


def normalize_for_understanding(prompt: str) -> Tuple[str, str, Optional[str]]:
    """
    Deterministic pre-pass:
    - trim + normalize whitespace
    - apply existing typo normalization (if available)
    - extract explicit CEFR if obvious
    """
    raw = prompt or ""
    raw_norm = _collapse_ws(raw)

    normalized = raw_norm.lower()
    if _workflow_normalize_typos is not None:
        try:
            normalized = _workflow_normalize_typos(raw_norm)
        except Exception:
            normalized = raw_norm.lower()

    explicit = _parse_explicit_cefr(raw_norm)
    return raw_norm, normalized, explicit


def _heuristic_route_hint(normalized_prompt: str) -> str:
    """
    Deterministic route hint aligned with existing decide_retrieval_route heuristics.

    This is only a stabilizer so the early AI understanding doesn't drift from
    current DB/AI routing behavior.
    """
    p = (normalized_prompt or "").lower()

    supported_tokens = [
        "restaurant",
        "travel",
        "shopping",
        "business",
        "health",
        "dating",
        "daily",
        "office",
        "market",
        "doctor",
        "hospital",
        "pharmacy",
    ]
    sports_words = ["football", "soccer", "basketball", "tennis", "sport", "gym", "fitness"]
    landlord_words = ["landlord", "rent", "tenant", "lease"]
    weather_words = [
        "weather",
        "climate",
        "rain",
        "snow",
        "storm",
        "temperature",
        "forecast",
        "cloudy",
        "sunny",
        "wind",
        "humid",
        "drizzle",
    ]
    niche_vocab = sports_words + landlord_words + weather_words

    if any(t in p for t in supported_tokens):
        return "db_first"
    if any(t in p for t in niche_vocab):
        return "ai_first"
    return "mixed"


# ---------------------------
# Strict output schema
# ---------------------------


class RequestUnderstandingResult(BaseModel):
    is_relevant: bool
    topic: str
    subtopic: Optional[str] = None
    situation_label: Optional[str] = None
    topic_keywords: List[str] = Field(default_factory=list)
    route_hint: str
    level_hint: Optional[str] = None
    confidence: float
    reason: str

    @field_validator("topic")
    @classmethod
    def _validate_topic(cls, v: str) -> str:
        vv = (v or "").strip().lower()
        if vv not in ALLOWED_TOPICS:
            # Defensive: keep behavior conservative.
            return "general"
        return vv

    @field_validator("route_hint")
    @classmethod
    def _validate_route(cls, v: str) -> str:
        vv = (v or "").strip().lower()
        if vv not in ROUTE_HINTS:
            return "mixed"
        return vv

    @field_validator("level_hint")
    @classmethod
    def _validate_level_hint(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return None
        vv = (v or "").strip().upper()
        if vv in CEFR_LEVELS:
            return vv
        return None

    @field_validator("confidence")
    @classmethod
    def _validate_conf(cls, v: float) -> float:
        try:
            f = float(v)
        except Exception:
            return 0.0
        return max(0.0, min(1.0, f))

    @field_validator("topic_keywords")
    @classmethod
    def _clean_keywords(cls, v: List[str]) -> List[str]:
        out: List[str] = []
        for x in v or []:
            if not isinstance(x, str):
                continue
            s = x.strip().lower()
            if not s:
                continue
            out.append(s)
        # cap to keep downstream stable
        return out[:15]


IRRELEVANT_FALLBACK_MESSAGES = [
    "I can help build vocabulary boxes — try a topic, level, or learning goal.",
    "That doesn't look like a vocabulary-box request. Try something like travel, dating, or business meetings.",
    "I'm not sure how to turn that into a vocabulary box. Try asking for words by topic or level.",
]


def _irrelevant_fallback_message(request_id: str) -> str:
    h = hash(request_id or "") % len(IRRELEVANT_FALLBACK_MESSAGES)
    return IRRELEVANT_FALLBACK_MESSAGES[h]


# ---------------------------
# Model call wrapper
# ---------------------------


def _get_request_understanding_llm(*, bypass_proxy: bool = False):
    from langchain_openai import ChatOpenAI

    # openai_httpx_client already applies the proxy bypass heuristic.
    # When bypass_proxy=True we force trust_env=False to avoid broken proxy env vars.
    http_client = openai_httpx_client(timeout=None)
    if bypass_proxy:
        import httpx

        http_client = httpx.Client(timeout=None, trust_env=False)

    return ChatOpenAI(
        model=OPENAI_MODEL,
        request_timeout=OPENAI_REQUEST_TIMEOUT,
        api_key=OPENAI_API_KEY,
        http_client=http_client,
    )


def _parse_strict_json(raw: str) -> Dict[str, Any]:
    """
    Parse model JSON robustly (strip code fences if any).
    """
    text = (raw or "").strip()
    if not text:
        return {}
    if "```" in text:
        parts = re.split(r"```(?:json)?\s*", text)
        for p in parts:
            p = p.strip()
            if p.startswith("{") and "confidence" in p:
                text = p
                break
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        # Best-effort extract first JSON object.
        m = re.search(r"\{[^{}]*\"is_relevant\"[^{}]*\}", text)
        if not m:
            return {}
        try:
            return json.loads(m.group(0))
        except Exception:
            return {}


def _call_llm_for_understanding(
    ctx: RequestUnderstandingContext,
    request_id: str,
) -> RequestUnderstandingResult:
    messages = build_request_understanding_messages(ctx)

    # Keep logging minimal but useful for debugging.
    logger.info(
        "request_understanding.request id=%s len=%d",
        request_id,
        len(ctx.raw_prompt),
        extra={"request_id": request_id, "call_type": "request_understanding"},
    )

    try:
        llm = _get_request_understanding_llm()
        msg = llm.invoke(messages)
        raw = (msg.content or "").strip()
    except Exception:
        # One retry: force trust_env=False for OpenAI calls (resilience).
        logger.exception("request_understanding.openai_first_failed id=%s", request_id)
        llm = _get_request_understanding_llm(bypass_proxy=True)
        msg = llm.invoke(messages)
        raw = (msg.content or "").strip()

    data = _parse_strict_json(raw)
    if not data:
        raise ValueError("request_understanding: empty or unparseable JSON")

    return RequestUnderstandingResult.model_validate(data)


# ---------------------------
# LangGraph node
# ---------------------------


UNDERSTANDING_APPLY_CONFIDENCE = 0.65
RELEVANCE_END_CONFIDENCE = 0.75
RELEVANCE_VALIDATE_CONFIDENCE = 0.60


def request_understanding(state: BoxWorkflowState) -> dict:
    """
    Early structured understanding node.

    Produces:
    - is_relevant (+ status/userMessage when not relevant)
    - topic, subtopic, situation_label, topic_keywords
    - retrieval_route based on route_hint (route_hint)
    - understanding_confidence + reason
    """
    request_id = state.get("request_id", "")
    raw_prompt = (state.get("prompt") or "").strip()

    if not raw_prompt:
        return {
            "is_relevant": False,
            "status": STATUS_IRRELEVANT_REQUEST,
            "relevance_user_message": _irrelevant_fallback_message(request_id),
            "user_message": _irrelevant_fallback_message(request_id),
            "topic": "general",
            "topic_keywords": [],
            "situation_label": None,
            "retrieval_route": "mixed",
            "retrieval_route_reason": "empty prompt",
            "understanding_confidence": 0.0,
            "understanding_reason": "empty prompt",
            "subtopic": None,
            "level_hint": None,
            "_request_understanding_applied": False,
        }

    raw_norm, normalized, explicit_cefr = normalize_for_understanding(raw_prompt)

    default_language = state.get("default_language") or "en"
    target_language = state.get("target_language") or "de"
    route_hint_prepass = _heuristic_route_hint(normalized)

    ctx = RequestUnderstandingContext(
        raw_prompt=raw_norm,
        normalized_prompt=normalized,
        default_language=default_language,
        target_language=target_language,
        explicit_cefr=explicit_cefr,
    )

    try:
        parsed = _call_llm_for_understanding(ctx=ctx, request_id=request_id)
    except Exception:
        logger.exception("request_understanding.error id=%s", request_id)
        is_rel = False
        status_msg = _irrelevant_fallback_message(request_id)
        return {
            "is_relevant": is_rel,
            "status": STATUS_IRRELEVANT_REQUEST,
            "relevance_user_message": status_msg,
            "user_message": status_msg,
            "topic": "general",
            "subtopic": None,
            "situation_label": None,
            "topic_keywords": [],
            "retrieval_route": route_hint_prepass,
            "retrieval_route_reason": "request understanding failed",
            "understanding_confidence": 0.0,
            "understanding_reason": "request understanding failed",
            "level_hint": explicit_cefr,
            "_request_understanding_applied": False,
        }

    # If it's relevant we apply the parsed structured fields.
    applied = bool(parsed.is_relevant) and parsed.confidence >= UNDERSTANDING_APPLY_CONFIDENCE

    status_msg = ""
    relevance_user_message = ""
    user_message = ""
    status = ""
    if not parsed.is_relevant:
        status = STATUS_IRRELEVANT_REQUEST
        status_msg = _irrelevant_fallback_message(request_id)
        relevance_user_message = status_msg
        user_message = status_msg

    return {
        "is_relevant": parsed.is_relevant,
        "status": status,
        "relevance_user_message": relevance_user_message,
        "user_message": user_message,
        "topic": parsed.topic,
        "subtopic": parsed.subtopic,
        "situation_label": parsed.situation_label,
        "topic_keywords": parsed.topic_keywords,
        "retrieval_route": route_hint_prepass,
        "retrieval_route_reason": (
            f"route_hint_prepass={route_hint_prepass}; {parsed.reason[:120] if parsed.reason else ''}"
        )[:200],
        "retrieval_route_confidence": parsed.confidence,
        "topic_source": "ai",
        "topic_confidence": parsed.confidence,
        "topic_reason": parsed.reason[:200] if parsed.reason else "",
        "understanding_confidence": parsed.confidence,
        "understanding_reason": parsed.reason[:200] if parsed.reason else "",
        "level_hint": parsed.level_hint or explicit_cefr,
        "_request_understanding_applied": applied,
    }


def route_after_request_understanding(state: BoxWorkflowState) -> str:
    """
    Routing for early node:
    - relevant -> topic_identification
    - irrelevant:
        • if understanding confidence is high -> END
        • else -> relevance_check fallback
    """
    from langgraph.graph import END

    conf = float(state.get("understanding_confidence") or 0.0)

    if state.get("is_relevant") is True:
        # Low-confidence "relevant" gets re-validated by the legacy relevance_check
        # to preserve backward compatibility.
        if conf >= RELEVANCE_VALIDATE_CONFIDENCE:
            return "topic_identification"
        return "relevance_check"

    # Low-confidence "not relevant" should not hard-stop the pipeline.
    if conf >= RELEVANCE_END_CONFIDENCE:
        return END
    return "relevance_check"

