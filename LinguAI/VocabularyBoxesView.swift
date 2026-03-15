//
//  VocabularyBoxesView.swift
//  LinguAI
//

import SwiftUI
import SwiftData
import Translation

// MARK: - Shared modal aesthetic & LinguAI branding
private enum ModalStyle {
    static let cornerRadius: CGFloat = 32
    static let edgePadding: CGFloat = 20
    /// LinguAI Green – hex #2EC470
    static var linguAIGreen: Color {
        Color(red: 46/255, green: 196/255, blue: 112/255)
    }
    /// Disabled primary button opacity – keeps label readable on green background (Add / Save)
    static let disabledButtonOpacity: Double = 0.65
    static let emptyCardShadowOpacity: Double = 0.1
    static let emptyCardShadowRadius: CGFloat = 20
    static let fabShadowRadius: CGFloat = 12
    static let fabShadowY: CGFloat = 8
    /// Sheet height for New/Edit box – extended so Save button sits higher with minimal gap below.
    static let newBoxSheetHeight: CGFloat = 340
}

// MARK: - Add Word sheet translation (timeout & user-facing messages)
private enum AddWordSheet {
    /// Shown when translation times out (e.g. after 3 seconds with no result).
    static let translationUnavailableMessage = "Translation currently unavailable"
    static let translationFailedMessage = "Couldn't translate this word."
    struct TranslationTimeout: Error {}
}

// MARK: - Split-pill floating bar (reusable)
/// Vertical divider used between segments in a split-pill FAB. Height ~40–50% of capsule content.
private struct SplitPillDivider: View {
    private static let height: CGFloat = 24
    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 1, height: Self.height)
    }
}

/// Reusable floating action bar in a single capsule. Use for one or multiple segments; insert `SplitPillDivider()` between segments. Pill width is intrinsic (content + padding); centered at bottom.
private struct SplitPillFloatingBar<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var bottomPadding: CGFloat = 20

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            HStack {
                Spacer(minLength: 0)
                content()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(.white.opacity(0.5), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.15), radius: ModalStyle.fabShadowRadius, x: 0, y: ModalStyle.fabShadowY)
                Spacer(minLength: 0)
            }
            .padding(.bottom, bottomPadding)
        }
    }
}

private extension Font {
    static let linguAIRounded = Font.system(.body, design: .rounded)
}

// MARK: - Box language support (for Language Direction + Smart Translate)
private enum BoxLanguage {
    /// Language codes we offer in the New Box sheet. Subset that works well with Translation + vocabulary.
    static let supportedCodes: [String] = [
        "de", "en", "es", "fr", "it", "pt", "nl", "pl", "ru", "tr", "ja", "ko",
        "zh-Hans", "zh-Hant", "ar", "hi", "th", "vi", "id", "sv", "da", "no", "fi", "hr"
    ]

    static func displayName(for code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? Locale.current.localizedString(forIdentifier: code) ?? code
    }

