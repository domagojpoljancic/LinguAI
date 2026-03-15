# Feasibility Study: German as Source Language (defaultLanguage)

**Date:** 2026-03-15  
**Scope:** Assessment only. No implementation.  
**Goal:** Support vocabulary generation where the **source word is German** and the **target word** is English (or ES, HR), e.g.:

```json
{
  "prompt": "Ich möchte A1 Restaurantvokabeln auf Englisch lernen",
  "defaultLanguage": "de",
  "targetLanguage": "en"
}
```

---

## 1. Executive summary

| Question | Answer |
|----------|--------|
| **Feasible?** | **Yes**, with moderate engineering effort. |
| **Best approach** | **DE→EN**: Use existing EN CEFR + EN Wiktionary and **invert** the pair (no German CEFR list required). **DE→ES / DE→HR**: Add German Wiktionary (kaikki de-extract) or triple-join EN CEFR + EN→DE + EN→ES. |
| **German CEFR list?** | No open, machine-readable OLP-style list. Goethe A1/A2/B1 exist as PDFs; Profile deutsch is commercial. For DE→EN we can reuse EN CEFR levels by inverting pairs. |
| **Schema changes?** | **None.** `vocab_entries` already has `(source_language, target_language, default_text, target_text)`. |
| **Retrieval changes?** | **None.** `retrieve_candidates(source_language, target_language, ...)` already filters by language pair. |
| **Recommendation** | **Proceed** for DE→EN (low effort); plan separate ingestion path for DE→ES / DE→HR (medium effort). |

---

## 2. Data source investigation

### 2.1 Wiktionary (kaikki.org)

| Source | Type | CEFR | Size (approx) | Languages | License | Ingestion difficulty |
|--------|------|------|---------------|-----------|---------|------------------------|
| **kaikki.org-dictionary-English.jsonl** (current) | Dictionary | No (we add via CEFR join) | ~1.45M lines, ~2.7 GB | EN→DE, EN→ES, EN→sh (HR) | CC BY-SA 4.0 | Already used |
| **kaikki.org-dictionary-German.jsonl** (postprocessed) | Dictionary | No | 942 MB | DE headwords (from enwiktionary) | CC BY-SA 4.0 | **Low** if structure matches; deprecated soon |
| **de-extract.jsonl** (raw Wiktextract, dewiktionary) | Dictionary | No | 2.8 GB (279 MB .gz) | DE headwords → translations (en, es, etc.) | CC BY-SA 4.0 | **Medium**: same Wiktextract schema (word, senses[].translations[] with code/word/sense) but from German Wiktionary; may need lang-code handling |

**Finding:**  
- For **DE→EN** we do **not** need a German dump. We can keep using the **English** Wiktionary: each EN headword has DE translations. So we can produce rows `(source_language=de, target_language=en, default_text=<DE translation>, target_text=<EN headword>, level=<from CEFR>)`. Same CEFR list, same file; only the join step writes the pair inverted.  
- For **DE→ES** and **DE→HR** we need either (1) **German Wiktionary** (de-extract) with ES/sh translations, or (2) **triple join**: EN CEFR + EN→DE + EN→ES (match on EN headword, output DE–ES pairs). Option (2) uses only current data; option (1) requires a new ingestion path for de-extract.

### 2.2 CEFR German vocabulary lists

| Source | Type | CEFR levels | Size / coverage | License | Ingestion difficulty |
|--------|------|-------------|----------------|---------|------------------------|
| **Open Language Profiles (OLP)** | CEFR list | N/A for DE | **No German profile.** Only EN (CEFR-J) and Mandarin. | CC | N/A |
| **Goethe-Institut** | CEFR list | A1, A2, B1 | A1/A2/B1 word lists (PDF). A2 ~800–1000 words. | Proprietary / educational | **Medium**: PDF extraction or manual; no single CSV |
| **Profile deutsch** | CEFR list | A1–C2 | Full CEFR; vocabulary + grammar. | Commercial (book + CD-ROM) | **High**: not freely downloadable; CD-ROM only |
| **DWDS / Goethe-Wortschatz** | Dictionary / list | Linked to Goethe levels | Machine-readable (API/CSV mentioned in some docs); exact download unclear | Varies | **Medium** if CSV/API available |

