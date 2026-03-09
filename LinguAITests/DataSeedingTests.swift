//
//  DataSeedingTests.swift
//  LinguAITests
//
//  Integration tests for resetAndReseed: one box "Grundlagen" with expected word count.
//

import Foundation
import SwiftData
import Testing
@testable import LinguAI

@MainActor
@Suite("Data seeding")
struct DataSeedingTests {

    /// Grundlagen seed word count (must match DataSeeding.grundlagenWords.count).
    private static let expectedGrundlagenWordCount = 34

    @Test("Reset and reseed creates single Grundlagen box with expected word count")
    func resetAndReseedCreatesGrundlagenBox() throws {
        let container = try TestingContainer.make()
        DataSeeding.resetAndReseed(container: container)

        let context = container.mainContext
        let boxes = try TestFixtures.fetchBoxes(from: context)

        #expect(boxes.count == 1)
        #expect(boxes[0].name == "Grundlagen")
        #expect(boxes[0].targetLanguageCode == "de")
        #expect(boxes[0].primaryLanguageCode == "en")
        #expect(boxes[0].words.count == Self.expectedGrundlagenWordCount)
    }
}
