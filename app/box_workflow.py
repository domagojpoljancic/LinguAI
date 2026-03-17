"""
Box-generation workflow nodes and routing.

Flow: relevance → topic → decide_retrieval_route → level → db_retrieval_attempt →
retrieval_quality_assessment → [optional ai_word_generation] → result_merge_and_filter →
box_creation_finalize → async_persist_ai_words (persist runs in FastAPI after HTTP response).
"""

import difflib
import logging
import os
import re
from typing import Any, Dict, List, Optional, Set, Tuple

from langchain_core.messages import SystemMessage, HumanMessage

from app.config import OPENAI_REQUEST_TIMEOUT
from app.state import BoxWorkflowState
from app.schemas import (
    STATUS_IRRELEVANT_REQUEST,
    STATUS_INSUFFICIENT_CONFIDENCE,
    STATUS_GENERATED_PLACEHOLDER,
    STATUS_GENERATION_EMPTY,
)
from app.ai_word_generator import generate_word_pairs
from app.prompts.word_generation import WordGenerationContext
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

# When topic came from AI (natural prompt), we pass topic_reason + these boost words to retrieval
# so situation-relevant vocabulary ranks first. Used only for ranking; retrieval stays deterministic.
TOPIC_SITUATION_BOOST: dict[str, list[str]] = {
    "health": ["hospital", "doctor", "medicine", "pharmacy", "appointment", "symptom", "pain", "nurse", "patient", "medical"],
    "restaurant": ["menu", "order", "bill", "table", "waiter", "food", "drink", "reservation", "kitchen", "coffee"],
    "travel": ["hotel", "airport", "flight", "passport", "luggage", "ticket", "train", "bus", "check", "reservation"],
    "business": ["meeting", "office", "email", "contract", "deadline", "presentation", "negotiation", "invoice", "agenda"],
    "shopping": ["price", "buy", "shop", "store", "receipt", "payment", "discount", "cash", "card"],
    "dating": ["date", "partner", "relationship", "love", "romance"],
    "daily": ["hello", "please", "thank", "sorry", "time", "day", "number"],
}


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


# ---- Topic identification (hybrid: deterministic fast-path, AI fallback for natural prompts) ----

# Minimum confidence to skip AI (deterministic result used when >= this).
TOPIC_DETERMINISTIC_CONFIDENCE_THRESHOLD = 0.7

# Confidence assigned when deterministic keyword match is found.
TOPIC_DETERMINISTIC_CONFIDENCE = 0.95

_TOPIC_TYPOS: Dict[str, str] = {
    "restaruant": "restaurant",
    "restraunt": "restaurant",
    "resteraunt": "restaurant",
    "travle": "travel",
    "travvel": "travel",
    "busines": "business",
    "buisness": "business",
}

_AI_LANG_CODES = frozenset({"en", "de", "es", "fr", "it", "pt", "nl", "pl"})

_LANG_ALIASES: Dict[str, str] = {
    "english": "en",
    "german": "de",
    "deutsch": "de",
    "spanish": "es",
    "español": "es",
    "espanol": "es",
    "french": "fr",
    "français": "fr",
    "francais": "fr",
    "italian": "it",
    "portuguese": "pt",
    "dutch": "nl",
    "polish": "pl",
}


def _canonical_lang(code: Optional[str]) -> str:
    if not code or not str(code).strip():
        return ""
    s = str(code).strip().lower().replace("_", "-")
    if s in _LANG_ALIASES:
        return _LANG_ALIASES[s]
    if len(s) == 2 and s.isalpha():
        return s
    if "-" in s:
        s = s.split("-")[0][:2]
    return s[:2] if len(s) >= 2 and s[:2].isalpha() else ""


