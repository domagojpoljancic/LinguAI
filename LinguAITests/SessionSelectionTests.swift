//
//  SessionSelectionTests.swift
//  LinguAITests
//
//  Unit tests for two-pass selectSessionWords: due vs future, counts, empty, boundaries.
//

import Foundation
import SwiftData
import Testing
@testable import LinguAI

@MainActor
@Suite("Session selection")
struct SessionSelectionTests {

    @Test("Only due words when enough due")
    func onlyDueWordsWhenEnoughDue() throws {
        let container = try TestingContainer.make()
        let context = container.mainContext
        let box = try TestFixtures.makeBox(in: context, wordPairs: [])
        let now = Date()
        let past = now.addingTimeInterval(-3600)
        _ = try TestFixtures.addWord(to: box, primaryText: "a", targetText: "b", level: 1, nextReviewDate: past, in: context)
        _ = try TestFixtures.addWord(to: box, primaryText: "c", targetText: "d", level: 1, nextReviewDate: past, in: context)
        _ = try TestFixtures.addWord(to: box, primaryText: "e", targetText: "f", level: 1, nextReviewDate: past, in: context)

        let selected = selectSessionWords(from: box.words, selectedLevelIDs: [1, 2, 3, 4, 5, 6], requestedCount: 2, now: now)

        #expect(selected.count == 2)
    }

    @Test("Requested count capped by available")
    func requestedCountCappedByAvailable() throws {
        let container = try TestingContainer.make()
        let context = container.mainContext
        let box = try TestFixtures.makeBox(in: context, wordPairs: [("p1", "t1"), ("p2", "t2")])

        let selected = selectSessionWords(from: box.words, selectedLevelIDs: [1, 2, 3, 4, 5, 6], requestedCount: 10, now: Date())

        #expect(selected.count == 2)
    }

    @Test("Minimum one when words exist")
    func minimumOneWhenWordsExist() throws {
        let container = try TestingContainer.make()
        let context = container.mainContext
        let box = try TestFixtures.makeBox(in: context, wordPairs: [("a", "b")])

        let selected = selectSessionWords(from: box.words, selectedLevelIDs: [1], requestedCount: 0, now: Date())

        #expect(selected.count == 1)
    }

    @Test("Filters by selected level IDs")
    func filtersBySelectedLevelIDs() throws {
        let container = try TestingContainer.make()
        let context = container.mainContext
        let box = try TestFixtures.makeBox(in: context, wordPairs: [])
        _ = try TestFixtures.addWord(to: box, primaryText: "a", targetText: "b", level: 1, in: context)
        _ = try TestFixtures.addWord(to: box, primaryText: "c", targetText: "d", level: 2, in: context)
        _ = try TestFixtures.addWord(to: box, primaryText: "e", targetText: "f", level: 3, in: context)

        let selectedOnlyLevel2 = selectSessionWords(from: box.words, selectedLevelIDs: [2], requestedCount: 10, now: Date())

        #expect(selectedOnlyLevel2.count == 1)
        #expect(selectedOnlyLevel2[0].level == 2)
    }

    @Test("Nil nextReviewDate treated as due")
    func nilNextReviewDateTreatedAsDue() throws {
        let container = try TestingContainer.make()
        let context = container.mainContext
        let box = try TestFixtures.makeBox(in: context, wordPairs: [("p", "t")])
        let word = box.words.first!
        word.nextReviewDate = nil
        try context.save()

        let selected = selectSessionWords(from: box.words, selectedLevelIDs: [1], requestedCount: 5, now: Date())

        #expect(selected.count == 1)
    }

    @Test("Empty filtered list returns empty")
    func emptyFilteredListReturnsEmpty() throws {
        let container = try TestingContainer.make()
        let context = container.mainContext
        let box = try TestFixtures.makeBox(in: context, wordPairs: [("a", "b")])

        let selected = selectSessionWords(from: box.words, selectedLevelIDs: [2], requestedCount: 5, now: Date())

        #expect(selected.count == 0)
    }
}
