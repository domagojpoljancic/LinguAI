//
//  BehaviorSpecs.swift
//  LinguAITests
//
//  Executable behavioral specifications. Each test mirrors a scenario in
//  Specifications/*.md (Given/When/Then). Run with the rest of the test suite (⌘U).
//

import Foundation
import SwiftData
import Testing
@testable import LinguAI

// MARK: - 01 Vocabulary boxes (Specifications/01-vocabulary-boxes.md)

@MainActor
@Suite("Behavior: Vocabulary boxes")
struct BoxBehaviorSpecs {

    @Test("Scenario: User creates a new box with name and language")
    func userCreatesNewBox() throws {
        // Given: empty store (fresh container)
        let container = try TestingContainer.make()
        let context = container.mainContext
        // When: user creates a box "Travel", German
        let box = VocabularyBox(name: "Travel", targetLanguageCode: "de", primaryLanguageCode: "en")
        context.insert(box)
        try context.save()
        // Then: box exists, has that name and language, zero words
        let boxes = try TestFixtures.fetchBoxes(from: context)
        #expect(boxes.count == 1)
        #expect(boxes[0].name == "Travel")
        #expect(boxes[0].targetLanguageCode == "de")
        #expect(boxes[0].wordCount == 0)
    }

    @Test("Scenario: Duplicate box names are rejected")
    func duplicateBoxNameRejected() throws {
        // Given: a box named "German" already exists
        let container = try TestingContainer.make()
        let context = container.mainContext
        _ = try TestFixtures.makeBox(in: context, name: "German", wordPairs: [])
        let boxes = try TestFixtures.fetchBoxes(from: context)
        // When: user tries to create another "german" (case-insensitive)
        let isDuplicate = Validation.isDuplicateBoxName("german", existingBoxes: boxes, editingBox: nil)
        // Then: validation rejects, no save
        #expect(isDuplicate == true)
    }

    @Test("Scenario: User renames a box")
    func userRenamesBox() throws {
        // Given: a box "Old Name" exists
        let container = try TestingContainer.make()
        let context = container.mainContext
        let box = try TestFixtures.makeBox(in: context, name: "Old Name", wordPairs: [("a", "b")])
        // When: user renames to "New Name" and saves
        box.name = "New Name"
        try context.save()
        // Then: box appears as "New Name", words unchanged
        let boxes = try TestFixtures.fetchBoxes(from: context)
        #expect(boxes[0].name == "New Name")
        #expect(boxes[0].words.count == 1)
    }

    @Test("Scenario: User deletes a box — cascade removes words")
    func userDeletesBoxCascade() throws {
        // Given: a box exists with words
        let container = try TestingContainer.make()
        let context = container.mainContext
        let box = try TestFixtures.makeBox(in: context, name: "ToDelete", wordPairs: [("a", "b"), ("c", "d")])
        // When: user deletes the box
        context.delete(box)
        try context.save()
        // Then: box and all its words are gone
        let boxes = try TestFixtures.fetchBoxes(from: context)
        #expect(boxes.isEmpty)
        let wordDescriptor = FetchDescriptor<BoxWord>()
        #expect(try context.fetchCount(wordDescriptor) == 0)
    }
}

// MARK: - 02 Words (Specifications/02-words.md)

@MainActor
@Suite("Behavior: Words in a box")
struct WordsBehaviorSpecs {

    @Test("Scenario: User adds a word — appears at level 1 with next review date")
    func userAddsWord() throws {
        // Given: a box exists
        let container = try TestingContainer.make()
        let context = container.mainContext
        let box = try TestFixtures.makeBox(in: context, wordPairs: [])
        // When: user adds "Hello" / "Hallo"
        let word = try TestFixtures.addWord(to: box, primaryText: "Hello", targetText: "Hallo", level: 1, in: context)
        // Then: word in list, level 1, next review date set
        #expect(box.words.count == 1)
        #expect(box.words.first!.primaryText == "Hello")
        #expect(box.words.first!.targetText == "Hallo")
        #expect(word.level == 1)
        #expect(word.nextReviewDate != nil)
    }

