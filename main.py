"""FastAPI server for LinguAI LangGraph backend."""

import hashlib
import html
import inspect
import json
import logging
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from dotenv import load_dotenv
from fastapi import BackgroundTasks, FastAPI, HTTPException
from fastapi.responses import HTMLResponse, PlainTextResponse

from app.config import DEBUG
from app.evaluation_log import log_evaluation_run
from app.graph import create_graph
from app.vocab_store import persist_ai_fallback_pairs
from app.idempotency import get as idempotency_get, set as idempotency_set
from app.logging_config import setup_logging
from app.schemas import (
    GenerateBoxesRequest,
    GenerateBoxesResponse,
    STATUS_GENERATED_PLACEHOLDER,
)
from app.state import BoxWorkflowState

# Load env first so optional LangSmith tracing works when set (LANGCHAIN_TRACING_V2=true, LANGCHAIN_API_KEY).
load_dotenv()

# Structured logging: configured centrally, readable in local dev; request_id in extras for filtering.
setup_logging()
logger = logging.getLogger(__name__)

app = FastAPI(title="LinguAI LangGraph", version="0.1.0")
graph = None


# ---------------------------------------------------------------------------
# Idempotency (customer_id + request_id, payload hash for conflict detection)
# ---------------------------------------------------------------------------


def _request_hash(req: GenerateBoxesRequest) -> str:
    """Canonical hash of request fields that affect the result (prompt, languages, existingBoxes)."""
    boxes = [b.model_dump(mode="json") for b in req.existingBoxes]
    boxes.sort(key=lambda x: x.get("boxId", ""))
    canonical = {
        "prompt": req.prompt,
        "defaultLanguage": req.defaultLanguage,
        "targetLanguage": req.targetLanguage,
        "existingBoxes": boxes,
    }
    return hashlib.sha256(json.dumps(canonical, sort_keys=True).encode()).hexdigest()


def _check_idempotency(req: GenerateBoxesRequest) -> Optional[GenerateBoxesResponse]:
    """
    Look up (customerId, requestId). If miss, return None. If hit with same payload hash,
    return cached response. If hit with different payload, raise 409 Conflict.
    """
    stored = idempotency_get(req.customerId, req.requestId)
    if stored is None:
        return None
    stored_hash, response_json = stored
    current_hash = _request_hash(req)
    if stored_hash != current_hash:
        raise HTTPException(
            status_code=409,
            detail="Idempotency conflict: this requestId was already used with a different payload for this customer.",
        )
    return GenerateBoxesResponse.model_validate_json(response_json)


# ---------------------------------------------------------------------------
# Duplicate strategy
# ---------------------------------------------------------------------------
# Duplicate box prevention for the same customer is achieved via idempotency:
# same (customerId, requestId) + same payload returns the cached response and no new generation.
# No separate semantic duplicate-detection; idempotency key covers retries and replays.


# ---------------------------------------------------------------------------
# Debug-only: request/response log file (not synced to git; logs/ is in .gitignore)
# ---------------------------------------------------------------------------

_REQUEST_RESPONSE_LOGGER: Optional[logging.Logger] = None


def _setup_request_response_log() -> Optional[logging.Logger]:
    """When DEBUG is True, add a file handler for request/response logging. Otherwise return None."""
    if not DEBUG:
        return None
    global _REQUEST_RESPONSE_LOGGER
    if _REQUEST_RESPONSE_LOGGER is not None:
        return _REQUEST_RESPONSE_LOGGER
    log_dir = Path(__file__).resolve().parent / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / "request_response.log"
    _REQUEST_RESPONSE_LOGGER = logging.getLogger("app.request_response")
    _REQUEST_RESPONSE_LOGGER.setLevel(logging.INFO)
    _REQUEST_RESPONSE_LOGGER.propagate = False
    handler = logging.FileHandler(log_file, encoding="utf-8")
    handler.setFormatter(logging.Formatter("%(message)s"))
    _REQUEST_RESPONSE_LOGGER.addHandler(handler)
    return _REQUEST_RESPONSE_LOGGER


def _log_request_response(kind: str, payload: dict) -> None:
    """Append one JSON line to the request/response log file (debug only)."""
    log = _setup_request_response_log()
    if log is None:
        return
    line = json.dumps({"ts": datetime.now(timezone.utc).isoformat(), "type": kind, "body": payload}, ensure_ascii=False)
    log.info(line)


# ---------------------------------------------------------------------------
# Debug: graph visualization (development only)
# ---------------------------------------------------------------------------


