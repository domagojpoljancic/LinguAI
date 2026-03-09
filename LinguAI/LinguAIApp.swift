//
//  LinguAIApp.swift
//  LinguAI
//
//  Created by Domagoj Poljancic on 05.03.26.
//

import SwiftUI
import SwiftData

#if DEBUG
/// DEBUG only: holds the app's ModelContainer for "How To" sheet → Developer Tools (Seed / Reset and Seed Demo Data).
enum DebugAppContainer {
    static weak var container: ModelContainer?
}
#endif

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
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            #if DEBUG
            DebugAppContainer.container = container
            #endif
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        // No automatic seeding: app starts with empty DB. Demo content only via DEBUG "How To" → Developer Tools.
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