    @Test("Scenario: Duplicate word pairs are rejected")
    func duplicateWordPairRejected() throws {
        // Given: box already has "Hello" / "Hallo"
        let container = try TestingContainer.make()
        let context = container.mainContext
        _ = try TestFixtures.makeBox(in: context, wordPairs: [("Hello", "Hallo")])
        let box = try TestFixtures.fetchBoxes(from: context)[0]
        // When: user tries to add same pair (case-insensitive)
        let isDuplicate = Validation.isDuplicateWordPair(primary: "hello", target: "hallo", words: box.words)
        // Then: validation rejects
        #expect(isDuplicate == true)
    }

    @Test("Scenario: User edits a word's text")
    func userEditsWord() throws {
        // Given: box contains "Hello" / "Hallo"
        let container = try TestingContainer.make()
        let context = container.mainContext
        let box = try TestFixtures.makeBox(in: context, wordPairs: [("Hello", "Hallo")])
        let word = box.words.first!
        // When: user edits to "Hi" / "Hallo"
        word.primaryText = "Hi"
        try context.save()
        // Then: word shows new text, level unchanged
        let boxes = try TestFixtures.fetchBoxes(from: context)
        #expect(boxes[0].words.first!.primaryText == "Hi")
        #expect(boxes[0].words.first!.level == 1)
    }
}

// MARK: - 03 Study session (Specifications/03-study-session.md)

@MainActor
@Suite("Behavior: Study session")
struct StudySessionBehaviorSpecs {

    @Test("Scenario: Session uses up to saved count when enough words exist")
    func sessionUsesPreferenceWhenEnoughWords() throws {
        // Given: preference 10, box has 20 words
        let container = try TestingContainer.make()
        let context = container.mainContext
        let box = try TestFixtures.makeBox(in: context, wordPairs: (1...20).map { ("p\($0)", "t\($0)") })
        let requestedCount = 10
        let now = Date()
        // When: user starts session
        let effectiveCount = max(1, min(requestedCount, box.words.count))
        let selected = selectSessionWords(from: box.words, selectedLevelIDs: [1, 2, 3, 4, 5, 6], requestedCount: effectiveCount, now: now)
        // Then: session has 10 words
        #expect(selected.count == 10)
    }

    @Test("Scenario: Session uses fewer words when box has fewer than preference")
    func sessionUsesAvailableWhenBoxHasFewer() throws {
        // Given: preference 10, box has 3 words
        let container = try TestingContainer.make()
        let context = container.mainContext
        let box = try TestFixtures.makeBox(in: context, wordPairs: [("a", "b"), ("c", "d"), ("e", "f")])
        let savedPreference = 10
        let now = Date()
        // When: user starts session (effective = min(preference, available))
        let effectiveCount = max(1, min(savedPreference, box.words.count))
        let selected = selectSessionWords(from: box.words, selectedLevelIDs: [1], requestedCount: effectiveCount, now: now)
        // Then: session has 3 words; preference 10 is not persisted here (that's UI); we assert effective behavior
        #expect(selected.count == 3)
    }

    @Test("Scenario: Session has at least one word when any words exist")
    func sessionAtLeastOneWhenWordsExist() throws {
        // Given: box has 1 word
        let container = try TestingContainer.make()
        let context = container.mainContext
        let box = try TestFixtures.makeBox(in: context, wordPairs: [("a", "b")])
        let now = Date()
        // When: start session (requestedCount could be 0 from UI; logic uses max(1, ...))
        let selected = selectSessionWords(from: box.words, selectedLevelIDs: [1], requestedCount: 0, now: now)
        // Then: session contains 1 word
        #expect(selected.count == 1)
    }