def _get_drawable_graph():
    """Return the LangGraph drawable graph for visualization, or None if not available."""
    global graph
    if graph is None:
        return None
    try:
        return graph.get_graph()
    except Exception:
        return None


# Known nodes: role and data flow (best-effort from code structure; not runtime trace).
_DEBUG_NODE_ROLES = {
    "request_understanding": "early structured intent (LLM)",
    "relevance_check": "gate (LLM)",
    "level_resolution": "CEFR explicit or LLM infer",
    "topic_identification": "deterministic keywords or AI classifier",
    "decide_retrieval_route": "db_first | ai_first | mixed (deterministic)",
    "db_retrieval_attempt": "SQLite retrieval by topic/level/lang",
    "retrieval_quality_assessment": "count primary-topic DB rows (strong threshold)",
    "ai_word_generation": "OpenAI Responses JSON schema; ~18s timeout default",
    "result_merge_and_filter": "merge DB+AI, dedupe, DB preferred on ties",
    "box_creation_finalize": "build boxes; queue persist_ai_fallback_pairs",
    "async_persist_ai_words": "marks queue; HTTP layer runs BackgroundTasks after response",
}
_DEBUG_NODE_IO = {
    "request_understanding": {
        "consumes": ["prompt", "request_id", "default_language", "target_language"],
        "produces": [
            "is_relevant",
            "status",
            "relevance_user_message",
            "user_message",
            "topic",
            "subtopic",
            "topic_keywords",
            "situation_label",
            "level_hint",
            "understanding_confidence",
            "understanding_reason",
            "retrieval_route",
            "retrieval_route_reason",
            "retrieval_route_confidence",
        ],
    },
    "relevance_check": {
        "consumes": ["prompt", "request_id"],
        "produces": ["is_relevant", "relevance_user_message", "status", "user_message"],
    },
    "level_resolution": {
        "consumes": ["prompt", "existing_boxes", "request_id", "topic"],
        "produces": ["level", "level_source", "status"],
    },
    "topic_identification": {
        "consumes": ["prompt"],
        "produces": ["topic", "topic_confidence", "topic_source", "topic_reason", "topic_keywords", "situation_label"],
    },
    "decide_retrieval_route": {
        "consumes": ["topic", "topic_confidence", "topic_keywords", "situation_label", "topic_reason", "prompt"],
        "produces": ["retrieval_route", "retrieval_route_reason", "retrieval_route_confidence"],
    },
    "db_retrieval_attempt": {
        "consumes": ["topic", "level", "default_language", "target_language", "existing_boxes", "topic_reason", "topic_keywords"],
        "produces": ["_db_entries", "_db_stats", "db_candidate_count"],
    },
    "retrieval_quality_assessment": {
        "consumes": ["_db_entries"],
        "produces": ["db_strong_candidate_count"],
    },
    "ai_word_generation": {
        "consumes": ["prompt", "level", "languages", "topic metadata", "retrieval_route", "existing_boxes"],
        "produces": ["_ai_generation_attempted", "_ai_validated", "ai_used", "ai_candidate_count", "ai_validated_count", "ai_failure_reason"],
    },
    "result_merge_and_filter": {
        "consumes": ["retrieval_route", "_db_entries", "_ai_validated", "_ai_generation_attempted", "db_strong_candidate_count"],
        "produces": ["_final_merged_rows", "final_candidate_count", "final_mix_strategy", "db_fallback_used", "ai_supplement_used"],
    },
    "box_creation_finalize": {
        "consumes": ["_final_merged_rows", "topic", "request_id"],
        "produces": ["status", "boxes", "user_message", "reached_box_creation", "persist_ai_fallback_pairs", "candidate_debug (optional)"],
    },
    "async_persist_ai_words": {
        "consumes": ["persist_ai_fallback_pairs"],
        "produces": ["async_persist_queued"],
    },
}

# State keys grouped for readability (from BoxWorkflowState).
_DEBUG_STATE_REQUEST = ["request_id", "customer_id", "prompt", "default_language", "target_language", "existing_boxes"]
_DEBUG_STATE_WORKFLOW = [
    "is_relevant", "relevance_user_message", "level", "level_source",
    "topic", "topic_confidence", "topic_source", "topic_reason", "topic_keywords", "situation_label",
    "subtopic", "understanding_confidence", "understanding_reason", "level_hint",
    "retrieval_route", "retrieval_route_reason", "retrieval_route_confidence",
    "db_candidate_count", "db_strong_candidate_count",
    "ai_used", "ai_candidate_count", "ai_validated_count", "ai_failure_reason",
    "final_candidate_count", "final_mix_strategy", "db_fallback_used", "ai_supplement_used",
    "async_persist_queued", "reached_box_creation",
]
_DEBUG_STATE_RESPONSE = ["status", "user_message", "boxes"]


