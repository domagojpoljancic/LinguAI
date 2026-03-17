# Box generation workflow (integrated)

## Files touched

- `app/box_workflow.py` — `db_retrieval_attempt`, `retrieval_quality_assessment`, `route_after_retrieval_quality`, `ai_word_generation`, `result_merge_and_filter`, `box_creation_finalize`, `async_persist_ai_words`
- `app/graph.py` — full node chain + conditional AI branch
- `app/state.py` — debug/integration fields
- `app/vocab_store.py` — `retrieve_candidates` returns phases; `persist_ai_fallback_pairs`
- `app/vocab_schema.py` — `ai_fallback` source_type + migration
- `app/ai_word_generator.py` — `WORD_GEN_TIMEOUT` default **18s**
- `main.py` — `BackgroundTasks` persist; `/debug/graph/*` ASCII + Mermaid
- `scripts/eval_workflow_integration.py` — E2E reports for listed prompts

## Routes

| Route | Behavior |
|-------|----------|
| **db_first** | DB first. If ≥20 **primary**-topic rows in retrieval → DB only (no AI call). Else if EN→DE/ES → AI top-up; on AI failure → DB only. |
| **ai_first** | AI first (when EN→DE/ES). ≥20 validated AI → AI-only list. &lt;20 → AI then DB fill. AI fail / wrong lang → full DB fallback. |
| **mixed** | Always calls AI when EN→DE/ES. Merge: primary DB → widened DB → AI (by confidence), dedupe, DB wins ties. |

## Timeout

- **`WORD_GEN_TIMEOUT`** default **18** (seconds) for interactive safety. Override via env. Separate from relevance/level/topic LLM timeouts.

## OpenAI failure → DB

- Any empty validated list after an AI attempt with failure reason, or missing key → merge uses DB rows only; `db_fallback_used=True` where applicable.

## Merge

- Deduplication on normalized `(default, target)`.
- DB-first sufficient: no AI.
- Top-up / fill: DB preferred when filling after AI (ai_first partial).
- Mixed: strict ordering primary → widened → AI.

## Async persistence

1. `box_creation_finalize` sets `persist_ai_fallback_pairs` (only words with `source=ai` in the merged list).
2. After `graph.invoke`, `main.generate_boxes` schedules `persist_ai_fallback_pairs()` on **FastAPI `BackgroundTasks`**.
3. **INSERT OR IGNORE** on unique pair; `source_type=ai_fallback`.
4. **Limitation:** On serverless or process exit right after response, background work may not run; use a job queue for durability.

## Eval

```bash
cd <repo> && PYTHONPATH=. python3 scripts/eval_workflow_integration.py
```

Requires `OPENAI_API_KEY` for relevance, topic (when needed), level inference, and AI word gen.

## MVP readiness (backend box gen)

**~7.5 / 10** — Integrated DB+AI merge, routing, persist-after-response, debug graphs aligned. Gaps: AI lang pair limited to EN→DE/ES; phrase requests still yield single-word pairs; broad topic coverage depends on DB seed + persisted AI rows.
