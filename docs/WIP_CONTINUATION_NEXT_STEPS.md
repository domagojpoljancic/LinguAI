# WIP Continuation — Next Steps

**Read this file first when resuming.** Last updated: snapshot at WIP commit.

**Honest state:** Hybrid DB+AI box generation is integrated but **not fully validated end-to-end**. Treat production use with caution until the verification checklist below is green.

---

## A. Current Architecture Snapshot

### Graph structure (execution order)

```
Start
  → request_understanding (LLM: structured intent JSON)
  → [if not relevant] END (or legacy relevance_check re-validation if confidence low)
  → topic_identification (keywords + typo/fuzzy OR Chat Completions classifier)
  → decide_retrieval_route (db_first | ai_first | mixed — deterministic)
  → level_resolution (regex CEFR OR LLM infer)
  → db_retrieval_attempt (SQLite by topic/lang/level)
  → retrieval_quality_assessment (counts primary-topic DB rows)
  → [branch] ai_word_generation OR skip straight to merge
        • Skip AI if: lang pair not both in {en,de,es,fr,it,pt,nl,pl} OR (db_first AND ≥20 strong primary DB rows)
  → result_merge_and_filter
  → box_creation_finalize
  → async_persist_ai_words (flag only; real SQLite write in FastAPI BackgroundTasks after HTTP)
  → END
```

### DB vs AI logic

| Route | Meaning |
|-------|---------|
| **db_first** | Strong curated topic + high confidence → DB first; if &lt;20 strong primary rows and AI allowed → AI top-up; AI fail → DB only. |
| **ai_first** | Sports, weather, gym, landlord keywords (prompt or classifier keywords) → AI first; ≥20 validated AI → AI-only list; else AI+DB mix; AI fail → DB only. |
| **mixed** | Vague/general → DB order then AI; dedupe; DB preferred on ties. |

### Where AI is actually used

| Step | API | When |
|------|-----|------|
| **request_understanding** | Chat Completions (`ChatOpenAI`) | First; produces `is_relevant/topic/topic_keywords/situation_label/route_hint/level_hint` as structured JSON |
| **relevance_check** | Chat Completions (`_get_llm`) | Every relevant path |
| **topic_identification** | Chat Completions (`ai_topic_classifier`) | When deterministic topic confidence low or general |
| **level_resolution** | Chat Completions | When no A1–C2 in prompt |
| **ai_word_generation** | OpenAI **Responses API** + JSON schema | Only on branch above; **WORD_GEN_TIMEOUT** default ~18s |

**Not AI:** `decide_retrieval_route`, DB retrieval, merge, finalize (except empty handling).

---

## B. What Was Just Implemented

- **Routing:** Topic + confidence + prompt keywords (sports, weather, landlord, etc.) → db_first / ai_first / mixed.
- **Early request understanding:** `request_understanding` runs first and produces `is_relevant`, `topic`, optional `subtopic`, `situation_label`, `topic_keywords`, `route_hint`, optional `level_hint`, plus `confidence` and `reason` (structured JSON).
- **Coexistence / backward compatibility:** for high-confidence relevant inputs, downstream legacy `topic_identification` / `decide_retrieval_route` are skipped via `_request_understanding_applied`; for low-confidence cases it falls back to the legacy `relevance_check` path.
- **AI word gen:** Structured pairs, single-word validation, expanded language pairs (8 codes, distinct pairs).
- **Merge:** Route-specific ordering, dedupe, `final_mix_strategy` / debug fields on state.
- **Async persistence:** `persist_ai_fallback_pairs` after response via `BackgroundTasks`; `source_type=ai_fallback`; INSERT OR IGNORE.
- **Language inference:** `_resolve_language_pair` in `topic_identification` (prompt hints, fill missing side).
- **Typos / fuzzy:** Common typo map + fuzzy match on topic keywords before AI topic call.
- **Empty results:** `status=generation_empty` (not `generated_placeholder`) when zero words; user-facing retry message.
- **Topic classifier:** `unsupported` normalized to `general` in `normalize_topic`; prompt steers “general + keywords” for niche themes.
- **Evaluation:** `scripts/eval_workflow_regression.py` → `logs/eval_workflow_regression.json`; `scripts/eval_workflow_integration.py`; `scripts/validate_flexible_topics.py` (HTTP).

