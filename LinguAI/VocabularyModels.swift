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

    /// Returns the new level after an answer. Correct: +1 (capped at 6). Wrong: 1.
    static func level(afterCorrect: Bool, currentLevel: Int) -> Int {
        guard currentLevel >= minLevel, currentLevel <= maxLevel else { return minLevel }
        if afterCorrect {
            return min(maxLevel, currentLevel + 1)
        }
        return minLevel
    }
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

    /// Progress 0...1 from average Leitner level (no words → 0).
    var progress: Double {
        guard !words.isEmpty else { return 0 }
        let sum = words.reduce(0) { $0 + $1.level }
        return Double(sum) / Double(words.count) / Double(LeitnerEngine.maxLevel)
    }
}

@Model
final class BoxWord {
    var uuid: UUID
    var primaryText: String
    var targetText: String
    var level: Int
    var createdAt: Date

    var box: VocabularyBox?

    init(
        uuid: UUID = UUID(),
        primaryText: String,
        targetText: String,
        level: Int = 1,
        box: VocabularyBox? = nil,
        createdAt: Date = .now
    ) {
        self.uuid = uuid
        self.primaryText = primaryText
        self.targetText = targetText
        self.level = min(LeitnerEngine.maxLevel, max(LeitnerEngine.minLevel, level))
        self.box = box
        self.createdAt = createdAt
    }
}
