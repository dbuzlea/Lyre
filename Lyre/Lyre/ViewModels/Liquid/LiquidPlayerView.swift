//
//  LiquidPlayerView.swift
//  Lyre
//

import SwiftUI

// MARK: - Liquid Player
//
// The modern player, shown in place of the click-wheel player when Settings → Player
// Style is Liquid. Less is more: the cover is the screen, and everything else is a few
// words and the handles to do things with.
//
// Three places, joined the same way:
//
//   Now Playing   the cover, full screen; the waves on its edges change songs
//                 (LiquidNowPlayingView)
//   Library       big type, then grids of covers and an album's page (LiquidLibraryView),
//                 with what's playing docked at the bottom as a droplet
//   Up Next       the tide that rises from the bottom edge of Now Playing (LiquidTideView)
//
// Changes of view are the same flood (see LiquidFlow): the colour of where you're going
// spreads out from where you touched until it covers the screen, and then that view is
// there. Now Playing and the library, the library's pages; playing something in the
// library floods into Now Playing in its cover's colour. Two moves follow the finger
// instead, as sheets do: Now Playing dragged down slides away to show the library page
// underneath, and Up Next pulled up from the bottom rises after the finger.
//
// iPhone Duo, open, the inner screen holds two places at once:
//
//   held as a book  Now Playing on the left page; on the right, the library as bubbles
//                   (LiquidBubbles), one dragged across the fold taken into Now
//                   Playing; Now Playing's library button swaps them for the library
//   turned, fold    Now Playing above the fold; below it, Up Next as a pool of drops
//   across          (LiquidPool), or the library in its place
//
// Partly open, the hinge is gravity: the lava runs toward the fold and the waves lean
// toward it. Stood half open and left alone for a while as the music plays, the screen
// gives itself to a visualizer (LiquidVisualizer) until it's touched. No other iPhone
// has a hinge, so none of this shows anywhere else.
//
// It drives the same MusicService as the other players, so switching styles keeps the
// music playing, and asks before clearing songs the listener queued, as they all do.

struct LiquidPlayerView: View {
    @ObservedObject var musicService: MusicService
    let themeSettings: ThemeSettings
    let foldMonitor: FoldPostureMonitor

    enum Screen { case nowPlaying, library }

