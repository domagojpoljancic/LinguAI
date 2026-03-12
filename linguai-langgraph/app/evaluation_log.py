"""
Lightweight evaluation/test run logging for the generate-boxes workflow.

Writes one line per run to logs/evaluation.log when the request looks like an
evaluation case (requestId starts with "req-") or when DEBUG is true.
Format: timestamp | requestId | relevance_passed | topic | level | level_source | steps | outcome
"""

import os
from datetime import datetime, timezone
from typing import Any


EVALUATION_LOG_DIR = "logs"
EVALUATION_LOG_FILE = "evaluation.log"
EVALUATION_REQUEST_PREFIX = "req-"


def _is_evaluation_request(request_id: str) -> bool:
    """True if requestId looks like an evaluation/test case."""
    return (request_id or "").strip().startswith(EVALUATION_REQUEST_PREFIX)


def _should_log_evaluation(request_id: str, debug: bool) -> bool:
    return _is_evaluation_request(request_id) or debug


def _steps_and_outcome(status: str, reached_box_creation: bool) -> tuple[str, str]:
    if status == "irrelevant_request":
        return "relevance_check", status
    if reached_box_creation:
        return (
            "relevance_check -> topic_identification -> level_resolution -> box_creation",
            "ready_for_generation" if status == "generated_placeholder" else status,
        )
    return "relevance_check -> topic_identification -> level_resolution", status


def log_evaluation_run(
    request_id: str,
    status: str,
    topic: str | None,
    level: str | None,
    level_source: str | None,
    reached_box_creation: bool,
    *,
    debug: bool = False,
) -> None:
    """
    Append a one-line evaluation summary to logs/evaluation.log when appropriate.

    Call after workflow completion with the response (or final state) fields.
    """
    if not _should_log_evaluation(request_id or "", debug):
        return
    relevance_passed = status != "irrelevant_request"
    steps, outcome = _steps_and_outcome(status, reached_box_creation)
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    topic_s = (topic or "").strip() or "-"
    level_s = (level or "").strip() or "-"
    level_source_s = (level_source or "").strip() or "-"
    line = f"{ts} | {request_id} | relevance_passed={'Y' if relevance_passed else 'N'} | topic={topic_s} | level={level_s} | level_source={level_source_s} | steps={steps} | outcome={outcome}\n"
    try:
        os.makedirs(EVALUATION_LOG_DIR, exist_ok=True)
        path = os.path.join(EVALUATION_LOG_DIR, EVALUATION_LOG_FILE)
        with open(path, "a", encoding="utf-8") as f:
            f.write(line)
    except OSError:
        pass  # do not fail the request if log write fails
