#!/usr/bin/env python3
"""
Run the six validation prompts and check ambiguous words in box output.
For full E2E (explicit + natural prompts, quality checks, regression) use validate_end_to_end_prompts.py.

Usage:
    # With API running: python scripts/run_six_validation_prompts.py
    # Or: LINGUAI_API_URL=http://localhost:2024/generate-boxes python scripts/run_six_validation_prompts.py
"""
import os
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

import requests

API_URL = os.environ.get("LINGUAI_API_URL", "http://localhost:2024/generate-boxes")

# Six validation prompts: (prompt, default_lang, target_lang)
VALIDATION_PROMPTS = [
    ("A1 restaurant words in German", "en", "de"),
    ("A1 travel words in Spanish", "en", "es"),
    ("B1 shopping words in German", "en", "de"),
    ("health vocabulary in Spanish", "en", "es"),
    ("B2 business words in German", "en", "de"),
    ("daily vocabulary in Spanish", "en", "es"),
]

# Ambiguous words we care about: (default_text, topic_context) -> expected target hint
AMBIGUOUS_CHECKS = {
    ("bill", "restaurant"): "Rechnung|factura|cuenta|addition",
    ("bar", "restaurant"): "Bar|bar|Kneipe",
    ("plane", "travel"): "Flugzeug|avión|avion",
    ("clock", "daily"): "Uhr|reloj",
    ("coffee", "restaurant"): "Kaffee|café|cafe",
}


def run_prompt(session: requests.Session, prompt: str, default_lang: str, target_lang: str, idx: int) -> dict:
    payload = {
        "requestId": f"validation-{idx}-{target_lang}",
        "customerId": "validation-cust",
        "prompt": prompt,
        "defaultLanguage": default_lang,
        "targetLanguage": target_lang,
        "existingBoxes": [],
    }
    try:
        r = session.post(API_URL, json=payload, timeout=30)
        body = r.json() if r.ok else {"error": r.text[:200]}
        return {"prompt": prompt[:50], "status": r.status_code, "body": body}
    except Exception as e:
        return {"prompt": prompt[:50], "status": None, "error": str(e)}


def main() -> int:
    base = API_URL.rsplit("/", 1)[0]
    session = requests.Session()
    try:
        session.get(f"{base}/", timeout=5)
    except Exception as e:
        print(f"Server not reachable at {base}: {e}", file=sys.stderr)
        print("Start with: uvicorn main:app --port 2024 --host 0.0.0.0", file=sys.stderr)
        return 1

    print(f"Running 6 validation prompts against {API_URL}\n")
    results = []
    for i, (prompt, default_lang, target_lang) in enumerate(VALIDATION_PROMPTS, start=1):
        out = run_prompt(session, prompt, default_lang, target_lang, i)
        results.append(out)
        status = out.get("status") or "ERR"
        body = out.get("body") or {}
        boxes = body.get("boxes") or []
        words = []
        if boxes:
            words = (boxes[0].get("words") or [])[:10]
        print(f"{i}. {prompt[:45]}... -> {status} | boxes={len(boxes)} words={len(words)}")
        if words:
            for w in words[:5]:
                print(f"   {w.get('default')} -> {w.get('target')}")
        if out.get("error"):
            print(f"   ERROR: {out['error']}")

    # Check ambiguous words if any box words returned
    print("\n--- Ambiguous word check (in returned box words) ---")
    all_words = []
    for r in results:
        for b in (r.get("body") or {}).get("boxes") or []:
            all_words.extend((b.get("words") or []))

    for (default, _ctx), pattern in AMBIGUOUS_CHECKS.items():
        found = [w for w in all_words if (w.get("default") or "").lower() == default.lower()]
        if found:
            targets = [w.get("target") for w in found]
            print(f"  {default} -> {targets}")
        else:
            print(f"  {default} -> (not in this run's box words)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
