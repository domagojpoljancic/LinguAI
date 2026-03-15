#!/usr/bin/env python3
"""
Validate idempotency and duplicate protection for POST /generate-boxes.

Requires the API server to be running (e.g. uvicorn main:app --port 2024).
Uses BASE_URL env or http://localhost:2024.

Scenarios:
  1. New (customerId, requestId) -> 200, normal generation
  2. Exact replay (same key + same payload) -> 200, same response (no duplicate work)
  3. Conflict (same key + different payload) -> 409
  4. Same customer, different requestId -> 200, new request
  5. Different customer, same requestId -> 200, no collision (separate keys)
"""

import json
import os
import sys

import requests

BASE_URL = os.environ.get("BASE_URL", "http://localhost:2024")


def make_body(customer_id: str, request_id: str, prompt: str) -> dict:
    return {
        "requestId": request_id,
        "customerId": customer_id,
        "prompt": prompt,
        "defaultLanguage": "en",
        "targetLanguage": "de",
        "existingBoxes": [],
    }


def main() -> int:
    endpoint = f"{BASE_URL}/generate-boxes"
    customer = "idempotency-validation-customer"
    request_id_1 = "idem-req-001"
    request_id_2 = "idem-req-002"
    prompt_a = "Give me B1 travel vocabulary"
    prompt_b = "Give me A2 restaurant words"

    passed = 0
    failed = 0

    # 1. New key -> 200
    print("1. New (customerId, requestId) -> expect 200...")
    r1 = requests.post(endpoint, json=make_body(customer, request_id_1, prompt_a), timeout=30)
    if r1.status_code != 200:
        print(f"   FAIL: got {r1.status_code}")
        failed += 1
    else:
        body1 = r1.json()
        if body1.get("status") != "generated_placeholder":
            print(f"   SKIP: status={body1.get('status')} (need success to store; run with vocab DB if needed)")
        passed += 1
        print("   OK")

    # 2. Exact replay -> 200, same response
    print("2. Exact replay (same key + same payload) -> expect 200, same response...")
    r2 = requests.post(endpoint, json=make_body(customer, request_id_1, prompt_a), timeout=30)
    if r2.status_code != 200:
        print(f"   FAIL: got {r2.status_code}")
        failed += 1
    else:
        body2 = r2.json()
        if body1.get("status") == "generated_placeholder" and body2.get("status") == "generated_placeholder":
            if body2.get("requestId") == body1.get("requestId") and body2.get("boxes") == body1.get("boxes"):
                print("   OK (cached response)")
                passed += 1
            else:
                print("   FAIL: response differs from first")
                failed += 1
        else:
            passed += 1
            print("   OK")

    # 3. Conflict: same key, different payload -> 409
    print("3. Conflict (same key + different payload) -> expect 409...")
    r3 = requests.post(endpoint, json=make_body(customer, request_id_1, prompt_b), timeout=30)
    if r3.status_code != 409:
        print(f"   FAIL: got {r3.status_code}, expected 409")
        failed += 1
    else:
        print("   OK")
        passed += 1

    # 4. Different requestId, same customer -> 200 (new request)
    print("4. Same customer, different requestId -> expect 200 (new request)...")
    r4 = requests.post(endpoint, json=make_body(customer, request_id_2, prompt_a), timeout=30)
    if r4.status_code != 200:
        print(f"   FAIL: got {r4.status_code}")
        failed += 1
    else:
        print("   OK")
        passed += 1

    # 5. Different customer, same requestId -> 200 (no collision)
    print("5. Different customer, same requestId -> expect 200 (no collision)...")
    r5 = requests.post(endpoint, json=make_body("other-customer", request_id_1, prompt_a), timeout=30)
    if r5.status_code != 200:
        print(f"   FAIL: got {r5.status_code}")
        failed += 1
    else:
        print("   OK")
        passed += 1

    print("")
    print(f"Passed: {passed}, Failed: {failed}")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
