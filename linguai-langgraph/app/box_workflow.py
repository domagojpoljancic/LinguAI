"""
Box-generation workflow nodes and routing.

Architecture:
- relevance_check (LLM)
- level_resolution (explicit CEFR → infer from boxes with nested words → optional LLM)
- topic_identification (deterministic keyword extraction)
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


# ---- Level resolution (explicit first, then inference; only stop when all fail) ----

def _parse_cefr_from_prompt(prompt: str) -> str | None:
    """Return explicit CEFR level from prompt if present. Deterministic."""
    if not prompt:
        return None
    m = CEFR_PATTERN.search(prompt)
    return m.group(1).upper() if m else None


def _infer_level_from_boxes(existing_boxes: list) -> str | None:
    """
    Infer CEFR from boxes with nested words. Uses completion and vocabulary exposure:
    - Highly completed boxes and their word counts signal stronger exposure.
    - Total words across boxes and words in high-completion boxes refine the estimate.
    No boxes or no usable data -> return None.
    """
    if not existing_boxes:
        return None
    total_words = 0
    weighted_words = 0.0  # words weighted by box completion (0-1)
    percents = []
    for b in existing_boxes:
        p = b.get("completionPercent") if isinstance(b, dict) else getattr(b, "completionPercent", None)
        p_val = float(p) if p is not None else 0.0
        percents.append(p_val)
        words_in_box = b.get("words") if isinstance(b, dict) else getattr(b, "words", None)
        n_w = len(words_in_box) if words_in_box else 0
        total_words += n_w
        weighted_words += n_w * (p_val / 100.0)
    if not percents:
        return None
    avg = sum(percents) / len(percents)
    n_boxes = len(existing_boxes)
    # Vocabulary exposure: words in boxes with completion >= 50% (learner has "seen" these)
    high_completion_words = sum(
        len(b.get("words") or []) for b in existing_boxes
        if (b.get("completionPercent") or 0) >= 50.0
    )
    # Heuristic: completion + box count + exposure (total and high-completion-weighted)
    if avg >= 70 and n_boxes >= 3 and high_completion_words >= 20:
        return "B2"
    if avg >= 50 and n_boxes >= 2 and (total_words >= 15 or high_completion_words >= 10):
        return "B1"
    if avg >= 25 or n_boxes >= 1 or total_words >= 5:
        return "A2"
    if total_words >= 1 or n_boxes >= 1:
        return "A1"
    return None


def _infer_level_from_boxes_llm(prompt: str, existing_boxes: list) -> str | None:
    """
    Optional LLM-based level inference from prompt + box-linked words (e.g. from high-completion boxes).
    Used when LEVEL_INFERENCE_USE_LLM=true. Returns CEFR or None.
    """
    try:
        from app.config import LEVEL_INFERENCE_USE_LLM
        if not LEVEL_INFERENCE_USE_LLM:
            return None
    except Exception:
        return None
    # Build word sample from boxes (prefer high-completion boxes)
    sorted_boxes = sorted(
        existing_boxes,
        key=lambda b: float(b.get("completionPercent") or 0),
        reverse=True,
    )
    word_samples = []
    for b in sorted_boxes:
        words = b.get("words") or []
        for w in words[:15]:
            word_samples.append(w.get("default") or w.get("target") or "")
        if len(word_samples) >= 30:
            break
    words_preview = " ".join(word_samples[:30]) if word_samples else "none"
    try:
        llm = _get_llm()
        msg = llm.invoke([
            SystemMessage(content="From the user request and their existing vocabulary (words from their boxes), choose one CEFR level: A1, A2, B1, B2, C1, or C2. Reply with only the level, e.g. A2."),
            HumanMessage(content=f"User request: {prompt}\nExisting vocabulary (sample): {words_preview}"),
        ])
        text = (msg.content or "").strip().upper()
        for lvl in CEFR_LEVELS:
            if lvl in text:
                return lvl
    except Exception as e:
        logger.debug("level_inference_llm failed: %s", e)
    return None


def level_resolution(state: BoxWorkflowState) -> dict:
    """
    Resolve CEFR: explicit in prompt first, then infer from boxes (completion + words per box), then optional LLM.
    Sets level_source to "explicit" or "inferred". Words are taken from existing_boxes[].words.
    """
    request_id = state.get("request_id", "")
    prompt = state.get("prompt") or ""
    existing_boxes = state.get("existing_boxes") or []

    level = _parse_cefr_from_prompt(prompt)
    source = "explicit" if level else ""

    if not level:
        level = _infer_level_from_boxes(existing_boxes)
        if level:
            source = "inferred"
    if not level:
        level = _infer_level_from_boxes_llm(prompt, existing_boxes)
        if level:
            source = "inferred"

    if level:
        logger.info(
            "level_resolution request_id=%s level=%s source=%s",
            request_id, level, source,
            extra={"request_id": request_id, "level": level, "level_source": source},
        )
        return {"level": level, "level_source": source, "status": ""}
    logger.info(
        "level_resolution request_id=%s no_level_after_inference",
        request_id,
        extra={"request_id": request_id, "level": None, "level_source": None},
    )
    return {
        "level": "",
        "level_source": "",
        "status": STATUS_INSUFFICIENT_CONFIDENCE,
        "user_message": "I couldn't determine your level. Try mentioning it (e.g. A1, B2) or add some boxes with progress.",
    }


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
    """If not relevant, end; else go to level resolution."""
    from langgraph.graph import END
    if state.get("is_relevant") is True:
        return "level_resolution"
    return END


def route_after_level(state: BoxWorkflowState) -> str:
    """
    If no level resolved after explicit + inference, end.
    Otherwise go to topic_identification (then box creation).
    """
    from langgraph.graph import END
    level = state.get("level") or ""
    if level.strip() in CEFR_LEVELS:
        return "topic_identification"
    return END