def _resolve_language_pair(state: BoxWorkflowState) -> Tuple[str, str]:
    d = _canonical_lang(state.get("default_language"))
    t = _canonical_lang(state.get("target_language"))
    pl = (state.get("prompt") or "").lower()
    if not d and t:
        d = "en" if t != "en" else "de"
    elif d and not t:
        t = "de" if d == "en" else ("en" if d in ("de", "es", "fr", "it") else "en")
    elif not d and not t:
        if "german" in pl or "deutsch" in pl:
            d, t = "en", "de"
        elif "spanish" in pl or "español" in pl or "espanol" in pl:
            d, t = "en", "es"
        else:
            d, t = "en", "de"
    if d == t and d:
        t = "de" if d == "en" else "en"
    return d, t


def _normalize_topic_typos(prompt: str) -> str:
    if not prompt:
        return ""
    s = prompt.lower()
    for bad, good in _TOPIC_TYPOS.items():
        s = re.sub(rf"\b{re.escape(bad)}\b", good, s)
    return s


def _identify_topic_deterministic(prompt: str) -> Tuple[str, float]:
    """Keyword match + typo fixes + fuzzy token match vs topic keywords."""
    if not prompt:
        return "general", 0.0
    lower = _normalize_topic_typos(prompt)
    tokens = set(re.split(r"\W+", lower))
    for label, keywords in TOPIC_KEYWORDS.items():
        if any(kw in lower or kw in tokens for kw in keywords):
            return label, TOPIC_DETERMINISTIC_CONFIDENCE
    long_tokens = [w for w in re.findall(r"[a-z]{4,}", lower) if len(w) >= 4]
    for label, keywords in TOPIC_KEYWORDS.items():
        for kw in keywords:
            if len(kw) < 4:
                continue
            for tok in long_tokens:
                if tok == kw:
                    return label, TOPIC_DETERMINISTIC_CONFIDENCE
                if len(tok) >= 5 and len(kw) >= 5:
                    if difflib.SequenceMatcher(None, tok, kw).ratio() >= 0.86:
                        return label, 0.88
    return "general", 0.0


def topic_identification(state: BoxWorkflowState) -> dict:
    """
    Identify the topic/theme for the box from the prompt.
    Hybrid: deterministic first (high confidence -> skip AI); AI fallback for natural/ambiguous prompts.
    Returns topic key from internal enum, confidence 0–1, source (deterministic | ai), and optional reason.
    Downstream retrieval uses topic key; box display name is derived via TOPIC_TO_BOX_NAME.
    """
    request_id = state.get("request_id", "")
    prompt = (state.get("prompt") or "").strip()
    d_lang, t_lang = _resolve_language_pair(state)
    logger.info("topic_identification.start id=%s", request_id, extra={"request_id": request_id})

    topic_key, confidence = _identify_topic_deterministic(prompt)
    use_ai = (
        topic_key is None
        or topic_key == "general"
        or confidence < TOPIC_DETERMINISTIC_CONFIDENCE_THRESHOLD
    )

    if not use_ai:
        topic_keywords = TOPIC_KEYWORDS.get(topic_key, [])[:5] if topic_key in TOPIC_KEYWORDS else [topic_key]
        situation_label = TOPIC_TO_BOX_NAME.get(topic_key, topic_key) or ""
        logger.info(
            "topic_identification.done id=%s topic=%s confidence=%s source=deterministic",
            request_id, topic_key, confidence,
            extra={"request_id": request_id, "topic": topic_key, "topic_confidence": confidence, "topic_source": "deterministic"},
        )
        return {
            "default_language": d_lang,
            "target_language": t_lang,
            "topic": topic_key,
            "topic_confidence": confidence,
            "topic_source": "deterministic",
            "topic_reason": "",
            "topic_keywords": topic_keywords,
            "situation_label": situation_label,
        }

    from app.ai_topic_classifier import classify_with_ai, normalize_topic

    ai_result = classify_with_ai(prompt, request_id)
    topic_key = normalize_topic(ai_result.get("topic"))
    try:
        confidence = float(ai_result.get("confidence", 0.0) or 0.0)
    except (TypeError, ValueError):
        confidence = 0.5
    reason = (ai_result.get("reason") or "").strip()
    topic_keywords = ai_result.get("topic_keywords") or []
    if not isinstance(topic_keywords, list):
        topic_keywords = []
    situation_label = (ai_result.get("situation_label") or "").strip()
    if isinstance(situation_label, str) and len(situation_label) > 100:
        situation_label = situation_label[:100]

    logger.info(
        "topic_identification.done id=%s topic=%s confidence=%s source=ai reason=%s keywords=%s",
        request_id, topic_key, confidence, reason[:50] if reason else "", topic_keywords,
        extra={
            "request_id": request_id,
            "topic": topic_key,
            "topic_confidence": confidence,
            "topic_source": "ai",
            "topic_reason": reason,
            "topic_keywords": topic_keywords,
            "situation_label": situation_label,
        },
    )
    return {
        "default_language": d_lang,
        "target_language": t_lang,
        "topic": topic_key,
        "topic_confidence": confidence,
        "topic_source": "ai",
        "topic_reason": reason,
        "topic_keywords": topic_keywords,
        "situation_label": situation_label,
    }


