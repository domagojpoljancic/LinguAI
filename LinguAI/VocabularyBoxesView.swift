//
//  VocabularyBoxesView.swift
//  LinguAI
//

import SwiftUI

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
    /// Compact sheet height for New/Edit box – keeps input in thumb reach (one-handed use).
    static let newBoxSheetHeight: CGFloat = 320
}

private extension Font {
    static let linguAIRounded = Font.system(.body, design: .rounded)
}

struct VocabularyBox: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var progress: Double
    var wordCount: Int

    init(name: String, progress: Double = 0.0, wordCount: Int = 0) {
        self.name = name
        self.progress = progress
        self.wordCount = wordCount
    }
}

struct VocabularyBoxesView: View {
    @State private var boxes: [VocabularyBox] = []
    @State private var isPresentingBoxEditor = false
    @State private var newBoxName: String = ""
    @State private var nameError: String?

    @State private var editingBoxID: UUID?

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
                    boxes.remove(atOffsets: offsets)
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
        let isEditing = editingBoxID != nil
        let isSaveDisabled = newBoxName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Box name")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("e.g. \(currentSuggestion)", text: $newBoxName)
                            .onChange(of: newBoxName) { newValue in
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
                    }

                    if let nameError {
                        Text(nameError)
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(.red)
                            .padding(.top, 8)
                    }

                    Text("\(newBoxName.count)/\(nameCharacterLimit) characters")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)

                    Spacer(minLength: 24)

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
        HStack(spacing: 16) {
            progressCircle(for: box.progress)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    Text(box.name)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    Text("\(box.wordCount) words")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        editingBoxID = nil
        newBoxName = ""
        nameError = nil
        currentSuggestion = Self.suggestionPool.randomElement() ?? "Greetings"
        isPresentingBoxEditor = true
    }

    private func startRenaming(_ box: VocabularyBox) {
        editingBoxID = box.id
        newBoxName = box.name
        nameError = nil
        isPresentingBoxEditor = true
    }

    private func saveBox() {
        let trimmed = newBoxName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let isDuplicate = boxes.contains { existing in
            existing.name.caseInsensitiveCompare(trimmed) == .orderedSame &&
            existing.id != editingBoxID
        }

        guard !isDuplicate else {
            nameError = "A box with this name already exists."
            return
        }

        if let editingBoxID,
           let index = boxes.firstIndex(where: { $0.id == editingBoxID }) {
            boxes[index].name = trimmed
        } else {
            boxes.append(VocabularyBox(name: trimmed))
        }

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
        editingBoxID = nil
        isPresentingBoxEditor = false
    }
}

struct VocabularyBoxDetailView: View {
    let box: VocabularyBox

    @State private var tableRows: [ModernDataTableRow] = ModernDataTableRow.sampleTwentyRows
    @State private var isShowingAddWord = false
    @State private var germanInput = ""
    @State private var englishInput = ""
    @State private var addWordError: String?

    @State private var isShowingEditWord = false
    @State private var editingRow: ModernDataTableRow?
    @State private var editGermanInput = ""
    @State private var editEnglishInput = ""
    @State private var editWordError: String?

    @State private var rowToDelete: ModernDataTableRow?
    @State private var isShowingDeleteWordConfirmation = false
    @FocusState private var addWordFocusedField: Int?
    @FocusState private var editWordFocusedField: Int?
    @State private var isShowingSettings = false
    @State private var isShowingStudy = false
    @State private var wordSheetDetent: PresentationDetent = .medium

