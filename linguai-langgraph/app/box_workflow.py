"""
Box-generation workflow nodes and routing.

Architecture:
- relevance_check (LLM)
- topic_identification (deterministic keyword extraction)
- level_resolution (explicit CEFR in prompt, else LLM infer from boxes/words/completion/topic; always produces a level)
- box_creation_placeholder (stub)
Words are nested under each box so level inference can use completion and vocabulary per box.
"""

import logging
import re

from langchain_core.messages import SystemMessage, HumanMessage

from app.state import BoxWorkflowState
from app.schemas import (
    STATUS_IRRELEVANT_REQUEST,
    STATUS_INSUFFICIENT_CONFIDENCE,
    STATUS_GENERATED_PLACEHOLDER,
)

logger = logging.getLogger(__name__)

CEFR_LEVELS = ("A1", "A2", "B1", "B2", "C1", "C2")
CEFR_PATTERN = re.compile(r"\b(A1|A2|B1|B2|C1|C2)\b", re.IGNORECASE)

# Topic keywords for deterministic extraction (expand as needed)
TOPIC_KEYWORDS = {
    "restaurant": ["restaurant", "food", "dining", "menu", "kitchen", "cooking", "recipe"],
    "travel": ["travel", "airport", "hotel", "vacation", "trip", "flight", "directions", "transport"],
    "business": ["business", "meeting", "office", "work", "email", "presentation", "negotiation"],
    "dating": ["dating", "romance", "relationship", "love", "flirting"],
    "shopping": ["shopping", "store", "market", "buy", "price", "clothes"],
    "health": ["health", "doctor", "pharmacy", "hospital", "medicine", "symptoms"],
    "daily": ["daily", "routine", "everyday", "greetings", "small talk", "basics"],
}


def _get_llm():
    """Lazy LLM so graph can be built without OPENAI_API_KEY at import time."""
    from langchain_openai import ChatOpenAI
    import os
    model = os.environ.get("OPENAI_MODEL", "gpt-4o-mini")
    return ChatOpenAI(model=model, request_timeout=30, api_key=os.environ.get("OPENAI_API_KEY"))


# ---- Relevance (LLM) ----

RELEVANCE_SYSTEM = """You judge whether a user prompt is relevant for generating a vocabulary/word list to learn in a language-learning app.
Relevant: prompts about topics, themes, or requests for words (e.g. "kitchen words in Spanish", "B1 travel vocabulary").
Not relevant: greetings, off-topic questions, or requests that are not about learning vocabulary (e.g. "what's the weather", "tell me a joke").
Reply with exactly two lines:
Line 1: RELEVANT or NOT_RELEVANT
Line 2: If NOT_RELEVANT, one short friendly sentence the app can show the user (e.g. "I can only help with vocabulary and language learning."). If RELEVANT, leave line 2 empty or a dash."""


def relevance_check(state: BoxWorkflowState) -> dict:
    """
    Classify whether the prompt is relevant for vocabulary-box generation.
    Single LLM call; returns is_relevant, relevance_user_message, and status if irrelevant.
    """
    request_id = state.get("request_id", "")
    prompt = (state.get("prompt") or "").strip() or " "
    try:
        msg = _get_llm().invoke([
            SystemMessage(content=RELEVANCE_SYSTEM),
            HumanMessage(content=prompt),
        ])
        text = (msg.content or "").strip().upper()
        is_relevant = "NOT_RELEVANT" not in text.split("\n")[0]
        user_message = ""
        if not is_relevant:
            lines = (msg.content or "").strip().split("\n")
            if len(lines) > 1 and lines[1].strip() and lines[1].strip() != "-":
                user_message = lines[1].strip()
            else:
                user_message = "I can only help with vocabulary and language learning."
        logger.info(
            "relevance_check request_id=%s result=%s",
            request_id, "relevant" if is_relevant else "not_relevant",
            extra={"request_id": request_id, "relevance_result": "relevant" if is_relevant else "not_relevant"},
        )
        return {
            "is_relevant": is_relevant,
            "relevance_user_message": user_message,
            "status": STATUS_IRRELEVANT_REQUEST if not is_relevant else "",
            "user_message": user_message if not is_relevant else "",
        }
    except Exception as e:
        logger.warning("relevance_check request_id=%s error=%s", request_id, e, exc_info=True)
        return {
            "is_relevant": False,
            "relevance_user_message": "Something went wrong. Please try again.",
            "status": STATUS_IRRELEVANT_REQUEST,
            "user_message": "Something went wrong. Please try again.",
        }


# ---- Level resolution (always produces a level: explicit or inferred; never ends flow) ----

# Safe default when inference fails or output is invalid. Prefer lower level.
DEFAULT_CEFR_WHEN_UNKNOWN = "A2"

LEVEL_INFERENCE_SYSTEM = """You infer the learner's CEFR level (A1, A2, B1, B2, C1, C2) from their request and progress.

You are given:
- User request (topic or theme they asked for)
- Their existing boxes: name, completion percentage, and sample of words in each box

Rules:
- Reply with exactly one level: A1, A2, B1, B2, C1, or C2. Nothing else.
- When uncertain between two levels, prefer the LOWER level (e.g. choose A2 over B1). It is safer to suggest slightly easier vocabulary.
- Consider: how many boxes, completion rates, which words they already have, and the topic (e.g. "basics" vs "advanced").
"""