    @State private var screen: Screen?
    @State private var path: [LiquidRoute] = []
    @State private var isTideShown = false
    /// How far up the tide is: 0 away, 1 open. A finger can hold it anywhere between.
    @State private var tideProgress: CGFloat = 0
    /// The progress when a finger took hold of the tide.
    @State private var tideDragStart: CGFloat?
    /// How far Now Playing has been dragged down, on its way back to the library.
    @State private var nowPlayingDrop: CGFloat = 0
    @State private var flood: Flood?
    @State private var showSettings = false
    @State private var showPodcastSearch = false
    @State private var pendingPlay: PendingPlay?
    @State private var notice: String?
    @State private var noticeTask: Task<Void, Never>?
    /// iPhone Duo, fold across the middle: the library below the fold instead of Up Next.
    @State private var isLibraryBelow = false
    /// The visualizer, while the Duo stands half open, left alone.
    @State private var isVisualizing = false
    /// iPhone Duo held as a book: the whole library on the right page, not the bubbles.
    @State private var isBookLibrary = false
    /// The library came up from a bubble held: going back from its page goes back to them.
    @State private var isBookLibraryFromBubbles = false
    @State private var bubbleTab: LiquidBubbleTab = .albums
    /// A bubble on its way into Now Playing: dragged, flying after a tap, or taken in.
    @State private var carried: CarriedBubble?
    /// Now Playing's page, on screen, for a bubble to be taken into.
    @State private var nowPlayingPage: CGRect = .zero
    @Environment(\.windowSafeArea) private var safeArea
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var library: ShelfLibrary { ShelfLibrary(musicService: musicService) }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                if let duo = duoLayout(for: geometry.size) {
                    switch duo {
                    case .book: bookLayout(geometry)
                    case .laptop: laptopLayout(geometry)
                    }
                } else {
                switch screen ?? (musicService.nowPlayingTrack != nil ? .nowPlaying : .library) {
                case .nowPlaying:
                    // The library waits underneath while Now Playing is dragged down.
                    if nowPlayingDrop > 0 {
                        libraryLayer(geometry)
                    }
                    LiquidNowPlayingView(
                        musicService: musicService,
                        themeSettings: themeSettings,
                        onOpenLibrary: { flood(.liquidGround, in: geometry) { screen = .library } },
                        onOpenQueue: openTide,
                        onOpenSettings: { showSettings = true },
                        onQueueDrag: { lift in dragTide(to: lift / tideHeight, from: 0) },
                        onQueueDragEnd: { lift, heading in
                            endTideDrag(opens: heading > tideHeight * 0.3 || lift > tideHeight * 0.25)
                        },
                        onOpenPlayingAlbum: openPlayingAlbum,
                        onDismissDrag: { drop in nowPlayingDrop = drop },
                        onDismissDragEnd: { drop, heading in endDismiss(drop: drop, heading: heading) }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: nowPlayingDrop > 0 ? 34 : 0, style: .continuous))
                    .shadow(color: .black.opacity(nowPlayingDrop > 0 ? 0.5 : 0), radius: 24)
                    .offset(y: nowPlayingDrop)
                case .library:
                    libraryLayer(geometry)
                }
                }

                if isVisualizing {
                    LiquidVisualizer(musicService: musicService) { wakeFromVisualizer() }
                        .transition(.opacity)
                        .zIndex(6)
                }

                if isTideShown {
                    LiquidTideView(
                        musicService: musicService,
                        progress: tideProgress,
                        onPick: { offset in
                            closeTide()
                            musicService.playUpcoming(at: offset)
                        },
                        onClose: closeTide,
                        onNotice: showNotice,
                        onDrag: { drop in dragTide(to: 1 - max(0, drop) / tideHeight, from: 1) },
                        onDragEnd: { drop, heading in endTideDrag(opens: !(drop > 120 || heading > 260)) }
                    )
                    .zIndex(2)
                }

                if let flood {
                    Circle()
                        .fill(flood.color)
                        .frame(width: flood.diameter, height: flood.diameter)
                        .scaleEffect(flood.scale)
                        .position(flood.origin)
                        .opacity(flood.opacity)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .zIndex(4)
                }

                LiquidTouchTrackerView()
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)

                if let notice {
                    Text(notice)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.75), in: Capsule())
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, safeArea.top + 60)
                        .transition(.opacity)
                        .accessibilityIdentifier("liquid.notice")
                        .zIndex(5)
                }
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { bounds = $0 }
        .animation(.easeInOut(duration: 0.2), value: notice)
        .environment(\.liquidFlood, LiquidFloodAction { color, origin, change in
            floodAction(color, origin, change)
        })
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $showSettings) {
            LiquidSettingsView(musicService: musicService, themeSettings: themeSettings,
                               foldMonitor: foldMonitor) { showSettings = false }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPodcastSearch) {
            PodcastSearchView(musicService: musicService)
        }
        .replaceQueuePrompt($pendingPlay, count: musicService.listenerQueuedCount)
        // Where Liquid is, for the Artwork Carousel to open on when the phone turns.
        .onChange(of: path, initial: true) { reportLocation() }
        // Left alone on a Duo stood half open, as the music plays: the visualizer.
        .task(id: foldMonitor.isPartlyOpen && musicService.isPlaying) { await watchForRest() }
        // Songs' tempos, for the waves and ripples to keep the beat: the one playing
        // first, then the library behind it (see SongTempos).
        .onChange(of: TempoLookupKey(playing: musicService.nowPlayingTrack?.id, songs: musicService.songs.count,
                                     isOn: themeSettings.liquidTempoLookup), initial: true) { lookUpTempos() }
        .onChange(of: foldMonitor.isPartlyOpen) { _, partly in
            if !partly { withAnimation(.easeInOut(duration: 0.4)) { isVisualizing = false } }
        }
        .animation(.easeInOut(duration: 0.6), value: isVisualizing)
        .onChange(of: screen) { reportLocation() }
        .onAppear {
            #if DEBUG
            // `--spool-sample-queue` fills Up Next with the first sample album's songs, so
            // the tide has something in it on a simulator with no music.
            // `--liquid-sample-middle` starts it on the second song, so there's one before.
            if ProcessInfo.processInfo.arguments.contains("--spool-sample-queue"),
               musicService.upNext.isEmpty, let album = library.albums.first {
                let middle = ProcessInfo.processInfo.arguments.contains("--liquid-sample-middle")
                musicService.seedQueueForUITests(album.preloadedTracks, startingAt: middle ? 1 : 0)
            }
            // `-LiquidBubbleShot 40` holds the first album's bubble that far (points) from
            // the fold, as if dragged there, for screenshots of Now Playing reaching for it.
            if UserDefaults.standard.object(forKey: "LiquidBubbleShot") != nil, let album = library.albums.first {
                let gap = CGFloat(UserDefaults.standard.double(forKey: "LiquidBubbleShot"))
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    let diameter: CGFloat = 120
                    let center = CGPoint(x: nowPlayingPage.maxX + gap + diameter / 2, y: nowPlayingPage.midY)
                    carried = CarriedBubble(album: album, diameter: diameter, center: center, origin: center)
                }
            }
            // `--liquid-visualizer` shows the Duo's visualizer at once, for screenshots.
            if ProcessInfo.processInfo.arguments.contains("--liquid-visualizer") { isVisualizing = true }
            // `-LiquidShot library|albums|artists|artist|album|songs|tide` opens there, for screenshots.
            switch UserDefaults.standard.string(forKey: "LiquidShot") {
            case "nowPlaying": screen = .nowPlaying
            case "library": screen = .library
            case "songs":
                screen = .library
                path = [.songs]
            case "albums":
                screen = .library
                path = [.albums]
            case "artists":
                screen = .library
                path = [.artists]
            case "artist":
                screen = .library
                if let name = library.albums.first?.artistName { path = [.artists, .artist(name)] }
            case "album":
                screen = .library
                if let album = library.albums.first { path = [.albums, .album(album)] }
            case "tide":
                screen = .nowPlaying
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    openTide()
                }
            default: break
            }
            #endif
        }
        .onDisappear { noticeTask?.cancel() }
    }

    // MARK: Moving

    private struct Flood {
        let color: Color
        let origin: CGPoint
        let diameter: CGFloat
        var scale: CGFloat = 0.01
        var opacity: Double = 1
    }

    /// The size and place of the player, for floods started by the views inside it.
    @State private var bounds: CGRect = .zero

    /// The colour of what's playing, deepened: what a flood into Now Playing fills with.
    private var nowPlayingColor: Color {
        let found = musicService.nowPlayingTrack.flatMap {
            LiquidColors.shared.cached("track:" + $0.albumTitle + "|" + $0.artistName)
        }
        return (found ?? Color(red: 0.17, green: 0.29, blue: 0.48)).liquidDeep
    }

    private func flood(_ color: Color, in geometry: GeometryProxy, then change: @escaping () -> Void) {
        bounds = geometry.frame(in: .global)
        floodAction(color, nil, change)
    }

    /// Spreads `color` out from `origin` (the last touch, when none is given) until it
    /// covers the screen, makes `change` under it, and lets it clear. One at a time.
    private func floodAction(_ color: Color, _ origin: CGPoint?, _ change: @escaping () -> Void) {
        guard flood == nil else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        var instant = Transaction()
        instant.disablesAnimations = true
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.25)) { change() }
            return
        }
        let size = bounds.size
        // Where the touch was, in the player's own space.
        // An origin given is on the screen (global); either way, into the player's space.
        let touch = (origin ?? LiquidTouchTracker.shared.lastTouch).map {
            CGPoint(x: $0.x - bounds.minX, y: $0.y - bounds.minY)
        } ?? CGPoint(x: size.width / 2, y: size.height / 2)
        // Large enough, centred on the touch, to reach the furthest corner.
        let reach = max(hypot(touch.x, touch.y), hypot(size.width - touch.x, touch.y),
                        hypot(touch.x, size.height - touch.y), hypot(size.width - touch.x, size.height - touch.y))
        flood = Flood(color: color, origin: touch, diameter: reach * 2 + 40)
        withAnimation(.easeIn(duration: Self.floodIn)) {
            flood?.scale = 1
        } completion: {
            withTransaction(instant) { change() }
            withAnimation(.easeOut(duration: Self.floodOut)) {
                flood?.opacity = 0
            } completion: {
                flood = nil
            }
        }
    }

    /// The flood's two halves: spreading, and clearing.
    private static let floodIn = 0.32
    private static let floodOut = 0.28

    /// The library, with what's playing docked at the bottom as a droplet (on a Duo's
    /// split screen, where Now Playing is in view, the droplet's place is `dock`'s).
    private func libraryLayer(_ geometry: GeometryProxy, lavaPull: CGVector = .zero,
                              dock: AnyView? = nil) -> some View {
        LiquidLibraryView(
            musicService: musicService,
            path: $path,
            onPlay: { album, tracks, index, whole in play(album, tracks, index, whole: whole, in: geometry.size) },
            onPlaySongs: playSongs,
            onQueue: queue,
            onFindShows: { showPodcastSearch = true },
            onOpenSettings: { showSettings = true },
            themeSettings: themeSettings,
            bottomInset: musicService.nowPlayingTrack != nil || dock != nil ? 104 + safeArea.bottom : safeArea.bottom,
            lavaPull: lavaPull
        )
        .overlay(alignment: .bottom) {
            Group {
                if let dock {
                    dock
                } else {
                    LiquidDroplet(musicService: musicService) { _ in
                        flood(nowPlayingColor, in: geometry) { screen = .nowPlaying }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.leading, safeArea.leading)
            .padding(.trailing, safeArea.trailing)
            .padding(.bottom, safeArea.bottom + 10)
            // Out of the way of a cover swung open.
            .opacity(LiquidFoldState.shared.isOpen ? 0 : 1)
            .allowsHitTesting(!LiquidFoldState.shared.isOpen)
            .animation(.easeInOut(duration: 0.25), value: LiquidFoldState.shared.isOpen)
        }
    }

    // MARK: iPhone Duo

    private enum DuoLayout { case book, laptop }

    /// Open, the Duo's inner screen: wider than tall held as a book, taller turned with
    /// the fold across the middle.
    private func duoLayout(for size: CGSize) -> DuoLayout? {
        guard foldMonitor.posture == .open, size.width > 0 else { return nil }
        #if DEBUG
        // `-LiquidDuoLayout book`: the book layout in whatever window there is. The
        // simulator can't turn Liquid sideways, which only the Duo's inner screen does.
        if UserDefaults.standard.string(forKey: "LiquidDuoLayout") == "book" { return .book }
        #endif
        return size.width > size.height ? .book : .laptop
    }

    /// How strongly the hinge pulls toward the fold: none open flat, more the further
    /// it's closed.
    private var hingePull: CGFloat {
        guard foldMonitor.isPartlyOpen, let angle = foldMonitor.angle else { return 0 }
        return CGFloat(min(1, max(0, (160 - angle) / 90)))
    }

    /// Now Playing, sharing the screen: no dragging it away (the other half is already
    /// in view).
    private func nowPlayingPane(lean: CGVector, onOpenLibrary: @escaping () -> Void,
                                queueDrag: Bool) -> some View {
        LiquidNowPlayingView(
            musicService: musicService,
            themeSettings: themeSettings,
            onOpenLibrary: onOpenLibrary,
            onOpenQueue: openTide,
            onOpenSettings: { showSettings = true },
            onQueueDrag: { lift in if queueDrag { dragTide(to: lift / tideHeight, from: 0) } },
            onQueueDragEnd: { lift, heading in
                if queueDrag { endTideDrag(opens: heading > tideHeight * 0.3 || lift > tideHeight * 0.25) }
            },
            onOpenPlayingAlbum: openPlayingAlbum,
            lean: lean
        )
    }

    /// Held as a book: Now Playing on the left page, and on the right the bubbles, or
    /// the whole library.
    private func bookLayout(_ geometry: GeometryProxy) -> some View {
        let half = geometry.size.width / 2
        let pull = hingePull
        return HStack(spacing: 0) {
            nowPlayingPane(lean: CGVector(dx: pull, dy: 0), onOpenLibrary: toggleBookLibrary, queueDrag: true)
                .frame(width: half)
                .clipped()
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { nowPlayingPage = $0 }
            ZStack {
                if isBookLibrary {
                    libraryLayer(geometry, lavaPull: CGVector(dx: -pull, dy: 0), dock: AnyView(
                        Button(action: toggleBookLibrary) {
                            Label(String(localized: "liquid.bubbles.back"), systemImage: "circle.grid.3x3.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18)
                                .frame(height: 46)
                                .background(.white.opacity(0.16), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("liquid.bubbles.back")
                    ))
                    .transition(.opacity)
                } else {
                    LiquidBubbleField(
                        musicService: musicService,
                        tab: $bubbleTab,
                        draggedID: carried?.album.id,
                        onPlay: { album, center, diameter in fly(album, from: center, diameter: diameter) },
                        onOpen: openFromBubbles,
                        onDrag: drag,
                        onDrop: drop
                    )
                    .transition(.opacity)
                }
            }
            .frame(width: half)
            .clipped()
        }
        .overlay { GeometryReader { carriedLayer(in: $0) } }
        .ignoresSafeArea()
        .onChange(of: path) { _, path in
            // Back from the page a bubble opened: the bubbles again.
            guard path.isEmpty, isBookLibraryFromBubbles else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                isBookLibrary = false
                isBookLibraryFromBubbles = false
            }
        }
    }

    /// Turned with the fold across: Now Playing above, Up Next's pool (or the library)
    /// below.
    private func laptopLayout(_ geometry: GeometryProxy) -> some View {
        let half = geometry.size.height / 2
        let pull = hingePull
        return VStack(spacing: 0) {
            nowPlayingPane(lean: CGVector(dx: 0, dy: pull), onOpenLibrary: { showBelow(library: true) },
                           queueDrag: false)
                .frame(height: half)
                .clipped()
            Group {
                if isLibraryBelow {
                    libraryLayer(geometry, lavaPull: CGVector(dx: 0, dy: -pull), dock: AnyView(
                        Button { showBelow(library: false) } label: {
                            Label(String(localized: "liquid.pool.title"), systemImage: "drop.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18)
                                .frame(height: 46)
                                .background(.white.opacity(0.16), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("liquid.pool.back")
                    ))
                } else {
                    LiquidPool(musicService: musicService, color: nowPlayingColor,
                               onPick: { offset in musicService.playUpcoming(at: offset) },
                               onNotice: showNotice,
                               onShowLibrary: { showBelow(library: true) })
                }
            }
            .frame(height: half)
            .clipped()
        }
        .ignoresSafeArea()
    }

    // MARK: Bubbles

    /// A bubble on its way into Now Playing, in screen points.
    private struct CarriedBubble {
        let album: AppAlbum
        let diameter: CGFloat
        var center: CGPoint
        /// Where it was in the field, to float back to.
        let origin: CGPoint
        var isTakenIn = false
        /// How far it's been taken in: 0 at the fold, 1 filling Now Playing.
        var takenIn: CGFloat = 0
        var opacity: Double = 1
    }

    /// How far past the fold a bubble's centre goes before Now Playing takes it.
    private static let takeInDepth: CGFloat = 36

    /// Now Playing's library button, held as a book: the right page swaps between the
    /// bubbles and the library.
    private func toggleBookLibrary() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.easeInOut(duration: 0.3)) {
            isBookLibrary.toggle()
            isBookLibraryFromBubbles = false
            path = []
        }
    }

    /// A bubble held, or a show tapped: its page, on the right.
    private func openFromBubbles(_ album: AppAlbum) {
        withAnimation(.easeInOut(duration: 0.3)) {
            path = [.album(album)]
            isBookLibrary = true
            isBookLibraryFromBubbles = true
        }
    }

    private func drag(_ album: AppAlbum, to center: CGPoint, diameter: CGFloat, from origin: CGPoint) {
        if let carried, carried.isTakenIn || carried.album.id != album.id { return }
        var moved = carried ?? CarriedBubble(album: album, diameter: diameter, center: center, origin: origin)
        moved.center = center
        withTransaction(Transaction(animation: nil)) { carried = moved }
        if center.x < nowPlayingPage.maxX - Self.takeInDepth { takeIn() }
    }

    /// Let go: heading past the fold, it's taken in; short of it, it floats back.
    private func drop(_ album: AppAlbum, heading: CGPoint) {
        guard let carried, !carried.isTakenIn, carried.album.id == album.id else { return }
        if heading.x < nowPlayingPage.maxX - Self.takeInDepth {
            takeIn()
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
                self.carried?.center = carried.origin
            } completion: {
                if self.carried?.isTakenIn == false { self.carried = nil }
            }
        }
    }

    /// A bubble tapped: it flies to the fold, and is taken in.
    private func fly(_ album: AppAlbum, from center: CGPoint, diameter: CGFloat) {
        guard carried == nil else { return }
        carried = CarriedBubble(album: album, diameter: diameter, center: center, origin: center)
        let fold = CGPoint(x: nowPlayingPage.maxX - Self.takeInDepth - 1,
                           y: min(max(center.y, nowPlayingPage.minY + diameter), nowPlayingPage.maxY - diameter))
        if reduceMotion {
            carried?.center = fold
            takeIn()
            return
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            carried?.center = fold
        } completion: {
            takeIn()
        }
    }

    /// Now Playing takes the bubble in: it slips through the fold, swells to fill the
    /// page and clears, and its album plays.
    private func takeIn() {
        guard var taken = carried, !taken.isTakenIn else { return }
        taken.isTakenIn = true
        withTransaction(Transaction(animation: nil)) { carried = taken }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let album = taken.album
        Task {
            let loaded = await library.tracks(for: album)
            let tracks = loaded.isEmpty ? album.tapeSongs(album.preloadedTracks) : loaded
            play(album, tracks, 0, whole: true, in: bounds.size, floods: false)
        }
        let page = nowPlayingPage
        withAnimation(.easeIn(duration: reduceMotion ? 0.01 : 0.45)) {
            carried?.center = CGPoint(x: page.midX, y: page.midY)
            carried?.takenIn = 1
        } completion: {
            withAnimation(.easeOut(duration: 0.3)) {
                carried?.opacity = 0
            } completion: {
                carried = nil
            }
        }
    }

    /// The bubble being carried, over both pages; reaching for the fold, Now Playing's
    /// edge swells out to meet it, joining it as two drops of water do.
    @ViewBuilder
    private func carriedLayer(in proxy: GeometryProxy) -> some View {
        if let carried {
            let origin = proxy.frame(in: .global).origin
            let center = CGPoint(x: carried.center.x - origin.x, y: carried.center.y - origin.y)
            let fold = nowPlayingPage.maxX - origin.x
            let r = carried.diameter / 2
            // Big enough, from Now Playing's middle, to cover it.
            let cover = hypot(nowPlayingPage.width, nowPlayingPage.height) / carried.diameter
            ZStack(alignment: .topLeading) {
                if !carried.isTakenIn {
                    membrane(fold: fold, bubble: center, radius: r)
                }
                LiquidBubble(album: carried.album, diameter: carried.diameter)
                    .scaleEffect(1.06 + (cover - 1) * carried.takenIn)
                    .position(center)
                    .opacity(carried.opacity)
                    // Taken in, all that's past the fold is inside Now Playing.
                    .mask(alignment: .topLeading) {
                        Rectangle().frame(width: carried.isTakenIn
                                          ? fold + (1 - carried.takenIn) * carried.diameter
                                          : proxy.size.width)
                    }
            }
            .allowsHitTesting(false)
        }
    }

    /// Now Playing's edge at the fold, as a line of water down it, swelling out toward
    /// the bubble the nearer it comes and running into it: clear, with a bright rim.
    private func membrane(fold: CGFloat, bubble: CGPoint, radius: CGFloat) -> some View {
        let gap = max(0, bubble.x - radius - fold)
        let near = max(0, min(1, 1 - gap / 150))
        /// The water's shapes, drawn `inset` points thinner all round.
        func water(inset: CGFloat) -> some View {
            Canvas { context, size in
                context.addFilter(.alphaThreshold(min: 0.5, color: .white))
                context.addFilter(.blur(radius: 14))
                context.drawLayer { layer in
                    // Past both ends of the screen, so the line has no ends to round.
                    layer.fill(Path(CGRect(x: fold - 13 + inset, y: -60, width: 26 - inset * 2, height: size.height + 120)),
                               with: .color(.white))
                    let swell = (14 + 26 * near) - inset
                    let reach = fold + gap * 0.6 * near
                    layer.fill(Path(ellipseIn: CGRect(x: reach - swell, y: bubble.y - swell * 2.1,
                                                      width: swell * 2, height: swell * 4.2)),
                               with: .color(.white))
                    let r = radius - inset
                    layer.fill(Path(ellipseIn: CGRect(x: bubble.x - r, y: bubble.y - r, width: r * 2, height: r * 2)),
                               with: .color(.white))
                }
            }
        }
        return ZStack {
            // The body of the water, barely tinted, and its rim.
            water(inset: 0).opacity(0.14)
            ZStack {
                water(inset: 0)
                water(inset: 2.5).blendMode(.destinationOut)
            }
            .compositingGroup()
            .opacity(0.75)
        }
        .shadow(color: .white.opacity(0.35), radius: 6)
        .accessibilityHidden(true)
    }

    /// Below the fold: the library, or Up Next's pool, flooding from one to the other.
    private func showBelow(library: Bool) {
        guard library != isLibraryBelow else { return }
        floodAction(library ? .liquidGround : nowPlayingColor, nil) { isLibraryBelow = library }
    }

    /// Waits for the screen to be left alone (a Duo stood half open, the music playing),
    /// then brings up the visualizer.
    private func watchForRest() async {
        guard foldMonitor.isPartlyOpen, musicService.isPlaying, !UIAccessibility.isVoiceOverRunning else { return }
        var restAfter: TimeInterval = 20
        #if DEBUG
        // `-LiquidRestSeconds 2`, for screenshots and UI tests.
        if UserDefaults.standard.object(forKey: "LiquidRestSeconds") != nil {
            restAfter = UserDefaults.standard.double(forKey: "LiquidRestSeconds")
        }
        #endif
        while !Task.isCancelled {
            let idle = Date().timeIntervalSince(LiquidTouchTracker.shared.lastTouchTime)
            if idle >= restAfter, !isVisualizing, !isTideShown, !showSettings {
                isVisualizing = true
            }
            try? await Task.sleep(for: .seconds(max(1, min(5, restAfter - idle))))
        }
    }

    /// What, changing, means tempos are to be asked for again.
    private struct TempoLookupKey: Equatable {
        let playing: String?
        let songs: Int
        let isOn: Bool
    }

    private func lookUpTempos() {
        // UI tests run without the network's say-so: no lookups there.
        guard themeSettings.liquidTempoLookup, !AppEnvironment.isUITesting else {
            SongTempos.shared.stop()
            return
        }
        SongTempos.shared.lookUp(musicService.nowPlayingTrack, then: musicService.songs)
    }

    private func wakeFromVisualizer() {
        LiquidTouchTracker.shared.lastTouchTime = Date()
        isVisualizing = false
    }

    private func reportLocation() {
        let current = screen ?? (musicService.nowPlayingTrack != nil ? .nowPlaying : .library)
        LiquidLocation.shared.update(screenIsLibrary: current == .library, path: path)
    }

    /// The album, playlist or show playing, as the library has it.
    private var playingAlbum: AppAlbum? {
        if let show = musicService.currentPodcastShowTitle {
            return library.podcasts.first { $0.title == show }
        }
        if let playlist = musicService.currentPlaylistID {
            return library.mixtapes.first { $0.mixtape?.id == playlist }
        }
        guard let track = musicService.nowPlayingTrack else { return nil }
        let title = TapeFormat.displayTitle(track.albumTitle)
        let albums = library.albums.filter { $0.tapeTitle == title }
        return albums.first { $0.artistName == track.artistName } ?? albums.first
    }

    /// Floods from Now Playing into the page of the album playing.
    private func openPlayingAlbum() {
        guard let album = playingAlbum else {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.4)
            return
        }
        Task {
            let color = await LiquidColors.shared.color(for: album)
            floodAction(color.liquidDeep, nil) {
                screen = .library
                path = [.album(album)]
            }
        }
    }

    /// How tall the tide stands open.
    private var tideHeight: CGFloat { max(1, LiquidTideView.height(in: bounds.height)) }

    private func openTide() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        isTideShown = true
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { tideProgress = 1 }
    }

    private func closeTide() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) {
            tideProgress = 0
        } completion: {
            // Unless a finger has caught it on the way down.
            if tideProgress == 0, tideDragStart == nil { isTideShown = false }
        }
    }

    /// A finger moving the tide to `progress`; `start` is where it was when the finger
    /// took hold.
    private func dragTide(to progress: CGFloat, from start: CGFloat) {
        if tideDragStart == nil { tideDragStart = start }
        isTideShown = true
        withTransaction(Transaction(animation: nil)) { tideProgress = min(1, max(0, progress)) }
    }

    private func endTideDrag(opens: Bool) {
        tideDragStart = nil
        opens ? openTide() : closeTide()
    }

    /// Let go of Now Playing: far enough down, or flicked, it slides away to the library
    /// page you came from; else it springs back.
    private func endDismiss(drop: CGFloat, heading: CGFloat) {
        guard drop > 0 else { return }
        if drop > 140 || heading > 420 {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.easeOut(duration: 0.26)) {
                nowPlayingDrop = bounds.height + 40
            } completion: {
                withTransaction(Transaction(animation: nil)) {
                    screen = .library
                    nowPlayingDrop = 0
                }
            }
        } else {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { nowPlayingDrop = 0 }
        }
    }

    // MARK: Playing

    /// Plays from the library, asking first if it would clear songs queued by hand, and
    /// floods into Now Playing in the album's colour (unless a bubble's being taken in,
    /// which is its own way in).
    private func play(_ album: AppAlbum, _ tracks: [AppTrack], _ index: Int, whole: Bool, in size: CGSize,
                      floods: Bool = true) {
        guard tracks.indices.contains(index) else { return }
        let queued = whole ? tracks : [tracks[index]]
        musicService.play(asking: { pendingPlay = $0 }, addToQueue: album.isPodcast ? nil : {
            queue(queued, .last, whole ? album.tapeTitle : tracks[index].title)
        }) {
            Task {
                if floods {
                    let color = await LiquidColors.shared.color(for: album)
                    floodAction(color.liquidDeep, nil) { screen = .nowPlaying }
                }
                if await library.play(album, tracks: tracks, startingAt: index) != .started {
                    showNotice(String(localized: "playback.nothingPlayable"))
                }
            }
        }
    }

    /// Plays a list of songs (every song, the recently played or added) from `index`,
    /// asking first as an album does, and floods into Now Playing in that song's colour.
    private func playSongs(_ tracks: [AppTrack], _ index: Int, whole: Bool, _ name: String) {
        guard tracks.indices.contains(index) else { return }
        let queued = whole ? tracks : [tracks[index]]
        musicService.play(asking: { pendingPlay = $0 }, addToQueue: {
            queue(queued, .last, whole ? name : tracks[index].title)
        }) {
            Task {
                let color = await LiquidColors.shared.color(for: tracks[index])
                floodAction(color.liquidDeep, nil) { screen = .nowPlaying }
                if await musicService.play(tracks: tracks, startingAt: index) != .started {
                    showNotice(String(localized: "playback.nothingPlayable"))
                }
            }
        }
    }

    private func queue(_ tracks: [AppTrack], _ placement: QueuePlacement, _ name: String) {
        Task {
            let outcome = await musicService.addToQueue(tracks: tracks, placement: placement)
            if !outcome.succeeded {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.4)
            }
            showNotice(outcome.message(name: name, requested: tracks.count, placement: placement,
                                       isCollection: tracks.count > 1))
        }
    }

    /// Long enough to read. Under a UI test it stays up longer: XCUITest waits for the
    /// app to go idle before the tap that queued something returns, and on the lava
    /// screen that can take most of 2.5 seconds, so the test sometimes looked after
    /// the notice had already gone.
    private static let noticeDuration: Duration = AppEnvironment.isUITesting ? .seconds(10) : .seconds(2.5)

    private func showNotice(_ text: String) {
        noticeTask?.cancel()
        notice = text
        noticeTask = Task {
            try? await Task.sleep(for: Self.noticeDuration)
            guard !Task.isCancelled else { return }
            notice = nil
        }
    }
}
