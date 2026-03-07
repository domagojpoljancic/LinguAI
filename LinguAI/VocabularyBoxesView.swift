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
    static let disabledButtonOpacity: Double = 0.3
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
                SettingsView()
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

// MARK: - Placeholder views (empty state for now)
private struct StudyView: View {
    var body: some View {
        VStack {
            Spacer()
            Text("Study")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

private struct SettingsView: View {
    var body: some View {
        VStack {
            Text("Settings")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    NavigationStack {
        VocabularyBoxesView()
    }
}