def _get_state_keys_from_schema() -> list[str]:
    """Return state keys from BoxWorkflowState (TypedDict) for debug docs."""
    return list(getattr(BoxWorkflowState, "__annotations__", {}).keys())


def _get_flow_order(drawable, compiled_graph) -> list[str]:
    """
    Execution order of nodes. Uses builder.node order (insertion order = flow order);
    drawable edges often collapse conditionals so we don't rely on them for full order.
    """
    builder = getattr(compiled_graph, "builder", None)
    node_specs = getattr(builder, "nodes", {}) if builder else {}
    if node_specs:
        return list(node_specs.keys())
    # Fallback: from drawable edges from __start__
    edges = getattr(drawable, "edges", []) or []
    next_map = {}
    for e in edges:
        src = getattr(e, "source", None) or (e[0] if isinstance(e, (list, tuple)) else None)
        tgt = getattr(e, "target", None) or (e[1] if isinstance(e, (list, tuple)) and len(e) > 1 else None)
        if src is None or tgt is None or tgt == "__end__":
            continue
        next_map.setdefault(src, []).append(tgt)
    order = []
    cur = "__start__"
    seen = set()
    while cur in next_map:
        candidates = [n for n in next_map[cur] if n != "__end__" and n not in seen]
        if not candidates:
            break
        nxt = candidates[0]
        if nxt not in ("__start__", "__end__"):
            order.append(nxt)
            seen.add(nxt)
        cur = nxt
    return order


# Known graph structure for "hands off to" (conditionals not always in drawable edges).
_DEBUG_HANDS_OFF = {
    "request_understanding": ["topic_identification (or relevance_check re-validate)", "END (if high-confidence irrelevant)"],
    "relevance_check": ["topic_identification", "END (if not relevant)"],
    "topic_identification": ["decide_retrieval_route"],
    "decide_retrieval_route": ["level_resolution"],
    "level_resolution": ["db_retrieval_attempt"],
    "db_retrieval_attempt": ["retrieval_quality_assessment"],
    "retrieval_quality_assessment": ["ai_word_generation OR result_merge_and_filter (branch)"],
    "ai_word_generation": ["result_merge_and_filter"],
    "result_merge_and_filter": ["box_creation_finalize"],
    "box_creation_finalize": ["async_persist_ai_words"],
    "async_persist_ai_words": ["END"],
}


def _get_hands_off(drawable, flow_order: list[str]) -> dict[str, list[str]]:
    """Map each node to list of successors. Uses known graph when drawable collapses conditionals."""
    if flow_order and all(n in _DEBUG_HANDS_OFF for n in flow_order):
        return _DEBUG_HANDS_OFF.copy()
    out = {}
    for e in getattr(drawable, "edges", []) or []:
        src = getattr(e, "source", None) or (e[0] if isinstance(e, (list, tuple)) else None)
        tgt = getattr(e, "target", None) or (e[1] if isinstance(e, (list, tuple)) and len(e) > 1 else None)
        if src is None or tgt is None:
            continue
        out.setdefault(src, []).append("end" if tgt == "__end__" else tgt)
    return out


def _introspect_node_callable(runnable) -> Optional[object]:
    """Unwrap runnable to underlying callable if possible (e.g. RunnableLambda.func)."""
    if runnable is None:
        return None
    fn = getattr(runnable, "func", runnable)
    return fn if callable(fn) else runnable


