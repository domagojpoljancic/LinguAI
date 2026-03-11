"""Pydantic models for API request/response contracts."""

from typing import List, Optional

from pydantic import BaseModel, Field


# ---- Nested types for existing data (request) ----

class ExistingBox(BaseModel):
    """A box the customer already has. completionPercent supports level inference."""

    boxId: str
    boxName: str
    completionPercent: float = Field(default=0.0, ge=0.0, le=100.0)


class ExistingWord(BaseModel):
    """A word pair the customer already has (in existing boxes)."""

    default: str
    target: str


# ---- Request: POST /generate-boxes ----

class GenerateBoxesRequest(BaseModel):
    """Request body for generating one box of words."""

    requestId: str
    customerId: str
    prompt: str
    defaultLanguage: str
    targetLanguage: str
    existingBoxes: List[ExistingBox] = Field(default_factory=list)
    existingWords: List[ExistingWord] = Field(default_factory=list)


# ---- Nested types for generated data (response) ----

class WordPair(BaseModel):
    """A generated default/target word pair (for response boxes)."""

    default: str
    target: str


class GeneratedBox(BaseModel):
    """One generated box with words. Used in response; empty list for now."""

    boxId: str
    boxName: str
    words: List[WordPair] = Field(default_factory=list)


# ---- Response: POST /generate-boxes ----

# Outcome codes for the app to map to UI / behavior.
STATUS_IRRELEVANT_REQUEST = "irrelevant_request"
STATUS_INSUFFICIENT_CONFIDENCE = "insufficient_confidence"
STATUS_GENERATED_PLACEHOLDER = "generated_placeholder"


class GenerateBoxesResponse(BaseModel):
    """Response for generate-boxes. status + userMessage let the app handle outcomes."""

    requestId: str
    defaultLanguage: str
    targetLanguage: str
    status: str
    userMessage: Optional[str] = None
    boxes: List[GeneratedBox] = Field(default_factory=list)
    # Clarify level and topic for app / box-creation step
    level: Optional[str] = None  # CEFR when resolved (explicit or inferred)
    levelSource: Optional[str] = None  # "explicit" | "inferred"
    topic: Optional[str] = None  # identified theme for the box
    reachedBoxCreation: bool = False  # True when workflow reached box-creation placeholder
