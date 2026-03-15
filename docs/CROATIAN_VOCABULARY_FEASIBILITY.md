# Feasibility Study: English → Croatian Vocabulary Support

**Date:** 2026-03-15  
**Scope:** Data availability and suitability for EN→Croatian vocabulary in the LinguAI vocabulary pipeline. No implementation.

---

## 1. Executive summary

- **Croatian is feasible for MVP** using the **same architecture** (CEFR + Wiktionary-derived translations).
- **Primary source:** kaikki.org **English** dictionary JSONL. Croatian translations appear under the **Serbo-Croatian** code **`sh`**, not `hr`. There are **~17,809** unique English headwords with `sh` translations; **~4,300** of them overlap with the CEFR list (**62.6%** CEFR coverage).
- **Recommendation:** **Proceed** with Croatian support. Use `sh` → `hr` in ingestion; expect ~4.3k CEFR-aligned entries for MVP. Optional later: Tatoeba/OPUS/ELRC to fill gaps or add phrases.

---

## 2. Current pipeline (relevant parts)

- **Schema:** `vocab_entries` already has `source_language` and `target_language`; no schema change needed.
- **CEFR:** Open Language Profiles CEFR-J (English headwords + levels A1–C2). **6,867** distinct headwords. Language-agnostic; no Croatian-specific CEFR list used.
- **Translations:** `scripts/ingestion/wiktionary.py` reads the **kaikki.org English** JSONL and extracts `translations` from top-level and `senses[]`. It accepts target languages via `_LANG_ALIASES` and any **2-letter** code. Currently only `de`/`deu` and `es`/`spa` (and `fr`/`fra`) are in the alias map.
- **Join:** CEFR headwords are joined with Wiktionary translations; one row per (headword, level, topic, target_lang). Sense-aware selection prefers topic-aligned glosses.

**Finding:** The pipeline does **not** currently extract Croatian because:
1. The **English** kaikki file uses **`sh`** (Serbo-Croatian) for Croatian/Serbian/Bosnian translations, not `hr`.
2. Under the code `hr` there is effectively **one** erroneous entry in the full file (e.g. a Cyrillic “Serbian” translation tagged `hr`).
3. There is **no** `hrv` (ISO 639-3) in the sampled translation objects.

So for Croatian we must treat **`sh`** as the source of EN→Croatian translations and map it to `hr` for storage/display.

---

## 3. Wiktionary / kaikki.org English JSONL

| Aspect | Result |
|--------|--------|
| **Source** | kaikki.org English dictionary (same file as DE/ES: `kaikki.org-dictionary-English.jsonl`) |
| **Type** | Dictionary (EN headword → translations by lang code) |
| **EN→HR coverage** | **As `sh` (Serbo-Croatian):** ~17,809 unique EN headwords with ≥1 translation; **4,300** overlap with CEFR list (**62.6%** CEFR coverage). As `hr`: negligible (1 noisy entry). |
| **Dataset size** | Same file as today (~1.45M lines, ~2.7 GB). No extra download. |
| **Licensing** | CC BY-SA 4.0 (Wiktionary); kaikki is derived open data. |
| **Suitability** | High: same format and sense/gloss structure as DE/ES; topic-aware selection applies. |
| **Ingestion difficulty** | **Low:** add `sh`→`hr` in ingestion (request `sh`, store as `hr`). |

**CEFR coverage comparison (same CEFR list, same file):**

- DE: **92.3%** (6,338 headwords)
- ES: **92.7%** (6,367 headwords)
- **SH (as HR): 62.6%** (4,300 headwords)

So Croatian has lower coverage than DE/ES but still **thousands** of CEFR-aligned words, enough for an MVP.

---

## 4. Open Language Profiles (CEFR)