def decide_retrieval_route(state: BoxWorkflowState) -> dict:
    """Decide whether to use DB, AI, or mixed retrieval based on topic and prompt context.

    Returns keys:
      - retrieval_route: "db_first" | "ai_first" | "mixed"
      - retrieval_route_reason: short explanation
      - retrieval_route_confidence: 0–1
    """
    request_id = state.get("request_id", "")
    topic = (state.get("topic") or "").strip().lower() or "general"
    topic_conf = float(state.get("topic_confidence") or 0.0)
    topic_keywords = state.get("topic_keywords") or []
    situation_label = (state.get("situation_label") or "").strip().lower()
    prompt = (state.get("prompt") or "").strip().lower()

    supported_topics = {"restaurant", "travel", "shopping", "business", "health", "dating", "daily"}

    def has_any(words: list[str]) -> bool:
        return any(w in prompt for w in words)

    sports_words = ["football", "soccer", "basketball", "tennis", "sport", "gym", "fitness"]
    landlord_words = ["landlord", "rent", "tenant", "lease"]
    weather_words = [
        "weather", "climate", "rain", "snow", "storm", "temperature", "forecast",
        "cloudy", "sunny", "wind", "humid", "drizzle",
    ]
    niche_vocab = sports_words + landlord_words + weather_words

    keywords_lower = [str(k).strip().lower() for k in topic_keywords]
    kw_set = set(k for k in keywords_lower if k)

    route = "mixed"
    reason = "default mixed routing"
    confidence = 0.5

    # 1. Strong, known topic -> db_first
    if topic in supported_topics and topic_conf >= 0.7:
        route = "db_first"
        reason = f"strong supported topic: {topic} (topic_confidence={topic_conf:.2f})"
        confidence = min(1.0, 0.8 + topic_conf / 5.0)
    # 2. Niche / broad topics: prefer AI-first (sports, weather, landlord, gym, etc.)
    elif (
        topic == "unsupported"
        or has_any(niche_vocab)
        or bool(kw_set.intersection(niche_vocab))
    ):
        route = "ai_first"
        reason = "broad or niche topic (sports, weather, gym, landlord, etc.) — AI-first"
        confidence = 0.85
    # 3. Vague but language-relevant -> mixed
    else:
        route = "mixed"
        reason = f"vague or general topic ({topic}) with topic_confidence={topic_conf:.2f}"
        confidence = 0.6 if topic_conf < 0.4 else 0.7

    logger.info(
        "decide_retrieval_route.done id=%s topic=%s route=%s conf=%s reason=%s",
        request_id, topic, route, confidence, reason,
        extra={
            "request_id": request_id,
            "retrieval_route": route,
            "retrieval_route_confidence": confidence,
        },
    )
    return {
        "retrieval_route": route,
        "retrieval_route_reason": reason,
        "retrieval_route_confidence": confidence,
    }


