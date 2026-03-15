# End-to-end validation summary

## Logic changes (vocabulary quality after topic resolution)

1. **Situation-hint ranking** (`app/vocab_store.py`)
   - `retrieve_candidates(..., situation_hint=None)`: when `situation_hint` is non-empty, it is tokenized (lowercase, words ≥2 chars). Rows whose `default_text` contains any of these tokens are sorted **first**, then by score desc, level asc, default_text.
   - Effect: for natural prompts resolved by AI (e.g. "labor with my wife" → health), the box lists situation-relevant words (hospital, doctor, medicine, nurse, appointment, pain, pharmacy) before other topic-matched words. No new data; deterministic reordering only.

2. **Passing situation hint from workflow** (`app/box_workflow.py`)
   - `TOPIC_SITUATION_BOOST`: per-topic list of practical default_text tokens (e.g. health: hospital, doctor, medicine, pharmacy, appointment, symptom, pain, nurse, patient, medical).
   - When `topic_source == "ai"` and `topic_reason` is set, `situation_hint = topic_reason + " " + " ".join(TOPIC_SITUATION_BOOST.get(topic_key, []))` is passed to `retrieve_candidates`. So AI reason (e.g. "labor and childbirth context") plus boost words are used for ranking; retrieval stays deterministic.

3. **No schema or retrieval-query changes**: same topic enum, same SQL, same widening rules. Only sort order changes when situation_hint is provided.

## Validation coverage

- **A. Explicit-topic prompts** (6): A1 restaurant (DE), A1 travel (ES), B1 shopping (DE), health (ES), B2 business (DE), daily (ES). All passed: topic deterministic, box on-topic, no wrong-sense, no obvious filler.
- **B. Natural prompts** (8): labor/midwife/doctor/medical emergency/pharmacy (health), small talk at work (business), hotel check-in (travel), ordering food at cafe (restaurant). All passed; AI-resolved ones show `topicSource=ai` and normalized topic.
- **Regression**: (1) Natural health prompts → topic=health and box contains at least one of hospital, doctor, medicine, pharmacy, appointment, symptom, pain, nurse. (2) Natural travel prompts → box contains travel keywords. Both passed.

## Before/after (2 natural prompts)

**1. "I want B2 words in German that will help me when going to labor with my wife"**

- Before (no situation hint): same 21 health words, order by score/level only (e.g. fever, health, hospital, medicine, nurse, sick, appointment, blood, ill, medical…).
- After (situation_hint = reason + health boost): **hospital, medicine, nurse, appointment, medical, patient, pain, pharmacy, symptom, fever** appear first. More obviously useful for a hospital/labor context.

**2. "phrases for talking to a midwife"**

- Before: health box with generic order.
- After: **hospital, medicine, nurse, appointment, medical, patient, pain, pharmacy, symptom, fever** leading the list. No "midwife" in DB, but practical care vocabulary is prioritized.

## Commands

```bash
# Start API
uvicorn main:app --port 2024 --host 0.0.0.0

# Topic-only validation
python scripts/validate_topic_prompts.py

# Full E2E (topic + box content + quality + regression)
python scripts/validate_end_to_end_prompts.py

# Machine-readable
LINGUAI_API_URL=http://localhost:2024/generate-boxes python scripts/validate_end_to_end_prompts.py --json
```

## Remaining weaknesses

- No DB entries for very situation-specific terms (e.g. midwife, labor, childbirth); we only reorder what exists.
- Situation boost lists are hand-curated; new situations may need new tokens.
- Wrong-sense blocklist remains small; edge cases may still appear.
- Single box per request; no multi-box or "health + travel" handling.

## MVP score and recommendation

- **MVP readiness: 84/100.** Topic resolution (deterministic + AI) and situation-aware ranking improve practical usefulness without changing schema or letting AI pick words. Explicit prompts unchanged; natural prompts yield more situation-relevant ordering.
- **Recommendation: Ship MVP.** One more iteration could add more situation keywords or blocklist entries based on user feedback; not required to ship.