    /// Emoji flag for a language code (uses main region when ambiguous, e.g. de → DE).
    static func flag(for code: String) -> String {
        let region = Self.regionCode(for: code)
        let scalars = region.utf16.map { Unicode.Scalar(0x1F1E6 - 65 + Int($0))! }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func regionCode(for languageCode: String) -> String {
        let map: [String: String] = [
            "de": "DE", "en": "US", "es": "ES", "fr": "FR", "it": "IT", "pt": "PT",
            "nl": "NL", "pl": "PL", "ru": "RU", "tr": "TR", "ja": "JP", "ko": "KR",
            "zh-Hans": "CN", "zh-Hant": "TW", "ar": "SA", "hi": "IN", "th": "TH",
            "vi": "VN", "id": "ID", "sv": "SE", "da": "DK", "no": "NO", "fi": "FI", "hr": "HR"
        ]
        return map[languageCode] ?? languageCode.prefix(2).uppercased().description
    }
}

/// Target languages for the New Box sheet – text-only display.
private enum NewBoxTargetLanguages {
    static let options: [(name: String, code: String)] = [
        ("German", "de"),
        ("Italian", "it"),
        ("Spanish", "es"),
        ("Dutch", "nl"),
        ("French", "fr"),
        ("Croatian", "hr")
    ]
    static let noSelectionCode = ""
}

struct VocabularyBoxesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VocabularyBox.name) private var boxes: [VocabularyBox]

    @State private var isPresentingBoxEditor = false
    @State private var newBoxName: String = ""
    @State private var nameError: String?

    @State private var editingBox: VocabularyBox?

    @State private var pendingDeleteOffsets: IndexSet?
    @State private var isShowingDeleteConfirmation = false

    private let nameCharacterLimit = 24
    private static let suggestionPool = [
        "Greetings", "Verbs", "Routine", "Travel", "Business",
        "Food", "Social", "Health", "Shopping", "Emergency",
        "Emotions", "Time", "Home", "Family", "Nature",
        "Slang", "Tech", "Opinion", "Questions", "Connectors"
    ]
    @State private var currentSuggestion = "Greetings"
    @FocusState private var isNewBoxNameFocused: Bool
    @State private var isShowingHowTo = false
    #if DEBUG
    @State private var howToSeedMessage: String? = nil
    @State private var showHowToSeedAlert = false
    #endif
    @State private var newBoxSheetDetent: PresentationDetent = .height(ModalStyle.newBoxSheetHeight)
    @State private var newBoxTargetLanguageCode: String = NewBoxTargetLanguages.noSelectionCode
    @State private var isShowingAISuggestSheet = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            if boxes.isEmpty {
                emptyStateCard
            } else {
                List {
                    ForEach(boxes, id: \.persistentModelID) { box in
                        NavigationLink {
                            VocabularyBoxDetailView(box: box)
                        } label: {
                            boxRow(for: box)
                        }
                        .contextMenu {
                            Button("Rename") {
                                startRenaming(box)
                            }
                        }
                    }
                    .onDelete(perform: deleteBoxes)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }

            floatingActionBar
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Vocabulary boxes")
                    .font(.system(.headline, design: .rounded).weight(.bold))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingHowTo = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.body.weight(.medium))
                        .foregroundStyle(ModalStyle.linguAIGreen)
                }
            }
        }
        .sheet(isPresented: $isPresentingBoxEditor) {
            newBoxSheet
                .presentationCornerRadius(ModalStyle.cornerRadius)
                .presentationDetents([.height(ModalStyle.newBoxSheetHeight), .large], selection: $newBoxSheetDetent)
                .presentationDragIndicator(.visible)
        }
        .onChange(of: isPresentingBoxEditor) { _, isPresented in
            if !isPresented { newBoxSheetDetent = .height(ModalStyle.newBoxSheetHeight) }
        }
        .sheet(isPresented: $isShowingHowTo) {
            howToSheet
        }
        .sheet(isPresented: $isShowingAISuggestSheet) {
            AISuggestSheetContent()
                .presentationCornerRadius(ModalStyle.cornerRadius)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert("Delete box?", isPresented: $isShowingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let offsets = pendingDeleteOffsets {
                    for index in offsets.sorted(by: >) {
                        modelContext.delete(boxes[index])
                    }
                }
                pendingDeleteOffsets = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteOffsets = nil
            }
        } message: {
            Text("Are you sure you want to delete this box?")
        }
        .onAppear { }
    }

    private var floatingActionBar: some View {
        SplitPillFloatingBar {
            HStack(spacing: 12) {
                Button {
                    startAddingBox()
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(ModalStyle.linguAIGreen)
                        .labelStyle(.titleAndIcon)
                }
                .frame(minHeight: 44)

                SplitPillDivider()

                Button {
                    isShowingAISuggestSheet = true
                } label: {
                    Label("AI Suggest", systemImage: "sparkles")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(ModalStyle.linguAIGreen)
                        .labelStyle(.titleAndIcon)
                }
                .frame(minHeight: 44)
            }
        }
    }

    private var howToSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    howToStep(
                        number: 1,
                        title: "Create a box",
                        body: "Tap the **Add** button at the bottom to create a new vocabulary box. Give it a name (e.g. Greetings, Travel)."
                    )
                    howToStep(
                        number: 2,
                        title: "Add words",
                        body: "Open a box and tap the **+** button to add words. Enter the word in your target language and the translation."
                    )
                    howToStep(
                        number: 3,
                        title: "Study",
                        body: "Use your boxes to review and practise your vocabulary. Swipe to delete or use the context menu to rename a box."
                    )

                    #if DEBUG
                    developerToolsSection
                    #endif
                }
                .padding(ModalStyle.edgePadding)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("How to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isShowingHowTo = false
                    }
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(ModalStyle.linguAIGreen)
                }
            }
            #if DEBUG
            .alert("Demo Data", isPresented: $showHowToSeedAlert) {
                Button("OK", role: .cancel) { howToSeedMessage = nil }
            } message: {
                if let howToSeedMessage {
                    Text(howToSeedMessage)
                }
            }
            #endif
        }
    }

    #if DEBUG
    private var developerToolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Developer Tools")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 10) {
                Button {
                    guard let container = DebugAppContainer.container else {
                        howToSeedMessage = "Not available"
                        showHowToSeedAlert = true
                        return
                    }
                    let seeded = DataSeeding.seedDemoDataIfPossible(container: container)
                    howToSeedMessage = seeded
                        ? "Done. Grundlagen demo box created. Dismiss and open the list to see it."
                        : "Database already has content. Use \"Reset and Seed Demo Data\" to replace with demo content."
                    showHowToSeedAlert = true
                } label: {
                    Label("Seed Demo Data", systemImage: "leaf.circle")
                        .font(.system(.body, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(ModalStyle.linguAIGreen)
                }
                .buttonStyle(.bordered)
                Button {
                    guard let container = DebugAppContainer.container else {
                        howToSeedMessage = "Not available"
                        showHowToSeedAlert = true
                        return
                    }
                    let ok = DataSeeding.resetAndReseedIfPossible(container: container)
                    howToSeedMessage = ok
                        ? "Done. All data cleared and Grundlagen seeded. Dismiss to see changes."
                        : "Failed"
                    showHowToSeedAlert = true
                } label: {
                    Label("Reset and Seed Demo Data", systemImage: "arrow.counterclockwise.circle")
                        .font(.system(.body, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(ModalStyle.linguAIGreen)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.top, 8)
    }
    #endif

    private func howToStep(number: Int, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(ModalStyle.linguAIGreen, in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                Text(LocalizedStringKey(body))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var emptyStateCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 56))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(ModalStyle.linguAIGreen)

            Text("No boxes yet")
                .font(.system(.headline, design: .rounded))

            Text("Tap the Add button below to create your first vocabulary box.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(ModalStyle.emptyCardShadowOpacity), radius: ModalStyle.emptyCardShadowRadius, x: 0, y: 4)
        .padding(.horizontal, 20)
    }

    private var newBoxSheet: some View {
        let isEditing = editingBox != nil
        let nameEmpty = newBoxName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let noLanguageSelected = newBoxTargetLanguageCode.isEmpty
        let isSaveDisabled = nameEmpty || noLanguageSelected
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Box name
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Box name")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("e.g. \(currentSuggestion)", text: $newBoxName)
                            .onChange(of: newBoxName) { _, newValue in
                                if newValue.count > nameCharacterLimit {
                                    newBoxName = String(newValue.prefix(nameCharacterLimit))
                                }
                            }
                            .textFieldStyle(.plain)
                            .font(.system(.body, design: .rounded))
                            .padding(12)
                            .background(Color(.systemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        isNewBoxNameFocused ? ModalStyle.linguAIGreen : Color.primary.opacity(0.15),
                                        lineWidth: 1
                                    )
                            )
                            .focused($isNewBoxNameFocused)
                        Text("\(newBoxName.count)/\(nameCharacterLimit) characters")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    if let nameError {
                        Text(nameError)
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(.red)
                            .padding(.top, 4)
                    }

                    // Target language – styled to match Box name field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Target language")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 10)

                        Picker(selection: $newBoxTargetLanguageCode) {
                            Text("Select language")
                                .font(.system(.body, design: .rounded))
                                .tag(NewBoxTargetLanguages.noSelectionCode)
                            ForEach(NewBoxTargetLanguages.options, id: \.code) { option in
                                Text(option.name)
                                    .font(.system(.body, design: .rounded))
                                    .tag(option.code)
                            }
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.menu)
                        .tint(ModalStyle.linguAIGreen)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    noLanguageSelected ? Color.primary.opacity(0.15) : ModalStyle.linguAIGreen,
                                    lineWidth: 1
                                )
                        )
                    }

                    Spacer(minLength: 8)

                    // Save button – full width (matches input fields), rounded corners, SF Pro Rounded
                    Button {
                        saveBox()
                    } label: {
                        Text("Save")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(ModalStyle.linguAIGreen)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
                    .disabled(isSaveDisabled)
                    .opacity(isSaveDisabled ? ModalStyle.disabledButtonOpacity : 1)
                }
                .padding(ModalStyle.edgePadding)
            }
            .scrollDismissesKeyboard(.interactively)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(isEditing ? "Edit box" : "New box")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismissAddBox()
                    }
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(ModalStyle.linguAIGreen)
                }
            }
        }
    }

    private func boxRow(for box: VocabularyBox) -> some View {
        HStack(alignment: .center, spacing: 16) {
            progressCircle(for: box.progressValue)

            VStack(alignment: .leading, spacing: 4) {
                Text(box.name)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .lineLimit(1)
                Text(BoxLanguage.displayName(for: box.targetLanguageCode))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(box.wordCount) words")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    private func progressCircle(for progress: Double) -> some View {
        let clamped = max(0, min(progress, 1))
        return ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 4)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    progressColor(for: clamped),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.45, dampingFraction: 0.8), value: clamped)
            Text("\(Int(round(clamped * 100)))%")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(width: 34, height: 34)
        .clipShape(Circle())
    }

    private func progressColor(for progress: Double) -> Color {
        let startHue: Double = 0.14
        let endHue: Double = 0.33
        let hue = startHue + (endHue - startHue) * progress
        return Color(hue: hue, saturation: 0.9, brightness: 0.95)
    }

    private func startAddingBox() {
        editingBox = nil
        newBoxName = ""
        nameError = nil
        currentSuggestion = Self.suggestionPool.randomElement() ?? "Greetings"
        newBoxTargetLanguageCode = NewBoxTargetLanguages.noSelectionCode
        isPresentingBoxEditor = true
    }

    private func startRenaming(_ box: VocabularyBox) {
        editingBox = box
        newBoxName = box.name
        let code = box.targetLanguageCode
        newBoxTargetLanguageCode = NewBoxTargetLanguages.options.contains(where: { $0.code == code }) ? code : NewBoxTargetLanguages.noSelectionCode
        nameError = nil
        isPresentingBoxEditor = true
    }

    private func saveBox() {
        let trimmed = newBoxName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !newBoxTargetLanguageCode.isEmpty else {
            nameError = "Please select a target language."
            return
        }

        guard !Validation.isDuplicateBoxName(trimmed, existingBoxes: boxes, editingBox: editingBox) else {
            nameError = "A box with this name already exists."
            return
        }

        if let editingBox {
            editingBox.name = trimmed
            editingBox.primaryLanguageCode = "en"
            editingBox.targetLanguageCode = newBoxTargetLanguageCode
        } else {
            let newBox = VocabularyBox(
                name: trimmed,
                targetLanguageCode: newBoxTargetLanguageCode,
                primaryLanguageCode: "en"
            )
            modelContext.insert(newBox)
        }
        do {
            try modelContext.save()
            // Defer dismiss to next run loop so SwiftData finishes and @Query updates before the list re-renders (avoids EXC_BREAKPOINT in SwiftData when adding a box).
            DispatchQueue.main.async {
                dismissAddBox()
            }
        } catch {
            nameError = "Could not save. Please try again."
        }
    }

    private func deleteBoxes(at offsets: IndexSet) {
        pendingDeleteOffsets = offsets
        isShowingDeleteConfirmation = true
    }

    private func dismissAddBox() {
        isNewBoxNameFocused = false
        newBoxName = ""
        nameError = nil
        editingBox = nil
        newBoxTargetLanguageCode = NewBoxTargetLanguages.noSelectionCode
        withAnimation(.easeOut(duration: 0.25)) {
            isPresentingBoxEditor = false
        }
    }
}

// MARK: - AI Suggest overlay (prompt entry sheet)

private enum AISuggestUIState: Equatable {
    case idle
    case thinking
    case success
    case retryableFailure(message: String)

    var submitButtonTitle: String {
        if case .retryableFailure = self { return "Try again" }
        return "Generate suggestions"
    }
}

