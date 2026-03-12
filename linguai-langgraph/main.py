"""FastAPI server for LinguAI LangGraph backend."""

import html
import inspect
import logging
import os
from typing import Optional

from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.responses import HTMLResponse, PlainTextResponse

from app.config import DEBUG
from app.graph import create_graph
from app.schemas import (
    GenerateBoxesRequest,
    GenerateBoxesResponse,
)
from app.state import BoxWorkflowState

# Load env first so optional LangSmith tracing works when set (LANGCHAIN_TRACING_V2=true, LANGCHAIN_API_KEY).
load_dotenv()

# Structured logging: readable in local dev; request_id in extras for filtering
logging.basicConfig(
    level=logging.DEBUG if DEBUG else logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

app = FastAPI(title="LinguAI LangGraph", version="0.1.0")
graph = None


# ---------------------------------------------------------------------------
# Idempotency (placeholder)
# ---------------------------------------------------------------------------


def check_idempotency(request_id: str) -> Optional[GenerateBoxesResponse]:
    """
    Placeholder for persistence-backed idempotency.
    When implemented: lookup request_id in store; if found return cached response, else return None.
    """
    # TODO: idempotency store lookup; return cached response if request_id already processed
    return None


# ---------------------------------------------------------------------------
# Duplicate strategy (placeholder)
# ---------------------------------------------------------------------------
# Future duplicate filtering may be by default word only, or by (default, target) pair.
# No implementation in this step; add filtering here or in a dedicated helper when needed.


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
    "relevance_check": "gate",
    "level_resolution": "enrichment",
    "topic_identification": "preparation",
    "box_creation_placeholder": "placeholder generation",
}
_DEBUG_NODE_IO = {
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
        "produces": ["topic"],
    },
    "box_creation_placeholder": {
        "consumes": ["(full state for response build)"],
        "produces": ["status", "boxes", "user_message", "reached_box_creation"],
    },
}

# State keys grouped for readability (from BoxWorkflowState).
_DEBUG_STATE_REQUEST = ["request_id", "customer_id", "prompt", "default_language", "target_language", "existing_boxes"]
_DEBUG_STATE_WORKFLOW = ["is_relevant", "relevance_user_message", "level", "level_source", "topic", "reached_box_creation"]
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
    "relevance_check": ["topic_identification", "end (if not relevant)"],
    "topic_identification": ["level_resolution"],
    "level_resolution": ["box_creation_placeholder"],
    "box_creation_placeholder": ["end"],
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
        "relevance_check": "Decide if prompt is suitable for vocabulary-box generation",
        "level_resolution": "Resolve or infer learner level (CEFR)",
        "topic_identification": "Identify topic/theme for the box",
        "box_creation_placeholder": "Build placeholder result (no real generation yet)",
    }
    lines = []
    lines.append("1. Request enters workflow")
    lines.append("   -> " + (flow_order[0] if flow_order else "(entry)"))
    for i, name in enumerate(flow_order):
        num = i + 2
        label = step_labels.get(name, name)
        lines.append(f"{num}. {label}")
        lines.append("   -> " + (flow_order[i + 1] if i + 1 < len(flow_order) else "end"))
    return "\n".join(lines)


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
    lines = []
    lines.append(f"[{step}] {name}")
    lines.append(f"  Role: {role}")
    lines.append(f"  Purpose: {purpose}")
    lines.append("  Type: function node")
    if fn:
        lines.append(f"  Function: {getattr(fn, '__name__', repr(fn))}()")
    if source:
        lines.append(f"  Source: {source}")
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
    return "\n".join(sections)


def _build_app_flow_mermaid() -> str:
    """
    Build Mermaid for full app flow and box workflow (boxes carry nested words).
    """
    return """flowchart TB
  subgraph app[" App flow "]
    A[POST /generate-boxes] --> B[Pydantic validation]
    B --> C[Request logging]
    C --> D[Idempotency precheck]
    D --> E[Build response]
    E --> F[JSON response]
  end
  subgraph workflow[" Box workflow "]
    W1[relevance_check] --> W2{relevant?}
    W2 -->|no| WEND1[END]
    W2 -->|yes| W3[topic_identification]
    W3 --> W4[level_resolution]
    W4 --> W5[box_creation_placeholder]
    W5 --> WEND2[END]
  end
  D --> workflow
  workflow --> E
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
        reachedBoxCreation=state.get("reached_box_creation") is True,
    )


@app.post("/generate-boxes", response_model=GenerateBoxesResponse)
def generate_boxes(req: GenerateBoxesRequest) -> GenerateBoxesResponse:
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

    cached = check_idempotency(req.requestId)
    if cached is not None:
        return cached

    try:
        initial = _request_to_workflow_state(req)
        final = graph.invoke(initial)
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
        return resp
    except Exception:
        logger.exception("generate_boxes workflow failed requestId=%s", req.requestId)
        return GenerateBoxesResponse(
            requestId=req.requestId,
            defaultLanguage=req.defaultLanguage,
            targetLanguage=req.targetLanguage,
            status="insufficient_confidence",
            userMessage="Something went wrong. Please try again.",
            boxes=[],
            reachedBoxCreation=False,
        )


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
    uvicorn.run("main:app", host="0.0.0.0", port=2024, reload=True)
