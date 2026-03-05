//
//  VocabularyBoxesView.swift
//  LinguAI
//

import SwiftUI

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

    var body: some View {
        List {
            if boxes.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "shippingbox")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)

                        Text("No boxes yet")
                            .font(.headline)

                        Text("Tap the plus button to create your first vocabulary box.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 32)
                }
            } else {
                Section {
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
            }
        }
        .navigationTitle("Vocabulary boxes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    startAddingBox()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingBoxEditor) {
            NavigationStack {
                Form {
                    Section(header: Text("Box name")) {
                        TextField("e.g. \(currentSuggestion)", text: $newBoxName)
                            .onChange(of: newBoxName) { newValue in
                                if newValue.count > nameCharacterLimit {
                                    newBoxName = String(newValue.prefix(nameCharacterLimit))
                                }
                            }

                        if let nameError {
                            Text(nameError)
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        HStack {
                            Spacer()
                            Text("\(newBoxName.count)/\(nameCharacterLimit) characters")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                }
                .navigationTitle("New box")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            dismissAddBox()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveBox()
                        }
                        .disabled(newBoxName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
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
        .padding(.vertical, 4)
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
        newBoxName = ""
        nameError = nil
        editingBoxID = nil
        isPresentingBoxEditor = false
    }
}

struct VocabularyBoxDetailView: View {
    let box: VocabularyBox

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            tableBody
        }
        .navigationTitle(box.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            tableHeaderCell("German")
            Divider().frame(height: 20)
            tableHeaderCell("English")
        }
        .background(Color(.secondarySystemBackground))
    }

    private func tableHeaderCell(_ title: String) -> some View {
        Text(title)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .font(.subheadline.weight(.semibold))
    }

    private var tableBody: some View {
        Color(.systemBackground)
            .frame(maxWidth: .infinity, minHeight: 100)
    }
}

#Preview {
    NavigationStack {
        VocabularyBoxesView()
    }
}

