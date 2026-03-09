//
//  PersistentStoreRegressionTests.swift
//  LinguAITests
//
//  Regression tests: data must survive container recreation (simulated app relaunch).
//  Uses a temporary persistent store URL; cleans up after each test.
//

import Foundation
import SwiftData
import Testing
@testable import LinguAI

@MainActor
@Suite("Persistent store regression")
struct PersistentStoreRegressionTests {

    @Test("Box persists across container recreation (simulated relaunch)")
    func boxPersistsAcrossContainerRecreation() throws {
        let storeURL = TestingContainer.makeTemporaryStoreURL()
        defer { TestingContainer.removePersistentStore(at: storeURL) }

        let boxName = "RegressionBox-\(UUID().uuidString.prefix(8))"
        do {
            let container = try TestingContainer.makePersistent(at: storeURL)
            let context = container.mainContext
            let box = VocabularyBox(
                name: boxName,
                targetLanguageCode: "de",
                primaryLanguageCode: "en"
            )
            context.insert(box)
            try context.save()
        }

        do {
            let container = try TestingContainer.makePersistent(at: storeURL)
            let context = container.mainContext
            let descriptor = FetchDescriptor<VocabularyBox>()
            let boxes = try context.fetch(descriptor)
            let matching = boxes.filter { $0.name == boxName }
            #expect(matching.count == 1)
            #expect(matching[0].name == boxName)
            #expect(matching[0].targetLanguageCode == "de")
        }
    }

    @Test("Word persists across container recreation (simulated relaunch)")
    func wordPersistsAcrossContainerRecreation() throws {
        let storeURL = TestingContainer.makeTemporaryStoreURL()
        defer { TestingContainer.removePersistentStore(at: storeURL) }

        let boxName = "WordRegression-\(UUID().uuidString.prefix(8))"
        let primaryText = "Hello"
        let targetText = "Hallo"
        do {
            let container = try TestingContainer.makePersistent(at: storeURL)
            let context = container.mainContext
            let box = VocabularyBox(
                name: boxName,
                targetLanguageCode: "de",
                primaryLanguageCode: "en"
            )
            context.insert(box)
            let word = BoxWord(primaryText: primaryText, targetText: targetText, level: 1, box: box)
            context.insert(word)
            try context.save()
        }

        do {
            let container = try TestingContainer.makePersistent(at: storeURL)
            let context = container.mainContext
            let boxDescriptor = FetchDescriptor<VocabularyBox>()
            let boxes = try context.fetch(boxDescriptor)
            let matching = boxes.filter { $0.name == boxName }
            #expect(matching.count == 1)
            #expect(matching[0].words.count == 1)
            #expect(matching[0].words[0].primaryText == primaryText)
            #expect(matching[0].words[0].targetText == targetText)
        }
    }
}
