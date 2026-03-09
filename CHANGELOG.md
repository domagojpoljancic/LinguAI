# Changelog

All notable changes to LinguAI are documented here.

## [Unreleased]

### Added
- **Swift Testing everywhere:** All LinguAITests use Swift Testing (`@Suite`, `@Test`, `#expect`). Suites: Box persistence, SRS logic, Leitner engine, Session selection, Box and word persistence, Progress, Validation, Data seeding. Helpers: `TestFixtures`, `TestingContainer` (no test attributes).
- **Validation tests:** Duplicate box name (case-insensitive, editing box excluded) and duplicate word-pair validation; logic extracted to `Validation.swift` for testability.
- **Record-answer integration tests:** Correct answer updates level and nextReviewDate; wrong answer resets to level 1 and sets nextReviewDate to now; correct at max level sets distantFuture.
- **DataSeedingTests:** Reset-and-reseed creates single "Grundlagen" box with expected word count (in-memory).
- **Add Word translation UX:** Single contextual "Translate to [language]" action when exactly one field has text; hint "Type in either field to translate into the other"; bidirectional translation (either field as source). Timeout 5s with user-facing messages ("Translation is unavailable right now." / "Couldn't translate this word."); loading state reset on success, timeout, and error.

### Changed
- **Add Word sheet:** Removed per-field translate buttons; plain text fields with one translate action row; translation errors clear when user types.
- **Debug:** Removed debug print from VocabularyBoxesView onAppear.

### Technical
- **LinguAITests:** No XCTest; Swift Testing only. New files: LeitnerEngineTests, SessionSelectionTests, BoxWordPersistenceTests, ProgressTests, ValidationTests, DataSeedingTests, TestFixtures; Validation.swift in app target. TEST_PLAN.md and TROUBLESHOOTING.md added.

## [v0.1] - Basic Vocabulary box functionality

### Added
- **Silent Spaced Repetition (SRS):** Word-level `lastReviewedDate` and `nextReviewDate` with timezone-safe, calendar-based intervals (Box 2: +1 day, 3: +2, 4: +4, 5: +7, Mastered: archived).
- **Two-pass session selection:** Sessions prioritize due words (oldest first), then fill with future words (shuffled) when needed.
- **Box 6 "Mastered":** Level 6 renamed to Mastered with trophy icon; mastered words excluded from default study rotation.
- **Add with AI / AI Suggest:** Segmented floating button (sparkles) with "Coming Soon" alert; vertical divider between Add and AI Suggest.
- **Empty box state:** Detail view shows a centered empty state (icon + copy) when a box has no words.
- **Croatian (Hrvatski):** Added to language options and flag mapping.
- **Settings:** Study direction preselection fix (normalized binding); version label "v0.1" at bottom of Settings.
- **Unit tests:** SRS tests for correct-answer nextReviewDate, incorrect-answer level reset, and two-pass session fetch; testable `selectSessionWords` and in-memory testing container.
- **Docs:** README (Leitner + Silent SRS), .gitignore (Build, UserInterfaceState, etc.).

### Changed
- **Floating action bar:** Compact pill layout; intrinsic width, centered; padding 20/10; consistent across Vocabulary Boxes, Box Detail, and Study.
- **Progression cards:** Mastered card aligned with numbered cards (fixed badge+count block height, same circle size, trophy 28pt).
- **Study direction:** Picker uses normalized binding so a segment is always selected when opening Settings from Box Progression.
- **SplitPillFloatingBar:** Trailing closure labeled with `content:` to fix deprecation warning.

### Fixed
- ViewBuilder "Instance member 'frame' cannot be used on type 'View'" in box detail empty state (wrapped conditional in `Group`).
- Study direction not preselected in Box Progression settings (binding always exposes a valid tag).

### Technical
- **Version:** Marketing 0.1, Build 1.
- **SwiftData:** BoxWord gains `lastReviewedDate`, `nextReviewDate`; new words get `nextReviewDate = Date.now`.
- **Leitner:** Correct → +1 level (cap 6); incorrect → level 1; Mastered (6) gets `nextReviewDate = .distantFuture`.

[v0.1]: https://github.com/your-org/LinguAI/releases/tag/v0.1
