"""
Simple evaluation runner for the LinguAI LangGraph generate-boxes workflow.

Usage:
    python scripts/run_evaluations.py

Requirements:
    - The FastAPI app must be running locally (default: http://localhost:2024).
    - tests/evaluation_payloads.json must exist with a list of cases.

Output:
    - Successes: logs/evaluation_results.jsonl (only 2xx responses).
    - Failures:  logs/evaluation_errors.jsonl (connection errors, timeouts, non-2xx, etc.).
"""

import json
import os
import sys
from datetime import datetime, timezone
from typing import Any, Dict, List

import requests


API_URL = os.environ.get("LINGUAI_API_URL", "http://localhost:2024/generate-boxes")
PAYLOADS_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), "tests", "evaluation_payloads.json")
LOG_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "logs")
RESULTS_PATH = os.path.join(LOG_DIR, "evaluation_results.jsonl")
ERRORS_PATH = os.path.join(LOG_DIR, "evaluation_errors.jsonl")


def _base_url() -> str:
    """Base URL for pre-flight check (e.g. http://localhost:2024)."""
    if "/generate-boxes" in API_URL:
        return API_URL.rsplit("/", 1)[0]
    return API_URL


def _utc_timestamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def check_server_reachable(session: requests.Session, timeout: int = 5) -> bool:
    """Return True if the API is reachable (e.g. GET /)."""
    base = _base_url()
    try:
        r = session.get(f"{base}/", timeout=timeout)
        return r.status_code == 200
    except Exception:
        return False


def load_cases(path: str) -> List[Dict[str, Any]]:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _compare_expected(actual: Dict[str, Any], expected: Dict[str, Any]) -> tuple[bool, List[Dict[str, Any]]]:
    """
    Compare actual response to expected (partial). Only keys present in expected are checked.
    Returns (all_match, list of mismatches with field, expected, actual).
    """
    mismatches: List[Dict[str, Any]] = []
    for key, exp_val in expected.items():
        actual_val = actual.get(key)
        if exp_val is None and actual_val is not None:
            if key == "reachedBoxCreation" and actual_val is False:
                pass
            else:
                mismatches.append({"field": key, "expected": exp_val, "actual": actual_val})
        elif exp_val is not None and actual_val != exp_val:
            mismatches.append({"field": key, "expected": exp_val, "actual": actual_val})
    return (len(mismatches) == 0, mismatches)


def run_case(session: requests.Session, case: Dict[str, Any]) -> Dict[str, Any]:
    name = case.get("name") or case.get("case") or "unnamed"
    payload = case.get("payload") or {}
    expected = case.get("expected") or {}
    request_id = payload.get("requestId") or ""
    ts = _utc_timestamp()
    result: Dict[str, Any] = {
        "timestamp": ts,
        "case_name": name,
        "requestId": request_id,
        "url": API_URL,
    }
    try:
        resp = session.post(API_URL, json=payload, timeout=30)
        result["http_status"] = resp.status_code
        try:
            body = resp.json()
        except ValueError:
            body = {"raw": resp.text[:500]}
        # Optionally enrich body with simple derived fields for assertions.
        if isinstance(body, dict):
            boxes = body.get("boxes") or []
            first_box = boxes[0] if boxes else {}
            words = first_box.get("words") or []
            body.setdefault("boxes_non_empty", bool(words))
        result["response"] = body
        result["status"] = body.get("status") if isinstance(body, dict) else None
        if expected and isinstance(body, dict):
            eval_ok, mismatches = _compare_expected(body, expected)
            result["eval_pass"] = eval_ok
            if mismatches:
                result["eval_mismatches"] = mismatches
    except Exception as e:
        result["http_status"] = None
        result["error_type"] = type(e).__name__
        result["error"] = str(e) if str(e) else repr(e)
    return result


def write_error_entry(path: str, entry: Dict[str, Any]) -> None:
    try:
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except OSError:
        pass


