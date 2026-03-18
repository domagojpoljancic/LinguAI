"""Graph state definitions."""

from typing import Any, Dict, List, TypedDict


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
    retrieval_route: str  # "db_first" | "ai_first" | "mixed"
    retrieval_route_reason: str
    retrieval_route_confidence: float
    # AI word generation + retrieval integration
    ai_used: bool
    ai_candidate_count: int
    ai_validated_count: int
    ai_failure_reason: str
    db_candidate_count: int  # primary + widened pool size from last DB fetch
    db_strong_candidate_count: int  # returned DB rows tagged primary topic
    final_candidate_count: int
    final_mix_strategy: str
    db_fallback_used: bool  # final list relied on DB because AI failed or disallowed
    ai_supplement_used: bool  # any AI pair in final response
    persist_ai_fallback_pairs: List[dict]  # [{default, target}] for BackgroundTasks; not in API JSON
    async_persist_queued: bool
    _ai_generation_attempted: bool  # internal; graph merge

    # ---- Internal pipeline keys (must be preserved across LangGraph nodes) ----
    # LangGraph retains only keys declared in the State schema. These are produced/consumed
    # by node functions below; if missing from the TypedDict they get dropped and downstream
    # nodes will see empty candidates.
    _db_entries: List[Dict[str, Any]]  # [{default, target, phase}, ...] from SQLite retrieve_candidates
    _db_stats: Dict[str, Any]  # raw retrieve_candidates stats (primary/widened counts, etc.)
    _ai_validated: List[Dict[str, Any]]  # [{default, target, confidence}, ...] from ai_word_generation
    _final_merged_rows: List[Dict[str, Any]]  # [{default, target, source}, ...] from result_merge_and_filter

    boxes: List[dict]
    user_message: str
    reached_box_creation: bool
