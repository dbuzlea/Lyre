//
//  DiscPlayerView.swift
//  Lyre
//

import SwiftUI
import os

private let logger = Logger(subsystem: "com.lyre.app", category: "DiscPlayer")

// MARK: - Disc Player
//
// The portable CD player, shown in place of the click-wheel player when Settings → Player
// Style is Disc. It drives the same MusicService, so switching styles mid-song keeps
// playing.
//
// The player is a round deck under a tinted lid, the disc turning on its spindle beneath
// it while it plays. Under the deck are the LCD, showing the track, the time (tap it for
// what's left), the title scrolling past and the modes, and the rubber keys:
//
//   ⏮ ⏯ ⏭      tapped, a song back (or to its start) and on; for a podcast, 15 seconds
//               back and 30 on. Held, ⏮ and ⏭ scan through the song.
//   MODE        repeat: off, all, one, shown on the LCD
//   RANDOM      tapped, plays in random order; held, shuffles every song onto a fresh
//               burned disc, as a shake does on the click wheel
//   OPEN        opens the lid to change discs
//
// Changing Discs (closed)
//   The lid pops up and the old disc comes off the spindle; the deck shrinks to the top
//   of the screen and the shelf of jewel cases comes up under it. Tapping a case opens it
//   (JewelCaseView) to its booklet, its disc and its track list; choosing a song, or Play,
//   lifts the disc out of the tray onto the spindle. Swiping a case left takes its whole
//   disc. The disc seats with a click, the shelf goes, the lid snaps shut, and the disc
//   spins up and plays. Tapping the lid again, or the shelf's close button, backs out.
//
//   Albums are pressed discs with their covers on them; playlists are burned CD-Rs with
//   their names written on in marker; shows are enhanced CDs (see DiscKind). The shelf is
//   the Spool's rack (TapeCarousel) holding cases, with the same search field, dividers
//   and A–Z index, and swiping a case right queues it.
//
// Open (iPhone Duo, unfolded)
//   The deck stands on the left with its lid up, the shelf on the right. A disc chosen
//   from the shelf goes onto the spindle and waits there; closing the phone is the lid
//   snapping shut, and it plays. A case opens over the shelf, leaving the deck in view.
//
// Up Next is the Spool's tray, pulled up from the grip under the keys. A song picked from
// it comes out as a disc of its own and goes on the spindle; the rest of Up Next stays.
// Holding the lid opens the case of the album playing.

struct DiscPlayerView: View {
    @ObservedObject var musicService: MusicService
    let themeSettings: ThemeSettings
    let foldMonitor: FoldPostureMonitor

    @State private var showSettings = false
    @State private var showPodcastSearch = false
    @State private var isQueueShown = false
    @State private var queueProgress: CGFloat = 0
    @State private var queueDragStart: CGFloat?
    @State private var containerHeight: CGFloat = 0
    /// Something about to play that would clear what the listener queued.
    @State private var pendingPlay: PendingPlay?
    @State private var notice: String?
    @State private var noticeTask: Task<Void, Never>?

    /// The lid up, on the closed layout. On an open Duo it's always up.
    @State private var isLidOpen = false
    /// The shelf out under the deck.
    @State private var isBrowsing = false
    @State private var flight: DiscFlight?
    /// Where the disc sits on the spindle, in SpoolPlayerView.coordinateSpace.
    @State private var seatFrame: CGRect = .zero
    /// A new disc on the spindle, shown until its first song plays.
    @State private var pendingDisc: LoadedDisc?
    /// The last disc put on, and its songs: while they play, the deck shows it, and the
    /// LCD numbers the tracks from it.
    @State private var seatedDisc: LoadedDisc?
    @State private var seatedTracks: [AppTrack] = []
    /// The motor bringing a new disc up to speed before it plays.
    @State private var isSpinningUp = false
    /// A disc put on the spindle of an open Duo, waiting for the phone to close.
    @State private var deckLoad: DiscLoad?
    /// The case open, and whether it was brought up from the disc playing.
    @State private var openCase: AppAlbum?
    @State private var isCaseFromDeck = false
    /// The shelf's half of an unfolded Duo, where a case opens.
    @State private var openShelfFrame: CGRect = .zero
    /// ⏮ or ⏭ held down, scanning through the song.
    @State private var scanTask: Task<Void, Never>?

    @AppStorage("DiscAlbumFrontID") private var albumFrontID: String?
    @AppStorage("DiscBurnedFrontID") private var burnedFrontID: String?
    @AppStorage("DiscPodcastFrontID") private var podcastFrontID: String?
    @AppStorage("DiscShelf") private var shelf: SpoolShelf = .albums
    @AppStorage("DiscShowsRemaining") private var showsRemaining = false
    @State private var shelfQuery = ""
    @State private var shelfMatches: ShelfSearchMatches?
    @FocusState private var isShelfSearchFocused: Bool
    @State private var keyboard = KeyboardMonitor()
    @Environment(\.windowSafeArea) private var safeArea

    private var theme: DiscTheme { themeSettings.discFinish.theme }
    private var library: ShelfLibrary { ShelfLibrary(musicService: musicService) }

