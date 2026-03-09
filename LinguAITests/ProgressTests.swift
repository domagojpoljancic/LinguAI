//
//  ProgressTests.swift
//  LinguAITests
//
//  Unit tests for VocabularyBox.progressValue and [VocabularyBox].totalMasteryProgress.
//

import SwiftData
import Testing
@testable import LinguAI

@MainActor
@Suite("Progress")
struct ProgressTests {

    private static let accuracy = 0.001

    @Test("Progress value all level 1 is zero")
    func progressValueAllLevelOne() throws {
        let container = try TestingContainer.make()
        let context = container.mainContext
        let box = try TestFixtures.makeBox(in: context, wordPairs: [("a", "b"), ("c", "d")])

        #expect(box.progressValue == 0)
    }

    @Test("Progress value all level 6 is one")
    func progressValueAllLevelSix() throws {
        let container = try TestingContainer.make()
        let context = container.mainContext
        let box = try TestFixtures.makeBox(in: context, wordPairs: [])
        _ = try TestFixtures.addWord(to: box, primaryText: "a", targetText: "b", level: 6, in: context)
        _ = try TestFixtures.addWord(to: box, primaryText: "c", targetText: "d", level: 6, in: context)

        #expect((box.progressValue - 1.0).magnitude < Self.accuracy)
    }

    @Test("Progress value mixed levels")
    func progressValueMixedLevels() throws {
        let container = try TestingContainer.make()
        let context = container.mainContext
        let box = try TestFixtures.makeBox(in: context, wordPairs: [])
        _ = try TestFixtures.addWord(to: box, primaryText: "a", targetText: "b", level: 1, in: context)
        _ = try TestFixtures.addWord(to: box, primaryText: "c", targetText: "d", level: 6, in: context)

        let expected = (0.0 + 1.0) / 2.0
        #expect((box.progressValue - expected).magnitude < Self.accuracy)
    }

    @Test("Total mastery progress empty boxes is zero")
    func totalMasteryProgressEmptyBoxes() throws {
        let container = try TestingContainer.make()
        let context = container.mainContext
        _ = try TestFixtures.makeBox(in: context, wordPairs: [])
        _ = try TestFixtures.makeBox(in: context, name: "Empty2", wordPairs: [])

        let boxes = try TestFixtures.fetchBoxes(from: context)
        #expect(boxes.totalMasteryProgress == 0)
    }

    @Test("Total mastery progress single box all level 6 is one")
    func totalMasteryProgressSingleBoxAllLevelSix() throws {
        let container = try TestingContainer.make()
        let context = container.mainContext
        let box = try TestFixtures.makeBox(in: context, wordPairs: [])
        _ = try TestFixtures.addWord(to: box, primaryText: "a", targetText: "b", level: 6, in: context)

        let boxes = try TestFixtures.fetchBoxes(from: context)
        #expect((boxes.totalMasteryProgress - 1.0).magnitude < Self.accuracy)
    }

    @Test("Total mastery progress two boxes weighted")
    func totalMasteryProgressTwoBoxesWeighted() throws {
        let container = try TestingContainer.make()
        let context = container.mainContext
        let box1 = try TestFixtures.makeBox(in: context, name: "B1", wordPairs: [])
        let box2 = try TestFixtures.makeBox(in: context, name: "B2", wordPairs: [])
        _ = try TestFixtures.addWord(to: box1, primaryText: "a", targetText: "b", level: 1, in: context)
        _ = try TestFixtures.addWord(to: box2, primaryText: "c", targetText: "d", level: 6, in: context)

        let boxes = try TestFixtures.fetchBoxes(from: context)
        let total = boxes.totalMasteryProgress
        #expect((total - 0.5).magnitude < Self.accuracy)
    }
}
