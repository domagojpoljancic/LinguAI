# Persistence Bug Fix — Summary

## 1. Root cause of the persistence bug

**The app was wiping all user data on every launch in DEBUG.**

In `LinguAIApp.swift` a flag was set to `true` and never reverted:

```swift
private let _reseedDatabaseForTesting = true
```

In `init()`:

```swift
#if DEBUG
if _reseedDatabaseForTesting {
    DataSeeding.resetAndReseed(container: sharedModelContainer)  // ran every launch
} else {
    DataSeeding.runIfNeeded(container: sharedModelContainer)
}
#endif
```

`DataSeeding.resetAndReseed`:

1. Fetches all `VocabularyBox` instances
2. Deletes every box (cascade deletes all words)
3. Saves the context
4. Seeds only the "Grundlagen" box
5. Clears `UserDefaults` study direction

So on each app restart (when built from Xcode with DEBUG), user-created boxes and words were deleted and replaced by the single seeded box. The persistence path itself was correct: the app uses `ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)` and calls `modelContext.save()` when creating/editing boxes and words. The bug was **launch-time behavior**, not save/load.

---

## 2. What code was fixed

- **LinguAIApp.swift**
  - Removed `_reseedDatabaseForTesting` and the conditional that called `resetAndReseed` on every DEBUG launch.
  - App now always calls `DataSeeding.runIfNeeded(container:)`, which seeds only when the database is empty (no boxes, no words).
  - Added DEBUG-only `DebugAppContainer.container` (weak ref) so Settings can access the app’s `ModelContainer` for the "Reset and Seed Demo Data" action.

- **DataSeeding.swift**
  - Added `resetAndReseedIfPossible(container:) -> Bool` for UI feedback; used by the DEBUG Settings button.

- **VocabularyBoxesView.swift**
  - Added DEBUG-only "Developer" section in `SettingsView` with a "Reset and Seed Demo Data" button that calls `DataSeeding.resetAndReseedIfPossible(container:)` and shows an alert with "Done…" or "Failed".

- **TestingContainer.swift**
  - Added `makeTemporaryStoreURL()`, `makePersistent(at:)`, and `removePersistentStore(at:)` for file-backed tests that simulate app relaunch.

- **PersistentStoreRegressionTests.swift** (new)
  - Two Swift Testing tests: box persists across container recreation, word (and box) persist across container recreation; both use a temp persistent store URL and clean up in `defer`.

- **LinguAI.xcodeproj**
  - Added `PersistentStoreRegressionTests.swift` to the LinguAITests target.

- **TEST_PLAN.md**
  - Documented the new persistent store regression suite and helpers.

---

## 3. Why the previous tests missed it

- All existing tests use **in-memory** `TestingContainer.make()`. They never use a file-backed store or simulate a second “launch” (new container at the same URL).
- They assert insert + save + fetch **in the same context/container**, so they only verify that save is called and the same context sees the data. They do not verify that data survives after the container is discarded and a new one is opened at the same store URL.
- No test runs the app’s `init()` or `DataSeeding.resetAndReseed`. So a bug that runs reset on every launch could not be caught by the existing suite.
- In short: the tests validated **logical** persistence (insert/save/fetch in one process) and **in-memory** behavior, not **durable** persistence across container recreation or launch-time logic.

---

## 4. Which new tests were added

- **PersistentStoreRegressionTests** (Swift Testing, suite "Persistent store regression"):
  - **Box persists across container recreation:** Create container at temp URL → insert one box → save → create a **new** container at the **same** URL → fetch all boxes → assert exactly one box with the expected name and language codes.
  - **Word persists across container recreation:** Same pattern: first container inserts a box and a word, save; second container at same URL fetches boxes and asserts one box with one word and correct primary/target text.

Both tests use `TestingContainer.makeTemporaryStoreURL()`, `makePersistent(at:)`, and `removePersistentStore(at:)` and run in isolation with cleanup.

---

## 5. Why the new test would have caught the old bug

**Clarification:** The new test does **not** run the app or `resetAndReseed`, so it would **not** have failed specifically when “reset on every launch” was enabled. It would still **pass** with that bug, because it uses its own temporary file-backed store and never calls app init.

The new test **does** protect against other persistence regressions:

- If the **app** were ever switched to `isStoredInMemoryOnly: true` by mistake, user data would disappear after restart; the **test** would still pass (it uses an explicit file URL). So the test does not directly detect that app configuration.
- If **save()** were broken or not actually writing to the store, the second container in the test would see no data and the test would **fail**.
- If the test helper were changed to use an in-memory store, the second container would see no data and the test would **fail**.

So: the **exact** “reset on every launch” bug is fixed by removing the reseed flag and is not covered by this test. The new test gives **evidence that file-backed persistence works** (write → new container → read), so any future change that breaks durable persistence (e.g. wrong store URL, or save not flushing to disk) is more likely to be caught.

---

## 6. DEBUG / demo seeding option implemented

- **Where:** Settings (sheet opened from the Study / box progression screen). Only visible in **DEBUG** builds (`#if DEBUG`).
- **Section:** "Developer" with one button: **"Reset and Seed Demo Data"**.
- **Behavior:** Taps call `DataSeeding.resetAndReseedIfPossible(container: DebugAppContainer.container!)`. That deletes all boxes and words, seeds the "Grundlagen" box, and clears the study direction default. An alert shows either "Done. Grundlagen seeded. Restart or navigate back to see changes." or "Failed" / "Not available".
- **Safety:** The section and `DebugAppContainer` are compiled only in DEBUG; release builds have no reference to them and no such button.
- **Convenience:** You can trigger it repeatedly during development; each run wipes and reseeds. No launch argument was added; the visible button was preferred.

---

## 7. Quick manual verification steps (on device)

1. **Persistence**
   - Create a new box, add a few words.
   - Force-quit the app (or stop from Xcode) and relaunch.
   - Confirm the box and words are still there.

2. **Seed-only when empty**
   - With no boxes (e.g. after uninstall/reinstall or after "Reset and Seed Demo Data"), launch once: only "Grundlagen" should appear.
   - Create a new box, quit, relaunch: your box and "Grundlagen" should both be present (no second seed, no wipe).

3. **DEBUG demo seed**
   - In DEBUG build, open Settings and tap "Reset and Seed Demo Data". Dismiss the alert, then go back: only "Grundlagen" should remain. Run again as needed for a clean demo state.

4. **Tests**
   - Run the full test suite (⌘U), including "Persistent store regression". Both new tests should pass.