# Ground-truth AI metadata per graph node. (_introspect_ai_usage used to scan only the node's own
# source for _get_llm/ChatOpenAI; delegating helpers like classify_with_ai / generate_word_pairs
# caused an early return with "AI calls: 0" before name-based fixes could run.)
_DEBUG_NODE_AI_METADATA: dict[str, dict[str, str]] = {
    "request_understanding": {
        "ai_calls": "0 or 1× Chat Completions (structured JSON)",
        "model": "OPENAI_MODEL (app.ai_request_understanding + langchain_openai.ChatOpenAI)",
        "mode": "Called in request_understanding node (skipped on empty prompt / exception paths)",
    },
    "relevance_check": {
        "ai_calls": "1× Chat Completions per run",
        "model": "OPENAI_MODEL (default gpt-4o-mini); ChatOpenAI + OPENAI_REQUEST_TIMEOUT (app.box_workflow._get_llm)",
        "mode": "Always invokes LLM for RELEVANT / NOT_RELEVANT",
    },
    "topic_identification": {
        "ai_calls": "0 or 1× Chat Completions",
        "model": "When used: OPENAI_MODEL / gpt-4o-mini via app.ai_topic_classifier.classify_with_ai (ChatOpenAI)",
        "mode": "Keyword path if non-general topic with confidence ≥ 0.7; else classify_with_ai (JSON: topic, keywords, situation_label)",
    },
    "level_resolution": {
        "ai_calls": "0 or 1× Chat Completions",
        "model": "When used: OPENAI_MODEL / gpt-4o-mini (app.box_workflow._infer_level_with_llm → _get_llm)",
        "mode": "If prompt contains A1–C2 → explicit level, no LLM; else one inference call from boxes/words context",
    },
    "decide_retrieval_route": {
        "ai_calls": "none",
        "model": "n/a",
        "mode": "Pure Python from topic, confidence, prompt keywords",
    },
    "db_retrieval_attempt": {
        "ai_calls": "none",
        "model": "n/a",
        "mode": "SQLite retrieve_candidates",
    },
    "retrieval_quality_assessment": {
        "ai_calls": "none",
        "model": "n/a",
        "mode": "Counts primary-phase DB rows in _db_entries",
    },
    "ai_word_generation": {
        "ai_calls": "0 or 1× Responses API (when node runs)",
        "model": "OPENAI_WORD_GEN_MODEL (default gpt-4o-mini); client.responses.create + strict json_schema",
        "mode": "When reached: distinct langs both in {en,de,es,fr,it,pt,nl,pl}; skipped if db_first+20 strong DB. Timeout WORD_GEN_TIMEOUT (default 18s).",
    },
    "result_merge_and_filter": {
        "ai_calls": "none",
        "model": "n/a",
        "mode": "Merge/dedupe by retrieval_route; no LLM",
    },
    "box_creation_finalize": {
        "ai_calls": "none",
        "model": "n/a",
        "mode": "Build boxes + persist_ai_fallback_pairs list for BackgroundTasks",
    },
    "async_persist_ai_words": {
        "ai_calls": "none",
        "model": "n/a",
        "mode": "Sets async_persist_queued; SQLite persist runs after HTTP in main.py",
    },
}


def _introspect_ai_usage(fn) -> dict[str, str]:
    """Return AI usage line for debug cards: explicit table first, then source heuristics."""
    base = {
        "ai_calls": "none",
        "model": "n/a",
        "mode": "deterministic",
    }
    if fn is None:
        base["mode"] = "unknown (no callable)"
        return base
    name = getattr(fn, "__name__", "")
    if name in _DEBUG_NODE_AI_METADATA:
        row = _DEBUG_NODE_AI_METADATA[name]
        return {
            "ai_calls": row["ai_calls"],
            "model": row["model"],
            "mode": row["mode"],
        }
    try:
        src = inspect.getsource(fn)
    except OSError:
        src = ""
    uses_llm = "_get_llm(" in src or "ChatOpenAI(" in src
    if not uses_llm:
        return base
    model_desc = "OPENAI_MODEL (see app.box_workflow._get_llm)"
    try:
        from app import box_workflow as _bw  # type: ignore

        if hasattr(_bw, "_get_llm"):
            llm_src = inspect.getsource(_bw._get_llm)
            marker = 'OPENAI_MODEL", "'
            idx = llm_src.find(marker)
            if idx != -1:
                start = idx + len(marker)
                end = llm_src.find('"', start)
                if end != -1:
                    model_desc = f"OPENAI_MODEL, default {llm_src[start:end]}"
    except Exception:
        pass
    return {
        "ai_calls": "see source (ChatOpenAI)",
        "model": model_desc,
        "mode": "invokes _get_llm or ChatOpenAI in this callable",
    }


def _node_purpose(fn) -> str:
    """One short sentence from docstring. Structural only."""
    doc = inspect.getdoc(fn) or getattr(fn, "__doc__", "")
    if not doc:
        return "(no description)"
    first = doc.strip().split("\n")[0].strip()
    return first[:100] + ("..." if len(first) > 100 else "")