| Aspect | Result |
|--------|--------|
| **Source** | Open Language Profiles CEFR-J (English vocabulary with CEFR levels). |
| **Type** | Word list (EN headwords + A1–C2). |
| **Croatian-specific CEFR list?** | **No.** Only the **English** CEFR list exists; Croatian support reuses it and needs EN→HR translations for those headwords. |
| **Suitability** | Same as DE/ES: levels come from this list; no change for Croatian. |

---

## 5. Tatoeba

| Aspect | Result |
|--------|--------|
| **Source** | Tatoeba (tatoeba.org, manythings.org, ELRC-SHARE). |
| **Type** | Sentence corpus (EN↔HR sentence pairs). |
| **EN↔HR size** | ~1,340–6,028 pairs (sources differ); ELRC: 3,980 translation units (CC-BY-2.0). |
| **Licensing** | CC-BY 2.0 (Tatoeba/ELRC). |
| **Suitability for vocab** | Medium: useful for **extracting** word pairs (e.g. word alignment / simple heuristics), not a direct word list. |
| **Ingestion difficulty** | **Medium:** need sentence-level processing and alignment to get (word, translation) pairs. |

**Verdict:** Good for **supplementing** coverage or adding phrases later; not required for MVP.

---

## 6. OpenSubtitles / OPUS

| Aspect | Result |
|--------|--------|
| **Source** | OPUS (opus.nlpl.eu), OpenSubtitles. |
| **Type** | Parallel corpus (subtitles). |
| **EN–HR** | Available (e.g. OpenSubtitles includes EN–HR among 94 languages). |
| **Licensing** | OpenSubtitles attribution required; check specific OPUS subset. |
| **Suitability for vocab** | Medium: large but noisy; needs alignment and filtering to get clean word lists. |
| **Ingestion difficulty** | **High:** alignment, dedup, quality filtering. |

**Verdict:** Optional for future expansion; not needed for MVP.

---

## 7. Other open / bilingual resources

| Source | Type | EN→HR coverage | Licensing | Suitability | Ingestion |
|--------|------|----------------|-----------|-------------|-----------|
| **Freedict** | Dictionary | No dedicated EN–HR found in search. | Permissive | N/A | N/A |
| **Glosbe** | Dictionary / community | EN–HR exists; scale/export unclear. | Community / ToS | Possible supplement | Medium (API/export) |
| **PanLex** | Lexical DB | Croatian (hrv) covered; 1k+ entries. | CC0 | Good for gap-filling | Medium (API/CSV/JSON) |
| **ELRC MaCoCu hr-en** | Parallel corpus | Large (e.g. 2.2M segments v2). | CC0 | Good for future expansion | Medium–High (TMX, word extraction) |

---

## 8. Pipeline evaluation: does the repo already extract Croatian?

- **Wiktionary ingestion (`scripts/ingestion/wiktionary.py`):**
  - **Does not** currently treat Croatian. It only has `_LANG_ALIASES` for `de`/`deu`, `es`/`spa`, `fr`/`fra`. Any 2-letter code is accepted from the file, but the file has almost no `hr` and uses **`sh`** for Serbo-Croatian.
  - So the existing code does **not** extract Croatian unless we either (a) pass `target_langs = ["sh"]` and store as `target_language = "hr"`, or (b) extend the alias/normalization so that when target is `hr` we also collect translations with lang code `sh` and store as `hr`.
- **Normalization:** No change needed for text (NFKC, strip, single spaces). For **language code** we need to decide that **`sh`** in the JSONL is ingested as **`hr`** (Croatian) for the app.

---

## 9. Feasibility answers

1. **Is Croatian feasible for MVP now?**  
   **Yes.** ~4,300 CEFR-aligned EN→Croatian pairs are available from the same kaikki English JSONL via `sh`, with the same join and topic logic as DE/ES.

2. **What dataset would likely become the primary source?**  
   **kaikki.org English dictionary JSONL**, using translations with **lang code `sh`** (Serbo-Croatian), stored and displayed as **`hr`** (Croatian).