def _existing_word_pairs(state: BoxWorkflowState) -> List[Tuple[str, str]]:
    """Flatten existingBoxes[].words[] into (default, target) pairs."""
    pairs: List[Tuple[str, str]] = []
    for box in state.get("existing_boxes") or []:
        for w in box.get("words") or []:
            pairs.append((w.get("default") or "", w.get("target") or ""))
    return pairs


TARGET_MIN_STRONG_WORDS = 20
MAX_BOX_WORDS = 30


def _ai_lang_pair_allowed(state: BoxWorkflowState) -> bool:
    """OpenAI word-pair gen for distinct languages in _AI_LANG_CODES (en, de, es, fr, it, …)."""
    d = _canonical_lang(state.get("default_language"))
    t = _canonical_lang(state.get("target_language"))
    return bool(d and t and d != t and d in _AI_LANG_CODES and t in _AI_LANG_CODES)


def _norm_pair(d: str, t: str) -> Tuple[str, str]:
    return ((d or "").strip().lower(), (t or "").strip().lower())


def _build_situation_hint(state: BoxWorkflowState, topic_key: str) -> Optional[str]:
    """Build situation hint for retrieval ranking from topic_reason, topic_keywords, situation_label, and boost."""
    parts: List[str] = []
    reason = (state.get("topic_reason") or "").strip()[:200]
    if reason:
        parts.append(reason)
    keywords = state.get("topic_keywords") or []
    for kw in keywords[:10]:
        if kw and isinstance(kw, str):
            parts.append(kw.strip())
    situation_label = (state.get("situation_label") or "").strip()[:80]
    if situation_label:
        parts.append(situation_label)
    boost = TOPIC_SITUATION_BOOST.get(topic_key, [])
    parts.extend(boost[:5])
    return " ".join(p for p in parts if p) or None


def db_retrieval_attempt(state: BoxWorkflowState) -> dict:
    """
    Load vocabulary candidates from SQLite by topic, level, language pair.
    Produces _db_entries (default/target/phase) and db_candidate_count (pool size).
    """
    request_id = state.get("request_id", "")
    default_lang, target_lang = _resolve_language_pair(state)
    topic_key = state.get("topic") or "general"
    level = state.get("level") or None
    existing_pairs = _existing_word_pairs(state)

    logger.info(
        "db_retrieval_attempt.start id=%s topic=%s lang=%s-%s",
        request_id, topic_key, default_lang, target_lang,
        extra={"request_id": request_id},
    )

    stats: Dict[str, Any] = {
        "primary_candidate_count": 0,
        "widened_candidate_count": 0,
        "final_count": 0,
    }
    entries: List[Dict[str, str]] = []

    if default_lang and target_lang and default_lang != target_lang:
        situation_hint = _build_situation_hint(state, topic_key)
        words, stats, _, phases = retrieve_candidates(
            default_lang,
            target_lang,
            display_topic=topic_key,
            level=level,
            existing_words=existing_pairs,
            max_items=MAX_BOX_WORDS,
            include_debug=False,
            situation_hint=situation_hint,
        )
        for i, w in enumerate(words):
            ph = phases[i] if i < len(phases) else "widened"
            entries.append({
                "default": w["default"],
                "target": w["target"],
                "phase": ph,
            })

    db_candidate_count = int(stats.get("primary_candidate_count") or 0) + int(
        stats.get("widened_candidate_count") or 0
    )
    return {
        "_db_entries": entries,
        "_db_stats": stats,
        "db_candidate_count": db_candidate_count,
    }


def retrieval_quality_assessment(state: BoxWorkflowState) -> dict:
    """Count strong (primary-topic) DB rows in retrieved set for routing thresholds."""
    entries = state.get("_db_entries") or []
    strong = sum(1 for e in entries if (e.get("phase") or "") == "primary")
    return {"db_strong_candidate_count": strong}


