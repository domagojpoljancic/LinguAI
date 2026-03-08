# LinguAI

Vocabulary learning app with a **6-box Leitner system** and **Silent SRS** (Spaced Repetition) for iOS.

## 6-Box Leitner System

Words move through six levels (boxes) based on your answers:

- **Correct** → move up one level (Box 1 → 2 → … → 6).
- **Incorrect** → reset to Box 1.

**Box 6** is **Mastered**: words here are treated as fully learned. They stay in Box 6 and are excluded from the default study rotation unless you explicitly include “Mastered” when starting a session.

Progress is shown as a 0–100% value: Box 1 = 0%, Box 2 = 20%, … Box 6 (Mastered) = 100%.

## Silent SRS (Spaced Repetition)

SRS runs in the background. There are no “due” badges or timers in the UI.

- **Scheduling**
  - When you answer **correctly**, the next review date is set from **start of today** (local calendar) plus an interval that depends on the **new** level:
    - Box 2: +1 day  
    - Box 3: +2 days  
    - Box 4: +4 days  
    - Box 5: +7 days  
    - Box 6 (Mastered): no future review (archived).
  - When you answer **incorrectly**, the word goes back to Box 1 and `nextReviewDate` is set to **now** so it can appear again soon.

- **Session selection (two-pass)**
  - **Pass 1:** Up to the requested session size, the app picks words whose `nextReviewDate` is today or in the past (“due”), ordered by oldest due first.
  - **Pass 2:** If there aren’t enough due words, the rest of the session is filled with “future” words (next review in the future), sorted by earliest next, then shuffled for variety.

So due words are prioritised, but you can still study more (including future or Mastered words) by choosing which boxes to include and the session size.

## Tech

- **SwiftUI** + **SwiftData** for persistence.
- **Leitner** logic and SRS intervals in the main app target; session selection is unit-tested (see `LinguAITests`).

## Version

**v0.1** — Internal release.
