#!/usr/bin/env python3
"""
Validate flexible-topic behavior: supported vs unsupported prompts.

Requires the API server running (e.g. uvicorn main:app --port 2024).
Set BASE_URL env or uses http://localhost:2024.

Prompts cover:
- Supported: A1 restaurant, B1 travel, etc.
- Unsupported / broader: football, basketball, gym, airport (travel), landlord, labor (health).
"""

import json
import os
import sys

import requests

BASE_URL = os.environ.get("BASE_URL", "http://localhost:2024")

# (prompt, expected_topic_style: "supported" | "unsupported" | "supported_travel" etc., expect_box: bool)
CASES = [
    ("A1 restaurant words in German", "supported", True),
    ("B1 travel vocabulary in Spanish", "supported", True),
    ("football words in German", "unsupported", False),
    ("basketball vocabulary in Spanish", "unsupported", False),
    ("words for going to the gym", "unsupported", False),
    ("phrases for the airport", "supported", True),  # travel
    ("vocabulary for talking to a landlord", "unsupported", False),
    ("words for labor with my wife", "supported", True),  # health
]


def make_body(prompt: str, case_id: int) -> dict:
    return {
        "requestId": f"flex-val-{case_id}-{hash(prompt) % 10**6}",
        "customerId": "flex-validation",
        "prompt": prompt,
        "defaultLanguage": "en",
        "targetLanguage": "de",
        "existingBoxes": [],
    }


def main() -> int:
    endpoint = f"{BASE_URL}/generate-boxes"
    results = []
    for i, (prompt, expected_style, expect_box) in enumerate(CASES):
        print(f"\n[{i+1}] {prompt!r}")
        try:
            r = requests.post(endpoint, json=make_body(prompt, i), timeout=45)
            r.raise_for_status()
            body = r.json()
        except Exception as e:
            print(f"    ERROR: {e}")
            results.append({
                "prompt": prompt,
                "error": str(e),
                "interpreted_topic": None,
                "status": None,
                "box_returned": False,
                "useful": False,
                "honest_fail": False,
            })
            continue

        status = body.get("status", "")
        topic = body.get("topic", "")
        topic_source = body.get("topicSource", "")
        topic_confidence = body.get("topicConfidence")
        topic_reason = body.get("topicReason") or ""
        topic_keywords = body.get("topicKeywords") or []
        situation_label = body.get("situationLabel") or ""
        boxes = body.get("boxes") or []
        user_message = (body.get("userMessage") or "").strip()
        box_returned = len(boxes) > 0 and len(boxes[0].get("words", [])) > 0

        # Interpreted topic/situation
        interpreted = f"topic={topic} source={topic_source} confidence={topic_confidence}"
        if topic_keywords:
            interpreted += f" keywords={topic_keywords}"
        if situation_label:
            interpreted += f" situation={situation_label!r}"

        # Useful: supported topic with box, or unsupported with topic_not_supported and no box
        topic_not_supported = status == "topic_not_supported"
        useful = (expect_box and box_returned) or (not expect_box and topic_not_supported and not box_returned)
        honest_fail = (not expect_box and topic_not_supported) or (expect_box and box_returned)

        print(f"    status: {status}")
        print(f"    interpreted: {interpreted}")
        print(f"    box_returned: {box_returned} (expect_box={expect_box})")
        print(f"    userMessage: {user_message[:80]}..." if len(user_message) > 80 else f"    userMessage: {user_message}")
        print(f"    useful: {useful}  honest_fail: {honest_fail}")

        results.append({
            "prompt": prompt,
            "interpreted_topic": interpreted,
            "status": status,
            "topic": topic,
            "topic_keywords": topic_keywords,
            "situation_label": situation_label,
            "box_returned": box_returned,
            "useful": useful,
            "honest_fail": honest_fail,
        })

    # Summary
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    useful_count = sum(1 for r in results if r.get("useful"))
    honest_count = sum(1 for r in results if r.get("honest_fail") or (r.get("box_returned") and "error" not in r))
    print(f"Useful outcome: {useful_count}/{len(results)}")
    print(f"Honest (box when supported, no junk when unsupported): {honest_count}/{len(results)}")
    if results:
        out_path = os.environ.get("VALIDATION_OUTPUT", "logs/flexible_topic_validation.json")
        os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
        with open(out_path, "w") as f:
            json.dump(results, f, indent=2)
        print(f"Results written to {out_path}")

    return 0 if useful_count == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