    var body: some View {
        ZStack {
            ModernDataTableView(
                header1: "German",
                header2: "English",
                rows: tableRows,
                onEdit: { row in
                    editingRow = row
                    editGermanInput = row.column1
                    editEnglishInput = row.column2
                    editWordError = nil
                    isShowingEditWord = true
                },
                onDelete: { row in
                    rowToDelete = row
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
                SettingsView(maxWordsAvailable: box.wordCount)
            }
        }
        .navigationDestination(isPresented: $isShowingStudy) {
            StudyView()
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
                if let row = rowToDelete {
                    tableRows.removeAll { $0.id == row.id }
                }
                rowToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                rowToDelete = nil
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
            floatingModalContent(
                title: "Add word",
                primaryButtonTitle: "Add",
                primaryAction: addWord,
                closeAction: { isShowingAddWord = false },
                isPrimaryDisabled: germanInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || englishInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                errorMessage: addWordError,
                focusedFieldIndex: $addWordFocusedField,
                sheetDetent: $wordSheetDetent,
                fields: [
                    ("German word", "e.g. Hallo", $germanInput),
                    ("English word", "e.g. Hello", $englishInput)
                ]
            )
        }
    }

    private func addWord() {
        let german = germanInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let english = englishInput.trimmingCharacters(in: .whitespacesAndNewlines)

        if german.isEmpty || english.isEmpty {
            addWordError = "Both fields are mandatory."
            return
        }

        tableRows.insert(
            ModernDataTableRow(column1: german, column2: english),
            at: 0
        )
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
                    ("German word", "e.g. Hallo", $editGermanInput),
                    ("English word", "e.g. Hello", $editEnglishInput)
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
        guard let editingRow else { return }
        let german = editGermanInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let english = editEnglishInput.trimmingCharacters(in: .whitespacesAndNewlines)

        if german.isEmpty || english.isEmpty {
            editWordError = "Both fields are mandatory."
            return
        }

        if let index = tableRows.firstIndex(where: { $0.id == editingRow.id }) {
            tableRows[index] = ModernDataTableRow(
                id: editingRow.id,
                column1: german,
                column2: english
            )
        }
        editWordError = nil
        self.editingRow = nil
        editGermanInput = ""
        editEnglishInput = ""
        isShowingEditWord = false
    }
}

// MARK: - Box Progression (Study) screen
private struct BoxProgressionLevel: Identifiable {
    let id: Int
    let levelNumber: Int
    let wordCount: Int
    let progress: Double // 0...1
}

private struct StudyView: View {
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

