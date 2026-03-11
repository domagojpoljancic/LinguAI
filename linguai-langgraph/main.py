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


def _get_state_keys_from_schema() -> list[str]:
    """Return state keys from BoxWorkflowState (TypedDict) for debug docs."""
    return list(getattr(BoxWorkflowState, "__annotations__", {}).keys())


def _introspect_node_callable(runnable) -> Optional[object]:
    """Unwrap runnable to underlying callable if possible (e.g. RunnableLambda.func)."""
    if runnable is None:
        return None
    fn = getattr(runnable, "func", runnable)
    return fn if callable(fn) else runnable


def _node_detail_lines(name: str, runnable) -> list[str]:
    """Build readable node detail lines for ASCII debug. Uses introspection; best-effort."""
    lines = []
    fn = _introspect_node_callable(runnable)
    if fn is None:
        lines.append(f"  [{name}]")
        lines.append("    type: (unknown)")
        return lines
    lines.append(f"  [{name}]")
    lines.append("    type: function node")
    lines.append(f"    function: {getattr(fn, '__name__', repr(fn))}")
    try:
        mod = inspect.getmodule(fn)
        fpath = inspect.getfile(fn) if hasattr(fn, "__code__") else getattr(mod, "__file__", "")
        if fpath:
            rel = os.path.relpath(fpath, os.getcwd()) if os.path.isabs(fpath) else fpath
            lines.append(f"    source: {rel}")
    except (TypeError, ValueError):
        pass
    doc = inspect.getdoc(fn) or getattr(fn, "__doc__", "")
    if doc:
        summary = doc.strip().split("\n")[0].strip()
        if len(summary) > 80:
            summary = summary[:77] + "..."
        lines.append(f"    doc: {summary}")
    lines.append("    state (BoxWorkflowState): " + ", ".join(_get_state_keys_from_schema()))
    lines.append("    updates (this node): response (derived from node return)")
    return lines


def _build_ascii_debug_content(drawable, compiled_graph) -> str:
    """
    Build plain-text debug view: topology (ASCII or simple flow) + node details + state summary.
    Uses compiled graph's builder.nodes for introspection when available.
    """
    sections = []
    sections.append("=" * 60)
    sections.append("  LinguAI LangGraph – workflow debug view")
    sections.append("=" * 60)

    # Flow / topology
    sections.append("\n--- Flow ---\n")
    try:
        flow_text = drawable.draw_ascii()
        sections.append(flow_text)
    except ImportError:
        parts = []
        for edge in getattr(drawable, "edges", []):
            src = getattr(edge, "source", None) or (edge[0] if isinstance(edge, (list, tuple)) else "?")
            tgt = getattr(edge, "target", None) or (edge[1] if isinstance(edge, (list, tuple)) and len(edge) > 1 else "?")
            parts.append(f"  {src} --> {tgt}")
        sections.append("\n".join(parts) if parts else "  (no edges)")

    # Node details
    sections.append("\n--- Node details ---\n")
    builder = getattr(compiled_graph, "builder", None)
    node_specs = getattr(builder, "nodes", {}) if builder else {}
    for node_name, spec in sorted(node_specs.items()):
        runnable = getattr(spec, "runnable", None)
        sections.extend(_node_detail_lines(node_name, runnable))
        sections.append("")
    if not node_specs:
        sections.append("  (no user-defined nodes; graph may only have __start__ / __end__)")

    # State summary
    sections.append("\n--- State (BoxWorkflowState) ---\n")
    sections.append("  keys: " + ", ".join(_get_state_keys_from_schema()))
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
    W2 -->|yes| W3[level_resolution]
    W3 --> W4{level?}
    W4 -->|no - only if inference failed| WEND2[END]
    W4 -->|yes - explicit or inferred| W5[topic_identification]
    W5 --> W6[box_creation_placeholder]
    W6 --> WEND3[END]
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
