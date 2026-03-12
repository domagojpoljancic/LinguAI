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
import os
import re
from typing import List, Tuple

from langchain_core.messages import SystemMessage, HumanMessage

from app.config import OPENAI_REQUEST_TIMEOUT, TOPIC_USE_LLM_FALLBACK
from app.state import BoxWorkflowState
from app.schemas import (
    STATUS_IRRELEVANT_REQUEST,
    STATUS_INSUFFICIENT_CONFIDENCE,
    STATUS_GENERATED_PLACEHOLDER,
)
from app.vocab_store import retrieve_candidates

logger = logging.getLogger(__name__)

CEFR_LEVELS = ("A1", "A2", "B1", "B2", "C1", "C2")
CEFR_PATTERN = re.compile(r"\b(A1|A2|B1|B2|C1|C2)\b", re.IGNORECASE)

# Topic keywords for deterministic extraction (expand as needed)
TOPIC_KEYWORDS = {
    "restaurant": ["restaurant", "food", "dining", "menu", "kitchen", "cooking", "recipe", "cafe", "bar"],
    "travel": ["travel", "airport", "hotel", "vacation", "trip", "flight", "directions", "transport"],
    "business": ["business", "meeting", "office", "work", "email", "presentation", "negotiation"],
    "dating": ["dating", "romance", "relationship", "love", "flirting"],
    "shopping": ["shopping", "store", "market", "buy", "price", "clothes"],
    "health": ["health", "doctor", "pharmacy", "hospital", "medicine", "symptoms"],
    "daily": ["daily", "routine", "everyday", "greetings", "small talk", "basics"],
}

# Short, product-quality box names (2–3 words). Avoid repetitive "X vocabulary".
TOPIC_TO_BOX_NAME = {
    "restaurant": "Street Eats",
    "travel": "City Break",
    "business": "Office Chat",
    "dating": "Date Night",
    "shopping": "Shop Talk",
    "health": "Health Basics",
    "daily": "Daily Basics",
}
DEFAULT_BOX_NAME = "Quick Start"


def _get_llm():
    """Lazy LLM so graph can be built without OPENAI_API_KEY at import time. Uses OPENAI_REQUEST_TIMEOUT."""
    from langchain_openai import ChatOpenAI
    model = os.environ.get("OPENAI_MODEL", "gpt-4o-mini")
    return ChatOpenAI(
        model=model,
        request_timeout=OPENAI_REQUEST_TIMEOUT,
        api_key=os.environ.get("OPENAI_API_KEY"),
    )


# ---- Relevance (LLM) ----

# Rotating fallbacks for irrelevant requests (natural, short, app-friendly).
IRRELEVANT_FALLBACK_MESSAGES = [
    "I can help build vocabulary boxes — try a topic, level, or learning goal.",
    "That doesn't look like a vocabulary-box request. Try something like travel, dating, or business meetings.",
    "I'm not sure how to turn that into a vocabulary box. Try asking for words by topic or level.",
]


def _irrelevant_fallback_message(request_id: str) -> str:
    """Pick a consistent fallback message for irrelevant requests (no LLM)."""
    h = hash(request_id or "") % len(IRRELEVANT_FALLBACK_MESSAGES)
    return IRRELEVANT_FALLBACK_MESSAGES[h]


RELEVANCE_SYSTEM = """You judge whether a user prompt is relevant for generating a vocabulary/word list to learn in a language-learning app.

Relevant: any request that is about getting, reviewing, or practicing vocabulary/words for learning. Include:
- Direct requests: "give me kitchen words", "B1 travel vocabulary", "words for restaurants"
- Indirect or conversational: "I'd like to review vocabulary and add harder words", "help me with words for my trip", "I need something for business meetings"
- Practice/review: "expand my word list", "more words for dating", "vocabulary for my level"

Not relevant: greetings only, off-topic questions, or requests that are not about learning vocabulary (e.g. "what's the weather", "tell me a joke", "translate this sentence" without asking for a word list).

Reply with exactly two lines:
Line 1: RELEVANT or NOT_RELEVANT
Line 2: If NOT_RELEVANT, one short natural sentence the app can show (e.g. "I can help build vocabulary boxes — try asking for a topic, level, or learning goal."). If RELEVANT, leave line 2 empty or a dash."""


