//
//  ValidationTests.swift
//  LinguAITests
//
//  Unit tests for duplicate box name and duplicate word pair validation.
//

import Foundation
import SwiftData
import Testing
@testable import LinguAI

@MainActor
@Suite("Validation")
struct ValidationTests {

    // MARK: - Box name

    @Test("Duplicate box name returns true when name matches existing (case-insensitive)")
    func duplicateBoxNameCaseInsensitive() throws {
        let container = try TestingContainer.make()
        let context = container.mainContext
        _ = try TestFixtures.makeBox(in: context, name: "German", wordPairs: [])
        let boxes = try TestFixtures.fetchBoxes(from: context)

        #expect(Validation.isDuplicateBoxName("german", existingBoxes: boxes, editingBox: nil) == true)
        #expect(Validation.isDuplicateBoxName("GERMAN", existingBoxes: boxes, editingBox: nil) == true)
        #expect(Validation.isDuplicateBoxName("Other", existingBoxes: boxes, editingBox: nil) == false)
    }

    @Test("Editing box is excluded from duplicate check")
    func editingBoxExcludedFromDuplicateCheck() throws {
        let container = try TestingContainer.make()
        let context = container.mainContext
        let box = try TestFixtures.makeBox(in: context, name: "German", wordPairs: [])
        let boxes = try TestFixtures.fetchBoxes(from: context)

        #expect(Validation.isDuplicateBoxName("German", existingBoxes: boxes, editingBox: box) == false)
        #expect(Validation.isDuplicateBoxName("German", existingBoxes: boxes, editingBox: nil) == true)
    }

    @Test("Empty list means no duplicate box name")
    func emptyBoxesNoDuplicate() {
        #expect(Validation.isDuplicateBoxName("Any", existingBoxes: [], editingBox: nil) == false)
    }

    // MARK: - Word pair

    @Test("Duplicate word pair returns true when primary and target match (case-insensitive)")
    func duplicateWordPairCaseInsensitive() throws {
        let container = try TestingContainer.make()
        let context = container.mainContext
        let box = try TestFixtures.makeBox(in: context, wordPairs: [("Hello", "Hallo"), ("Thanks", "Danke")])

        #expect(Validation.isDuplicateWordPair(primary: "hello", target: "hallo", words: box.words) == true)
        #expect(Validation.isDuplicateWordPair(primary: "Thanks", target: "Danke", words: box.words) == true)
        #expect(Validation.isDuplicateWordPair(primary: "New", target: "Neu", words: box.words) == false)
    }

    @Test("Empty words list means no duplicate word pair")
    func emptyWordsNoDuplicate() {
        #expect(Validation.isDuplicateWordPair(primary: "A", target: "B", words: []) == false)
    }
}
