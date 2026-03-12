# LinguAI LangGraph – OpenAI & Logging Audit

## 1. Execution map: request flow

```
POST /generate-boxes
  → FastAPI (main.generate_boxes)
  → check_idempotency (placeholder, no-op)
  → _request_to_workflow_state (map body → state dict)
  → graph.invoke(initial)  [LangGraph]
       → relevance_check (node)
            → _get_llm().invoke([system, user prompt])  [OpenAI call #1]
            → route_after_relevance → topic_identification | END
       → topic_identification (node, no OpenAI)
       → level_resolution (node)
            → _parse_cefr_from_prompt (regex) or _infer_level_with_llm
                 → _get_llm().invoke([system, context])  [OpenAI call #2, only if no explicit level]
       → box_creation_placeholder (node, no OpenAI)
  → _workflow_state_to_response (state → GenerateBoxesResponse)
  → return GenerateBoxesResponse
```

**OpenAI call sites (this app only):**

- **relevance_check** in `app/box_workflow.py`: one `_get_llm().invoke(...)` with system + user prompt.
- **_infer_level_with_llm** in `app/box_workflow.py`: one `llm.invoke(...)` when level is not found in prompt (explicit CEFR).

---

## 2. Where to change OpenAI variable(s)

### Locations found

| Location | Variable(s) | Role |
|----------|-------------|------|
| **app/config.py** | `OPENAI_API_KEY`, `OPENAI_MODEL`, `LEVEL_INFERENCE_USE_LLM` | Read from `os.environ` at import; **not used** by the box workflow. Documented as “single place” but workflow does not import these. |
| **app/box_workflow.py** `_get_llm()` | `os.environ.get("OPENAI_API_KEY")`, `os.environ.get("OPENAI_MODEL", "gpt-4o-mini")` | **Actual source of truth** for the generate-boxes workflow. Lazy init so graph builds without API key. |
| **app/nodes.py** | Hardcoded `ChatOpenAI(model="gpt-4o-mini", request_timeout=60)` | Separate agent path; **no env vars**. Used by a different flow (LinguAI agent), not by `/generate-boxes`. |

### Recommended single place for normal development

- **For the `/generate-boxes` workflow:** set in `.env` (or environment):
  - `OPENAI_API_KEY` – required for real calls.
  - `OPENAI_MODEL` – optional; default is `gpt-4o-mini`. This is the **only** variable that controls the model for relevance and level-inference calls; it is read **only** in `app/box_workflow.py` inside `_get_llm()`.
- **Best place to “change the variable” for normal dev:** change **`OPENAI_MODEL`** in `.env` (or your env). No code change needed; `_get_llm()` reads it each time.
- **Optional consolidation:** have `_get_llm()` use `from app.config import OPENAI_MODEL, OPENAI_API_KEY` so `app/config.py` is the single place that reads env and the workflow uses that. Right now they are separate (config is pass-through only; workflow reads env directly).

### Exact variable names

- **OPENAI_API_KEY** – API key (set in env; never log).
- **OPENAI_MODEL** – model name, e.g. `gpt-4o-mini` (default in code).
- **OPENAI_BASE_URL** – not used in this repo; LangChain’s `ChatOpenAI` can take `base_url` if you need a proxy or alternate endpoint.

---

## 3. Logging audit

### Request to OpenAI logged? **Yes** (after changes)

- **relevance_check:** logs `openai_request` with `request_id`, `call_type=relevance_check`, `model`, `prompt_length` (no full prompt).
- **level_inference:** logs `openai_request` with `request_id`, `call_type=level_inference`, `model`, `context_length`.

### Response from OpenAI logged? **Yes** (after changes)

- **relevance_check:** logs `openai_response` with success, result (relevant/not_relevant), truncated `response_preview` (up to 80 chars); plus token usage when present in `response_metadata`.
- **level_inference:** logs `openai_response` with success, `inferred_level`, truncated `response_preview`; plus token usage when present.
- **On failure:** `logger.exception(...)` in both paths so stack traces are recorded.

### Node-by-node logging status

| Node | Start | Key decision / branch | Important inputs (summary) | Completion | Failure |
|------|--------|------------------------|----------------------------|------------|--------|
| **relevance_check** | Yes | Yes (relevant / not_relevant) | prompt_length, model | Yes (+ OpenAI response summary) | Yes (exception) |
| **topic_identification** | Yes | N/A (deterministic) | topic | Yes | N/A |
| **level_resolution** | Yes | Yes (explicit vs inferred, level value) | level, level_source | Yes | Yes (in _infer_level_with_llm) |
| **box_creation_placeholder** | Yes | N/A | — | Yes (“reached”) | N/A |

---

## 4. Minimal code changes made

