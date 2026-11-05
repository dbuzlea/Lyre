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

    @State private var current: Int
    @State private var isExpanded = false
    /// How far a sideways drag has the cards along, while it lasts.
    @State private var drag: CGFloat = 0
    /// Whether the drag in progress is sideways (turning the cards), decided at its start,
    /// so scrolling a card's page up and down doesn't nudge it along.
    @State private var dragIsSideways: Bool?
    @Environment(\.windowSafeArea) private var safeArea
    @Environment(\.liquidNavigator) private var navigator

    /// Scrolled this far down, the card fills the screen.
    private static var expandsAt: CGFloat { 60 }
    /// Pulled this far down from its top, the deck closes.
    private static var closesAt: CGFloat { -110 }
    /// Either side of the card in front, where the next ones peek in.
    private static var margin: CGFloat { 18 }
    private static var gap: CGFloat { 10 }

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
            // Clear of a camera at the side (an iPhone Duo closed), as the pages are.
            let width = geometry.size.width - safeArea.leading - safeArea.trailing
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
                // The card in front and the one either side, each placed by how far it is
                // from the front: nothing else is drawn, and the card in front, filling
                // the screen, is lined up with it wherever it is in the list.
                ZStack(alignment: .topLeading) {
                    ForEach(shown, id: \.self) { index in
                        card(deck.items[index], index: index, width: width, height: cardHeight)
                    }
                }
                .frame(width: width, height: cardHeight, alignment: .topLeading)
                .clipped()
                .contentShape(Rectangle())
                .simultaneousGesture(turning(width: width))
                .padding(.top, top)
                .padding(.leading, safeArea.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("liquid.deck")
        .accessibilityAction(.escape, onClose)
        .accessibilityScrollAction { edge in
            switch edge {
            case .leading: turn(to: current - 1)
            case .trailing: turn(to: current + 1)
            default: break
            }
        }
    }

    /// The card in front and its neighbours; filling the screen, it's the only card.
    private var shown: [Int] {
        isExpanded ? [current] : Array(max(0, current - 1)...min(deck.items.count - 1, current + 1))
    }

    /// A card's place: across from the front by its distance from it, plus the drag.
    /// The one in front, filling the screen, takes the whole width.
    private func card(_ item: LiquidDeckItem, index: Int, width: CGFloat, height: CGFloat) -> some View {
        let fills = isExpanded && current == index
        let cardWidth = width - 2 * Self.margin
        let x = fills ? 0 : Self.margin + CGFloat(index - current) * (cardWidth + Self.gap) + drag
        return content(item)
            .environment(\.liquidCard, LiquidCardContext(close: onClose) { y in scrolled(y, on: index) })
            .environment(\.liquidNavigator, cardNavigator)
            .frame(width: fills ? width : cardWidth, height: height)
            // It runs to the bottom edge, so only its top corners are rounded.
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: isExpanded ? 0 : 30, topTrailingRadius: isExpanded ? 0 : 30,
                                              style: .continuous))
            .overlay(alignment: .top) {
                if fills { bar(item) }
            }
            .offset(x: x)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("liquid.deck.card.\(index)")
    }

    /// A sideways drag turns to the next card or the one before; past either end it
    /// gives, and comes back. Up and down is the card's own page scrolling.
    private func turning(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !isExpanded else { return }
                if dragIsSideways == nil {
                    dragIsSideways = abs(value.translation.width) > abs(value.translation.height)
                }
                guard dragIsSideways == true else { return }
                let atEnd = (value.translation.width > 0 && current == 0)
                    || (value.translation.width < 0 && current == deck.items.count - 1)
                drag = atEnd ? value.translation.width / 3 : value.translation.width
            }
            .onEnded { value in
                defer { dragIsSideways = nil }
                guard !isExpanded, dragIsSideways == true else { return }
                let travel = value.predictedEndTranslation.width
                let turnAt = width / 4
                turn(to: travel < -turnAt ? current + 1 : travel > turnAt ? current - 1 : current)
            }
    }

    private func turn(to index: Int) {
        if min(max(index, 0), deck.items.count - 1) != current { UsageStats.shared.used(.cardSwipe) }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            current = min(max(index, 0), deck.items.count - 1)
            drag = 0
        }
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
            UsageStats.shared.used(.cardFullScreen)
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
