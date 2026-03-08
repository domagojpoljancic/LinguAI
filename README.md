# LinguAI

**Vocabulary that sticks — without the overwhelm.**

LinguAI is an iOS app that helps you learn and retain vocabulary using a proven **6-box Leitner system** and **silent spaced repetition**. You focus on studying; the app quietly prioritises what you need to review next.

---

## Why LinguAI

Most vocabulary tools either bombard you with “due” counts and timers or hide how repetition works. LinguAI takes a different approach:

- **Clear progression** — Words move through six boxes (1 → … → 6). Correct answers move a word up; wrong answers reset it to Box 1. You always see where each word stands.
- **Silent SRS** — Spaced repetition runs in the background. The app prefers words that are due for review but never locks you into a fixed schedule. Want to study more? You can.
- **No guilt, no clutter** — No due badges or countdowns. Just open a box, choose your session size, and study. The system does the rest.

Built as a side project by a product manager who wanted a simple, effective vocabulary tool — and who cares as much about the learning science as the experience.

---

## What you can do (v0.1)

- **Create vocabulary boxes** — One box per topic or language (e.g. Greetings, Travel). Name them, pick a target language (e.g. German, Italian, Croatian).
- **Add words** — Enter target-language word + translation. Words start in Box 1 and are available to study immediately.
- **Study with cards** — Swipe or tap to reveal the answer; mark correct or incorrect. Words move up a box (or back to 1) based on your answer.
- **Box progression view** — See six boxes (1–5 numbered, 6 = **Mastered**) with word counts and progress. Choose which boxes to include in each session.
- **Settings** — Study direction (which language → which), words per session (capped by your selection), haptic feedback. Version label at the bottom for tracking.

*More features (e.g. AI-suggested lists) are planned; the core loop is solid and ready for daily use.*

---

## How it works

### 6-box Leitner system

| Your answer | What happens        |
|------------|---------------------|
| **Correct** | Word moves up one box (1→2→…→6). |
| **Incorrect** | Word goes back to Box 1. |

**Box 6 = Mastered** — Words here are treated as learned and are left out of the default “due” rotation. You can still include the Mastered box when you start a session if you want to review them.

Progress is shown as 0–100%: Box 1 = 0%, Box 2 = 20%, … Box 6 = 100%.

### Silent spaced repetition (SRS)

SRS runs behind the scenes. No due dates or timers in the UI.

- **When you get it right** — The app schedules the next review from *start of today* (your local timezone) plus an interval by box: Box 2 → +1 day, 3 → +2 days, 4 → +4 days, 5 → +7 days. Mastered words are not scheduled again.
- **When you get it wrong** — The word returns to Box 1 and is eligible again right away.

**Session building (two-pass):**

1. **Pass 1** — Fill the session with words that are “due” (next review today or in the past), oldest first.
2. **Pass 2** — If there aren’t enough due words, fill the rest with “future” words (soonest next review first, then shuffled for variety).

So due items are prioritised, but you’re never blocked from studying more — you choose session size and which boxes to include.

---

## Tech and quality

- **Stack:** SwiftUI, SwiftData (iOS).
- **Testing:** Unit tests for SRS intervals, Leitner level reset, and two-pass session selection (`LinguAITests`).
- **Version:** v0.1 (Build 1) — internal release.

---

## Getting started

1. Clone the repo and open `LinguAI.xcodeproj` in Xcode.
2. Build and run on a simulator or device (iOS 26+).
3. Create a box, add words, and start studying.

---

## Status and roadmap

- **v0.1** — Basic vocabulary box functionality: create boxes, add words, study with Leitner + silent SRS, Mastered box, settings, tests, and docs.
- **Next** — “AI Suggest” for generated vocabulary lists; further UX polish and optional onboarding.

---

*LinguAI — built with product sense and learning science in mind.*