- **app/box_workflow.py**
  - **OpenAI request logging:** before each `invoke` in `relevance_check` and `_infer_level_with_llm`: log model, call_type, and input length (no secrets, no full prompt/context).
  - **OpenAI response logging:** after each successful `invoke`: log success, result (or inferred level), truncated response preview; log token usage from `response_metadata` when available (`_log_openai_usage`).
  - **Failure logging:** in `relevance_check`, catch block now uses `logger.exception(...)` instead of `logger.warning(..., exc_info=True)`. In `_infer_level_with_llm`, catch block uses `logger.exception(...)`.
  - **Node start logging:** one line at the start of each of the four nodes: `relevance_check`, `topic_identification`, `level_resolution`, `box_creation_placeholder`.

No other files were changed. No refactors to control flow or config.

---

## 5. Analysis of box_creation_placeholder

### What it does

- **Signature:** `box_creation_placeholder(state: BoxWorkflowState) -> dict`
- **Behavior:**
  - Logs that the node was reached.
  - Returns a **fixed** dict:
    - `status = STATUS_GENERATED_PLACEHOLDER` (`"generated_placeholder"`)
    - `boxes = []`
    - `user_message = "Ready to generate (placeholder)."`
    - `reached_box_creation = True`
- **No** LLM call, no I/O, no side effects, no use of `state` except `request_id` for logging.

### Is it effectively a no-op?

**Yes.** It is an intentional stub:

- Docstring: “Placeholder for box generation. No real generation yet; returns stub outcome.”
- Return value is constant; the only effect is updating workflow state so the API can set `reachedBoxCreation=True` and `status="generated_placeholder"` in the HTTP response.
- The “work” (relevance, topic, level) is done in earlier nodes; this node only marks that the pipeline reached the box-creation step.

So: **no-op for real box generation**, but **not no-op for the API contract** – it sets the response fields that the client uses to know the flow succeeded and reached box creation.

---

## 6. Example API requests

### Endpoint and method

- **URL:** `POST /generate-boxes`
- **Headers:** `Content-Type: application/json`
- **Body:** JSON matching `GenerateBoxesRequest` (see schemas).

### 1. Normal successful flow (relevant, explicit level, reaches box_creation_placeholder)

```bash
curl -s -X POST http://localhost:2024/generate-boxes \
  -H "Content-Type: application/json" \
  -d '{
    "requestId": "req-normal-001",
    "customerId": "cust-1",
    "prompt": "I want B2 business vocabulary for German",
    "defaultLanguage": "en",
    "targetLanguage": "de",
    "existingBoxes": []
  }'
```

**Expected path:** relevance_check (OpenAI) → relevant → topic_identification → level_resolution (explicit B2) → box_creation_placeholder. Response: `status=generated_placeholder`, `level=B2`, `levelSource=explicit`, `reachedBoxCreation=true`.

---

### 2. Alternate branch: not relevant (stops after relevance_check)

```bash
curl -s -X POST http://localhost:2024/generate-boxes \
  -H "Content-Type: application/json" \
  -d '{
    "requestId": "req-irrelevant-002",
    "customerId": "cust-1",
    "prompt": "What is the weather in Berlin?",
    "defaultLanguage": "en",
    "targetLanguage": "de",
    "existingBoxes": []
  }'
```

**Expected path:** relevance_check (OpenAI) → not relevant → **END**. No topic, level, or box_creation. Response: `status=irrelevant_request`, `userMessage` set, `reachedBoxCreation=false`.

---

### 3. Level inferred (no explicit CEFR; uses OpenAI in level_resolution)

```bash
curl -s -X POST http://localhost:2024/generate-boxes \
  -H "Content-Type: application/json" \
  -d '{
    "requestId": "req-inferred-003",
    "customerId": "cust-2",
    "prompt": "Restaurant and travel words in Spanish",
    "defaultLanguage": "en",
    "targetLanguage": "es",
    "existingBoxes": [
      {
        "boxId": "box-1",
        "boxName": "Basics",
        "completionPercent": 60,
        "words": [
          {"default": "hello", "target": "hola"},
          {"default": "please", "target": "por favor"}
        ]
      }
    ]
  }'
```

**Expected path:** relevance_check → topic_identification → level_resolution (no explicit level → OpenAI inference) → box_creation_placeholder. Response: `levelSource=inferred`, `level` one of A1–C2, `reachedBoxCreation=true`.

---

### 4. Missing/invalid input (validation error)

If the body is invalid (e.g. missing required fields), FastAPI returns 422 and no workflow runs. Example invalid body (missing `requestId`):

```bash
curl -s -X POST http://localhost:2024/generate-boxes \
  -H "Content-Type: application/json" \
  -d '{
    "customerId": "cust-1",
    "prompt": "B1 vocabulary",
    "defaultLanguage": "en",
    "targetLanguage": "de",
    "existingBoxes": []
  }'
```

**Expected:** 422 Unprocessable Entity; no graph invocation.

---

### 5. OpenAI error / fallback

- **relevance_check:** On OpenAI failure, node returns `is_relevant=False`, `user_message="Something went wrong. Please try again."` and logs the exception. Flow goes to END; response `status=irrelevant_request` (same as “not relevant”).
- **level_resolution:** On OpenAI failure in `_infer_level_with_llm`, returns `DEFAULT_CEFR_WHEN_UNKNOWN` ("A2") and flow continues; response has `level=A2`, `levelSource=inferred`.

