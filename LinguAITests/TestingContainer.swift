//
//  TestingContainer.swift
//  LinguAITests
//
//  In-memory ModelContainer for VocabularyBox and BoxWord. Keeps container
//  alive so SwiftData context remains valid during tests.
//

import Foundation
import SwiftData
@testable import LinguAI

enum TestingContainer {
    /// Creates an in-memory ModelContainer for VocabularyBox and BoxWord.
    /// Store the returned container for the duration of the test so it is not deallocated.
    static func make() throws -> ModelContainer {
        let schema = Schema([
            VocabularyBox.self,
            BoxWord.self,
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [config])
    }
}
