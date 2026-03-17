#!/usr/bin/env python3
"""
Regression eval for generate-boxes workflow. Writes logs/eval_workflow_regression.json.

Rules (FAIL recorded in case):
  - empty boxes + status generated_placeholder
  - ai_first route but AI node ran and ai_validated_count==0 and OPENAI_API_KEY set (heuristic)
  - obvious supported-topic typo cases with empty boxes when API key present

Usage:
  PYTHONPATH=. python3 scripts/eval_workflow_regression.py
"""

from __future__ import annotations

import json
import os
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

LOG_PATH = Path(__file__).resolve().parents[1] / "logs" / "eval_workflow_regression.json"


def _word_count(state: dict) -> int:
    n = 0
    for box in state.get("boxes") or []:
        n += len(box.get("words") or [])
    return n


def _failures(case: dict, state: dict, has_key: bool) -> list[str]:
    fails: list[str] = []
    st = state.get("status") or ""
    wc = _word_count(state)
    if wc == 0 and st == "generated_placeholder":
        fails.append("empty_boxes_with_generated_placeholder")
    route = (state.get("retrieval_route") or "").lower()
    ai_val = int(state.get("ai_validated_count") or 0)
    ai_attempted = bool(state.get("_ai_generation_attempted"))
    if (
        has_key
        and route == "ai_first"
        and ai_attempted
        and ai_val == 0
        and wc == 0
    ):
        fails.append("ai_first_ran_but_no_ai_words_and_empty")
    if has_key and case.get("expect_words") and wc == 0:
        if state.get("is_relevant") is False:
            fails.append("expected_words_but_irrelevant")
        else:
            fails.append("expected_words_but_empty")
    return fails  # without OPENAI_API_KEY, only empty+placeholder is enforced above


def main() -> None:
    from app.graph import create_graph

    os.makedirs(LOG_PATH.parent, exist_ok=True)
    graph = create_graph()
    has_key = bool((os.environ.get("OPENAI_API_KEY") or "").strip())

    cases = [
        # A — broad / AI
        {"prompt": "football words in German", "dl": "en", "tl": "de", "tag": "A_football", "expect_words": True},
        {"prompt": "Football/Soccer words", "dl": "en", "tl": "de", "tag": "A_football_short", "expect_words": True},
        {"prompt": "weather vocabulary B2 German", "dl": "en", "tl": "de", "tag": "A_weather_b2", "expect_words": True},
        {"prompt": "Weather words in B2 German", "dl": "en", "tl": "de", "tag": "A_weather_exact", "expect_words": True},
        {"prompt": "gym words in Spanish", "dl": "en", "tl": "es", "tag": "A_gym_es", "expect_words": True},
        {"prompt": "talking to landlord", "dl": "en", "tl": "de", "tag": "A_landlord", "expect_words": True},
        # B — curated DB-first (en-es has seed)
        {"prompt": "A1 restaurant words in German", "dl": "en", "tl": "de", "tag": "B_restaurant_de", "expect_words": True},
        {"prompt": "B1 travel vocabulary in Spanish", "dl": "en", "tl": "es", "tag": "B_travel_es", "expect_words": True},
        # C — typos
        {"prompt": "Words for restaruant", "dl": "en", "tl": "de", "tag": "C_typo_restaruant", "expect_words": True},
        {"prompt": "travle words", "dl": "en", "tl": "es", "tag": "C_typo_travle", "expect_words": True},
        {"prompt": "busines english words", "dl": "en", "tl": "de", "tag": "C_typo_busines", "expect_words": True},
        # D — edge
        {"prompt": "", "dl": "en", "tl": "de", "tag": "D_empty", "expect_words": False},
        {"prompt": "hello", "dl": "en", "tl": "de", "tag": "D_vague", "expect_words": False},
        {"prompt": "restaurant mix español und English Wörter", "dl": "en", "tl": "es", "tag": "D_mixed_lang", "expect_words": True},
        {"prompt": "words for the airport", "dl": "en", "tl": "es", "tag": "D_no_level", "expect_words": True},
    ]

    results: list[dict] = []
    all_fails: list[str] = []

    for c in cases:
        rid = f"reg-{uuid.uuid4().hex[:10]}"
        try:
            state = graph.invoke(
                {
                    "prompt": c["prompt"],
                    "default_language": c["dl"],
                    "target_language": c["tl"],
                    "existing_boxes": [],
                    "request_id": rid,
                    "customer_id": "eval-regression",
                }
            )
        except Exception as e:
            results.append(
                {
                    "tag": c["tag"],
                    "error": str(e),
                    "failures": ["graph_invoke_exception"],
                }
            )
            all_fails.append(c["tag"])
            continue

        if not state.get("is_relevant", True):
            results.append(
                {
                    "tag": c["tag"],
                    "relevant": False,
                    "status": state.get("status"),
                    "failures": [] if not c.get("expect_words") else ["marked_irrelevant"],
                }
            )
            if c.get("expect_words"):
                all_fails.append(c["tag"])
            continue

        words = []
        for box in state.get("boxes") or []:
            words.extend(box.get("words") or [])
        samples = [f'{w.get("default")}/{w.get("target")}' for w in words[:6]]

        fails = _failures(c, state, has_key)
        rec = {
            "tag": c["tag"],
            "prompt_preview": (c["prompt"] or "")[:55],
            "lang": f'{c["dl"]}->{c["tl"]}',
            "topic": state.get("topic"),
            "route": state.get("retrieval_route"),
            "db_candidates": state.get("db_candidate_count"),
            "db_strong": state.get("db_strong_candidate_count"),
            "ai_validated": state.get("ai_validated_count"),
            "ai_failure": state.get("ai_failure_reason"),
            "final_count": state.get("final_candidate_count"),
            "mix_strategy": state.get("final_mix_strategy"),
            "status": state.get("status"),
            "word_count": len(words),
            "samples": samples,
            "useful": len(words) >= 5,
            "failures": fails,
        }
        results.append(rec)
        all_fails.extend([f"{c['tag']}:{f}" for f in fails])

    out = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "openai_configured": has_key,
        "summary": {
            "cases": len(cases),
            "failure_events": len(all_fails),
            "ok": len(all_fails) == 0,
        },
        "results": results,
    }
    LOG_PATH.write_text(json.dumps(out, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps(out["summary"], indent=2))
    print(f"Wrote {LOG_PATH}")
    if all_fails:
        print("Failures:", all_fails[:20])
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
