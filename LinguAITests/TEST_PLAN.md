# LinguAI Test Plan

## Phase 1 — Analysis Summary

### Core app features (inferred from codebase)
- **Vocabulary boxes:** Create, rename, delete boxes; each has name, target + primary language.
- **Words:** Add, edit, delete words (primary + target text); level 1–6 (Leitner); SRS fields `lastReviewedDate`, `nextReviewDate`.
- **Study session:** Two-pass selection (due first, then future); Leitner level updates on correct/incorrect; Mastered (level 6) archived from rotation.
- **Settings:** Study direction (primary ↔ target), words per session, haptic feedback; version label.
- **Progress:** Per-box `progressValue` (0–1); global `totalMasteryProgress` (weighted).

### Existing coverage (before this pass)
- **BoxPersistenceTests (Swift Testing):** One test — box creation persists and can be fetched.
- **LinguAISRSTests (Swift Testing):** Correct answer Box 1 → nextReviewDate; incorrect Box 3 → level 1 + nextReviewDate now; two-pass fills 10 with 2 due + 8 future.
- **TestingContainer:** In-memory `ModelContainer` for VocabularyBox + BoxWord.

### Gaps identified
- All tests use Swift Testing (no XCTest in this target).
- Leitner level transitions and levelWeight not fully covered; SRS nextReviewDate for other levels.
- Session selection: level filter, empty list, requested count cap, nil nextReviewDate.
- No CRUD for words (add, update, delete); no cascade delete (box → words).
- No progressValue / totalMasteryProgress tests.
- No shared fixtures; duplicate setup across tests.
- No UI test target.

---

## Phase 2 — Implemented Coverage

### Test helpers
- **TestFixtures.swift** — `makeBox(in:name:targetLanguageCode:primaryLanguageCode:wordPairs:)`, `addWord(to:primaryText:targetText:level:nextReviewDate:in:)`, `fetchBoxes(from:)`, `wordCount(for:)`. All use in-memory context only.

### Unit tests (Swift Testing)
- **LeitnerEngineTests** (suite: "Leitner engine")
  - Correct answer: increments level 1→2, 2→3, 5→6; at max (6) stays 6.
  - Incorrect answer: resets to 1 from any level.
  - Boundaries: level 0/7 clamp to valid range.
  - levelWeight: 1=0, 2=0.2, …, 6=1.0; out of range = 0.
  - nextReviewDate: level 2 = tomorrow start of day; level 6 = +14 days; level 1 = same day.

- **SessionSelectionTests** (suite: "Session selection")
  - Only due words when enough due.
  - Requested count capped by available words.
  - Minimum one when words exist (requestedCount 0).
  - Filters by selectedLevelIDs (only level 2 selected).
  - nil nextReviewDate treated as due.
  - Empty filtered list returns empty.

### Persistent store regression (file-backed, simulates relaunch)
- **PersistentStoreRegressionTests** (suite: "Persistent store regression")
  - Box persists across container recreation: create container at temp URL → insert box → save → new container at same URL → fetch; assert box exists.
  - Word persists across container recreation: same pattern with box + word; assert word and relationship survive.
  - Uses `TestingContainer.makeTemporaryStoreURL()`, `makePersistent(at:)`, `removePersistentStore(at:)`; cleans up temp directory after each test.
  - These tests would fail if the app used in-memory-only storage, or if save() did not persist to disk, or if a second process/container could not see the data.

### Integration / persistence tests (Swift Testing, in-memory only)
- **BoxWordPersistenceTests** (suite: "Box and word persistence")
  - Create box and fetch; add words and persist; new word has nextReviewDate set.
  - Update box name persists; update word (text + level) persists.
  - Delete word removes from box; delete box cascades to words (no orphan words).
  - Empty box progressValue is zero.

- **ProgressTests** (suite: "Progress")
  - progressValue: all level 1 = 0; all level 6 = 1.0; mixed = expected average.
  - totalMasteryProgress: empty boxes = 0; single box all level 6 = 1.0; two boxes (one level 1, one level 6) = 0.5.

### Other Swift Testing suites
- **BoxPersistenceTests** (suite: "Box persistence") — box creation persists.
- **LinguAISRSTests** (suite: "SRS logic") — SRS correct/incorrect and two-pass selection.

---

## Core features now covered

| Feature | Unit | Integration / persistence |
|--------|------|----------------------------|
| Leitner level transitions | ✅ LeitnerEngineTests | — |
| SRS nextReviewDate intervals | ✅ LeitnerEngineTests | — |
| Two-pass session selection | ✅ SessionSelectionTests | — |
| Box CRUD | — | ✅ BoxWordPersistenceTests |
| Word CRUD + cascade delete | — | ✅ BoxWordPersistenceTests |
| New word nextReviewDate default | — | ✅ BoxWordPersistenceTests |
| progressValue / totalMasteryProgress | ✅ ProgressTests | — |

---

## Remaining gaps / hard-to-test areas

1. **UI flows** — No UI test target yet. Add-word validation (empty fields, duplicate pair), study session flow, settings changes would require a **LinguAIUITests** target and XCUITest (or Swift Testing UI). Recommended next: add UI test target and one smoke test (e.g. launch, tap Vocabulary box, see list or empty state).

2. **Translation** — Add-word sheet translation (triggerTranslation → runTranslation) depends on system Translation framework; not exercised in tests. Could add a mock or skip in unit tests.

3. **View-only logic** — Duplicate-name validation for boxes, duplicate word-pair validation, and error messages live in View methods; extracting to a small “validation” helper would allow unit tests without UI.

4. **Study direction default** — Default primary → target is applied in onAppear and in Settings binding; covered indirectly by SRS/session tests that don’t depend on direction. No dedicated test for the default tag.

---

## Next high-value tests (suggested)

1. **UI test target** — Create LinguAIUITests; one test: launch app → open Vocabulary box → assert list or empty state visible.
2. **Box name validation** — Extract `validateNewBoxName(_:existingBoxes:editingBox:)` (or similar) and test duplicate name and empty name.
3. **Word pair validation** — Extract “is duplicate word pair” and test against box.words.
4. **Study session** — One integration test: build session with selectSessionWords, then simulate recordAnswer (level + nextReviewDate) and assert state (optional, if you want to lock full SRS flow).

All tests use **in-memory SwiftData only** (TestingContainer + TestFixtures). No production database is touched.
