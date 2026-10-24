//
//  LiquidBubbles.swift
//  Lyre
//

import SwiftUI

// MARK: - Bubbles
//
// iPhone Duo, open and held as a book: the right page, beside Now Playing, is the library
// as bubbles. Each album, playlist or show is a bubble with its cover in it, floating in
// place in the dark, bigger the more songs it holds. A bar of tabs down the right edge
// chooses which: Albums, Playlists or Podcasts. The field scrolls when there are more
// than fit.
//
//   tap an album or playlist     it plays, the bubble flying into Now Playing
//   drag it left                 it goes with the finger; at the fold, Now Playing's edge
//                                reaches out for it, and past the fold it's taken in
//                                and plays (the parent draws that, see LiquidPlayerView)
//   hold it                      its page opens, to choose one song
//   tap a show                   its episodes open; a show isn't dragged
//
// How they're laid out (`LiquidBubbleLayout`): each bubble in turn drops into the lowest
// place it fits across the width without touching those already down, as bubbles
// settle in a glass. The same library comes out the same way every time. They drift a
// little where they rest, each at its own pace, but stay put otherwise: no tilting, as
// the lava lamp does. Still with Reduce Motion, in Low Power Mode and in UI tests.

enum LiquidBubbleTab: String, CaseIterable, Identifiable {
    case albums, playlists, podcasts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .albums:    String(localized: "menu.albums")
        case .playlists: String(localized: "menu.playlists")
        case .podcasts:  String(localized: "menu.podcasts")
        }
    }

    var symbol: String {
        switch self {
        case .albums:    "square.stack.fill"
        case .playlists: "music.note.list"
        case .podcasts:  "mic.fill"
        }
    }

    var emptyText: String {
        switch self {
        case .albums:    String(localized: "liquid.bubbles.empty.albums")
        case .playlists: String(localized: "liquid.bubbles.empty.playlists")
        case .podcasts:  String(localized: "liquid.bubbles.empty.podcasts")
        }
    }
}

// MARK: Layout

enum LiquidBubbleLayout {
    /// The smallest bubble (a single) and the largest (thirty songs or more).
    static let smallest: CGFloat = 64
    static let largest: CGFloat = 156
    /// What a bubble whose songs aren't known yet counts as.
    static let unknownCount = 10
    /// Room between bubbles.
    static let gap: CGFloat = 10

    /// How wide a bubble of `count` songs is: one song the smallest, thirty or more the
    /// largest, in between by the logarithm, so a few songs more tell on a short album
    /// more than on a long one. Never more than half of `width`.
    static func diameter(forSongs count: Int?, width: CGFloat) -> CGFloat {
        let songs = Double(max(1, count ?? unknownCount))
        let share = min(1, log(songs) / log(30))
        let largest = min(Self.largest, max(smallest, width / 2 - gap))
        return (smallest + (largest - smallest) * share).rounded()
    }

    /// The songs on an item, as far as they're known without loading: an album's count,
    /// a playlist's or show's songs if it has them already.
    static func songCount(of album: AppAlbum) -> Int? {
        if let show = album.podcast { return show.episodes.count }
        if let count = album.tapeTrackCount { return count }
        return album.preloadedTracks.isEmpty ? nil : album.preloadedTracks.count
    }

    /// Where each bubble's centre goes, and how tall the field is: each in turn drops
    /// into the lowest place it fits, across `width`, under `top`.
    static func pack(_ diameters: [CGFloat], width: CGFloat, top: CGFloat = 0) -> (centers: [CGPoint], height: CGFloat) {
        var placed: [(center: CGPoint, radius: CGFloat)] = []
        var bottom = top
        for (index, diameter) in diameters.enumerated() {
            let r = diameter / 2
            var best: CGPoint?
            let step: CGFloat = 6
            let lowest = r + gap / 2
            let highest = max(lowest, width - r - gap / 2)
            var x = lowest
            while x <= highest + 0.5 {
                var y = top + r + gap / 2
                for other in placed {
                    let reach = other.radius + r + gap
                    let dx = abs(other.center.x - x)
                    guard dx < reach else { continue }
                    y = max(y, other.center.y + (reach * reach - dx * dx).squareRoot())
                }
                // Ties go to whichever the bubble's own small lean favours, so the
                // field doesn't pile up against the left.
                let lean = jitter(index) * 3
                if best.map({ y + lean < $0.y - 0.5 }) ?? true { best = CGPoint(x: x, y: y + lean) }
                x += step
            }
            let center = best.map { CGPoint(x: $0.x, y: $0.y - jitter(index) * 3) } ?? CGPoint(x: width / 2, y: top + r)
            placed.append((center, r))
            bottom = max(bottom, center.y + r + gap / 2)
        }
        return (placed.map(\.center), bottom)
    }

