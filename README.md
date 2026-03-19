# LinguAI
Vocabulary that sticks — built for silent practice, not loud reminders.

LinguAI is a SwiftUI vocabulary app built on a **6-box Leitner system** with **silent spaced repetition**. You open the app, choose how many cards you want, and study. The app prioritizes reviews in the background—without due counts, timers, or guilt.

This repo contains:
- **iOS app** (`LinguAI/`, `LinguAITests/`, `Specifications/`)
- **Agentic backend** (FastAPI + LangGraph) powering AI-assisted vocabulary box generation: `main.py` + `app/`

## Why LinguAI is different
- **Progress is visible, schedules are not.** You see each word’s box (1 → … → 6 / Mastered), but you never manage due dates.
- **Silent SRS, two-pass sessions.** When you start a study session, the app fills it with words that are due (oldest first), then backfills with “soonest next” items for variety.
- **AI helps you create boxes—your learning loop stays clean.** “AI Suggest” is designed to generate a new vocabulary box that respects your existing progress (box completion + known words) and avoids duplicate suggestions.

## Key features
- **Vocabulary boxes (topic-first)**: create boxes, add word pairs, edit/delete, and track progress.
- **Leitner progression (6 boxes + Mastered)**:
  - Correct answers move a word up one box.
  - Incorrect answers reset the word to Box 1.
  - Box 6 (“Mastered”) is treated as learned by default.
- **Silent spaced repetition (SRS)**:
  - Correct schedules the next review using box-based day intervals.
  - Wrong returns the word to Box 1 and makes it eligible again right away.
- **Session builder that doesn’t block you**:
  - Pass 1: due words (next review today/past).
  - Pass 2: future words (soonest first, shuffled for variety).
- **AI Suggest (optional)**: generate a new vocabulary box from a prompt and your current box progress.
- **Premium UX details**: haptics (toggleable), careful sheet flows, and translation-assisted word entry.

## How the iOS learning loop works
### 6-box Leitner
Correct and incorrect answers move words between boxes:
- Correct: **1 → 2 → … → 6**
- Incorrect: **→ 1**

Progress is shown as a weighted value (Box 1 = 0%, …, Box 6 = 100%).

### Silent spaced repetition
SRS runs “behind the scenes”:
- Correct schedules the next review from local “start of today” using box-based intervals.
- Incorrect returns the word to Box 1 and makes it eligible immediately.

### Two-pass session building
When you start a session, LinguAI:
1. Picks due words first (oldest `nextReviewDate`).
2. If needed, fills remaining slots with future words (soonest next review first), then shuffles the backfill.

## How the agentic backend works
The backend exposes a single product-critical endpoint:
- `POST /generate-boxes`

### What the backend generates
Given:
- a user prompt (topic/intent),
- a target language,
- your existing boxes (completion percent + known word pairs),

the workflow produces a **new vocabulary box candidate** (or a structured “can’t do / try again” outcome that the app can display).

### LangGraph workflow (intent → level → retrieval → optional generation)
The graph lives in `app/graph.py` and is assembled from node functions in `app/box_workflow.py`. Conceptually:
- **Request understanding + relevance check** (LLM-gated)
- **Topic identification** (deterministic keywords with an AI fallback when needed)
- **Learner level resolution** (explicit CEFR in prompt, otherwise inferred from progress)
- **Retrieval attempt from local vocabulary store** (SQLite)
- **Retrieval quality assessment**
- If the DB isn’t strong enough: **OpenAI Responses API** generates candidate word pairs using a strict JSON schema
- **Merge + dedupe + finalize** the response
- **Persist AI fallback pairs asynchronously** (non-blocking `BackgroundTasks`)

### Idempotency that supports retries (important for mobile)
`POST /generate-boxes` implements idempotency keyed by `(customerId, requestId)` with a payload hash:
- Same keys + same payload replay the cached result
- Same keys + different payload returns **HTTP 409 Conflict**
- Only successful generations are stored (safe to retry after transient failures)

The in-repo iOS “AI Suggest” flow reuses `requestId` for exact retries by computing a deterministic payload signature.

