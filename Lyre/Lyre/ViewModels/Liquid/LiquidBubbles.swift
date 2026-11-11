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
    ///
    /// LYRE-61: a bubble is only tried against the ones near the top of the pile. One
    /// buried deeper than the biggest bubble could reach down can never hold a new one
    /// up (every new bubble rests at least as high as the lowest point of the surface),
    /// so it drops out. Trying each against every bubble before was a hundred million
    /// tries for a library of a couple of thousand albums, long enough on opening a Duo
    /// for the system to stop Lyre.
    nonisolated static func pack(_ diameters: [CGFloat], width: CGFloat, top: CGFloat = 0) -> (centers: [CGPoint], height: CGFloat) {
        var centers: [CGPoint] = []
        centers.reserveCapacity(diameters.count)
        // The bubbles still near enough the surface to hold a new one up.
        var active: [(center: CGPoint, radius: CGFloat)] = []
        var bottom = top
        let step: CGFloat = 6
        let largestRadius = (diameters.max() ?? 0) / 2
        let smallestRadius = (diameters.min() ?? 0) / 2
        // The surface: how high the pile's top is at each place a bubble's centre is tried.
        let samples = max(1, Int((width / step).rounded(.up)) + 1)
        var surface = [CGFloat](repeating: top, count: samples)
        // Its lowest point is looked for only where a centre can go: the edges, which no
        // bubble reaches over, would otherwise keep it at the bottom for good.
        let firstReachable = min(samples - 1, max(0, Int(((smallestRadius + gap / 2) / step).rounded(.up))))
        let lastReachable = max(firstReachable, min(samples - 1, Int(((width - smallestRadius - gap / 2) / step).rounded(.down))))
        for (index, diameter) in diameters.enumerated() {
            let r = diameter / 2
            var best: CGPoint?
            let lowest = r + gap / 2
            let highest = max(lowest, width - r - gap / 2)
            var x = lowest
            while x <= highest + 0.5 {
                var y = top + r + gap / 2
                for other in active {
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
            centers.append(center)
            active.append((center, r))
            bottom = max(bottom, center.y + r + gap / 2)
            // The surface over this bubble rises to its top.
            let first = max(0, Int(((center.x - r) / step).rounded(.down)))
            let last = min(samples - 1, Int(((center.x + r) / step).rounded(.up)))
            if first <= last {
                for sample in first...last {
                    let dx = abs(CGFloat(sample) * step - center.x)
                    guard dx < r else { continue }
                    surface[sample] = max(surface[sample], center.y + (r * r - dx * dx).squareRoot())
                }
            }
            // Those buried too deep to reach the lowest point of the surface drop out.
            let floor = surface[firstReachable...lastReachable].min() ?? top
            active.removeAll { $0.center.y + $0.radius + largestRadius + gap < floor }
        }
        return (centers, bottom)
    }

    /// Steady noise in -1...1 for a bubble, from its place in the list.
    nonisolated static func jitter(_ seed: Int) -> CGFloat {
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
    /// Let go: it, where it was heading, and how fast it was going (points a second).
    let onDrop: (AppAlbum, CGPoint, CGPoint) -> Void
    /// Whether the tabs stand down the field's edge; not when they're in an iPhone Duo's
    /// side column with the other buttons.
    var showsTabBar = true

    @Environment(\.windowSafeArea) private var safeArea
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var packing = Packing()
    /// Whether the field is moving, for the bubbles' touches; not observed, so the
    /// scroll starting and stopping redraws nothing.
    @State private var scroll = BubbleScrollState()

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

    /// Up to how many bubbles are packed on the main thread (a few milliseconds' work).
    static let packedHere = 600

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
                // While it scrolls the bubbles hold still and the scroll moves still
                // pictures of them (StillWhileScrolling); a touch landing on it moving
                // only stops it, as in any list, rather than playing what's under it.
                .modifier(StillWhileScrolling())
                .modifier(TracksScrolling(scroll: scroll))
                .onChange(of: key(items, width), initial: true) { _, key in
                    repack(items, width: width, key: key)
                }
            }
            // In the side column instead, when the player puts them there (SideRail): the
            // bubbles then keep clear of that column, as the tabs used to for them.
            if showsTabBar {
                tabBar
            } else {
                Color.clear.frame(width: safeArea.trailing)
            }
        }
        .background(Color.liquidGround)
        // The bubbles answer to the phone's tilt while they're up (BubbleTilt).
        .onAppear { BubbleTilt.shared.attach() }
        .onDisappear { BubbleTilt.shared.detach() }
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
        // A few hundred pack in a moment, here, so the field is laid out as it opens and
        // never re-laid under a finger. A bigger library is packed off the main thread
        // (LYRE-61), so opening a Duo never waits on it: the field shows its bubbles once
        // they're down, unless the list or the width has moved on meanwhile.
        guard diameters.count > Self.packedHere else {
            let packed = LiquidBubbleLayout.pack(diameters, width: width)
            packing = Packing(key: key, diameters: diameters, centers: packed.centers, height: packed.height)
            return
        }
        Task {
            let packed = await Task.detached(priority: .userInitiated) {
                LiquidBubbleLayout.pack(diameters, width: width)
            }.value
            guard key == self.key(self.items, width) else { return }
            packing = Packing(key: key, diameters: diameters, centers: packed.centers, height: packed.height)
        }
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
                        BubbleCell(album: items[index], diameter: d,
                                   drifts: LiquidBubbleLayout.drifts && !reduceMotion,
                                   isHidden: draggedID == items[index].id, scroll: scroll,
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
        VStack(spacing: 14) { LiquidBubbleTabs(tab: $tab) }
            .frame(width: Self.barWidth)
            .frame(maxHeight: .infinity)
            .padding(.trailing, safeArea.trailing)
            .background(Color.white.opacity(0.04))
    }
}

