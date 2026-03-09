//
//  LeitnerEngineTests.swift
//  LinguAITests
//
//  Unit tests for Leitner level transitions and SRS nextReviewDate.
//

import Foundation
import Testing
@testable import LinguAI

@Suite("Leitner engine")
struct LeitnerEngineTests {

    @Test("Correct answer increments level")
    func correctAnswerIncrementsLevel() {
        #expect(LeitnerEngine.level(afterCorrect: true, currentLevel: 1) == 2)
        #expect(LeitnerEngine.level(afterCorrect: true, currentLevel: 2) == 3)
        #expect(LeitnerEngine.level(afterCorrect: true, currentLevel: 5) == 6)
    }

    @Test("Correct answer at max level stays at six")
    func correctAnswerAtMaxLevelStaysAtSix() {
        #expect(LeitnerEngine.level(afterCorrect: true, currentLevel: 6) == 6)
    }

    @Test("Incorrect answer resets to level one")
    func incorrectAnswerResetsToLevelOne() {
        #expect(LeitnerEngine.level(afterCorrect: false, currentLevel: 1) == 1)
        #expect(LeitnerEngine.level(afterCorrect: false, currentLevel: 3) == 1)
        #expect(LeitnerEngine.level(afterCorrect: false, currentLevel: 6) == 1)
    }

    @Test("Level boundaries clamp to valid range")
    func levelBoundariesClampToValidRange() {
        #expect(LeitnerEngine.level(afterCorrect: true, currentLevel: 0) == 1)
        #expect(LeitnerEngine.level(afterCorrect: true, currentLevel: 7) == 1)
        #expect(LeitnerEngine.level(afterCorrect: false, currentLevel: 0) == 1)
    }

    @Test("Level weight progress 0 to 1")
    func levelWeightProgress() {
        #expect(LeitnerEngine.levelWeight(for: 1) == 0.0)
        #expect(LeitnerEngine.levelWeight(for: 2) == 0.2)
        #expect(LeitnerEngine.levelWeight(for: 3) == 0.4)
        #expect(LeitnerEngine.levelWeight(for: 6) == 1.0)
    }

    @Test("Level weight out of range returns zero")
    func levelWeightOutOfRangeReturnsZero() {
        #expect(LeitnerEngine.levelWeight(for: 0) == 0)
        #expect(LeitnerEngine.levelWeight(for: 7) == 0)
    }

    @Test("Next review date level 2 is tomorrow start of day")
    func nextReviewDateLevelTwoIsTomorrowStartOfDay() {
        let cal = Calendar.current
        let result = nextReviewDate(afterCorrectAnswer: 2, calendar: cal)
        let startOfToday = cal.startOfDay(for: Date())
        let expected = cal.date(byAdding: .day, value: 1, to: startOfToday)!
        #expect(cal.isDate(result, inSameDayAs: expected))
        #expect(cal.component(.hour, from: result) == 0)
    }

    @Test("Next review date level 6 is fourteen days ahead")
    func nextReviewDateLevelSixIsFourteenDaysAhead() {
        let cal = Calendar.current
        let result = nextReviewDate(afterCorrectAnswer: 6, calendar: cal)
        let startOfToday = cal.startOfDay(for: Date())
        let expected = cal.date(byAdding: .day, value: 14, to: startOfToday)!
        #expect(cal.isDate(result, inSameDayAs: expected))
    }

    @Test("Next review date level 1 returns same day")
    func nextReviewDateLevelOneReturnsSameDay() {
        let cal = Calendar.current
        let result = nextReviewDate(afterCorrectAnswer: 1, calendar: cal)
        let startOfToday = cal.startOfDay(for: Date())
        #expect(cal.isDate(result, inSameDayAs: startOfToday))
    }
}
