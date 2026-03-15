# Idempotency and Duplicate Protection

## 1. Current-state summary (before implementation)

### What existed before

- **requestId**  
  - Used in logging (e.g. `request_received requestId=...`), passed through workflow state, and used in `box_workflow` to form `box_id` (`generated-{request_id}`).  
  - **Not** used for idempotency: `check_idempotency(request_id)` was a placeholder that always returned `None`.

- **customerId**  
  - Present in `GenerateBoxesRequest` and in `BoxWorkflowState`; passed through to the graph.  
  - Not used for idempotency or duplicate prevention.

- **Idempotency**  
  - **Not implemented.**  
  - In `main.py`, a stub `check_idempotency(request_id: str) -> Optional[GenerateBoxesResponse]` with a TODO and `return None` was called before the workflow. No store, no caching.

- **Duplicate prevention**  
  - **None** at the API or “duplicate box” level.  
  - In `app/vocab_store.py`, “duplicate” means filtering duplicate **words** against the user’s existing boxes inside a single run. No protection against the same **request** being processed twice.

- **Persistence**  
  - SQLite used only for vocabulary (`data/vocab.db` via `app/vocab_store.py`). No idempotency store, no cache, no replay protection.

### What happens today if the same frontend request is sent twice (before this change)

- Both requests are treated as new. The workflow runs twice (relevance, topic, level, box creation, LLM calls, retrieval).  
- Two responses are returned (typically identical if inputs and backend are unchanged).  
- No duplicate “logical” box is prevented at the backend; `box_id` is `generated-{request_id}`, so the client might dedupe by `requestId`/box_id, but the backend does not avoid duplicate work or enforce idempotency.

---

## 2. Files changed

| File | Change |
|------|--------|
| `app/idempotency.py` | **New.** SQLite-backed idempotency store: `get(customer_id, request_id)`, `set(...)`; key `(customer_id, request_id)`; stores `request_hash` and `response_json`. |
| `main.py` | Replaced placeholder idempotency with real logic: `_request_hash(req)`, `_check_idempotency(req)` using `(customerId, requestId)`, payload hash, and 409 on conflict; store only on success (`status == generated_placeholder`). |
| `.gitignore` | Added `data/idempotency.db`. |
| `scripts/validate_idempotency.py` | **New.** Script that runs five API scenarios (new key, exact replay, conflict, different requestId, different customer). |
| `tests/test_idempotency.py` | **New.** Unit tests for idempotency store (get/set, key isolation, overwrite); require `pytest`. |
| `docs/IDEMPOTENCY_AND_DUPLICATE_PROTECTION.md` | **New.** This document. |

---

## 3. Exact logic added

### Idempotency key

- **Key:** `(customerId, requestId)`.  
- **Reason:** So that the same `requestId` used by different customers does not collide, and so that replay/retry is scoped per customer.

### Request hash

- **Inputs:** `prompt`, `defaultLanguage`, `targetLanguage`, `existingBoxes` (canonical: boxes sorted by `boxId`, then JSON with `sort_keys=True`).  
- **Algorithm:** SHA-256 of the canonical JSON.  
- **Use:** Same key + same hash → return cached response. Same key + different hash → **409 Conflict**.

### Flow in `main.py`

1. **Pre-check:** `_check_idempotency(req)`  
   - `idempotency_get(req.customerId, req.requestId)`.  
   - If miss → return `None` (proceed to workflow).  
   - If hit: compare stored hash with `_request_hash(req)`.  
     - Same hash → return cached `GenerateBoxesResponse` (from stored JSON).  
     - Different hash → raise `HTTPException(409, detail="Idempotency conflict: ...")`.

2. **After workflow:** Only when `resp.status == STATUS_GENERATED_PLACEHOLDER`:  
   - `idempotency_set(req.customerId, req.requestId, _request_hash(req), resp.model_dump_json())`.

### Duplicate box prevention

- Handled entirely by idempotency: a replayed request (same key + same payload) returns the cached response and the workflow is not run again, so no second “logical” generation and no duplicate downstream effects. No separate semantic duplicate-detection.

---

## 4. Storage / caching approach

- **Where:** SQLite DB at `data/idempotency.db` (overridable with `IDEMPOTENCY_DB_PATH`).  
- **Table:** `idempotency_store (customer_id, request_id, request_hash, response_json, created_at)` with `PRIMARY KEY (customer_id, request_id)`.  
- **What is stored:** Only **successful** responses (`status == generated_placeholder`). Failures (e.g. irrelevant_request, insufficient_confidence, errors) are not cached so that retries can get a fresh run.  
- **Concurrency:** Single DB file; SQLite serializes writes. No cross-process lock. If two workers both miss for the same new key, both may run the workflow; both can call `set()` and the last write wins. Safe for single-instance or low-contention MVP.

---

## 5. Validation scenarios run and results

Script: `scripts/validate_idempotency.py` (requires server running, e.g. `uvicorn main:app --port 2024`).

| # | Scenario | Expected | Result |
|---|----------|----------|--------|
| 1 | New `(customerId, requestId)` | 200, normal generation | OK |
| 2 | Exact replay (same key + same payload) | 200, same response (cached) | OK (cached response) |
| 3 | Conflict (same key + different payload) | 409 | OK |
| 4 | Same customer, different requestId | 200, new request | OK |
| 5 | Different customer, same requestId | 200, no collision | OK |

All five passed. Additional smoke test: idempotency store `get`/`set` exercised with a temporary DB; behavior as expected.

---

## 6. Limitations

- **Conflict response:** 409 is a new HTTP status for this API (success path remains 200 + `GenerateBoxesResponse`). Clients must handle 409 if they reuse `requestId` with a different payload.  
- **No TTL:** Stored entries are not expired; DB can grow. Acceptable for MVP; add TTL or cleanup later if needed.  
- **Concurrency:** As above, no distributed lock; duplicate work is possible only when two identical requests for the same key are in flight at the same time; last write wins and replays later get the cached response.  
- **Only success cached:** Failed or low-confidence outcomes are not stored; retries always re-run the workflow.

---

## 7. Safe for MVP?

Yes. Same `(customerId, requestId)` + same payload is idempotent (cached response, no duplicate generation). Same key + different payload is rejected with 409. Keys are per customer, so no cross-customer collision. Storage is minimal (one SQLite table), and behavior is deterministic and documented.
