//
//  LiquidDiscover.swift
//  Lyre
//

import SwiftUI

// MARK: - Liquid Discover
//
// What Apple Music offers (Discover), on a page of its own from the lava menu, kept
// simple: each section (Made for You's groups, Recently Played, New Releases, Replay,
// the charts, the genres) is one soap bubble with its covers floating inside it as
// smaller bubbles, and nothing else to choose between. A tap on a bubble opens it up
// into a grid of everything in the section (LiquidDiscoverSectionPage), zooming out of
// the bubble where the OS can. In Recently Played a cover's bubble is as big as the
// songs played from it lately: an album played through is a big one, a song off another
// a small one. Elsewhere the first few are the biggest, as a section puts its best first.
//
// The bubbles float: each drifts a few points and back, slowly and out of step with
// the others, and the big ones' outlines wobble as a bubble's does in the air. With
// Reduce Motion on, they keep still.
//
// In the grid, each cover is a bubble too. A cover opens as a card, the section's others either side of it; one the
// library hasn't streams; a genre opens as a playlist of its top songs. Asked for when
// the page first opens, and filled in a section at a time.

struct LiquidDiscoverPage: View {
    @Environment(\.liquidNavigator) private var navigator
    @Environment(\.liquidDiscoverZoom) private var zoom
    @ObservedObject var musicService: MusicService
    let bottomInset: CGFloat

    var body: some View {
        let sections = Discover.shared.sections
        GeometryReader { geometry in
            let diameter = (min(geometry.size.width - 40, 360) * 0.86).rounded()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    LiquidPageTitle(title: String(localized: "discover.title"))
                    if sections.isEmpty {
                        Text(Discover.emptyText)
                            .foregroundStyle(.white.opacity(0.7))
                            .accessibilityIdentifier("liquid.discover.empty")
                    }
                    ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                        // Left, then right, then left: bubbles drifting down the page.
                        let side: HorizontalAlignment = index.isMultiple(of: 2) ? .leading : .trailing
                        VStack(alignment: side, spacing: 10) {
                            Text(section.title.lowercasedKeepingAppleMusic)
                                .font(.system(size: 22, weight: .medium))
                                .tracking(-0.5)
                                .foregroundStyle(.white)
                                .accessibilityAddTraits(.isHeader)
                            Button { navigator.push(.discoverSection(section)) } label: {
                                LiquidDiscoverBubble(section: section, weights: weights(for: section),
                                                     diameter: diameter)
                            }
                            .buttonStyle(BubblePressStyle())
                            .modifier(DiscoverZoomSource(id: section.id, namespace: zoom))
                            .accessibilityLabel(section.title)
                            .accessibilityValue(String(format: String(localized: "discover.bubble.count"), section.items.count))
                            .accessibilityHint(String(localized: "discover.bubble.hint"))
                            .accessibilityIdentifier("liquid.discover.bubble")
                        }
                        .frame(maxWidth: .infinity, alignment: index.isMultiple(of: 2) ? .leading : .trailing)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("liquid.discover.\(section.id)")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, bottomInset + 20)
            }
            .modifier(StillWhileScrolling())
            // The section open, handed on to the next player switched to (LYRE-41).
            .onAppear { LiquidPlace.opened(list: "discover") }
        }
        .background(LiquidPageGround())
        .toolbar(.hidden, for: .navigationBar)
        .task { await Discover.shared.load(in: musicService) }
        // The bubbles answer to the phone's tilt while the page is up (BubbleTilt).
        .onAppear { BubbleTilt.shared.attach() }
        .onDisappear { BubbleTilt.shared.detach() }
    }

    /// How big each cover's bubble is: by songs played from it, in Recently Played.
    private func weights(for section: DiscoverSection) -> [Double] {
        let items = Array(section.items.prefix(LiquidDiscoverBubble.shown))
        return section.kind == .recentlyPlayed
            ? DiscoverBubbleWeights.recentlyPlayed(items, songs: musicService.recentlyPlayed)
            : DiscoverBubbleWeights.byPlace(items.count)
    }
}

