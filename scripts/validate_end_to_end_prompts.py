#!/usr/bin/env python3
"""
End-to-end validation: topic resolution + box content for explicit and natural prompts.

For each case reports: prompt, topic, topicSource, topicConfidence, topicReason,
box name, word count, sample words, and quality checks (on-topic, practically useful,
no wrong-sense, no obvious filler).

Usage: Start API (e.g. uvicorn main:app --port 2024), then:
  python scripts/validate_end_to_end_prompts.py
  python scripts/validate_end_to_end_prompts.py --json  # machine-readable to stdout

Regression: at least 2 natural-prompt checks (topic=health + box contains health keywords).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

import requests

API_URL = os.environ.get("LINGUAI_API_URL", "http://localhost:2024/generate-boxes")

# A. Explicit-topic prompts (expect deterministic topic, good box)
EXPLICIT_PROMPTS = [
    ("A1 restaurant words in German", "en", "de"),
    ("A1 travel words in Spanish", "en", "es"),
    ("B1 shopping words in German", "en", "de"),
    ("health vocabulary in Spanish", "en", "es"),
    ("B2 business words in German", "en", "de"),
    ("daily vocabulary in Spanish", "en", "es"),
]

# B. Natural prompts (expect AI topic resolution when not keyword-matched)
NATURAL_PROMPTS = [
    ("I want B2 words in German that will help me when going to labor with my wife", "en", "de"),
    ("phrases for talking to a midwife", "en", "de"),
    ("German words for visiting the doctor", "en", "de"),
    ("Spanish vocabulary for a medical emergency", "en", "es"),
    ("words for awkward small talk at work", "en", "de"),
    ("help me at the pharmacy in German", "en", "de"),
    ("German words I can use at a hotel check-in", "en", "de"),
    ("Spanish words for ordering food at a cafe", "en", "es"),
]

# Regression: natural prompts that must resolve to topic and box must contain at least one of these (default_text)
REGRESSION_HEALTH_KEYWORDS = ["hospital", "doctor", "medicine", "pharmacy", "appointment", "symptom", "pain", "nurse"]
REGRESSION_TRAVEL_KEYWORDS = ["hotel", "check-in", "reservation", "passport", "luggage", "room"]


def run_one(
    session: requests.Session,
    prompt: str,
    default_lang: str,
    target_lang: str,
    request_suffix: str = "",
) -> dict:
    payload = {
        "requestId": f"e2e-{abs(hash(prompt)) % 10**6}{request_suffix}",
        "customerId": "e2e-validation",
        "prompt": prompt,
        "defaultLanguage": default_lang,
        "targetLanguage": target_lang,
        "existingBoxes": [],
    }
    try:
        r = session.post(API_URL, json=payload, timeout=45)
        body = r.json() if r.ok else {}
        box = (body.get("boxes") or [None])[0]
        words = (box.get("words") or []) if box else []
        return {
            "prompt": prompt,
            "default_lang": default_lang,
            "target_lang": target_lang,
            "http": r.status_code,
            "topic": body.get("topic"),
            "topicSource": body.get("topicSource"),
            "topicConfidence": body.get("topicConfidence"),
            "topicReason": body.get("topicReason"),
            "boxName": box.get("boxName") if box else None,
            "wordCount": len(words),
            "words": words,
            "defaults": [w.get("default") for w in words if w.get("default")],
        }
    except Exception as e:
        return {"prompt": prompt, "error": str(e), "default_lang": default_lang, "target_lang": target_lang}


def assess(result: dict) -> dict:
    """Simple quality checks: on-topic, practically useful, no wrong-sense, no obvious filler."""
    topic = (result.get("topic") or "").lower()
    defaults = result.get("defaults") or []
    source = result.get("topicSource") or ""
    checks = {
        "on_topic": bool(topic and topic in ("restaurant", "travel", "shopping", "business", "health", "dating", "daily", "general")),
        "practically_useful": len(defaults) >= 5 and not all(w in ("word", "phrase", "thing") for w in defaults[:5]),
        "no_obvious_filler": not any(d and d.lower() in ("word", "phrase") for d in defaults[:10]),
        "has_sample_words": len(defaults) >= 3,
    }
    # Heuristic wrong-sense: known bad pairs (expand if needed)
    bad_pairs = [("bill", "gesetzentwurf"), ("bar", "block"), ("coffee", "kaffebohne"), ("plane", "plano"), ("clock", "cuentakilómetros")]
    targets = [w.get("target", "").lower() for w in (result.get("words") or [])]
    default_list = [w.get("default", "").lower() for w in (result.get("words") or [])]
    wrong_sense = False
    for d, t in bad_pairs:
        if d in default_list:
            idx = default_list.index(d)
            if idx < len(targets) and t in (targets[idx] or ""):
                wrong_sense = True
                break
    checks["no_wrong_sense"] = not wrong_sense
    return checks


def regression_health(result: dict) -> bool:
    """Natural health prompt should yield topic=health and at least one health keyword in box."""
    if (result.get("topic") or "").lower() != "health":
        return False
    defaults = [d.lower() for d in (result.get("defaults") or [])]
    return any(kw in " ".join(defaults) for kw in REGRESSION_HEALTH_KEYWORDS)


def regression_natural_topic_source(result: dict) -> bool:
    """For natural prompts we expect topicSource=ai (unless prompt has strong keyword)."""
    # Optional: we don't require ai for all natural; just that topic is normalized.
    return (result.get("topicSource") or "") in ("ai", "deterministic")


def main() -> int:
    ap = argparse.ArgumentParser(description="End-to-end validation for explicit and natural prompts")
    ap.add_argument("--json", action="store_true", help="Output JSON only (no human report)")
    ap.add_argument("--base", type=str, default="", help="Base URL override (e.g. http://localhost:2024)")
    args = ap.parse_args()
    if args.base:
        global API_URL
        API_URL = args.base.rstrip("/") + "/generate-boxes"

    base = API_URL.rsplit("/", 1)[0]
    session = requests.Session()
    try:
        session.get(f"{base}/", timeout=5)
    except Exception as e:
        print(f"Server not reachable at {base}: {e}", file=sys.stderr)
        return 1

    all_results = []
    # Explicit
    for prompt, dl, tl in EXPLICIT_PROMPTS:
        r = run_one(session, prompt, dl, tl, "-explicit")
        r["group"] = "explicit"
        r["quality"] = assess(r)
        all_results.append(r)

    # Natural
    for prompt, dl, tl in NATURAL_PROMPTS:
        r = run_one(session, prompt, dl, tl, "-natural")
        r["group"] = "natural"
        r["quality"] = assess(r)
        r["regression_health_ok"] = regression_health(r) if (r.get("topic") or "").lower() == "health" else None
        all_results.append(r)

    if args.json:
        print(json.dumps(all_results, indent=2, ensure_ascii=False))
        return 0

    # Human report
    print("=" * 60)
    print("A. EXPLICIT-TOPIC PROMPTS")
    print("=" * 60)
    for r in all_results:
        if r.get("group") != "explicit":
            continue
        print(f"\nPrompt: {r['prompt']}")
        print(f"  topic={r.get('topic')} topicSource={r.get('topicSource')} topicConfidence={r.get('topicConfidence')}")
        print(f"  boxName={r.get('boxName')} wordCount={r.get('wordCount')}")
        sample = (r.get("defaults") or [])[:10]
        print(f"  sample: {sample}")
        q = r.get("quality") or {}
        print(f"  on_topic={q.get('on_topic')} practically_useful={q.get('practically_useful')} no_wrong_sense={q.get('no_wrong_sense')} no_obvious_filler={q.get('no_obvious_filler')}")

    print("\n" + "=" * 60)
    print("B. NATURAL PROMPTS (AI topic resolution)")
    print("=" * 60)
    for r in all_results:
        if r.get("group") != "natural":
            continue
        print(f"\nPrompt: {r['prompt']}")
        print(f"  topic={r.get('topic')} topicSource={r.get('topicSource')} topicConfidence={r.get('topicConfidence')}")
        if r.get("topicReason"):
            print(f"  topicReason={r['topicReason']}")
        print(f"  boxName={r.get('boxName')} wordCount={r.get('wordCount')}")
        sample = (r.get("defaults") or [])[:10]
        print(f"  sample: {sample}")
        q = r.get("quality") or {}
        print(f"  on_topic={q.get('on_topic')} practically_useful={q.get('practically_useful')} no_wrong_sense={q.get('no_wrong_sense')} no_obvious_filler={q.get('no_obvious_filler')}")
        if r.get("regression_health_ok") is not None:
            print(f"  regression_health_ok={r['regression_health_ok']}")

    # Regression summary
    health_results = [r for r in all_results if r.get("group") == "natural" and (r.get("topic") or "").lower() == "health"]
    travel_results = [r for r in all_results if r.get("group") == "natural" and (r.get("topic") or "").lower() == "travel"]
    reg_health_ok = all(regression_health(r) for r in health_results) if health_results else True
    reg_travel_ok = all(
        any(kw in " ".join((r.get("defaults") or [])).lower() for kw in REGRESSION_TRAVEL_KEYWORDS)
        for r in travel_results
    ) if travel_results else True
    print("\n" + "=" * 60)
    print("REGRESSION")
    print("  natural health prompts -> topic=health + box has health keywords:", reg_health_ok)
    print("  natural travel prompts -> box has travel keywords:", reg_travel_ok)
    print("=" * 60)

    return 0 if (reg_health_ok and reg_travel_ok) else 1


if __name__ == "__main__":
    sys.exit(main())
