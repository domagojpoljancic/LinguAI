//
//  VocabularyModels.swift
//  LinguAI
//
//  SwiftData schema and Leitner engine. Production-grade persistence with
//  clear relationships and 6-level progression.
//

import Foundation
import SwiftData

// MARK: - Leitner engine (6 levels)

/// Leitner progression: Correct → move up one level (max 6); Wrong → reset to Level 1.
enum LeitnerEngine {
    static let maxLevel = 6
    static let minLevel = 1

    /// Weight for mastery progress: Box 1 = 0%, 2 = 20%, 3 = 40%, 4 = 60%, 5 = 80%, 6 = 100%.
    static func levelWeight(for level: Int) -> Double {
        guard level >= minLevel, level <= maxLevel else { return 0 }
        return Double(level - 1) * 0.2
    }

    /// Returns the new level after an answer. Correct: +1 (capped at 6). Wrong: 1.
    static func level(afterCorrect: Bool, currentLevel: Int) -> Int {
        guard currentLevel >= minLevel, currentLevel <= maxLevel else { return minLevel }
        if afterCorrect {
            return min(maxLevel, currentLevel + 1)
        }
        return minLevel
    }
}

// MARK: - SRS intervals (silent spaced repetition)

/// Days to add for next review by new level after a correct answer. Level 1 = 0 (wrong answer).
private let srsDaysByLevel: [Int: Int] = [
    2: 1, 3: 2, 4: 4, 5: 7, 6: 14
]

/// Returns the next review date after a correct answer: start of today (local) + interval days. Uses current calendar for timezone safety.
func nextReviewDate(afterCorrectAnswer newLevel: Int, calendar: Calendar = .current) -> Date {
    let days = srsDaysByLevel[newLevel] ?? 0
    let now = Date()
    let startOfToday = calendar.startOfDay(for: now)
    return calendar.date(byAdding: .day, value: days, to: startOfToday) ?? now
}

// MARK: - SwiftData models

@Model
final class VocabularyBox {
    var name: String
    var targetLanguageCode: String
    var primaryLanguageCode: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \BoxWord.box)
    var words: [BoxWord] = []

    init(
        name: String,
        targetLanguageCode: String,
        primaryLanguageCode: String = "en",
        createdAt: Date = .now
    ) {
        self.name = name
        self.targetLanguageCode = targetLanguageCode
        self.primaryLanguageCode = primaryLanguageCode
        self.createdAt = createdAt
    }

    var wordCount: Int { words.count }

    /// Box progress 0...1: [Σ(Word Level - 1) / (Total Words × 5)]. Linear step: 5 gaps between Level 1 (0%) and Level 6 / Mastered (100%).
    /// Level 1 = 0%, Level 3 = 40%, Level 6 (Mastered) = 100%. Empty box = 0.
    var progressValue: Double {
        guard !words.isEmpty else { return 0 }
        let sum = words.reduce(0.0) { acc, word in
            acc + (Double(word.level) - 1) / 5.0
        }
        return sum / Double(words.count)
    }
}

// MARK: - Global mastery progress (weighted across all boxes)

extension Array where Element == VocabularyBox {
    /// Total mastery progress 0...1: Σ(Words in Level_n × Weight_n) / Total Words.
    /// Box 1 = 0%, Box 2 = 20%, Box 3 = 40%, Box 4 = 60%, Box 5 = 80%, Box 6 (Mastered) = 100%.
    var totalMasteryProgress: Double {
        var totalWords = 0
        var weightedSum: Double = 0
        for box in self {
            for word in box.words {
                totalWords += 1
                weightedSum += LeitnerEngine.levelWeight(for: word.level)
            }
        }
        guard totalWords > 0 else { return 0 }
        return weightedSum / Double(totalWords)
    }
}

@Model
final class BoxWord {
    var uuid: UUID
    var primaryText: String
    var targetText: String
    var level: Int
    var createdAt: Date
    /// Last time the word was reviewed (correct or incorrect). Used for SRS.
    var lastReviewedDate: Date?
    /// When the word is next due for review. nil = treat as due. New words get Date.now so they are immediately available.
    var nextReviewDate: Date?

    var box: VocabularyBox?

    init(
        uuid: UUID = UUID(),
        primaryText: String,
        targetText: String,
        level: Int = 1,
        box: VocabularyBox? = nil,
        createdAt: Date = .now,
        lastReviewedDate: Date? = nil,
        nextReviewDate: Date? = nil
    ) {
        self.uuid = uuid
        self.primaryText = primaryText
        self.targetText = targetText
        self.level = min(LeitnerEngine.maxLevel, max(LeitnerEngine.minLevel, level))
        self.box = box
        self.createdAt = createdAt
        self.lastReviewedDate = lastReviewedDate
        self.nextReviewDate = nextReviewDate ?? createdAt
    }
}

// MARK: - Session word selection (two-pass SRS)

/// Two-pass selection: due words first (oldest nextReviewDate), then future words to fill. Used by study session and tests.
func selectSessionWords(from words: [BoxWord], selectedLevelIDs: Set<Int>, requestedCount: Int, now: Date) -> [BoxWord] {
    let filtered = words.filter { selectedLevelIDs.contains($0.level) }
    let count = max(1, min(requestedCount, filtered.count))

    let due = filtered.filter { ($0.nextReviewDate ?? .distantPast) <= now }
    let dueSorted = due.sorted { ($0.nextReviewDate ?? .distantPast) < ($1.nextReviewDate ?? .distantPast) }
    var selected = Array(dueSorted.prefix(count))

    if selected.count < count {
        let future = filtered.filter { word in
            guard let d = word.nextReviewDate else { return false }
            return d > now
        }
        let futureSorted = future.sorted { ($0.nextReviewDate ?? .distantFuture) < ($1.nextReviewDate ?? .distantFuture) }
        let needed = count - selected.count
        selected.append(contentsOf: futureSorted.shuffled().prefix(needed))
    }

    return selected
}
