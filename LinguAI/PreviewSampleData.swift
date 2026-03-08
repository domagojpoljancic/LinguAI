//
//  PreviewSampleData.swift
//  LinguAI
//
//  Reusable SwiftData preview system. In-memory containers and seeded sample data
//  for consistent, fast previews. All code is debug-only and never ships.
//

#if DEBUG

import Foundation
import SwiftUI
import SwiftData

// MARK: - Preview container factory & caching

/// In-memory schema matching the app. Use for all preview containers so views see
/// the same model types (VocabularyBox, BoxWord, Item).
private let previewSchema = Schema([
    Item.self,
    VocabularyBox.self,
    BoxWord.self,
])

/// Creates a new in-memory `ModelContainer` for previews. Use `sharedPreviewContainerWithData`
/// or `sharedPreviewContainerEmpty` for cached containers.
func makePreviewContainer(seed: Bool = false) throws -> ModelContainer {
    let config = ModelConfiguration(
        schema: previewSchema,
        isStoredInMemoryOnly: true
    )
    let container = try ModelContainer(for: previewSchema, configurations: [config])
    if seed {
        seedSampleData(into: container.mainContext)
    }
    return container
}

/// Returns a shared `ModelContext` backed by the seeded in-memory container.
/// Use this when you need a context for one-off preview setups; for views use
/// `.withSampleData()` so the view receives the container via environment.
func makeSharedContext() -> ModelContext {
    sharedPreviewContainerWithData.mainContext
}

// MARK: - Cached preview containers (modifier caching)

/// **Caching:** The first time a preview uses `.withSampleData()`, this creates
/// one in-memory container, seeds it, and stores it here. Every subsequent
/// preview reuses the same container, so SwiftUI doesn’t recreate the graph
/// and previews stay fast. Add new sample data by editing `seedSampleData(into:)`.
private var _sharedPreviewContainerWithData: ModelContainer?
private let _previewDataLock = NSLock()

var sharedPreviewContainerWithData: ModelContainer {
    _previewDataLock.lock()
    defer { _previewDataLock.unlock() }
    if let existing = _sharedPreviewContainerWithData {
        return existing
    }
    guard let container = try? makePreviewContainer(seed: true) else {
        fatalError("PreviewSampleData: failed to create seeded container")
    }
    _sharedPreviewContainerWithData = container
    return container
}

/// Empty in-memory container for "Empty State" previews. Cached the same way.
private var _sharedPreviewContainerEmpty: ModelContainer?
var sharedPreviewContainerEmpty: ModelContainer {
    _previewDataLock.lock()
    defer { _previewDataLock.unlock() }
    if let existing = _sharedPreviewContainerEmpty {
        return existing
    }
    guard let container = try? makePreviewContainer(seed: false) else {
        fatalError("PreviewSampleData: failed to create empty container")
    }
    _sharedPreviewContainerEmpty = container
    return container
}

// MARK: - Seeding (object graph built before inserts)

/// Seeds the context with 3 boxes: French (5+ words), German (5+ words), Spanish (empty).
/// Relationships are established by inserting the box first, then inserting words
/// with `word.box = box` so the inverse `box.words` is fully connected.
func seedSampleData(into context: ModelContext) {
    let now = Date()

    // 1. French box – 5+ words
    let frenchBox = VocabularyBox(
        name: "French",
        targetLanguageCode: "fr",
        primaryLanguageCode: "en",
        createdAt: now
    )
    context.insert(frenchBox)
    let frenchWords: [(String, String)] = [
        ("Hello", "Bonjour"),
        ("Thank you", "Merci"),
        ("Goodbye", "Au revoir"),
        ("Please", "S'il vous plaît"),
        ("Water", "Eau"),
        ("Coffee", "Café"),
    ]
    for (primary, target) in frenchWords {
        let word = BoxWord(
            primaryText: primary,
            targetText: target,
            level: Int.random(in: 1...LeitnerEngine.maxLevel),
            box: frenchBox,
            createdAt: now
        )
        context.insert(word)
    }

    // 2. German box – 5+ words
    let germanBox = VocabularyBox(
        name: "German",
        targetLanguageCode: "de",
        primaryLanguageCode: "en",
        createdAt: now.addingTimeInterval(-100)
    )
    context.insert(germanBox)
    let germanWords: [(String, String)] = [
        ("Hello", "Hallo"),
        ("Thank you", "Danke"),
        ("Goodbye", "Auf Wiedersehen"),
        ("Please", "Bitte"),
        ("Water", "Wasser"),
        ("Book", "Buch"),
    ]
    for (primary, target) in germanWords {
        let word = BoxWord(
            primaryText: primary,
            targetText: target,
            level: Int.random(in: 1...LeitnerEngine.maxLevel),
            box: germanBox,
            createdAt: now
        )
        context.insert(word)
    }

    // 3. Spanish box – empty (tests empty state in lists)
    let spanishBox = VocabularyBox(
        name: "Spanish",
        targetLanguageCode: "es",
        primaryLanguageCode: "en",
        createdAt: now.addingTimeInterval(-200)
    )
    context.insert(spanishBox)

    do {
        try context.save()
    } catch {
        fatalError("PreviewSampleData: seed save failed – \(error)")
    }
}

// MARK: - Preview modifiers (reusable trait)

/// Applies the shared seeded in-memory container so the view sees 3 boxes
/// (French, German, Spanish) with correct relationships.
struct WithSampleDataModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .modelContainer(sharedPreviewContainerWithData)
    }
}

/// Applies the shared empty in-memory container for "Empty State" UI previews.
struct WithEmptyPreviewDataModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .modelContainer(sharedPreviewContainerEmpty)
    }
}

extension View {
    /// Use in `#Preview` to show views with 3 seeded boxes (French, German, Spanish).
    /// Container is cached; add more data in `seedSampleData(into:)` in PreviewSampleData.swift.
    func withSampleData() -> some View {
        modifier(WithSampleDataModifier())
    }

    /// Use in `#Preview` to test empty state (no boxes).
    func withEmptyPreviewData() -> some View {
        modifier(WithEmptyPreviewDataModifier())
    }
}

#endif