// MARK: - A Section's Bubble

/// One soap bubble holding a section's covers as smaller bubbles, packed together.
struct LiquidDiscoverBubble: View {
    let section: DiscoverSection
    let weights: [Double]
    let diameter: CGFloat

    /// The most covers a bubble holds; the grid has the rest.
    static let shown = 9

    var body: some View {
        let items = Array(section.items.prefix(Self.shown))
        let circles = BubblePacking.pack(Array(weights.prefix(items.count)))
        let half = diameter / 2
        LiquidSoapBubble(diameter: diameter, wobbles: true, flattens: true, tilts: true, seed: section.id) {
            ZStack {
                Color.white.opacity(0.05)
                ForEach(Array(zip(items, circles).enumerated()), id: \.element.0.id) { _, pair in
                    let (item, circle) = pair
                    let side = (CGFloat(circle.r) * diameter).rounded()
                    mini(item, diameter: side)
                        // Each a little adrift inside, by less than the gap round it.
                        .modifier(BubbleFloat(seed: item.id, reach: max(1.5, side * 0.025)))
                        .position(x: half + CGFloat(circle.x) * half, y: half + CGFloat(circle.y) * half)
                }
            }
        }
        .modifier(BubbleFloat(seed: section.id, reach: 6))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func mini(_ item: AppAlbum, diameter: CGFloat) -> some View {
        LiquidSoapBubble(diameter: diameter, isLight: true, tilts: true, seed: item.id) {
            if section.kind == .genres {
                // A genre has no cover until it's opened: its name on a colour of its own.
                ZStack {
                    LinearGradient(colors: [Self.colour(for: item.title), Self.colour(for: item.title).opacity(0.55)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text(item.title)
                        .font(.system(size: min(20, max(9, diameter * 0.15)), weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .padding(diameter * 0.16)
                }
            } else {
                LiquidCover(source: .album(item))
            }
        }
    }

    /// A colour that's always the same for a name.
    static func colour(for name: String) -> Color {
        let hash = name.unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.55, brightness: 0.62)
    }
}

/// A bubble gives a little under the finger.
struct BubblePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Sizes and Packing

nonisolated enum DiscoverBubbleWeights {
    /// Recently Played: each album as big as the songs played from it lately (one
    /// played without any of its songs counted still gets a bubble).
    static func recentlyPlayed(_ items: [AppAlbum], songs: [AppTrack]) -> [Double] {
        var counts: [String: Int] = [:]
        for song in songs { counts[key(song.albumTitle), default: 0] += 1 }
        return items.map { 1 + Double(counts[key($0.title)] ?? 0) }
    }

    /// Anywhere else: the first biggest, as a section puts its best first.
    static func byPlace(_ count: Int) -> [Double] {
        (0..<count).map { 1 + Double(count - $0) * 0.3 }
    }

    private static func key(_ title: String) -> String { TapeFormat.displayTitle(title).lowercased() }
}

/// Circles packed inside a circle: given each one's weight (its area), where it goes and
/// how big it is, in a unit circle (radius 1, centred on 0). The biggest goes in the
/// middle and the rest spiral out round it, each where it first fits, then the whole is
/// centred and scaled to fill the bubble.
nonisolated enum BubblePacking {
    struct Circle: Equatable {
        let x: Double
        let y: Double
        let r: Double
    }

    /// The share of the bubble's radius the packed circles fill, leaving a rim of film.
    static let fill = 0.84

    @MainActor private static var cache: [[Double]: [Circle]] = [:]

    /// The layout for `weights`, worked out once for each set of weights (a section
    /// redraws as covers load, and packing is the costly part).
    @MainActor static func pack(_ weights: [Double]) -> [Circle] {
        if let known = cache[weights] { return known }
        let circles = layout(weights)
        if cache.count > 64 { cache.removeAll() }
        cache[weights] = circles
        return circles
    }

    static func layout(_ weights: [Double], gap: Double = 0.07) -> [Circle] {
        guard !weights.isEmpty else { return [] }
        let radii = weights.map { sqrt(max($0, 0.01)) }
        let order = radii.indices.sorted { radii[$0] > radii[$1] || (radii[$0] == radii[$1] && $0 < $1) }
        let unit = radii[order[0]]
        var placed: [Int: Circle] = [:]
        for index in order {
            let r = radii[index]
            guard !placed.isEmpty else {
                placed[index] = Circle(x: 0, y: 0, r: r)
                continue
            }
            // Out along a spiral until it touches nothing.
            var step = 0.0
            while true {
                let angle = step * 0.5 + Double(index) * 1.7
                let distance = step * 0.02 * unit
                let x = distance * cos(angle), y = distance * sin(angle)
                let fits = placed.values.allSatisfy { hypot($0.x - x, $0.y - y) >= $0.r + r + gap * unit }
                if fits || step > 4000 {
                    placed[index] = Circle(x: x, y: y, r: r)
                    break
                }
                step += 1
            }
        }
        // Centred on the middle of what's been packed, and scaled to fill the bubble.
        let circles = placed.values
        let minX = circles.map { $0.x - $0.r }.min() ?? 0, maxX = circles.map { $0.x + $0.r }.max() ?? 0
        let minY = circles.map { $0.y - $0.r }.min() ?? 0, maxY = circles.map { $0.y + $0.r }.max() ?? 0
        let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
        let reach = circles.map { hypot($0.x - cx, $0.y - cy) + $0.r }.max() ?? 1
        let scale = fill / max(reach, 0.0001)
        return weights.indices.map { index in
            let c = placed[index]!
            return Circle(x: (c.x - cx) * scale, y: (c.y - cy) * scale, r: c.r * scale)
        }
    }
}

// MARK: - A Section, Opened

/// A section's bubble opened up: everything in it, as a grid of covers (the genres as
/// names to tap).
struct LiquidDiscoverSectionPage: View {
    @Environment(\.liquidNavigator) private var navigator
    let section: DiscoverSection
    let bottomInset: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LiquidPageTitle(title: section.title.lowercasedKeepingAppleMusic)
                    if section.kind == .genres {
                        genres
                    } else {
                        LiquidBubbleGrid(albums: section.items, width: geometry.size.width - 40,
                                         identifier: { _ in "liquid.discover.item" }, holdMenu: false,
                                         open: open)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, bottomInset + 20)
            }
            .modifier(StillWhileScrolling())
        }
        .background(LiquidPageGround())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("liquid.discover.section")
    }

    /// A cover opens as a card, the section's others either side of it.
    private func open(_ index: Int) {
        navigator.openDeck(section.items.map { .album($0) }, index, section.title)
    }

    private var genres: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(Array(section.items.enumerated()), id: \.element.id) { index, genre in
                Button { open(index) } label: {
                    Text(genre.title)
                        .font(.system(size: 15, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.horizontal, 10)
                        .background(.white.opacity(0.12), in: Capsule())
                }
                .foregroundStyle(.white)
                .buttonStyle(LyrePressStyle())
                .accessibilityIdentifier("liquid.discover.genre")
            }
        }
    }
}