def _node_source(fn) -> str:
    """Relative path to source file or empty."""
    try:
        mod = inspect.getmodule(fn)
        fpath = inspect.getfile(fn) if hasattr(fn, "__code__") else getattr(mod, "__file__", "")
        if fpath:
            return os.path.relpath(fpath, os.getcwd()) if os.path.isabs(fpath) else fpath
    except (TypeError, ValueError):
        pass
    return ""


def _format_flow_overview(flow_order: list[str]) -> str:
    """Flow section: numbered steps in execution order, clear arrows."""
    step_labels = {
        "relevance_check": "1× Chat Completions: RELEVANT / NOT_RELEVANT",
        "topic_identification": "Keywords (no LLM) or 1× Chat Completions (ai_topic_classifier)",
        "decide_retrieval_route": "db_first | ai_first | mixed (no LLM)",
        "level_resolution": "CEFR from prompt (no LLM) or 1× Chat Completions infer",
        "db_retrieval_attempt": "SQLite only",
        "retrieval_quality_assessment": "Count primary DB rows (no LLM)",
        "ai_word_generation": "0–1× Responses API (branch); WORD_GEN_TIMEOUT default 18s",
        "result_merge_and_filter": "Merge DB+AI (no LLM)",
        "box_creation_finalize": "Build boxes + persist queue (no LLM)",
        "async_persist_ai_words": "Flag queue; SQLite after HTTP response",
    }
    lines = []
    lines.append("1. Request enters workflow")
    lines.append("   -> " + (flow_order[0] if flow_order else "(entry)"))
    for i, name in enumerate(flow_order):
        num = i + 2
        label = step_labels.get(name, name)
        lines.append(f"{num}. {label}")
        nxt = flow_order[i + 1] if i + 1 < len(flow_order) else "end"
        if name == "retrieval_quality_assessment":
            nxt = "ai_word_generation OR merge (branch)"
        lines.append("   -> " + nxt)
    return "\n".join(lines)


# Display names for graph overview (internal node names -> diagram label)
_DEBUG_NODE_DISPLAY_NAMES = {
    "decide_retrieval_route": "route",
    "db_retrieval_attempt": "db_retrieval",
    "retrieval_quality_assessment": "db_quality",
    "ai_word_generation": "ai_words",
    "result_merge_and_filter": "merge",
    "box_creation_finalize": "box_build",
    "async_persist_ai_words": "persist_queue",
}

def _format_graph_overview(flow_order: list[str]) -> str:
    """Compact one-line graph view: [Start] -> [node] -> ... -> [End]."""
    if not flow_order:
        return "(no user-defined nodes in flow)"
    parts = ["[Start]"]
    for name in flow_order:
        display = _DEBUG_NODE_DISPLAY_NAMES.get(name, name)
        parts.append(f"[{display}]")
    parts.append("[End]")
    return " -> ".join(parts)


def _format_node_card(
    step: int,
    name: str,
    runnable,
    hands_off: list[str],
) -> str:
    """One node block: role, purpose, consumes, produces, hands off to."""
    fn = _introspect_node_callable(runnable)
    role = _DEBUG_NODE_ROLES.get(name, "node")
    purpose = _node_purpose(fn) if fn else "(unknown)"
    source = _node_source(fn) if fn else ""
    io = _DEBUG_NODE_IO.get(name, {})
    consumes = io.get("consumes", ["(inferred from state)"])
    produces = io.get("produces", ["(inferred from state)"])
    ai_info = _introspect_ai_usage(fn)
    lines = []
    lines.append(f"[{step}] {name}")
    lines.append(f"  Role: {role}")
    lines.append(f"  Purpose: {purpose}")
    lines.append("  Type: function node")
    if fn:
        lines.append(f"  Function: {getattr(fn, '__name__', repr(fn))}()")
    if source:
        lines.append(f"  Source: {source}")
    if ai_info:
        lines.append("  AI usage:")
        lines.append(f"    - AI calls: {ai_info.get('ai_calls', 'unknown')}")
        lines.append(f"    - Model: {ai_info.get('model', 'unknown')}")
        lines.append(f"    - Mode: {ai_info.get('mode', 'unknown')}")
    lines.append("  Consumes:")
    for c in consumes:
        lines.append(f"    - {c}")
    lines.append("  Produces:")
    for p in produces:
        lines.append(f"    - {p}")
    lines.append("  Hands off to: " + ", ".join(hands_off) if hands_off else "  Hands off to: (none)")
    return "\n".join(lines)