def _log_openai_usage(msg, request_id: str, call_type: str) -> None:
    """Log token usage from OpenAI response if present. Safe summary only."""
    meta = getattr(msg, "response_metadata", None) or {}
    usage = meta.get("token_usage") or meta.get("usage")
    if usage:
        logger.info(
            "openai.usage %s id=%s %s",
            call_type, request_id, usage,
            extra={"request_id": request_id, "call_type": call_type, "usage": usage},
        )


def relevance_check(state: BoxWorkflowState) -> dict:
    """
    Classify whether the prompt is relevant for vocabulary-box generation.
    Single LLM call; returns is_relevant, relevance_user_message, and status if irrelevant.
    """
    request_id = state.get("request_id", "")
    prompt = (state.get("prompt") or "").strip() or " "
    logger.info("relevance_check.start id=%s", request_id, extra={"request_id": request_id})
    model = os.environ.get("OPENAI_MODEL", "gpt-4o-mini")
    logger.info(
        "openai.request relevance_check id=%s model=%s len=%d",
        request_id, model, len(prompt),
        extra={"request_id": request_id, "call_type": "relevance_check", "model": model, "prompt_length": len(prompt)},
    )
    try:
        msg = _get_llm().invoke([
            SystemMessage(content=RELEVANCE_SYSTEM),
            HumanMessage(content=prompt),
        ])
        raw = (msg.content or "").strip()
        text = raw.upper()
        # Robust classification: look for NOT_RELEVANT or RELEVANT in first segment (avoid brittle line assumptions).
        first_chunk = (text.split("\n")[0] if "\n" in text else text)[:200]
        if "NOT_RELEVANT" in first_chunk:
            is_relevant = False
        elif "RELEVANT" in first_chunk:
            is_relevant = True
        else:
            # Unparseable or malformed: fail safe to irrelevant with good user message.
            is_relevant = False
            logger.warning("relevance_check id=%s unparseable response, treating as irrelevant", request_id)
        user_message = ""
        if not is_relevant:
            lines = [s.strip() for s in raw.split("\n") if s.strip()]
            # Second line often contains the user-facing message; use if it looks like a sentence.
            candidate = (lines[1] if len(lines) > 1 else "").strip()
            if candidate and candidate not in ("-", "RELEVANT", "NOT_RELEVANT") and len(candidate) > 10:
                user_message = candidate
            else:
                user_message = _irrelevant_fallback_message(request_id)
        response_preview = (text[:80] + "..") if len(text) > 80 else text
        logger.info(
            "openai.response relevance_check id=%s ok result=%s prev=%s",
            request_id, "relevant" if is_relevant else "not_relevant", response_preview,
            extra={"request_id": request_id, "call_type": "relevance_check", "result": "relevant" if is_relevant else "not_relevant"},
        )
        _log_openai_usage(msg, request_id, "relevance_check")
        logger.info(
            "relevance_check.done id=%s result=%s",
            request_id, "relevant" if is_relevant else "not_relevant",
            extra={"request_id": request_id, "relevance_result": "relevant" if is_relevant else "not_relevant"},
        )
        return {
            "is_relevant": is_relevant,
            "relevance_user_message": user_message,
            "status": STATUS_IRRELEVANT_REQUEST if not is_relevant else "",
            "user_message": user_message if not is_relevant else "",
        }
    except Exception:
        logger.exception("relevance_check.error id=%s openai_call_failed", request_id)
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
    prompt = (state.get("prompt") or "").strip()
    topic = (state.get("topic") or "").strip() or "general"
    prompt_snippet = (prompt[:200] + "…") if len(prompt) > 200 else prompt
    parts = [f"User request / topic: {topic}"]
    if prompt_snippet:
        parts.append(f"Prompt snippet: {prompt_snippet}")
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
    request_id = state.get("request_id", "")
    context = _build_level_inference_context(state)
    model = os.environ.get("OPENAI_MODEL", "gpt-4o-mini")
    logger.info(
        "openai.request level_inference id=%s model=%s len=%d",
        request_id, model, len(context),
        extra={"request_id": request_id, "call_type": "level_inference", "model": model, "context_length": len(context)},
    )
    try:
        llm = _get_llm()
        msg = llm.invoke([
            SystemMessage(content=LEVEL_INFERENCE_SYSTEM),
            HumanMessage(content=context),
        ])
        text = (msg.content or "").strip().upper()
        inferred = None
        for lvl in CEFR_LEVELS:
            if lvl in text:
                inferred = lvl
                break
        logger.info(
            "openai.response level_inference id=%s ok level=%s prev=%s",
            request_id, inferred or "none", (text[:60] + "..") if len(text) > 60 else text,
            extra={"request_id": request_id, "call_type": "level_inference", "inferred_level": inferred},
        )
        _log_openai_usage(msg, request_id, "level_inference")
        if inferred:
            return inferred
    except Exception:
        logger.exception("level_inference.error id=%s openai_call_failed", request_id)
    return DEFAULT_CEFR_WHEN_UNKNOWN