    /// Steady noise in -1...1 for a bubble, from its place in the list.
    static func jitter(_ seed: Int) -> CGFloat {
        let x = sin(Double(seed) * 12.9898 + 78.233) * 43_758.5453
        return CGFloat((x - x.rounded(.down)) * 2 - 1)
    }

    /// Whether the bubbles drift where they rest.
    static var drifts: Bool {
        !ProcessInfo.processInfo.isLowPowerModeEnabled && !AppEnvironment.isUITesting
    }
}

// MARK: Field

struct LiquidBubbleField: View {
    @ObservedObject var musicService: MusicService
    @Binding var tab: LiquidBubbleTab
    /// The bubble being dragged, drawn by the parent meanwhile, so hidden here.
    let draggedID: String?
    /// An album or playlist tapped: it, where its bubble's centre is on screen, and how wide.
    let onPlay: (AppAlbum, CGPoint, CGFloat) -> Void
    /// A bubble held, or a show tapped: its page.
    let onOpen: (AppAlbum) -> Void
    /// A bubble dragged: it, where its centre is now on screen, how wide, and where it
    /// started.
    let onDrag: (AppAlbum, CGPoint, CGFloat, CGPoint) -> Void
    /// Let go: it, and where it was heading.
    let onDrop: (AppAlbum, CGPoint) -> Void

    @Environment(\.windowSafeArea) private var safeArea
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var packing = Packing()

    private var library: ShelfLibrary { ShelfLibrary(musicService: musicService) }

    private var items: [AppAlbum] {
        switch tab {
        case .albums:    library.albums
        case .playlists: library.mixtapes
        case .podcasts:  library.podcasts
        }
    }

    /// The bubbles, worked out once for a list and a width.
    struct Packing {
        var key = ""
        var diameters: [CGFloat] = []
        var centers: [CGPoint] = []
        var height: CGFloat = 0
    }

    /// Bubbles are grouped into bands this tall, so only those near the screen are made.
    private static let band: CGFloat = 360
    private static let barWidth: CGFloat = 58

