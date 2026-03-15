"""Graph state definitions."""

from typing import List, TypedDict


# ---- Box generation workflow state ----

class BoxWorkflowState(TypedDict, total=False):
    """
    State for the generate-boxes LangGraph workflow.
    Carries request data and step outputs through the pipeline.
    """

    # From request (each box has boxId, boxName, completionPercent, words)
    prompt: str
    default_language: str
    target_language: str
    existing_boxes: List[dict]  # [{boxId, boxName, completionPercent, words: [{default, target}, ...]}, ...]
    request_id: str
    customer_id: str

    # Step outputs
    is_relevant: bool
    relevance_user_message: str
    level: str  # CEFR: A1, A2, B1, B2, C1, C2
    level_source: str  # "explicit" | "inferred" — for response clarity
    status: str  # outcome code for response
    topic: str  # internal topic key (restaurant, travel, health, ... | general | unsupported)
    topic_confidence: float  # 0–1 from topic_identification
    topic_source: str  # "deterministic" | "ai"
    topic_reason: str  # optional reason from AI classifier
    topic_keywords: List[str]  # optional keywords for retrieval/situation (e.g. ["football"], ["labor", "birth"])
    situation_label: str  # short situation description (e.g. "football vocabulary", "at the airport")
    boxes: List[dict]
    user_message: str  # optional user-facing message
    reached_box_creation: bool  # True when box_creation_placeholder ran
