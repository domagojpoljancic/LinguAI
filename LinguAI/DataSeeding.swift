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

    /// Runs once at launch if the database is empty. Uses a background context so the UI
    /// does not hang. Checks via FetchDescriptor to never duplicate on subsequent launches.
    static func runIfNeeded(container: ModelContainer) {
        DispatchQueue.global(qos: .userInitiated).async {
            let context = ModelContext(container)
            do {
                let isEmpty = try isDatabaseEmpty(context: context)
                guard isEmpty else { return }
                try seedGrundlagen(into: context)
            } catch {
                assertionFailure("DataSeeding failed: \(error)")
            }
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
    private static func seedGrundlagen(into context: ModelContext) throws {
        let box = VocabularyBox(
            name: defaultBoxName,
            targetLanguageCode: targetLanguageCode,
            primaryLanguageCode: primaryLanguageCode,
            createdAt: .now
        )
        context.insert(box)

        let now = Date()
        for (primaryText, targetText) in grundlagenWords {
            let word = BoxWord(
                primaryText: primaryText,
                targetText: targetText,
                level: LeitnerEngine.minLevel,
                box: box,
                createdAt: now
            )
            context.insert(word)
        }

        try context.save()
    }
}
