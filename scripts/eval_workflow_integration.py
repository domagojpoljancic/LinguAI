#!/usr/bin/env python3
"""
End-to-end workflow evaluation: same graph as POST /generate-boxes.

Reports per prompt:
  retrieval_route, db_candidate_count, db_strong_candidate_count,
  ai_candidate_count, ai_validated_count, final count, strategies,
  db_fallback_used, ai_supplement_used, sample words.

Usage:
  cd repo && PYTHONPATH=. python3 scripts/eval_workflow_integration.py

Requires OPENAI_API_KEY for full AI paths; without it, DB-fallback behavior is still visible.
"""

from __future__ import annotations

import json
import os
import sys
import uuid

# Repo root on path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def main() -> None:
    from app.graph import create_graph

    graph = create_graph()

    cases = [
        ("A1 restaurant words in German", "en", "de"),
        ("B1 travel vocabulary in Spanish", "en", "es"),
        ("football words in German", "en", "de"),
        ("basketball vocabulary in Spanish", "en", "es"),
        ("words for going to the gym", "en", "de"),
        ("phrases for talking to a landlord", "en", "de"),
        ("words for labor with my wife", "en", "de"),
        ("phrases for the airport", "en", "es"),
        ("vocabulary for a pharmacy visit", "en", "es"),
        ("business small talk in German", "en", "de"),
    ]

    print("=" * 72)
    print("Box workflow integration eval (graph.invoke)")
    print("=" * 72)

    for prompt, dl, tl in cases:
        rid = f"eval-{uuid.uuid4().hex[:8]}"
        state = graph.invoke(
            {
                "prompt": prompt,
                "default_language": dl,
                "target_language": tl,
                "existing_boxes": [],
                "request_id": rid,
                "customer_id": "eval-customer",
            }
        )
        if not state.get("is_relevant", True):
            print(f"\n--- IRRELEVANT: {prompt[:50]}...")
            continue

        words = []
        for box in state.get("boxes") or []:
            words.extend(box.get("words") or [])
        samples = [f"{w.get('default')}/{w.get('target')}" for w in words[:8]]

        report = {
            "prompt": prompt[:60],
            "lang": f"{dl}->{tl}",
            "route": state.get("retrieval_route"),
            "route_reason": (state.get("retrieval_route_reason") or "")[:70],
            "db_candidate_count": state.get("db_candidate_count"),
            "db_strong_candidate_count": state.get("db_strong_candidate_count"),
            "ai_raw": state.get("ai_candidate_count"),
            "ai_validated": state.get("ai_validated_count"),
            "ai_failure": state.get("ai_failure_reason") or "",
            "final_count": state.get("final_candidate_count"),
            "mix_strategy": state.get("final_mix_strategy"),
            "db_fallback_used": state.get("db_fallback_used"),
            "ai_supplement_used": state.get("ai_supplement_used"),
            "persist_queued": len(state.get("persist_ai_fallback_pairs") or []),
            "samples": samples,
        }
        print("\n" + json.dumps(report, indent=2, ensure_ascii=False))

    print("\n" + "=" * 72)
    print("Persistence: returned AI pairs are listed in persist_ai_fallback_pairs;")
    print("main.py schedules persist_ai_fallback_pairs() via BackgroundTasks after HTTP response.")
    print("Re-run the same prompt after persist to see DB counts increase where topics align.")
    print("=" * 72)


if __name__ == "__main__":
    main()
