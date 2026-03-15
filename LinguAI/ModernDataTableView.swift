//
//  ModernDataTableView.swift
//  LinguAI
//

import SwiftUI

/// A row model for the two-column table.
struct ModernDataTableRow: Identifiable {
    let id: UUID
    let column1: String
    let column2: String

    init(id: UUID = UUID(), column1: String, column2: String) {
        self.id = id
        self.column1 = column1
        self.column2 = column2
    }

    /// 20 rows of lorem ipsum words for sample/demo content.
    static let sampleTwentyRows: [ModernDataTableRow] = {
        let words = [
            "lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit",
            "sed", "eiusmod", "tempor", "incididunt", "labore", "dolore", "magna", "aliqua",
            "enim", "minim", "veniam", "quis", "nostrud", "exercitation", "ullamco", "laboris"
        ]
        return (0..<20).map { i in
            ModernDataTableRow(
                column1: words[i % words.count],
                column2: words[(i + 11) % words.count]
            )
        }
    }()
}

/// A two-column table with a sticky header, inset grouped style, and modern 2026 iOS aesthetic.
/// Supports Dark Mode and Dynamic Type via system colors and scalable fonts.
struct ModernDataTableView: View {
    let header1: String
    let header2: String
    let rows: [ModernDataTableRow]
    var onEdit: ((ModernDataTableRow) -> Void)?
    var onDelete: ((ModernDataTableRow) -> Void)?

    private let horizontalInset: CGFloat = 16
    private let cardCornerRadius: CGFloat = 12
    private let cardStrokeWidth: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            cardContent
        }
        .padding(.horizontal, horizontalInset)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private var cardContent: some View {
        VStack(spacing: 0) {
            stickyHeaderRow
            insetDivider
            listBody
        }
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 4)
    }

    private var stickyHeaderRow: some View {
        HStack(alignment: .center, spacing: 0) {
            Text(header1.uppercased())
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.secondary)
                .tracking(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, horizontalInset)
                .padding(.vertical, 12)

            Text(header2.uppercased())
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.secondary)
                .tracking(0.5)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, horizontalInset)
                .padding(.vertical, 12)
        }
        .background(Color(.tertiarySystemGroupedBackground))
    }

    private var insetDivider: some View {
        Divider()
            .padding(.leading, horizontalInset)
    }

    @ViewBuilder
    private var listBody: some View {
        if rows.isEmpty {
            Color(.systemBackground)
                .frame(height: 80)
        } else {
            List {
                ForEach(rows) { row in
                    HStack(spacing: 0) {
                        Text(row.column1)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(row.column2)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.vertical, 10)
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                    .contextMenu {
                        if let onEdit {
                            Button("Edit") { onEdit(row) }
                        }
                        if let onDelete {
                            Button("Delete", role: .destructive) { onDelete(row) }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if let onDelete {
                            Button("Delete", role: .destructive) { onDelete(row) }
                        }
                        if let onEdit {
                            Button("Edit") { onEdit(row) }
                                .tint(.orange)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
        }
    }
}

// MARK: - Previews

#Preview("With data") {
    ModernDataTableView(
        header1: "German",
        header2: "English",
        rows: ModernDataTableRow.sampleTwentyRows
    )
}

#Preview("Empty") {
    ModernDataTableView(
        header1: "Column 1",
        header2: "Column 2",
        rows: []
    )
}
