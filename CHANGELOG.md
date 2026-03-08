# Changelog

All notable changes to LinguAI are documented here.

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