    var body: some View {
        ZStack {
            background

            Group {
                switch foldMonitor.posture {
                case .open:          openLayout
                case .closed, .tent: closedLayout
                }
            }
            .padding(safeArea)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: foldMonitor.posture)

            if let album = openCase {
                jewelCase(album)
                    .transition(.opacity)
                    .zIndex(3)
            }

            if isQueueShown {
                SpoolQueueTray(
                    musicService: musicService,
                    progress: queueProgress,
                    height: queueTrayHeight,
                    bottomInset: safeArea.bottom,
                    onScrub: { progress in
                        withTransaction(Transaction(animation: nil)) { queueProgress = progress }
                    },
                    onScrubEnd: { closes in closes ? closeQueue() : openQueue() },
                    onClose: closeQueue,
                    onNotice: showNotice,
                    onPick: { _, track, frame in loadFromQueue(track, from: frame) }
                )
                .zIndex(3.5)
            }

            if let flight {
                flyingDisc(flight)
                    .zIndex(4)
            }

            if let notice {
                Text(notice)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.75), in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, safeArea.bottom + 24)
                    .transition(.opacity)
                    .accessibilityIdentifier("disc.notice")
                    .zIndex(5)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: notice)
        .environment(\.discTheme, theme)
        .environment(\.spoolTheme, theme.spoolTheme)
        // The shelf is the Spool's rack, which reports frames in this space.
        .coordinateSpace(name: SpoolPlayerView.coordinateSpace)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { containerHeight = $0 }
        .sheet(isPresented: $showSettings) {
            DiscSettingsView(musicService: musicService, themeSettings: themeSettings,
                             foldMonitor: foldMonitor) { showSettings = false }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPodcastSearch) {
            PodcastSearchView(musicService: musicService)
        }
        .replaceQueuePrompt($pendingPlay, count: musicService.listenerQueuedCount)
        // A new song, or a new episode streaming: the disc going on is now playing.
        .onChange(of: musicService.currentTrack?.id ?? musicService.currentEpisode?.id) {
            pendingDisc = nil
        }
        .onChange(of: foldMonitor.posture) { _, posture in
            // Unfolding mid-change abandons it; the open layout has its own shelf.
            isBrowsing = false
            isLidOpen = false
            if posture != .open, let load = deckLoad {
                // Closing the phone snaps the lid shut on the disc waiting, and it plays.
                deckLoad = nil
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                DiscSound.lidClose.play()
                spinUp(load.disc, tracks: load.tracks, startingAt: load.index)
            }
        }
        .modifier(ShelfSearching(query: shelfQuery, library: library, shelf: $shelf, matches: $shelfMatches))
        .onChange(of: isBrowsing) { _, browsing in
            // The shelf opens whole each time.
            guard !browsing else { return }
            isShelfSearchFocused = false
            shelfQuery = ""
        }
        .onAppear {
            _ = Self.resetShelfForUITests
            #if DEBUG
            // `--spool-sample-queue` fills Up Next with the first sample album's songs, so
            // the tray has something to show on a simulator with no music.
            if ProcessInfo.processInfo.arguments.contains("--spool-sample-queue"),
               musicService.upNext.isEmpty, let album = library.albums.first {
                musicService.seedQueueForUITests(album.preloadedTracks)
            }
            // `-DiscShot shelf|case|put` starts there, for screenshots.
            switch UserDefaults.standard.string(forKey: "DiscShot") {
            case "shelf":
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    openDeck()
                }
            case "case":
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    openDeck()
                    try? await Task.sleep(for: .seconds(1.2))
                    if let album = library.albums.first { openCaseOf(album) }
                }
            case "put":
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    if let album = library.albums.first {
                        let tracks = await library.tracks(for: album)
                        let disc = LoadedDisc(album: album)
                        seatedDisc = disc
                        seatedTracks = tracks
                        pendingDisc = disc
                        isSpinningUp = true
                    }
                }
            default: break
            }
            #endif
        }
        .onDisappear {
            noticeTask?.cancel()
            stopScanning()
        }
    }

    /// `--spool-reset-rack` at launch forgets where the shelf was left, and which shelf
    /// it was on, once, so each UI test starts from the first album. Debug builds only.
    private static let resetShelfForUITests: Void = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--spool-reset-rack") {
            for key in ["DiscAlbumFrontID", "DiscBurnedFrontID", "DiscPodcastFrontID", "DiscShelf"] {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        #endif
    }()

    /// The casing, edge to edge, with a fine brushed grain.
    private var background: some View {
        ZStack {
            theme.bodyGradient
            LinearGradient(colors: [.white.opacity(0.1), .clear, .white.opacity(0.06), .clear, .white.opacity(0.08)],
                           startPoint: .leading, endPoint: .trailing)
        }
        .ignoresSafeArea()
    }

    // MARK: - Layouts

    private var closedLayout: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let deckSide = isBrowsing
                ? min(size.width * 0.56, size.height * 0.3)
                : min(size.width - 56, size.height * 0.44)
            VStack(spacing: 14) {
                topBar
                    .padding(.horizontal, 20)
                if !isBrowsing { Spacer(minLength: 0) }
                deck(side: deckSide, lidOpen: isLidOpen)
                    .gesture(
                        LongPressGesture(minimumDuration: 0.5)
                            .onEnded { _ in showCaseOfDisc() }
                            .exclusively(before: TapGesture().onEnded { isBrowsing ? closeDeck() : openDeck() })
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: "disc.lid"))
                    .accessibilityValue(deckDisc?.title ?? String(localized: "disc.noDisc"))
                    .accessibilityHint(String(localized: isBrowsing ? "disc.lid.close" : "disc.lid.open"))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("disc.lid")
                    .accessibilityAction { isBrowsing ? closeDeck() : openDeck() }
                    .accessibilityActions {
                        if caseOfDisc != nil {
                            Button(String(localized: "spool.carousel.showSongs")) { showCaseOfDisc() }
                        }
                    }
                if isBrowsing {
                    shelfColumn(showsClose: true)
                        .padding(.horizontal, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    Spacer(minLength: 0)
                    controls
                        .padding(.horizontal, 20)
                        .transition(.opacity)
                }
            }
            .padding(.top, 8)
            .frame(width: size.width, height: size.height)
            // A swipe in from the right edge opens the lid, like OPEN.
            .simultaneousGesture(edgeSwipe(width: size.width), isEnabled: !isLidOpen && flight == nil)
        }
    }

    /// An unfolded iPhone Duo: the deck on the left with its lid up, the shelf on the
    /// right. A disc chosen from the shelf waits on the spindle until the phone closes.
    private var openLayout: some View {
        GeometryReader { geometry in
            HStack(spacing: 16) {
                VStack(spacing: 16) {
                    topBar
                    Spacer(minLength: 0)
                    deck(side: min(geometry.size.width * 0.42, geometry.size.height * 0.5), lidOpen: true)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(String(localized: "disc.lid"))
                        .accessibilityValue(deckLoad?.disc.title ?? "")
                        .accessibilityIdentifier("disc.lid")
                    lcd
                    Spacer(minLength: 0)
                    Text(String(localized: deckLoad == nil ? "disc.open.hint" : "spool.closeToPlay"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.ink)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(theme.ink.opacity(0.12), in: Capsule())
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: deckLoad == nil)
                        .accessibilityIdentifier("disc.open.hint")
                }
                .frame(width: geometry.size.width * 0.46)
                shelfColumn(showsClose: false)
                    .padding(.top, 8)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named(SpoolPlayerView.coordinateSpace))
                    } action: { openShelfFrame = $0 }
            }
            .padding(12)
        }
    }

    /// How far in from the right edge a swipe must start to open the lid.
    private static let edgeSwipeZone: CGFloat = 28

    private func edgeSwipe(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 15)
            .onEnded { value in
                let dx = value.translation.width
                let fromEdge = value.startLocation.x > width - Self.edgeSwipeZone
                let sideways = abs(dx) > abs(value.translation.height) * 1.5
                let far = dx < -60 || value.predictedEndTranslation.width < -160
                if fromEdge, sideways, far { openDeck() }
            }
    }

    // MARK: - Deck

    /// The name, AirPlay and Settings.
    private var topBar: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(String(localized: "disc.brand"))
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .italic()
                    .tracking(3)
                Text(String(localized: "disc.subtitle"))
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .opacity(0.7)
            }
            .foregroundStyle(theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityHidden(true)
            Spacer(minLength: 8)
            AirPlayRouteButton(identifier: "disc.airplay") { isActive in
                Image(systemName: "airplayaudio")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(isActive ? theme.accent : theme.buttonSymbol)
                    .frame(width: 36, height: 36)
                    .background(theme.buttonLight.opacity(0.8), in: Circle())
            }
            Button { showSettings = true } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.buttonSymbol)
                    .frame(width: 36, height: 36)
                    .background(theme.buttonLight.opacity(0.8), in: Circle())
            }
            .accessibilityLabel(String(localized: "settings.title"))
            .accessibilityIdentifier("disc.settings")
        }
    }

    /// The round deck, standing proud of the casing: a bevelled body with a groove
    /// where the lid meets it, the well the disc turns in, the pickup under it, the
    /// spindle, and the domed lid over it all, hinged at the back with a catch at the
    /// front. The light comes from the top left, as it does on the keys.
    private func deck(side: CGFloat, lidOpen: Bool) -> some View {
        let discSize = side * 0.86
        let disc = deckDisc
        let well = side * 0.9
        return ZStack {
            // The shadow the deck casts on the casing, soft and offset down.
            Ellipse()
                .fill(.black.opacity(0.35))
                .frame(width: side * 0.92, height: side * 0.84)
                .blur(radius: side * 0.05)
                .offset(y: side * 0.06)

            // The body: its face, shaded from the light, and the bevel round its edge
            // catching it at the top and falling into shade at the bottom.
            Circle()
                .fill(LinearGradient(colors: [theme.bodyLight, theme.body, theme.bodyDark],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
            Circle()
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.1), .black.opacity(0.3)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: side * 0.016)
            Circle()
                .fill(LinearGradient(colors: [theme.bodyLight.opacity(0.9), theme.body.opacity(0.4)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: side * 0.955, height: side * 0.955)

            // The groove the lid sits in: dark, with its far wall lit.
            Circle()
                .strokeBorder(.black.opacity(0.5), lineWidth: side * 0.012)
                .frame(width: side * 0.935, height: side * 0.935)
            Circle()
                .trim(from: 0.05, to: 0.45)
                .stroke(.white.opacity(0.5), lineWidth: 1)
                .frame(width: side * 0.938, height: side * 0.938)

            // The well, sunk into the body.
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.2), Color(white: 0.05)],
                                     center: .center, startRadius: 0, endRadius: well / 2)
                    .shadow(.inner(color: .black.opacity(0.9), radius: side * 0.03, x: 0, y: side * 0.02)))
                .frame(width: well, height: well)

            // The pickup's slot and its lens.
            Capsule()
                .fill(Color(white: 0.02).shadow(.inner(color: .black, radius: 3, y: 2)))
                .frame(width: side * 0.11, height: side * 0.34)
                .overlay(alignment: .bottom) {
                    Circle()
                        .fill(RadialGradient(colors: [Color(red: 0.6, green: 0.7, blue: 1), Color(red: 0.1, green: 0.1, blue: 0.3)],
                                             center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: side * 0.025))
                        .frame(width: side * 0.05, height: side * 0.05)
                        .padding(.bottom, side * 0.05)
                }
                .offset(y: side * 0.25)

            // Where the disc sits, measured whether there's a disc or not.
            Color.clear
                .frame(width: discSize, height: discSize)
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(SpoolPlayerView.coordinateSpace))
                } action: { seatFrame = $0 }

            if let disc, showsDiscOnSpindle {
                DiscSpinner(isSpinning: isDiscSpinning) {
                    CompactDisc(kind: disc.kind, art: disc.art, title: disc.title, diameter: discSize)
                }
                .overlay(DiscSheen(diameter: discSize))
                // Lifted off the floor of the well on the spindle.
                .shadow(color: .black.opacity(0.6), radius: side * 0.015, y: side * 0.012)
                .transition(.opacity)
            }

            // The spindle.
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.98), Color(white: 0.5)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: side * 0.05))
                .frame(width: side * 0.08, height: side * 0.08)
                .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1.5)

            lid(side: side)
                .rotation3DEffect(.degrees(lidOpen ? -70 : 0), axis: (x: 1, y: 0, z: 0),
                                  anchor: .top, perspective: 0.55)
                .opacity(lidOpen ? 0.9 : 1)
                .allowsHitTesting(false)

            // The hinge's knuckles at the back, and the catch at the front.
            ForEach([-1.0, 1.0], id: \.self) { sideOf in
                hingeKnuckle(side: side)
                    .offset(x: side * 0.13 * sideOf, y: -side * 0.462)
            }
            lidCatch(side: side)
                .offset(y: side * 0.468)
        }
        .frame(width: side, height: side)
        .contentShape(Circle())
    }

    private func hingeKnuckle(side: CGFloat) -> some View {
        Capsule()
            .fill(LinearGradient(colors: [theme.bodyLight, theme.bodyDark], startPoint: .top, endPoint: .bottom))
            .overlay(Capsule().strokeBorder(.black.opacity(0.25), lineWidth: 0.5))
            .frame(width: side * 0.1, height: side * 0.032)
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
    }

    /// The tab at the front of the lid that pops it.
    private func lidCatch(side: CGFloat) -> some View {
        Capsule()
            .fill(LinearGradient(colors: [theme.accentLight, theme.accent], startPoint: .top, endPoint: .bottom))
            .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 0.5))
            .overlay {
                Image(systemName: "chevron.up")
                    .font(.system(size: max(6, side * 0.022), weight: .black))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: side * 0.12, height: side * 0.04)
            .shadow(color: .black.opacity(0.4), radius: 2, y: 1.5)
            .accessibilityHidden(true)
    }

    /// Smoked plastic, domed, in a bevelled rim of the body's colour, with the name
    /// printed on it. The disc shows through.
    private func lid(side: CGFloat) -> some View {
        let size = side * 0.92
        let window = size * 0.86
        return ZStack {
            // The rim: the body's colour, bevelled, stepping down into the window.
            Circle()
                .strokeBorder(LinearGradient(colors: [theme.bodyLight, theme.body, theme.bodyDark],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: (size - window) / 2 + 1)
            Circle()
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.9), .clear, .black.opacity(0.25)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: 1.5)

            // The window: tinted plastic over the well, darkening to its edge as it
            // curves away, with the rim's shadow falling inside it.
            ZStack {
                Circle()
                    .fill(theme.lid.opacity(theme.isClear ? 0.4 : 0.6)
                        .shadow(.inner(color: .black.opacity(0.7), radius: size * 0.025, x: 0, y: size * 0.015)))
                Circle()
                    .fill(RadialGradient(colors: [.clear, .clear, .black.opacity(0.35)],
                                         center: UnitPoint(x: 0.5, y: 0.42), startRadius: 0, endRadius: window * 0.55))
                // The light on the dome: a broad soft reflection, and a sharp line where
                // the plastic curves at the top.
                Ellipse()
                    .fill(LinearGradient(colors: [.white.opacity(0.38), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .frame(width: window * 0.62, height: window * 0.3)
                    .rotationEffect(.degrees(-28))
                    .offset(x: -window * 0.13, y: -window * 0.24)
                    .blur(radius: window * 0.01)
                Circle()
                    .trim(from: 0.56, to: 0.78)
                    .stroke(.white.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: window * 0.94, height: window * 0.94)
                    .blur(radius: 0.4)
                Circle()
                    // On the right, clear of the print round the bottom.
                    .trim(from: 0.88, to: 0.99)
                    .stroke(.white.opacity(0.18), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: window * 0.92, height: window * 0.92)
            }
            .frame(width: window, height: window)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.black.opacity(0.45), lineWidth: 1))

            Text(String(localized: "disc.brand"))
                .font(.system(size: side * 0.07, weight: .heavy, design: .rounded))
                .italic()
                .tracking(side * 0.01)
                .foregroundStyle(.white.opacity(0.75))
                .shadow(color: .black.opacity(0.4), radius: 0, y: 1)
                .offset(y: -side * 0.32)
            // Printed round the bottom of the window, just inside its edge.
            ArcText(text: String(localized: "disc.lid.print"),
                    radius: window / 2 - side * 0.035,
                    fontSize: side * 0.028, tracking: side * 0.006)
                .foregroundStyle(.white.opacity(0.6))

            // The hub cap, which presses the disc onto the spindle: a domed metal
            // button with turned rings.
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [theme.bodyLight, theme.body, theme.bodyDark],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: side * 0.08))
                ForEach([0.75, 0.5], id: \.self) { ring in
                    Circle()
                        .stroke(.white.opacity(0.18), lineWidth: 0.5)
                        .frame(width: side * 0.14 * ring, height: side * 0.14 * ring)
                }
                Circle()
                    .fill(.white.opacity(0.7))
                    .frame(width: side * 0.025, height: side * 0.018)
                    .blur(radius: 1)
                    .offset(x: -side * 0.02, y: -side * 0.025)
            }
            .frame(width: side * 0.14, height: side * 0.14)
            .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
        }
        .frame(width: size, height: size)
        .compositingGroup()
        // The lid stands a little above the body, so it throws a shadow on it.
        .shadow(color: .black.opacity(0.35), radius: side * 0.012, y: side * 0.01)
        .accessibilityHidden(true)
    }

    /// The disc on the spindle, unless it has come off for a change: the lid's up on the
    /// closed layout, or another is on its way in.
    private var showsDiscOnSpindle: Bool {
        if flight != nil { return false }
        if foldMonitor.posture == .open { return true }
        return !isBrowsing || pendingDisc != nil
    }

    /// The disc to show on the spindle: one going in, or waiting on an open Duo, or the
    /// one playing.
    private var deckDisc: LoadedDisc? {
        if let pendingDisc { return pendingDisc }
        if let deckLoad { return deckLoad.disc }
        if let seatedDisc, isPlayingFromSeated { return seatedDisc }
        if let episode = musicService.currentEpisode, let track = musicService.nowPlayingTrack {
            return LoadedDisc(album: nil, title: episode.showTitle, kind: .enhanced, art: .track(track),
                              id: "show:\(episode.showTitle)")
        }
        if let track = musicService.currentTrack ?? musicService.nowPlayingTrack {
            return LoadedDisc(album: nil, title: TapeFormat.displayTitle(track.albumTitle), kind: .pressed,
                              art: .track(track), id: "album:\(track.albumTitle)")
        }
        return nil
    }

    /// Whether what's playing came off the last disc put on.
    private var isPlayingFromSeated: Bool {
        guard let seatedDisc else { return false }
        if let album = seatedDisc.album { return library.isPlaying(from: album) }
        guard let id = musicService.currentTrack?.id else { return false }
        return seatedTracks.contains { $0.id == id }
    }

    private var isDiscSpinning: Bool {
        (musicService.isPlaying && deckLoad == nil && pendingDisc == nil && !isBrowsing) || isSpinningUp
    }

    /// The case of the album playing, which holding the lid brings up.
    private var caseOfDisc: AppAlbum? {
        guard let album = seatedDisc?.album, isPlayingFromSeated || pendingDisc?.album?.id == album.id else { return nil }
        return album
    }

    private func showCaseOfDisc() {
        guard let album = caseOfDisc, !isLidOpen, !isBrowsing, !isSpinningUp, flight == nil, openCase == nil else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isCaseFromDeck = true
        openCase = album
    }

    // MARK: - Controls

    /// The LCD, the keys, and the grip Up Next is pulled up by.
    private var controls: some View {
        VStack(spacing: 14) {
            lcd
            transportKeys
            modeKeys
            queueGrip
        }
        .padding(.bottom, 8)
    }

    private var lcd: some View {
        DiscLCD(
            clock: musicService.clock,
            duration: deckLoad == nil && pendingDisc == nil ? musicService.duration : 0,
            track: trackPosition,
            title: lcdTitle,
            isPlaying: musicService.isPlaying || isSpinningUp,
            shuffle: musicService.shuffleMode != .off,
            repeatMode: musicService.repeatMode,
            rate: musicService.isPlayingPodcast ? musicService.podcastRate : nil,
            status: lcdStatus,
            showsRemaining: $showsRemaining
        )
        .contextMenu {
            if musicService.isPlayingPodcast {
                ForEach(MusicService.podcastRates, id: \.self) { rate in
                    Button {
                        musicService.setPodcastRate(rate)
                    } label: {
                        if rate == musicService.podcastRate {
                            Label(SpoolPlayerView.speedText(rate), systemImage: "checkmark")
                        } else {
                            Text(SpoolPlayerView.speedText(rate))
                        }
                    }
                }
            }
        }
    }

    /// What the display says where the time goes, when there's no time to show.
    private var lcdStatus: String? {
        if isSpinningUp { return String(localized: "disc.lcd.read") }
        if isLidOpen && foldMonitor.posture != .open { return String(localized: "disc.lcd.open") }
        if deckLoad != nil { return String(localized: "disc.lcd.ready") }
        if deckDisc == nil { return String(localized: "disc.lcd.noDisc") }
        return nil
    }

    private var lcdTitle: String {
        if let disc = pendingDisc ?? deckLoad?.disc { return disc.title }
        if let episode = musicService.currentEpisode { return "\(episode.title) — \(episode.showTitle)" }
        if let track = musicService.currentTrack { return "\(track.title) — \(track.artistName)" }
        return String(localized: "disc.noDisc.hint")
    }

    /// The song's place on the disc: from the disc put on, or else Up Next's.
    private var trackPosition: (number: Int, count: Int)? {
        guard pendingDisc == nil, deckLoad == nil,
              let id = musicService.currentTrack?.id ?? musicService.currentEpisode?.id else { return nil }
        if let index = seatedTracks.firstIndex(where: { $0.id == id }) {
            return (index + 1, seatedTracks.count)
        }
        let queue = musicService.playbackQueue
        guard !queue.isEmpty else { return nil }
        return (queue.currentIndex + 1, queue.tracks.count)
    }

    private var transportKeys: some View {
        let isPodcast = musicService.isPlayingPodcast && deckLoad == nil
        let isPlaying = (musicService.isPlaying && deckLoad == nil) || isSpinningUp
        return HStack(spacing: 14) {
            DiscKey(symbol: isPodcast ? "gobackward.15" : "backward.end.alt.fill",
                    label: String(localized: isPodcast ? "spool.skipBack" : "disc.previous"),
                    size: CGSize(width: 80, height: 56),
                    onHoldStart: { startScanning(forward: false) }, onHoldEnd: stopScanning) {
                Task { await musicService.skip(forward: false) }
            }
            .accessibilityIdentifier("disc.previous")
            DiscKey(symbol: isPlaying ? "pause.fill" : "play.fill",
                    label: String(localized: isPlaying ? "spool.pause" : "spool.play"),
                    isAccent: true, size: CGSize(width: 96, height: 60)) {
                playPause()
            }
            .accessibilityIdentifier("disc.playPause")
            DiscKey(symbol: isPodcast ? "goforward.30" : "forward.end.alt.fill",
                    label: String(localized: isPodcast ? "spool.skipForward" : "disc.next"),
                    size: CGSize(width: 80, height: 56),
                    onHoldStart: { startScanning(forward: true) }, onHoldEnd: stopScanning) {
                Task { await musicService.skip(forward: true) }
            }
            .accessibilityIdentifier("disc.next")
        }
    }

    private var modeKeys: some View {
        HStack(spacing: 12) {
            DiscKey(symbol: nil, caption: String(localized: "disc.mode"), label: String(localized: "disc.mode.label"),
                    size: CGSize(width: 80, height: 36)) {
                cycleRepeat()
            }
            .accessibilityValue(repeatText(musicService.repeatMode))
            .accessibilityIdentifier("disc.mode")
            DiscKey(symbol: nil, caption: String(localized: "disc.random"), label: String(localized: "disc.random.label"),
                    size: CGSize(width: 80, height: 36),
                    onHoldStart: shuffleAll) {
                toggleRandom()
            }
            .accessibilityValue(String(localized: musicService.shuffleMode != .off ? "disc.random.on" : "disc.random.off"))
            .accessibilityAction(named: String(localized: "spool.shuffleAll")) { shuffleAll() }
            .accessibilityIdentifier("disc.random")
            DiscKey(symbol: "eject.fill", caption: String(localized: "disc.open"), label: String(localized: "disc.open.label"),
                    size: CGSize(width: 80, height: 36)) {
                openDeck()
            }
            .accessibilityIdentifier("disc.open")
        }
    }

    /// The handle under the keys that the Up Next tray is pulled up by.
    private var queueGrip: some View {
        let count = musicService.upcoming.count
        return VStack(spacing: 6) {
            Capsule()
                .fill(theme.ink.opacity(0.4))
                .frame(width: 40, height: 5)
            HStack(spacing: 6) {
                Text(String(localized: "spool.queue.title").uppercased())
                    .tracking(1.5)
                if count > 0 {
                    Text("\(count)")
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(theme.ink.opacity(0.15), in: Capsule())
                }
            }
            .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(theme.ink.opacity(0.8))
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture(perform: openQueue)
        .gesture(queueDrag, isEnabled: !isBrowsing && openCase == nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(String(localized: "spool.queue.open"))
        .accessibilityValue(count > 0 ? String(format: String(localized: "queue.upNextCount"), count) : "")
        .accessibilityAction(.default, openQueue)
        .accessibilityIdentifier("disc.queue.grip")
    }

    private var queueTrayHeight: CGFloat {
        max(320, (containerHeight - safeArea.top - safeArea.bottom) * 0.72)
    }

    private var queueDrag: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(SpoolPlayerView.coordinateSpace))
            .onChanged { value in
                if queueDragStart == nil {
                    queueDragStart = queueProgress
                    isQueueShown = true
                }
                let progress = (queueDragStart ?? 0) - value.translation.height / queueTrayHeight
                withTransaction(Transaction(animation: nil)) { queueProgress = min(1, max(0, progress)) }
            }
            .onEnded { value in
                queueDragStart = nil
                let speed = value.velocity.height
                let opens = speed < -300 || (speed < 300 && -value.translation.height > queueTrayHeight * 0.25)
                opens ? openQueue() : closeQueue()
            }
    }

    // MARK: - Shelf

    /// The search field, the dividers and the shelf of cases: under the deck on the
    /// closed layout, and on the right of an open Duo.
    private func shelfColumn(showsClose: Bool) -> some View {
        VStack(spacing: 10) {
            ShelfSearchField(query: $shelfQuery, prompt: String(localized: "disc.search.prompt"),
                             isFocused: $isShelfSearchFocused)
            ShelfDividers(
                shelf: $shelf,
                title: { ShelfSearchMatches.dividerTitle(Self.shelfTitle($0), on: $0, matches: shelfMatches) },
                onFindShows: { showPodcastSearch = true }
            )
            ZStack {
                TapeCarousel(
                    albums: shelfItems,
                    emptyText: shelfMatches == nil ? Self.emptyText(on: shelf) : String(localized: "search.noResults"),
                    emptyAction: shelf == .podcasts && shelfMatches == nil
                        ? (String(localized: "spool.shelf.findShows"), { showPodcastSearch = true })
                        : nil,
                    card: { album, size in AnyView(JewelCaseCard(album: album, size: size).equatable()) },
                    cardAspectRatio: JewelCaseCard.aspectRatio,
                    // Every case opens to its booklet and songs; swiped left, its disc goes in whole.
                    opensToChoose: { _ in true },
                    swipeLeftLoads: true,
                    byline: { album in
                        [album.caseByline, album.tapeTrackCount.map(album.tapeFormat.count)]
                            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                    },
                    hiddenID: flight?.hiddenID ?? openCase?.id ?? deckLoad?.disc.album?.id,
                    onInsert: { album, frame in insertDisc(album, from: frame) },
                    onShowSongs: { album, _ in openCaseOf(album) },
                    onQueue: { album, placement in queue(album, placement: placement) },
                    onClose: closeDeck,
                    showsClose: showsClose,
                    frontID: shelfFrontID
                )
                .id("\(shelf.rawValue):\(shelfMatches?.query ?? "")")
                .transition(.opacity)
                .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { _ in
                    isShelfSearchFocused = false
                })
            }
        }
        // Stops above the keyboard while it's up.
        .padding(.bottom, max(0, keyboard.height - safeArea.bottom))
    }

    private var shelfItems: [AppAlbum] { shelfMatches?.items(on: shelf) ?? library.items(on: shelf) }

    private var shelfFrontID: Binding<String?> {
        switch shelf {
        case .albums:   return $albumFrontID
        case .mixtapes: return $burnedFrontID
        case .podcasts: return $podcastFrontID
        }
    }

    nonisolated private static func shelfTitle(_ shelf: SpoolShelf) -> String {
        switch shelf {
        case .albums:   return String(localized: "spool.shelf.albums")
        case .mixtapes: return String(localized: "disc.shelf.burned")
        case .podcasts: return String(localized: "spool.shelf.podcasts")
        }
    }

    private static func emptyText(on shelf: SpoolShelf) -> String {
        switch shelf {
        case .albums:   return String(localized: "spool.shelf.empty")
        case .mixtapes: return String(localized: "disc.shelf.burned.empty")
        case .podcasts: return String(localized: "spool.shelf.podcasts.empty")
        }
    }

    // MARK: - Jewel Case

    private func jewelCase(_ album: AppAlbum) -> some View {
        let fromDeck = isCaseFromDeck
        let view = JewelCaseView(
            album: album,
            loadTracks: { await library.tracks(for: album) },
            onPick: { tracks, index, whole, frame in
                openCase = nil
                isCaseFromDeck = false
                let queued = whole ? tracks : [tracks[index]]
                let addToQueue: (() -> Void)? = album.isPodcast ? nil : {
                    queue(queued, placement: .last, name: whole ? album.tapeTitle : tracks[index].title)
                }
                if fromDeck {
                    // The disc is already on the spindle: it plays from the song chosen.
                    musicService.play(asking: { pendingPlay = $0 }, addToQueue: addToQueue) {
                        Task { await startPlaying(LoadedDisc(album: album), tracks: tracks, startingAt: index) }
                    }
                } else {
                    musicService.play(asking: { pendingPlay = $0 }, addToQueue: addToQueue) {
                        changeDisc(LoadedDisc(album: album), from: frame, startingAt: index,
                                   tracks: Task { tracks })
                    }
                }
            },
            onQueue: { tracks, placement in
                queue(tracks, placement: placement, name: tracks.count == 1 ? tracks[0].title : album.tapeTitle)
            },
            onClose: {
                openCase = nil
                isCaseFromDeck = false
            },
            playingID: musicService.currentEpisode?.id ?? musicService.currentTrack?.id
        )
        // On an open Duo the case opens over the shelf, leaving the deck in view.
        return Group {
            if foldMonitor.posture == .open, openShelfFrame.width > 0 {
                view
                    .frame(width: openShelfFrame.width, height: openShelfFrame.height)
                    .position(x: openShelfFrame.midX, y: openShelfFrame.midY)
            } else {
                view
            }
        }
    }

    private func openCaseOf(_ album: AppAlbum) {
        guard openCase == nil, flight == nil else { return }
        isShelfSearchFocused = false
        isCaseFromDeck = false
        openCase = album
    }

    // MARK: - The Flight

    /// A copy of the disc travelling from its case onto the spindle, shrinking or growing
    /// to fit and turning as it goes.
    private func flyingDisc(_ flight: DiscFlight) -> some View {
        let start = flight.start
        let startSize = min(start.width, start.height) * 0.92
        let scale = flight.hasLanded ? seatFrame.width / max(startSize, 1) : 1
        return CompactDisc(kind: flight.disc.kind, art: flight.disc.art, title: flight.disc.title, diameter: startSize)
            .overlay(DiscSheen(diameter: startSize))
            .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 6)
            .rotationEffect(.degrees(flight.hasLanded ? 160 : 0))
            .scaleEffect(scale)
            .position(flight.hasLanded
                      ? CGPoint(x: seatFrame.midX, y: seatFrame.midY)
                      : CGPoint(x: start.midX, y: start.midY))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: - Actions

    private func playPause() {
        if let load = deckLoad {
            deckLoad = nil
            spinUp(load.disc, tracks: load.tracks, startingAt: load.index)
        } else if musicService.hasNowPlaying {
            Task { await musicService.togglePlayPause() }
        } else {
            openDeck()
        }
    }

    private func cycleRepeat() {
        Task {
            await musicService.toggleRepeatMode()
            showNotice(repeatText(musicService.repeatMode))
        }
    }

    private func repeatText(_ mode: RepeatMode) -> String {
        switch mode {
        case .off: return String(localized: "disc.mode.off")
        case .all: return String(localized: "disc.mode.all")
        case .one: return String(localized: "disc.mode.one")
        }
    }

    private func toggleRandom() {
        Task {
            await musicService.toggleShuffleMode()
            showNotice(String(localized: musicService.shuffleMode != .off ? "disc.random.on" : "disc.random.off"))
        }
    }

    /// Every song, shuffled, on a fresh burned disc.
    private func shuffleAll() {
        musicService.play(asking: { pendingPlay = $0 }, addToQueue: {
            queue(library.songs.shuffled(), placement: .last, name: String(localized: "menu.songs"))
        }) { shuffleEverything() }
    }

    private func shuffleEverything() {
        let songs = library.songs.shuffled()
        guard !songs.isEmpty else {
            showNotice(String(localized: "spool.shuffle.empty"))
            return
        }
        showNotice(String(localized: "spool.shuffle.done"))
        deckLoad = nil
        let disc = LoadedDisc(album: nil, title: String(localized: "disc.shuffle.title"), kind: .burned, art: .none,
                              id: "shuffle:\(songs[0].id)")
        spinUp(disc, tracks: Task { songs }, startingAt: 0)
    }

    // MARK: - Changing Discs

    /// Pops the lid and brings the shelf up under the deck.
    private func openDeck() {
        guard foldMonitor.posture != .open, !isLidOpen, flight == nil, !isSpinningUp else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        DiscSound.lidOpen.play()
        withAnimation(.spring(duration: 0.35, bounce: 0.35)) {
            isLidOpen = true
        } completion: {
            withAnimation(.spring(duration: 0.5, bounce: 0.12)) { isBrowsing = true }
        }
    }

    /// Backs out without changing discs.
    private func closeDeck() {
        guard isBrowsing, flight == nil else { return }
        withAnimation(.spring(duration: 0.45, bounce: 0.1)) {
            isBrowsing = false
        } completion: {
            shutLid()
        }
    }

    private func shutLid(then completion: @escaping () -> Void = {}) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        DiscSound.lidClose.play()
        withAnimation(.spring(duration: 0.28, bounce: 0.2)) {
            isLidOpen = false
        } completion: {
            completion()
        }
    }

    /// A case swiped left: its whole disc goes in. Asks first if that would clear songs
    /// the listener queued.
    private func insertDisc(_ album: AppAlbum, from frame: CGRect) {
        guard flight == nil else { return }
        musicService.play(asking: { pendingPlay = $0 },
                          addToQueue: album.isPodcast ? nil : { queue(album, placement: .last) }) {
            changeDisc(LoadedDisc(album: album), from: frame, startingAt: 0,
                       tracks: Task { await library.tracks(for: album) })
        }
    }

    /// Flies `disc` from `frame` onto the spindle. On the closed layout the shelf goes,
    /// the lid shuts and it plays from `index`; on an open Duo it waits for the phone to
    /// close.
    private func changeDisc(_ disc: LoadedDisc, from frame: CGRect, startingAt index: Int,
                            tracks: Task<[AppTrack], Never>) {
        guard flight == nil else { return }
        isShelfSearchFocused = false
        // The old disc comes off, so its song stops.
        if musicService.isPlaying {
            Task { await musicService.togglePlayPause() }
        }
        flight = DiscFlight(disc: disc, start: frame, hiddenID: disc.album?.id)
        // Drawn where it sets off first, then sent on its way.
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.5)) {
                flight?.hasLanded = true
            } completion: {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                DiscSound.seat.play()
                var swap = Transaction()
                swap.disablesAnimations = true
                if foldMonitor.posture == .open {
                    withTransaction(swap) {
                        deckLoad = DiscLoad(disc: disc, tracks: tracks, index: index)
                        flight = nil
                    }
                    return
                }
                withTransaction(swap) {
                    pendingDisc = disc
                    flight = nil
                }
                withAnimation(.spring(duration: 0.45, bounce: 0.1)) {
                    isBrowsing = false
                } completion: {
                    shutLid {
                        spinUp(disc, tracks: tracks, startingAt: index)
                    }
                }
            }
        }
    }

    /// A song picked from Up Next: it comes out of the tray as a disc of its own, the lid
    /// pops, the disc goes on, the lid shuts and it plays. The rest of Up Next stays.
    private func loadFromQueue(_ track: AppTrack, from row: CGRect) {
        guard flight == nil, !isLidOpen, !isSpinningUp, seatFrame.width > 0, row.width > 0 else {
            closeQueue()
            return
        }
        let side = row.height * 0.9
        let start = CGRect(x: row.midX - side / 2, y: row.midY - side / 2, width: side, height: side)
        let disc = LoadedDisc(album: nil, title: TapeFormat.displayTitle(track.albumTitle), kind: .pressed,
                              art: .track(track), id: "queue:\(track.id)")
        let after = musicService.upcoming.filter { $0.id != track.id }
        if musicService.isPlaying {
            Task { await musicService.togglePlayPause() }
        }
        closeQueue()
        let isOpen = foldMonitor.posture == .open
        if !isOpen {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            DiscSound.lidOpen.play()
            withAnimation(.spring(duration: 0.35, bounce: 0.35)) { isLidOpen = true }
        }
        flight = DiscFlight(disc: disc, start: start, hiddenID: nil)
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.55)) {
                flight?.hasLanded = true
            } completion: {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                DiscSound.seat.play()
                var swap = Transaction()
                swap.disablesAnimations = true
                withTransaction(swap) {
                    pendingDisc = disc
                    flight = nil
                }
                let play = {
                    seatedDisc = disc
                    seatedTracks = [track] + after
                    spinUp(forUpcoming: track)
                }
                isOpen ? play() : shutLid(then: play)
            }
        }
    }

    /// The motor bringing a disc up to speed, then the song coming in. The music waits
    /// for the disc, however soon its songs are ready.
    private func spinUp(_ disc: LoadedDisc, tracks: Task<[AppTrack], Never>, startingAt index: Int) {
        DiscSound.spinUp.play()
        pendingDisc = disc
        isSpinningUp = true
        Task {
            async let loaded = tracks.value
            try? await Task.sleep(for: Self.spinUpTime)
            let songs = await loaded
            guard !songs.isEmpty else {
                isSpinningUp = false
                pendingDisc = nil
                showNotice(String(localized: "playback.nothingPlayable"))
                return
            }
            let outcome = await startPlaying(disc, tracks: songs, startingAt: min(index, songs.count - 1))
            isSpinningUp = false
            if outcome != .started { pendingDisc = nil }
        }
    }

    /// The spin-up for a song from Up Next, which then jumps the queue to it.
    private func spinUp(forUpcoming track: AppTrack) {
        DiscSound.spinUp.play()
        isSpinningUp = true
        Task {
            try? await Task.sleep(for: Self.spinUpTime)
            // Found again by identity: the queue may have moved on meanwhile.
            if let offset = musicService.upcoming.firstIndex(where: { $0.id == track.id }) {
                musicService.playUpcoming(at: offset)
            } else {
                showNotice(String(localized: "playback.nothingPlayable"))
            }
            isSpinningUp = false
            try? await Task.sleep(for: .seconds(2))
            if pendingDisc?.id == "queue:\(track.id)" { pendingDisc = nil }
        }
    }

    /// How long a disc takes to come up to speed before it plays.
    private static let spinUpTime: Duration = .milliseconds(700)

    @discardableResult
    private func startPlaying(_ disc: LoadedDisc, tracks: [AppTrack], startingAt index: Int) async -> PlaybackStartOutcome {
        logger.info("Disc playing: \(disc.title, privacy: .private)")
        seatedDisc = disc
        seatedTracks = tracks
        let outcome: PlaybackStartOutcome
        if let album = disc.album {
            outcome = await library.play(album, tracks: tracks, startingAt: index)
        } else {
            outcome = await musicService.play(tracks: tracks, startingAt: index)
        }
        if outcome != .started {
            showNotice(String(localized: "playback.nothingPlayable"))
        }
        return outcome
    }

    // MARK: - Scanning

    /// Scans through the song while ⏮ or ⏭ is held: slowly at first, then faster the
    /// longer it's held. The time follows frame by frame; the player is moved along a few
    /// times a second, so a playing song is heard in snatches, as a CD player cues.
    private func startScanning(forward: Bool) {
        guard musicService.hasNowPlaying, musicService.duration > 0, deckLoad == nil else { return }
        scanTask?.cancel()
        musicService.startScrubbing()
        scanTask = Task {
            let direction: Double = forward ? 1 : -1
            let start = ContinuousClock.now
            var previous = start
            var lastSeek = start
            var time = musicService.clock.time
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                let now = ContinuousClock.now
                let dt = Self.seconds(now - previous)
                previous = now
                let held = Self.seconds(now - start)
                let speed: Double = held < 1.5 ? 6 : held < 4 ? 15 : 30
                let end = max(0, musicService.duration - 1)
                time = min(max(time + direction * speed * dt, 0), end)
                musicService.clock.time = time
                if Self.seconds(now - lastSeek) >= 0.25 {
                    lastSeek = now
                    await musicService.seek(to: time)
                }
            }
        }
    }

    private func stopScanning() {
        guard let task = scanTask else { return }
        task.cancel()
        scanTask = nil
        let time = musicService.clock.time
        Task {
            await musicService.seek(to: time)
            musicService.stopScrubbing()
        }
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    // MARK: - Up Next

    private func openQueue() {
        guard !isBrowsing, flight == nil, openCase == nil else { return }
        isQueueShown = true
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { queueProgress = 1 }
    }

    private func closeQueue() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) {
            queueProgress = 0
        } completion: {
            if queueProgress == 0 { isQueueShown = false }
        }
    }

    private func queue(_ album: AppAlbum, placement: QueuePlacement) {
        guard !album.isPodcast else { return }
        Task {
            let tracks = await library.tracks(for: album)
            queue(tracks, placement: placement, name: album.tapeTitle)
        }
    }

    private func queue(_ tracks: [AppTrack], placement: QueuePlacement, name: String) {
        Task {
            let outcome = await musicService.addToQueue(tracks: tracks, placement: placement)
            if !outcome.succeeded {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.4)
            }
            showNotice(outcome.message(name: name, requested: tracks.count, placement: placement,
                                       isCollection: tracks.count > 1))
        }
    }

    private func showNotice(_ text: String) {
        noticeTask?.cancel()
        notice = text
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            notice = nil
        }
    }
}

/// A disc as the deck shows it.
private struct LoadedDisc {
    /// The album, playlist or show it was pressed from; none for a shuffle or a song
    /// from Up Next.
    let album: AppAlbum?
    let title: String
    let kind: DiscKind
    let art: DiscArt
    let id: String

    init(album: AppAlbum?, title: String, kind: DiscKind, art: DiscArt, id: String) {
        self.album = album
        self.title = title
        self.kind = kind
        self.art = art
        self.id = id
    }

    init(album: AppAlbum) {
        self.init(album: album, title: album.tapeTitle, kind: DiscKind(album), art: .album(album), id: album.id)
    }
}

/// A disc on its way to the spindle.
private struct DiscFlight {
    let disc: LoadedDisc
    /// Where it set off, in SpoolPlayerView.coordinateSpace.
    let start: CGRect
    /// The case on the shelf left empty while its disc is in the air.
    let hiddenID: String?
    var hasLanded = false
}

/// A disc on the spindle of an open Duo, and the song to start it from. Its songs load
/// while it waits; closing the phone plays it.
private struct DiscLoad {
    let disc: LoadedDisc
    let tracks: Task<[AppTrack], Never>
    let index: Int
}