To simulate: use an invalid `OPENAI_API_KEY` or disconnect network and send a request that triggers level inference (e.g. prompt without CEFR, with or without boxes).

---

### 6. Edge case: reaches box_creation_placeholder with empty boxes

Same as (1) or (3); `existingBoxes: []` is valid. The placeholder always returns `boxes=[]` regardless of input.

---

### JSON-only payloads (for copy-paste)

**Normal, explicit level:**

```json
{
  "requestId": "req-normal-001",
  "customerId": "cust-1",
  "prompt": "I want B2 business vocabulary for German",
  "defaultLanguage": "en",
  "targetLanguage": "de",
  "existingBoxes": []
}
```

**Not relevant:**

```json
{
  "requestId": "req-irrelevant-002",
  "customerId": "cust-1",
  "prompt": "What is the weather in Berlin?",
  "defaultLanguage": "en",
  "targetLanguage": "de",
  "existingBoxes": []
}
```

**Level inferred (with existing boxes):**

```json
{
  "requestId": "req-inferred-003",
  "customerId": "cust-2",
  "prompt": "Restaurant and travel words in Spanish",
  "defaultLanguage": "en",
  "targetLanguage": "es",
  "existingBoxes": [
    {
      "boxId": "box-1",
      "boxName": "Basics",
      "completionPercent": 60,
      "words": [
        {"default": "hello", "target": "hola"},
        {"default": "please", "target": "por favor"}
      ]
    }
  ]
}
```

---

## 7. Proposed test suite (not implemented)

### Unit tests (node logic)

- **_parse_cefr_from_prompt**
  - Valid CEFR in prompt (A1–C2, case variations) → returns that level.
  - No CEFR in prompt → None.
  - Multiple CEFR in prompt → first match (document current behavior).
- **_identify_topic_deterministic**
  - Prompts containing keywords from `TOPIC_KEYWORDS` → correct label (e.g. “restaurant vocabulary”).
  - Unknown topic → “general vocabulary” or derived from words.
- **level_resolution**
  - State with explicit CEFR in prompt → level = that CEFR, level_source = "explicit".
  - State without CEFR, mock `_infer_level_with_llm` to return "B1" → level = "B1", level_source = "inferred".
  - State without CEFR, mock `_infer_level_with_llm` to raise → level = "A2", level_source = "inferred".
- **relevance_check**
  - Mock LLM returning "RELEVANT\n" → is_relevant=True, status not irrelevant.
  - Mock LLM returning "NOT_RELEVANT\n..." → is_relevant=False, status=irrelevant_request, user_message from second line or default.
  - Mock LLM raise → is_relevant=False, status=irrelevant_request, user_message fallback.
- **box_creation_placeholder**
  - Any state → returns status=generated_placeholder, boxes=[], reached_box_creation=True; no exception.

### Integration tests (API)

- **POST /generate-boxes**
  - Valid body, mock or real OpenAI:
    - Assert 200, response schema, `reachedBoxCreation` and `status` consistent with path.
  - Irrelevant prompt (or mocked relevance_check) → 200, `status=irrelevant_request`, `reachedBoxCreation=false`.
  - Invalid body (missing required field) → 422.
  - Optional: invalid API key or timeout → 200 with fallback status and no 5xx.

### OpenAI client behavior (mocks)

- **relevance_check:** Patch `_get_llm().invoke` to return an AIMessage with fixed content; assert state updates (is_relevant, user_message) and that no raw key/headers are logged.
- **level_resolution:** Patch `_get_llm().invoke` to return message with "B2" in content; assert level=B2, level_source=inferred. Patch to raise; assert level=A2 and no uncaught exception.
- **Logging assertions:** For a request that triggers one OpenAI call, assert log records contain openai_request and openai_response with expected call_type and no api_key or full prompt. Optionally assert usage is logged when mock supplies response_metadata.

### Branch coverage (by node)

- **relevance_check:** relevant path; not_relevant path (first line NOT_RELEVANT); not_relevant with second-line message vs default; exception path.
- **topic_identification:** keyword match; fallback from words; empty prompt.
- **level_resolution:** explicit level path; inferred path (success); inferred path (LLM failure → A2).
- **route_after_relevance:** is_relevant True → topic_identification; is_relevant False → END.
- **box_creation_placeholder:** single branch; regression test that return value and types are unchanged.

### Regression test for box_creation_placeholder

- Invoke `box_creation_placeholder` with minimal state `{"request_id": "r1"}`.
- Assert return keys: `status`, `boxes`, `user_message`, `reached_box_creation`.
- Assert `status == "generated_placeholder"`, `boxes == []`, `reached_box_creation is True`.
- Assert no external calls (e.g. no invoke on any LLM).

---

## 8. Final list of files changed

- **app/box_workflow.py** – Added: `_log_openai_usage`; OpenAI request/response logging in `relevance_check` and `_infer_level_with_llm`; `logger.exception` on failure; node-start logs for all four nodes. Added top-level `import os`.

No other files were modified. `/debug/graph/render` and the rest of the app are unchanged.
