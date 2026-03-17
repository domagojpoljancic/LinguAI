#!/usr/bin/env python3
"""
Evaluate AI fallback word generation in isolation (no full box workflow merge).

Requires OPENAI_API_KEY. Uses topic_identification + decide_retrieval_route to populate
routing and topic metadata, then app.ai_word_generator.generate_word_pairs.

Usage:
  python scripts/eval_ai_word_generation.py
  python scripts/eval_ai_word_generation.py --json
"""

from __future__ import annotations

import argparse
import json
import os
import sys

# Ensure project root on path
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from dotenv import load_dotenv

load_dotenv()

CASES = [
    ("football words in German", "en", "de", "B1"),
    ("basketball vocabulary in Spanish", "en", "es", "B1"),
    ("words for going to the gym", "en", "de", "A2"),
    ("phrases for talking to a landlord", "en", "de", "B1"),
    ("business small talk in German", "en", "de", "B1"),
]


def run_case(prompt: str, default_lang: str, target_lang: str, level: str) -> dict:
    from app.box_workflow import decide_retrieval_route, topic_identification
    from app.ai_word_generator import generate_word_pairs
    from app.prompts.word_generation import WordGenerationContext

    rid = f"eval-{hash(prompt) % 10**8}"
    state = {
        "request_id": rid,
        "prompt": prompt,
        "default_language": default_lang,
        "target_language": target_lang,
        "existing_boxes": [],
    }
    state.update(topic_identification(state))
    state.update(decide_retrieval_route(state))

    ctx = WordGenerationContext(
        user_prompt=prompt,
        default_language=default_lang,
        target_language=target_lang,
        level=level,
        topic=state.get("topic") or "general",
        topic_keywords=list(state.get("topic_keywords") or []),
        situation_label=state.get("situation_label") or "",
        topic_reason=state.get("topic_reason") or "",
        retrieval_route=state.get("retrieval_route") or "mixed",
        existing_default_words=[],
        existing_word_pairs=[],
        max_pairs=22,
    )
    result = generate_word_pairs(ctx, request_id=rid)

    samples = [
        {"default": p.default, "target": p.target, "confidence": round(p.confidence, 3)}
        for p in result.validated[:8]
    ]
    useful = (
        len(result.validated) >= 5
        and result.ai_failure_reason is None
    ) or (
        len(result.validated) >= 3
        and prompt.lower().split()[0] in ("football", "basketball", "gym", "landlord")
    )

    return {
        "prompt": prompt,
        "retrieval_route": state.get("retrieval_route"),
        "route_reason": state.get("retrieval_route_reason"),
        "topic": state.get("topic"),
        "raw_generated_count": result.raw_count,
        "validated_count": result.validated_count,
        "filtered_count": result.filtered_count,
        "sample_words": samples,
        "ai_failure_reason": result.ai_failure_reason,
        "looks_useful": bool(result.validated) and (useful or len(result.validated) >= 4),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true", help="Print JSON only")
    args = ap.parse_args()
    if not os.environ.get("OPENAI_API_KEY"):
        print("OPENAI_API_KEY required", file=sys.stderr)
        return 1

    rows = []
    for prompt, dl, tl, lvl in CASES:
        row = run_case(prompt, dl, tl, lvl)
        rows.append(row)
        if not args.json:
            print(f"\n{'='*60}\nPrompt: {row['prompt']!r}")
            print(f"  route: {row['retrieval_route']} ({row['route_reason']})")
            print(f"  topic: {row['topic']}")
            print(f"  raw: {row['raw_generated_count']}  validated: {row['validated_count']}  filtered: {row['filtered_count']}")
            if row["ai_failure_reason"]:
                print(f"  failure: {row['ai_failure_reason']}")
            print(f"  samples: {row['sample_words']}")
            print(f"  looks_useful: {row['looks_useful']}")

    out_path = os.path.join(ROOT, "logs", "eval_ai_word_generation.json")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w") as f:
        json.dump(rows, f, indent=2)
    if not args.json:
        print(f"\nWrote {out_path}")
    else:
        print(json.dumps(rows, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
