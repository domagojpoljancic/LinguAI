//
//  LinguAIApp.swift
//  LinguAI
//
//  Created by Domagoj Poljancic on 05.03.26.
//

import SwiftUI
import SwiftData

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

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