/// Albums, Playlists, Podcasts: which the bubbles are. Down the field's own edge, or in
/// an iPhone Duo's side column with the other buttons (SideRail), at the top, as
/// navigation goes.
struct LiquidBubbleTabs: View {
    @Binding var tab: LiquidBubbleTab

    var body: some View {
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
            .buttonStyle(LyrePressStyle())
            .accessibilityLabel(option.title)
            .accessibilityAddTraits(option == tab ? .isSelected : [])
            .accessibilityIdentifier("liquid.bubbles.tab.\(option.rawValue)")
        }
    }
}

// MARK: Bubble

/// Whether the bubble field is scrolling, kept where reading and writing it redraws
/// nothing: the touches ask it at the moment a finger lands.
final class BubbleScrollState {
    var isMoving = false
}

/// Keeps a BubbleScrollState up to date with the scroll view it's on (iOS 18 on).
private struct TracksScrolling: ViewModifier {
    let scroll: BubbleScrollState

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { _, phase in scroll.isMoving = phase != .idle }
        } else {
            content
        }
    }
}

/// One bubble in the field, with its touches.
///
/// The touches are UIKit's, so they sit with the field's scrolling as a list's rows do:
/// a tap is a tap only if the field was still when the finger landed (landing on it
/// moving just stops it); a hold opens the bubble's page unless the finger moves off;
/// and a drag only takes the bubble if it sets off leftward, mostly sideways, so up and
/// down is always the field's. Where the bubble is on screen is worked out from the
/// touch, when there is one, rather than measured on every frame of a scroll.
private struct BubbleCell: View {
    let album: AppAlbum
    let diameter: CGFloat
    let drifts: Bool
    let isHidden: Bool
    let scroll: BubbleScrollState
    let onPlay: (AppAlbum, CGPoint, CGFloat) -> Void
    let onOpen: (AppAlbum) -> Void
    let onDrag: (AppAlbum, CGPoint, CGFloat, CGPoint) -> Void
    let onDrop: (AppAlbum, CGPoint, CGPoint) -> Void

    var body: some View {
        let bubble = LiquidBubble(album: album, diameter: diameter)
            .opacity(isHidden ? 0 : 1)
            .contentShape(Circle())
            .modifier(BubbleTouches(album: album, diameter: diameter, scroll: scroll,
                                    onPlay: onPlay, onOpen: onOpen, onDrag: onDrag, onDrop: onDrop))
        return Group {
            if drifts {
                bubble.modifier(BubbleFloat(seed: album.id, reach: 3))
            } else {
                bubble
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(album.tapeTitle)
        .accessibilityValue(album.isPodcast || album.isMixtape ? "" : album.artistName)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(album.isPodcast ? String(localized: "liquid.bubbles.hint.show")
                                            : String(localized: "liquid.bubbles.hint"))
        .accessibilityAction { album.isPodcast ? onOpen(album) : onPlay(album, .zero, diameter) }
        .accessibilityAction(named: String(localized: "liquid.bubbles.open")) { onOpen(album) }
        .accessibilityIdentifier("liquid.bubble.\(album.id)")
    }
}

/// A bubble's touches: UIKit's from iOS 18, which sit with the field's scrolling;
/// before that, SwiftUI's, the bubble's place measured as it moves.
private struct BubbleTouches: ViewModifier {
    let album: AppAlbum
    let diameter: CGFloat
    let scroll: BubbleScrollState
    let onPlay: (AppAlbum, CGPoint, CGFloat) -> Void
    let onOpen: (AppAlbum) -> Void
    let onDrag: (AppAlbum, CGPoint, CGFloat, CGPoint) -> Void
    let onDrop: (AppAlbum, CGPoint, CGPoint) -> Void

    @State private var frame: CGRect = .zero
    @State private var isDragging = false

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .gesture(BubbleTap(scroll: scroll, diameter: diameter) { center in
                    album.isPodcast ? onOpen(album) : onPlay(album, center, diameter)
                })
                .gesture(BubbleHold {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onOpen(album)
                })
                .gesture(BubblePull(diameter: diameter, isEnabled: !album.isPodcast,
                                    onBegin: { UIImpactFeedbackGenerator(style: .light).impactOccurred() },
                                    onMove: { center, origin in onDrag(album, center, diameter, origin) },
                                    onEnd: { heading, velocity in onDrop(album, heading, velocity) }))
        } else {
            let center = CGPoint(x: frame.midX, y: frame.midY)
            content
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
                .onTapGesture { album.isPodcast ? onOpen(album) : onPlay(album, center, diameter) }
                .onLongPressGesture(minimumDuration: 0.45) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onOpen(album)
                }
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
                                              y: center.y + value.predictedEndTranslation.height),
                               CGPoint(x: value.velocity.width, y: value.velocity.height))
                    })
        }
    }
}

