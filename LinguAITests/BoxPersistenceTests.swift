//
//  BoxPersistenceTests.swift
//  LinguAITests
//
//  TDD: Box creation persistence. Must pass before wiring the New Box Save button.
//

import Foundation
import SwiftData
import Testing
@testable import LinguAI

@MainActor
@Suite("Box persistence")
struct BoxPersistenceTests {

    @Test("Creating a box and saving persists it so it can be fetched back")
    func testBoxCreationPersists() throws {
        let container = try TestingContainer.make()
        let context = container.mainContext

        let box = VocabularyBox(
            name: "Test",
            targetLanguageCode: "de",
            primaryLanguageCode: "en"
        )
        context.insert(box)
        try context.save()

        var descriptor = FetchDescriptor<VocabularyBox>()
        descriptor.sortBy = [SortDescriptor(\.name)]
        let fetched = try context.fetch(descriptor)

        #expect(fetched.count == 1)
        #expect(fetched[0].name == "Test")
        #expect(fetched[0].targetLanguageCode == "de")
        #expect(fetched[0].primaryLanguageCode == "en")
    }
}
