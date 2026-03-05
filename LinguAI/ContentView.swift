//
//  ContentView.swift
//  LinguAI
//
//  Created by Domagoj Poljancic on 05.03.26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    private let gridColumns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    private var primaryGreen: Color {
        // Use the system green that feels familiar across iOS
        Color(.systemGreen)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                .ignoresSafeArea()

                VStack(spacing: 24) {
                    headerBar
                    titleSection
                    categoriesGrid
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }
        }
    }

    private var headerBar: some View {
        HStack {
            Button {
                // TODO: open side menu
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(primaryGreen)
                    .padding(10)
                    .background(
                        Circle()
                            .fill(primaryGreen.opacity(0.08))
                    )
            }

            Spacer()

            Button {
                // TODO: open account
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(primaryGreen)
                    .padding(10)
                    .background(
                        Circle()
                            .fill(primaryGreen.opacity(0.08))
                    )
            }
        }
    }

    private var titleSection: some View {
        VStack(spacing: 8) {
            Text("LinguAI")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundColor(primaryGreen)

            Text("Level up your language skills.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var categoriesGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 16) {
            categoryCard(
                title: "Grammar",
                subtitle: "Rules & exercises",
                systemImage: "text.cursor",
                badgeText: "Coming soon"
            )

            categoryCard(
                title: "Vocabulary box",
                subtitle: "Words & phrases",
                systemImage: "shippingbox"
            )

            categoryCard(
                title: "Reading",
                subtitle: "Comprehension practice",
                systemImage: "book.closed",
                badgeText: "Coming soon"
            )

            categoryCard(
                title: "Chat",
                subtitle: "Talk with AI tutor",
                systemImage: "bubble.left.and.bubble.right",
                badgeText: "Coming soon"
            )
        }
    }

    private func categoryCard(
        title: String,
        subtitle: String,
        systemImage: String,
        badgeText: String? = nil
    ) -> some View {
        Button {
            // TODO: navigate to \(title) section
        } label: {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(
                        Circle()
                            .fill(primaryGreen.opacity(0.9))
                    )

                VStack(spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)

                if let badgeText {
                    Text(badgeText)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(.systemOrange).opacity(0.12))
                        )
                        .foregroundColor(Color(.systemOrange))
                        .padding(.top, 4)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 160)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(primaryGreen.opacity(0.11))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(primaryGreen.opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: primaryGreen.opacity(0.18), radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
