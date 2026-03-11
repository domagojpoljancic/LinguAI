# Implementation Summary: Level Flow Fix, Topic, Logging, Debug

## 1. What was wrong or risky in the old flow

- **Flow stopped when level was “no”:** After `level_resolution`, the router `route_after_level` sent the graph to `END` whenever `level` was empty. So if the user didn’t mention a CEFR level in the prompt, the workflow ended immediately and never tried to infer level from existing boxes or words.
- **No inference from existing words:** Level inference only used `existing_boxes` (completion percent). There was no use of `existing_words` from the payload, so “infer from words” was missing.
- **No topic for box creation:** State and response had no topic/theme field, so a later box-creation step couldn’t know what the box was about (e.g. “restaurant vocabulary”).
- **Response didn’t explain outcome:** The API didn’t expose whether level was explicit or inferred, what topic was identified, or whether the box-creation placeholder was reached.
- **Logging:** No structured workflow logs (relevance, level, topic, continuation), and no distinction between debug (full payload) and production-safe logging.

## 2. Architecture chosen

- **Level detection (explicit):** Deterministic regex on the prompt for CEFR tokens `A1`–`C2` (`CEFR_PATTERN`). If found, we use that level and set `level_source: "explicit"`.
- **Level inference (when no explicit level):** Ordered fallbacks: (1) infer from **existing_boxes** (completion-percent heuristic, unchanged), (2) optional **LLM-based** inference from prompt + existing words when `LEVEL_INFERENCE_USE_LLM=true`, (3) **heuristic from existing_words** (word count buckets: e.g. 5+ → A2, 20+ → B1, 50+ → B2). Only if all of these fail do we set `status: insufficient_confidence` and leave `level` empty; the router then sends the graph to END.
- **Topic identification:** Its own node `topic_identification` after the level router. Deterministic keyword matching against a small map (e.g. “restaurant”, “travel”, “business”) to produce a label like “restaurant vocabulary”. Stored in state `topic` for the box-creation step. No LLM in this step by default; easy to add later if needed.

## 3. Full contents of every modified file

See the repo; key edits:

- **app/state.py** — Added `level_source`, `topic`, `reached_box_creation` to `BoxWorkflowState`.
- **app/schemas.py** — Added `level`, `levelSource`, `topic`, `reachedBoxCreation` to `GenerateBoxesResponse`.
- **app/config.py** — New: `DEBUG`, `OPENAI_MODEL`, `LEVEL_INFERENCE_USE_LLM` from env.
- **app/box_workflow.py** — Level resolution now: explicit → boxes → words (LLM if enabled, else heuristic); `level_source` set; new `topic_identification` node (deterministic keywords); logging in each node.
- **app/graph.py** — New node `topic_identification`; edge `level_resolution` → `topic_identification` → `box_creation_placeholder` (when level is set).
- **main.py** — Uses `app.config.DEBUG`; logging config; request/response and workflow logs; debug-only full payload; `_workflow_state_to_response` maps `level`, `levelSource`, `topic`, `reachedBoxCreation`; Mermaid updated for new flow and “level? no only if inference failed”.
- **README.md** — Added “HOW TO SEE LOGS LIVE” (PyCharm Run/Debug, terminal, debug mode vs non-debug).

## 4. Example request JSON that exercises inferred-level behavior

No CEFR in the prompt; level should be inferred from existing words (and/or boxes):

```json
{
  "requestId": "req-infer-001",
  "customerId": "cust-1",
  "prompt": "I want more words for restaurants and ordering food",
  "defaultLanguage": "en",
  "targetLanguage": "es",
  "existingBoxes": [
    { "boxId": "box-1", "boxName": "Basics", "completionPercent": 30 }
  ],
  "existingWords": [
    { "default": "hello", "target": "hola" },
    { "default": "please", "target": "por favor" },
    { "default": "thank you", "target": "gracias" },
    { "default": "water", "target": "agua" },
    { "default": "bill", "target": "cuenta" },
    { "default": "menu", "target": "menú" }
  ]
}
```

## 5. Example response JSONs

**A. Level explicit (user said “B1” in prompt):**

```json
{
  "requestId": "req-explicit-001",
  "defaultLanguage": "en",
  "targetLanguage": "es",
  "status": "generated_placeholder",
  "userMessage": "Ready to generate (placeholder).",
  "boxes": [],
  "level": "B1",
  "levelSource": "explicit",
  "topic": "travel vocabulary",
  "reachedBoxCreation": true
}
```

**B. Level inferred (no CEFR in prompt; inferred from words/boxes):**

```json
{
  "requestId": "req-infer-001",
  "defaultLanguage": "en",
  "targetLanguage": "es",
  "status": "generated_placeholder",
  "userMessage": "Ready to generate (placeholder).",
  "boxes": [],
  "level": "A2",
  "levelSource": "inferred",
  "topic": "restaurant vocabulary",
  "reachedBoxCreation": true
}
```

## 6. HOW TO SEE LOGS LIVE

See **README.md** section “HOW TO SEE LOGS LIVE”. Summary:

- **PyCharm Run/Debug:** Logs appear in the Run or Debug tool window.
- **Terminal:** Run `uvicorn main:app --reload --port 2024 --host 0.0.0.0`; logs go to that terminal.
- **Debug mode:** Set `DEBUG=true` to log the full request body at debug level (local only). Without DEBUG, only summary fields are logged (no full prompt/payload).