### Recently fixed (high-signal runtime/product issues)
- **LangGraph state propagation:** added missing internal underscore keys to the shared `BoxWorkflowState` so intermediate node outputs aren’t silently dropped.
- **OpenAI transport/proxy reliability:** added `openai_httpx_client()` + proxy-bypass retry so evaluation/runtime isn’t blocked by bad proxy env vars.
- **SQLite thread-safety (server path):** removed global cached SQLite connection reuse; each retrieval call uses its own connection (and closes it), so concurrent FastAPI threads don’t crash.
- **Relevance false negatives:** added a narrow fast-path in `relevance_check` for short vocabulary-intent prompts (e.g. `Basketball`, `Weather`, `Flowers`, `Cars`) and landlord-like intent.
- **Fake-success generic filler quality gate:** added a final integrity gate in `box_creation_finalize()` to prevent “niche” box names from returning mostly generic daily/basic filler.
- **Early request understanding node:** added `request_understanding` as the real graph entry point to consolidate structured intent (relevance/topic/keywords/route hint/level hint) before legacy nodes.

---

## C. Known Issues (CRITICAL)

| Issue | Status / notes |
|-------|----------------|
| **Football / weather** | **Recently addressed** (ai_first + weather keywords + broader AI langs). **Re-verify** with real API key; can still fail on timeout, over-filtering, or bad model output. |
| **`unsupported` topic** | Classifier should map to **general**; old code paths or cached behavior may still mention `unsupported` in logs. DB topic `"unsupported"` still yields **zero** rows if it ever leaks into retrieval. |
| **Empty boxes + success** | **Mitigated:** `generation_empty` when no words. **Must confirm** no remaining path returns `generated_placeholder` with `boxes=[]`. |
| **Typo sensitivity** | **Partially fixed** (restaruant → restaurant, fuzzy). Long tail of typos still possible. |
| **AI not triggered** | Happens if: wrong/missing langs outside allowed set, db_first with 20+ strong DB, missing API key, or branch skips node. |
| **Evaluation instability** | Results depend on **OPENAI_API_KEY**, model behavior, and latency; same script can pass/fail across runs. |
| **Niche specificity still brittle** | Even with the final quality gate, niche prompts can still be awkward if topic/situation extraction doesn’t anchor retrieval strongly enough. Quality gate prefers honesty (empty) over fake success, but exact niche coverage may still need tightening. |

Known good right now:
- Server/runtime path is thread-safe for SQLite retrieval (no cross-thread connection crashes).
- Fake-success generic filler degradation is gated off with `generation_empty` when niche content is weak.
- Short-topic relevance false-negatives have a narrow fast-path (Basketball/Weather/Flowers/Cars + landlord-like intent).

---

## D. What MUST Be Verified Next (checklist)

1. [ ] Run `scripts/eval_workflow_regression.py` **with** `OPENAI_API_KEY` set; inspect `logs/eval_workflow_regression.json`; exit code 0.
2. [ ] Run `scripts/eval_workflow_integration.py` with key; spot-check football, weather, typos.
3. [ ] Manually POST `/generate-boxes`: confirm **no** response with `status=generated_placeholder` and empty `boxes`.
4. [ ] POST a clear **ai_first** prompt (e.g. football en→de): confirm `ai_validated_count` / words in response (or `generation_empty` if fail — not fake success).
5. [ ] POST **A1 restaurant** en→es (seeded DB): confirm DB-first path and non-empty box without relying on AI if DB sufficient.
6. [ ] POST **“Words for restaruant”** en→de: confirm non-empty or explicit `generation_empty`, not `insufficient_confidence` from uncaught errors.