**Finding:**  
There is **no** open, single machine-readable German CEFR list equivalent to `olp-en-cefrj`. For **DE→EN** we avoid this by reusing the **English** CEFR list and inverting the pair (German translation becomes `default_text`, English headword becomes `target_text`). For a future **German-led** pipeline (e.g. DE→ES with German CEFR levels), we would need either Goethe PDFs, Profile deutsch (commercial), or a community list.

### 2.3 Other potential sources

| Source | Type | CEFR | DE relevance | License | Ingestion difficulty |
|--------|------|------|---------------|--------|------------------------|
| **Tatoeba** | Sentence corpus | No | DE↔EN ~331k pairs; DE↔ES/HR available | CC BY 2.0 / CC0 | **Medium**: sentence-level; need alignment/extraction for word pairs |
| **Leipzig Corpora** | Frequency lists | No | DE frequency lists available | CC BY 4.0 | **Medium**: no CEFR; could combine with level mapping later |
| **OPUS / OpenSubtitles** | Parallel corpora | No | DE–EN etc. | Various | **Medium–High**: sentence-level, alignment |
| **PanLex** | Lexical database | No | Multi-language word pairs | CC BY 4.0 | **Medium**: different schema; no CEFR |
| **ELRC-SHARE** | Corpora | No | DE–EN, DE–ES etc. | Various | **Medium**: sentence/corpus level |

**Finding:**  
Useful for **supplementing** or for future phrase-level features. Not required for MVP of DE-as-source; primary path is CEFR + Wiktionary (inverted for DE→EN, or German Wiktionary for DE→ES/DE→HR).

---

## 3. Pipeline impact

### 3.1 Current pipeline (summary)

- **CEFR:** `scripts/ingestion/cefr.py` loads Open Language Profiles **English** CSV (`headword`, `CEFR`). Output: `dict[headword_norm, level]` (English headwords).
- **Wiktionary:** `scripts/ingestion/wiktionary.py` loads **kaikki.org English** JSONL; extracts `word`/`head` and `translations` / `senses[].translations` for target langs (`de`, `es`, etc.). Returns `{target_lang: {headword: [(word, sense_gloss), ...]}}` (EN headword → translation + gloss).
- **Join:** `scripts/ingestion/join.py` joins CEFR (EN headwords + levels) with Wiktionary (EN→target). Produces rows with `source_lang="en"`, `target_lang=de|es`, `default_text=EN headword`, `target_text=translation`. Topic from `scripts/ingestion/topics.py` via **English** keyword match on headword.
- **Write:** `scripts/ingestion/write_db.py` and `app/vocab_schema.py`: same schema for any `(source_language, target_language, default_text, target_text)`.

### 3.2 Does the pipeline assume English headwords?

| Component | Assumption | Impact for German source |
|-----------|------------|---------------------------|
| **CEFR** | English headwords only (OLP EN list). | For **DE→EN** we keep using EN headwords; we just **swap** default_text and target_text when writing (DE word = default_text, EN word = target_text). No German CEFR list needed. |
| **Wiktionary loader** | Reads **English** JSONL; headword = EN. | For DE→EN we still use the same file; we only change how we build the row (translation → default_text, headword → target_text). For DE→ES/DE→HR we need either German Wiktionary or triple join. |
| **Join** | `cefr_headword_to_level` keys = EN; `headword_to_translations` keys = EN. | For DE→EN: join unchanged; after join, when building the row, set `default_text=translation`, `target_text=headword`, `source_lang="de"`, `target_lang="en"`. |
| **Topic tagging** | `topics.py` uses **English** keyword lists (restaurant, travel, …) on `default_text`. | For DE headwords, many product topics are cognates (Restaurant, Hotel, Ticket, Business). Native German words (e.g. Tisch, Essen) would not match. **Options:** (1) Add German keywords to `TOPIC_KEYWORDS` / `TOPIC_SENSE_KEYWORDS`, or (2) tag by CEFR list metadata if available, or (3) accept more "general" for pure German words initially. |

### 3.3 Required pipeline changes (by scenario)

**Scenario A: DE→EN only (invert current pipeline)**