def route_after_retrieval_quality(state: BoxWorkflowState) -> str:
    """Skip AI when lang pair disallowed or db_first already has enough strong DB words."""
    if not _ai_lang_pair_allowed(state):
        return "result_merge_and_filter"
    route = (state.get("retrieval_route") or "mixed").lower()
    strong = int(state.get("db_strong_candidate_count") or 0)
    if route == "db_first" and strong >= TARGET_MIN_STRONG_WORDS:
        return "result_merge_and_filter"
    return "ai_word_generation"


def ai_word_generation(state: BoxWorkflowState) -> dict:
    """
    OpenAI structured word pairs (single-word), validated. Interactive timeout via WORD_GEN_TIMEOUT (default 18s).
    """
    request_id = state.get("request_id", "")
    existing_pairs = _existing_word_pairs(state)
    avoid = []
    for box in state.get("existing_boxes") or []:
        for w in box.get("words") or []:
            d = (w.get("default") or "").strip()
            if d:
                avoid.append(d)

    dl, tl = _resolve_language_pair(state)
    ctx = WordGenerationContext(
        user_prompt=state.get("prompt") or "",
        default_language=dl,
        target_language=tl,
        level=(state.get("level") or "A2"),
        topic=(state.get("topic") or "general"),
        topic_keywords=list(state.get("topic_keywords") or []),
        situation_label=(state.get("situation_label") or ""),
        topic_reason=(state.get("topic_reason") or ""),
        retrieval_route=(state.get("retrieval_route") or "mixed"),
        existing_default_words=avoid,
        existing_word_pairs=existing_pairs,
        max_pairs=32,
    )
    result = generate_word_pairs(ctx, request_id)
    validated = [
        {"default": v.default, "target": v.target, "confidence": v.confidence}
        for v in result.validated
    ]
    patch = result.to_state_patch()
    return {
        "_ai_generation_attempted": True,
        "_ai_validated": validated,
        **patch,
    }