def _format_state_summary() -> str:
    """State keys grouped by category."""
    lines = []
    lines.append("  Request fields:")
    for k in _DEBUG_STATE_REQUEST:
        lines.append(f"    - {k}")
    lines.append("  Workflow fields:")
    for k in _DEBUG_STATE_WORKFLOW:
        lines.append(f"    - {k}")
    lines.append("  Response fields:")
    for k in _DEBUG_STATE_RESPONSE:
        lines.append(f"    - {k}")
    lines.append("  Internal / pipeline (API omits some):")
    lines.append("    - _db_entries, _db_stats, _ai_validated, _ai_generation_attempted")
    lines.append("    - _final_merged_rows, persist_ai_fallback_pairs")
    return "\n".join(lines)


def _build_ascii_debug_content(drawable, compiled_graph) -> str:
    """
    Workflow debug view in execution order: flow overview, node cards (consumes/produces), state summary.
    Designed for product/debug readers used to n8n/Flowise-style flows.
    """
    flow_order = _get_flow_order(drawable, compiled_graph)
    hands_off_map = _get_hands_off(drawable, flow_order)
    builder = getattr(compiled_graph, "builder", None)
    node_specs = getattr(builder, "nodes", {}) if builder else {}

    sections = []
    sep = "=" * 60
    sections.append(sep)
    sections.append("  LinguAI LangGraph – workflow debug view")
    sections.append(sep)

    # Compact graph overview for quick visual scan
    sections.append("")
    sections.append("GRAPH OVERVIEW")
    sections.append("-" * 60)
    sections.append(_format_graph_overview(flow_order))
    sections.append("")
    sections.append("  Note: builder lists every node; ai_word_generation runs only when the branch")
    sections.append("  from retrieval_quality_assessment routes there (see Hands off / Mermaid).")

    # Flow overview (execution order)
    sections.append("")
    sections.append("FLOW OVERVIEW")
    sections.append("-" * 60)
    sections.append(_format_flow_overview(flow_order))

    # Node details in flow order
    sections.append("")
    sections.append("NODE DETAILS")
    sections.append("-" * 60)
    for step, name in enumerate(flow_order, start=1):
        spec = node_specs.get(name)
        runnable = getattr(spec, "runnable", None) if spec else None
        hands_off = hands_off_map.get(name, [])
        sections.append("")
        sections.append(_format_node_card(step, name, runnable, hands_off))
    if not flow_order:
        sections.append("  (no user-defined nodes in flow)")

    # State summary (grouped)
    sections.append("")
    sections.append("STATE SUMMARY")
    sections.append("-" * 60)
    sections.append(_format_state_summary())
    sections.append("")
    sections.append("POST-RESPONSE (FastAPI BackgroundTasks)")
    sections.append("-" * 60)
    sections.append(
        "  - After JSON is returned: main._run_persist_ai_fallback → vocab_store.persist_ai_fallback_pairs"
    )
    sections.append(
        "  - INSERT OR IGNORE; source_type=ai_fallback; only pairs actually shown to the user (from persist_ai_fallback_pairs)."
    )
    sections.append(
        "  - Limitation: in-process task; may not finish if the process exits immediately (e.g. some serverless)."
    )
    sections.append("")
    return "\n".join(sections)


def _build_app_flow_mermaid() -> str:
    """Matches app/graph.py: branch skips ai_word_generation when DB sufficient or wrong lang pair."""
    return """flowchart TB
  subgraph app[" App flow "]
    A[POST /generate-boxes] --> B[Pydantic validation]
    B --> C[Logging]
    C --> D[Idempotency]
    D --> WFLOW[LangGraph invoke]
    WFLOW --> E[Build JSON response]
    E --> F[Return response]
    F --> BG[BackgroundTasks: persist_ai_fallback_pairs]
  end
  subgraph workflow[" Box workflow same as graph.py "]
    W0["request_understanding<br/>1x Chat Completions (structured intent)"] --> W1{relevant?}
    W1 -->|no (or low confidence)| W2["relevance_check<br/>1x Chat Completions (legacy gate)"]
    W1 -->|yes (high confidence)| W3["topic_identification<br/>keywords or 0-1x Chat Completions"]
    W2 --> W3
    W3 --> W3b[decide_retrieval_route]
    W3b --> W4["level_resolution<br/>regex CEFR or 0-1x Chat Completions"]
    W4 --> W5[db_retrieval_attempt]
    W5 --> W6[retrieval_quality_assessment]
    W6 --> W6b{Run ai_word_generation?}
    W6b -->|Yes EN-DE or EN-ES and not db_first with 20 strong primary| W7["ai_word_generation Responses API JSON"]
    W6b -->|No wrong pair or DB enough| W8[result_merge_and_filter]
    W7 --> W8
    W8 --> W9[box_creation_finalize]
    W9 --> W10[async_persist_ai_words]
    W10 --> WEND2[END]
  end
  D --> WFLOW
  WFLOW --> E
"""


