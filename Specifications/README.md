# LinguAI Behavioral Specifications

This folder contains **human-readable specifications** of how the app behaves. Each scenario is written in **Given / When / Then** format so that product, QA, and engineering share a single understanding.

## Purpose

- **Document** key behavior for non-engineers
- **Align** expectations across the team
- **Complement** the test suite: the scenarios listed here are implemented as executable tests in `LinguAITests` (see `BehaviorSpecs.swift`)

## Format

Each specification file (`.md`) describes one area of the app. Scenarios look like this:

```gherkin
### Scenario: [Short title]

**Given** [initial context / preconditions]  
**When** [the user or system does something]  
**Then** [observable outcome]
```

Optional: **And** can extend any clause.

## Files

| File | Area |
|------|------|
| [01-vocabulary-boxes.md](01-vocabulary-boxes.md) | Creating, renaming, and deleting boxes |
| [02-words.md](02-words.md) | Adding and editing words in a box |
| [03-study-session.md](03-study-session.md) | Starting a session, word count, selection |
| [04-persistence.md](04-persistence.md) | Data surviving app restart |
| [05-settings.md](05-settings.md) | Session word count and study direction |

## How to add a new scenario

1. **Choose the right file** (or create a new one, e.g. `06-new-feature.md`).
2. **Add a scenario** in Given/When/Then form. Use clear, concrete steps.
3. **Implement it** in `LinguAITests/BehaviorSpecs.swift`: add a `@Test("Scenario: ...")` that mirrors the scenario (Given = setup, When = action, Then = assertions).
4. **Run the test** (⌘U or Test navigator) to keep the spec executable.

## Relationship to other tests

- **Unit tests** (e.g. `LeitnerEngineTests`, `ValidationTests`) test isolated logic with minimal setup.
- **Behavior specs** test **end-to-end flows** and **user-visible outcomes**; they use the same in-memory container and fixtures but assert on full scenarios.
- **Regression tests** (e.g. `PersistentStoreRegressionTests`) guard against specific bugs (e.g. persistence across container recreation).

All live in the same `LinguAITests` target and run together.