/// Where a touched bubble's centre is on screen: the touch on screen, less the touch
/// within the bubble, plus half the bubble.
@available(iOS 18.0, *)
private func bubbleCenter(_ converter: UIGestureRecognizerRepresentableCoordinateSpaceConverter,
                          diameter: CGFloat) -> CGPoint {
    let onScreen = converter.location(in: .global)
    let inBubble = converter.location(in: .local)
    return CGPoint(x: onScreen.x - inBubble.x + diameter / 2, y: onScreen.y - inBubble.y + diameter / 2)
}

/// A tap on a bubble, unless the finger landed on the field moving, and not once a
/// hold has taken the touch.
@available(iOS 18.0, *)
private struct BubbleTap: UIGestureRecognizerRepresentable {
    let scroll: BubbleScrollState
    let diameter: CGFloat
    let onTap: (CGPoint) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator(scroll: scroll) }

    func makeUIGestureRecognizer(context: Context) -> UITapGestureRecognizer {
        let tap = UITapGestureRecognizer()
        tap.delegate = context.coordinator
        return tap
    }

    func handleUIGestureRecognizerAction(_ recognizer: UITapGestureRecognizer, context: Context) {
        guard recognizer.state == .ended else { return }
        onTap(bubbleCenter(context.converter, diameter: diameter))
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let scroll: BubbleScrollState
        init(scroll: BubbleScrollState) { self.scroll = scroll }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            !scroll.isMoving
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
            other.name == "lyre.bubble.hold"
        }
    }
}

/// A bubble held still for a moment: its page.
@available(iOS 18.0, *)
private struct BubbleHold: UIGestureRecognizerRepresentable {
    let onHold: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let hold = UILongPressGestureRecognizer()
        hold.name = "lyre.bubble.hold"
        hold.minimumPressDuration = 0.45
        hold.allowableMovement = 10
        return hold
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        if recognizer.state == .began { onHold() }
    }
}

/// A bubble pulled out of the field toward Now Playing: only begun by a drag setting off
/// leftward and mostly sideways, so the field's own scrolling is never taken from it.
@available(iOS 18.0, *)
private struct BubblePull: UIGestureRecognizerRepresentable {
    let diameter: CGFloat
    let isEnabled: Bool
    let onBegin: () -> Void
    /// Where the bubble's centre is now, on screen, and where it started.
    let onMove: (CGPoint, CGPoint) -> Void
    /// Let go: where it was heading, and how fast it was going.
    let onEnd: (CGPoint, CGPoint) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        context.coordinator.isEnabled = isEnabled
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let moved = recognizer.translation(in: nil)
        switch recognizer.state {
        case .began:
            // Where it started: where it is now, less how far the finger's come.
            let now = bubbleCenter(context.converter, diameter: diameter)
            context.coordinator.origin = CGPoint(x: now.x - moved.x, y: now.y - moved.y)
            onBegin()
            onMove(now, context.coordinator.origin)
        case .changed:
            let origin = context.coordinator.origin
            onMove(CGPoint(x: origin.x + moved.x, y: origin.y + moved.y), origin)
        case .ended, .cancelled, .failed:
            let origin = context.coordinator.origin
            let velocity = recognizer.state == .ended ? recognizer.velocity(in: nil) : .zero
            // Where a flick would carry it: a quarter of a second on at its speed.
            onEnd(CGPoint(x: origin.x + moved.x + velocity.x * 0.25, y: origin.y + moved.y + velocity.y * 0.25),
                  velocity)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isEnabled = true
        var origin: CGPoint = .zero

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard isEnabled, let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: nil)
            return velocity.x < 0 && abs(velocity.x) > abs(velocity.y) * 1.2
        }
    }
}

/// A bubble: the cover in a soap bubble, as everywhere else in Liquid (LiquidSoapBubble),
/// leaning with the phone's tilt. Flattened to one picture, so a field of them scrolls
/// as still pictures; `wobbles` for the one being carried, whose film keeps moving.
struct LiquidBubble: View {
    let album: AppAlbum
    let diameter: CGFloat
    var wobbles = false

    var body: some View {
        LiquidSoapBubble(diameter: diameter, wobbles: wobbles, isLight: diameter < 120, flattens: !wobbles,
                         tilts: true, seed: album.id) {
            LiquidCover(source: .album(album))
        }
    }
}
