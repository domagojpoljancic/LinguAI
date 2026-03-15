//
//  TestingContainer.swift
//  LinguAITests
//
//  In-memory and persistent ModelContainer helpers for tests.
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
    
    /// Schema used for persistent regression tests (matches app minus Item).
    private static let persistentSchema = Schema([
        VocabularyBox.self,
        BoxWord.self,
    ])
    
    /// Creates a temporary directory URL for a persistent store. Caller must delete when done.
    static func makeTemporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("LinguAITests-\(UUID().uuidString)", isDirectory: true)
    }
    
    /// Creates a ModelContainer that persists to the given directory URL (SwiftData will create store files inside).
    /// Use for regression tests that simulate app relaunch by creating a second container at the same URL.
    static func makePersistent(at storeDirectory: URL) throws -> ModelContainer {
        let storeURL = storeDirectory.appendingPathComponent("default.store")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        let config = ModelConfiguration(
            schema: persistentSchema,
            url: storeURL
        )
        return try ModelContainer(for: persistentSchema, configurations: [config])
    }
    
    /// Deletes the store directory and any files inside. Call after persistent tests to clean up.
    static func removePersistentStore(at storeDirectory: URL) {
        try? FileManager.default.removeItem(at: storeDirectory)
    }
}
