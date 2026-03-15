//
//  ContentView.swift
//  LinguAI
//
//  Created by Domagoj Poljancic on 05.03.26.

 
import SwiftUI
import SwiftData

private enum AppRoute: Hashable {
    case vocabularyBoxes
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    private let gridColumns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    @State private var navigationPath = NavigationPath()

    private var primaryGreen: Color {
        Color(.systemGreen)
    }

    // Order: top row Reading (left), Vocabulary boxes (right); bottom row Grammar (left), Chat (right)
    private static let categories: [(title: String, subtitle: String, systemImage: String, isActive: Bool, isBlurredTeaser: Bool)] = [
        ("Reading", "Comprehension practice", "book.closed", false, false),
        ("Vocabulary boxes", "Words & phrases", "shippingbox", true, false),
        ("Grammar", "Rules & exercises", "text.cursor", false, true),
        ("Chat", "Talk with AI tutor", "bubble.left.and.bubble.right", false, true)
    ]

    var body: some View {
        NavigationStack(path: $navigationPath) {
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
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .vocabularyBoxes:
                    VocabularyBoxesView()
                        .environment(\.modelContext, modelContext)
                }
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
            ForEach(Array(Self.categories.enumerated()), id: \.offset) { _, category in
                categoryCard(
                    title: category.title,
                    subtitle: category.subtitle,
                    systemImage: category.systemImage,
                    isActive: category.isActive,
                    isBlurredTeaser: category.isBlurredTeaser,
                    badgeText: category.isActive ? nil : "Coming soon",
                    action: category.isActive ? { navigationPath.append(AppRoute.vocabularyBoxes) } : nil
                )
            }
        }
    }

    private func categoryCard(
        title: String,
        subtitle: String,
        systemImage: String,
        isActive: Bool = true,
        isBlurredTeaser: Bool = false,
        badgeText: String? = nil,
        action: (() -> Void)?
    ) -> some View {
        let background = isActive
            ? primaryGreen.opacity(0.11)
            : Color(.systemGray6)

        let border = isActive
            ? primaryGreen.opacity(0.35)
            : Color(.systemGray4).opacity(0.8)

        let shadowColor = isActive
            ? primaryGreen.opacity(0.18)
            : Color.black.opacity(0.04)

        let cardContent = VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundColor(.white)
                .padding(10)
                .background(
                    Circle()
                        .fill(isActive ? primaryGreen.opacity(0.9) : Color(.systemGray3))
                )

            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(isActive ? .primary : .secondary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 160)
        .blur(radius: isBlurredTeaser ? 6 : 0)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(background)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(border, lineWidth: 1)
                )
                .shadow(color: shadowColor, radius: 8, x: 0, y: 4)
        )
        .overlay(alignment: .topTrailing) {
            if let badgeText, !isActive {
                Text(badgeText)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(.systemOrange))
                    )
                    .foregroundColor(.white)
                    .padding(.top, 6)
                    .padding(.trailing, 6)
            }
        }

        return Button {
            if isActive {
                action?()
            }
        } label: {
            cardContent
        }
        .buttonStyle(.plain)
        .allowsHitTesting(isActive)
    }
}

#if DEBUG
#Preview {
    ContentView()
        .withSampleData()
}
#endif