def level_resolution(state: BoxWorkflowState) -> dict:
    """
    Always resolve a CEFR level: explicit in prompt first, else infer via LLM from boxes/words/completion/topic.
    Never ends the flow; fallback to A2 when inference fails. Sets level_source to "explicit" or "inferred".
    """
    request_id = state.get("request_id", "")
    prompt = state.get("prompt") or ""
    existing_boxes = state.get("existing_boxes") or []
    logger.info("level_resolution.start id=%s", request_id, extra={"request_id": request_id})

    level = _parse_cefr_from_prompt(prompt)
    source = "explicit" if level else "inferred"

    if level:
        logger.info(
            "level_resolution.done id=%s level=%s source=explicit",
            request_id, level,
            extra={"request_id": request_id, "level": level, "level_source": "explicit", "explicit_found": True},
        )
        return {"level": level, "level_source": source, "status": ""}

    logger.info("level_inference.start id=%s", request_id, extra={"request_id": request_id})
    level = _infer_level_with_llm(state)
    logger.info("level_inference.done id=%s level=%s", request_id, level, extra={"request_id": request_id, "level": level})
    logger.info(
        "level_resolution.done id=%s level=%s source=inferred",
        request_id, level,
        extra={"request_id": request_id, "level": level, "level_source": "inferred", "explicit_found": False, "inferred_used": True},
    )
    return {"level": level, "level_source": source, "status": ""}


TOPIC_LLM_SYSTEM = """You name vocabulary boxes for a language-learning app.

You are given a user request. Your job:
- Understand what TOPIC or situation the user cares about (e.g. restaurant, airport, dating, office meetings, job interview, travel, small talk).
- Return a SHORT, app-ready box name: 2–3 words, clear and friendly.

Guidelines:
- Examples of good names: "Street Eats", "Airport Basics", "Cafe Talk", "Office Chat", "Date Night", "Daily Basics", "City Break", "Travel Prep".
- Keep it concise and easy to understand.
- Avoid generic labels like "travel vocabulary" or "restaurant vocabulary".
- Avoid long sentences, punctuation, or explanations.

Reply with ONLY the short box name, nothing else.
"""


# ---- Topic identification ----

def _identify_topic_key(prompt: str) -> str:
    """
    Extract a topic key from prompt using keyword matching.
    Returns an internal key (e.g. "restaurant", "travel") for mapping to box name.
    """
    if not prompt:
        return "general"
    lower = prompt.lower()
    # Token-based check for robustness
    tokens = set(re.split(r"\W+", lower))
    for label, keywords in TOPIC_KEYWORDS.items():
        if any(kw in lower or kw in tokens for kw in keywords):
            return label
    return "general"