- **Ingestion:**  
  - Keep: same CEFR load, same Wiktionary load (EN→DE).  
  - Change: in join/write, for a "DE as source" mode, output  
    `source_language=de`, `target_language=en`,  
    `default_text=translation` (German), `target_text=headword` (English),  
    `level=level`, `topic=tag_topic(translation)` (prefer tagging on German word; may need DE keywords).  
  - Alternatively, keep topic from current logic by tagging the **English** headword before invert, so topic is still derived from EN (same as today), then assign that topic to the inverted row.
- **New entrypoint:** e.g. `--source-lang de --target-lang en` (or a separate script path) that runs the same load but with inverted row construction.
- **Complexity:** **Low** (small change in join/write and topic handling).

**Scenario B: DE→ES and DE→HR**

- **Option B1 – Triple join (no German Wiktionary):**  
  Load EN CEFR + EN→DE + EN→ES (and EN→sh for HR). For each EN headword with level, take one DE and one ES (or sh) translation; output `(de, es, de_word, es_word, level)` and `(de, hr, de_word, hr_word, level)`. Sense-aware selection should prefer same sense for DE and ES (e.g. same gloss).  
  - **Complexity:** **Medium** (new join logic; two translation dicts keyed by EN headword).

- **Option B2 – German Wiktionary (de-extract.jsonl):**  
  New loader that reads **German** Wiktextract JSONL (headword = DE), extracts translations to `en`, `es`, `sh`. Then we need **German CEFR** or a level source. Without German CEFR we could: (i) use level from a separate small list, or (ii) leave level NULL and rely on topic/score, or (iii) map EN CEFR to DE words via EN Wiktionary (EN headword → DE translation, then use that EN level for the DE word).  
  - **Complexity:** **Medium–High** (new file format path, possibly different field names; CEFR handling for DE).

### 3.4 CEFR alignment with German headwords

- **DE→EN:** CEFR alignment is **preserved** by reusing the English CEFR list: the level is that of the English headword, which is the target. So "this German word is the translation of an A1 English word" ⇒ we store level A1 for that DE→EN pair. No German CEFR list required.
- **DE→ES / DE→HR:** If we use triple join (EN CEFR + EN→DE + EN→ES), same idea: level comes from the EN headword. If we use German Wiktionary only, we need another level source (Goethe, Profile deutsch, or NULL).

### 3.5 Estimated vocabulary size (DE→EN, inverted pipeline)

- Current CEFR list: **6,867** distinct English headwords.  
- Current EN→DE coverage (from existing docs): **~92%** CEFR overlap (~6,338 headwords).  
- **DE→EN:** Same counts: **~6,300+** rows achievable (one row per CEFR headword that has a DE translation). No new data source required.

---

## 4. Database design impact

### 4.1 Schema

- **Table:** `vocab_entries` already has `source_language`, `target_language`, `default_text`, `target_text`, `level`, `topic`, `tags`, `score`, `source_type`.  
- **Uniqueness:** `(source_language, target_language, default_text, target_text)`.  
- **Indexes:** `(source_language, target_language, topic)` and `(source_language, target_language, topic, level)`.

**Conclusion:** **No schema change** needed. DE→EN, DE→ES, DE→HR are just additional values of `(source_language, target_language)`.

### 4.2 Uniqueness and retrieval

- Uniqueness is per language pair and per (default_text, target_text). So (de, en, "Hallo", "hello") coexists with (en, de, "hello", "Hallo") without conflict.  
- Retrieval in `app/vocab_store.py` uses `WHERE source_language = ? AND target_language = ? AND topic IN (...)`. So `retrieve_candidates("de", "en", ...)` works as soon as we have rows with `source_language='de'` and `target_language='en'`.

**Conclusion:** **No change** to schema, indexes, or retrieval logic required for DE as source.

---

## 5. Prompt processing impact

### 5.1 Request flow

- Request already carries `defaultLanguage` and `targetLanguage` (e.g. `"de"`, `"en"`).  
- `main.py` puts them into state as `default_language`, `target_language`.  
- `box_creation_placeholder` calls `retrieve_candidates(default_lang, target_lang, ...)`.

So for `defaultLanguage: "de"`, `targetLanguage: "en"`, the only requirement is that the DB contains rows with `(source_language='de', target_language='en')`. No change to prompt flow for language pair selection.