private struct AISuggestSheetContent: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VocabularyBox.name) private var boxes: [VocabularyBox]

    @State private var promptText = ""
    @State private var selectedTargetLanguageCode: String = NewBoxTargetLanguages.options.first?.code ?? "de"
    @State private var uiState: AISuggestUIState = .idle
    /// Idempotency: reuse same requestId when retrying same payload; new requestId when payload changes.
    @State private var lastRequestId: String?
    @State private var lastPayloadSignature: String?
    @FocusState private var isPromptFocused: Bool

    private var trimmedPrompt: String {
        promptText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSubmitDisabled: Bool {
        trimmedPrompt.isEmpty || uiState == .thinking
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch uiState {
                case .idle, .retryableFailure:
                    promptEntryContent
                case .thinking:
                    thinkingContent
                case .success:
                    successContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("AI Suggest")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(ModalStyle.linguAIGreen)
                }
            }
        }
    }

    // MARK: - Prompt entry (idle / retry)

    private var promptEntryContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(.title3, design: .rounded).weight(.medium))
                            .foregroundStyle(ModalStyle.linguAIGreen)
                        Text("Suggest vocabulary")
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundStyle(.primary)
                    }
                    Text("Describe what you want to learn. I’ll suggest words and phrases for a new box.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 20)

                if case .retryableFailure(let message) = uiState {
                    retryBanner(message: message)
                        .padding(.bottom, 16)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("What do you need?")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                    promptInputField
                }

                targetLanguageSection
                    .padding(.top, 20)
                    .padding(.bottom, 40)
            }
            .padding(ModalStyle.edgePadding)
        }
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            primarySubmitButton
        }
    }

    private func retryBanner(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.body)
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Target language chip row: label + horizontal scroll of pills. Uses fixed height and clear styling so chips are never clipped and remain readable in light/dark mode.
    private var targetLanguageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Target language")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(NewBoxTargetLanguages.options, id: \.code) { option in
                        targetLanguageChip(
                            name: option.name,
                            code: option.code,
                            isSelected: selectedTargetLanguageCode == option.code
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: 52)
        }
    }

    private func targetLanguageChip(name: String, code: String, isSelected: Bool) -> some View {
        let isGerman = code == "de"
        return Button {
            if isGerman { selectedTargetLanguageCode = code }
        } label: {
            Text(name)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(
                    isSelected
                        ? Color.white
                        : (isGerman ? Color.primary : Color.secondary)
                )
                .padding(.horizontal, 18)
                .frame(height: 44)
                .background(
                    Capsule()
                        .fill(
                            isSelected
                                ? ModalStyle.linguAIGreen
                                : Color(.tertiarySystemFill)
                        )
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? Color.clear : Color(.separator),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(!isGerman)
    }

    private var primarySubmitButton: some View {
        Button {
            submitPrompt()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                Text(uiState.submitButtonTitle)
                    .font(.system(.body, design: .rounded).weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isSubmitDisabled ? Color(.tertiarySystemFill) : ModalStyle.linguAIGreen)
            .foregroundStyle(isSubmitDisabled ? Color.secondary : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 50)
        .disabled(isSubmitDisabled)
        .padding(.horizontal, ModalStyle.edgePadding)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .background(Color(.systemBackground))
        .overlay(alignment: .top) {
            Divider()
        }
    }

    // MARK: - Thinking (loading)

    private var thinkingContent: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            thinkingIndicator
            Text("Thinking")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(.primary)
            Text("Creating your vocabulary box…")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var thinkingIndicator: some View {
        TimelineView(.animation) { context in
            let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360
            ZStack {
                Circle()
                    .stroke(ModalStyle.linguAIGreen.opacity(0.25), lineWidth: 4)
                    .frame(width: 56, height: 56)
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(ModalStyle.linguAIGreen, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))
                    .rotationEffect(.degrees(angle))
            }
        }
    }

    // MARK: - Success

    private var successContent: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(ModalStyle.linguAIGreen)
            Text("Everything is ready")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(.primary)
            Text("Your box is ready. Close this sheet to see it in your list.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer(minLength: 0)
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(ModalStyle.linguAIGreen)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, ModalStyle.edgePadding)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var promptInputField: some View {
        TextField("e.g. A1 restaurant words in German, doctor visit phrases, business Spanish…", text: $promptText, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(.body, design: .rounded))
            .lineLimit(4...8)
            .padding(12)
            .frame(minHeight: 120, alignment: .topLeading)
            .background(Color(.secondarySystemGroupedBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isPromptFocused ? ModalStyle.linguAIGreen : Color.primary.opacity(0.12),
                        lineWidth: isPromptFocused ? 1.5 : 1
                    )
            )
            .focused($isPromptFocused)
    }

    private func submitPrompt() {
        let prompt = trimmedPrompt
        guard !prompt.isEmpty, uiState != .thinking else { return }

        uiState = .thinking
        let request = buildRequest(prompt: prompt)

        Task {
            let result: Result<GenerateBoxesResponse, Error>
            do {
                let response = try await callGenerateBoxes(request: request)
                result = .success(response)
            } catch {
                result = .failure(error)
            }

            await MainActor.run {
                handleResponse(result, prompt: prompt)
            }
        }
    }

    private func buildRequest(prompt: String) -> GenerateBoxesRequest {
        let existingBoxes: [ExistingBoxRequest] = boxes.map { box in
            ExistingBoxRequest(
                boxId: box.persistentModelID.hashValue.description,
                boxName: box.name,
                completionPercent: box.progressValue * 100,
                words: box.words.map { w in
                    WordInBoxRequest(default: w.primaryText, target: w.targetText)
                }
            )
        }
        let payloadSignature = payloadSignatureForIdempotency(prompt: prompt, targetLanguage: selectedTargetLanguageCode, boxes: boxes)
        let requestId: String
        if payloadSignature == lastPayloadSignature, let id = lastRequestId {
            requestId = id
        } else {
            requestId = UUID().uuidString
            lastRequestId = requestId
            lastPayloadSignature = payloadSignature
        }
        return GenerateBoxesRequest(
            requestId: requestId,
            customerId: GenerateBoxesAPI.customerId,
            prompt: prompt,
            defaultLanguage: "en",
            targetLanguage: selectedTargetLanguageCode,
            existingBoxes: existingBoxes
        )
    }

    /// Deterministic fingerprint for (prompt, targetLanguage, existingBoxes) so we reuse requestId for exact retries.
    private func payloadSignatureForIdempotency(prompt: String, targetLanguage: String, boxes: [VocabularyBox]) -> String {
        let boxPart = boxes
            .sorted { $0.persistentModelID.hashValue < $1.persistentModelID.hashValue }
            .map { "\($0.persistentModelID.hashValue)|\($0.name)|\($0.words.count)" }
            .joined(separator: "|")
        return "\(prompt)|\(targetLanguage)|\(boxes.count)|\(boxPart)"
    }

    private func handleResponse(_ result: Result<GenerateBoxesResponse, Error>, prompt: String) {
        switch result {
        case .success(let response):
            if response.status == GenerateBoxesStatus.generatedPlaceholder, !response.boxes.isEmpty {
                createBoxesFromResponse(response)
                uiState = .success
            } else if response.status == GenerateBoxesStatus.generatedPlaceholder, response.boxes.isEmpty {
                uiState = .retryableFailure(message: response.userMessage ?? "No vocabulary was generated. Try a different prompt.")
            } else if response.status == GenerateBoxesStatus.irrelevantRequest {
                uiState = .retryableFailure(message: response.userMessage ?? "That doesn’t seem to be about vocabulary. Try describing words or phrases you want to learn.")
            } else if response.status == GenerateBoxesStatus.insufficientConfidence {
                uiState = .retryableFailure(message: response.userMessage ?? "I couldn’t generate a good list. Try rephrasing your prompt.")
            } else {
                uiState = .retryableFailure(message: response.userMessage ?? "Something went wrong. Please try again.")
            }
        case .failure(let error):
            let message: String
            if let serviceError = error as? GenerateBoxesServiceError {
                switch serviceError {
                case .idempotencyConflict:
                    lastRequestId = nil
                    lastPayloadSignature = nil
                    message = "This request was already used with different options. Please start a new generation."
                case .networkError:
                    message = "Connection failed. Check your network and try again."
                case .httpError(let code):
                    message = code == 0 ? "Request failed." : "Server error. Please try again."
                case .decodingError:
                    message = "Invalid response. Please try again."
                case .invalidURL:
                    message = "Invalid configuration. Please try again."
                }
            } else {
                message = "Something went wrong. Please try again."
            }
            uiState = .retryableFailure(message: message)
        }
    }

    private func createBoxesFromResponse(_ response: GenerateBoxesResponse) {
        let defaultLang = response.defaultLanguage
        let targetLang = response.targetLanguage
        for genBox in response.boxes {
            let newBox = VocabularyBox(
                name: genBox.boxName,
                targetLanguageCode: targetLang,
                primaryLanguageCode: defaultLang
            )
            modelContext.insert(newBox)
            for pair in genBox.words {
                let word = BoxWord(
                    primaryText: pair.default,
                    targetText: pair.target,
                    box: newBox
                )
                modelContext.insert(word)
            }
        }
        try? modelContext.save()
    }
}

struct VocabularyBoxDetailView: View {
    let box: VocabularyBox
    @Environment(\.modelContext) private var modelContext

    @State private var isShowingAddWord = false
    @State private var germanInput = ""
    @State private var englishInput = ""
    @State private var addWordError: String?

    @State private var isShowingEditWord = false
    @State private var editingWord: BoxWord?
    @State private var editGermanInput = ""
    @State private var editEnglishInput = ""
    @State private var editWordError: String?

    @State private var wordToDelete: BoxWord?
    @State private var isShowingDeleteWordConfirmation = false
    @FocusState private var addWordFocusedField: Int?
    @FocusState private var editWordFocusedField: Int?
    @State private var isTranslating = false
    @State private var translationConfiguration: TranslationSession.Configuration?
    /// When set, runTranslation will translate this text and fill the target field. fillTargetField: true = result → englishInput, false = result → germanInput.
    @State private var translationIntent: (text: String, fillTargetField: Bool)?
    @State private var isShowingStudy = false
    @State private var wordSheetDetent: PresentationDetent = .medium

    private var primaryLanguageName: String { BoxLanguage.displayName(for: box.primaryLanguageCode) }
    private var targetLanguageName: String { BoxLanguage.displayName(for: box.targetLanguageCode) }

    private var tableRows: [ModernDataTableRow] {
        box.words.sorted { $0.createdAt > $1.createdAt }.map {
            ModernDataTableRow(id: $0.uuid, column1: $0.targetText, column2: $0.primaryText)
        }
    }

    var body: some View {
        ZStack {
            Group {
                if box.words.isEmpty {
                    emptyBoxStateView
                } else {
                    ModernDataTableView(
                        header1: targetLanguageName,
                        header2: primaryLanguageName,
                        rows: tableRows,
                        onEdit: { row in
                            editingWord = box.words.first { $0.uuid == row.id }
                            editEnglishInput = row.column1
                            editGermanInput = row.column2
                            editWordError = nil
                            isShowingEditWord = true
                        },
                        onDelete: { row in
                            wordToDelete = box.words.first { $0.uuid == row.id }
                            isShowingDeleteWordConfirmation = true
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))

            detailFloatingActionBar
        }
        .navigationTitle(box.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $isShowingStudy) {
            StudyView(box: box)
        }
        .sheet(isPresented: $isShowingAddWord) {
            addWordSheet
                .presentationCornerRadius(ModalStyle.cornerRadius)
        }
        .sheet(isPresented: $isShowingEditWord) {
            editWordSheet
                .presentationCornerRadius(ModalStyle.cornerRadius)
        }
        .onChange(of: isShowingAddWord) { _, show in
            if show { wordSheetDetent = .medium }
            else { isTranslating = false; translationIntent = nil }
        }
        .onChange(of: isShowingEditWord) { _, show in if show { wordSheetDetent = .medium } }
        .alert("Delete word?", isPresented: $isShowingDeleteWordConfirmation) {
            Button("Delete", role: .destructive) {
                if let word = wordToDelete {
                    modelContext.delete(word)
                    try? modelContext.save()
                }
                wordToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                wordToDelete = nil
            }
        } message: {
            Text("This word will be removed from the table. This cannot be undone.")
        }
    }

    private var emptyBoxStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 56))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(ModalStyle.linguAIGreen)

            Text("No words added yet.")
                .font(.system(.headline, design: .rounded))

            Text("Tap the + button to start building your vocabulary.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(ModalStyle.emptyCardShadowOpacity), radius: ModalStyle.emptyCardShadowRadius, x: 0, y: 4)
        .padding(.horizontal, 20)
    }

    private var detailFloatingActionBar: some View {
        SplitPillFloatingBar {
            HStack(spacing: 12) {
                Button {
                    isShowingStudy = true
                } label: {
                    Label("Study", systemImage: "play.fill")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(ModalStyle.linguAIGreen)
                        .labelStyle(.titleAndIcon)
                }
                .frame(minHeight: 44)

                SplitPillDivider()

                Button {
                    addWordError = nil
                    germanInput = ""
                    englishInput = ""
                    isTranslating = false
                    translationIntent = nil
                    isShowingAddWord = true
                } label: {
                    Label("Add word", systemImage: "plus")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(ModalStyle.linguAIGreen)
                        .labelStyle(.titleAndIcon)
                }
                .frame(minHeight: 44)
            }
        }
    }

    private var addWordSheet: some View {
        NavigationStack {
            addWordSheetBody
                .translationTask(translationConfiguration) { session in
                    await runTranslation(using: session)
                }
        }
    }

    private var addWordSheetBody: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Type in either field to translate into the other.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 14)

                    // Target language word field (e.g. German word)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(targetLanguageName) word")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)
                        addWordTextField(
                            text: $englishInput,
                            placeholder: "e.g. \(targetLanguageName)",
                            isFocused: addWordFocusedField == 0
                        )
                        .focused($addWordFocusedField, equals: 0)
                    }
                    .padding(.bottom, 12)

                    // Primary language word field (e.g. English word)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(primaryLanguageName) word")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)
                        addWordTextField(
                            text: $germanInput,
                            placeholder: "e.g. \(primaryLanguageName)",
                            isFocused: addWordFocusedField == 1
                        )
                        .focused($addWordFocusedField, equals: 1)
                    }

                    // Single contextual translate action: only when exactly one field has text
                    if let translateLabel = addWordTranslateActionLabel {
                        HStack(spacing: 10) {
                            if isTranslating {
                                ProgressView()
                                    .scaleEffect(0.9)
                                    .tint(ModalStyle.linguAIGreen)
                                Text("Translating…")
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(.secondary)
                            } else {
                                Button {
                                    triggerTranslation()
                                } label: {
                                    Label(translateLabel, systemImage: "globe")
                                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                                }
                                .foregroundStyle(ModalStyle.linguAIGreen)
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .padding(.top, 4)
                    }

                    if let addWordError {
                        Text(addWordError)
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(.red)
                            .padding(.top, 8)
                    }
                }
                .padding(ModalStyle.edgePadding)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: englishInput) { _, newValue in
                // If one field becomes empty, clear the other so both sides stay in sync (no feedback loop: clearing the other doesn’t refill this one).
                if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { germanInput = "" }
                clearTranslationErrorIfNeeded()
            }
            .onChange(of: germanInput) { _, newValue in
                if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { englishInput = "" }
                clearTranslationErrorIfNeeded()
            }

            // Add button pinned to bottom of sheet
            Button(action: addWord) {
                Text("Add")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(ModalStyle.linguAIGreen)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(minHeight: 50)
            .disabled(germanInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || englishInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity((germanInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || englishInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                ? ModalStyle.disabledButtonOpacity : 1)
            .padding(.horizontal, ModalStyle.edgePadding)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .background(Color(.systemBackground))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Add word")
                    .font(.system(.headline, design: .rounded).weight(.bold))
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { isShowingAddWord = false }
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(ModalStyle.linguAIGreen)
            }
        }
        .presentationDetents([.medium, .large], selection: $wordSheetDetent)
        .presentationDragIndicator(.visible)
    }

    /// Plain text field for Add Word sheet (no translate button inside).
    private func addWordTextField(
        text: Binding<String>,
        placeholder: String,
        isFocused: Bool
    ) -> some View {
        TextField(placeholder, text: text)
            .textInputAutocapitalization(.never)
            .textFieldStyle(.plain)
            .font(.system(.body, design: .rounded))
            .padding(12)
            .background(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isFocused ? ModalStyle.linguAIGreen : Color.primary.opacity(0.15),
                        lineWidth: 1
                    )
            )
    }

    /// Label for the single translate action, or nil when translate should be hidden (both empty or both filled).
    private var addWordTranslateActionLabel: String? {
        let targetTrimmed = englishInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let primaryTrimmed = germanInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let onlyTarget = !targetTrimmed.isEmpty && primaryTrimmed.isEmpty
        let onlyPrimary = targetTrimmed.isEmpty && !primaryTrimmed.isEmpty
        if onlyTarget {
            return "Translate to \(primaryLanguageName)"
        }
        if onlyPrimary {
            return "Translate to \(targetLanguageName)"
        }
        return nil
    }

    private func clearTranslationErrorIfNeeded() {
        guard let msg = addWordError else { return }
        if msg == AddWordSheet.translationUnavailableMessage
            || msg == AddWordSheet.translationFailedMessage
        {
            addWordError = nil
        }
    }

    private func triggerTranslation() {
        let targetTrimmed = englishInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let primaryTrimmed = germanInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let onlyTarget = !targetTrimmed.isEmpty && primaryTrimmed.isEmpty
        let onlyPrimary = targetTrimmed.isEmpty && !primaryTrimmed.isEmpty
        addWordError = nil
        if onlyTarget {
            translationIntent = (targetTrimmed, false)
            translationConfiguration = .init(
                source: Locale.Language(identifier: box.targetLanguageCode),
                target: Locale.Language(identifier: box.primaryLanguageCode)
            )
        } else if onlyPrimary {
            translationIntent = (primaryTrimmed, true)
            translationConfiguration = .init(
                source: Locale.Language(identifier: box.primaryLanguageCode),
                target: Locale.Language(identifier: box.targetLanguageCode)
            )
        } else {
            return
        }
        if translationConfiguration != nil {
            translationConfiguration?.invalidate()
        }
        isTranslating = true
    }

    private func runTranslation(using session: TranslationSession) async {
        guard let intent = translationIntent else { return }
        let text = intent.text
        let fillTargetField = intent.fillTargetField
        let timeoutSeconds: UInt64 = 3

        do {
            let result = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    let response = try await session.translate(text)
                    return response.targetText
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                    throw AddWordSheet.TranslationTimeout()
                }
                let first = try await group.next()!
                group.cancelAll()
                return first
            }
            await MainActor.run {
                if fillTargetField {
                    englishInput = result
                } else {
                    germanInput = result
                }
            }
        } catch is AddWordSheet.TranslationTimeout {
            await MainActor.run {
                addWordError = AddWordSheet.translationUnavailableMessage
            }
        } catch {
            await MainActor.run {
                addWordError = AddWordSheet.translationFailedMessage
            }
        }
        await MainActor.run {
            isTranslating = false
            translationIntent = nil
        }
    }

    private func addWord() {
        let primary = germanInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = englishInput.trimmingCharacters(in: .whitespacesAndNewlines)

        if primary.isEmpty || target.isEmpty {
            addWordError = "Both fields are mandatory."
            return
        }

        guard !Validation.isDuplicateWordPair(primary: primary, target: target, words: box.words) else {
            addWordError = "This word pair already exists in the box."
            return
        }

        let word = BoxWord(primaryText: primary, targetText: target, level: 1, box: box)
        modelContext.insert(word)
        try? modelContext.save()
        addWordError = nil
        germanInput = ""
        englishInput = ""
        isShowingAddWord = false
    }

    private var editWordSheet: some View {
        NavigationStack {
            floatingModalContent(
                title: "Edit word",
                primaryButtonTitle: "Save",
                primaryAction: saveEditedWord,
                closeAction: { isShowingEditWord = false },
                isPrimaryDisabled: editGermanInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || editEnglishInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                errorMessage: editWordError,
                focusedFieldIndex: $editWordFocusedField,
                sheetDetent: $wordSheetDetent,
                fields: [
                    ("\(targetLanguageName) word", "e.g. \(targetLanguageName)", $editEnglishInput),
                    ("\(primaryLanguageName) word", "e.g. \(primaryLanguageName)", $editGermanInput)
                ]
            )
        }
    }

    private func floatingModalContent(
        title: String,
        primaryButtonTitle: String,
        primaryAction: @escaping () -> Void,
        closeAction: @escaping () -> Void,
        isPrimaryDisabled: Bool,
        errorMessage: String?,
        focusedFieldIndex: FocusState<Int?>.Binding,
        sheetDetent: Binding<PresentationDetent>,
        fields: [(label: String, placeholder: String, text: Binding<String>)]
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(Array(fields.enumerated()), id: \.offset) { index, field in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(field.label)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField(field.placeholder, text: field.text)
                                .textInputAutocapitalization(.never)
                                .textFieldStyle(.plain)
                                .font(.system(.body, design: .rounded))
                                .padding(12)
                                .background(Color(.systemBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(
                                            focusedFieldIndex.wrappedValue == index
                                                ? ModalStyle.linguAIGreen
                                                : Color.primary.opacity(0.15),
                                            lineWidth: 1
                                        )
                                )
                                .focused(focusedFieldIndex, equals: index)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(.red)
                    }
                }

                Spacer(minLength: 24)

                Button(action: primaryAction) {
                    Text(primaryButtonTitle)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(ModalStyle.linguAIGreen)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .frame(minHeight: 50)
                .disabled(isPrimaryDisabled)
                .opacity(isPrimaryDisabled ? ModalStyle.disabledButtonOpacity : 1)
            }
            .padding(ModalStyle.edgePadding)
        }
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.bold))
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: closeAction)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(ModalStyle.linguAIGreen)
            }
        }
        .presentationDetents([.medium, .large], selection: sheetDetent)
        .presentationDragIndicator(.visible)
    }

    private func saveEditedWord() {
        guard let editingWord else { return }
        let primary = editGermanInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = editEnglishInput.trimmingCharacters(in: .whitespacesAndNewlines)

        if primary.isEmpty || target.isEmpty {
            editWordError = "Both fields are mandatory."
            return
        }

        editingWord.primaryText = primary
        editingWord.targetText = target
        try? modelContext.save()
        editWordError = nil
        self.editingWord = nil
        editGermanInput = ""
        editEnglishInput = ""
        isShowingEditWord = false
    }
}