def _parse_cefr_from_prompt(prompt: str) -> str | None:
    """Return explicit CEFR level from prompt if present. Deterministic."""
    if not prompt:
        return None
    m = CEFR_PATTERN.search(prompt)
    return m.group(1).upper() if m else None


def _build_level_inference_context(state: BoxWorkflowState) -> str:
    """Build structured context for LLM: boxes, completion, words sample, topic."""
    existing_boxes = state.get("existing_boxes") or []
    topic = (state.get("topic") or "").strip() or "general"
    parts = [f"User request / topic: {topic}"]
    if not existing_boxes:
        parts.append("Existing boxes: none")
        return "\n".join(parts)
    # Prefer high-completion boxes first
    sorted_boxes = sorted(
        existing_boxes,
        key=lambda b: float(b.get("completionPercent") or 0),
        reverse=True,
    )
    for i, b in enumerate(sorted_boxes[:10]):
        name = b.get("boxName") or b.get("boxId") or f"box_{i}"
        pct = b.get("completionPercent")
        pct_str = f"{float(pct):.0f}%" if pct is not None else "?"
        words = b.get("words") or []
        sample = " ".join((w.get("default") or w.get("target") or "") for w in words[:10])
        if words:
            sample = sample[:80] + ("..." if len(sample) > 80 else "")
        else:
            sample = "(no words)"
        parts.append(f"Box: {name} | completion: {pct_str} | words sample: {sample}")
    return "\n".join(parts)


def _infer_level_with_llm(state: BoxWorkflowState) -> str:
    """
    Infer CEFR from boxes/words/completion/topic via OpenAI. Returns valid CEFR.
    On failure or invalid output returns DEFAULT_CEFR_WHEN_UNKNOWN (bias lower).
    """
    prompt = state.get("prompt") or ""
    existing_boxes = state.get("existing_boxes") or []
    context = _build_level_inference_context(state)
    try:
        llm = _get_llm()
        msg = llm.invoke([
            SystemMessage(content=LEVEL_INFERENCE_SYSTEM),
            HumanMessage(content=context),
        ])
        text = (msg.content or "").strip().upper()
        for lvl in CEFR_LEVELS:
            if lvl in text:
                return lvl
    except Exception as e:
        logger.warning("level_inference_llm failed request_id=%s error=%s", state.get("request_id", ""), e)
    return DEFAULT_CEFR_WHEN_UNKNOWN


def level_resolution(state: BoxWorkflowState) -> dict:
    """
    Always resolve a CEFR level: explicit in prompt first, else infer via LLM from boxes/words/completion/topic.
    Never ends the flow; fallback to A2 when inference fails. Sets level_source to "explicit" or "inferred".
    """
    request_id = state.get("request_id", "")
    prompt = state.get("prompt") or ""
    existing_boxes = state.get("existing_boxes") or []

    level = _parse_cefr_from_prompt(prompt)
    source = "explicit" if level else "inferred"

    if level:
        logger.info(
            "level_resolution request_id=%s level=%s source=explicit explicit_found=true",
            request_id, level,
            extra={"request_id": request_id, "level": level, "level_source": "explicit", "explicit_found": True},
        )
        return {"level": level, "level_source": source, "status": ""}

    level = _infer_level_with_llm(state)
    logger.info(
        "level_resolution request_id=%s level=%s source=inferred explicit_found=false inferred_used=true",
        request_id, level,
        extra={"request_id": request_id, "level": level, "level_source": "inferred", "explicit_found": False, "inferred_used": True},
    )
    return {"level": level, "level_source": source, "status": ""}


# ---- Topic identification ----

def _identify_topic_deterministic(prompt: str) -> str:
    """
    Extract a single topic label from prompt using keyword matching.
    Returns a short label suitable for box name/theme (e.g. "restaurant vocabulary").
    """
    if not prompt:
        return "general vocabulary"
    lower = prompt.lower()
    for label, keywords in TOPIC_KEYWORDS.items():
        if any(kw in lower for kw in keywords):
            return f"{label} vocabulary"
    # Fallback: first few significant words or "general"
    words = [w for w in re.split(r"\W+", lower) if len(w) > 2][:3]
    if words:
        return " ".join(words) + " vocabulary"
    return "general vocabulary"


def topic_identification(state: BoxWorkflowState) -> dict:
    """
    Identify the topic/theme for the box from the prompt.
    Deterministic keyword extraction; state holds prompt so box-creation can use topic.
    """
    request_id = state.get("request_id", "")
    prompt = state.get("prompt") or ""
    topic = _identify_topic_deterministic(prompt)
    logger.info(
        "topic_identification request_id=%s topic=%s",
        request_id, topic,
        extra={"request_id": request_id, "topic": topic},
    )
    return {"topic": topic}


# ---- Box creation placeholder ----

def box_creation_placeholder(state: BoxWorkflowState) -> dict:
    """Placeholder for box generation. No real generation yet; returns stub outcome."""
    request_id = state.get("request_id", "")
    logger.info(
        "box_creation_placeholder request_id=%s reached",
        request_id,
        extra={"request_id": request_id, "reached_box_creation": True},
    )
    return {
        "status": STATUS_GENERATED_PLACEHOLDER,
        "boxes": [],
        "user_message": "Ready to generate (placeholder).",
        "reached_box_creation": True,
    }


# ---- Routers for conditional edges ----

def route_after_relevance(state: BoxWorkflowState) -> str:
    """If not relevant, end; else go to topic_identification (then level_resolution, then box_creation)."""
    from langgraph.graph import END
    if state.get("is_relevant") is True:
        return "topic_identification"
    return END
