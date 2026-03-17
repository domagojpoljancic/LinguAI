"""
LangGraph definition for the generate-boxes workflow.

Flow:
  relevance_check -> topic_identification -> decide_retrieval_route -> level_resolution
  -> db_retrieval_attempt -> retrieval_quality_assessment
  -> [db_first strong DB & enough? skip AI] else ai_word_generation
  -> result_merge_and_filter -> box_creation_finalize -> async_persist_ai_words -> END

  AI persistence runs in FastAPI BackgroundTasks after the HTTP response (non-blocking).
"""

from langgraph.graph import StateGraph, END

from app.state import BoxWorkflowState
from app.box_workflow import (
    relevance_check,
    level_resolution,
    topic_identification,
    decide_retrieval_route,
    db_retrieval_attempt,
    retrieval_quality_assessment,
    route_after_retrieval_quality,
    ai_word_generation,
    result_merge_and_filter,
    box_creation_finalize,
    async_persist_ai_words,
    route_after_relevance,
)


def create_graph():
    """Build and compile the box-generation workflow graph."""
    graph = StateGraph(BoxWorkflowState)
    graph.add_node("relevance_check", relevance_check)
    graph.add_node("topic_identification", topic_identification)
    graph.add_node("decide_retrieval_route", decide_retrieval_route)
    graph.add_node("level_resolution", level_resolution)
    graph.add_node("db_retrieval_attempt", db_retrieval_attempt)
    graph.add_node("retrieval_quality_assessment", retrieval_quality_assessment)
    graph.add_node("ai_word_generation", ai_word_generation)
    graph.add_node("result_merge_and_filter", result_merge_and_filter)
    graph.add_node("box_creation_finalize", box_creation_finalize)
    graph.add_node("async_persist_ai_words", async_persist_ai_words)

    graph.set_entry_point("relevance_check")
    graph.add_conditional_edges("relevance_check", route_after_relevance)
    graph.add_edge("topic_identification", "decide_retrieval_route")
    graph.add_edge("decide_retrieval_route", "level_resolution")
    graph.add_edge("level_resolution", "db_retrieval_attempt")
    graph.add_edge("db_retrieval_attempt", "retrieval_quality_assessment")
    graph.add_conditional_edges(
        "retrieval_quality_assessment",
        route_after_retrieval_quality,
        {
            "ai_word_generation": "ai_word_generation",
            "result_merge_and_filter": "result_merge_and_filter",
        },
    )
    graph.add_edge("ai_word_generation", "result_merge_and_filter")
    graph.add_edge("result_merge_and_filter", "box_creation_finalize")
    graph.add_edge("box_creation_finalize", "async_persist_ai_words")
    graph.add_edge("async_persist_ai_words", END)

    return graph.compile()