---

## E. Suggested Next Steps (PRIORITIZED)

1. **Stabilize input normalization** — expand typo dictionary; optional light spellcheck for topic tokens.
2. **Clean topic classification** — ensure no code path passes `unsupported` into `retrieve_candidates`; align ALLOWED_TOPICS / docs.
3. **Routing → AI execution** — add structured logging (route + `_ai_generation_attempted` + failure_reason) on every request; optional metrics.
4. **Finalization** — audit all branches for empty words; align `reachedBoxCreation` semantics with product.
5. **Evaluation** — pin or document model/env; add CI job that runs regression **with** secrets on schedule; widen edge cases (same-lang pair, very long prompt).

---
## H. What Still Feels Conceptually Weak
1. **Broad topic handling** is still split across multiple steps (relevance → topic classification → routing → merge). Even if each step is correct, combined behavior can drift.
2. **Niche prompts can still degrade awkwardly** if the interpreted `situation_label` / `topic_keywords` doesn’t anchor retrieval strongly enough.
3. **Prompt understanding may be better centralized earlier** in the workflow (reduce fragmentation across multiple LLM calls and heuristics).

---
## I. Suggested Next Architectural Direction (NOT yet implemented)
Consider a single early “AI understanding” step that produces structured output once, then downstream nodes consume it deterministically:
- relevance
- topic/subtopic
- `situation_label`
- `topic_keywords`
- route hint
- optional level hint

This is a future design direction only; it is **not implemented yet**.

---

## F. How to Run Everything

**Assumptions:** Repo root = `linguai-langgraph` (where `main.py` and `app/` live). Python venv activated if you use one.

```bash
# Env
export OPENAI_API_KEY="sk-..."
export DEBUG=true                    # optional, for debug endpoints + file logging

# Install (if needed)
pip install -r requirements.txt      # or project’s install path

# Start API
cd /path/to/linguai-langgraph
uvicorn main:app --host 0.0.0.0 --port 2024 --reload
```

**Evaluation (graph invoke, no server):**

```bash
cd /path/to/linguai-langgraph
PYTHONPATH=. python3 scripts/eval_workflow_integration.py
PYTHONPATH=. python3 scripts/eval_workflow_regression.py
# Output: logs/eval_workflow_regression.json (+ exit 1 if failures with key)
```

**Evaluation (HTTP, server must be up):**

```bash
BASE_URL=http://localhost:2024 python3 scripts/validate_flexible_topics.py
```

**Logs:**

- Request/response (debug): `logs/request_response.log` when `DEBUG=true`
- Regression JSON: `logs/eval_workflow_regression.json`
- Flexible-topic HTTP validation output: `logs/flexible_topic_validation.json`

**Debug endpoints** (require `DEBUG=true`):

```text
GET http://localhost:2024/debug/graph/ascii
GET http://localhost:2024/debug/graph/render
```

---

## G. Risks

| Risk | Impact |
|------|--------|
| **AI latency / timeout** | `generation_empty` or partial lists; tune `WORD_GEN_TIMEOUT` / model. |
| **BackgroundTasks** | Persist may not finish if process exits (serverless); not a durable queue. |
| **Missing vocab** | en-de (and others) thin in SQLite vs en-es seed; relies on AI top-up. |
| **Over-filtering** | Single-word + confidence rules drop valid pairs (esp. compounds/phrases). |
| **Idempotency** | Only successful `generated_placeholder` responses cached; `generation_empty` not cached by design — retries may repeat work. |

---

## Rollback

This WIP is intended as a **safe revert point**. If you need to undo:

```bash
git revert <this-commit-sha>
# or
git reset --hard <parent-commit>
```

Message on commit: *WIP: hybrid retrieval … UNTESTED, safe to revert*.