// MARK: - Box Progression (Study) screen
private struct BoxFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] { [:] }
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, n in n })
    }
}

private struct BoxProgressionLevel: Identifiable {
    let id: Int
    let levelNumber: Int
    let wordCount: Int
    let progress: Double // 0...1
}

private struct StudyView: View {
    var box: VocabularyBox

    private static let cardCornerRadius: CGFloat = 30
    private static let cardShadowRadius: CGFloat = 12
    private static let cardShadowY: CGFloat = 6
    private static let cardShadowOpacity: Double = 0.1
    private static let gridSpacing: CGFloat = 16
    private static let edgePadding: CGFloat = 16
    private static let cardHeight: CGFloat = 160
    private static let progressBarHeight: CGFloat = 4
    private static let progressTrackOpacity: Double = 0.25
    private static let selectedBorderWidth: CGFloat = 2
    private static let unselectedContentOpacity: Double = 0.4
    private static let levelBadgeSize: CGFloat = 52
    private static let levelBadgeGreenOpacity: Double = 0.1

    @State private var selectedLevelIDs: Set<Int> = [1, 2, 3, 4, 5, 6]
    @State private var isShowingSettings = false
    @State private var isShowingSession = false

    @State private var levelWordCounts: [Int: Int] = [:]
    @State private var boxFrames: [Int: CGRect] = [:]
    @State private var isShowingAnimation = false
    @State private var activeMoves: [(from: Int, to: Int, count: Int, isSuccess: Bool)] = []
    @State private var popBoxID: Int? = nil
    @State private var popScale: CGFloat = 1

