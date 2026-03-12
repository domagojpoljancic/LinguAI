"""
LangGraph definition for the generate-boxes workflow.

Flow:
  relevance_check (LLM)
    -> [relevant?] no -> END
    -> [relevant?] yes -> topic_identification -> level_resolution -> box_creation_placeholder -> END

  level_resolution always produces a level (explicit or inferred); never ends the flow.
"""

from langgraph.graph import StateGraph, END

from app.state import BoxWorkflowState
from app.box_workflow import (
    relevance_check,
    level_resolution,
    topic_identification,
    box_creation_placeholder,
    route_after_relevance,
)


def create_graph():
    """Build and compile the box-generation workflow graph."""
    graph = StateGraph(BoxWorkflowState)
    graph.add_node("relevance_check", relevance_check)
    graph.add_node("topic_identification", topic_identification)
    graph.add_node("level_resolution", level_resolution)
    graph.add_node("box_creation_placeholder", box_creation_placeholder)

    graph.set_entry_point("relevance_check")
    graph.add_conditional_edges("relevance_check", route_after_relevance)
    graph.add_edge("topic_identification", "level_resolution")
    graph.add_edge("level_resolution", "box_creation_placeholder")
    graph.add_edge("box_creation_placeholder", END)

    return graph.compile()
