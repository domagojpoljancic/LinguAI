# AI fallback word generation

## Files changed / added

| Path | Role |
|------|------|
| `app/prompts/word_generation.py` | `WordGenerationContext`, `SYSTEM_INSTRUCTIONS`, `build_user_message()` |
| `app/ai_word_generator.py` | Responses API call, JSON schema, validation, `WordGenerationResult`, `generate_word_pairs()` |
| `app/state.py` | `ai_used`, `ai_candidate_count`, `ai_validated_count`, `ai_failure_reason` (for Prompt 3 merge) |
| `app/graph.py` | Docstring: AI module not in graph |
| `main.py` | Debug ASCII: `decide_retrieval_route` node, state keys, AI capability footer; Mermaid: route node + `ai_word_generator` subgraph |
| `scripts/eval_ai_word_generation.py` | Isolated eval: topic + route + generation |
| `requirements.txt` | `openai>=1.50.0` |
| `docs/AI_WORD_GENERATION.md` | This doc |

## Prompt builder location

- **`app/prompts/word_generation.py`**
  - `SYSTEM_INSTRUCTIONS` — rules (single words, high confidence, practical vocab).
  - `WordGenerationContext` — all inputs including `retrieval_route`, languages, level, topic, keywords, situation, reason, existing words/pairs.
  - `build_user_message(ctx)` — full user block for the API.

## Model / API

- **OpenAI Responses API** — `client.responses.create(...)`
- **Model:** `gpt-4o-mini` (override with `OPENAI_WORD_GEN_MODEL`)
- **Structured output:** `text.format.type = "json_schema"`, `strict: true`, schema name `vocabulary_word_pairs`
- **Timeout:** `WORD_GEN_TIMEOUT` (default 45s) on `OpenAI()` client

## Response schema (API)

```json
{
  "type": "object",
  "properties": {
    "items": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "default": { "type": "string" },
          "target": { "type": "string" },
          "confidence": { "type": "number" }
        },
        "required": ["default", "target", "confidence"],
        "additionalProperties": false
      }
    }
  },
  "required": ["items"],
  "additionalProperties": false
}
```

## Validation / filtering

- Empty `default` / `target`
- Not exactly one whitespace-separated token per field (`_is_single_token`)
- Length / garbage heuristics (`_looks_like_garbage`: URLs, all-punct, etc.)
- `confidence < WORD_GEN_MIN_CONFIDENCE` (default 0.72)
- Duplicate `(default_lower, target_lower)` or duplicate default lemma vs existing user vocabulary

Returns `ValidatedWordPair` with `source="ai_generated"`.

## Failure handling

- Missing API key → `ai_failure_reason="missing_api_key"`, empty list, no raise
- Timeout / rate limit / API errors → reason string, empty list
- Bad JSON / empty items → `malformed_output` or `empty_model_output`
- All rows filtered → `all_items_filtered`

`generate_word_pairs` **never raises** to callers.

## Graph / debug

- LangGraph unchanged (no new node).
- `/debug/graph/ascii`: full node list includes `decide_retrieval_route`; state summary includes AI fields; footer describes `ai_word_generator`.
- `/debug/graph/render`: Mermaid shows `decide_retrieval_route` and dashed edge to AI module subgraph.

## Evaluation

```bash
python scripts/eval_ai_word_generation.py
```

Output: `logs/eval_ai_word_generation.json`.

## Latest validation run (example)

| Prompt | route | raw | validated | filtered | notes |
|--------|-------|-----|------------|----------|-------|
| football words in German | ai_first | 22 | 22 | 0 | goal/Tor, match/Spiel, … |
| basketball vocabulary in Spanish | ai_first | 22 | 22 | 0 | sensible sports terms |
| words for going to the gym | ai_first | 23 | 22 | 0 | gym/fitness DE |
| phrases for talking to a landlord | ai_first | 22 | 21 | 1 | rent/Miete, landlord/Vermieter |
| business small talk in German | db_first | 22 | 22 | 0 | still valid AI vocab for eval |

## Risks before full integration

- Translations not verified against a gold lexicon; occasional weak pair (e.g. nuance of “score”).
- Strict single-token rule may drop valid compounds written as two words in EN.
- Quota/latency under load; merge step should cap AI pairs and prefer DB when `db_first`.