// MARK: - A Cover as a Bubble

/// A cover in a section's grid: a soap bubble, floating a little, its name under it.
struct LiquidBubbleTile: View {
    let album: AppAlbum
    let diameter: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            LiquidSoapBubble(diameter: diameter, isLight: true, flattens: true, tilts: true, seed: album.id) {
                LiquidCover(source: .album(album))
            }
            .modifier(BubbleFloat(seed: album.id, reach: 3))
            VStack(spacing: 2) {
                HStack(spacing: 5) {
                    Text(album.tapeTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    // An explicit album is marked, beside its clean version (LYRE-23).
                    if album.isExplicit { ExplicitBadge() }
                }
                Text(album.caseByline ?? album.artistName)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Floating

/// A bubble adrift: it moves up to `reach` points away and back, and a little sideways,
/// over a few seconds, each by its own `seed` so no two keep time. An offset only, moved
/// by the render loop, so it costs no layout; still with Reduce Motion on.
struct BubbleFloat: ViewModifier {
    let seed: String
    let reach: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidBubblesStill) private var isHeldStill
    @State private var isAway = false

    func body(content: Content) -> some View {
        let wander = Self.wander(seed)
        content
            .offset(x: isAway ? reach * wander.dx : 0, y: isAway ? reach * wander.dy : 0)
            .onAppear { if !isHeldStill { drift(wander) } }
            // While the page scrolls, the bubbles settle where they are and the scroll
            // moves still pictures; they drift again once it stops.
            .onChange(of: isHeldStill) { _, still in
                if still {
                    withAnimation(.easeOut(duration: 0.25)) { isAway = false }
                } else {
                    drift(wander)
                }
            }
    }

    private func drift(_ wander: (dx: CGFloat, dy: CGFloat, duration: Double, delay: Double)) {
        guard !reduceMotion else { return }
        withTransaction(Transaction(animation: nil)) { isAway = false }
        withAnimation(.easeInOut(duration: wander.duration).repeatForever(autoreverses: true).delay(wander.delay)) {
            isAway = true
        }
    }

    /// Which way and how slowly a bubble drifts, the same each time for a seed.
    static func wander(_ seed: String) -> (dx: CGFloat, dy: CGFloat, duration: Double, delay: Double) {
        let hash = seed.unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }
        let angle = Double(hash % 360) * .pi / 180
        return (CGFloat(cos(angle)) * 0.6, -abs(CGFloat(sin(angle))) - 0.4,
                2.6 + Double(hash % 17) / 10, Double(hash % 9) / 10)
    }
}

// MARK: - Still While Scrolling

private struct LiquidBubblesStillKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Bubbles hold still (a page of them scrolling): no drift, no wobble, until it's false.
    var liquidBubblesStill: Bool {
        get { self[LiquidBubblesStillKey.self] }
        set { self[LiquidBubblesStillKey.self] = newValue }
    }
}