    private var levels: [BoxProgressionLevel] {
        (1...6).map { levelNum in
            let count = levelWordCounts[levelNum] ?? 0
            let total = max(1, box.words.count)
            let progress = Double(count) / Double(total)
            return BoxProgressionLevel(id: levelNum, levelNumber: levelNum, wordCount: count, progress: progress)
        }
    }

    private func refreshLevelCounts() {
        var counts: [Int: Int] = [:]
        for level in 1...6 {
            counts[level] = box.words.filter { $0.level == level }.count
        }
        levelWordCounts = counts
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 24)
                    VStack(spacing: Self.gridSpacing) {
                        // Row 1: Levels 1 and 2
                        HStack(spacing: Self.gridSpacing) {
                            progressionCard(levels[0])
                            progressionCard(levels[1])
                        }
                        // Row 2: Levels 3 and 4
                        HStack(spacing: Self.gridSpacing) {
                            progressionCard(levels[2])
                            progressionCard(levels[3])
                        }
                        // Row 3: Levels 5 and 6
                        HStack(spacing: Self.gridSpacing) {
                            progressionCard(levels[4])
                            progressionCard(levels[5])
                        }
                    }
                    .padding(Self.edgePadding)
                    Spacer(minLength: 24)
                }
                .frame(maxWidth: .infinity, minHeight: 500)
                .coordinateSpace(name: "boxProgression")
                .onPreferenceChange(BoxFramePreferenceKey.self) { boxFrames = $0 }
                .overlay {
                    if isShowingAnimation, !activeMoves.isEmpty {
                        flyingBadgesOverlay
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Box Progression")
            .onAppear { refreshLevelCounts() }
            .onChange(of: isShowingSession) { _, showing in if !showing { refreshLevelCounts() } }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.body.weight(.medium))
                            .foregroundStyle(ModalStyle.linguAIGreen)
                    }
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                NavigationStack {
                    SettingsView(box: box, maxWordsAvailable: totalWordsInSelectedLevels)
                }
            }
            .navigationDestination(isPresented: $isShowingSession) {
                StudySessionView(
                    box: box,
                    selectedLevelIDs: selectedLevelIDs,
                    onFinish: { isShowingSession = false },
                    onWordMoved: { from, to, isSuccess in
                        activeMoves.append((from: from, to: to, count: 1, isSuccess: isSuccess))
                        isShowingAnimation = true
                    }
                )
            }

            startFloatingButton
        }
    }

    private var totalWordsInSelectedLevels: Int {
        levels.filter { selectedLevelIDs.contains($0.id) }.map(\.wordCount).reduce(0, +)
    }

    private var startFloatingButton: some View {
        let wordCount = totalWordsInSelectedLevels
        let isDisabled = wordCount == 0
        return SplitPillFloatingBar {
            Button {
                isShowingSession = true
            } label: {
                Text("Start (\(wordCount))")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(isDisabled ? .secondary : ModalStyle.linguAIGreen)
            }
            .disabled(isDisabled)
            .frame(minHeight: 44)
        }
    }

    /// Fixed height for badge + count so Mastered and Box 1–5 cards align.
    private static let badgeCountBlockHeight: CGFloat = 88

    private func progressionCard(_ level: BoxProgressionLevel) -> some View {
        let isSelected = selectedLevelIDs.contains(level.id)
        let count = level.wordCount
        let isPopping = popBoxID == level.id
        let isMastered = level.id == LeitnerEngine.maxLevel
        return Button {
            toggleSelection(level.id)
        } label: {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    if isMastered {
                        ZStack {
                            Circle()
                                .fill(ModalStyle.linguAIGreen.opacity(Self.levelBadgeGreenOpacity))
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(ModalStyle.linguAIGreen)
                        }
                        .frame(width: Self.levelBadgeSize, height: Self.levelBadgeSize)
                    } else {
                        Text("Box \(level.levelNumber)")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(height: Self.levelBadgeSize)
                            .background(
                                Capsule()
                                    .fill(ModalStyle.linguAIGreen.opacity(Self.levelBadgeGreenOpacity))
                            )
                    }

                    Text(count == 1 ? "1 card" : "\(count) cards")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .scaleEffect(isPopping ? popScale : 1)
                }
                .frame(height: Self.badgeCountBlockHeight)
                .frame(maxWidth: .infinity)

                Spacer(minLength: 0)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: Self.progressBarHeight / 2, style: .continuous)
                            .fill(ModalStyle.linguAIGreen.opacity(Self.progressTrackOpacity))
                        RoundedRectangle(cornerRadius: Self.progressBarHeight / 2, style: .continuous)
                            .fill(ModalStyle.linguAIGreen)
                            .frame(width: max(0, geo.size.width * CGFloat(level.progress)))
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: level.progress)
                    }
                }
                .frame(height: Self.progressBarHeight)
                .clipShape(RoundedRectangle(cornerRadius: Self.progressBarHeight / 2, style: .continuous))
            }
            .opacity(isSelected ? 1 : Self.unselectedContentOpacity)
            .padding(.vertical, 20)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: Self.cardHeight)
            .background(
                RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? ModalStyle.linguAIGreen : Color.primary.opacity(0.06),
                        lineWidth: isSelected ? Self.selectedBorderWidth : 1
                    )
            )
            .shadow(
                color: .black.opacity(Self.cardShadowOpacity),
                radius: Self.cardShadowRadius,
                x: 0,
                y: Self.cardShadowY
            )
        }
        .buttonStyle(ProgressionCardButtonStyle())
        .frame(maxWidth: .infinity)
        .frame(height: Self.cardHeight)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: BoxFramePreferenceKey.self,
                    value: [level.id: geo.frame(in: .named("boxProgression"))]
                )
            }
        )
    }

    private var flyingBadgesOverlay: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(activeMoves.enumerated()), id: \.offset) { index, move in
                    if let fromRect = boxFrames[move.from], let toRect = boxFrames[move.to] {
                        FlyingBadgeView(
                            fromRect: fromRect,
                            toRect: toRect,
                            count: move.count,
                            isSuccess: move.isSuccess,
                            startDelay: Double(index) * 0.1,
                            onLand: { },
                            onBurstStart: { applyMoveAndPop(move: move) },
                            onExitComplete: { removeMove(move) }
                        )
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// Called at burst start: update counts and subtle number bump. Never let a box count go below zero.
    private func applyMoveAndPop(move: (from: Int, to: Int, count: Int, isSuccess: Bool)) {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        let fromCount = levelWordCounts[move.from, default: 0]
        let toCount = levelWordCounts[move.to, default: 0]
        let deduct = min(move.count, max(0, fromCount))
        levelWordCounts[move.from] = max(0, fromCount - deduct)
        levelWordCounts[move.to] = toCount + deduct
        popBoxID = move.to
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            popScale = 1.1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.easeOut(duration: 0.15)) {
                popScale = 1
                popBoxID = nil
            }
        }
    }

    private func removeMove(_ move: (from: Int, to: Int, count: Int, isSuccess: Bool)) {
        activeMoves.removeAll { $0.from == move.from && $0.to == move.to && $0.count == move.count }
        if activeMoves.isEmpty {
            isShowingAnimation = false
        }
    }

    private func toggleSelection(_ levelID: Int) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if selectedLevelIDs.contains(levelID) {
            selectedLevelIDs.remove(levelID)
        } else {
            selectedLevelIDs.insert(levelID)
        }
    }
}