def _topic_to_box_name(topic_key: str, prompt: str) -> str:
    """
    Map topic key to a short, product-quality box name (2–3 words).
    Fallback for "general" uses first two significant words from prompt if available.
    """
    if topic_key in TOPIC_TO_BOX_NAME:
        return TOPIC_TO_BOX_NAME[topic_key]
    if topic_key == "general" and prompt:
        words = [w for w in re.split(r"\W+", prompt.lower()) if len(w) > 2][:2]
        if words:
            return " ".join(w.capitalize() for w in words)
    return DEFAULT_BOX_NAME


def _needs_topic_llm_fallback(topic_key: str, name: str, prompt: str) -> bool:
    """
    Heuristic: call LLM only when deterministic result is too generic or unclear.
    - general key with non-trivial prompt
    - default box name fallback
    """
    if not prompt.strip():
        return False
    if topic_key == "general":
        return True
    if name == DEFAULT_BOX_NAME:
        return True
    return False


def _infer_topic_with_llm(prompt: str, request_id: str) -> str | None:
    """
    Low-cost LLM fallback for topic/box naming.
    Returns a short 2–3 word label or None on failure.
    """
    model = os.environ.get("OPENAI_MODEL", "gpt-4o-mini")
    logger.info(
        "openai.request topic_inference id=%s model=%s len=%d",
        request_id, model, len(prompt),
        extra={"request_id": request_id, "call_type": "topic_inference", "model": model, "prompt_length": len(prompt)},
    )
    try:
        llm = _get_llm()
        msg = llm.invoke([
            SystemMessage(content=TOPIC_LLM_SYSTEM),
            HumanMessage(content=prompt),
        ])
        text = (msg.content or "").strip()
        # Normalize: first line only, collapse whitespace, cap to 3 words.
        first_line = text.split("\n", 1)[0].strip()
        if not first_line:
            return None
        words = [w for w in re.split(r"\s+", first_line) if w]
        short = " ".join(words[:3])
        short = short.strip()
        if not short:
            return None
        # Basic guard against obviously generic labels.
        lower = short.lower()
        if "vocabulary" in lower or "words" in lower or len(short) > 40:
            return None
        logger.info(
            "openai.response topic_inference id=%s ok topic=%s",
            request_id, short,
            extra={"request_id": request_id, "call_type": "topic_inference", "topic_label": short},
        )
        _log_openai_usage(msg, request_id, "topic_inference")
        return short
    except Exception:
        logger.exception("topic_inference.error id=%s openai_call_failed", request_id)
        return None


def topic_identification(state: BoxWorkflowState) -> dict:
    """
    Identify the topic/theme for the box from the prompt.
    Deterministic first, then optional low-cost LLM fallback for better names.
    Returns a short box name (e.g. "Street Eats", "City Break") for display and future generation.
    """
    request_id = state.get("request_id", "")
    prompt = state.get("prompt") or ""
    logger.info("topic_identification.start id=%s", request_id, extra={"request_id": request_id})

    topic_key = _identify_topic_key(prompt)
    deterministic_name = _topic_to_box_name(topic_key, prompt)
    use_llm = TOPIC_USE_LLM_FALLBACK and _needs_topic_llm_fallback(topic_key, deterministic_name, prompt)

    final_name = deterministic_name
    source = "deterministic"
    if use_llm:
        llm_name = _infer_topic_with_llm(prompt, request_id)
        if llm_name:
            final_name = llm_name
            source = "llm_fallback"
        else:
            source = "deterministic_fallback"

    logger.info(
        "topic_identification.done id=%s topic=%s source=%s",
        request_id, final_name, source,
        extra={"request_id": request_id, "topic": final_name, "topic_source": source, "topic_key": topic_key},
    )
    return {"topic": final_name}