/// Holds a scroll view's bubbles still while it moves (iOS 18 on, which reports a scroll's
/// phase; before, they float on).
struct StillWhileScrolling: ViewModifier {
    @State private var isScrolling = false

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollPhaseChange { _, phase in
                    let moving = phase != .idle
                    if moving != isScrolling {
                        isScrolling = moving
                        BubbleTilt.shared.isPaused = moving
                    }
                }
                .onDisappear { BubbleTilt.shared.isPaused = false }
                .environment(\.liquidBubblesStill, isScrolling)
        } else {
            content
        }
    }
}

// MARK: - The Zoom

/// The namespace a section's bubble and its opened page share, for the zoom between
/// them (iOS 18 on; a plain push before).
private struct LiquidDiscoverZoomKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var liquidDiscoverZoom: Namespace.ID? {
        get { self[LiquidDiscoverZoomKey.self] }
        set { self[LiquidDiscoverZoomKey.self] = newValue }
    }
}

/// A bubble just tapped, for the push it leads to: an album page opened from its own
/// bubble zooms out of it (and back into it) instead of flooding, so it's seen where it
/// came from. Only a tap a moment ago counts.
@MainActor
enum LiquidZoom {
    private static var tapped: (id: String, at: Date)?

    static func tapped(_ albumID: String) { tapped = (albumID, Date()) }

    /// Whether `albumID`'s bubble was the one just tapped; asking forgets it either way.
    static func take(_ albumID: String) -> Bool {
        defer { tapped = nil }
        guard let tapped, Date().timeIntervalSince(tapped.at) < 1 else { return false }
        return tapped.id == albumID
    }

    static func sourceID(_ albumID: String) -> String { "album." + albumID }
}

struct DiscoverZoomSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

struct DiscoverZoomDestination: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), let namespace {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}
