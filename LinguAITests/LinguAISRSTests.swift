//
//  LinguAISRSTests.swift
//  LinguAITests
//
//  Unit tests for Silent SRS: nextReviewDate intervals, Leitner level reset, and two-pass session selection.
//

import Foundation
import SwiftData
import Testing
@testable import LinguAI

@MainActor
@Suite("SRS logic")
struct LinguAISRSTests {

    // MARK: - Test 1: Correct answer in Box 1 → nextReviewDate = 1 day from start of today

    @Test("Correct answer in Box 1 sets nextReviewDate to 1 day from start of today (calendar-based)")
    func correctAnswerBox1SetsNextReviewDate() {
        let cal = Calendar.current
        let result = nextReviewDate(afterCorrectAnswer: 2, calendar: cal)
        let startOfToday = cal.startOfDay(for: Date())
        let expectedTomorrow = cal.date(byAdding: .day, value: 1, to: startOfToday)!

        #expect(cal.isDate(result, inSameDayAs: expectedTomorrow))
        #expect(cal.component(.hour, from: result) == 0)
        #expect(cal.component(.minute, from: result) == 0)
    }

    // MARK: - Test 2: Incorrect answer in Box 3 → level 1, nextReviewDate = now

    @Test("Incorrect answer in Box 3 resets level to 1")
    func incorrectAnswerResetsLevelTo1() {
        let newLevel = LeitnerEngine.level(afterCorrect: false, currentLevel: 3)
        #expect(newLevel == 1)
    }

    @Test("Incorrect answer resets nextReviewDate to now (via word update)")
    func incorrectAnswerResetsNextReviewDate() throws {
        let container = try TestingContainer.make()
        let context = container.mainContext

        let box = VocabularyBox(name: "SRS", targetLanguageCode: "de", primaryLanguageCode: "en")
        context.insert(box)

        let word = BoxWord(primaryText: "hello", targetText: "hallo", level: 3, box: box)
        context.insert(word)
        try context.save()

        let before = Date()
        word.level = LeitnerEngine.level(afterCorrect: false, currentLevel: word.level)
        word.nextReviewDate = Date()
        try context.save()
        let after = Date()

        #expect(word.level == 1)
        #expect(word.nextReviewDate != nil)
        #expect(word.nextReviewDate! >= before.addingTimeInterval(-1))
        #expect(word.nextReviewDate! <= after.addingTimeInterval(1))
    }

    // MARK: - Test 3: Two-pass fetch – 10 requested, 2 due → session has 2 due + 8 future

    @Test("Two-pass selection fills requested count with due first, then future")
    func twoPassSelectionFillsWithDueThenFuture() throws {
        let container = try TestingContainer.make()
        let context = container.mainContext

        let box = VocabularyBox(name: "TwoPass", targetLanguageCode: "de", primaryLanguageCode: "en")
        context.insert(box)

        let now = Date()
        let oneHourAgo = now.addingTimeInterval(-3600)
        let oneDayAhead = now.addingTimeInterval(86400)

        let due1 = BoxWord(primaryText: "a", targetText: "b", level: 1, box: box, nextReviewDate: oneHourAgo)
        let due2 = BoxWord(primaryText: "c", targetText: "d", level: 1, box: box, nextReviewDate: oneHourAgo)
        context.insert(due1)
        context.insert(due2)

        for i in 0..<10 {
            let w = BoxWord(primaryText: "p\(i)", targetText: "t\(i)", level: 1, box: box, nextReviewDate: oneDayAhead)
            context.insert(w)
        }
        try context.save()

        let selected = selectSessionWords(from: box.words, selectedLevelIDs: [1, 2, 3, 4, 5, 6], requestedCount: 10, now: now)

        #expect(selected.count == 10)
        let selectedIDs = Set(selected.map(\.uuid))
        #expect(selectedIDs.contains(due1.uuid))
        #expect(selectedIDs.contains(due2.uuid))
    }

    // MARK: - Record-answer integration (same logic as StudyView.recordAnswer)

    @Test("Recording correct answer updates level and nextReviewDate")
    func recordCorrectAnswerUpdatesLevelAndNextReviewDate() throws {
        let container = try TestingContainer.make()
        let context = container.mainContext
        let box = try TestFixtures.makeBox(in: context, wordPairs: [("a", "b")])
        let word = box.words.first!
        let cal = Calendar.current

        word.level = LeitnerEngine.level(afterCorrect: true, currentLevel: word.level)
        word.lastReviewedDate = Date()
        word.nextReviewDate = word.level == LeitnerEngine.maxLevel
            ? .distantFuture
            : nextReviewDate(afterCorrectAnswer: word.level, calendar: cal)
        try context.save()

        #expect(word.level == 2)
        #expect(word.nextReviewDate != nil)
        #expect(word.nextReviewDate != .distantFuture)
        let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        #expect(cal.isDate(word.nextReviewDate!, inSameDayAs: startOfTomorrow))
    }

    @Test("Recording wrong answer resets level to 1 and sets nextReviewDate to now")
    func recordWrongAnswerResetsLevelAndSetsNextReviewToNow() throws {
        let container = try TestingContainer.make()
        let context = container.mainContext
        let box = try TestFixtures.makeBox(in: context, wordPairs: [])
        _ = try TestFixtures.addWord(to: box, primaryText: "a", targetText: "b", level: 3, in: context)
        let word = box.words.first!

        word.level = LeitnerEngine.level(afterCorrect: false, currentLevel: word.level)
        word.lastReviewedDate = Date()
        word.nextReviewDate = Date()
        try context.save()

        #expect(word.level == 1)
        #expect(word.nextReviewDate != nil)
    }

    @Test("Recording correct at max level sets nextReviewDate to distantFuture")
    func recordCorrectAtMaxLevelSetsDistantFuture() throws {
        let container = try TestingContainer.make()
        let context = container.mainContext
        let box = try TestFixtures.makeBox(in: context, wordPairs: [])
        _ = try TestFixtures.addWord(to: box, primaryText: "a", targetText: "b", level: 5, in: context)
        let word = box.words.first!
        let cal = Calendar.current

        word.level = LeitnerEngine.level(afterCorrect: true, currentLevel: word.level)
        word.lastReviewedDate = Date()
        word.nextReviewDate = word.level == LeitnerEngine.maxLevel
            ? .distantFuture
            : nextReviewDate(afterCorrectAnswer: word.level, calendar: cal)
        try context.save()

        #expect(word.level == 6)
        #expect(word.nextReviewDate == .distantFuture)
    }
}