def _existing_word_pairs(state: BoxWorkflowState) -> List[Tuple[str, str]]:
    """Flatten existingBoxes[].words[] into (default, target) pairs."""
    pairs: List[Tuple[str, str]] = []
    for box in state.get("existing_boxes") or []:
        for w in box.get("words") or []:
            pairs.append((w.get("default") or "", w.get("target") or ""))
    return pairs


def box_creation_placeholder(state: BoxWorkflowState) -> dict:
    """
    First real box generation:
    - retrieve vocabulary from local SQLite store
    - filter by language pair, topic, and level
    - remove duplicates against existing user boxes
    - return up to 30 word pairs (default -> target) for a single box.
    """
    request_id = state.get("request_id", "")
    default_lang = (state.get("default_language") or "").lower()
    target_lang = (state.get("target_language") or "").lower()
    topic_label = state.get("topic") or ""
    level = state.get("level") or None

    existing_pairs = _existing_word_pairs(state)

    logger.info(
        "box_creation_placeholder.start id=%s topic=%s level=%s lang_pair=%s-%s",
        request_id,
        topic_label or "(none)",
        level or "(unknown)",
        default_lang or "(none)",
        target_lang or "(none)",
        extra={
            "request_id": request_id,
            "topic": topic_label,
            "level": level,
            "default_language": default_lang,
            "target_language": target_lang,
        },
    )

    words: List[dict]
    stats: dict
    if not default_lang or not target_lang:
        words = []
        stats = {
            "primary_topic": "",
            "widened_topics": [],
            "primary_candidate_count": 0,
            "widened_candidate_count": 0,
            "duplicate_count": 0,
            "final_count": 0,
            "used_fallback_source": False,
            "partial": True,
        }
    else:
        words, stats = retrieve_candidates(
            default_lang,
            target_lang,
            display_topic=topic_label,
            level=level,
            existing_words=existing_pairs,
            max_items=30,
        )

    final_count = stats.get("final_count", len(words))
    partial = bool(stats.get("partial", final_count < 30))
    logger.info(
        "box_creation_placeholder.done id=%s topic=%s level=%s lang_pair=%s-%s primary_candidates=%s widened_candidates=%s duplicates_removed=%s final_items=%s partial=%s used_fallback=%s",
        request_id,
        topic_label or "(none)",
        level or "(unknown)",
        default_lang or "(none)",
        target_lang or "(none)",
        stats.get("primary_candidate_count"),
        stats.get("widened_candidate_count"),
        stats.get("duplicate_count"),
        final_count,
        partial,
        stats.get("used_fallback_source"),
        extra={
            "request_id": request_id,
            "topic": topic_label,
            "level": level,
            "default_language": default_lang,
            "target_language": target_lang,
            "primary_candidate_count": stats.get("primary_candidate_count"),
            "widened_candidate_count": stats.get("widened_candidate_count"),
            "duplicate_count": stats.get("duplicate_count"),
            "final_items": final_count,
            "partial": partial,
            "used_fallback_source": stats.get("used_fallback_source"),
        },
    )

    box_name = topic_label or DEFAULT_BOX_NAME
    box_id = f"generated-{request_id or 'box'}"

    boxes = []
    if words:
        boxes.append(
            {
                "boxId": box_id,
                "boxName": box_name,
                "words": words,
            }
        )

    return {
        "status": STATUS_GENERATED_PLACEHOLDER,
        "boxes": boxes,
        "user_message": "Ready to review a vocabulary box.",
        "reached_box_creation": True,
    }


# ---- Routers for conditional edges ----

def route_after_relevance(state: BoxWorkflowState) -> str:
    """If not relevant, end; else go to topic_identification (then level_resolution, then box_creation)."""
    from langgraph.graph import END
    if state.get("is_relevant") is True:
        return "topic_identification"
    return END