def _merge_results(state: BoxWorkflowState) -> Tuple[List[Dict[str, Any]], str, bool, bool]:
    """
    Returns (final_rows with source tag, strategy, db_fallback_used, ai_supplement_used).
    """
    route = (state.get("retrieval_route") or "mixed").lower()
    entries = list(state.get("_db_entries") or [])
    ai_attempted = bool(state.get("_ai_generation_attempted"))
    raw_ai = state.get("_ai_validated") or []
    ai_items: List[Dict[str, Any]] = [
        {"default": x["default"], "target": x["target"], "confidence": float(x.get("confidence", 0.8))}
        for x in raw_ai
        if isinstance(x, dict) and x.get("default") and x.get("target")
    ]
    ai_allowed = _ai_lang_pair_allowed(state)
    strong = int(state.get("db_strong_candidate_count") or 0)
    has_ai = len(ai_items) > 0
    ai_failed = ai_attempted and not has_ai

    def db_primary_first() -> List[Dict[str, str]]:
        primary = [e for e in entries if e.get("phase") == "primary"]
        widened = [e for e in entries if e.get("phase") != "primary"]
        return primary + widened

    db_fallback = False
    ai_supp = False
    out: List[Dict[str, Any]] = []
    seen: Set[Tuple[str, str]] = set()

    def add_row(d: str, t: str, source: str) -> None:
        k = _norm_pair(d, t)
        if k[0] == "" or k[1] == "" or k in seen:
            return
        seen.add(k)
        out.append({"default": d.strip(), "target": t.strip(), "source": source})
        if source == "ai":
            nonlocal ai_supp
            ai_supp = True

    strategy = "unknown"

    if route == "db_first":
        if strong >= TARGET_MIN_STRONG_WORDS:
            for e in db_primary_first():
                if len(out) >= MAX_BOX_WORDS:
                    break
                add_row(e["default"], e["target"], "db_primary" if e.get("phase") == "primary" else "db_widened")
            strategy = "db_only_sufficient"
        elif ai_allowed and has_ai:
            for e in db_primary_first():
                if len(out) >= MAX_BOX_WORDS:
                    break
                add_row(e["default"], e["target"], "db_primary" if e.get("phase") == "primary" else "db_widened")
            for a in sorted(ai_items, key=lambda x: -x["confidence"]):
                if len(out) >= MAX_BOX_WORDS:
                    break
                add_row(a["default"], a["target"], "ai")
            strategy = "db_first_ai_topup"
        elif ai_allowed and ai_failed:
            for e in db_primary_first():
                if len(out) >= MAX_BOX_WORDS:
                    break
                add_row(e["default"], e["target"], "db_primary" if e.get("phase") == "primary" else "db_widened")
            strategy = "db_first_ai_failed_db_only"
            db_fallback = True
        else:
            for e in db_primary_first():
                if len(out) >= MAX_BOX_WORDS:
                    break
                add_row(e["default"], e["target"], "db_primary" if e.get("phase") == "primary" else "db_widened")
            strategy = "db_first_no_ai_lang_or_skipped"

    elif route == "ai_first":
        if not ai_allowed or not ai_attempted:
            db_fallback = True
            for e in db_primary_first():
                if len(out) >= MAX_BOX_WORDS:
                    break
                add_row(e["default"], e["target"], "db_primary" if e.get("phase") == "primary" else "db_widened")
            strategy = "ai_first_db_only_lang_or_no_attempt"
        elif ai_failed:
            db_fallback = True
            for e in db_primary_first():
                if len(out) >= MAX_BOX_WORDS:
                    break
                add_row(e["default"], e["target"], "db_primary" if e.get("phase") == "primary" else "db_widened")
            strategy = "ai_first_api_fail_db_fallback"
        elif len(ai_items) >= TARGET_MIN_STRONG_WORDS:
            for a in sorted(ai_items, key=lambda x: -x["confidence"]):
                if len(out) >= MAX_BOX_WORDS:
                    break
                add_row(a["default"], a["target"], "ai")
            strategy = "ai_first_sufficient"
        else:
            for a in sorted(ai_items, key=lambda x: -x["confidence"]):
                add_row(a["default"], a["target"], "ai")
            for e in db_primary_first():
                if len(out) >= MAX_BOX_WORDS:
                    break
                add_row(e["default"], e["target"], "db_primary" if e.get("phase") == "primary" else "db_widened")
            strategy = "ai_first_partial_db_fill"

    else:  # mixed
        if not ai_allowed or not ai_attempted:
            for e in db_primary_first():
                if len(out) >= MAX_BOX_WORDS:
                    break
                add_row(e["default"], e["target"], "db_primary" if e.get("phase") == "primary" else "db_widened")
            strategy = "mixed_degraded_db_only_lang" if not ai_allowed else "mixed_no_ai_branch"
        else:
            for e in entries:
                if e.get("phase") != "primary":
                    continue
                if len(out) >= MAX_BOX_WORDS:
                    break
                add_row(e["default"], e["target"], "db_primary")
            for e in entries:
                if e.get("phase") == "primary":
                    continue
                if len(out) >= MAX_BOX_WORDS:
                    break
                add_row(e["default"], e["target"], "db_widened")
            for a in sorted(ai_items, key=lambda x: -x["confidence"]):
                if len(out) >= MAX_BOX_WORDS:
                    break
                add_row(a["default"], a["target"], "ai")
            strategy = "mixed_db_then_ai_ranked"
            if ai_failed:
                db_fallback = True
            if has_ai:
                ai_supp = True

    return out, strategy, db_fallback, ai_supp