// MARK: - Flying badge (post-session word movement)
private struct FlyingBadgeView: View {
    let fromRect: CGRect
    let toRect: CGRect
    let count: Int
    let isSuccess: Bool
    var startDelay: Double = 0
    let onLand: () -> Void
    let onBurstStart: () -> Void
    let onExitComplete: () -> Void

    private static let flyDuration: Double = 1.5
    /// Badge stays stuck at corner for this long before burst.
    private static let stickDuration: Double = 2.0
    private static let explosionDuration: Double = 0.5
    private static let particleCount: Int = 12

    /// Upper-right corner of target card, slightly overlapping the border (badge anchor).
    private static let cornerInset: CGFloat = 18

    @State private var progress: CGFloat = 0
    @State private var hasLanded = false
    @State private var hasStarted = false
    @State private var isExploding = false
    @State private var explosionProgress: CGFloat = 0
    @State private var badgeVisible = true

    private var fromCenter: CGPoint {
        CGPoint(x: fromRect.midX, y: fromRect.midY)
    }
    /// Landing spot: upper-right corner of target card.
    private var landingPosition: CGPoint {
        CGPoint(x: toRect.maxX - Self.cornerInset, y: toRect.minY + Self.cornerInset)
    }
    private var controlPoint: CGPoint {
        let midX = (fromCenter.x + landingPosition.x) / 2
        let arcY = min(fromCenter.y, landingPosition.y) - 50
        return CGPoint(x: midX, y: arcY)
    }
    private var currentPosition: CGPoint {
        let t = progress
        let x = (1 - t) * (1 - t) * fromCenter.x + 2 * (1 - t) * t * controlPoint.x + t * t * landingPosition.x
        let y = (1 - t) * (1 - t) * fromCenter.y + 2 * (1 - t) * t * controlPoint.y + t * t * landingPosition.y
        return CGPoint(x: x, y: y)
    }
    private var badgeColor: Color {
        isSuccess ? ModalStyle.linguAIGreen : Color(.systemRed)
    }

