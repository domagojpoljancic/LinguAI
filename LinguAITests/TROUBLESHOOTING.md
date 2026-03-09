# LinguAI Tests – Troubleshooting

## 1. Simulator: "Application failed preflight checks" / Busy (Code 1)

This usually means the simulator or launch environment is in a bad state. Try in order:

1. **Quit Simulator** (Simulator → Quit) and **quit Xcode**. Reopen Xcode, then run again.
2. **Delete the app from the simulator**: Boot the simulator, long-press the LinguAI icon → Remove App. Then run from Xcode again.
3. **Clean and rebuild**: Xcode → Product → Clean Build Folder (⇧⌘K), then Product → Build (⌘B). Run (⌘R).
4. **Reset the simulator**: In Simulator menu, Device → Erase All Content and Settings. Then run again.
5. **Use a different simulator**: Product → Destination → choose another iPhone (e.g. iPhone 15 if you used iPhone 16).
6. **Restart Mac** if the above don’t help (clears CoreSimulatorService and other system state).

---

## 2. Question marks on test files and tests not in Test navigator

If **TestFixtures**, **LeitnerEngineTests**, **SessionSelectionTests**, **BoxWordPersistenceTests**, or **ProgressTests** show a **?** in the Project navigator, or if only "Box persistence" and "SRS logic" (5 tests) appear in the Test navigator:

### A. Fix file references (question marks)

1. In the **Project navigator**, select each file that has a **?**.
2. In the **File inspector** (right panel), check **Location**. It should be **Relative to Group** and the path should match the file on disk (e.g. `TestFixtures.swift` inside the LinguAITests group).
3. If the path is wrong: select the file → File inspector → **Location** → **Relative to Group** → set path to the filename only (e.g. `TestFixtures.swift`), or use the folder icon to re-select the file on disk.
4. If the file is **missing** (red name): right‑click the LinguAITests group → **Add Files to "LinguAI"…** → select the missing `.swift` file(s) in `LinguAITests/` → ensure **Add to targets: LinguAITests** is checked → Add.

### B. Ensure new tests are in the target and discovered

1. Select the **LinguAI** project (blue icon) in the Project navigator.
2. Select the **LinguAITests** target → **Build Phases** → **Compile Sources**.
3. Confirm these are listed: `TestingContainer.swift`, `TestFixtures.swift`, `BoxPersistenceTests.swift`, `LinguAISRSTests.swift`, `LeitnerEngineTests.swift`, `SessionSelectionTests.swift`, `BoxWordPersistenceTests.swift`, `ProgressTests.swift`. If any are missing, click **+** and add them.
4. **Clean Build Folder** (⇧⌘K), then **Product → Build For → Testing** (⌘U to run tests).
5. Open the **Test navigator** (⌘6). You should see all Swift Testing suites: Box persistence, SRS logic, Leitner engine, Session selection, Box and word persistence, Progress — with their test methods. Helper files (TestingContainer, TestFixtures) have no test annotations and do not appear as tests.

### C. If tests still don’t appear

1. Close Xcode.
2. Delete DerivedData for this project:
   - **Xcode → Settings → Locations** → click the arrow next to **Derived Data** path, then delete the folder **LinguAI-…** (or delete the whole DerivedData folder).
   - Or in Terminal: `rm -rf ~/Library/Developer/Xcode/DerivedData/LinguAI-*`
3. Reopen the project in Xcode, build (⌘B), then run tests (⌘U).

---

## 3. Running only tests (without launching the app)

To run tests without launching the app in the simulator:

- **Product → Test** (⌘U), or  
- Click the **diamond** next to a test class/method in the Test navigator.

If the scheme is set to **Run** and you press ⌘R, Xcode will try to launch the app; use ⌘U to run tests only and avoid the simulator launch error while you fix it.