def result_merge_and_filter(state: BoxWorkflowState) -> dict:
    """
    DB-first / AI-first / mixed merge, dedupe, prefer DB on ties. Target up to 30 words.
    """
    request_id = state.get("request_id", "")
    final_rows, strategy, db_fb, ai_supp = _merge_results(state)
    logger.info(
        "result_merge_and_filter id=%s strategy=%s final_n=%s db_fallback=%s ai_supp=%s",
        request_id, strategy, len(final_rows), db_fb, ai_supp,
        extra={"request_id": request_id, "final_mix_strategy": strategy},
    )
    return {
        "_final_merged_rows": final_rows,
        "final_candidate_count": len(final_rows),
        "final_mix_strategy": strategy,
        "db_fallback_used": db_fb,
        "ai_supplement_used": ai_supp,
        "ai_used": ai_supp or (state.get("ai_used") is True),
    }


def _box_display_name(state: BoxWorkflowState, topic_key: str) -> str:
    sl = (state.get("situation_label") or "").strip()
    if sl and 3 <= len(sl) <= 48 and topic_key in ("general", "daily"):
        return sl[0].upper() + sl[1:] if len(sl) > 1 else sl.upper()
    return TOPIC_TO_BOX_NAME.get(topic_key, DEFAULT_BOX_NAME)


def box_creation_finalize(state: BoxWorkflowState) -> dict:
    """Build response box from merged words; queue AI pairs for post-response persistence."""
    request_id = state.get("request_id", "")
    topic_key = state.get("topic") or "general"
    box_display_name = _box_display_name(state, topic_key)
    rows = state.get("_final_merged_rows") or []
    words = [{"default": r["default"], "target": r["target"]} for r in rows]
    persist = [
        {"default": r["default"], "target": r["target"]}
        for r in rows
        if r.get("source") == "ai"
    ]
    box_id = f"generated-{request_id or 'box'}"
    boxes: List[dict] = []
    if words:
        boxes.append({"boxId": box_id, "boxName": box_display_name, "words": words})

    debug_candidates = os.environ.get("DEBUG_BOX_CANDIDATES") == "1"
    candidate_debug = None
    if debug_candidates and rows:
        candidate_debug = [
            {
                "default": r["default"],
                "target": r["target"],
                "selection_reason": r.get("source", ""),
            }
            for r in rows
        ]

    if not words:
        logger.warning(
            "box_creation_finalize.empty id=%s topic=%s strategy=%s",
            request_id,
            topic_key,
            state.get("final_mix_strategy"),
            extra={"request_id": request_id},
        )
        out = {
            "status": STATUS_GENERATION_EMPTY,
            "boxes": [],
            "user_message": (
                "We couldn't build a vocabulary list this time. "
                "Check your connection, confirm your language pair is supported, or try rephrasing — then tap try again."
            ),
            "reached_box_creation": True,
            "persist_ai_fallback_pairs": [],
        }
    else:
        out = {
            "status": STATUS_GENERATED_PLACEHOLDER,
            "boxes": boxes,
            "user_message": "Ready to review a vocabulary box.",
            "reached_box_creation": True,
            "persist_ai_fallback_pairs": persist,
        }
    if candidate_debug is not None:
        out["candidate_debug"] = candidate_debug
    return out


def async_persist_ai_words(state: BoxWorkflowState) -> dict:
    """
    Graph boundary for post-response work: FastAPI BackgroundTasks persist persist_ai_fallback_pairs
    after the HTTP response (see main.generate_boxes). This node does not write to DB.
    """
    n = len(state.get("persist_ai_fallback_pairs") or [])
    return {"async_persist_queued": n > 0}


# ---- Routers for conditional edges ----

def route_after_relevance(state: BoxWorkflowState) -> str:
    """If not relevant, end; else go to topic_identification (then level_resolution, then box_creation)."""
    from langgraph.graph import END
    if state.get("is_relevant") is True:
        return "topic_identification"
    return END