    private static var levels: [BoxProgressionLevel] {
        [
            BoxProgressionLevel(id: 1, levelNumber: 1, wordCount: 48, progress: 0.85),
            BoxProgressionLevel(id: 2, levelNumber: 2, wordCount: 124, progress: 0.6),
            BoxProgressionLevel(id: 3, levelNumber: 3, wordCount: 89, progress: 0.3),
            BoxProgressionLevel(id: 4, levelNumber: 4, wordCount: 52, progress: 0.1),
            BoxProgressionLevel(id: 5, levelNumber: 5, wordCount: 180, progress: 0.55),
            BoxProgressionLevel(id: 6, levelNumber: 6, wordCount: 352, progress: 0.42)
        ]
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: Self.gridSpacing) {
                    // Row 1: Levels 1 and 2
                    HStack(spacing: Self.gridSpacing) {
                        progressionCard(Self.levels[0])
                        progressionCard(Self.levels[1])
                    }

                    // Row 2: Levels 3 and 4
                    HStack(spacing: Self.gridSpacing) {
                        progressionCard(Self.levels[2])
                        progressionCard(Self.levels[3])
                    }

                    // Row 3: Levels 5 and 6
                    HStack(spacing: Self.gridSpacing) {
                        progressionCard(Self.levels[4])
                        progressionCard(Self.levels[5])
                    }
                }
                .padding(Self.edgePadding)
                .padding(.bottom, 72)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Box Progression")
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
                    SettingsView(maxWordsAvailable: totalWordsInSelectedLevels)
                }
            }
            .navigationDestination(isPresented: $isShowingSession) {
                StudySessionView(
                    wordPairs: StudySessionView.sampleWordPairs,
                    sourceLanguageLabel: "German",
                    translationLanguageLabel: "English",
                    onFinish: { isShowingSession = false }
                )
            }

            startFloatingButton
        }
    }

    private var totalWordsInSelectedLevels: Int {
        Self.levels.filter { selectedLevelIDs.contains($0.id) }.map(\.wordCount).reduce(0, +)
    }

    private var startFloatingButton: some View {
        let count = selectedLevelIDs.count
        let isDisabled = count == 0
        return Button {
            isShowingSession = true
        } label: {
            Text("Start (\(count))")
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
        return Button {
            toggleSelection(level.id)
        } label: {
            VStack(spacing: 12) {
                // Top: Level number in badge (faint green background)
                ZStack {
                    Circle()
                        .fill(ModalStyle.linguAIGreen.opacity(Self.levelBadgeGreenOpacity))
                    Text("\(level.levelNumber)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                .frame(width: Self.levelBadgeSize, height: Self.levelBadgeSize)

                // Middle: count
                Text("\(level.wordCount)")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                // Bottom: thin progress bar (line)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: Self.progressBarHeight / 2, style: .continuous)
                            .fill(ModalStyle.linguAIGreen.opacity(Self.progressTrackOpacity))
                        RoundedRectangle(cornerRadius: Self.progressBarHeight / 2, style: .continuous)
                            .fill(ModalStyle.linguAIGreen)
                            .frame(width: max(0, geo.size.width * level.progress))
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

private struct ProgressionCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Study Session
private struct StudySessionView: View {
    typealias WordPair = (native: String, translation: String)

    var wordPairs: [WordPair]
    /// Source language (primary word), shown in header badge and above the main word when revealed.
    var sourceLanguageLabel: String = "German"
    /// Translation language, shown above the translation when revealed.
    var translationLanguageLabel: String = "English"
    var onFinish: () -> Void

    @AppStorage("wordsPerSession") private var wordsPerSession: Int = 10
    @AppStorage("hapticFeedbackEnabled") private var hapticFeedbackEnabled: Bool = true

    @State private var sessionWords: [WordPair] = []
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

    private var totalWords: Int { sessionWords.count }
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
                            .frame(width: max(0, geo.size.width * progress))
                            .animation(.easeInOut(duration: 0.35), value: progress)
                    }
                }
                .frame(height: Self.progressBarHeight)

                // Header: back (left), source language pill (center)
                HStack {
                    Button {
                        showExitAlert = true
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundStyle(ModalStyle.linguAIGreen)
                            .frame(width: 44, height: 44)
                    }

                    Spacer()

                    Text(sourceLanguageLabel)
                        .font(.system(.caption2, design: .rounded).weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color(.systemGray5)))

                    Spacer()

                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 8)
                .padding(.top, 12)
                .padding(.bottom, 24)

                // Word card (center): white card, primary word, translation + language labels when revealed
                if !sessionWords.isEmpty, currentIndex < sessionWords.count {
                    let pair = sessionWords[currentIndex]
                    VStack(spacing: 16) {
                        VStack(spacing: 6) {
                            if isRevealed {
                                Text(sourceLanguageLabel)
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(Color(.systemGray))
                            }
                            Text(pair.native)
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)
                        }

                        if isRevealed {
                            VStack(spacing: 6) {
                                Text(translationLanguageLabel)
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(Color(.systemGray))
                                Text(pair.translation)
                                    .font(.system(size: 22, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
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
            let count = min(wordsPerSession, wordPairs.count)
            sessionWords = Array(wordPairs.shuffled().prefix(max(1, count)))
            sessionStartTime = Date()
        }
        .alert("End Session?", isPresented: $showExitAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Exit", role: .destructive) {
                onFinish()
            }
        } message: {
            Text("Progress for this session will be lost.")
        }
    }

    private var completionOverlay: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Text("Well Done!")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Session Complete")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)

                Text("\(totalWords) words studied")
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
        if currentIndex + 1 >= totalWords {
            withAnimation(.easeOut(duration: 0.25)) {
                showCompletion = true
            }
        } else {
            currentIndex += 1
            isRevealed = false
        }
    }
}

extension StudySessionView {
    /// Sample word pairs for development; replace with real data from selected boxes.
    static let sampleWordPairs: [WordPair] = [
        ("Hallo", "Hello"),
        ("Danke", "Thank you"),
        ("Bitte", "Please"),
        ("Ja", "Yes"),
        ("Nein", "No"),
        ("Guten Morgen", "Good morning"),
        ("Auf Wiedersehen", "Goodbye"),
        ("Entschuldigung", "Excuse me"),
        ("Wie geht es dir?", "How are you?"),
        ("Ich heiße...", "My name is..."),
        ("Wasser", "Water"),
        ("Brot", "Bread"),
        ("Buch", "Book"),
        ("Haus", "House"),
        ("Zeit", "Time"),
        ("Freund", "Friend"),
        ("Arbeit", "Work"),
        ("Liebe", "Love"),
        ("Tag", "Day"),
        ("Nacht", "Night")
    ]
}

private struct SettingsView: View {
    /// When set, words per session is capped by this (e.g. total words in selected boxes). Otherwise cap at 50.
    var maxWordsAvailable: Int? = nil

    @Environment(\.dismiss) private var dismiss
    @AppStorage("wordsPerSession") private var wordsPerSession: Int = 10
    @AppStorage("hapticFeedbackEnabled") private var hapticFeedbackEnabled: Bool = true

    private var effectiveMaxWords: Int {
        max(1, min(50, maxWordsAvailable ?? 50))
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Words per session")
                        .font(.system(.body, design: .rounded))
                    Spacer()
                    Picker("Words per session", selection: $wordsPerSession) {
                        ForEach(1...effectiveMaxWords, id: \.self) { n in
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
            wordsPerSession = min(max(1, wordsPerSession), effectiveMaxWords)
        }
    }
}

#Preview {
    NavigationStack {
        VocabularyBoxesView()
    }
}