### Observability and debug
When `DEBUG=true`:
- The server enables debug graph endpoints:
  - `GET /debug/graph/ascii`
  - `GET /debug/graph/render`
- It can log the full request payload (use locally; prompts can contain user text).

Outside debug mode:
- Logs are privacy-conscious and focus on request metadata and workflow outcomes.

## Repository map
- `LinguAI/`: SwiftUI views, SwiftData models, Leitner + SRS logic, and the UI flows
- `LinguAITests/`: Swift Testing unit/integration tests (in-memory SwiftData + persistence regressions)
- `Specifications/`: human-readable Given/When/Then behavioral specs
- `app/`: backend workflow nodes, prompts, schemas, retrieval, idempotency, and observability
- `main.py`: FastAPI entrypoint and `/generate-boxes`
- `data/`: local vocabulary DB + idempotency DB (generated at runtime)
- `docs/`: longer-form architecture/prompt/agent notes
- `scripts/`: ingestion utilities (for future dataset expansion)

## Setup and run
### Backend (FastAPI + LangGraph)
1. Create a virtual environment:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   ```
2. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```
3. Configure environment:
   ```bash
   cp .env.example .env
   # set OPENAI_API_KEY
   ```
4. Run the server:
   ```bash
   uvicorn main:app --reload --host 0.0.0.0 --port 2024
   ```

Health check:
- `GET /` → `{"status":"ok", ...}`

Example request:
```bash
curl -s -X POST http://localhost:2024/generate-boxes \
  -H "Content-Type: application/json" \
  -d '{
    "requestId": "req-001",
    "customerId": "cust-1",
    "prompt": "A1 restaurant words in German",
    "defaultLanguage": "en",
    "targetLanguage": "de",
    "existingBoxes": []
  }'
```

### iOS app
1. Open `LinguAI.xcodeproj` in Xcode.
2. Run on a simulator (defaults to `http://localhost:2024`) or a device.
3. For a physical device, set `LINGUAI_API_BASE_URL` in the app’s target Info to your Mac’s reachable IP, e.g.:
   - `http://192.168.1.5:2024`

## Testing / quality signals
### iOS
- Uses **Swift Testing** (`LinguAITests`) with in-memory SwiftData.
- Includes unit and integration coverage for:
  - Leitner progression
  - SRS interval scheduling
  - two-pass session selection
  - CRUD + cascade delete
  - validation
  - persistence regression checks
- Behavioral specs are captured as Given/When/Then in `Specifications/` and implemented in `LinguAITests/BehaviorSpecs.swift`.

### Backend
- `pytest` covers core correctness for idempotency (`tests/test_idempotency.py`).
- Debug graph endpoints provide a quick sanity check while iterating on the workflow (`/debug/graph/*` when `DEBUG=true`).

## Roadmap (next durable steps)
- Expand curated vocabulary coverage and ingestion pipeline (`scripts/`).
- Add more topic support with deterministic-first logic and AI fallbacks where needed.
- Improve iOS onboarding and session personalization without reintroducing due-date anxiety.

# LinguAI

**Vocabulary that sticks — without the overwhelm.**

LinguAI is an iOS app that helps you learn and retain vocabulary using a proven **6-box Leitner system** and **silent spaced repetition**. You focus on studying; the app quietly prioritises what you need to review next.

This repo contains:

- **iOS app** — at the repo root: `LinguAI.xcodeproj`, `LinguAI/`, `LinguAITests/`, `Specifications/`
- **Backend** — in [`linguai-langgraph/`](linguai-langgraph/): FastAPI + LangGraph for chat and vocabulary box generation (see [linguai-langgraph/README.md](linguai-langgraph/README.md) for setup and API)

---

## Why LinguAI

Most vocabulary tools either bombard you with "due" counts and timers or hide how repetition works. LinguAI takes a different approach:

