//
//  LiquidCardDeck.swift
//  Lyre
//

import SwiftUI

// MARK: - Liquid Card Deck
//
// What's chosen from one of Liquid's lists (Discover, the artists, the albums, the
// playlists) opens as a card over the list rather than a page in place of it, as Apple
// Sports opens a game: the list it came from dims behind, named at the top, and the
// card holds the album's, playlist's or artist's own page. The cards either side of it
// show at the edges: swiping across turns to the next in the list, so a list can be
// looked through a card at a time.
//
// Scrolled down, the card grows to fill the screen, a bar across the top naming it;
// scrolled back to its top, it's a card again. Pulled down from its top, or closed with
// its chevron, the deck goes and the list is as it was.
//
// A card's page knows it's in a card (`liquidCard`): its way back closes the deck, and it
// says how far it's scrolled, which is what grows and shrinks the card.

/// One card: an album or playlist, or an artist.
enum LiquidDeckItem: Hashable {
    case album(AppAlbum)
    case artist(String)

    var title: String {
        switch self {
        case .album(let album): album.tapeTitle
        case .artist(let name): name
        }
    }
}

/// A deck: its cards, the one chosen, and the list it came from, named at the top.
struct LiquidDeck: Identifiable {
    let id = UUID()
    let items: [LiquidDeckItem]
    let index: Int
    let title: String
}

/// What a page in a card is told: how to close the deck, and where to say it's scrolled.
struct LiquidCardContext {
    var close: () -> Void
    /// How far down the page is scrolled (negative while pulled down from its top).
    var scrolled: (CGFloat) -> Void
}

extension EnvironmentValues {
    /// Set while a page is shown in a card of the deck; nil on a page of its own.
    @Entry var liquidCard: LiquidCardContext? = nil
}

extension View {
    /// Tells the card this page is in how far it's scrolled.
    /// (iOS 17 can't say, so there the card stays a card, closed by its chevron.)
    func reportsLiquidCardScroll(_ card: LiquidCardContext?) -> some View {
        modifier(LiquidCardScrollReport(card: card))
    }
}

private struct LiquidCardScrollReport: ViewModifier {
    let card: LiquidCardContext?

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), let card {
            content.onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in
                card.scrolled(y)
            }
        } else {
            content
        }
    }
}

struct LiquidCardDeckView<Content: View>: View {
    let deck: LiquidDeck
    let onClose: () -> Void
    @ViewBuilder let content: (LiquidDeckItem) -> Content

    @State private var current: Int?
    @State private var isExpanded = false
    @Environment(\.windowSafeArea) private var safeArea
    @Environment(\.liquidNavigator) private var navigator

    /// Scrolled this far down, the card fills the screen.
    private static var expandsAt: CGFloat { 60 }
    /// Pulled this far down from its top, the deck closes.
    private static var closesAt: CGFloat { -110 }

    init(deck: LiquidDeck, onClose: @escaping () -> Void, @ViewBuilder content: @escaping (LiquidDeckItem) -> Content) {
        self.deck = deck
        self.onClose = onClose
        self.content = content
        _current = State(initialValue: deck.index)
    }

    var body: some View {
        GeometryReader { geometry in
            let top = isExpanded ? 0 : max(safeArea.top, 6) + 40
            let cardHeight = geometry.size.height - top
            ZStack(alignment: .top) {
                Color.black.opacity(isExpanded ? 1 : 0.55)
                Text(deck.title.lowercasedKeepingAppleMusic)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 40)
                    .padding(.top, max(safeArea.top, 6) + 10)
                    .opacity(isExpanded ? 0 : 1)
                    .accessibilityIdentifier("liquid.deck.title")
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: isExpanded ? 0 : 10) {
                        ForEach(deck.items.indices, id: \.self) { index in
                            card(deck.items[index], index: index, height: cardHeight)
                                .containerRelativeFrame(.horizontal) { width, _ in isExpanded ? width : width - 36 }
                                .id(index)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $current)
                .contentMargins(.horizontal, isExpanded ? 0 : 18, for: .scrollContent)
                .scrollDisabled(isExpanded)
                .scrollIndicators(.hidden)
                .frame(height: cardHeight)
                // The next card peeks in only as far as the deck's edge.
                .clipped()
                .padding(.top, top)
                // Clear of a camera at the side (an iPhone Duo closed), as the pages are.
                .padding(.leading, safeArea.leading)
                .padding(.trailing, safeArea.trailing)
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("liquid.deck")
        .accessibilityAction(.escape, onClose)
    }

    private func card(_ item: LiquidDeckItem, index: Int, height: CGFloat) -> some View {
        content(item)
            .environment(\.liquidCard, LiquidCardContext(close: onClose) { y in scrolled(y, on: index) })
            .environment(\.liquidNavigator, cardNavigator)
            .frame(height: height)
            // It runs to the bottom edge, so only its top corners are rounded.
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: isExpanded ? 0 : 30, topTrailingRadius: isExpanded ? 0 : 30,
                                              style: .continuous))
            .overlay(alignment: .top) {
                if isExpanded, current == index { bar(item) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("liquid.deck.card.\(index)")
    }

    /// The library's moves, from a card: back closes the deck, and a page opened from
    /// it (an artist's, a song's album) closes the deck and opens over the list.
    private var cardNavigator: LiquidNavigator {
        var card = navigator
        let push = navigator.push
        card.back = onClose
        card.push = { route in
            onClose()
            push(route)
        }
        return card
    }

    /// Grows the card at its first scroll down, shrinks it back at its top, and closes
    /// the deck when it's pulled down from there. Only the card in front counts.
    private func scrolled(_ y: CGFloat, on index: Int) {
        guard index == current else { return }
        if !isExpanded, y > Self.expandsAt {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { isExpanded = true }
        } else if isExpanded, y <= 2 {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { isExpanded = false }
        } else if !isExpanded, y < Self.closesAt {
            onClose()
        }
    }

    /// Across the top of a card that fills the screen: its name, and the way back to
    /// the list.
    private func bar(_ item: LiquidDeckItem) -> some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.15), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "liquid.card.close"))
            .accessibilityIdentifier("liquid.card.bar.close")
            Spacer(minLength: 8)
            barArt(item)
            Text(item.title)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 8)
            Color.clear.frame(width: 40, height: 40)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, safeArea.top + 4)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
        .transition(.opacity)
        .accessibilityIdentifier("liquid.card.bar")
    }

    @ViewBuilder
    private func barArt(_ item: LiquidDeckItem) -> some View {
        switch item {
        case .album(let album):
            LiquidCover(source: .album(album))
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .artist(let name):
            ArtistPhoto(name: name, fallback: nil, size: 28)
        }
    }
}
