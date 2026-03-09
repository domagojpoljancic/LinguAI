//
//  DataSeeding.swift
//  LinguAI
//
//  One-time seeding of the default "Grundlagen" (Basics) box with high-frequency
//  German words. Uses FetchDescriptor to avoid duplicates on subsequent launches.
//

import Foundation
import SwiftData

enum DataSeeding {

    private static let defaultBoxName = "Grundlagen"
    private static let targetLanguageCode = "de"
    private static let primaryLanguageCode = "en"

    /// High-frequency German → English pairs for the default box (culturally accurate).
    /// Format: (primaryText: English, targetText: German).
    private static let grundlagenWords: [(String, String)] = [
        // Greetings
        ("Hello", "Hallo"),
        ("Thanks", "Danke"),
        ("Please", "Bitte"),
        ("Bye", "Tschüss"),
        ("Yes", "Ja"),
        ("No", "Nein"),
        // Essentials
        ("I", "Ich"),
        ("You", "Du"),
        ("We", "Wir"),
        ("To be", "Sein"),
        ("To have", "Haben"),
        ("To go", "Gehen"),
        ("To do", "Machen"),
        // Nouns
        ("Time", "Zeit"),
        ("Year", "Jahr"),
        ("Way", "Weg"),
        ("Man", "Mann"),
        ("Woman", "Frau"),
        ("Child", "Kind"),
        // Question words
        ("What", "Was"),
        ("Where", "Wo"),
        ("Who", "Wer"),
        ("How", "Wie"),
        ("Why", "Warum"),
        // Common adjectives
        ("Good", "Gut"),
        ("Big", "Groß"),
        ("Small", "Klein"),
        ("New", "Neu"),
        ("Old", "Alt"),
        // Connectors
        ("And", "Und"),
        ("But", "Aber"),
        ("Or", "Oder"),
        ("With", "Mit"),
        // Article (common)
        ("The", "Der"),
    ]

    /// Seeds the Grundlagen demo box only if the database is empty. Call from main thread; uses mainContext.
    /// When spreadLevels is true, words are assigned random levels 1–6 to simulate customer progress. Used by DEBUG "Seed Demo Data" only.
    /// Returns true if seeded, false if DB already had content (no duplicate).
    static func seedDemoDataIfPossible(container: ModelContainer, spreadLevels: Bool = true) -> Bool {
        let context = container.mainContext
        do {
            guard try isDatabaseEmpty(context: context) else { return false }
            try seedGrundlagen(into: context, spreadLevels: spreadLevels)
            return true
        } catch {
            assertionFailure("DataSeeding.seedDemoDataIfPossible failed: \(error)")
            return false
        }
    }

    /// Deletes all boxes (and their words), reseeds "Grundlagen", and clears stored study
    /// direction so the default (target → primary) is used. Call from main thread; uses mainContext.
    static func resetAndReseed(container: ModelContainer) {
        let context = container.mainContext
        do {
            var boxDescriptor = FetchDescriptor<VocabularyBox>()
            boxDescriptor.sortBy = [SortDescriptor(\.createdAt)]
            let boxes = try context.fetch(boxDescriptor)
            for box in boxes {
                context.delete(box)
            }
            try context.save()
            try seedGrundlagen(into: context)
            UserDefaults.standard.removeObject(forKey: "studyDirection")
        } catch {
            assertionFailure("DataSeeding.resetAndReseed failed: \(error)")
        }
    }

    /// Same as resetAndReseed but returns success/failure for UI feedback (e.g. DEBUG Settings).
    static func resetAndReseedIfPossible(container: ModelContainer) -> Bool {
        let context = container.mainContext
        do {
            var boxDescriptor = FetchDescriptor<VocabularyBox>()
            boxDescriptor.sortBy = [SortDescriptor(\.createdAt)]
            let boxes = try context.fetch(boxDescriptor)
            for box in boxes {
                context.delete(box)
            }
            try context.save()
            try seedGrundlagen(into: context)
            UserDefaults.standard.removeObject(forKey: "studyDirection")
            return true
        } catch {
            assertionFailure("DataSeeding.resetAndReseed failed: \(error)")
            return false
        }
    }

    /// Returns true if there are no boxes and no words (safe one-time seed condition).
    private static func isDatabaseEmpty(context: ModelContext) throws -> Bool {
        var boxDescriptor = FetchDescriptor<VocabularyBox>()
        boxDescriptor.fetchLimit = 1
        let hasBoxes = (try context.fetchCount(boxDescriptor)) > 0
        if hasBoxes { return false }

        var wordDescriptor = FetchDescriptor<BoxWord>()
        wordDescriptor.fetchLimit = 1
        let hasWords = (try context.fetchCount(wordDescriptor)) > 0
        return !hasWords
    }

    /// Creates the default "Grundlagen" box and all word pairs, then saves.
    /// Relationship: insert box first, then each word with `word.box = box`.
    /// When spreadLevels is true, each word gets a random level 1–6 to simulate progress across boxes.
    private static func seedGrundlagen(into context: ModelContext, spreadLevels: Bool = false) throws {
        let box = VocabularyBox(
            name: defaultBoxName,
            targetLanguageCode: targetLanguageCode,
            primaryLanguageCode: primaryLanguageCode,
            createdAt: .now
        )
        context.insert(box)

        let now = Date()
        for (primaryText, targetText) in grundlagenWords {
            let level = spreadLevels ? Int.random(in: LeitnerEngine.minLevel...LeitnerEngine.maxLevel) : LeitnerEngine.minLevel
            let word = BoxWord(
                primaryText: primaryText,
                targetText: targetText,
                level: level,
                box: box,
                createdAt: now
            )
            context.insert(word)
        }

        try context.save()
    }
}