    var body: some View {
        let label = isSuccess ? "+\(count)" : "-\(count)"
        ZStack {
            if badgeVisible {
                Circle()
                    .fill(badgeColor.opacity(0.95))
                    .overlay(
                        Text(label)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    )
                    .frame(width: 36, height: 36)
                    .position(currentPosition)
                    .opacity(isExploding ? 0 : (hasStarted ? 1 : 0))
                if isExploding {
                    explosionParticles
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + startDelay) {
                hasStarted = true
                withAnimation(.easeInOut(duration: Self.flyDuration)) {
                    progress = 1
                }
            }
        }
        .onChange(of: progress) { _, newValue in
            if newValue >= 0.99, !hasLanded {
                hasLanded = true
                onLand()
                // 1. Stick: keep badge still at corner for 2.0s. Do not hide or burst yet.
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.stickDuration) {
                    // 2. Burst: trigger at this exact coordinate; simultaneously hide badge (opacity 0).
                    onBurstStart()
                    isExploding = true
                    withAnimation(.easeOut(duration: Self.explosionDuration)) {
                        explosionProgress = 1
                    }
                    // 4. Don't clear the flying view until burst has fully finished (0.5s).
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.explosionDuration) {
                        onExitComplete()
                    }
                }
            }
        }
    }

    private var explosionParticles: some View {
        let origin = landingPosition
        return ZStack {
            ForEach(0..<Self.particleCount, id: \.self) { i in
                let angle = CGFloat(i) * (360 / CGFloat(Self.particleCount)) * .pi / 180
                let radius: CGFloat = 28 * explosionProgress
                let x = origin.x + cos(angle) * radius
                let y = origin.y + sin(angle) * radius
                Circle()
                    .fill(badgeColor)
                    .frame(width: 6, height: 6)
                    .scaleEffect(0.6 + explosionProgress * 1.4)
                    .opacity(Double(1 - explosionProgress))
                    .position(x: x, y: y)
            }
        }
        .animation(.easeOut(duration: Self.explosionDuration), value: explosionProgress)
    }
}

private struct ProgressionCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Well Done overlay (scale + opacity, no confetti)
private struct WellDoneOverlayView: View {
    let totalWords: Int
    let onFinish: () -> Void
    @State private var isVisible = false

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Text("Well Done!")
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Session Complete")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)

                Text("\(totalWords) word\(totalWords == 1 ? "" : "s") studied")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary)

                Button(action: onFinish) {
                    Text("Finish")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(ModalStyle.linguAIGreen, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }
            .scaleEffect(isVisible ? 1 : 0.8)
            .opacity(isVisible ? 1 : 0)
            .animation(.easeOut(duration: 0.6), value: isVisible)
            .onAppear {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                isVisible = true
            }
        }
    }
}

// MARK: - Shake effect (Box 1 wrong answer)
private struct ShakeModifier: ViewModifier {
    let trigger: Bool
    @State private var phase: Int = -1
    private static let steps: [CGFloat] = [-8, 8, -8, 8, 0]

    func body(content: Content) -> some View {
        content
            .offset(x: phase >= 0 && phase < Self.steps.count ? Self.steps[phase] : 0)
            .animation(.easeInOut(duration: 0.05), value: phase)
            .onChange(of: trigger) { _, newValue in
                if newValue { runShake() }
            }
    }

    private func runShake() {
        for i in 0..<Self.steps.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.05) {
                phase = i
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(Self.steps.count) * 0.05) {
            phase = -1
        }
    }
}

// MARK: - Study Session (Leitner: correct → +1 level, wrong → level 1)
private struct StudySessionView: View {
    var box: VocabularyBox
    var selectedLevelIDs: Set<Int>
    var onFinish: () -> Void
    var onWordMoved: ((_ fromLevel: Int, _ toLevel: Int, _ isSuccess: Bool) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @AppStorage("studyDirection") private var studyDirection: String = ""
    @AppStorage("sessionWordCount") private var sessionWordCount: Int = 10
    @AppStorage("hapticFeedbackEnabled") private var hapticFeedbackEnabled: Bool = true

    private var isPrimaryFirst: Bool { studyDirection == "\(box.primaryLanguageCode.prefix(2).uppercased())_\(box.targetLanguageCode.prefix(2).uppercased())" }
    private var sourceLanguageLabel: String { isPrimaryFirst ? BoxLanguage.displayName(for: box.primaryLanguageCode) : BoxLanguage.displayName(for: box.targetLanguageCode) }
    private var translationLanguageLabel: String { isPrimaryFirst ? BoxLanguage.displayName(for: box.targetLanguageCode) : BoxLanguage.displayName(for: box.primaryLanguageCode) }

    /// (word, questionText, answerText) for the card; Leitner updates word.level on answer.
    @State private var sessionEntries: [(word: BoxWord, question: String, answer: String)] = []
    @State private var currentIndex: Int = 0
    @State private var isRevealed: Bool = false
    @State private var correctCount: Int = 0
    @State private var incorrectCount: Int = 0
    @State private var sessionStartTime: Date = .now
    @State private var showCompletion: Bool = false
    @State private var showExitAlert: Bool = false
    @State private var shouldShakeCard: Bool = false

    private static let progressBarHeight: CGFloat = 7
    private static let cardCornerRadius: CGFloat = 32
    private static let cardShadowRadius: CGFloat = 16
    private static let cardShadowOpacity: Double = 0.08
    private static let wrongButtonColor = Color(.systemRed).opacity(0.18)
    private static let wrongIconColor = Color(.systemRed)

    private var totalWords: Int { sessionEntries.count }
    private var completedCount: Int { correctCount + incorrectCount }
    private var progress: Double {
        guard totalWords > 0 else { return 0 }
        return Double(completedCount) / Double(totalWords)
    }
    private var totalTime: TimeInterval { Date().timeIntervalSince(sessionStartTime) }
    private var accuracyPercent: Int {
        let total = correctCount + incorrectCount
        guard total > 0 else { return 100 }
        return Int(round(Double(correctCount) / Double(total) * 100))
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress bar (6–8pt, rounded track)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: Self.progressBarHeight / 2, style: .continuous)
                            .fill(Color.primary.opacity(0.1))
                        RoundedRectangle(cornerRadius: Self.progressBarHeight / 2, style: .continuous)
                            .fill(ModalStyle.linguAIGreen)
                            .frame(width: max(0, geo.size.width * CGFloat(progress)))
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progress)
                    }
                }
                .frame(height: Self.progressBarHeight)
                .clipShape(RoundedRectangle(cornerRadius: Self.progressBarHeight / 2, style: .continuous))

                // Header: source language pill only (back is in nav bar)
                HStack {
                    Spacer()
                    Text(sourceLanguageLabel)
                        .font(.system(.caption2, design: .rounded).weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color(.systemGray5)))
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.top, 12)
                .padding(.bottom, 24)

                // Word card (center): question + answer; Leitner level updated on answer
                if !sessionEntries.isEmpty, currentIndex < sessionEntries.count {
                    let entry = sessionEntries[currentIndex]
                    let questionText = entry.question
                    let answerText = entry.answer
                    VStack(spacing: 20) {
                        VStack(spacing: 16) {
                            Text(questionText)
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)

                            if isRevealed {
                                Text(answerText)
                                    .font(.system(size: 22, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .move(edge: .top)),
                                        removal: .opacity
                                    ))
                            }
                        }
                        .padding(32)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                        .shadow(
                            color: .black.opacity(Self.cardShadowOpacity),
                            radius: Self.cardShadowRadius,
                            x: 0,
                            y: 6
                        )
                        .padding(.horizontal, 24)
                        .modifier(ShakeModifier(trigger: shouldShakeCard))
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isRevealed)
                        .id(entry.word.uuid)
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))

                        // Language Pill 2 (Target): below the card when translation revealed
                        if isRevealed {
                            Text(translationLanguageLabel)
                                .font(.system(.caption2, design: .rounded).weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color(.systemGray5)))
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity.combined(with: .move(edge: .top))
                                ))
                                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isRevealed)
                        }
                    }
                }

                Spacer(minLength: 0)

                // Bottom: Check pill or Wrong / Correct circles
                if isRevealed {
                    HStack(spacing: 32) {
                        Button {
                            recordAnswer(correct: false)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(.title2, design: .rounded).weight(.bold))
                                .foregroundStyle(Self.wrongIconColor)
                                .frame(width: 64, height: 64)
                                .background(Circle().fill(Self.wrongButtonColor))
                                .overlay(Circle().strokeBorder(Self.wrongIconColor.opacity(0.5), lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)

                        Button {
                            recordAnswer(correct: true)
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(.title2, design: .rounded).weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 64, height: 64)
                                .background(Circle().fill(ModalStyle.linguAIGreen))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 32)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.9)),
                        removal: .opacity
                    ))
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isRevealed)
                } else {
                    SplitPillFloatingBar(content: {
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                if hapticFeedbackEnabled {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                                isRevealed = true
                            }
                        } label: {
                            Text("Check")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(ModalStyle.linguAIGreen)
                        }
                        .frame(minHeight: 44)
                    }, bottomPadding: 32)
                }
            }
            .opacity(showCompletion ? 0 : 1)

            // Completion overlay
            if showCompletion {
                completionOverlay
            }
        }
        .onAppear {
            if studyDirection.isEmpty {
                let p = String(box.primaryLanguageCode.prefix(2)).uppercased()
                let t = String(box.targetLanguageCode.prefix(2)).uppercased()
                studyDirection = "\(p)_\(t)"
            }
            let filtered = box.words.filter { selectedLevelIDs.contains($0.level) }
            let now = Date()
            // Effective session size for this box only: preference clamped by available words; never persists back.
            let requestedCount = max(1, min(sessionWordCount, filtered.count))
            let selected = selectSessionWords(from: box.words, selectedLevelIDs: selectedLevelIDs, requestedCount: requestedCount, now: now)

            sessionEntries = selected.map { word in
                let q = isPrimaryFirst ? word.primaryText : word.targetText
                let a = isPrimaryFirst ? word.targetText : word.primaryText
                return (word: word, question: q, answer: a)
            }
            sessionStartTime = Date()
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(showCompletion)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showExitAlert = true
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
        .alert("End Session?", isPresented: $showExitAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Exit", role: .destructive) {
                onFinish()
            }
        } message: {
            Text("Your current progress will be lost.")
        }
    }

    private var completionOverlay: some View {
        WellDoneOverlayView(
            totalWords: totalWords,
            onFinish: onFinish
        )
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let m = Int(interval) / 60
        let s = Int(interval) % 60
        if m > 0 {
            return "\(m)m \(s)s"
        }
        return "\(s)s"
    }

    private func recordAnswer(correct: Bool) {
        if hapticFeedbackEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        if correct { correctCount += 1 } else { incorrectCount += 1 }
        if currentIndex < sessionEntries.count {
            let word = sessionEntries[currentIndex].word
            let fromLevel = word.level
            word.level = LeitnerEngine.level(afterCorrect: correct, currentLevel: word.level)
            word.lastReviewedDate = Date.now
            if correct {
                if word.level == LeitnerEngine.maxLevel {
                    word.nextReviewDate = .distantFuture
                } else {
                    word.nextReviewDate = nextReviewDate(afterCorrectAnswer: word.level, calendar: .current)
                }
            } else {
                word.nextReviewDate = Date.now
            }
            try? modelContext.save()
            if fromLevel != word.level {
                onWordMoved?(fromLevel, word.level, correct)
            } else if fromLevel == 1 && !correct {
                shouldShakeCard = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    shouldShakeCard = false
                }
            }
        }
        if currentIndex + 1 >= totalWords {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                showCompletion = true
            }
        } else {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                isRevealed = false
                currentIndex += 1
            }
        }
    }
}

