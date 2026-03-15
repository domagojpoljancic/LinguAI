# Flexible-Topic Implementation: Design, Logic, and Validation

## 1. Files changed

| File | Change |
|------|--------|
| **app/state.py** | Added `topic_keywords: List[str]`, `situation_label: str` to `BoxWorkflowState`. |
| **app/schemas.py** | Added `STATUS_TOPIC_NOT_SUPPORTED`; added `topicKeywords`, `situationLabel` to `GenerateBoxesResponse`. |
| **app/ai_topic_classifier.py** | Extended to return `topic_keywords`, `situation_label`; added "unsupported" to allowed topics; updated system prompt so AI returns "unsupported" for sports, gym, landlord, etc., and richer JSON. |
| **app/box_workflow.py** | Deterministic path now sets `topic_keywords` and `situation_label`; AI path passes them through. Added `_build_situation_hint()` from reason + keywords + situation_label. In `box_creation_placeholder`: (1) early return with `topic_not_supported` when topic is "unsupported" or general with confidence < 0.5; (2) situation_hint built from richer metadata; (3) guardrail: if topic is "general" and retrieval returned only widened words (primary_candidate_count == 0, final_count > 0), return `topic_not_supported` instead of a box. Added `TOPIC_NOT_SUPPORTED_MESSAGE`. |
| **app/vocab_store.py** | In `_primary_and_widen_topics`, when `display_topic == "unsupported"` return `("unsupported", [])` so retrieval returns 0 words (defensive). |
| **main.py** | `_workflow_state_to_response` now maps `topic_keywords` → `topicKeywords`, `situation_label` → `situationLabel`. |
| **scripts/validate_flexible_topics.py** | New script: runs 8 prompts (supported + unsupported), checks status/box/useful/honest_fail, writes `logs/flexible_topic_validation.json`. |
| **docs/FLEXIBLE_TOPICS_IMPLEMENTATION.md** | This document. |

---

## 2. Exact logic added

### Topic understanding (richer output)

- **Deterministic path:** When keyword match hits a known topic, we now also set `topic_keywords` from `TOPIC_KEYWORDS[topic_key][:5]` and `situation_label` from `TOPIC_TO_BOX_NAME[topic_key]`.
- **AI path:** Classifier returns `topic`, `confidence`, `reason`, `topic_keywords` (list), `situation_label`. All passed through state. "unsupported" is a valid topic when the prompt is about sports, gym, landlord, etc.

### Retrieval use of richer metadata

- **Situation hint:** `_build_situation_hint(state, topic_key)` concatenates `topic_reason`, `topic_keywords` (up to 10), `situation_label`, and `TOPIC_SITUATION_BOOST.get(topic_key, [])[:5]`. This string is passed to `retrieve_candidates(..., situation_hint=...)`. Retrieval is unchanged: still filter by `topic IN (primary, widened)`; ranking uses hint tokens to put situation-relevant words first (existing behavior).

### Guardrails (no junk boxes)

1. **Early exit:** If `topic == "unsupported"` or `(topic == "general" and topic_confidence < 0.5)`, we do not call retrieval. We return `status=topic_not_supported`, `boxes=[]`, `user_message=TOPIC_NOT_SUPPORTED_MESSAGE`, `reached_box_creation=True`.
2. **Post-retrieval guardrail:** If `topic == "general"` and `primary_candidate_count == 0` and `final_count > 0` (we would return only widened/daily/generic words), we discard the result and return the same `topic_not_supported` response instead of a box.

### Vocab_store

- For `display_topic == "unsupported"`, `_primary_and_widen_topics` returns `("unsupported", [])`, so `fetch_for_topics([])` is not used but if it were called with `["unsupported"]` we’d get 0 rows. Box workflow skips retrieval for unsupported anyway.

---

## 3. How topic understanding was extended

- **State:** `topic_keywords: List[str]`, `situation_label: str` added; `topic` can be `"unsupported"` as well as the existing enum.
- **AI classifier:** Prompt updated to (1) list "unsupported" and when to use it (sports, gym, real estate, niche); (2) require `topic_keywords` and `situation_label` in JSON. Parser fills `topic_keywords` (list, max 15) and `situation_label` (max 100 chars). `normalize_topic()` passes "unsupported" through.
- **Deterministic:** Still uses `TOPIC_KEYWORDS` and returns one of the supported topics; we now also populate `topic_keywords` and `situation_label` from the same topic for consistency.

