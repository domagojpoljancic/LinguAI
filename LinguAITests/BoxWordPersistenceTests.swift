//
//  BoxWordPersistenceTests.swift
//  LinguAITests
//
//  Integration tests: CRUD for boxes and words, cascade delete, in-memory only.
//

import SwiftData
import Testing
@testable import LinguAI

@MainActor
@Suite("Box and word persistence")
struct BoxWordPersistenceTests {

    @Test("Create box and fetch")
    func createBoxAndFetch() throws {
        let container = try TestingContainer.make()
        let context = container.mainContext

        _ = try TestFixtures.makeBox(in: context, name: "German", targetLanguageCode: "de", primaryLanguageCode: "en")

        let fetched = try TestFixtures.fetchBoxes(from: context)
        #expect(fetched.count == 1)
        #expect(fetched[0].name == "German")
        #expect(fetched[0].targetLanguageCode == "de")
        #expect(fetched[0].primaryLanguageCode == "en")
        #expect(fetched[0].wordCount == 0)
    }

    @Test("Add words to box and persist")
    func addWordsToBoxAndPersist() throws {
        let container = try TestingContainer.make()
        let context = container.mainContext
        _ = try TestFixtures.makeBox(in: context, wordPairs: [("Hello", "Hallo"), ("Thanks", "Danke")])

        let fetched = try TestFixtures.fetchBoxes(from: context)
        #expect(fetched.count == 1)
        #expect(fetched[0].words.count == 2)
        let texts = fetched[0].words.map { ($0.primaryText, $0.targetText) }.sorted(by: { $0.0 < $1.0 })
        #expect(texts[0].0 == "Hello")
        #expect(texts[0].1 == "Hallo")
        #expect(texts[1].0 == "Thanks")
        #expect(texts[1].1 == "Danke")
    }

    @Test("New word has nextReviewDate set")
    func newWordHasNextReviewDateSet() throws {
        let container = try TestingContainer.make()
        let context = container.mainContext
        let box = try TestFixtures.makeBox(in: context, wordPairs: [("a", "b")])

        let word = box.words.first!
        #expect(word.nextReviewDate != nil)
        #expect(word.level == 1)
    }

    @Test("Update box name persists")
    func updateBoxNamePersists() throws {
        let container = try TestingContainer.make()
        let context = container.mainContext
        let box = try TestFixtures.makeBox(in: context, name: "Original")

        box.name = "Renamed"
        try context.save()

        let fetched = try TestFixtures.fetchBoxes(from: context)
        #expect(fetched[0].name == "Renamed")
    }

    @Test("Update word persists")
    func updateWordPersists() throws {
        let container = try TestingContainer.make()
        let context = container.mainContext
        let box = try TestFixtures.makeBox(in: context, wordPairs: [("old", "alt")])
        let word = box.words.first!

        word.primaryText = "new"
        word.targetText = "neu"
        word.level = 2
        try context.save()

        let fetched = try TestFixtures.fetchBoxes(from: context)
        let w = fetched[0].words.first!
        #expect(w.primaryText == "new")
        #expect(w.targetText == "neu")
        #expect(w.level == 2)
    }

    @Test("Delete word removes from box")
    func deleteWordRemovesFromBox() throws {
        let container = try TestingContainer.make()
        let context = container.mainContext
        let box = try TestFixtures.makeBox(in: context, wordPairs: [("a", "b"), ("c", "d")])
        let wordToDelete = box.words.first!

        context.delete(wordToDelete)
        try context.save()

        let fetched = try TestFixtures.fetchBoxes(from: context)
        #expect(fetched[0].words.count == 1)
    }

    @Test("Delete box cascades to words")
    func deleteBoxCascadesToWords() throws {
        let container = try TestingContainer.make()
        let context = container.mainContext
        let box = try TestFixtures.makeBox(in: context, wordPairs: [("a", "b"), ("c", "d")])

        context.delete(box)
        try context.save()

        let boxes = try TestFixtures.fetchBoxes(from: context)
        #expect(boxes.count == 0)

        let wordDescriptor = FetchDescriptor<BoxWord>()
        let words = try context.fetch(wordDescriptor)
        #expect(words.count == 0)
    }

    @Test("Empty box progressValue is zero")
    func emptyBoxProgressValueIsZero() throws {
        let container = try TestingContainer.make()
        let context = container.mainContext
        let box = try TestFixtures.makeBox(in: context, wordPairs: [])

        #expect(box.progressValue == 0)
    }

    @Test("BoxWord init clamps level to valid range")
    func boxWordInitClampsLevel() {
        let below = BoxWord(primaryText: "a", targetText: "b", level: 0)
        let above = BoxWord(primaryText: "c", targetText: "d", level: 10)
        #expect(below.level == 1)
        #expect(above.level == 6)
    }
}