    var body: some View {
        HStack(spacing: 0) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let items = items
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(tab.title)
                            .font(.system(size: 30, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(.white)
                            .padding(.leading, 20)
                            .padding(.top, safeArea.top + 18)
                            .padding(.bottom, 6)
                            .accessibilityAddTraits(.isHeader)
                        if items.isEmpty {
                            Text(tab.emptyText)
                                .font(.system(size: 15))
                                .foregroundStyle(.white.opacity(0.6))
                                .padding(.horizontal, 20)
                                .padding(.top, 40)
                        } else if packing.centers.count == items.count {
                            bands(items, width: width)
                        }
                    }
                    .padding(.bottom, safeArea.bottom + 24)
                }
                .onChange(of: key(items, width), initial: true) { _, key in
                    repack(items, width: width, key: key)
                }
            }
            tabBar
        }
        .background(Color.liquidGround)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("liquid.bubbles")
    }

    private func key(_ items: [AppAlbum], _ width: CGFloat) -> String {
        "\(tab.rawValue)|\(Int(width))|\(items.count)|\(items.first?.id ?? "")|\(items.last?.id ?? "")"
    }

    private func repack(_ items: [AppAlbum], width: CGFloat, key: String) {
        guard width > 0, packing.key != key else { return }
        let diameters = items.map {
            LiquidBubbleLayout.diameter(forSongs: LiquidBubbleLayout.songCount(of: $0), width: width)
        }
        let packed = LiquidBubbleLayout.pack(diameters, width: width)
        packing = Packing(key: key, diameters: diameters, centers: packed.centers, height: packed.height)
    }

    /// The bubbles in bands, made as they come near the screen.
    private func bands(_ items: [AppAlbum], width: CGFloat) -> some View {
        let count = max(1, Int((packing.height / Self.band).rounded(.up)))
        return LazyVStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { band in
                let top = CGFloat(band) * Self.band
                ZStack(alignment: .topLeading) {
                    ForEach(items.indices.filter { Int(packing.centers[$0].y / Self.band) == band }, id: \.self) { index in
                        let d = packing.diameters[index]
                        BubbleCell(album: items[index], diameter: d, seed: index,
                                   drifts: LiquidBubbleLayout.drifts && !reduceMotion,
                                   isHidden: draggedID == items[index].id,
                                   onPlay: onPlay, onOpen: onOpen, onDrag: onDrag, onDrop: onDrop)
                            .position(x: packing.centers[index].x, y: packing.centers[index].y - top)
                    }
                }
                .frame(width: width, height: band == count - 1 ? max(0, packing.height - top) : Self.band,
                       alignment: .topLeading)
                .zIndex(Double(count - band))
            }
        }
    }

    /// The tabs, down the right edge, clear of the side the screen's corner is on.
    private var tabBar: some View {
        VStack(spacing: 14) {
            ForEach(LiquidBubbleTab.allCases) { option in
                Button {
                    guard option != tab else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.easeInOut(duration: 0.3)) { tab = option }
                } label: {
                    Image(systemName: option.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(option == tab ? Color.black : Color.white.opacity(0.75))
                        .frame(width: 44, height: 44)
                        .background(option == tab ? Color.white : Color.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(option == tab ? .isSelected : [])
                .accessibilityIdentifier("liquid.bubbles.tab.\(option.rawValue)")
            }
        }
        .frame(width: Self.barWidth)
        .frame(maxHeight: .infinity)
        .padding(.trailing, safeArea.trailing)
        .background(Color.white.opacity(0.04))
    }
}

// MARK: Bubble

/// One bubble in the field, with its touches.
private struct BubbleCell: View {
    let album: AppAlbum
    let diameter: CGFloat
    let seed: Int
    let drifts: Bool
    let isHidden: Bool
    let onPlay: (AppAlbum, CGPoint, CGFloat) -> Void
    let onOpen: (AppAlbum) -> Void
    let onDrag: (AppAlbum, CGPoint, CGFloat, CGPoint) -> Void
    let onDrop: (AppAlbum, CGPoint) -> Void

    /// Where it is on screen, for the parent to take it from.
    @State private var frame: CGRect = .zero
    @State private var isDragging = false
    @State private var rise = false
    @State private var sway = false

    private var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }

    var body: some View {
        LiquidBubble(album: album, diameter: diameter)
            .offset(x: sway ? 2.5 : -2.5, y: rise ? -4 : 4)
            .opacity(isHidden ? 0 : 1)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            .contentShape(Circle())
            .onTapGesture {
                album.isPodcast ? onOpen(album) : onPlay(album, center, diameter)
            }
            .onLongPressGesture(minimumDuration: 0.45) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onOpen(album)
            }
            // Leftward, mostly sideways: up and down is the field scrolling.
            .simultaneousGesture(album.isPodcast ? nil : DragGesture(minimumDistance: 12, coordinateSpace: .global)
                .onChanged { value in
                    if !isDragging {
                        guard value.translation.width < 0,
                              abs(value.translation.width) > abs(value.translation.height) * 1.2 else { return }
                        isDragging = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    onDrag(album, CGPoint(x: center.x + value.translation.width, y: center.y + value.translation.height),
                           diameter, center)
                }
                .onEnded { value in
                    guard isDragging else { return }
                    isDragging = false
                    onDrop(album, CGPoint(x: center.x + value.predictedEndTranslation.width,
                                          y: center.y + value.predictedEndTranslation.height))
                })
            .onAppear {
                guard drifts else { return }
                // Each at its own pace, so they never move together.
                let pace = 2.6 + Double(LiquidBubbleLayout.jitter(seed) + 1) * 0.9
                withAnimation(.easeInOut(duration: pace).repeatForever(autoreverses: true)) { rise = true }
                withAnimation(.easeInOut(duration: pace * 1.37).repeatForever(autoreverses: true)) { sway = true }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(album.tapeTitle)
            .accessibilityValue(album.isPodcast || album.isMixtape ? "" : album.artistName)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(album.isPodcast ? String(localized: "liquid.bubbles.hint.show")
                                                : String(localized: "liquid.bubbles.hint"))
            .accessibilityAction(named: String(localized: "liquid.bubbles.open")) { onOpen(album) }
            .accessibilityIdentifier("liquid.bubble.\(album.id)")
    }
}

/// A bubble: the cover seen through a ball of glass, lit from above on the left, darker
/// toward its rim, with a bright edge.
struct LiquidBubble: View {
    let album: AppAlbum
    let diameter: CGFloat

    var body: some View {
        ZStack {
            LiquidCover(source: .album(album))
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
            Circle()
                .fill(RadialGradient(colors: [.clear, .black.opacity(0.32)], center: .center,
                                     startRadius: diameter * 0.28, endRadius: diameter * 0.52))
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.42), .white.opacity(0)],
                                     center: UnitPoint(x: 0.32, y: 0.24),
                                     startRadius: 0, endRadius: diameter * 0.34))
                .blendMode(.screen)
            Circle()
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.06), .white.opacity(0.25)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: max(1, diameter / 70))
        }
        .frame(width: diameter, height: diameter)
        .compositingGroup()
        .shadow(color: .black.opacity(0.45), radius: diameter / 12, y: diameter / 24)
    }
}