private struct SettingsView: View {
    /// When set, study direction options are derived from this box's primary/target languages.
    var box: VocabularyBox? = nil
    /// When set, words per session is capped by this (e.g. total words in selected boxes). Otherwise cap at 50.
    var maxWordsAvailable: Int? = nil

    @Environment(\.dismiss) private var dismiss
    @AppStorage("studyDirection") private var studyDirection: String = ""
    @AppStorage("sessionWordCount") private var sessionWordCount: Int = 10
    @AppStorage("hapticFeedbackEnabled") private var hapticFeedbackEnabled: Bool = true

    /// Curated list for Words per session: 1, then multiples of 5 up to total, then total (e.g. 1, 5, 10, 15, 20, 24). No duplicates.
    private var wordCountOptions: [Int] {
        let total = effectiveMaxWords
        var opts: [Int] = [1]
        opts += stride(from: 5, through: total, by: 5)
        if total > 1, !opts.contains(total) {
            opts.append(total)
        }
        return opts
    }

    /// Short label for study direction (e.g. "en" → "EN", "de" → "DE", "zh" → "ZH").
    private static func shortDirectionLabel(for code: String) -> String {
        let s = code.prefix(2).uppercased()
        return String(s)
    }

    /// When box is set, the two study direction tags (primary→target and target→primary).
    private var studyDirectionTags: (primaryTarget: String, targetPrimary: String)? {
        guard let box else { return nil }
        let p = Self.shortDirectionLabel(for: box.primaryLanguageCode)
        let t = Self.shortDirectionLabel(for: box.targetLanguageCode)
        return ("\(p)_\(t)", "\(t)_\(p)")
    }

    /// Minimum 1, maximum 50 or the words available (whichever is lower). Allows picker to show actual total (e.g. 3).
    private var effectiveMaxWords: Int {
        max(1, min(50, maxWordsAvailable ?? 50))
    }

    /// Binding for the "Number of words" picker: displays a value that is always in wordCountOptions (so the picker is valid),
    /// but only writes to the persisted preference when the user explicitly picks. If the stored value (e.g. 20) is above the
    /// current box cap (e.g. 12), we display the cap (12) so the picker shows a valid option; the stored 20 is unchanged
    /// until the user selects a new value.
    private var sessionWordCountPickerBinding: Binding<Int> {
        Binding(
            get: {
                if wordCountOptions.contains(sessionWordCount) {
                    return sessionWordCount
                }
                return wordCountOptions.last ?? 10
            },
            set: { sessionWordCount = $0 }
        )
    }

    /// Binding that always exposes a valid tag for the current box so the segmented Picker shows a selection from the first frame.
    private var studyDirectionBinding: Binding<String> {
        Binding(
            get: {
                guard let tags = studyDirectionTags else { return studyDirection }
                if studyDirection == tags.primaryTarget || studyDirection == tags.targetPrimary {
                    return studyDirection
                }
                return tags.primaryTarget
            },
            set: { studyDirection = $0 }
        )
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Study Direction")
                        .font(.system(.body, design: .rounded))
                    if let box, let tags = studyDirectionTags {
                        Picker("Study Direction", selection: studyDirectionBinding) {
                            Text("\(Self.shortDirectionLabel(for: box.primaryLanguageCode)) → \(Self.shortDirectionLabel(for: box.targetLanguageCode))")
                                .font(.system(.subheadline, design: .rounded))
                                .tag(tags.primaryTarget)
                            Text("\(Self.shortDirectionLabel(for: box.targetLanguageCode)) → \(Self.shortDirectionLabel(for: box.primaryLanguageCode))")
                                .font(.system(.subheadline, design: .rounded))
                                .tag(tags.targetPrimary)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .tint(ModalStyle.linguAIGreen)
                    } else {
                        Picker("Study Direction", selection: Binding(
                            get: { studyDirection == "EN_DE" || studyDirection == "DE_EN" ? studyDirection : "EN_DE" },
                            set: { studyDirection = $0 }
                        )) {
                            Text("EN → DE")
                                .font(.system(.subheadline, design: .rounded))
                                .tag("EN_DE")
                            Text("DE → EN")
                                .font(.system(.subheadline, design: .rounded))
                                .tag("DE_EN")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .tint(ModalStyle.linguAIGreen)
                    }
                }
            } header: {
                Text("Study")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
            }

            Section {
                Picker("Number of words", selection: sessionWordCountPickerBinding) {
                    ForEach(wordCountOptions, id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                }
                .pickerStyle(.menu)
                .tint(ModalStyle.linguAIGreen)
            } header: {
                Text("Session")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
            }

            Section {
                Toggle(isOn: $hapticFeedbackEnabled) {
                    HStack(spacing: 8) {
                        Image(systemName: "iphone.radiowaves.left.and.right")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(ModalStyle.linguAIGreen)
                        Text("Haptic Feedback")
                            .font(.system(.body, design: .rounded))
                    }
                }
                .tint(ModalStyle.linguAIGreen)
            } header: {
                Text("Feedback")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Text("v0.1")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary.opacity(0.5))
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(ModalStyle.linguAIGreen)
            }
        }
        .onAppear {
            if let tags = studyDirectionTags {
                if studyDirection.isEmpty || (studyDirection != tags.primaryTarget && studyDirection != tags.targetPrimary) {
                    studyDirection = tags.primaryTarget
                }
            }
        }
    }
}

#if DEBUG
#Preview("Preview with data") {
    NavigationStack {
        VocabularyBoxesView()
            .withSampleData()
    }
}

#Preview("Preview empty") {
    NavigationStack {
        VocabularyBoxesView()
            .withEmptyPreviewData()
    }
}
#endif

