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
//                   Playing; a side bar of sections down the status bar's column
//   turned, fold    the book turned: Now Playing above the fold, the side bar's
//   across          section below it, a bubble dragged up across the fold
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
    /// Which flood is the latest, and the change waiting under it.
    @State private var floodGeneration = 0
    @State private var floodChange: (() -> Void)?
    @State private var showSettings = false
    @State private var showPodcastSearch = false
    @State private var pendingPlay: PendingPlay?
    @State private var notice: String?
    @State private var noticeTask: Task<Void, Never>?
    /// iPhone Duo open: whether the fold is across the middle (Now Playing above it) or
    /// down it (Now Playing on the left), for which way a bubble crosses it.
    private var foldIsAcross: Bool { duoLayout(for: bounds.size) == .laptop }
    /// Open: where the section page is on screen, and where on it the bubble whose page is
    /// open was held, for that page to grow out of it and go back into it.
    @State private var sectionFrame: CGRect = .zero
    @State private var bubbleZoomAnchor: UnitPoint?
    /// The water at the fold (FoldWater): droplets falling back into it, the ink of a
    /// bubble taken in, and when the surface last rippled from a bubble pressing on it.
    @State private var foldDroplets: [FoldWater.Droplet] = []
    @State private var ink: FoldWater.Ink?
    @State private var lastPressRipple = Date.distantPast
    /// A held bubble's songs spread around it (TrackSpread); where the finger had gone
    /// before they'd come; and whether a carried one is over the fold, felt once.
    @State private var spread: TrackSpread?
    /// Bumped as Up Next's bubble swallows a carried bubble, for its gulp.
    @State private var fieldUpNextGulps = 0
    @State private var pendingSpreadFinger: CGPoint?
    @State private var spreadPastFold = false
    /// `-LiquidInkShot`: the ink held this far through its spread, for screenshots.
    @State private var inkShotProgress: Double?
    /// The visualizer, while the Duo stands half open, left alone.
    @State private var isVisualizing = false
    /// iPhone Duo held as a book: the whole library on the right page, not the bubbles.
    /// Held as a book: the section the side bar has open on the right-hand page.
    @AppStorage("LiquidBookSection") private var bookSection: BookSection = .albums
    /// The side bar's fifth button: whichever of the sections that aren't always there
    /// (Playlists, Podcasts, Discover, the recent lists) was opened last.
    @AppStorage("LiquidBookRecent") private var bookRecent: BookSection = .playlists
    /// The library came up from a bubble held: going back from its page goes back to them.
    /// A bubble on its way into Now Playing: dragged, flying after a tap, or taken in.
    @State private var carried: CarriedBubble?
    /// Now Playing's page, on screen, for a bubble to be taken into.
    /// Where Now Playing is on screen in each open layout, kept apart: turning the phone,
    /// the layout going away still reports where it was after the new one has, and one
    /// shared frame was left the old layout's (the ink then spread through the wrong half).
    @State private var nowPlayingInBook: CGRect = .zero
    @State private var nowPlayingTurned: CGRect = .zero
    /// Where Now Playing is on screen, in the layout showing.
    private var nowPlayingPage: CGRect { foldIsAcross ? nowPlayingTurned : nowPlayingInBook }
    /// A bubble just taken in, for Now Playing to ripple where it went in.
    @State private var splash: LiquidSplash?
    @Environment(\.windowSafeArea) private var safeArea
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var library: ShelfLibrary { ShelfLibrary(musicService: musicService) }

    var body: some View {
        playerBody
            // LYRE-41: switched to from another player, Liquid opens that section's list
            // on the cover (or song) it was left on there. The lists themselves tell
            // where they are (LiquidPlace), so there's nothing to tell from here.
            .modifier(HandsOverBrowsing(position: nil, adopt: adoptBrowsePosition))
    }

    private func adoptBrowsePosition(_ position: BrowsePosition) {
        let (list, route) = LiquidPlace.list(for: position.shelf)
        if let id = position.itemID { LiquidPlace.handOver(id, list: list) }
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            screen = .library
            if let section = BookSection(route: route) { chooseBookSection(section) }
            path = [route]
        }
    }

    private var playerBody: some View {
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
                        onOpenQueue: { openTide() },
                        onOpenSettings: { showSettings = true },
                        onQueueDrag: { lift in dragTide(to: lift / tideHeight, from: 0) },
                        onQueueDragEnd: { lift, heading, speed in
                            endTideDrag(opens: heading > tideHeight * 0.3 || lift > tideHeight * 0.25,
                                        speed: speed / tideHeight)
                        },
                        onOpenPlayingAlbum: openPlayingAlbum,
                        onDismissDrag: { drop in nowPlayingDrop = drop },
                        onDismissDragEnd: { drop, heading, speed in endDismiss(drop: drop, heading: heading, speed: speed) }
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
                        onClose: { closeTide() },
                        onNotice: showNotice,
                        onDrag: { drop in dragTide(to: 1 - max(0, drop) / tideHeight, from: 1) },
                        onDragEnd: { drop, heading, speed in
                            endTideDrag(opens: !(drop > 120 || heading > 260), speed: -speed / tideHeight)
                        }
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
                        .lyreFont(size: 13, weight: .semibold, maxScale: 1.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .lyreFill(.black, 0.75, in: Capsule())
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
        // A song added to the library from a list, or why it couldn't be (LibraryAdder).
        .onReceive(LibraryAdder.shared.$notice) { if let notice = $0 { showNotice(notice.text) } }
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
            // `-LiquidBubblePress 30` presses it that far into the surface instead.
            let defaults = UserDefaults.standard
            if defaults.object(forKey: "LiquidBubbleShot") != nil || defaults.object(forKey: "LiquidBubblePress") != nil,
               let album = library.albums.first {
                let gap = defaults.object(forKey: "LiquidBubblePress") != nil
                    ? -CGFloat(defaults.double(forKey: "LiquidBubblePress"))
                    : CGFloat(defaults.double(forKey: "LiquidBubbleShot"))
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    let diameter: CGFloat = 120
                    // Negative: pressed into the surface that far, held back as a finger would be.
                    let raw = -gap
                    let shown = FoldWater.shownPush(raw, radius: diameter / 2)
                    let center = CGPoint(x: nowPlayingPage.maxX + diameter / 2 - shown, y: nowPlayingPage.midY)
                    var shot = CarriedBubble(album: album, diameter: diameter, center: center, origin: center)
                    shot.push = raw
                    _ = shot.neck.update(gap: max(0, -shown), radius: diameter / 2)
                    carried = shot
                }
            }
            // `-LiquidInkShot 0.4` holds the ink of a bubble taken in that far through its
            // spread, from the fold's middle, for screenshots.
            if defaults.object(forKey: "LiquidInkShot") != nil, let album = library.albums.first {
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    let color = await LiquidColors.shared.color(for: album)
                    inkShotProgress = defaults.double(forKey: "LiquidInkShot")
                    ink = FoldWater.Ink(origin: contact(at: CGPoint(x: nowPlayingPage.maxX, y: nowPlayingPage.midY)).screen,
                                        color: color)
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
            case "recentlyPlayed":
                screen = .library
                path = [.recentlyPlayed]
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
    /// covers the screen, makes `change` under it, and lets it clear.
    ///
    /// A flood is never waited on: asked for again while one is spreading, it takes the
    /// new colour and the new change (the newer touch is what was meant); asked for while
    /// one is clearing, it fills back in from where it is and clears again over the new
    /// change. Each flood's completions check they're still the latest before acting.
    ///
    /// Open, an iPhone Duo has Now Playing and the library side by side: there's nothing
    /// to flood between, and a flood would cover both pages. The change is made where it
    /// is, the page moving by its own push, or a bubble's zoom.
    private func floodAction(_ color: Color, _ origin: CGPoint?, _ change: @escaping () -> Void) {
        if duoLayout(for: bounds.size) != nil {
            change()
            return
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        var instant = Transaction()
        instant.disablesAnimations = true
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.25)) { change() }
            return
        }
        floodGeneration += 1
        let generation = floodGeneration
        floodChange = change
        if let current = flood {
            // Caught mid-way: the same water, recoloured, carried on from where it is.
            flood = Flood(color: color, origin: current.origin, diameter: current.diameter,
                          scale: current.scale, opacity: current.opacity)
        } else {
            let size = bounds.size
            // An origin given is on the screen (global); either way, into the player's space.
            let touch = (origin ?? LiquidTouchTracker.shared.lastTouch).map {
                CGPoint(x: $0.x - bounds.minX, y: $0.y - bounds.minY)
            } ?? CGPoint(x: size.width / 2, y: size.height / 2)
            // Large enough, centred on the touch, to reach the furthest corner.
            let reach = max(hypot(touch.x, touch.y), hypot(size.width - touch.x, touch.y),
                            hypot(touch.x, size.height - touch.y), hypot(size.width - touch.x, size.height - touch.y))
            flood = Flood(color: color, origin: touch, diameter: reach * 2 + 40)
        }
        // What's left of the spread (all of it, for a new flood) takes its share of the time.
        let left = 1 - (flood?.scale ?? 0.01) * CGFloat(flood?.opacity ?? 1)
        withAnimation(.easeIn(duration: Self.floodIn * max(0.3, left))) {
            flood?.scale = 1
            flood?.opacity = 1
        } completion: {
            guard generation == floodGeneration else { return }
            let pending = floodChange
            floodChange = nil
            withTransaction(instant) { pending?() }
            withAnimation(.easeOut(duration: Self.floodOut)) {
                flood?.opacity = 0
            } completion: {
                if generation == floodGeneration { flood = nil }
            }
        }
    }

    /// The flood's two halves: spreading, and clearing.
    private static let floodIn = 0.32
    private static let floodOut = 0.28

    /// The library, with what's playing docked at the bottom as a droplet (on a Duo's
    /// split screen, where Now Playing is in view, the droplet's place is `dock`'s).
    /// The library; `besideNowPlaying` on an open Duo, where Now Playing is already in view:
    /// no droplet to flood back into it, and no room kept for one.
    private func libraryLayer(_ geometry: GeometryProxy, lavaPull: CGVector = .zero,
                              besideNowPlaying: Bool = false, rootDepth: Int = 0) -> some View {
        LiquidLibraryView(
            musicService: musicService,
            path: $path,
            onPlay: { album, tracks, index, whole in play(album, tracks, index, whole: whole, in: geometry.size) },
            onPlaySongs: playSongs,
            onQueue: queue,
            onFindShows: { showPodcastSearch = true },
            onOpenSettings: { showSettings = true },
            themeSettings: themeSettings,
            bottomInset: musicService.nowPlayingTrack != nil && !besideNowPlaying ? 104 + safeArea.bottom : safeArea.bottom,
            lavaPull: lavaPull,
            onNotice: showNotice,
            rootDepth: rootDepth
        )
        .overlay(alignment: .bottom) {
            if !besideNowPlaying {
                LiquidDroplet(musicService: musicService) { _ in
                    flood(nowPlayingColor, in: geometry) { screen = .nowPlaying }
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
                                queueDrag: Bool, railEdge: HorizontalEdge? = .trailing,
                                showsLibraryButton: Bool = true) -> some View {
        LiquidNowPlayingView(
            musicService: musicService,
            themeSettings: themeSettings,
            onOpenLibrary: onOpenLibrary,
            onOpenQueue: { openTide() },
            onOpenSettings: { showSettings = true },
            onQueueDrag: { lift in if queueDrag { dragTide(to: lift / tideHeight, from: 0) } },
            onQueueDragEnd: { lift, heading, speed in
                if queueDrag {
                    endTideDrag(opens: heading > tideHeight * 0.3 || lift > tideHeight * 0.25, speed: speed / tideHeight)
                }
            },
            onOpenPlayingAlbum: openPlayingAlbum,
            lean: lean,
            splash: splash,
            railEdge: railEdge,
            showsLibraryButton: showsLibraryButton
        )
    }

    /// Held as a book: Now Playing on the left page, and on the right the section the side
    /// bar has open: the albums, playlists or shows as bubbles, or the songs, artists,
    /// search, Discover and the recent lists as the library's pages. The side bar, down
    /// the status bar's column, is the way round the library; Now Playing keeps its own
    /// buttons, down its left edge.
    private func bookLayout(_ geometry: GeometryProxy) -> some View {
        let half = geometry.size.width / 2
        let pull = hingePull
        let inColumn = SideRail.isOn(safeArea)
        let height = geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
        // Under the status bar's reserve as usual; in a short window (stood as a tent),
        // from just under the clock, closer together, and with what still doesn't fit in "…".
        let usual = height - SideRail.statusReserve - safeArea.bottom - 12
        let top = BookSection.fitted(recent: bookRecent, height: usual).spacing == 14
            ? SideRail.statusReserve : SideRail.stripTop
        let bar = BookSection.fitted(recent: bookRecent, height: height - top - safeArea.bottom - 12)
        return HStack(spacing: 0) {
            Group {
                // Stood half open (as a tent, on a table): the song as the visualizer has
                // it, with what it needs to be played.
                if foldMonitor.isPartlyOpen {
                    standingNowPlaying
                } else {
                    nowPlayingPane(lean: CGVector(dx: pull, dy: 0), onOpenLibrary: {}, queueDrag: true,
                                   railEdge: .leading, showsLibraryButton: false)
                }
            }
            .frame(width: half)
            .clipped()
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { nowPlayingInBook = $0 }
            sectionPage(geometry, lavaPull: CGVector(dx: -pull, dy: 0), barInColumn: inColumn)
                .frame(width: half)
                .clipped()
        }
        // The side bar: the sections first, as navigation goes, the rest in "…".
        .overlay {
            if inColumn {
                SideRailButtons(spacing: bar.spacing, top: top) {
                    bookSectionButtons(bar: bar.bar, more: bar.more)
                }
            }
        }
        .overlay { GeometryReader { spreadLayer(in: $0) } }
        .overlay { GeometryReader { carriedLayer(in: $0) } }
        .ignoresSafeArea()
    }

    /// Turned with the fold across: the book turned. Now Playing above the fold, and below
    /// it the section the side bar has open, the side bar down that half's right edge.
    /// Up Next is pulled up over both, as on any phone; a bubble is dragged up across the
    /// fold into Now Playing as it's dragged left across it held as a book.
    private func laptopLayout(_ geometry: GeometryProxy) -> some View {
        let half = (geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom) / 2
        let pull = hingePull
        return ZStack {
            // Its buttons in its own row, as on any phone: the half is too short for them
            // down an edge.
            nowPlayingPane(lean: CGVector(dx: 0, dy: pull), onOpenLibrary: {}, queueDrag: true,
                           railEdge: nil, showsLibraryButton: false)
                .frame(height: half)
                .clipped()
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { nowPlayingTurned = $0 }
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()
            // Laid from the bottom, not under a view that leaves out the top's safe area:
            // a library page there would have its list run up under the fold.
            sectionPage(geometry, lavaPull: CGVector(dx: 0, dy: -pull), barInColumn: false)
                .frame(height: half)
                .clipped()
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: [.bottom, .horizontal])
        }
        .overlay { GeometryReader { spreadLayer(in: $0) }.ignoresSafeArea() }
        .overlay { GeometryReader { carriedLayer(in: $0) }.ignoresSafeArea() }
    }

    /// The page the side bar opens sections on, open either way: the albums, playlists or
    /// shows as bubbles, or the library's page for the rest. Its side bar is in the status
    /// column (`barInColumn`), or down the page's own right edge.
    private func sectionPage(_ geometry: GeometryProxy, lavaPull: CGVector, barInColumn: Bool) -> some View {
        let tab = bookSection.bubbleTab
        return HStack(spacing: 0) {
            ZStack {
                if let tab, path.isEmpty {
                    LiquidBubbleField(
                        musicService: musicService,
                        tab: Binding(get: { tab }, set: { chooseBookSection(BookSection(tab: $0)) }),
                        draggedID: carried?.album.id,
                        onPlay: { album, center, diameter in fly(album, from: center, diameter: diameter) },
                        onOpen: openFromBubbles,
                        onDrag: drag,
                        onDrop: { album, heading, velocity in drop(album, heading: heading, velocity: velocity) },
                        showsTabBar: false,
                        keepsClearOfColumn: barInColumn,
                        onFindShows: { showPodcastSearch = true },
                        onSpread: beginSpread,
                        onSpreadMove: moveSpread,
                        onSpreadEnd: endSpread,
                        pullDirection: foldIsAcross ? nil : CGVector(dx: -1, dy: 0)
                    )
                    .transition(.opacity)
                } else {
                    libraryLayer(geometry, lavaPull: lavaPull,
                                 besideNowPlaying: true, rootDepth: tab == nil ? 1 : 0)
                        .transition(tab != nil && bubbleZoomAnchor != nil
                                    ? .scale(scale: 0.12, anchor: bubbleZoomAnchor ?? .center).combined(with: .opacity)
                                    : .opacity)
                }
            }
            // Back to the bubbles however the page was left (its back button, the swipe).
            .animation(LyreMotion.light, value: path.isEmpty)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { sectionFrame = $0 }
            // Without a status bar's column, the sections stand down the page's own right
            // edge, beside what they open rather than over it.
            if !barInColumn {
                GeometryReader { strip in
                    let bar = BookSection.fitted(recent: bookRecent, height: strip.size.height - 16)
                    VStack(spacing: bar.spacing) { bookSectionButtons(bar: bar.bar, more: bar.more) }
                        .frame(width: 58, height: strip.size.height)
                }
                .frame(width: 58)
                .frame(maxHeight: .infinity)
                .background(Color.white.opacity(0.04))
            }
        }
        // The page's own buttons (the way back, an album's) stand on the page: the column
        // is the side bar's sections and nothing else. Below the fold there's no status
        // bar to keep clear of, so they stand near the page's top.
        .environment(\.sideRailHoldsPageButtons, false)
        .environment(\.liquidPageTop, foldIsAcross ? 12 : 56)
        // Opened on a section of pages (the one last open): its page, not the lava menu.
        .onAppear {
            if path.isEmpty, bookSection.bubbleTab == nil { path = [bookSection.route] }
        }
        .onChange(of: path) { _, path in
            // Back from an album opened from the bubbles: the bubbles again. A section
            // of pages can't be gone back from (it's the bottom page; rootDepth).
            if path.isEmpty, bookSection.bubbleTab == nil {
                self.path = [bookSection.route]
            }
        }
    }

    /// The side bar's sections, and "…" for the rest.
    @ViewBuilder private func bookSectionButtons(bar: [BookSection], more: [BookSection]) -> some View {
        ForEach(bar) { section in
            Button { openBookSection(section) } label: {
                Image(systemName: section.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(section == bookSection ? Color.black : Color.white.opacity(0.75))
                    .frame(width: 44, height: 44)
                    .background(section == bookSection ? Color.white : Color.white.opacity(0.1), in: Circle())
            }
            .buttonStyle(LyrePressStyle())
            .accessibilityLabel(section.title)
            .accessibilityAddTraits(section == bookSection ? .isSelected : [])
            .accessibilityIdentifier("liquid.book.\(section.rawValue)")
        }
        let moreIsOpen = more.contains(bookSection)
        Menu {
            ForEach(more) { section in
                Button { openBookSection(section) } label: {
                    Label(section.title, systemImage: section.symbol)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(moreIsOpen ? Color.black : Color.white.opacity(0.75))
                .frame(width: 44, height: 44)
                .background(moreIsOpen ? Color.white : Color.white.opacity(0.1), in: Circle())
        }
        .accessibilityLabel(String(localized: "sideRail.more"))
        .accessibilityValue(moreIsOpen ? bookSection.title : "")
        .accessibilityIdentifier("liquid.book.more")
    }

    /// Held as a book but stood half open (as a tent on a table): Now Playing as the
    /// visualizer shows the song, the cover in the middle with rings on the beat, with its
    /// title, the keys to play it, and Now Playing's own buttons down the left edge.
    private var standingNowPlaying: some View {
        LiquidVisualizer(musicService: musicService, onWake: {}, standing: true, onOpenQueue: { openTide() })
            .overlay(alignment: .topLeading) {
                VStack(spacing: 14) {
                    LiquidNowPlayingButtons(part: .rest, track: musicService.nowPlayingTrack, themeSettings: themeSettings,
                                            onOpenLibrary: {}, onOpenSettings: { showSettings = true })
                }
                .frame(width: SideRail.leadingWidth)
                .padding(.top, max(safeArea.top, 20) + 20)
            }
            .ignoresSafeArea()
    }

    /// A section opened: one of the sections that aren't always in the side bar takes its
    /// fifth button, so the one last used is a tap away. The four that are always there
    /// never move, so they stay where the thumb expects them.
    private func chooseBookSection(_ section: BookSection) {
        bookSection = section
        if BookSection.rotating.contains(section) { bookRecent = section }
    }

    /// A section chosen in the side bar: its bubbles, or its page at the bottom of the
    /// right-hand page's own pages.
    private func openBookSection(_ section: BookSection) {
        UISelectionFeedbackGenerator().selectionChanged()
        bubbleZoomAnchor = nil
        withAnimation(.easeInOut(duration: 0.25)) {
            chooseBookSection(section)
            path = section.bubbleTab == nil ? [section.route] : []
        }
    }

    // MARK: Bubbles

    /// A bubble on its way into Now Playing, in screen points.
    private struct CarriedBubble {
        let album: AppAlbum
        let diameter: CGFloat
        /// Where it's drawn: where the finger has it, held back by the surface at the fold.
        var center: CGPoint
        /// Where the finger has it.
        var finger: CGPoint
        /// Where it was in the field, to float back to.
        let origin: CGPoint
        /// How far its leading edge is pushed past the fold (FoldWater): negative short of it.
        var push: CGFloat = -.greatestFiniteMagnitude
        var neck = FoldWater.Neck()
        /// The surface has given way: it's under the water, still held, waiting to be let go.
        var isThrough = false
        var isTakenIn = false
        /// How far it's gone in, 0 at the surface giving way to 1 dissolved.
        var takenIn: CGFloat = 0
        var opacity: Double = 1
        /// How fast it's moving (points a second), eased over the last few moves: what
        /// it's drawn out along.
        var velocity: CGPoint = .zero
        var movedAt = Date()
        /// It's touched the water at the fold (felt once, as a soft tap).
        var hasTouched = false
        /// Its album's colour, for the ink it becomes in Now Playing.
        var color: Color?
        /// Carried by a finger (not flown there by a tap): Up Next's bubble comes up.
        var isDragged = false
        /// Over Up Next's bubble: let go, it joins Up Next (felt once on the way in).
        var isOverUpNext = false
        /// Let go on Up Next's bubble, and going down into it.
        var isQueued = false

        init(album: AppAlbum, diameter: CGFloat, center: CGPoint, origin: CGPoint) {
            self.album = album
            self.diameter = diameter
            self.center = center
            self.finger = center
            self.origin = origin
        }
    }

    /// How far a point is past the fold, into Now Playing: across it held as a book (to
    /// the left), or up across it turned. Negative still on the bubbles' side.
    private func pastFold(_ point: CGPoint) -> CGFloat {
        foldIsAcross ? nowPlayingPage.maxY - point.y : nowPlayingPage.maxX - point.x
    }

    /// `point` moved `distance` on the way into Now Playing (back out, negative).
    private func movedIn(_ point: CGPoint, by distance: CGFloat) -> CGPoint {
        foldIsAcross ? CGPoint(x: point.x, y: point.y - distance) : CGPoint(x: point.x - distance, y: point.y)
    }

    /// Where a bubble at `center` meets the fold: in Now Playing's own points, and on screen.
    private func contact(at center: CGPoint) -> (local: CGPoint, screen: CGPoint) {
        let page = nowPlayingPage
        let local = foldIsAcross
            ? CGPoint(x: min(max(center.x - page.minX, 0), page.width), y: page.height - 6)
            : CGPoint(x: page.width - 6, y: min(max(center.y - page.minY, 0), page.height))
        return (local, CGPoint(x: page.minX + local.x, y: page.minY + local.y))
    }

    /// How far past the fold a tapped bubble flies before it's taken in.
    private static let takeInDepth: CGFloat = 36

    /// A bubble held, or a show tapped: its page, on the right.
    private func openFromBubbles(_ album: AppAlbum) {
        // Out of the bubble held: grown from where it was, and gone back into it.
        bubbleZoomAnchor = anchor(in: sectionFrame, at: LiquidTouchTracker.shared.lastTouch)
        withAnimation(LyreMotion.light) { path = [.album(album)] }
    }

    /// A touch on the screen as a point in `frame` (its middle, without one).
    private func anchor(in frame: CGRect, at touch: CGPoint?) -> UnitPoint {
        guard let touch, frame.width > 0, frame.height > 0 else { return .center }
        return UnitPoint(x: min(max((touch.x - frame.minX) / frame.width, 0), 1),
                         y: min(max((touch.y - frame.minY) / frame.height, 0), 1))
    }

    /// A new bubble picked up: its colour looked up for the ink, while it's carried.
    private func pickUp(_ bubble: CarriedBubble) -> CarriedBubble {
        let id = bubble.album.id
        Task {
            let color = await LiquidColors.shared.color(for: bubble.album)
            if carried?.album.id == id { carried?.color = color }
        }
        return bubble
    }

    private func drag(_ album: AppAlbum, to center: CGPoint, diameter: CGFloat, from origin: CGPoint) {
        if let carried, carried.isTakenIn || carried.album.id != album.id { return }
        var moved = carried ?? pickUp(CarriedBubble(album: album, diameter: diameter, center: center, origin: origin))
        let r = diameter / 2
        // Its speed, eased over the last few moves so one jittery frame doesn't jerk it.
        let now = Date()
        let dt = now.timeIntervalSince(moved.movedAt)
        if dt > 0.001, dt < 0.2 {
            let instant = CGPoint(x: (center.x - moved.finger.x) / dt, y: (center.y - moved.finger.y) / dt)
            moved.velocity = CGPoint(x: moved.velocity.x * 0.6 + instant.x * 0.4, y: moved.velocity.y * 0.6 + instant.y * 0.4)
        }
        moved.movedAt = now
        moved.finger = center
        moved.isDragged = true
        // Over Up Next's bubble (not a show's: its episodes don't queue): felt once.
        let overUpNext = !album.isPodcast && fieldUpNextCatches(center)
        if overUpNext != moved.isOverUpNext {
            moved.isOverUpNext = overUpNext
            if overUpNext { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.8) }
        }
        let raw = pastFold(center) + r
        // Through the surface, it goes where the finger takes it, under the water, until
        // it's let go; carried all the way back out, the surface closes behind it.
        if moved.isThrough {
            moved.push = raw
            moved.center = center
            if raw < -4 { moved.isThrough = false }
            withTransaction(Transaction(animation: nil)) { carried = moved }
            return
        }
        // The surface holds it back: past the fold, it's shown pressed in only as far as
        // the water gives.
        let shown = FoldWater.shownPush(raw, radius: r)
        moved.push = raw
        moved.center = movedIn(center, by: shown - raw)
        // Meeting the water at the fold: a soft tap, once.
        if !moved.hasTouched, raw >= -4 {
            moved.hasTouched = true
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
        }
        // The neck of water: joined at touching, snapped when pulled too far away.
        if moved.neck.update(gap: max(0, -shown), radius: r) {
            snapNeck(at: moved.center, gap: max(0, -shown), radius: r)
        }
        withTransaction(Transaction(animation: nil)) { carried = moved }

        // Pressing: felt as the surface holding, seen as Now Playing rippling from there.
        let pressure = FoldWater.pressure(raw, radius: r)
        FoldHaptics.shared.press(raw > 0 ? pressure : 0)
        if raw > 0, now.timeIntervalSince(lastPressRipple) > 0.18 {
            lastPressRipple = now
            splash = LiquidSplash(point: contact(at: moved.center).local, strength: 0.2 + 0.45 * Double(pressure))
        }
        if FoldWater.breaks(raw, radius: r) { breakThrough() }
    }

    /// Pushed past what the surface holds: it gives way with a pop and a splash, and the
    /// bubble is in the water, still held. Let go there, it's taken in (drop).
    private func breakThrough() {
        guard var through = carried, !through.isThrough, !through.isTakenIn else { return }
        through.isThrough = true
        through.center = through.finger
        through.push = pastFold(through.finger) + through.diameter / 2
        _ = through.neck.release()
        withTransaction(Transaction(animation: nil)) { carried = through }
        FoldHaptics.shared.pop()
        splash = LiquidSplash(point: contact(at: through.center).local, strength: 0.8)
    }

    /// The neck between the surface and a bubble at `center` snapping: a droplet left
    /// halfway, falling back into the surface.
    private func snapNeck(at center: CGPoint, gap: CGFloat, radius: CGFloat) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
        guard !reduceMotion else { return }
        let droplet = FoldWater.Droplet(from: movedIn(center, by: radius + gap / 2), radius: max(6, radius * 0.12))
        foldDroplets.append(droplet)
        Task {
            try? await Task.sleep(for: .seconds(FoldWater.Droplet.life))
            foldDroplets.removeAll { $0.id == droplet.id }
        }
    }

    /// Let go: heading through the surface, it's taken in; short of it, it floats back to
    /// its place, going on at the finger's speed and wobbling a little as it settles.
    private func drop(_ album: AppAlbum, heading: CGPoint, velocity: CGPoint) {
        guard var carried, !carried.isTakenIn, carried.album.id == album.id else { return }
        let r = carried.diameter / 2
        // Let go on Up Next's bubble: down into it, and into Up Next.
        if !carried.isThrough, !album.isPodcast, fieldUpNextCatches(carried.finger) {
            queueCarried()
            return
        }
        // Let go in the water, or flung through the surface: taken in, and only now.
        if carried.isThrough || FoldWater.breaks(pastFold(heading) + r, radius: r) {
            takeIn()
            return
        }
        FoldHaptics.shared.release()
        if carried.neck.release() {
            snapNeck(at: carried.center, gap: max(0, -FoldWater.shownPush(carried.push, radius: r)), radius: r)
        }
        carried.push = -.greatestFiniteMagnitude
        withTransaction(Transaction(animation: nil)) { self.carried = carried }
        let away = CGPoint(x: carried.origin.x - carried.center.x, y: carried.origin.y - carried.center.y)
        let distance = hypot(away.x, away.y)
        // The finger's speed toward home.
        let toward = distance < 1 ? 0 : (velocity.x * away.x + velocity.y * away.y) / distance
        withAnimation(LyreMotion.release(velocity: toward, distance: distance)) {
            self.carried?.center = carried.origin
            self.carried?.velocity = .zero
        } completion: {
            if self.carried?.isTakenIn == false { self.carried = nil }
        }
    }

    /// Where Up Next's bubble comes up while a bubble is carried from the field: at the
    /// foot of the section's page, in the middle, clear of the side bar.
    private var fieldUpNextSpot: CGPoint? {
        guard sectionFrame.width > 0 else { return nil }
        let room = spreadRoom
        let d = TrackSpread.upNextDiameter
        return CGPoint(x: room.midX, y: room.maxY - d / 2 - 40)
    }

    /// The section's page less the side bar down its edge and the top: where a held
    /// bubble's songs, and Up Next's bubble, go.
    private var spreadRoom: CGRect {
        var room = sectionFrame
        room.size.width -= foldIsAcross || !SideRail.isOn(safeArea) ? 58 : SideRail.column(safeArea)
        room.origin.y += 60
        room.size.height -= 60
        return room
    }

    private func fieldUpNextCatches(_ point: CGPoint) -> Bool {
        guard let spot = fieldUpNextSpot else { return false }
        let d = TrackSpread.upNextDiameter
        return LiquidUpNextWell.catches(point, frame: CGRect(x: spot.x - d / 2, y: spot.y - d / 2, width: d, height: d))
    }

    /// A carried bubble let go on Up Next's bubble: it goes down into it, which gulps, and
    /// its songs join Up Next, after any queued by hand.
    private func queueCarried() {
        guard var queued = carried, let spot = fieldUpNextSpot else { return }
        queued.isTakenIn = true
        queued.isQueued = true
        queued.velocity = .zero
        _ = queued.neck.release()
        withTransaction(Transaction(animation: nil)) { carried = queued }
        FoldHaptics.shared.release()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        fieldUpNextGulps += 1
        let album = queued.album
        Task {
            let loaded = await library.tracks(for: album)
            let tracks = loaded.isEmpty ? album.tapeSongs(album.preloadedTracks) : loaded
            quickQueue(tracks, name: album.title)
        }
        withAnimation(.easeIn(duration: reduceMotion ? 0.01 : 0.3)) {
            carried?.center = spot
            carried?.takenIn = 1
            carried?.opacity = 0
        } completion: {
            carried = nil
        }
    }

    /// A bubble tapped: it flies to the fold, and is taken in.
    private func fly(_ album: AppAlbum, from tapped: CGPoint, diameter: CGFloat) {
        guard carried == nil else { return }
        // Played from VoiceOver, with no touch: from the middle of the bubbles' page.
        let page = nowPlayingPage
        let center = tapped != .zero ? tapped
            : foldIsAcross ? CGPoint(x: page.midX, y: page.maxY + page.height / 2)
            : CGPoint(x: page.maxX + page.width / 2, y: page.midY)
        carried = pickUp(CarriedBubble(album: album, diameter: diameter, center: center, origin: center))
        let fold = foldIsAcross
            ? CGPoint(x: min(max(center.x, page.minX + diameter), page.maxX - diameter),
                      y: page.maxY - Self.takeInDepth - 1)
            : CGPoint(x: page.maxX - Self.takeInDepth - 1,
                      y: min(max(center.y, page.minY + diameter), page.maxY - diameter))
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

    /// Let go in the water (or tapped, or flung through): the bubble sinks in, wavering as
    /// it's seen through the water, and dissolves; its colour spreads through Now Playing
    /// like ink, and its album plays. The ink spreads from where it went in, for one let go
    /// far inside, from where it is.
    private func takeIn() {
        guard var taken = carried, !taken.isTakenIn else { return }
        taken.isTakenIn = true
        taken.velocity = .zero
        _ = taken.neck.release()
        let wasThrough = taken.isThrough
        withTransaction(Transaction(animation: nil)) { carried = taken }
        let entry = contact(at: taken.center)
        if wasThrough {
            // The surface already gave way: let go, it settles in with a soft tap.
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.8)
        } else {
            FoldHaptics.shared.pop()
            splash = LiquidSplash(point: entry.local)
        }
        // Its colour spreads through Now Playing once it's really to play: asked first
        // whether to clear Up Next, only when the answer's to clear it and play.
        let origin = wasThrough && nowPlayingPage.contains(taken.center) ? taken.center : entry.screen
        let color = taken.color ?? nowPlayingColor
        let album = taken.album
        Task {
            let loaded = await library.tracks(for: album)
            let tracks = loaded.isEmpty ? album.tapeSongs(album.preloadedTracks) : loaded
            play(album, tracks, 0, whole: true, in: bounds.size, floods: false) {
                spreadInk(from: origin, color: color)
            }
        }
        let r = taken.diameter / 2
        withAnimation(.easeIn(duration: reduceMotion ? 0.01 : 0.42)) {
            carried?.center = movedIn(taken.center, by: r * 1.3)
            carried?.takenIn = 1
            carried?.opacity = 0
        } completion: {
            carried = nil
        }
    }

    /// The water at the fold, the bubble carried to it, and the ink of one taken in; kept
    /// moving (a TimelineView) only while any of them is there.
    private func carriedLayer(in proxy: GeometryProxy) -> some View {
        // A bubble held still at the fold wavers where it's under water; not under a UI test,
        // where a picture that never settles keeps XCUITest waiting (the ink and the
        // droplets end on their own).
        let wavers = carried != nil && !AppEnvironment.isUITesting
        let moving = !reduceMotion && (wavers || (ink != nil && inkShotProgress == nil) || !foldDroplets.isEmpty)
        return TimelineView(.animation(paused: !moving)) { timeline in
            carriedContent(in: proxy, now: timeline.date)
        }
        .allowsHitTesting(false)
    }

    private func carriedContent(in proxy: GeometryProxy, now: Date) -> some View {
        let origin = proxy.frame(in: .global).origin
        let across = foldIsAcross
        // Along the way to Now Playing: x held as a book, y turned. Shapes for the water
        // are worked out as if the fold ran down the screen, and laid across when turned.
        let fold = across ? nowPlayingPage.maxY - origin.y : nowPlayingPage.maxX - origin.x
        func local(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x - origin.x, y: point.y - origin.y) }
        func folded(_ point: CGPoint) -> CGPoint { across ? CGPoint(x: point.y, y: point.x) : point }
        let droplets: [(center: CGPoint, radius: CGFloat)] = foldDroplets.map { droplet in
            let t = min(1, now.timeIntervalSince(droplet.start) / FoldWater.Droplet.life)
            let from = folded(local(droplet.from))
            // Falling back into the surface, quicker as it goes, and shrinking into it.
            let x = fold + (from.x - fold) * (1 - t * t)
            return (CGPoint(x: x, y: from.y), droplet.radius * (1 - 0.4 * t))
        }
        return ZStack(alignment: .topLeading) {
            if let ink { inkLayer(ink, origin: origin, now: now) }
            // Up Next's bubble, come up at the foot of the page while a bubble's carried:
            // drawn toward it as it nears, gulping it down when it's let go on it.
            if let carried, let spot = fieldUpNextSpot, !carried.album.isPodcast,
               (carried.isDragged && !carried.isTakenIn) || carried.isQueued {
                let d = TrackSpread.upNextDiameter
                let frame = CGRect(x: spot.x - d / 2, y: spot.y - d / 2, width: d, height: d)
                let draw = carried.isQueued ? (pull: CGFloat(0), lean: CGFloat(0))
                    : LiquidUpNextWell.draw(toward: carried.finger, frame: frame)
                let toward = CGVector(dx: carried.finger.x - spot.x, dy: carried.finger.y - spot.y)
                let length = max(1, hypot(toward.dx, toward.dy))
                UpNextDropBubble(diameter: d, pull: draw.pull, lean: CGVector(dx: toward.dx / length, dy: toward.dy / length),
                                 gulps: fieldUpNextGulps)
                    .position(local(spot))
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.3).combined(with: .opacity))
            }
            if let carried {
                let r = carried.diameter / 2
                let pressure = carried.isTakenIn || carried.isThrough ? 0 : FoldWater.pressure(carried.push, radius: r)
                let squash = FoldWater.squash(pressure)
                // Flattened, its leading edge stays against the surface.
                let center = movedIn(local(carried.center), by: carried.isTakenIn || carried.isThrough ? 0 : r * (1 - squash.along))
                let shown = FoldWater.shownPush(carried.push, radius: r)
                let gap = max(0, -shown)
                let speed = hypot(carried.velocity.x, carried.velocity.y)
                let alongCenter = across ? center.y : center.x
                if carried.isThrough && !carried.isTakenIn {
                    // The surface closed behind it.
                    membrane(fold: fold, bubble: nil, radii: .zero, neck: 0, near: 0, bow: 0,
                             droplets: droplets, across: across)
                } else if !carried.isTakenIn {
                    membrane(fold: fold, bubble: folded(center),
                             radii: CGSize(width: r * squash.along, height: r * squash.across),
                             neck: carried.neck.width(gap: gap, radius: r),
                             near: max(0, min(1, 1 - gap / 150)),
                             bow: carried.push > 0 ? pressure * r * 0.45 : 0,
                             droplets: droplets, across: across)
                } else if !droplets.isEmpty {
                    membrane(fold: fold, bubble: nil, radii: .zero, neck: 0, near: 0, bow: 0,
                             droplets: droplets, across: across)
                }
                // Its film keeps moving while it's carried; flattened against the water as
                // it presses into it, drawn out along its way while it's quick, and seen
                // through the water where it's past the surface.
                LiquidBubble(album: carried.album, diameter: carried.diameter, wobbles: !reduceMotion)
                    .layerEffect(ShaderLibrary.foldRefraction(.float(fold - (alongCenter - r)),
                                                              .float(across ? 1 : 0),
                                                              .float(now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1000))),
                                 maxSampleOffset: CGSize(width: 6, height: 6),
                                 isEnabled: !reduceMotion)
                    .scaleEffect(x: across ? squash.across : squash.along, y: across ? squash.along : squash.across)
                    .modifier(MotionStretch(amount: reduceMotion ? 0 : min(1, speed / 2400),
                                            angle: atan2(carried.velocity.y, carried.velocity.x),
                                            along: 0.12, across: 0.06))
                    .scaleEffect(1.06 * (1 - 0.3 * carried.takenIn))
                    .position(center)
                    .opacity(carried.opacity)
                // What it is, beside it as it's carried: below it, or above it near the
                // bottom, kept on the screen.
                if !carried.isTakenIn {
                    let below = center.y + r * squash.across + 30
                    let labelY = below + 24 > proxy.size.height ? center.y - r * squash.across - 30 : below
                    carriedTitle(carried.album)
                        .position(x: min(max(center.x, 120), proxy.size.width - SideRail.column(safeArea) - 120), y: labelY)
                        .transition(.opacity)
                }
            } else if !droplets.isEmpty {
                membrane(fold: fold, bubble: nil, radii: .zero, neck: 0, near: 0, bow: 0,
                         droplets: droplets, across: across)
            }
        }
    }

    /// Played from the library beside Now Playing (an iPhone Duo open): what's played
    /// comes into Now Playing as a bubble let go does, its colour spreading through it like
    /// ink from the fold, level with where it was chosen, and a ring out from there.
    /// `chosenAt` is where it was chosen, taken before any question about Up Next (whose
    /// answer is a touch of its own, somewhere else).
    private func spreadInkBeside(_ color: Color, chosenAt: CGPoint?) {
        guard duoLayout(for: bounds.size) != nil, nowPlayingPage.width > 0 else { return }
        let entry = contact(at: chosenAt ?? CGPoint(x: nowPlayingPage.maxX, y: nowPlayingPage.midY))
        splash = LiquidSplash(point: entry.local, strength: 0.8)
        spreadInk(from: entry.screen, color: color)
    }

    /// A carried bubble's album and artist, on a small dark label.
    private func carriedTitle(_ album: AppAlbum) -> some View {
        bubbleLabel(album.title, album.artistName)
            .accessibilityIdentifier("liquid.carried.title")
    }

    /// A name, and what's under it, on a small dark label.
    private func bubbleLabel(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 1) {
            Text(title)
                .lyreFont(size: 15, weight: .semibold, maxScale: 1.5)
            Text(detail)
                .lyreFont(size: 12, maxScale: 1.5)
                .lyreFaded(0.75)
        }
        .lineLimit(1)
        // As wide as its words, up to a limit.
        .frame(maxWidth: 190)
        .fixedSize()
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .lyreMaterial(.ultraThinMaterial, in: Capsule(), solid: Color(white: 0.16))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
    }

    // MARK: A Held Bubble's Songs

    /// An album's or a playlist's bubble held: its songs burst out around it, once they've
    /// come; one alone, or none, and its page opens instead.
    private func beginSpread(_ album: AppAlbum, at center: CGPoint, diameter: CGFloat) -> Bool {
        guard sectionFrame.width > 0 else { return false }
        pendingSpreadFinger = nil
        spreadPastFold = false
        spread = TrackSpread(album: album, center: center, diameter: diameter)
        let id = album.id
        Task {
            let loaded = await library.tracks(for: album)
            let tracks = loaded.isEmpty ? album.tapeSongs(album.preloadedTracks) : loaded
            guard spread?.album.id == id, spread?.isOut == false else { return }
            guard tracks.count > 1 else {
                spread = nil
                openFromBubbles(album)
                return
            }
            // Within the section's page, clear of the side bar down its edge and of the top,
            // where a finger reaches badly and a tap can be taken for the status bar's.
            let room = spreadRoom
            spread?.tracks = tracks
            let slots = TrackSpreadLayout.slots(count: tracks.count + 1, around: center,
                                                diameter: diameter, within: room)
            spread?.slots = slots
            // Up Next's bubble, big, in the open place nearest the held one; smaller if
            // that's what fits; or, with no room at all, at the foot of the page.
            let open = [1, 0.8, 0.64].lazy.compactMap { scale -> (CGPoint, CGFloat)? in
                let size = TrackSpread.upNextDiameter * scale
                return TrackSpreadLayout.openSpot(for: size, avoiding: slots, held: center,
                                                  heldDiameter: diameter, within: room).map { ($0, size) }
            }.first
            spread?.upNextSpot = open?.0 ?? fieldUpNextSpot
            spread?.upNextSize = open?.1 ?? TrackSpread.upNextDiameter
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : LyreMotion.light) { spread?.isOut = true }
            if let finger = pendingSpreadFinger { moveSpread(finger) }
            if spread?.isHeld == false, let finger = pendingSpreadFinger { endSpread(finger) }
        }
        return true
    }

    /// The finger that held the bubble, moving on: over a song, it's chosen (felt as a
    /// tick); carried on from it toward Now Playing, the song goes with the finger.
    private func moveSpread(_ finger: CGPoint) {
        guard var moved = spread, moved.isOut else {
            pendingSpreadFinger = finger
            return
        }
        if moved.carried != nil {
            moved.carriedAt = finger
            moved.isOverUpNext = followUpNext(finger, was: moved.isOverUpNext)
            let past = pastFold(finger) > -10
            if past != spreadPastFold {
                spreadPastFold = past
                if past { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
            }
        } else {
            let under = TrackSpreadLayout.slot(at: finger, in: moved.slots)
            if under == nil, let chosen = moved.highlighted, chosen != TrackSpread.pageSlot,
               pastFold(finger) > pastFold(moved.slots[chosen]) + TrackSpreadLayout.bubble * 0.5
                || hypot(finger.x - moved.slots[chosen].x, finger.y - moved.slots[chosen].y)
                    > (TrackSpreadLayout.bubble + TrackSpreadLayout.gap) * 1.1 {
                // Off it, toward Now Playing, or well clear of it any way (toward Up Next's
                // bubble): picked up. A neighbour's nearer than that, so sliding on to it
                // chooses it instead.
                moved.carried = chosen
                moved.carriedAt = finger
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } else if under != moved.highlighted {
                if under != nil { UISelectionFeedbackGenerator().selectionChanged() }
                withAnimation(LyreMotion.tap) { spread?.highlighted = under }
                moved.highlighted = under
            }
        }
        withTransaction(Transaction(animation: nil)) { spread = moved }
    }

    /// The finger lifted: on a song, it plays; a song carried over the fold plays in Now
    /// Playing; over none, the songs stay out to be tapped or carried.
    private func endSpread(_ finger: CGPoint) {
        guard var ended = spread else { return }
        ended.isHeld = false
        spread = ended
        guard ended.isOut else {
            pendingSpreadFinger = finger
            return
        }
        if let carried = ended.carried {
            finishCarry(carried, at: finger)
        } else if let chosen = ended.highlighted {
            choose(chosen)
        }
    }

    /// A song carried near Up Next's bulge: the bulge drawn toward it; over it, felt once.
    /// Returns whether it's over it.
    private func followUpNext(_ finger: CGPoint, was: Bool) -> Bool {
        let well = LiquidUpNextWell.shared
        well.follow(finger)
        let over = well.catches(finger) || catchesUpNextBubble(finger)
        if over != was {
            if over { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.8) }
            withAnimation(LyreMotion.tap) { spread?.isOverUpNext = over }
        }
        return over
    }

    /// Whether a song let go at `point` falls into the spread's Up Next bubble.
    private func catchesUpNextBubble(_ point: CGPoint) -> Bool {
        guard let frame = spread?.upNextFrame, frame.width > 0 else { return false }
        return LiquidUpNextWell.catches(point, frame: frame)
    }

    /// A song let go on Up Next (the spread's bubble, or Now Playing's bulge): it goes down
    /// into it and that gulps, and it joins Up Next, after any queued by hand.
    private func dropIntoUpNext(_ slot: Int, intoBubble: Bool) {
        guard let dropped = spread, let song = dropped.track(atSlot: slot) else { return }
        let well = LiquidUpNextWell.shared
        let mouth = intoBubble
            ? (dropped.upNextSpot ?? dropped.carriedAt)
            : CGPoint(x: well.frame.midX, y: well.frame.maxY - 14)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .easeIn(duration: 0.22)) {
            spread?.carriedAt = mouth
            spread?.swallowed = slot
        }
        if intoBubble {
            spread?.upNextGulps += 1
            well.release()
        } else {
            well.swallow()
            let page = nowPlayingPage
            splash = LiquidSplash(point: CGPoint(x: mouth.x - page.minX, y: mouth.y - page.minY), strength: 0.6)
        }
        quickQueue([song.track], name: song.track.title)
        Task {
            // Long enough to see it gulped.
            try? await Task.sleep(for: .milliseconds(intoBubble ? 420 : 220))
            closeSpread()
        }
    }

    /// Songs dropped on Up Next: after those queued by hand, or next with none.
    private func quickQueue(_ tracks: [AppTrack], name: String) {
        guard !tracks.isEmpty else { return }
        Task {
            let (outcome, afterOthers) = await musicService.quickQueue(tracks)
            if !outcome.succeeded {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.4)
            }
            showNotice(outcome.message(name: name, requested: tracks.count,
                                       placement: afterOthers ? .last : .next, isCollection: tracks.count > 1))
        }
    }

    /// A song carried and let go: on Up Next, added to it; over the fold, played; short
    /// of it, back to its place.
    private func finishCarry(_ slot: Int, at point: CGPoint) {
        if slot != TrackSpread.pageSlot, catchesUpNextBubble(point) {
            dropIntoUpNext(slot, intoBubble: true)
            return
        }
        if slot != TrackSpread.pageSlot, LiquidUpNextWell.shared.catches(point) {
            dropIntoUpNext(slot, intoBubble: false)
            return
        }
        LiquidUpNextWell.shared.release()
        if pastFold(point) > -10 {
            choose(slot)
        } else {
            withAnimation(LyreMotion.light) {
                spread?.carried = nil
                spread?.highlighted = nil
            }
        }
    }

    /// A little bubble chosen: the album's page, or the album played from that song.
    private func choose(_ slot: Int) {
        guard let chosen = spread else { return }
        closeSpread()
        if slot == TrackSpread.pageSlot {
            openFromBubbles(chosen.album)
        } else if let song = chosen.track(atSlot: slot) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            play(chosen.album, chosen.tracks, song.index, whole: true, in: bounds.size)
        }
    }

    /// The songs gone back into their bubble.
    private func closeSpread() {
        LiquidUpNextWell.shared.release()
        let id = spread?.album.id
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : LyreMotion.light) {
            spread?.isOut = false
            spread?.highlighted = nil
            spread?.carried = nil
        } completion: {
            if spread?.album.id == id, spread?.isOut == false { spread = nil }
        }
    }

    /// The held bubble's songs, over the section's page, which dims behind them.
    @ViewBuilder
    private func spreadLayer(in proxy: GeometryProxy) -> some View {
        if let spread {
            let origin = proxy.frame(in: .global).origin
            let page = sectionFrame.offsetBy(dx: -origin.x, dy: -origin.y)
            let center = CGPoint(x: spread.center.x - origin.x, y: spread.center.y - origin.y)
            let named = spread.carried ?? spread.highlighted
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.black.opacity(spread.isOut ? 0.55 : 0))
                    .frame(width: page.width, height: page.height)
                    .position(x: page.midX, y: page.midY)
                    .contentShape(Rectangle())
                    .onTapGesture { closeSpread() }
                    .accessibilityLabel(String(localized: "liquid.spread.close"))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("liquid.spread.close")
                LiquidBubble(album: spread.album, diameter: spread.diameter)
                    .scaleEffect(spread.isOut ? 1.06 : 1)
                    .position(center)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                ForEach(Array(spread.slots.enumerated()), id: \.offset) { slot, place in
                    let at = spread.carried == slot || spread.swallowed == slot
                        ? spread.carriedAt : (spread.isOut ? place : spread.center)
                    let isSwallowed = spread.swallowed == slot
                    spreadBubble(spread, slot: slot)
                        .scaleEffect(isSwallowed ? 0.15 : spread.isOut ? (named == slot ? 1.3 : 1) : 0.2)
                        .opacity(isSwallowed || !spread.isOut ? 0 : 1)
                        .position(x: at.x - origin.x, y: at.y - origin.y)
                        .animation(reduceMotion ? nil : LyreMotion.light.delay(spread.isOut ? Double(slot) * 0.012 : 0),
                                   value: spread.isOut)
                        .onTapGesture { choose(slot) }
                        .gesture(DragGesture(minimumDistance: 6, coordinateSpace: .global)
                            .onChanged { value in
                                guard slot != TrackSpread.pageSlot else { return }
                                var carried = self.spread
                                carried?.carried = slot
                                carried?.carriedAt = value.location
                                carried?.isOverUpNext = followUpNext(value.location,
                                                                     was: self.spread?.isOverUpNext ?? false)
                                withTransaction(Transaction(animation: nil)) { self.spread = carried }
                            }
                            .onEnded { value in
                                guard slot != TrackSpread.pageSlot else { return }
                                finishCarry(slot, at: value.location)
                            })
                }
                // Up Next's bubble, come up among them while a song's carried: drawn toward
                // the song as it nears, and gulping it down when it's let go on it.
                // (Under a UI test, from the start: a test's drag can't find what isn't there.)
                if let spot = spread.upNextSpot, spread.isOut,
                   spread.carried != nil || spread.swallowed != nil || AppEnvironment.isUITesting {
                    let draw = spread.swallowed == nil
                        ? LiquidUpNextWell.draw(toward: spread.carriedAt, frame: spread.upNextFrame)
                        : (pull: CGFloat(0), lean: CGFloat(0))
                    let toward = CGVector(dx: spread.carriedAt.x - spot.x, dy: spread.carriedAt.y - spot.y)
                    let length = max(1, hypot(toward.dx, toward.dy))
                    UpNextDropBubble(diameter: spread.upNextSize, pull: draw.pull,
                                       lean: CGVector(dx: toward.dx / length, dy: toward.dy / length),
                                       gulps: spread.upNextGulps)
                        .position(x: spot.x - origin.x, y: spot.y - origin.y)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.2).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
                // What the chosen one is, above it.
                if spread.isOut, spread.swallowed == nil, let named, spread.slots.indices.contains(named) {
                    let place = spread.carried == named ? spread.carriedAt : spread.slots[named]
                    let song = spread.track(atSlot: named)
                    bubbleLabel(song?.track.title ?? String(localized: "liquid.spread.allSongs"),
                                spread.isOverUpNext && spread.carried == named
                                    ? String(localized: "liquid.spread.toUpNext")
                                    : song.map { String(format: String(localized: "liquid.spread.track"), $0.index + 1) }
                                        ?? spread.album.title)
                        .position(x: min(max(place.x - origin.x, 120), proxy.size.width - SideRail.column(safeArea) - 120),
                                  y: max(place.y - origin.y - TrackSpreadLayout.bubble * 0.65 - 30, 30))
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("liquid.spread.title")
                }
            }
            // While the finger that held the bubble is down, it's that finger's; lifted,
            // the songs are there to be tapped or carried.
            .allowsHitTesting(!spread.isHeld)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("liquid.spread")
        }
    }

    /// One of a held bubble's little bubbles: a song's, numbered, or the album page's.
    private func spreadBubble(_ spread: TrackSpread, slot: Int) -> some View {
        let diameter = TrackSpreadLayout.bubble
        let song = spread.track(atSlot: slot)
        let isNamed = spread.highlighted == slot || spread.carried == slot
        return LiquidSoapBubble(diameter: diameter, isLight: true, flattens: true, seed: spread.album.id + "#\(slot)") {
            ZStack {
                LiquidCover(source: .album(spread.album))
                    .overlay(Color.black.opacity(0.42))
                if song == nil {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 17, weight: .bold))
                } else {
                    Text("\(slot)")
                        .lyreFont(size: 17, weight: .bold, design: .rounded, maxScale: 1.5)
                }
            }
            .foregroundStyle(.white)
        }
        .overlay(Circle().strokeBorder(.white.opacity(isNamed ? 0.95 : 0), lineWidth: 2.5))
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(song?.track.title ?? String(localized: "liquid.spread.allSongs"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(song.map { "liquid.spread.track.\($0.index)" } ?? "liquid.spread.open")
    }

    /// A colour spreading through Now Playing like ink, from `origin` on screen.
    private func spreadInk(from origin: CGPoint, color: Color) {
        guard !reduceMotion else { return }
        let spread = FoldWater.Ink(origin: origin, color: color)
        ink = spread
        Task {
            try? await Task.sleep(for: .seconds(FoldWater.Ink.life))
            if ink?.id == spread.id { ink = nil }
        }
    }

    /// The ink of a bubble taken in, spreading through Now Playing.
    private func inkLayer(_ ink: FoldWater.Ink, origin: CGPoint, now: Date) -> some View {
        let page = nowPlayingPage.offsetBy(dx: -origin.x, dy: -origin.y)
        let progress = inkShotProgress ?? min(1, now.timeIntervalSince(ink.start) / FoldWater.Ink.life)
        return Rectangle()
            .fill(ink.color)
            .colorEffect(ShaderLibrary.inkSpread(.float2(page.size),
                                                 .float2(CGPoint(x: ink.origin.x - nowPlayingPage.minX,
                                                                 y: ink.origin.y - nowPlayingPage.minY)),
                                                 .float(progress), .float(ink.seed)))
            .frame(width: page.width, height: page.height)
            .position(x: page.midX, y: page.midY)
            // Not for VoiceOver; there for a UI test to see it's spreading.
            .accessibilityHidden(!AppEnvironment.isUITesting)
            .accessibilityIdentifier("liquid.ink")
    }

    /// Now Playing's edge at the fold, as a line of water down it: swelling toward a
    /// bubble the nearer it comes, reaching out to it in a neck that joins them, bowing in
    /// ahead of it as it presses, and taking back the droplets a snapped neck leaves; clear,
    /// with a bright rim. Worked out as if the fold ran down the screen (`bubble`, `radii`
    /// along and across, the droplets), and laid across when turned (`across`).
    private func membrane(fold: CGFloat, bubble: CGPoint?, radii: CGSize, neck: CGFloat, near: CGFloat,
                          bow: CGFloat, droplets: [(center: CGPoint, radius: CGFloat)], across: Bool) -> some View {
        /// The water's shapes, drawn `inset` points thinner all round.
        func water(inset: CGFloat) -> some View {
            Canvas { context, size in
                let length = across ? size.width : size.height
                func laid(_ rect: CGRect) -> CGRect {
                    across ? CGRect(x: rect.minY, y: rect.minX, width: rect.height, height: rect.width) : rect
                }
                func laid(_ point: CGPoint) -> CGPoint { across ? CGPoint(x: point.y, y: point.x) : point }
                context.addFilter(.alphaThreshold(min: 0.5, color: .white))
                context.addFilter(.blur(radius: 14))
                context.drawLayer { layer in
                    // Past both ends of the screen, so the line has no ends to round.
                    layer.fill(Path(laid(CGRect(x: fold - 13 + inset, y: -60, width: 26 - inset * 2, height: length + 120))),
                               with: .color(.white))
                    if let bubble {
                        let leading = bubble.x - radii.width
                        let gap = max(0, leading - fold)
                        // The surface swelling toward it.
                        let swell = (14 + 26 * near) - inset
                        let reach = fold + gap * 0.6 * near
                        layer.fill(Path(ellipseIn: laid(CGRect(x: reach - swell, y: bubble.y - swell * 2.1,
                                                               width: swell * 2, height: swell * 4.2))),
                                   with: .color(.white))
                        // The neck: wide at the surface, narrower where it holds the bubble.
                        if neck > 1 {
                            let atSurface = neck * 1.25 - inset
                            let atBubble = neck - inset
                            var bridge = Path()
                            bridge.move(to: laid(CGPoint(x: fold, y: bubble.y - atSurface / 2)))
                            bridge.addLine(to: laid(CGPoint(x: bubble.x, y: bubble.y - atBubble / 2)))
                            bridge.addLine(to: laid(CGPoint(x: bubble.x, y: bubble.y + atBubble / 2)))
                            bridge.addLine(to: laid(CGPoint(x: fold, y: bubble.y + atSurface / 2)))
                            bridge.closeSubpath()
                            layer.fill(bridge, with: .color(.white))
                        }
                        // The surface bowed in ahead of it, as it presses.
                        if bow > 0.5 {
                            let height = radii.height * 1.7 - inset
                            layer.fill(Path(ellipseIn: laid(CGRect(x: fold - bow - 6, y: bubble.y - height / 2,
                                                                   width: bow + 12, height: height))),
                                       with: .color(.white))
                        }
                        // The bubble, as flattened as it's pressed.
                        layer.fill(Path(ellipseIn: laid(CGRect(x: bubble.x - radii.width + inset,
                                                               y: bubble.y - radii.height + inset,
                                                               width: (radii.width - inset) * 2,
                                                               height: (radii.height - inset) * 2))),
                                   with: .color(.white))
                    }
                    for droplet in droplets {
                        let r = droplet.radius + 6 - inset
                        layer.fill(Path(ellipseIn: laid(CGRect(x: droplet.center.x - r, y: droplet.center.y - r,
                                                               width: r * 2, height: r * 2))),
                                   with: .color(.white))
                    }
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
    private var playingAlbum: AppAlbum? { library.playingAlbum }

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

    /// Opens Up Next; `speed` is how fast a finger let go of it was lifting it, in tide
    /// heights a second, carried on into the rise.
    private func openTide(speed: CGFloat = 0) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        isTideShown = true
        let left = 1 - tideProgress
        withAnimation(speed == 0 ? LyreMotion.light : LyreMotion.release(velocity: speed, distance: left)) {
            tideProgress = 1
        }
    }

    private func closeTide(speed: CGFloat = 0) {
        let animation = speed == 0 ? LyreMotion.light
            : LyreMotion.release(velocity: -speed, distance: tideProgress, bounces: false)
        withAnimation(animation) {
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
        // Past open it gives a little more, ever less, as a rubber band does.
        let shown = progress > 1 ? 1 + LyreMotion.rubberBand(progress - 1, limit: 0.06) : max(0, progress)
        withTransaction(Transaction(animation: nil)) { tideProgress = shown }
    }

    /// `speed`: the finger's, in tide heights a second, upward positive.
    private func endTideDrag(opens: Bool, speed: CGFloat = 0) {
        tideDragStart = nil
        opens ? openTide(speed: speed) : closeTide(speed: speed)
    }

    /// Let go of Now Playing: far enough down, or flicked, it slides away to the library
    /// page you came from; else it springs back.
    /// `speed` is the finger's, downward positive, carried on into either.
    private func endDismiss(drop: CGFloat, heading: CGFloat, speed: CGFloat = 0) {
        guard drop > 0 else { return }
        if drop > 140 || heading > 420 {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            let away = bounds.height + 40 - drop
            withAnimation(LyreMotion.release(velocity: max(speed, 0), distance: away, bounces: false)) {
                nowPlayingDrop = bounds.height + 40
            } completion: {
                withTransaction(Transaction(animation: nil)) {
                    screen = .library
                    nowPlayingDrop = 0
                }
            }
        } else {
            withAnimation(LyreMotion.release(velocity: -speed, distance: drop)) { nowPlayingDrop = 0 }
        }
    }

    // MARK: Playing

    /// Plays from the library, asking first if it would clear songs queued by hand, and
    /// floods into Now Playing in the album's colour (unless a bubble's being taken in,
    /// which is its own way in).
    /// `onPlays` runs once it's really to play: at once, or when the question about Up Next
    /// (clear it and play?) has been answered so; not if it's added to Up Next instead, or
    /// the question's put away.
    private func play(_ album: AppAlbum, _ tracks: [AppTrack], _ index: Int, whole: Bool, in size: CGSize,
                      floods: Bool = true, onPlays: (() -> Void)? = nil) {
        guard tracks.indices.contains(index) else { return }
        let queued = whole ? tracks : [tracks[index]]
        let chosenAt = LiquidTouchTracker.shared.lastTouch
        musicService.play(asking: { pendingPlay = $0 }, addToQueue: album.isPodcast ? nil : {
            queue(queued, .last, whole ? album.tapeTitle : tracks[index].title)
        }) {
            onPlays?()
            Task {
                if floods {
                    let color = await LiquidColors.shared.color(for: album)
                    spreadInkBeside(color, chosenAt: chosenAt)
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
        let chosenAt = LiquidTouchTracker.shared.lastTouch
        musicService.play(asking: { pendingPlay = $0 }, addToQueue: {
            queue(queued, .last, whole ? name : tracks[index].title)
        }) {
            Task {
                let color = await LiquidColors.shared.color(for: tracks[index])
                spreadInkBeside(color, chosenAt: chosenAt)
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

/// The Duo held open as a book: the library's sections, down the side bar. Albums, Songs,
/// Artists, Playlists and Search stand in it; the rest are in its "…" menu.
enum BookSection: String, CaseIterable, Identifiable {
    case albums, songs, artists, playlists, search, podcasts, discover, recentlyPlayed, recentlyAdded

    var id: String { rawValue }

    /// Always in the side bar, always in the same place.
    static let fixed: [BookSection] = [.albums, .songs, .artists, .search]
    /// One of these, the last opened, takes the side bar's fifth button; the rest are in "…".
    static let rotating: [BookSection] = [.playlists, .podcasts, .discover, .recentlyPlayed, .recentlyAdded]

    static func bar(recent: BookSection) -> [BookSection] {
        fixed + [rotating.contains(recent) ? recent : .playlists]
    }

    static func more(recent: BookSection) -> [BookSection] {
        let shown = bar(recent: recent).last
        return rotating.filter { $0 != shown }
    }

    /// The side bar fitted to `height` points of rail (an iPhone Duo stood as a tent has
    /// a short window): the buttons apart as they usually are if all of them and "…" fit,
    /// closer if that's what fits, and if even then they don't, the fewest given up to
    /// "…" (Artists first, then Search, then Songs), the rest keeping their places.
    static func fitted(recent: BookSection, height: CGFloat) -> (spacing: CGFloat, bar: [BookSection], more: [BookSection]) {
        let bar = bar(recent: recent)
        var more = more(recent: recent)
        func fits(_ spacing: CGFloat) -> Int { Int((height + spacing) / (44 + spacing)) }
        if fits(14) >= bar.count + 1 { return (14, bar, more) }
        let room = max(3, fits(8)) - 1
        guard room < bar.count else { return (8, bar, more) }
        var kept = bar
        for section in [BookSection.artists, .search, .songs] where kept.count > room {
            kept.removeAll { $0 == section }
            more.insert(section, at: 0)
        }
        return (8, kept, more)
    }

    var title: String {
        switch self {
        case .albums:         String(localized: "liquid.menu.albums").localizedCapitalized
        case .songs:          String(localized: "liquid.menu.songs").localizedCapitalized
        case .artists:        String(localized: "liquid.menu.artists").localizedCapitalized
        case .playlists:      String(localized: "liquid.menu.playlists").localizedCapitalized
        case .search:         String(localized: "liquid.menu.search").localizedCapitalized
        case .podcasts:       String(localized: "liquid.menu.podcasts").localizedCapitalized
        case .discover:       String(localized: "discover.title")
        case .recentlyPlayed: String(localized: "liquid.menu.recentlyPlayed").localizedCapitalized
        case .recentlyAdded:  String(localized: "liquid.menu.recentlyAdded").localizedCapitalized
        }
    }

    var symbol: String {
        switch self {
        case .albums:         "square.stack.fill"
        case .songs:          "music.note"
        case .artists:        "music.microphone"
        case .playlists:      "music.note.list"
        case .search:         "magnifyingglass"
        case .podcasts:       "mic.fill"
        case .discover:       "sparkles"
        case .recentlyPlayed: "clock.arrow.circlepath"
        case .recentlyAdded:  "plus.square.on.square"
        }
    }

    /// The bubbles a section shows, for the albums, playlists and shows.
    var bubbleTab: LiquidBubbleTab? {
        switch self {
        case .albums:    .albums
        case .playlists: .playlists
        case .podcasts:  .podcasts
        default:         nil
        }
    }

    /// The library's page for a section.
    var route: LiquidRoute {
        switch self {
        case .albums:         .albums
        case .songs:          .songs
        case .artists:        .artists
        case .playlists:      .playlists
        case .search:         .search
        case .podcasts:       .podcasts
        case .discover:       .discover
        case .recentlyPlayed: .recentlyPlayed
        case .recentlyAdded:  .recentlyAdded
        }
    }

    init(tab: LiquidBubbleTab) {
        switch tab {
        case .albums:    self = .albums
        case .playlists: self = .playlists
        case .podcasts:  self = .podcasts
        }
    }

    /// The section a library page is, if it's one.
    init?(route: LiquidRoute) {
        guard let found = Self.allCases.first(where: { $0.route == route }) else { return nil }
        self = found
    }
}


/// Up Next, as a bubble to drop on: among a held bubble's songs while one's carried
/// (TrackSpread), or at the foot of the page while a bubble is (Liquid's open layouts).
/// Twice a song bubble's size and lit, so it stands out from them: a pale film with the
/// symbol dark on it, a glow, and a slow breath while it waits. It swells and leans toward
/// what's carried as it comes, as the fold's water does, and gulps when it's let go on it.
private struct UpNextDropBubble: View {
    var diameter: CGFloat = TrackSpread.upNextDiameter
    /// 0 out of reach … 1 over it.
    let pull: CGFloat
    /// Toward what's carried, a unit vector.
    let lean: CGVector
    let gulps: Int
    @State private var gulp: CGFloat = 0
    @State private var breath = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let d = diameter
        VStack(spacing: 6) {
            LiquidSoapBubble(diameter: d, wobbles: !reduceMotion, flattens: true, seed: "up-next") {
                ZStack {
                    LinearGradient(colors: [Color(white: 0.97), Color(white: 0.78)],
                                   startPoint: .top, endPoint: .bottom)
                    Image(systemName: "text.line.last.and.arrowtriangle.forward")
                        .font(.system(size: d * 0.35, weight: .bold))
                        .foregroundStyle(.black)
                }
            }
            .frame(width: d, height: d)
            .background(Circle().fill(.white.opacity(0.25 + 0.35 * pull)).blur(radius: 18 + 10 * pull))
            .overlay(Circle().strokeBorder(.white.opacity(0.6 + 0.4 * pull), lineWidth: 2.5 + 1.5 * pull))
            .scaleEffect((breath ? 1.04 : 1) + 0.22 * pull + gulp)
            .offset(x: lean.dx * 12 * pull, y: lean.dy * 12 * pull)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: pull)
            Text(String(localized: "liquid.upNext"))
                .lyreFont(size: 13, weight: .heavy, maxScale: 1.5)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.white, in: Capsule())
                .fixedSize()
        }
        // The label hangs below; the bubble is what sits on the spot.
        .offset(y: 15)
        .onAppear {
            guard !reduceMotion, !AppEnvironment.isUITesting else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { breath = true }
        }
        .onChange(of: gulps) {
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.16, dampingFraction: 0.5)) { gulp = 0.3 }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.45).delay(0.14)) { gulp = 0 }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "liquid.upNext"))
        .accessibilityIdentifier("liquid.spread.upNext")
    }
}
