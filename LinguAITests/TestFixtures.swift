//
//  TestFixtures.swift
//  LinguAITests
//
//  Reusable in-memory test data builders. All persistence uses TestingContainer (in-memory only).
//

import Foundation
import SwiftData
@testable import LinguAI

@MainActor
enum TestFixtures {

    /// Inserts a box with optional words and saves. Returns the box; keep container alive for the test.
    static func makeBox(
        in context: ModelContext,
        name: String = "TestBox",
        targetLanguageCode: String = "de",
        primaryLanguageCode: String = "en",
        wordPairs: [(primary: String, target: String)] = []
    ) throws -> VocabularyBox {
        let box = VocabularyBox(
            name: name,
            targetLanguageCode: targetLanguageCode,
            primaryLanguageCode: primaryLanguageCode
        )
        context.insert(box)
        for (primary, target) in wordPairs {
            let word = BoxWord(primaryText: primary, targetText: target, level: 1, box: box)
            context.insert(word)
        }
        try context.save()
        return box
    }

    /// Inserts a word into an existing box and saves. Returns the word.
    static func addWord(
        to box: VocabularyBox,
        primaryText: String,
        targetText: String,
        level: Int = 1,
        nextReviewDate: Date? = nil,
        in context: ModelContext
    ) throws -> BoxWord {
        let word = BoxWord(
            primaryText: primaryText,
            targetText: targetText,
            level: level,
            box: box,
            nextReviewDate: nextReviewDate
        )
        context.insert(word)
        try context.save()
        return word
    }

    /// Fetches all boxes sorted by name (for assertions).
    static func fetchBoxes(from context: ModelContext) throws -> [VocabularyBox] {
        var descriptor = FetchDescriptor<VocabularyBox>()
        descriptor.sortBy = [SortDescriptor(\.name)]
        return try context.fetch(descriptor)
    }

    /// Fetches all words for a box (via relationship; use after refresh if needed).
    static func wordCount(for box: VocabularyBox) -> Int {
        box.words.count
    }
}