3. **What additional sources might improve coverage?**  
   - **Tatoeba / ELRC:** sentence pairs to extract more (word, translation) pairs and possibly phrases.  
   - **PanLex:** lexical DB (hrv) for gap-filling missing CEFR headwords.  
   - **MaCoCu / OPUS:** parallel corpora for future, higher-effort expansion.

---

## 10. Recommended primary source and MVP numbers

- **Primary source:** kaikki.org English JSONL, translations with **`sh`** → stored as **`hr`**.
- **Estimated MVP word coverage:** **~4,300** CEFR-tagged EN→Croatian entries (62.6% of the CEFR list).
- **Engineering effort (when you implement):** **Low.** One ingestion change: when target language is `hr`, request `sh` from the file and write `target_language = "hr"` (plus add `"sh": "hr"` in alias/normalization as needed). No schema change; no new CEFR source.

---

## 11. Risks

| Risk | Mitigation |
|------|------------|
| **Coverage lower than DE/ES** | 4.3k words is sufficient for MVP; document that HR has ~63% CEFR coverage; optionally add Tatoeba/PanLex later. |
| **Serbo-Croatian vs Croatian** | Wiktionary “sh” includes Croatian; spelling is largely shared; some regional/script variation possible; acceptable for learner vocabulary. |
| **Quality** | Same as DE/ES (Wiktionary community data); sense-based selection already applied. |
| **Licensing** | CC BY-SA for Wiktionary/kaikki; same as current pipeline. |

---

## 12. Recommendation and minimal ingestion plan (when you implement)

- **Recommendation:** **Proceed** with Croatian support. Data is sufficient and the pipeline is ready except for the `sh`→`hr` mapping.

**Minimal ingestion plan (outline only):**

1. **Language code handling**  
   In `scripts/ingestion/wiktionary.py`, ensure that when target language is **`hr`**, the code also collects translations whose lang code is **`sh`** (and optionally keep `hr` if you ever fix that one entry). Store all as `target_language = "hr"`. Concretely: e.g. add `"sh": "hr"` (and possibly `"hr": "hr"`) to `_LANG_ALIASES`, and when building `want` for streaming, if `"hr"` is in `target_langs`, add `"sh"` to the set of accepted lang codes and emit with normalized lang `"hr"`.

2. **Ingest**  
   Run existing ingest with `--target-lang de,es,hr` (and same CEFR and wiktionary path as today). No new scripts.

3. **Validation**  
   After ingest, check `SELECT target_language, COUNT(*) FROM vocab_entries GROUP BY target_language` and confirm EN→hr row count (~4,300) and spot-check a few topics/levels.

4. **Optional later**  
   Add Tatoeba or PanLex-based ingestion to fill missing CEFR headwords or add phrases; keep primary source as kaikki.

---

## 13. Source summary table

| Source | Type | EN→HR estimate | Size | Licensing | Suitability | Ingestion |
|--------|------|----------------|------|-----------|-------------|-----------|
| **kaikki EN JSONL (sh)** | Dictionary | ~4,300 CEFR / ~17.8k headwords | Same file as DE/ES | CC BY-SA | **Primary** | Low |
| Open Language Profiles | CEFR list (EN) | N/A (EN only) | ~6.9k headwords | As per OLP | Same as DE/ES | N/A |
| Tatoeba / ELRC | Sentence corpus | 1.3k–6k pairs | Small | CC-BY-2.0 | Supplement | Medium |
| OPUS OpenSubtitles | Parallel corpus | Available | Large | Attribution | Future | High |
| PanLex | Lexical DB | Good (hrv) | 1k+ per lang | CC0 | Gap-fill | Medium |
| MaCoCu hr-en | Parallel corpus | Large | 2.2M segments | CC0 | Future | Medium–High |
| Freedict | Dictionary | No EN–HR found | — | — | — | — |
| Glosbe | Dictionary | Yes, scale unclear | — | ToS | Possible | Medium |

---

*End of feasibility study. No code was modified.*