- **Clear progression** — Words move through six boxes (1 → … → 6). Correct answers move a word up; wrong answers reset it to Box 1. You always see where each word stands.
- **Silent SRS** — Spaced repetition runs in the background. The app prefers words that are due for review but never locks you into a fixed schedule. Want to study more? You can.
- **No guilt, no clutter** — No due badges or countdowns. Just open a box, choose your session size, and study. The system does the rest.

Built as a side project by a product manager who wanted a simple, effective vocabulary tool — and who cares as much about the learning science as the experience.

---

## What you can do (v0.1)

- **Create vocabulary boxes** — One box per topic or language (e.g. Greetings, Travel). Name them, pick a target language (e.g. German, Italian, Croatian).
- **Add words** — Enter target-language word + translation. Optional: type in one field and use **Translate to [language]** to fill the other (on-device translation, 5s timeout; clear error messages if unavailable). Words start in Box 1 and are available to study immediately.
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

**Box 6 = Mastered** — Words here are treated as learned and are left out of the default "due" rotation. You can still include the Mastered box when you start a session if you want to review them.

Progress is shown as 0–100%: Box 1 = 0%, Box 2 = 20%, … Box 6 = 100%.

### Silent spaced repetition (SRS)

SRS runs behind the scenes. No due dates or timers in the UI.

- **When you get it right** — The app schedules the next review from *start of today* (your local timezone) plus an interval by box: Box 2 → +1 day, 3 → +2 days, 4 → +4 days, 5 → +7 days. Mastered words are not scheduled again.
- **When you get it wrong** — The word returns to Box 1 and is eligible again right away.

**Session building (two-pass):**

1. **Pass 1** — Fill the session with words that are "due" (next review today or in the past), oldest first.
2. **Pass 2** — If there aren't enough due words, fill the rest with "future" words (soonest next review first, then shuffled for variety).

So due items are prioritised, but you're never blocked from studying more — you choose session size and which boxes to include.

---

## Tech and quality (iOS)

- **Stack:** SwiftUI, SwiftData, Translation framework (iOS).
- **Testing:** All unit and integration tests use **Swift Testing** (`LinguAITests`). Coverage includes Leitner engine, SRS intervals, two-pass session selection, box/word CRUD and cascade delete, progress values, validation (duplicate box name / word pair), data seeding, and record-answer flow. Helpers: `TestingContainer` (in-memory SwiftData), `TestFixtures`. See `LinguAITests/TEST_PLAN.md` and `LinguAITests/TROUBLESHOOTING.md` for details. **Behavioral specs:** human-readable Given/When/Then scenarios live in `Specifications/`; executable tests implementing them are in `LinguAITests/BehaviorSpecs.swift`.
- **Version:** v0.1 (Build 1) — internal release.

### High-level architecture

- **Models:** `VocabularyBox`, `BoxWord` (SwiftData); Leitner and SRS logic in `VocabularyModels.swift`. Pure validation in `Validation.swift`.
- **UI:** `ContentView` → category grid; `VocabularyBoxesView` → box list and detail; study flow and Add/Edit word sheets in the same file. Settings and study direction stored in `UserDefaults` / `@AppStorage`.
- **Data:** One-time seed via `DataSeeding` (e.g. "Grundlagen" for empty DB); in-memory container only in tests.

---

## Getting started

### iOS app

1. Clone the repo and open **`LinguAI.xcodeproj`** in Xcode (at the repo root).
2. Build and run on a simulator or device (iOS 26+).
3. Create a box, add words, and start studying.

**Running tests:** In Xcode **Product → Test** (⌘U), or use the Test navigator (⌘6). All tests use in-memory persistence; no production database is touched.

### Backend

The LangGraph backend (FastAPI, chat, `/generate-boxes`) lives in **`linguai-langgraph/`**. For setup, running the server, vocabulary DB, and API details, see **[linguai-langgraph/README.md](linguai-langgraph/README.md)**.

---

## Status and roadmap

- **v0.1** — Basic vocabulary box functionality: create boxes, add words, study with Leitner + silent SRS, Mastered box, settings, tests, and docs.
- **Next** — "AI Suggest" for generated vocabulary lists; further UX polish and optional onboarding.

---

*LinguAI — built with product sense and learning science in mind.*
