#!/usr/bin/env python3
"""
Validate hybrid topic identification against fixed test prompts.
Reports: prompt, resolved topic, confidence, source (ai | deterministic).

Usage: Start API (uvicorn main:app --port 2024), then:
  python scripts/validate_topic_prompts.py
"""
import json
import os
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

import requests

API_URL = os.environ.get("LINGUAI_API_URL", "http://localhost:2024/generate-boxes")

# Deterministic (should NOT trigger AI): clear topic keywords.
DETERMINISTIC_PROMPTS = [
    "A1 restaurant words in German",
    "B1 travel vocabulary in Spanish",
    "B2 business German words",
]

# Natural / ambiguous (should trigger AI fallback when no strong keyword).
AI_PROMPTS = [
    "I want B2 words in German that will help me when going to labor with my wife",
    "phrases for talking to a midwife",
    "Spanish vocabulary for a medical emergency",
    "words for awkward small talk at work",
    "help me at the pharmacy in German",
    "German words I can use at a hotel check-in",
    "Spanish words for ordering food at a cafe",
]


def run_one(session: requests.Session, prompt: str, default_lang: str = "en", target_lang: str = "de") -> dict:
    payload = {
        "requestId": f"topic-val-{hash(prompt) % 10**6}",
        "customerId": "topic-validation",
        "prompt": prompt,
        "defaultLanguage": default_lang,
        "targetLanguage": target_lang,
        "existingBoxes": [],
    }
    try:
        r = session.post(API_URL, json=payload, timeout=30)
        body = r.json() if r.ok else {}
        return {
            "prompt": prompt,
            "http": r.status_code,
            "topic": body.get("topic"),
            "topicSource": body.get("topicSource"),
            "topicConfidence": body.get("topicConfidence"),
            "topicReason": body.get("topicReason"),
        }
    except Exception as e:
        return {"prompt": prompt, "error": str(e)}


def main() -> int:
    base = API_URL.rsplit("/", 1)[0]
    session = requests.Session()
    try:
        session.get(f"{base}/", timeout=5)
    except Exception as e:
        print(f"Server not reachable at {base}: {e}", file=sys.stderr)
        return 1

    print("=== Deterministic prompts (expect source=deterministic, no AI) ===\n")
    for prompt in DETERMINISTIC_PROMPTS:
        out = run_one(session, prompt)
        print(f"Prompt: {out['prompt']}")
        print(f"  topic={out.get('topic')} confidence={out.get('topicConfidence')} source={out.get('topicSource')}")
        if out.get("topicReason"):
            print(f"  reason={out['topicReason']}")
        print()

    print("=== Natural prompts (expect source=ai when not keyword-matched) ===\n")
    for prompt in AI_PROMPTS:
        out = run_one(session, prompt)
        print(f"Prompt: {out['prompt']}")
        print(f"  topic={out.get('topic')} confidence={out.get('topicConfidence')} source={out.get('topicSource')}")
        if out.get("topicReason"):
            print(f"  reason={out['topicReason']}")
        print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
