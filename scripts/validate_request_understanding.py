#!/usr/bin/env python3
"""
Validate the early request-understanding component only.

This script MUST NOT generate vocabulary words; it only runs:
  app.ai_request_understanding.request_understanding
and prints the structured understanding fields.
"""

from __future__ import annotations

import json
import os
import sys

# Repo root on path (so `import app.*` works when invoked directly)
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.ai_request_understanding import request_understanding


def main() -> int:
    prompts = [
        "Basketball",
        "Weather",
        "Flowers",
        "Cars",
        "Car parts words",
        "Words for flower experts",
        "Flower vocabulary",
        "Weather vocabulary",
        "Car parts words",  # repeat for stability
        "Words for restaruant",
        "talking to landlord",
        "A1 restaurant words in German",
        "B1 travel vocabulary in Spanish",
    ]

    results: list[dict] = []
    for i, p in enumerate(prompts):
        state = {
            "prompt": p,
            "default_language": "en",
            "target_language": "de",
            "existing_boxes": [],
            "request_id": f"ru-{i}",
            "customer_id": "validate_request_understanding",
        }

        patch = request_understanding(state)
        results.append(
            {
                "prompt": p,
                "is_relevant": patch.get("is_relevant"),
                "topic": patch.get("topic"),
                "subtopic": patch.get("subtopic"),
                "situation_label": patch.get("situation_label"),
                "topic_keywords": patch.get("topic_keywords"),
                "route_hint": patch.get("retrieval_route"),
                "level_hint": patch.get("level_hint"),
                "confidence": patch.get("understanding_confidence"),
                "reason": patch.get("understanding_reason"),
            }
        )

    print(json.dumps(results, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