---

## 4. How retrieval uses the richer topic info

- Retrieval is still **deterministic**: filter by `(source_language, target_language, topic IN (primary, widened))`. No new DB columns or tag-based query.
- **Ranking:** `situation_hint` is built from `topic_reason` + `topic_keywords` + `situation_label` + boost list. Existing `retrieve_candidates(..., situation_hint=...)` tokenizes the hint and ranks rows whose `default_text` contains any hint token higher. So for "words for labor with my wife" we get keywords like ["labor", "birth", "hospital"] and situation "labor and childbirth", and health-topic rows matching those words rank first.

---

## 5. What guardrail prevents junk boxes

- **Unsupported / vague general:** Before retrieval, if `topic == "unsupported"` or `(topic == "general" and topic_confidence < 0.5)`, we never run retrieval and return `topic_not_supported` with a fixed message. So "football words", "gym", "landlord" get an honest "we don't have that" instead of a box of daily/generic words.
- **General but retrieval would be junk:** If we did run retrieval (e.g. topic "general" with higher confidence) and get `primary_candidate_count == 0` but `final_count > 0`, we refuse to return that box and instead return `topic_not_supported`. So we never return a box built only from widened/daily/general when the effective topic was generic.

---

## 6. Validation results

Script: `scripts/validate_flexible_topics.py` (server must be running).

| Prompt | Interpreted topic/situation | Retrieval behavior | Box returned? | Useful? | Honest fail? |
|--------|----------------------------|--------------------|---------------|---------|--------------|
| A1 restaurant words in German | restaurant, deterministic, keywords + Street Eats | primary topic restaurant | Yes | Yes | Yes |
| B1 travel vocabulary in Spanish | travel, deterministic, City Break | primary topic travel | Yes | Yes | Yes |
| football words in German | unsupported, ai, football/sport | skipped (unsupported) | No | Yes | Yes |
| basketball vocabulary in Spanish | unsupported, ai, basketball/sport | skipped | No | Yes | Yes |
| words for going to the gym | unsupported, ai, gym/fitness | skipped | No | Yes | Yes |
| phrases for the airport | travel, deterministic | primary topic travel | Yes | Yes | Yes |
| vocabulary for talking to a landlord | unsupported, ai, landlord/rent | skipped | No | Yes | Yes |
| words for labor with my wife | health, ai, labor/birth/hospital | primary topic health, situation ranking | Yes | Yes | Yes |

**Summary:** 8/8 useful outcome, 8/8 honest (box when supported, no junk when unsupported). Unsupported topics now fail with `topic_not_supported` and a clear message instead of generic vocabulary.

---

## 7. Remaining limitations

- **Tag/keyword search in DB:** We do not query by `tags` or free-form keywords; retrieval is still only by `topic IN (...)`. So we cannot fulfill "football" by searching tags until ingestion adds such tags and we extend retrieval.
- **AI variability:** "Labor with my wife" is mapped to health by the classifier; a different model or prompt could occasionally misclassify. Confidence threshold (0.5 for general) and guardrails limit damage.
- **New status:** Clients must handle `status === "topic_not_supported"` and show `userMessage` (or a localized string).
- **Supported set is fixed:** Adding a new supported topic (e.g. "sports") still requires ingestion + topic key + mapping in `TOPIC_KEYWORDS` / `_primary_and_widen_topics`; this change does not add new topics, only honest refusal for unsupported ones and richer metadata for supported ones.

---

## 8. MVP readiness

- **Before:** Unsupported prompts (e.g. "football words") collapsed to "general" and returned irrelevant generic boxes. **After:** Unsupported prompts return `topic_not_supported` and a clear message; supported prompts still get deterministic retrieval and situation-aware ranking.
- **Backward compatibility:** Supported topics and response shape unchanged; new optional fields (`topicKeywords`, `situationLabel`) and one new status (`topic_not_supported`).
- **Determinism:** No AI-generated vocabulary; retrieval remains deterministic; only understanding/classification uses the LLM.
- **MVP readiness score:** Ready for MVP: supported topics behave as before, unsupported topics fail honestly, and the API contract is extended in a backward-compatible way with a clear path for clients to handle unsupported topics.
