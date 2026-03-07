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

private extension Font {
    static let linguAIRounded = Font.system(.body, design: .rounded)
}

// MARK: - Box language support (for Language Direction + Smart Translate)
private enum BoxLanguage {
    /// Language codes we offer in the New Box sheet. Subset that works well with Translation + vocabulary.
    static let supportedCodes: [String] = [
        "de", "en", "es", "fr", "it", "pt", "nl", "pl", "ru", "tr", "ja", "ko",
        "zh-Hans", "zh-Hant", "ar", "hi", "th", "vi", "id", "sv", "da", "no", "fi"
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
            "vi": "VN", "id": "ID", "sv": "SE", "da": "DK", "no": "NO", "fi": "FI"
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
        ("French", "fr")
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
    @State private var newBoxSheetDetent: PresentationDetent = .height(ModalStyle.newBoxSheetHeight)
    @State private var newBoxTargetLanguageCode: String = NewBoxTargetLanguages.noSelectionCode

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            if boxes.isEmpty {
                emptyStateCard
            } else {
                List {
                    ForEach(boxes) { box in
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
    }

    private var floatingActionBar: some View {
        VStack {
            Spacer(minLength: 0)
            Button {
                startAddingBox()
            } label: {
                Label("Add", systemImage: "plus")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(ModalStyle.linguAIGreen)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(.white.opacity(0.5), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.15), radius: ModalStyle.fabShadowRadius, x: 0, y: ModalStyle.fabShadowY)
            .padding(.bottom, 20)
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
        }
    }

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
            progressCircle(for: box.progress)

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
            Text("\(Int(clamped * 100))%")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(width: 34, height: 34)
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

        let isDuplicate = boxes.contains { existing in
            existing.name.caseInsensitiveCompare(trimmed) == .orderedSame &&
            existing !== editingBox
        }
        guard !isDuplicate else {
            nameError = "A box with this name already exists."
            return
        }

        if let editingBox {
            editingBox.name = trimmed
            editingBox.primaryLanguageCode = "en"
            editingBox.targetLanguageCode = newBoxTargetLanguageCode
        } else {
            let box = VocabularyBox(
                name: trimmed,
                targetLanguageCode: newBoxTargetLanguageCode,
                primaryLanguageCode: "en"
            )
            modelContext.insert(box)
        }
        try? modelContext.save()
        dismissAddBox()
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
    @State private var textToTranslateForTask: String?
    @State private var isShowingSettings = false
    @State private var isShowingStudy = false
    @State private var wordSheetDetent: PresentationDetent = .medium

    private var primaryLanguageName: String { BoxLanguage.displayName(for: box.primaryLanguageCode) }
    private var targetLanguageName: String { BoxLanguage.displayName(for: box.targetLanguageCode) }

    private var tableRows: [ModernDataTableRow] {
        box.words.sorted { $0.createdAt > $1.createdAt }.map {
            ModernDataTableRow(id: $0.uuid, column1: $0.primaryText, column2: $0.targetText)
        }
    }

    /// Set to true to show the Smart Translate button between source and target fields in Add word sheet.
    private let showTranslateButton = false

    var body: some View {
        ZStack {
            ModernDataTableView(
                header1: primaryLanguageName,
                header2: targetLanguageName,
                rows: tableRows,
                onEdit: { row in
                    editingWord = box.words.first { $0.uuid == row.id }
                    editGermanInput = row.column1
                    editEnglishInput = row.column2
                    editWordError = nil
                    isShowingEditWord = true
                },
                onDelete: { row in
                    wordToDelete = box.words.first { $0.uuid == row.id }
                    isShowingDeleteWordConfirmation = true
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))

            detailFloatingActionBar
        }
        .navigationTitle(box.name)
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
                SettingsView(box: box, maxWordsAvailable: box.wordCount)
            }
        }
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
        .onChange(of: isShowingAddWord) { _, show in if show { wordSheetDetent = .medium } }
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

    private var detailFloatingActionBar: some View {
        VStack {
            Spacer(minLength: 0)
            HStack(spacing: 24) {
                Button {
                    isShowingStudy = true
                } label: {
                    Label("Study", systemImage: "play.fill")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(ModalStyle.linguAIGreen)
                }
                .frame(minHeight: 44)
                Button {
                    addWordError = nil
                    germanInput = ""
                    englishInput = ""
                    isShowingAddWord = true
                } label: {
                    Label("Add word", systemImage: "plus")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(ModalStyle.linguAIGreen)
                }
                .frame(minHeight: 44)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(.white.opacity(0.5), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.15), radius: ModalStyle.fabShadowRadius, x: 0, y: ModalStyle.fabShadowY)
            .padding(.bottom, 20)
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
                    // Primary language word field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(primaryLanguageName) word")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("e.g. \(primaryLanguageName)", text: $germanInput)
                            .textInputAutocapitalization(.never)
                            .textFieldStyle(.plain)
                            .font(.system(.body, design: .rounded))
                            .padding(12)
                            .background(Color(.systemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        addWordFocusedField == 0
                                            ? ModalStyle.linguAIGreen
                                            : Color.primary.opacity(0.15),
                                        lineWidth: 1
                                    )
                            )
                            .focused($addWordFocusedField, equals: 0)
                    }
                    .padding(.bottom, 12)

                    if showTranslateButton {
                        // Translate icon between fields
                        HStack {
                            Spacer(minLength: 0)
                            if isTranslating {
                                ProgressView()
                                    .scaleEffect(0.9)
                                    .tint(ModalStyle.linguAIGreen)
                            } else {
                                Button {
                                    triggerTranslation()
                                } label: {
                                    Image(systemName: "character.bubble")
                                        .font(.system(.title2, design: .rounded).weight(.medium))
                                }
                                .foregroundStyle(canTranslate ? ModalStyle.linguAIGreen : Color.primary.opacity(0.25))
                                .disabled(!canTranslate)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(height: 44)
                    }

                    // Target language word field (tight spacing below primary field)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(targetLanguageName) word")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("e.g. \(targetLanguageName)", text: $englishInput)
                            .textInputAutocapitalization(.never)
                            .textFieldStyle(.plain)
                            .font(.system(.body, design: .rounded))
                            .padding(12)
                            .background(Color(.systemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        addWordFocusedField == 1
                                            ? ModalStyle.linguAIGreen
                                            : Color.primary.opacity(0.15),
                                        lineWidth: 1
                                    )
                            )
                            .focused($addWordFocusedField, equals: 1)
                            .overlay(
                                Group {
                                    if showTranslateButton, isTranslating {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(ModalStyle.linguAIGreen.opacity(0.06))
                                    }
                                }
                            )
                    }

                    if let addWordError {
                        Text(addWordError)
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(.red)
                    }
                }
                .padding(ModalStyle.edgePadding)
            }
            .scrollDismissesKeyboard(.interactively)

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

    private var canTranslate: Bool {
        !germanInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func triggerTranslation() {
        guard canTranslate else { return }
        addWordError = nil
        let text = germanInput.trimmingCharacters(in: .whitespacesAndNewlines)
        textToTranslateForTask = text
        isTranslating = true
        if translationConfiguration != nil {
            translationConfiguration?.invalidate()
        }
        let source = Locale.Language(identifier: box.primaryLanguageCode)
        let target = Locale.Language(identifier: box.targetLanguageCode)
        translationConfiguration = .init(source: source, target: target)
    }

    private func runTranslation(using session: TranslationSession) async {
        guard let text = textToTranslateForTask else { return }
        do {
            let response = try await session.translate(text)
            await MainActor.run {
                englishInput = response.targetText
            }
        } catch {
            await MainActor.run {
                addWordError = "Translation failed. Check language models in Settings."
            }
        }
        await MainActor.run {
            isTranslating = false
            textToTranslateForTask = nil
        }
    }

    private func addWord() {
        let primary = germanInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = englishInput.trimmingCharacters(in: .whitespacesAndNewlines)

        if primary.isEmpty || target.isEmpty {
            addWordError = "Both fields are mandatory."
            return
        }

        let isDuplicate = box.words.contains {
            $0.primaryText.caseInsensitiveCompare(primary) == .orderedSame &&
            $0.targetText.caseInsensitiveCompare(target) == .orderedSame
        }
        guard !isDuplicate else {
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
                    ("\(primaryLanguageName) word", "e.g. \(primaryLanguageName)", $editGermanInput),
                    ("\(targetLanguageName) word", "e.g. \(targetLanguageName)", $editEnglishInput)
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

                    Button("Debug: Test Animation") {
                        runMockAnimation()
                    }
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 24)
                    .padding(.bottom, 32)
                }
                .padding(Self.edgePadding)
                .padding(.bottom, 72)
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
                    onFinish: { isShowingSession = false }
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
        return Button {
            isShowingSession = true
        } label: {
            Text("Start (\(wordCount))")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(isDisabled ? .secondary : ModalStyle.linguAIGreen)
        }
        .disabled(isDisabled)
        .frame(minHeight: 44)
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: ModalStyle.fabShadowRadius, x: 0, y: ModalStyle.fabShadowY)
        .padding(.bottom, 20)
    }

    private func progressionCard(_ level: BoxProgressionLevel) -> some View {
        let isSelected = selectedLevelIDs.contains(level.id)
        let count = level.wordCount
        let isPopping = popBoxID == level.id
        return Button {
            toggleSelection(level.id)
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(ModalStyle.linguAIGreen.opacity(Self.levelBadgeGreenOpacity))
                    Text("\(level.levelNumber)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                .frame(width: Self.levelBadgeSize, height: Self.levelBadgeSize)

                Text("\(count)")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .scaleEffect(isPopping ? popScale : 1)

                Spacer(minLength: 0)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: Self.progressBarHeight / 2, style: .continuous)
                            .fill(ModalStyle.linguAIGreen.opacity(Self.progressTrackOpacity))
                        RoundedRectangle(cornerRadius: Self.progressBarHeight / 2, style: .continuous)
                            .fill(ModalStyle.linguAIGreen)
                            .frame(width: max(0, geo.size.width * CGFloat(level.progress)))
                    }
                }
                .frame(height: Self.progressBarHeight)
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

    private func runMockAnimation() {
        refreshLevelCounts()
        popBoxID = nil
        popScale = 1
        isShowingAnimation = true
        activeMoves = [
            (from: 1, to: 2, count: 3, isSuccess: true),
            (from: 4, to: 5, count: 2, isSuccess: true),
            (from: 3, to: 1, count: 1, isSuccess: false)
        ]
    }

    /// Called at burst start: update counts and subtle number bump. No card frame/color change.
    private func applyMoveAndPop(move: (from: Int, to: Int, count: Int, isSuccess: Bool)) {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        if move.isSuccess {
            levelWordCounts[move.from, default: 0] -= move.count
            levelWordCounts[move.to, default: 0] += move.count
        } else {
            levelWordCounts[move.from, default: 0] -= move.count
            levelWordCounts[move.to, default: 0] += move.count
        }
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

// MARK: - Confetti (completion celebration)
private struct ConfettiView: View {
    private static let particleCount = 55
    private static let colors: [Color] = [
        ModalStyle.linguAIGreen,
        Color(.systemRed),
        Color(.systemOrange),
        Color(.systemYellow),
        Color(.systemBlue),
        Color(.systemPurple)
    ]
    @State private var dropProgress: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let fallDistance = height + 80
            ZStack {
                ForEach(0..<Self.particleCount, id: \.self) { i in
                    let x = (CGFloat(i) * 31 + 19).truncatingRemainder(dividingBy: width)
                    let color = Self.colors[i % Self.colors.count]
                    let delay = Double(i % 7) * 0.04
                    let size: CGFloat = [6, 7, 8, 9][i % 4]
                    RoundedRectangle(cornerRadius: size / 3, style: .continuous)
                        .fill(color)
                        .frame(width: size, height: size * CGFloat(1.4))
                        .position(x: x, y: -20 + dropProgress * fallDistance)
                        .opacity(dropProgress < 0.95 ? 1 : max(0, (1 - dropProgress) * CGFloat(20)))
                        .animation(.easeIn(duration: 2.2).delay(delay), value: dropProgress)
                }
            }
            .onAppear {
                dropProgress = 1
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Study Session (Leitner: correct → +1 level, wrong → level 1)
private struct StudySessionView: View {
    var box: VocabularyBox
    var selectedLevelIDs: Set<Int>
    var onFinish: () -> Void

    @Environment(\.modelContext) private var modelContext
    @AppStorage("studyDirection") private var studyDirection: String = "EN_DE"
    @AppStorage("wordsPerSession") private var wordsPerSession: Int = 10
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
                            .animation(.easeInOut(duration: 0.35), value: progress)
                    }
                }
                .frame(height: Self.progressBarHeight)

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
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.15), radius: ModalStyle.fabShadowRadius, x: 0, y: ModalStyle.fabShadowY)
                    .padding(.bottom, 32)
                }
            }
            .opacity(showCompletion ? 0 : 1)

            // Completion overlay
            if showCompletion {
                completionOverlay
            }
        }
        .onAppear {
            let filtered = box.words.filter { selectedLevelIDs.contains($0.level) }
            let capped = Array(filtered.shuffled().prefix(max(1, min(wordsPerSession, filtered.count))))
            sessionEntries = capped.map { word in
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
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            ConfettiView()
                .allowsHitTesting(false)

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

                Button {
                    onFinish()
                } label: {
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
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showCompletion)
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
            word.level = LeitnerEngine.level(afterCorrect: correct, currentLevel: word.level)
            try? modelContext.save()
        }
        if currentIndex + 1 >= totalWords {
            withAnimation(.easeOut(duration: 0.25)) {
                showCompletion = true
            }
        } else {
            withAnimation(.easeInOut(duration: 0.3)) {
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
    @AppStorage("studyDirection") private var studyDirection: String = "EN_DE"
    @AppStorage("wordsPerSession") private var wordsPerSession: Int = 10
    @AppStorage("hapticFeedbackEnabled") private var hapticFeedbackEnabled: Bool = true

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

    /// Minimum 5, maximum 50 or the words available in the box (whichever is lower).
    private var effectiveMaxWords: Int {
        max(5, min(50, maxWordsAvailable ?? 50))
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Study Direction")
                        .font(.system(.body, design: .rounded))
                    if let box, let tags = studyDirectionTags {
                        Picker("Study Direction", selection: $studyDirection) {
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
                        Picker("Study Direction", selection: $studyDirection) {
                            Text("DE → EN")
                                .font(.system(.subheadline, design: .rounded))
                                .tag("DE_EN")
                            Text("EN → DE")
                                .font(.system(.subheadline, design: .rounded))
                                .tag("EN_DE")
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
                HStack {
                    Text("Words per session")
                        .font(.system(.body, design: .rounded))
                    Spacer()
                    Picker("Words per session", selection: $wordsPerSession) {
                        ForEach(5...effectiveMaxWords, id: \.self) { n in
                            Text("\(n)").tag(n)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .tint(ModalStyle.linguAIGreen)
                }
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
            wordsPerSession = min(max(5, wordsPerSession), effectiveMaxWords)
            if let tags = studyDirectionTags {
                studyDirection = tags.primaryTarget
            }
        }
    }
}

#Preview {
    NavigationStack {
        VocabularyBoxesView()
    }
    .modelContainer(for: [VocabularyBox.self, BoxWord.self], inMemory: true)
}