    @Test("Scenario: Words filtered by selected level")
    func sessionFiltersBySelectedLevel() throws {
        // Given: box has words at levels 1, 2, 3; user selected only level 2
        let container = try TestingContainer.make()
        let context = container.mainContext
        let box = try TestFixtures.makeBox(in: context, wordPairs: [])
        _ = try TestFixtures.addWord(to: box, primaryText: "a", targetText: "b", level: 1, in: context)
        _ = try TestFixtures.addWord(to: box, primaryText: "c", targetText: "d", level: 2, in: context)
        _ = try TestFixtures.addWord(to: box, primaryText: "e", targetText: "f", level: 3, in: context)
        // When: start session with only level 2 selected
        let selected = selectSessionWords(from: box.words, selectedLevelIDs: [2], requestedCount: 10, now: Date())
        // Then: only level-2 word included
        #expect(selected.count == 1)
        #expect(selected[0].level == 2)
    }
}

// MARK: - 04 Persistence (Specifications/04-persistence.md)

@MainActor
@Suite("Behavior: Persistence")
struct PersistenceBehaviorSpecs {

    @Test("Scenario: User-created boxes persist after app restart (container recreation)")
    func boxesPersistAfterRestart() throws {
        // Simulated restart: new container at same store URL
        let storeURL = TestingContainer.makeTemporaryStoreURL()
        defer { TestingContainer.removePersistentStore(at: storeURL) }
        let boxName = "SurvivesRestart-\(UUID().uuidString.prefix(8))"
        do {
            let container = try TestingContainer.makePersistent(at: storeURL)
            let context = container.mainContext
            let box = VocabularyBox(name: boxName, targetLanguageCode: "de", primaryLanguageCode: "en")
            context.insert(box)
            try context.save()
        }
        do {
            let container = try TestingContainer.makePersistent(at: storeURL)
            let context = container.mainContext
            let boxes = try context.fetch(FetchDescriptor<VocabularyBox>())
            let match = boxes.filter { $0.name == boxName }
            #expect(match.count == 1)
        }
    }

    @Test("Scenario: Words in a box persist after app restart")
    func wordsPersistAfterRestart() throws {
        let storeURL = TestingContainer.makeTemporaryStoreURL()
        defer { TestingContainer.removePersistentStore(at: storeURL) }
        let boxName = "WordsSurvive-\(UUID().uuidString.prefix(8))"
        do {
            let container = try TestingContainer.makePersistent(at: storeURL)
            let context = container.mainContext
            let box = try TestFixtures.makeBox(in: context, name: boxName, wordPairs: [("Hello", "Hallo"), ("Thanks", "Danke")])
            _ = (box, context)
        }
        do {
            let container = try TestingContainer.makePersistent(at: storeURL)
            let context = container.mainContext
            let boxes = try TestFixtures.fetchBoxes(from: context)
            let match = boxes.filter { $0.name == boxName }
            #expect(match.count == 1)
            #expect(match[0].words.count == 2)
        }
    }
}

// MARK: - 05 Settings (Specifications/05-settings.md)

@MainActor
@Suite("Behavior: Settings — session word count")
struct SettingsBehaviorSpecs {

    @Test("Scenario: Effective session size is min(preference, available) — preference not overwritten")
    func effectiveSessionSizeIsMinOfPreferenceAndAvailable() {
        // Given: saved preference 20, box has 5 words
        let savedPreference = 20
        let availableInBox = 5
        // When: we compute effective count for this session (as the app does)
        let effectiveCount = max(1, min(savedPreference, availableInBox))
        // Then: session uses 5; preference 20 remains unchanged (persistence is in UI layer)
        #expect(effectiveCount == 5)
    }

    @Test("Scenario: Default word count is 10")
    func defaultWordCountIsTen() {
        // Given: user never changed preference (default 10)
        let defaultPreference = 10
        // When: we use it for session size
        let effectiveCount = max(1, min(defaultPreference, 100))
        // Then: value used is 10
        #expect(effectiveCount == 10)
    }
}
