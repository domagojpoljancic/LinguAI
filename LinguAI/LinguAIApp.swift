//
//  LinguAIApp.swift
//  LinguAI
//
//  Created by Domagoj Poljancic on 05.03.26.
//

import SwiftUI
import SwiftData

/// Set to `true` for one launch to clear the database, reseed "Grundlagen", and reset study direction default. Set back to `false` after.
private let _reseedDatabaseForTesting = true

@main
struct LinguAIApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            VocabularyBox.self,
            BoxWord.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        #if DEBUG
        if _reseedDatabaseForTesting {
            DataSeeding.resetAndReseed(container: sharedModelContainer)
        } else {
            DataSeeding.runIfNeeded(container: sharedModelContainer)
        }
        #else
        DataSeeding.runIfNeeded(container: sharedModelContainer)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