### 5.2 Topic identification

- **Deterministic:** Uses keyword lists in `app/box_workflow.py` and `scripts/ingestion/topics.py` (English: restaurant, travel, etc.).  
- **AI:** Classifier maps natural prompt to internal topic; prompt can be in any language (e.g. "Ich möchte Restaurantvokabeln").

For **German prompts**, deterministic matching will work for cognates (Restaurant, Hotel, Ticket, Business, etc.). Pure German words (Tisch, Essen, Arzt) won’t match unless we add German keywords. So either:

- Add **German keywords** (and optionally sense keywords) for the same topics in `topics.py` and any workflow topic lists, or  
- Rely more on **AI** topic classification for German prompts and accept more "general" for deterministic path when no keyword matches.

### 5.3 Level and ranking

- Level resolution is CEFR-based and language-agnostic (A1–C2).  
- Ranking uses `default_text` for situation-hint matching and score/level. No English-specific logic.

**Conclusion:** Prompt workflow supports `defaultLanguage = "de"` once data exists. Only topic keyword coverage for German may need extension to improve topic-specific boxes for German prompts.

---

## 6. Summary table

| Area | Supports DE as source? | Change required |
|------|------------------------|-----------------|
| **Schema** | Yes | None |
| **Retrieval** | Yes | None |
| **Request/state** | Yes | None |
| **Topic (deterministic)** | Partial (cognates) | Add DE keywords for full coverage |
| **Topic (AI)** | Yes | Optional: mention DE in instructions |
| **CEFR (DE→EN)** | Yes | Use EN CEFR; invert pair in ingestion |
| **CEFR (DE→ES/HR)** | Yes if triple join or DE Wiktionary | New join or DE Wiktionary path |
| **Ingestion (DE→EN)** | Yes | Invert row (default_text ↔ target_text, source_lang=de, target_lang=en) |
| **Ingestion (DE→ES/HR)** | Yes | Triple join or load de-extract + level strategy |

---

## 7. Recommended approach and effort

### 7.1 DE→EN

- **Data:** Existing CEFR CSV + existing English Wiktionary JSONL.  
- **Logic:** Add an ingestion path (e.g. `--source-lang de --target-lang en`) that:  
  - Loads CEFR and EN→DE translations as today.  
  - Joins as today.  
  - Writes each row as `(de, en, translation_de, headword_en, level, topic, ...)`.  
  - Topic: keep tagging from English headword (or add German keywords and tag from DE word).  
- **Effort:** **Small** (on the order of 1–2 days including tests and a few manual checks).

### 7.2 DE→ES and DE→HR

- **Option 1 – Triple join:** Use EN CEFR + EN→DE + EN→ES (and EN→sh for HR); output (de, es) and (de, hr) pairs with same level.  
  - **Effort:** **Medium** (join and sense alignment logic, ~3–5 days).  
- **Option 2 – German Wiktionary:** Add loader for de-extract.jsonl; produce DE→en, DE→es; level from EN CEFR mapping or leave NULL/limited.  
  - **Effort:** **Medium–High** (new format, level strategy, ~5–8 days).

### 7.3 Topic keywords

- Add German equivalents (and optionally sense keywords) to `scripts/ingestion/topics.py` (and workflow topic lists if used for ranking) so that DE headwords get correct topic tags.  
- **Effort:** **Small** (half day to one day).

---

## 8. Conclusion and recommendation

- **Feasibility:** Supporting **German as source language** is **feasible** without schema or retrieval changes.  
- **DE→EN** is the lowest-effort path: reuse EN CEFR and EN Wiktionary and **invert** the vocabulary pair in ingestion; estimated **~6,300+** DE→EN entries.  
- **DE→ES** and **DE→HR** are feasible via triple join (current data) or German Wiktionary (new data); no German CEFR list is strictly required if we derive level from the English headword.  
- **Recommendation:** **Proceed** with implementation: implement DE→EN first (inverted pipeline), then add DE→ES/DE→HR via triple join or de-extract as a second phase. Extend topic keywords for German for better topic-specific boxes when the prompt is in German.

---

**Document version:** 1.0  
**No code changes were made; this is an analysis-only deliverable.**