def main() -> int:
    if not os.path.exists(PAYLOADS_PATH):
        print(f"[ERROR] evaluation payloads not found at {PAYLOADS_PATH}", file=sys.stderr)
        return 1

    try:
        os.makedirs(LOG_DIR, exist_ok=True)
    except OSError:
        pass

    try:
        cases = load_cases(PAYLOADS_PATH)
    except Exception as e:
        print(f"[ERROR] failed to load payloads: {e}", file=sys.stderr)
        return 1

    session = requests.Session()

    if not check_server_reachable(session):
        print(f"Server unreachable at {_base_url()} - aborting evaluation run", file=sys.stderr)
        print("Start the API with: python -m uvicorn main:app --host 0.0.0.0 --port 2024", file=sys.stderr)
        return 1

    print(f"Running {len(cases)} evaluation case(s) against {API_URL}")
    success_count = 0
    fail_count = 0
    error_count = 0
    eval_with_expected = sum(1 for c in cases if c.get("expected"))
    eval_pass_count = 0
    eval_fail_count = 0

    with open(RESULTS_PATH, "a", encoding="utf-8") as success_file:
        for idx, case in enumerate(cases, start=1):
            name = case.get("name") or f"case-{idx}"
            payload = case.get("payload") or {}
            request_id = payload.get("requestId") or "-"
            result = run_case(session, case)

            http_status = result.get("http_status")
            status = result.get("status")
            error = result.get("error")
            error_type = result.get("error_type")

            if error is not None:
                error_count += 1
                err_entry = {
                    "timestamp": result.get("timestamp"),
                    "case_name": name,
                    "requestId": request_id,
                    "url": API_URL,
                    "error_type": error_type or "Exception",
                    "error": error,
                }
                write_error_entry(ERRORS_PATH, err_entry)
                print(f"ERROR {name} -> {error_type}: {error}")
            elif http_status is None:
                error_count += 1
                err_entry = {
                    "timestamp": result.get("timestamp"),
                    "case_name": name,
                    "requestId": request_id,
                    "url": API_URL,
                    "error_type": "NoResponse",
                    "error": "No HTTP status received",
                }
                write_error_entry(ERRORS_PATH, err_entry)
                print(f"ERROR {name} -> No HTTP status received")
            elif 200 <= http_status < 300:
                success_count += 1
                success_file.write(json.dumps(result, ensure_ascii=False) + "\n")
                outcome = status or "ok"
                eval_pass = result.get("eval_pass")
                mismatches = result.get("eval_mismatches") or []
                if expected := case.get("expected"):
                    if eval_pass is True:
                        eval_pass_count += 1
                        print(f"PASS {name} -> {http_status} {outcome} (eval OK)")
                    elif eval_pass is False and mismatches:
                        eval_fail_count += 1
                        print(f"PASS {name} -> {http_status} {outcome} (eval FAIL: {mismatches})")
                    else:
                        print(f"PASS {name} -> {http_status} {outcome}")
                else:
                    print(f"PASS {name} -> {http_status} {outcome}")
            else:
                fail_count += 1
                err_entry = {
                    "timestamp": result.get("timestamp"),
                    "case_name": name,
                    "requestId": request_id,
                    "url": API_URL,
                    "error_type": "HTTP",
                    "error": f"HTTP {http_status}",
                    "http_status": http_status,
                }
                write_error_entry(ERRORS_PATH, err_entry)
                print(f"FAIL {name} -> HTTP {http_status}")

    print(f"Finished: {success_count} passed, {fail_count} failed (non-2xx), {error_count} errors (e.g. connection refused)")
    if eval_with_expected:
        print(f"Eval (expected outcomes): {eval_pass_count} passed, {eval_fail_count} failed (of {eval_with_expected} cases with expected)")
    print(f"Successes: {RESULTS_PATH}")
    print(f"Errors:    {ERRORS_PATH}")
    return 0 if error_count == 0 and fail_count == 0 and eval_fail_count == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