def _render_mermaid_html(mermaid_src: str, title: str = "Graph") -> str:
    """Return minimal HTML page that renders the given Mermaid source in the browser."""
    escaped = html.escape(mermaid_src)
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>{html.escape(title)}</title>
</head>
<body>
  <div class="mermaid">{escaped}</div>
  <script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
  <script>mermaid.initialize({{ startOnLoad: true }});</script>
</body>
</html>"""


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------


@app.on_event("startup")
def startup():
    global graph
    graph = create_graph()


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@app.get("/")
def health():
    """Health check for load balancers and monitoring."""
    return {"status": "ok", "service": "linguai-langgraph"}


def _request_summary(req: GenerateBoxesRequest) -> dict:
    """Summary stats for logging (privacy-conscious)."""
    boxes = req.existingBoxes
    total_words = sum(len(b.words) for b in boxes)
    completions = [b.completionPercent for b in boxes]
    avg_completion = sum(completions) / len(completions) if completions else 0.0
    high_completion_count = sum(1 for c in completions if c >= 50.0)
    return {
        "existing_box_count": len(boxes),
        "total_word_count": total_words,
        "avg_completion": round(avg_completion, 1),
        "boxes_with_high_completion": high_completion_count,
    }


def _request_to_workflow_state(req: GenerateBoxesRequest) -> dict:
    """Map API request to workflow state dict for graph invocation. Words nested under each box."""
    return {
        "prompt": req.prompt,
        "default_language": req.defaultLanguage,
        "target_language": req.targetLanguage,
        "existing_boxes": [
            {
                "boxId": b.boxId,
                "boxName": b.boxName,
                "completionPercent": b.completionPercent,
                "words": [{"default": w.default, "target": w.target} for w in b.words],
            }
            for b in req.existingBoxes
        ],
        "request_id": req.requestId,
        "customer_id": req.customerId,
    }


def _workflow_state_to_response(state: dict) -> GenerateBoxesResponse:
    """Map final workflow state to API response."""
    return GenerateBoxesResponse(
        requestId=state.get("request_id", ""),
        defaultLanguage=state.get("default_language", ""),
        targetLanguage=state.get("target_language", ""),
        status=state.get("status", "insufficient_confidence"),
        userMessage=state.get("user_message") or state.get("relevance_user_message") or None,
        boxes=state.get("boxes", []),
        level=state.get("level") or None,
        levelSource=state.get("level_source") or None,
        topic=state.get("topic") or None,
        topicSource=state.get("topic_source") or None,
        topicConfidence=state.get("topic_confidence"),
        topicReason=state.get("topic_reason") or None,
        topicKeywords=state.get("topic_keywords"),
        situationLabel=state.get("situation_label") or None,
        reachedBoxCreation=state.get("reached_box_creation") is True,
        candidate_debug=state.get("candidate_debug"),
    )


def _run_persist_ai_fallback(
    default_lang: str,
    target_lang: str,
    pairs: list,
    level: Optional[str],
    topic: Optional[str],
    request_id: str,
) -> None:
    """Background task: persist returned AI pairs (INSERT OR IGNORE)."""
    if not pairs:
        return
    tpl = [(p.get("default", ""), p.get("target", "")) for p in pairs]
    n = persist_ai_fallback_pairs(
        default_lang,
        target_lang,
        tpl,
        level=level,
        topic=topic,
    )
    logger.info(
        "background_persist_ai id=%s inserted=%d",
        request_id,
        n,
        extra={"request_id": request_id},
    )


@app.post("/generate-boxes", response_model=GenerateBoxesResponse)
def generate_boxes(req: GenerateBoxesRequest, background_tasks: BackgroundTasks) -> GenerateBoxesResponse:
    """
    Generate one box of words: relevance -> level resolution (explicit or inferred) -> topic -> box placeholder.
    Returns structured status, levelSource, topic, reachedBoxCreation, and optional userMessage.
    """
    summary = _request_summary(req)
    logger.info(
        "request_received requestId=%s prompt_length=%d defaultLanguage=%s targetLanguage=%s existing_box_count=%d total_word_count=%d avg_completion=%s boxes_high_completion=%d",
        req.requestId,
        len(req.prompt),
        req.defaultLanguage,
        req.targetLanguage,
        summary["existing_box_count"],
        summary["total_word_count"],
        summary["avg_completion"],
        summary["boxes_with_high_completion"],
        extra={"request_id": req.requestId, **summary},
    )
    if DEBUG:
        logger.debug("request_payload requestId=%s body=%s", req.requestId, req.model_dump(mode="json"))
    _log_request_response("request", req.model_dump(mode="json"))

    try:
        cached = _check_idempotency(req)
    except HTTPException as e:
        if e.status_code == 409:
            _log_request_response("response", {"status_code": 409, "detail": str(e.detail)})
        raise

    if cached is not None:
        logger.info("idempotency_hit customerId=%s requestId=%s", req.customerId, req.requestId)
        _log_request_response("response", cached.model_dump(mode="json"))
        return cached

    try:
        initial = _request_to_workflow_state(req)
        final = graph.invoke(initial)
        to_persist = list(final.get("persist_ai_fallback_pairs") or [])
        if to_persist:
            background_tasks.add_task(
                _run_persist_ai_fallback,
                req.defaultLanguage.lower(),
                req.targetLanguage.lower(),
                to_persist,
                final.get("level"),
                final.get("topic"),
                req.requestId,
            )
        resp = _workflow_state_to_response(final)
        logger.info(
            "request_complete requestId=%s status=%s level=%s levelSource=%s topic=%s reachedBoxCreation=%s",
            req.requestId,
            resp.status,
            resp.level,
            resp.levelSource,
            resp.topic,
            resp.reachedBoxCreation,
            extra={
                "request_id": req.requestId,
                "status": resp.status,
                "level": resp.level,
                "level_source": resp.levelSource,
                "topic": resp.topic,
                "reached_box_creation": resp.reachedBoxCreation,
            },
        )
        log_evaluation_run(
            req.requestId,
            resp.status,
            resp.topic,
            resp.level,
            resp.levelSource,
            resp.reachedBoxCreation,
            debug=DEBUG,
        )
        if resp.status == STATUS_GENERATED_PLACEHOLDER:
            request_hash = _request_hash(req)
            idempotency_set(req.customerId, req.requestId, request_hash, resp.model_dump_json())
        _log_request_response("response", resp.model_dump(mode="json"))
        return resp
    except Exception:
        logger.exception("generate_boxes workflow failed requestId=%s", req.requestId)
        fallback = GenerateBoxesResponse(
            requestId=req.requestId,
            defaultLanguage=req.defaultLanguage,
            targetLanguage=req.targetLanguage,
            status="insufficient_confidence",
            userMessage="Something went wrong. Please try again.",
            boxes=[],
            reachedBoxCreation=False,
        )
        _log_request_response("response", fallback.model_dump(mode="json"))
        return fallback


# ---------------------------------------------------------------------------
# Debug endpoints (only when DEBUG=true)
# ---------------------------------------------------------------------------


@app.get("/debug/graph/ascii", response_class=PlainTextResponse)
def debug_graph_ascii():
    """
    LangGraph/agent workflow debug view: topology + node details (function, source, doc, state keys).
    Plain text. Development only; disabled when DEBUG is not set.
    """
    if not DEBUG:
        return PlainTextResponse(
            "Debug endpoints are disabled. Set DEBUG=true to enable.",
            status_code=404,
        )
    drawable = _get_drawable_graph()
    if drawable is None:
        return PlainTextResponse(
            "Graph not available (not built or get_graph failed).",
            status_code=503,
        )
    content = _build_ascii_debug_content(drawable, graph)
    return PlainTextResponse(content)


@app.get("/debug/graph/render", response_class=HTMLResponse)
def debug_graph_render():
    """
    Full app flow diagram: API -> validation -> logging -> idempotency -> workflow -> response.
    Renders in browser via Mermaid. Development only.
    """
    if not DEBUG:
        return HTMLResponse(
            "<!DOCTYPE html><html><body><p>Debug endpoints are disabled. Set DEBUG=true to enable.</p></body></html>",
            status_code=404,
        )
    mermaid_src = _build_app_flow_mermaid()
    return HTMLResponse(_render_mermaid_html(mermaid_src, title="LinguAI app flow"))


if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", "2024"))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=True)
