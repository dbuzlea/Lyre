//
//  SpoolPlayerView.swift
//  Lyre
//

import SwiftUI
import MusicKit
import MediaPlayer
import UIKit
import OSLog

private let logger = Logger(subsystem: "com.pinkhatcreations.lyreapp", category: "SpoolPlayerView")

// MARK: - Spool Player
//
// The cassette player, shown in place of the click-wheel player when Settings → Player
// Style is Spool. It drives the same MusicService, so switching styles mid-song keeps
// playing.
//
// The layout follows the fold posture (see FoldPosture):
//   closed — deck on the left with the cassette stood on end behind a hinged door;
//            transport keys in a strip down the right edge. Tapping the door, eject, or
//            a swipe in from the right edge runs the tape change described under
//            "Changing Tapes" below.
//   open   — iPhone Duo, unfolded: the deck on the left with its door standing open,
//            the tape rack on the right. Swiping a tape left flies it across into the
//            door, with the sound of it going in, and it waits there; closing the
//            phone shuts the door on it (its sound too) and the tape plays. See
//            "Loading on an Open Duo" below.
//   tent   — cassette lying flat with the keys along the bottom edge. Eject opens the
//            tape shelf as a sheet.
//
// Loading on an Open Duo
//   Tapes are chosen as on the closed deck, from the same rack: swiped left, or a song
//   picked in a case. The tape flies from the rack into the open door and seats with the
//   insert sound; what was playing stops, as its tape has come out. A case opens over the
//   rack, its song list above the tray, so a song picked from it is seen to leave the
//   tray, stand upright and go across into the door. Nothing plays yet:
//   the tape waits in the deck (`deckLoad`), its place in the rack left empty, until the
//   phone is closed. Closing it is the door shutting: the door's sound, the motor running
//   up, and the tape playing from the song chosen. A newer tape swiped in takes the
//   waiting one's place.
//
// Changing Tapes (closed)
//   1. The door swings open on its left-hand hinge and the old tape slides out of its
//      seat.
//   2. The page slides left, leaving the open door at the edge, and the tape carousel
//      slides in beside it.
//   3. Swiping a tape left hands it to a flying copy, which turns upright and drops into
//      the door. The real card is hidden meanwhile so the tape is only drawn once.
//   4. The page slides back, the door shuts, and the tape plays. Its tracks start loading
//      the moment it leaves the carousel, so they are usually ready by the time it lands.
//   Tapping the open door or the carousel's close button backs out, and the old tape
//   drops back into its seat.
//
// Searching (closed)
//   The search field over the shelf dividers narrows the rack to the tapes that match
//   what's typed, a song bringing up the album it's on (see ShelfSearchField). The rack
//   stops above the keyboard while it's up. Putting a tape in, or opening its case,
//   puts the keyboard away; closing the rack clears the search. The open shelf and the
//   tent layout's shelf sheet have a search field of their own (TapeShelfView).
//
// An iPhone without a hinge is always closed. On iPhone Duo, opening the phone reaches
// `open`; `tent` is only reachable through the debug override in the options menu, since
// the hinge cannot tell it apart from `open` (see FoldPosture).

struct SpoolPlayerView: View {
    /// Coordinate space the carousel and the door report frames in, so a tape can fly
    /// between them.
    static let coordinateSpace = "SpoolPlayer"

    @ObservedObject var musicService: MusicService
    let themeSettings: ThemeSettings
    let foldMonitor: FoldPostureMonitor

    @State private var showShelf = false
    @State private var showSettings = false
    @State private var showPodcastSearch = false
    /// The Up Next tray: in the view while `isQueueShown`, and `queueProgress` of the way
    /// up (0 put away, 1 open), which a finger on its grip or header scrubs.
    @State private var isQueueShown = false
    @State private var queueProgress: CGFloat = 0
    @State private var queueDragStart: CGFloat?
    @State private var containerHeight: CGFloat = 0
    /// A tape put in the open deck on an unfolded Duo, waiting for the phone to close.
    @State private var deckLoad: DeckLoad?
    /// The rack's half of an unfolded Duo, where a case opens.
    @State private var openRackFrame: CGRect = .zero
    /// A tape waiting to go in, as it would clear songs queued by hand.
    @State private var pendingPlay: PendingPlay?
    @State private var notice: String?
    /// The new tape's motor turning: from the door shutting until its first song plays,
    /// the reels spin and the play key is down while the player starts the song.
    @State private var isMotorRunning = false
    /// Fast forward or rewind held down, winding through the song.
    @State private var windTask: Task<Void, Never>?
    @State private var noticeTask: Task<Void, Never>?

    // Tape change (closed posture)
    @State private var isDoorOpen = false
    @State private var isBrowsing = false
    @State private var flight: TapeFlight?
    /// True from the moment a new tape lands until the door has shut on it.
    @State private var isNewTapeSeated = false
    /// Where a seated tape sits, in `coordinateSpace`.
    @State private var seatFrame: CGRect = .zero
    /// The new tape, shown on the label until its first track is playing.
    @State private var pendingTape: AppAlbum?
    /// A song picked from Up Next, shown on the tape until it is playing.
    @State private var pendingTrack: AppTrack?
    /// The old tape slid out of its seat while the door is open for a song from Up Next.
    @State private var isOldTapeOut = false
    /// The last tape put in the deck. While its songs play, the deck draws it in its own
    /// format (a cassingle stays a cassingle).
    @State private var seatedTape: AppAlbum?
    /// The tape whose case is open, showing its J-card and track list.
    @State private var openCase: CaseScene?
    /// How far the open case has come out of the rack: 0 closed in its slot, 1 open.
    @State private var caseProgress: CGFloat = 0
    /// The tape last at the front of the rack, so the rack reopens where it was left.
    /// Stored, so it lasts across launches too.
    @AppStorage("SpoolRackFrontID") private var rackFrontID: String?
    /// The same for the mixtape shelf.
    @AppStorage("SpoolMixtapeFrontID") private var mixtapeFrontID: String?
    @AppStorage("SpoolPodcastFrontID") private var podcastFrontID: String?
    /// The shelf the rack shows: albums or mixtapes. Kept, so the rack reopens on it.
    @AppStorage("SpoolShelf") private var shelf: SpoolShelf = .albums
    /// What's typed over the rack, and the tapes it leaves on each shelf; nil when
    /// nothing is being searched for.
    @State private var shelfQuery = ""
    @State private var shelfMatches: ShelfSearchMatches?
    @FocusState private var isShelfSearchFocused: Bool
    @State private var keyboard = KeyboardMonitor()
    /// The door's right edge with the page at rest, which sets how far the page slides.
    @State private var doorRestingMaxX: CGFloat = 0
    /// LyreView ignores the safe area so the classic body bleeds to the edges, which
    /// leaves SwiftUI reporting zero insets here; ContentView measures them instead.
    @Environment(\.windowSafeArea) private var safeArea

    var body: some View {
        ZStack {
            theme.bodyGradient
                .ignoresSafeArea()

            Group {
                switch foldMonitor.posture {
                case .closed: closedLayout
                case .open:   openLayout
                case .tent:   tentLayout
                }
            }
            .padding(safeArea)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: foldMonitor.posture)

            if let scene = openCase {
                CassetteCaseView(
                    album: scene.album,
                    progress: caseProgress,
                    closedFrame: scene.closedFrame,
                    loadTracks: { await tapeTracks(for: scene.album) },
                    onPick: { tracks, index, frame in
                        if scene.isFromDeck {
                            // The tape is already in the deck: the case goes back and
                            // the tape plays from the chosen song.
                            closeCase()
                            musicService.play(asking: { pendingPlay = $0 },
                                              addToQueue: queueSong(index, of: tracks, on: scene.album)) {
                                SpoolSound.buttonPress.play()
                                play(LoadedTape(album: scene.album, tracks: tracks), startingAt: index)
                            }
                            return
                        }
                        // The case goes as the cassette leaves its tray for the deck.
                        withAnimation(.easeOut(duration: 0.25)) { openCase = nil }
                        caseProgress = 0
                        insertTape(scene.album, from: frame, startingAt: index, tracks: tracks)
                    },
                    onQueue: { tracks, placement in
                        queue(tracks, placement: placement, name: tracks.count == 1 ? tracks[0].title : scene.album.tapeTitle)
                    },
                    onClose: closeCase,
                    playingID: musicService.currentEpisode?.id ?? musicService.currentTrack?.id,
                    onScrub: { progress in
                        withTransaction(Transaction(animation: nil)) { caseProgress = progress }
                    },
                    onScrubEnd: { closes in
                        if closes {
                            closeCase()
                        } else {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { caseProgress = 1 }
                        }
                    },
                    onReady: {
                        withAnimation(.spring(response: 0.62, dampingFraction: 0.84)) { caseProgress = 1 }
                    },
                    // On an open Duo the case opens over the rack, leaving the deck in view.
                    bounds: foldMonitor.posture == .open && openRackFrame.width > 0 ? openRackFrame : nil
                )
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
                flyingTape(flight)
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
                    .accessibilityIdentifier("spool.notice")
                    // Over the open case, whose songs can be queued.
                    .zIndex(5)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: notice)
        .environment(\.spoolTheme, theme)
        .coordinateSpace(name: Self.coordinateSpace)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { containerHeight = $0 }
        .sheet(isPresented: $showSettings) {
            SpoolSettingsView(musicService: musicService, themeSettings: themeSettings,
                              foldMonitor: foldMonitor) { showSettings = false }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPodcastSearch) {
            PodcastSearchView(musicService: musicService)
        }
        .replaceQueuePrompt($pendingPlay, count: musicService.listenerQueuedCount)
        .sheet(isPresented: $showShelf) {
            TapeShelfView(albums: musicService.albums, hint: String(localized: "spool.shelf.hint.closed"),
                          songs: musicService.songs) { album in
                showShelf = false
                insert(album, thenPlay: true)
            }
            .presentationDetents([.medium, .large])
        }
        // A new song, or a new episode streaming: the tape going in is now playing.
        .onChange(of: musicService.currentTrack?.id ?? musicService.currentEpisode?.id) {
            pendingTape = nil
            pendingTrack = nil
        }
        .onChange(of: foldMonitor.posture) { _, posture in
            // Unfolding mid-change abandons it; the open posture has its own shelf.
            isBrowsing = false
            isDoorOpen = false
            switch posture {
            case .closed, .tent:
                // Closing the phone shuts the door on a tape waiting in the deck: the
                // door's sound, the motor running up, and the tape plays.
                if let load = deckLoad {
                    deckLoad = nil
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    SpoolSound.doorClose.play()
                    startMotor(load.album, tracks: load.tracks, startingAt: load.index)
                }
            case .open:
                showShelf = false
            }
        }
        .modifier(ShelfSearching(query: shelfQuery, library: library, shelf: $shelf, matches: $shelfMatches))
        .onChange(of: isBrowsing) { _, browsing in
            // The rack opens on the whole shelf each time.
            guard !browsing else { return }
            isShelfSearchFocused = false
            shelfQuery = ""
        }
        .onChange(of: themeSettings.spoolModel) {
            // A different body has its door somewhere else; start again from closed.
            isBrowsing = false
            isDoorOpen = false
            doorRestingMaxX = 0
        }
        .onAppear {
            _ = Self.resetRackForUITests
            #if DEBUG
            // `--spool-sample-queue` puts the first sample tape's songs in the queue, so
            // Up Next has something to show on a simulator with no music.
            if ProcessInfo.processInfo.arguments.contains("--spool-sample-queue"),
               musicService.upNext.isEmpty, let tape = tapes.first {
                musicService.seedQueueForUITests(tape.preloadedTracks)
            }
            #endif
        }
        .onDisappear {
            noticeTask?.cancel()
            stopWinding()
        }
    }

    /// `--spool-reset-rack` at launch forgets where the rack was left, and which shelf it
    /// was on, once, so each UI test starts from the first album. Debug builds only.
    private static let resetRackForUITests: Void = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--spool-reset-rack") {
            UserDefaults.standard.removeObject(forKey: "SpoolRackFrontID")
            UserDefaults.standard.removeObject(forKey: "SpoolMixtapeFrontID")
            UserDefaults.standard.removeObject(forKey: "SpoolPodcastFrontID")
            UserDefaults.standard.removeObject(forKey: "SpoolShelf")
        }
        #endif
    }()

    private var theme: SpoolTheme { themeSettings.spoolFinish.theme }
    private var model: SpoolModel { themeSettings.spoolModel }

    // MARK: - Layouts

    /// Width of the key strip in the closed layout, and the gap before it.
    private static let stripWidth: CGFloat = 92
    private static let stripSpacing: CGFloat = 12
    private static let deckLeading: CGFloat = 24
    /// How much of the screen the open door keeps while the carousel is out.
    private static let doorShareWhileBrowsing: CGFloat = 0.34

    private var closedLayout: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            // Slide the page until the door's right edge sits at the share it keeps.
            let doorMaxX = doorRestingMaxX > 0 ? doorRestingMaxX : width - Self.deckLeading
            let pageShift = max(0, doorMaxX - width * Self.doorShareWhileBrowsing)
            let carouselWidth = width - width * Self.doorShareWhileBrowsing - 20

            ZStack(alignment: .trailing) {
                Group {
                    switch model {
                    case .original: originalDeck(pageShift: pageShift)
                    case .slim:     slimDeck
                    }
                }
                .offset(x: isBrowsing ? -pageShift : 0)

                if isBrowsing {
                    rackColumn(showsClose: true)
                        .frame(width: carouselWidth)
                        // Full height: the rack runs from under the header to just above
                        // the home indicator.
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            // A swipe in from the right edge opens the door, like the eject key.
            // Simultaneous so a key under the finger still takes an ordinary press.
            .simultaneousGesture(edgeSwipe(width: width), isEnabled: !isDoorOpen && flight == nil)
        }
    }

    /// The original: the deck stood upright beside a metal rail carrying the keys.
    private func originalDeck(pageShift: CGFloat) -> some View {
        HStack(spacing: Self.stripSpacing) {
            VStack(spacing: 16) {
                originalBrand
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(isBrowsing ? 0 : 1)
                Spacer(minLength: 0)
                door
                Spacer(minLength: 0)
                queueGrip
                    .opacity(isBrowsing ? 0 : 1)
            }
            .padding(.leading, Self.deckLeading)
            .padding(.vertical, 20)

            // The rail leaves the other way, clearing the right side for the rack.
            keyStrip(axis: .vertical)
                .frame(width: Self.stripWidth)
                .offset(x: isBrowsing ? pageShift + Self.stripWidth + Self.stripSpacing : 0)
                .opacity(isBrowsing ? 0 : 1)
        }
    }

    /// The slim: keys along the top edge, a logo plate, and the tape lying flat behind a
    /// pill-shaped window.
    private var slimDeck: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                keyBank(axis: .horizontal, compact: true)
                Spacer(minLength: 4)
                optionsMenu
            }
            .opacity(isBrowsing ? 0 : 1)

            slimLogoPlate
                .opacity(isBrowsing ? 0 : 1)

            Spacer(minLength: 0)
            door
            Spacer(minLength: 0)
            queueGrip
                .opacity(isBrowsing ? 0 : 1)
        }
        .padding(.horizontal, Self.deckLeading)
        .padding(.vertical, 20)
    }

    /// How far in from the right edge a swipe must start to open the door.
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

    /// The tape compartment. Tapping it opens the door to change tapes, or backs out.
    private var door: some View {
        CassetteDoor(
            isOpen: isDoorOpen,
            showsTape: (!isBrowsing && !isOldTapeOut) || isNewTapeSeated,
            hinge: model == .original ? .leading : .bottom,
            window: model == .original
                ? .inset(CGRect(x: 0.24, y: 0.18, width: 0.52, height: 0.64))
                : .pill(CGRect(x: 0.08, y: 0.2, width: 0.84, height: 0.6)),
            markings: model == .original ? AnyView(originalDoorMarkings) : AnyView(slimDoorMarkings),
            onSeatFrame: { seatFrame = $0 }
        ) {
            cassette(axis: model.tapeAxis)
        }
        .aspectRatio(model == .original ? 0.66 : 1.42, contentMode: .fit)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .named(Self.coordinateSpace)).maxX
        } action: { maxX in
            // Only at rest; while browsing it reports the slid position.
            if !isBrowsing { doorRestingMaxX = maxX }
        }
        // Holding the door brings up the playing album's case; a tap works the door.
        // The hold is tried first, so a press let go early is still a tap.
        .gesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in showCaseInDeck() }
                .exclusively(before: TapGesture().onEnded { isBrowsing ? closeDeck() : openDeck() })
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("spool.door")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isBrowsing
                           ? String(localized: "spool.door.close")
                           : String(localized: "spool.door.open"))
        .accessibilityAction { isBrowsing ? closeDeck() : openDeck() }
        .accessibilityActions {
            if caseInDeck != nil {
                Button(String(localized: "spool.carousel.showSongs")) { showCaseInDeck() }
            }
        }
    }

    /// The album in the deck, when it's one that comes in a case: the tape whose songs
    /// are playing (or paused), or the tape last put in if nothing else has played since.
    private var caseInDeck: AppAlbum? {
        guard let tape = seatedTape, tape.comesInCase else { return nil }
        guard let track = musicService.currentTrack else { return tape }
        return isPlaying(track, from: tape) ? tape : nil
    }

    /// Whether what's playing came off `tape`, the last tape put in the deck.
    private func isSeatedTapePlaying(_ tape: AppAlbum) -> Bool { library.isPlaying(from: tape) }

    private func isPlaying(_ track: AppTrack, from tape: AppAlbum) -> Bool {
        library.isPlaying(track, from: tape)
    }

    /// Lifts the playing album's case out of the closed door and opens it on its songs.
    private func showCaseInDeck() {
        guard let album = caseInDeck, !isDoorOpen, !isBrowsing, !isMotorRunning,
              flight == nil, openCase == nil, seatFrame.width > 0 else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // The closed case, lying flat, as big as fits over the tape in the door.
        let aspect = CassetteView.aspectRatio
        let width = min(seatFrame.width, seatFrame.height * aspect)
        let frame = CGRect(x: seatFrame.midX - width / 2, y: seatFrame.midY - width / aspect / 2,
                           width: width, height: width / aspect)
        caseProgress = 0
        openCase = CaseScene(album: album, closedFrame: frame, isFromDeck: true)
    }

    /// The copy of a tape that travels from the carousel into the door, shrinking to fit
    /// the seat as it goes. The original stands its tape upright, so the tape turns on
    /// the way; the slim takes it lying flat.
    private func flyingTape(_ flight: TapeFlight) -> some View {
        let start = flight.start
        let turns = model.tapeAxis == .vertical
        let scale = turns
            ? min(seatFrame.height / max(start.width, 1), seatFrame.width / max(start.height, 1))
            : min(seatFrame.width / max(start.width, 1), seatFrame.height / max(start.height, 1))
        let held = flight.isLifted ? flight.lift ?? start : start
        return CassetteShell(
            transport: CassetteShell.resting,
            title: flight.title,
            size: start.size,
            labelArt: flight.labelArt,
            format: flight.format,
            trackCount: flight.trackCount,
            blank: flight.blank
        )
        .frame(width: start.width, height: start.height)
        .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 6)
        .rotationEffect(.degrees(flight.hasLanded && turns ? 90 : 0))
        .scaleEffect(flight.hasLanded ? scale : held.width / max(start.width, 1))
        .position(flight.hasLanded
                  ? CGPoint(x: seatFrame.midX, y: seatFrame.midY)
                  : CGPoint(x: held.midX, y: held.midY))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var tentLayout: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                cassette(axis: .horizontal)
                brand
                    .fixedSize()
                    .rotationEffect(.degrees(90))
                    .frame(width: 44)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .frame(maxHeight: .infinity)

            keyStrip(axis: .horizontal)
                .frame(height: 92)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
    }

    /// The rack and what's over it: the search field and the shelf dividers. Beside the
    /// open door on the closed deck, and on the right of an open Duo.
    private func rackColumn(showsClose: Bool) -> some View {
        VStack(spacing: 10) {
            ShelfSearchField(query: $shelfQuery, prompt: String(localized: "spool.search.prompt"),
                             isFocused: $isShelfSearchFocused)
            ShelfDividers(
                shelf: $shelf,
                title: { ShelfSearchMatches.dividerTitle($0.title, on: $0, matches: shelfMatches) },
                onFindShows: { showPodcastSearch = true }
            )
            // Each shelf is its own rack, so it opens on its own front tape;
            // switching crossfades one rack for the other.
            ZStack {
                TapeCarousel(
                    albums: shelfTapes,
                    emptyText: shelfEmptyText,
                    emptyAction: shelf == .podcasts && shelfMatches == nil
                        ? (String(localized: "spool.shelf.findShows"), { showPodcastSearch = true })
                        : nil,
                    // The tape in flight, the case out of the rack, or a tape waiting in an
                    // open Duo's deck, leaves a gap.
                    hiddenID: flight?.hiddenID ?? openCase?.album.id ?? deckLoad?.album.id,
                    onInsert: { album, frame in insertTape(album, from: frame) },
                    onShowSongs: { album, frame in openCaseOf(album, from: frame) },
                    onQueue: { album, placement in queue(album, placement: placement) },
                    onClose: closeDeck,
                    showsClose: showsClose,
                    frontID: shelfFrontID
                )
                // Rebuilt for each search too, so it opens on a tape that's there.
                .id("\(shelf.rawValue):\(shelfMatches?.query ?? "")")
                .transition(.opacity)
                // Going through the rack is the sign typing is done.
                .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { _ in
                    isShelfSearchFocused = false
                })
            }
        }
        // Stops above the keyboard while it's up. LyreView ignores the keyboard's safe
        // area, so the rack has to make the room itself.
        .padding(.bottom, max(0, keyboard.height - safeArea.bottom))
    }

    /// An unfolded iPhone Duo: the deck on the left, its door standing open, and the rack
    /// on the right. A tape swiped left from the rack flies across into the door and
    /// waits there; closing the phone plays it (see "Loading on an Open Duo").
    private var openLayout: some View {
        GeometryReader { geometry in
            HStack(spacing: 16) {
                unfoldedDeck
                    .frame(width: geometry.size.width * 0.46)
                rackColumn(showsClose: false)
                    .padding(.top, 8)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named(Self.coordinateSpace))
                    } action: { openRackFrame = $0 }
            }
            .padding(12)
        }
    }

    /// The deck with its door open, waiting for a tape: the one swiped in from the rack,
    /// or the one already playing.
    private var unfoldedDeck: some View {
        VStack(spacing: 18) {
            HStack {
                brand
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Spacer(minLength: 8)
                optionsMenu
            }
            Spacer(minLength: 0)
            CassetteDoor(
                isOpen: true,
                // Empty while a tape is on its way in: the old one has come out.
                showsTape: flight == nil && (deckLoad != nil || musicService.hasNowPlaying),
                hinge: model == .original ? .leading : .bottom,
                window: model == .original
                    ? .inset(CGRect(x: 0.24, y: 0.18, width: 0.52, height: 0.64))
                    : .pill(CGRect(x: 0.08, y: 0.2, width: 0.84, height: 0.6)),
                // Bare: the closed door's caption, "tap the door to choose a tape", is
                // for the closed deck; here the tape comes from the rack beside it.
                markings: AnyView(EmptyView()),
                onSeatFrame: { seatFrame = $0 }
            ) {
                cassette(axis: model.tapeAxis)
            }
            .aspectRatio(model == .original ? 0.66 : 1.42, contentMode: .fit)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("spool.door")
            .accessibilityValue(deckLoad.map { $0.album.tapeTitle } ?? "")
            Spacer(minLength: 0)
            Text(String(localized: deckLoad == nil ? "spool.open.hint" : "spool.closeToPlay"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(theme.ink.opacity(0.12), in: Capsule())
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: deckLoad == nil)
                .accessibilityIdentifier("spool.open.hint")
        }
        .padding(.vertical, 12)
    }

    // MARK: - Pieces

    private var brand: some View {
        Text(String(localized: "spool.brand"))
            .font(.system(size: 34, weight: .black, design: .rounded))
            .tracking(4)
            .foregroundStyle(theme.logo)
            .accessibilityHidden(true)
    }

    /// The model line printed in the original's top corner. The name itself is on the
    /// door.
    private var originalBrand: some View {
        Text(String(localized: "spool.subtitle"))
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(theme.ink.opacity(0.75))
            .accessibilityHidden(true)
    }

    /// Embossed on the original's door: the name above the window, an arrow beside it
    /// showing which way the tape goes in, and what's playing.
    private var originalDoorMarkings: some View {
        GeometryReader { geometry in
            let size = geometry.size
            Text(String(localized: "spool.brand"))
                .font(.system(size: size.width * 0.1, weight: .heavy, design: .rounded))
                .tracking(size.width * 0.01)
                .foregroundStyle(theme.ink.opacity(0.9))
                .shadow(color: .black.opacity(0.3), radius: 0, x: 0, y: 1)
                .position(x: size.width * 0.5, y: size.height * 0.1)
                .accessibilityHidden(true)
            Image(systemName: "arrow.up")
                .font(.system(size: size.width * 0.09, weight: .light))
                .foregroundStyle(theme.ink.opacity(0.85))
                .position(x: size.width * 0.88, y: size.height * 0.56)
                .accessibilityHidden(true)
            // What's playing, printed up the strip left of the window like the spine of
            // a case, reading from the bottom.
            nowPlayingCaption(titleSize: size.width * 0.068, subtitleSize: size.width * 0.054)
                .frame(width: size.height * 0.64, alignment: .leading)
                .rotationEffect(.degrees(-90))
                .position(x: size.width * 0.13, y: size.height * 0.5)
        }
    }

    /// Printed on the slim's door: what's playing, under the window.
    private var slimDoorMarkings: some View {
        GeometryReader { geometry in
            let size = geometry.size
            nowPlayingCaption(titleSize: size.height * 0.072, subtitleSize: size.height * 0.058)
                .frame(width: size.width * 0.8, alignment: .leading)
                .position(x: size.width * 0.5, y: size.height * 0.9)
        }
    }

    /// The slim's metal plate: the name on the left, STEREO in the accent script on the
    /// right, a pinstripe along the top, and the elapsed time.
    private var slimLogoPlate: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(String(localized: "spool.brand"))
                .font(.system(size: 26, weight: .heavy, design: .serif))
                .tracking(5)
                .foregroundStyle(theme.isLight ? theme.ink : theme.keySymbol)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(localized: "spool.stereo"))
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .italic()
                    .foregroundStyle(theme.isLight ? theme.logo : theme.accent)
                counter
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [theme.railLight, theme.rail], startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(theme.isLight ? theme.logo : theme.accent)
                        .frame(height: 3)
                        .padding(.top, 6)
                }
                .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 2)
        )
        .accessibilityHidden(true)
    }

    private func cassette(axis: Axis) -> some View {
        // A tape that isn't playing yet sits still at the start of side A.
        let tape = pendingTape ?? deckLoad?.album
        let isIdle = tape != nil || pendingTrack != nil
        // The tape in the deck, if what's playing came from it.
        let seated = pendingTrack != nil ? nil : tape ?? seatedTape.flatMap { seated in
            isSeatedTapePlaying(seated) ? seated : nil
        }
        // A podcast keeps its show's tape in the deck: a streamed episode has no song
        // whose cover could stand in for the label.
        let labelled = tape ?? (seated?.isPodcast == true ? seated : nil)
        return CassetteView(
            clock: musicService.clock,
            duration: isIdle ? 0 : musicService.duration,
            // A new tape's reels start turning with its motor, before the song does.
            isPlaying: (!isIdle && musicService.isPlaying) || isMotorRunning,
            title: labelled?.tapeTitle ?? pendingTrack?.title ?? nowPlayingTitle,
            labelArt: labelled.map(TapeLabelArt.album) ?? (pendingTrack ?? musicService.currentTrack).map(TapeLabelArt.track),
            format: seated?.tapeFormat ?? .album,
            trackCount: seated?.tapeTrackCount,
            blank: seated?.tapeBlank,
            axis: axis
        )
        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
    }

    /// The song and artist, printed on the door. Sized by the door, so it scales with it.
    private func nowPlayingCaption(titleSize: CGFloat, subtitleSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(nowPlayingTitle ?? String(localized: "spool.noTape"))
                .font(.system(size: titleSize, weight: .semibold))
            Text(nowPlayingTitle == nil ? String(localized: "spool.noTape.hint") : nowPlayingSubtitle ?? "")
                .font(.system(size: subtitleSize))
                .opacity(0.75)
        }
        .lineLimit(1)
        .foregroundStyle(theme.ink)
        .shadow(color: .white.opacity(theme.isLight ? 0.25 : 0), radius: 0, x: 0, y: 1)
    }

    /// The transport keys on their steel strip, stacked down the edge or along the bottom.
    private func keyStrip(axis: Axis) -> some View {
        let layout = axis == .vertical
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            if axis == .vertical {
                hotlineMenu
                airPlayKey
                counter
                Spacer(minLength: 8)
            }
            // The keys stand proud of the rail, out past its inner edge, as on the
            // original's side.
            keyBank(axis: axis)
                .offset(x: axis == .vertical ? -Self.keyOverhang : 0,
                        y: axis == .horizontal ? -Self.keyOverhang : 0)
            if axis == .vertical {
                Spacer(minLength: 8)
            } else {
                // The time readout is the first thing to go when the strip is narrow.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        Spacer(minLength: 8)
                        counter
                        optionsMenu
                    }
                    HStack {
                        Spacer(minLength: 0)
                        optionsMenu
                    }
                }
            }
        }
        .padding(axis == .vertical ? .vertical : .horizontal, 18)
        .padding(axis == .vertical ? .horizontal : .vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(theme.railGradient)
                // Brushed grain.
                .overlay(
                    LinearGradient(colors: [.white.opacity(0.12), .clear, .white.opacity(0.08), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .clipShape(RoundedRectangle(cornerRadius: 28))
                )
                .shadow(color: .black.opacity(0.25), radius: 6, x: -2, y: 0)
        )
    }

    /// How far the keys stand out past the rail's edge.
    private static let keyOverhang: CGFloat = 18

    /// The transport keys side by side like piano keys. Down the original's rail they
    /// stand out to the left and push in to the right; along a top or bottom edge they
    /// stand up and push down. Play latches down while the tape plays.
    private func keyBank(axis: Axis, compact: Bool = false) -> some View {
        let isPlaying = (musicService.isPlaying && deckLoad == nil) || isMotorRunning
        let isPodcast = musicService.isPlayingPodcast && deckLoad == nil && pendingTrack == nil
        let proud: Edge = axis == .vertical ? .leading : .top
        let layout = axis == .vertical
            ? AnyLayout(VStackLayout(spacing: 2))
            : AnyLayout(HStackLayout(spacing: 2))
        return layout {
            SpoolKey(symbol: isPlaying ? "pause.fill" : "play.fill",
                     label: isPlaying ? String(localized: "spool.pause") : String(localized: "spool.play"),
                     isAccent: true, isLatched: isPlaying, compact: compact, proudEdge: proud) {
                playPause()
            }
            // Tapped, the wind keys skip a song, or for a podcast jump 30 seconds on or
            // 15 back; held, they wind through this one.
            SpoolKey(symbol: isPodcast ? "goforward.30" : "forward.fill",
                     label: String(localized: isPodcast ? "spool.skipForward" : "spool.next"),
                     compact: compact, proudEdge: proud,
                     onHoldStart: { startWinding(forward: true) }, onHoldEnd: stopWinding) {
                if isPodcast {
                    jump(by: PodcastStreamPlayer.skipForwardInterval)
                } else {
                    Task { await musicService.skipToNext() }
                }
            }
            SpoolKey(symbol: isPodcast ? "gobackward.15" : "backward.fill",
                     label: String(localized: isPodcast ? "spool.skipBack" : "spool.previous"),
                     compact: compact, proudEdge: proud,
                     onHoldStart: { startWinding(forward: false) }, onHoldEnd: stopWinding) {
                if isPodcast {
                    jump(by: -PodcastStreamPlayer.skipBackwardInterval)
                } else {
                    // Back to the song's start once it's under way, as on every player.
                    Task { await musicService.previousOrRestart() }
                }
            }
            // Tapped, eject opens the deck to change tapes; held, it shuffles every song,
            // as a shake does on the click wheel and the crank on the gramophone.
            SpoolKey(symbol: "eject.fill", label: String(localized: "spool.eject"),
                     compact: compact, proudEdge: proud,
                     onHoldStart: shuffleAll) {
                chooseTape()
            }
            .accessibilityAction(named: String(localized: "spool.shuffleAll")) { shuffleAll() }
        }
    }

    /// AirPlay, then Settings.
    private var optionsMenu: some View {
        HStack(spacing: 8) {
            airPlayKey
            Button { showSettings = true } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.keySymbol)
                    .frame(width: 36, height: 36)
                    .background(theme.keyLight.opacity(0.7), in: Circle())
            }
            .accessibilityLabel(String(localized: "settings.title"))
            .accessibilityIdentifier("spool.settings")
        }
    }

    /// Where it plays: the phone, or an AirPlay speaker. Lit in the accent colour while
    /// it's on one.
    private var airPlayKey: some View {
        AirPlayRouteButton(identifier: "spool.airplay") { isActive in
            Image(systemName: "airplayaudio")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(isActive ? theme.accent : theme.keySymbol)
                .frame(width: 36, height: 36)
                .background(theme.keyLight.opacity(0.7), in: Circle())
        }
    }

    /// The original's orange hotline button on top of the rail, which opens Settings.
    private var hotlineMenu: some View {
        Button { showSettings = true } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 48, height: 30)
                .background(
                    Capsule()
                        .fill(LinearGradient(colors: [theme.accentLight, theme.accent],
                                             startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)
                )
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(String(localized: "settings.title"))
        .accessibilityIdentifier("spool.settings")
    }

    /// The tape counter. Tapped, it brings up Up Next. For a podcast it counts down
    /// what's left, and the speed knob sits under it.
    private var counter: some View {
        let isPodcast = musicService.isPlayingPodcast
        return VStack(spacing: 4) {
            Button(action: openQueue) {
                ElapsedTimeLabel(clock: musicService.clock,
                                 remainingOf: isPodcast ? musicService.duration : nil)
                    .frame(minWidth: 44, minHeight: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "spool.queue.open"))
            if isPodcast {
                speedKnob
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPodcast)
    }

    /// A podcast's playing speed, like a deck's pitch control: 0.75× to 2×.
    private var speedKnob: some View {
        Menu {
            ForEach(MusicService.podcastRates, id: \.self) { rate in
                Button {
                    musicService.setPodcastRate(rate)
                } label: {
                    if rate == musicService.podcastRate {
                        Label(Self.speedText(rate), systemImage: "checkmark")
                    } else {
                        Text(Self.speedText(rate))
                    }
                }
            }
        } label: {
            Text(Self.speedText(musicService.podcastRate))
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(theme.keySymbol)
                .padding(.horizontal, 8)
                .frame(minWidth: 44, minHeight: 24)
                .background(theme.keyLight.opacity(0.8), in: Capsule())
                .overlay(Capsule().strokeBorder(theme.keySymbol.opacity(0.25), lineWidth: 1))
                .frame(minHeight: 30)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(String(localized: "spool.speed"))
        .accessibilityValue(Self.speedText(musicService.podcastRate))
        .accessibilityIdentifier("spool.speed")
    }

    /// "1×", "1.25×".
    static func speedText(_ rate: Float) -> String {
        rate.formatted(.number.precision(.fractionLength(0...2))) + "×"
    }

    /// Jumps through a podcast by `seconds`. The key's own click is the sound of it.
    private func jump(by seconds: TimeInterval) {
        Task { await musicService.jump(by: seconds) }
    }

    /// Every song, shuffled, straight into the deck.
    private func shuffleAll() {
        // A shuffle replaces Up Next: ask first if it holds songs queued by hand.
        musicService.play(asking: { pendingPlay = $0 }, addToQueue: {
            let songs = library.songs.shuffled()
            queue(songs, placement: .last, name: String(localized: "menu.songs"))
        }) { shuffleEverything() }
    }

    /// Queueing song `index` of `tracks` instead of playing it, offered when asking; nil
    /// for a show's episodes, which aren't queued.
    private func queueSong(_ index: Int, of tracks: [AppTrack], on album: AppAlbum) -> (() -> Void)? {
        guard !album.isPodcast, tracks.indices.contains(index) else { return nil }
        return { queue([tracks[index]], placement: .last, name: tracks[index].title) }
    }

    private func shuffleEverything() {
        let songs = library.songs.shuffled()
        guard !songs.isEmpty else {
            showNotice(String(localized: "spool.shuffle.empty"))
            return
        }
        showNotice(String(localized: "spool.shuffle.done"))
        deckLoad = nil
        pendingTape = nil
        seatedTape = nil
        Task {
            if await musicService.play(tracks: songs, startingAt: 0) != .started {
                showNotice(String(localized: "playback.nothingPlayable"))
            }
        }
    }

    /// The handle under the door that the Up Next tray is pulled up by.
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
        .accessibilityIdentifier("spool.queue.grip")
    }

    /// How tall the Up Next tray stands when it is all the way up.
    private var queueTrayHeight: CGFloat {
        max(320, (containerHeight - safeArea.top - safeArea.bottom) * 0.72)
    }

    /// Pulls the tray up after the finger, from the grip.
    private var queueDrag: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.coordinateSpace))
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

    // MARK: - Tapes

    /// The library as the rack shows it (see ShelfLibrary).
    private var library: ShelfLibrary { ShelfLibrary(musicService: musicService) }
    private var tapes: [AppAlbum] { library.albums }
    private var mixtapes: [AppAlbum] { library.mixtapes }
    private var podcastTapes: [AppAlbum] { library.podcasts }

    /// The tapes on the shelf the rack is showing: those that match, while searching.
    private var shelfTapes: [AppAlbum] { shelfMatches?.items(on: shelf) ?? library.items(on: shelf) }

    private var shelfEmptyText: String {
        shelfMatches == nil ? ShelfLibrary.emptyText(on: shelf) : String(localized: "search.noResults")
    }

    /// Where each shelf was left: each keeps its own front tape.
    private var shelfFrontID: Binding<String?> {
        switch shelf {
        case .albums:   return $rackFrontID
        case .mixtapes: return $mixtapeFrontID
        case .podcasts: return $podcastFrontID
        }
    }

    // MARK: - Now Playing

    /// The song on the door: a song from Up Next going in, or else what's playing.
    private var nowPlayingTitle: String? {
        pendingTrack?.title ?? musicService.currentTrack?.title ?? musicService.currentEpisode?.title
    }

    private var nowPlayingSubtitle: String? {
        if pendingTrack == nil, let episode = musicService.currentEpisode { return episode.showTitle }
        guard let track = pendingTrack ?? musicService.currentTrack else { return nil }
        return track.albumTitle.isEmpty ? track.artistName : "\(track.artistName) — \(track.albumTitle)"
    }

    // MARK: - Actions

    private func playPause() {
        if let load = deckLoad {
            deckLoad = nil
            startMotor(load.album, tracks: load.tracks, startingAt: load.index)
        } else if musicService.hasNowPlaying {
            Task { await musicService.togglePlayPause() }
        } else {
            chooseTape()
        }
    }

    /// The closed deck changes tapes through its door; the tent layout has no room for
    /// the carousel, so it keeps the shelf sheet.
    private func chooseTape() {
        if foldMonitor.posture == .closed {
            openDeck()
        } else {
            showShelf = true
        }
    }

    // MARK: - Tape Change

    private func openDeck() {
        guard !isDoorOpen, flight == nil else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        SpoolSound.cassetteEject.play()
        withAnimation(.spring(duration: 0.35, bounce: 0.3)) {
            isDoorOpen = true
        } completion: {
            withAnimation(.spring(duration: 0.5, bounce: 0.12)) { isBrowsing = true }
        }
    }

    /// Backs out without changing tapes.
    private func closeDeck() {
        guard isBrowsing, flight == nil else { return }
        withAnimation(.spring(duration: 0.45, bounce: 0.1)) {
            isBrowsing = false
        } completion: {
            shutDoor()
        }
    }

    private func shutDoor(then completion: @escaping () -> Void = {}) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        SpoolSound.doorClose.play()
        withAnimation(.spring(duration: 0.3, bounce: 0.25)) {
            isDoorOpen = false
        } completion: {
            completion()
        }
    }

    /// Lifts an album's case out of the rack and swings it open.
    private func openQueue() {
        guard !isBrowsing, flight == nil, openCase == nil else { return }
        if !isQueueShown {
            isQueueShown = true
        }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { queueProgress = 1 }
    }

    private func closeQueue() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) {
            queueProgress = 0
        } completion: {
            // Unless a finger has caught it on the way down.
            if queueProgress == 0 { isQueueShown = false }
        }
    }

    private func openCaseOf(_ album: AppAlbum, from frame: CGRect) {
        guard openCase == nil, flight == nil else { return }
        isShelfSearchFocused = false
        caseProgress = 0
        // Drawn closed in its slot first; the case's onReady then swings it open.
        openCase = CaseScene(album: album, closedFrame: frame)
    }

    /// Swings the lid shut and puts the case back in its slot.
    private func closeCase() {
        guard openCase != nil else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
            caseProgress = 0
        } completion: {
            var settle = Transaction()
            settle.disablesAnimations = true
            withTransaction(settle) { openCase = nil }
        }
    }

    /// Flies `album` from `frame` into the door and plays it from `index`. The cassette
    /// case passes the tracks it already loaded; a swiped tape loads its own.
    private func insertTape(_ album: AppAlbum, from frame: CGRect,
                            startingAt index: Int = 0, tracks preloaded: [AppTrack]? = nil) {
        guard flight == nil else { return }
        // A new tape replaces Up Next: ask first if it holds songs queued by hand, before
        // the old tape comes out.
        // Queued instead: the song picked from its case, or a tape swiped in whole.
        let addToQueue: (() -> Void)? = if let preloaded {
            queueSong(index, of: preloaded, on: album)
        } else if album.isPodcast {
            nil
        } else {
            { queue(album, placement: .last) }
        }
        musicService.play(asking: { pendingPlay = $0 }, addToQueue: addToQueue) {
            changeTape(album, from: frame, startingAt: index, tracks: preloaded)
        }
    }

    private func changeTape(_ album: AppAlbum, from frame: CGRect,
                            startingAt index: Int, tracks preloaded: [AppTrack]?) {
        guard flight == nil else { return }
        isShelfSearchFocused = false
        // Start loading now; the flight and the slide back cover most of the wait.
        let tracks = Task {
            if let preloaded { return preloaded }
            return await tapeTracks(for: album)
        }
        flight = TapeFlight(album: album, start: frame)
        pendingTape = album
        seatedTape = album
        // The old tape is out of the deck, so its song stops; the new one only starts
        // once it is in, the door is shut and its motor has run up.
        if musicService.isPlaying {
            Task { await musicService.togglePlayPause() }
        }

        // On an open Duo the door stays open: the tape goes in and waits there until the
        // phone is closed, which shuts the door and plays it.
        if foldMonitor.posture == .open {
            withAnimation(.easeIn(duration: 0.42)) {
                flight?.hasLanded = true
            } completion: {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                SpoolSound.cassetteInsert.play()
                var swap = Transaction()
                swap.disablesAnimations = true
                withTransaction(swap) {
                    deckLoad = DeckLoad(album: album, tracks: tracks, index: index)
                    flight = nil
                }
            }
            return
        }

        withAnimation(.easeIn(duration: 0.42)) {
            flight?.hasLanded = true
        } completion: {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            SpoolSound.cassetteInsert.play()
            // Swap the flying copy for the seated tape in the same frame.
            var swap = Transaction()
            swap.disablesAnimations = true
            withTransaction(swap) {
                isNewTapeSeated = true
                flight = nil
            }
            withAnimation(.spring(duration: 0.45, bounce: 0.1)) {
                isBrowsing = false
            } completion: {
                isNewTapeSeated = false
                shutDoor {
                    startMotor(album, tracks: tracks, startingAt: index)
                }
            }
        }
    }

    /// Loads a song picked from Up Next. Its label has been pulled out of the stack; now
    /// the cassette comes up out of it while the tray drops away, the door opens and the
    /// old tape slides out, the cassette goes in, the door shuts, and once the motor has
    /// run up the song plays. The rest of the queue stays as it was.
    private func loadFromQueue(_ track: AppTrack, from row: CGRect) {
        guard flight == nil, !isDoorOpen, !isMotorRunning, seatFrame.width > 0, row.width > 0 else {
            closeQueue()
            return
        }
        // The cassette fits inside its label to begin with, as if still in its sleeve.
        let aspect = CassetteView.aspectRatio
        let startHeight = row.height * 0.8
        let start = CGRect(x: row.midX - startHeight * aspect / 2, y: row.midY - startHeight / 2,
                           width: startHeight * aspect, height: startHeight)
        // Held up just below the door, clear of it, while the door opens.
        let liftWidth = min(containerHeight * 0.24, model.tapeAxis == .vertical ? seatFrame.height : seatFrame.width)
        let liftHeight = liftWidth / aspect
        let liftY = min(seatFrame.maxY + CassetteDoor<EmptyView>.inset + 16 + liftHeight / 2,
                        containerHeight - safeArea.bottom - liftHeight / 2 - 8)
        let lift = CGRect(x: seatFrame.midX - liftWidth / 2, y: liftY - liftWidth / aspect / 2,
                          width: liftWidth, height: liftWidth / aspect)

        flight = TapeFlight(track: track, start: start, lift: lift)
        if musicService.isPlaying {
            Task { await musicService.togglePlayPause() }
        }
        closeQueue()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            flight?.isLifted = true
        }
        // The door opens under it, and the old tape comes out of its seat.
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        SpoolSound.cassetteEject.play()
        withAnimation(.spring(duration: 0.35, bounce: 0.3)) {
            isDoorOpen = true
        } completion: {
            withAnimation(.easeOut(duration: 0.25)) {
                isOldTapeOut = true
            } completion: {
                withAnimation(.easeIn(duration: 0.4)) {
                    flight?.hasLanded = true
                } completion: {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    SpoolSound.cassetteInsert.play()
                    var swap = Transaction()
                    swap.disablesAnimations = true
                    withTransaction(swap) {
                        pendingTrack = track
                        isOldTapeOut = false
                        flight = nil
                    }
                    shutDoor { startMotor(for: track) }
                }
            }
        }
    }

    /// The motor run-up for a song from Up Next, which then jumps the queue to it.
    private func startMotor(for track: AppTrack) {
        SpoolSound.buttonPress.play()
        isMotorRunning = true
        Task {
            try? await Task.sleep(for: Self.motorRunUp)
            // Found again by identity: the queue may have moved on during the change.
            if let offset = musicService.upcoming.firstIndex(where: { $0.id == track.id }) {
                musicService.playUpcoming(at: offset)
            } else {
                showNotice(String(localized: "playback.nothingPlayable"))
            }
            isMotorRunning = false
            // If the song never comes in, the deck goes back to showing what is playing.
            try? await Task.sleep(for: .seconds(2))
            if pendingTrack?.id == track.id { pendingTrack = nil }
        }
    }

    /// With the door shut on a new tape: the play key goes down, the motor runs up and
    /// the reels turn, and only then does the song start. The music waits for the deck,
    /// however soon its tracks are ready; the reels keep turning if the tracks are slower.
    private func startMotor(_ album: AppAlbum, tracks: Task<[AppTrack], Never>, startingAt index: Int) {
        SpoolSound.buttonPress.play()
        isMotorRunning = true
        Task {
            async let loaded = tracks.value
            try? await Task.sleep(for: Self.motorRunUp)
            let songs = await loaded
            guard !songs.isEmpty else {
                isMotorRunning = false
                pendingTape = nil
                showNotice(String(localized: "playback.nothingPlayable"))
                return
            }
            let outcome = await startPlaying(LoadedTape(album: album, tracks: songs),
                                     startingAt: min(index, songs.count - 1))
            isMotorRunning = false
            if outcome != .started { pendingTape = nil }
        }
    }

    /// How long the motor runs before the song comes in: the time a real deck takes to
    /// bring the tape up to speed.
    private static let motorRunUp: Duration = .milliseconds(650)

    // MARK: - Winding

    /// Winds through the song while a wind key is held: slowly at first, then faster the
    /// longer it's held, as a deck's motor gets going. The reels and the time follow the
    /// wind frame by frame; the player is moved along a few times a second, so a playing
    /// song is heard in snatches, the way a cueing deck sounds.
    private func startWinding(forward: Bool) {
        guard musicService.hasNowPlaying, musicService.duration > 0, deckLoad == nil else { return }
        windTask?.cancel()
        musicService.startScrubbing()
        windTask = Task {
            let direction: Double = forward ? 1 : -1
            let start = ContinuousClock.now
            var previous = start
            var lastSeek = start
            var lastGrain = start - .seconds(1)
            var grains = 0
            var time = musicService.clock.time
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                let now = ContinuousClock.now
                let dt = Self.seconds(now - previous)
                previous = now
                let held = Self.seconds(now - start)
                let speed: Double = held < 1.5 ? 8 : held < 4 ? 16 : 32
                let end = max(0, musicService.duration - 1)
                time = min(max(time + direction * speed * dt, 0), end)
                musicService.clock.time = time
                if Self.seconds(now - lastSeek) >= 0.25 {
                    lastSeek = now
                    await musicService.seek(to: time)
                }
                // The rewind whir, faint under the music: pieces of it in turn, each
                // starting under the end of the last so they run together. The wind
                // stops at either end of the tape, and so does the whir.
                let isWinding = forward ? time < end : time > 0
                if isWinding, now - lastGrain >= SpoolSound.rewindInterval {
                    lastGrain = now
                    SpoolSound.nextRewind(after: grains).play()
                    grains += 1
                }
            }
        }
    }

    private func stopWinding() {
        guard let task = windTask else { return }
        task.cancel()
        windTask = nil
        let time = musicService.clock.time
        Task {
            await musicService.seek(to: time)
            musicService.stopScrubbing()
        }
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    /// Loads an album's tracks as a tape, then plays it or leaves it waiting for the fold.
    private func insert(_ album: AppAlbum, thenPlay: Bool) {
        Task {
            let tracks = await tapeTracks(for: album)
            await MainActor.run {
                guard !tracks.isEmpty else {
                    showNotice(String(localized: "playback.nothingPlayable"))
                    return
                }
                let tape = LoadedTape(album: album, tracks: tracks)
                if thenPlay {
                    musicService.play(asking: { pendingPlay = $0 },
                                      addToQueue: album.isPodcast ? nil : { queue(tracks, placement: .last, name: album.tapeTitle) }) {
                        play(tape)
                    }
                } else {
                    deckLoad = DeckLoad(album: album, tracks: Task { tracks }, index: 0)
                }
            }
        }
    }

    private func play(_ tape: LoadedTape, startingAt index: Int = 0) {
        Task { await startPlaying(tape, startingAt: index) }
    }

    @discardableResult
    private func startPlaying(_ tape: LoadedTape, startingAt index: Int) async -> PlaybackStartOutcome {
        logger.info("Spool playing tape: \(tape.album.title, privacy: .private)")
        seatedTape = tape.album
        let outcome = await library.play(tape.album, tracks: tape.tracks, startingAt: index)
        if outcome != .started {
            showNotice(String(localized: "playback.nothingPlayable"))
        }
        return outcome
    }

    /// A tape's songs as they go on it: an album's each once (see `withoutDuplicates`),
    /// a mixtape's as the playlist has them.
    private func tapeTracks(for album: AppAlbum) async -> [AppTrack] {
        await library.tracks(for: album)
    }

    /// Queues a whole album from the rack, leaving what's playing alone.
    private func queue(_ album: AppAlbum, placement: QueuePlacement) {
        guard !album.isPodcast else { return }
        Task {
            let tracks = await tapeTracks(for: album)
            queue(tracks, placement: placement, name: album.tapeTitle)
        }
    }

    /// Queues songs and says what happened, in the words the other players use.
    private func queue(_ tracks: [AppTrack], placement: QueuePlacement, name: String) {
        Task {
            let outcome = await musicService.addToQueue(tracks: tracks, placement: placement)
            await MainActor.run {
                if !outcome.succeeded {
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.4)
                }
                showNotice(outcome.message(name: name, requested: tracks.count, placement: placement,
                                           isCollection: tracks.count > 1))
            }
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

private struct TapeFlight {
    /// The rack card left empty while its tape is in the air.
    let hiddenID: String?
    let title: String?
    let labelArt: TapeLabelArt
    let format: TapeFormat
    let trackCount: Int?
    let blank: String?
    /// The tape's frame where it set off, in SpoolPlayerView.coordinateSpace.
    let start: CGRect
    /// Where a song's cassette is held up, out of its label, before it goes in the door.
    var lift: CGRect?
    var isLifted = false
    var hasLanded = false

    init(album: AppAlbum, start: CGRect) {
        hiddenID = album.id
        title = album.tapeTitle
        labelArt = .album(album)
        format = album.tapeFormat
        trackCount = album.tapeTrackCount
        blank = album.tapeBlank
        self.start = start
    }

    init(track: AppTrack, start: CGRect, lift: CGRect) {
        hiddenID = nil
        title = track.title
        labelArt = .track(track)
        format = .album
        trackCount = nil
        blank = nil
        self.start = start
        self.lift = lift
    }
}

private struct CaseScene {
    let album: AppAlbum
    /// Where the closed case sits — its slot in the rack, or over the door — in
    /// `coordinateSpace`.
    let closedFrame: CGRect
    /// Brought up from the deck, holding the tape already playing, rather than taken
    /// from the rack.
    var isFromDeck = false
}

private struct LoadedTape: Equatable {
    let album: AppAlbum
    let tracks: [AppTrack]
}

/// A tape put in the open deck on an unfolded Duo, and the song to start it from. Its
/// songs load while it waits; closing the phone plays it.
private struct DeckLoad {
    let album: AppAlbum
    let tracks: Task<[AppTrack], Never>
    let index: Int
}

// MARK: - Elapsed Time

/// Observes the clock on its own, so the twice-a-second ticks redraw only this label.
private struct ElapsedTimeLabel: View {
    @ObservedObject var clock: PlaybackClock
    /// Counts down what's left of this length instead of up, when set.
    var remainingOf: TimeInterval?
    @Environment(\.spoolTheme) private var theme

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(theme.keySymbol.opacity(0.8))
            .accessibilityHidden(true)
    }

    /// "3:07", or for a countdown "-42:10", with hours when there are any: "-1:05:00".
    private var text: String {
        guard let length = remainingOf, length > 0 else { return AppHelpers.formatTime(clock.time) }
        let left = Int(max(0, length - clock.time))
        let clock = left >= 3600
            ? String(format: "%d:%02d:%02d", left / 3600, left / 60 % 60, left % 60)
            : String(format: "%d:%02d", left / 60, left % 60)
        return "-" + clock
    }
}

// MARK: - Keys

/// A mechanical transport key: a block that stands proud of the casing and pushes in
/// when pressed, like the piano keys on a cassette player.
/// A transport key. It clunks going down and clicks coming back up. A key given
/// `onHoldStart` also does something for as long as it is held: past `holdDelay` the
/// hold begins, and letting go (or sliding off the key) ends it without the tap's action.
private struct SpoolKey: View {
    let symbol: String
    let label: String
    var isAccent = false
    /// Held down, as a play key locks while the tape runs.
    var isLatched = false
    /// The slim's smaller keys, which sit in a row along its top edge.
    var compact = false
    /// The edge the key stands out from; pressing pushes it the opposite way.
    var proudEdge: Edge = .leading
    var onHoldStart: (() -> Void)?
    var onHoldEnd: (() -> Void)?
    let action: () -> Void

    static let holdDelay: Duration = .milliseconds(400)

    @State private var holdTask: Task<Void, Never>?
    @State private var isHolding = false
    /// Set once this press has turned into a hold, so letting go doesn't also tap.
    @State private var pressWasHeld = false

    var body: some View {
        Button {
            guard !pressWasHeld else { return }
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.9)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: compact ? 16 : 18, weight: .heavy))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(SpoolKeyStyle(isAccent: isAccent, isLatched: isLatched,
                                   compact: compact, proudEdge: proudEdge,
                                   onPressChange: pressChanged))
        .accessibilityLabel(label)
        .accessibilityAddTraits(isLatched ? .isSelected : [])
        .onDisappear { endHold() }
    }

    private func pressChanged(_ isDown: Bool) {
        // Down, the key clicks; let go after a hold, it clicks back up. A tap's release
        // is part of its press sound.
        if isDown {
            SpoolSound.buttonPress.play()
        } else if isHolding {
            SpoolSound.buttonRelease.play()
        }
        guard onHoldStart != nil else { return }
        if isDown {
            pressWasHeld = false
            holdTask?.cancel()
            holdTask = Task {
                try? await Task.sleep(for: Self.holdDelay)
                guard !Task.isCancelled else { return }
                pressWasHeld = true
                isHolding = true
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                onHoldStart?()
            }
        } else {
            endHold()
        }
    }

    private func endHold() {
        holdTask?.cancel()
        holdTask = nil
        guard isHolding else { return }
        isHolding = false
        onHoldEnd?()
    }
}

private struct SpoolKeyStyle: ButtonStyle {
    let isAccent: Bool
    var isLatched = false
    var compact = false
    var proudEdge: Edge = .leading
    var onPressChange: (Bool) -> Void = { _ in }
    @Environment(\.spoolTheme) private var theme

    /// How much of the key's side shows at rest, and how far a press pushes it in.
    private static let wall: CGFloat = 9
    private static let travel: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        let isDown = configuration.isPressed || isLatched
        let size = compact ? CGSize(width: 58, height: 48) : CGSize(width: 82, height: 62)
        let isSideways = proudEdge == .leading || proudEdge == .trailing
        // The key's footprint shrinks from its proud edge as it goes in; the face keeps
        // its size and the visible side wall gets shorter.
        let pushed = isDown ? Self.travel : 0
        let radius: CGFloat = compact ? 3 : 4
        let faceColors = isAccent ? [theme.accentLight, theme.accent] : [theme.keyLight, theme.key]

        return ZStack(alignment: innerAlignment) {
            // The key's side, seen past the casing: the face colour in shade.
            RoundedRectangle(cornerRadius: radius)
                .fill(LinearGradient(colors: faceColors.reversed(),
                                     startPoint: isSideways ? .leading : .top,
                                     endPoint: isSideways ? .trailing : .bottom))
                .overlay(RoundedRectangle(cornerRadius: radius).fill(.black.opacity(0.38)))

            // The face, with a catch of light on its leading edge and the symbol
            // engraved into it.
            RoundedRectangle(cornerRadius: radius)
                .fill(LinearGradient(colors: faceColors, startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.05)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing),
                                      lineWidth: 1)
                )
                .overlay(RoundedRectangle(cornerRadius: radius).fill(.black.opacity(isDown ? 0.1 : 0)))
                .overlay {
                    configuration.label
                        .foregroundStyle(isAccent ? Color.white.opacity(0.95) : theme.keySymbol.opacity(0.85))
                        // Engraved: a light lip under the cut.
                        .shadow(color: .white.opacity(isAccent || !theme.isLight ? 0.15 : 0.5), radius: 0, x: 0, y: 1)
                }
                .frame(width: isSideways ? size.width - Self.wall : size.width,
                       height: isSideways ? size.height : size.height - Self.wall)
        }
        .frame(width: isSideways ? size.width - pushed : size.width,
               height: isSideways ? size.height : size.height - pushed)
        .frame(width: size.width, height: size.height, alignment: innerAlignment)
        .shadow(color: .black.opacity(isDown ? 0.12 : 0.3), radius: isDown ? 1 : 2,
                x: proudEdge == .leading ? -1 : 0, y: 1)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.07), value: isDown)
        .onChange(of: configuration.isPressed) { _, pressed in onPressChange(pressed) }
    }

    /// The side the key is anchored to: away from its proud edge.
    private var innerAlignment: Alignment {
        switch proudEdge {
        case .leading:  return .trailing
        case .trailing: return .leading
        case .top:      return .bottom
        case .bottom:   return .top
        }
    }
}

// MARK: - Tape Shelf

/// The albums in the library as a grid of tapes to pick from, with a search field over
/// them that narrows the grid as it's typed in (see LibrarySearch).
struct TapeShelfView: View {
    let albums: [AppAlbum]
    let hint: String
    var selectedID: String?
    /// Every song, so a song's name finds the album it's on.
    var songs: [AppTrack] = []
    let onSelect: (AppAlbum) -> Void

    @State private var query = ""
    /// The albums the search leaves, worked out once per pause in the typing.
    @State private var shown: [AppAlbum]?
    @FocusState private var isSearchFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 14)]

    private var visibleAlbums: [AppAlbum] { shown ?? albums }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "spool.shelf.title"))
                .font(.system(size: 28, weight: .bold))
            Text(hint)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            if !albums.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField(String(localized: "spool.search.prompt"), text: $query)
                        .focused($isSearchFocused)
                        .submitLabel(.search)
                        .onSubmit { isSearchFocused = false }
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("spool.shelf.search")
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "search.clear"))
                    }
                }
                .font(.system(size: 15))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                .padding(.top, 10)
            }

            if albums.isEmpty || visibleAlbums.isEmpty {
                Text(albums.isEmpty ? String(localized: "spool.shelf.empty") : String(localized: "search.noResults"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(visibleAlbums) { album in
                            Button { onSelect(album) } label: {
                                tape(for: album)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .scrollDismissesKeyboard(.immediately)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .task(id: query) {
            if shown != nil || !query.isEmpty {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
            }
            let terms = LibrarySearch.terms(query)
            shown = terms.isEmpty ? nil : LibrarySearch.filter(albums, matching: query, songs: songs)
        }
    }

    private func tape(for album: AppAlbum) -> some View {
        let isSelected = album.id == selectedID
        return VStack(alignment: .leading, spacing: 4) {
            TapeArtwork(album: album, size: 104)
                .frame(width: 104, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(SpoolPalette.accent, lineWidth: isSelected ? 3 : 0)
                )
            Text(album.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Text(album.artistName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 104)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

struct TapeArtwork: View {
    let album: AppAlbum
    let size: CGFloat

    var body: some View {
        if let show = album.podcast {
            LocalArtworkImage(cacheKey: show.artworkCacheKey, size: size, artwork: show.artwork,
                              remoteURL: show.artworkURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                KraftSleeve(title: album.title, size: size)
            }
        } else if let artwork = album.musicKitAlbum?.artwork ?? album.mixtape?.musicKitPlaylist?.artwork {
            ArtworkImage(artwork, width: size)
        } else if album.mpArtwork != nil {
            LocalArtworkImage(cacheKey: album.id, size: size, artwork: album.mpArtwork) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                KraftSleeve(title: album.title, size: size)
            }
        } else {
            KraftSleeve(title: album.title, size: size)
        }
    }
}

/// What's stuck on a mixtape's J-card: the covers of its first four different albums,
/// cut out and laid together, or the playlist's own art when it has fewer.
struct MixtapeArtwork: View {
    let album: AppAlbum
    let size: CGFloat

    var body: some View {
        let covers = Self.covers(album.preloadedTracks)
        if covers.count == 4 {
            let half = (size / 2).rounded()
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    TrackArtwork(track: covers[0], size: half).frame(width: half, height: half).clipped()
                    TrackArtwork(track: covers[1], size: half).frame(width: half, height: half).clipped()
                }
                GridRow {
                    TrackArtwork(track: covers[2], size: half).frame(width: half, height: half).clipped()
                    TrackArtwork(track: covers[3], size: half).frame(width: half, height: half).clipped()
                }
            }
            .frame(width: size, height: size)
        } else {
            TapeArtwork(album: album, size: size)
        }
    }

    /// One song from each of the first four albums on the tape.
    static func covers(_ tracks: [AppTrack]) -> [AppTrack] {
        var seen = Set<String>()
        var covers: [AppTrack] = []
        for track in tracks where covers.count < 4 {
            let key = track.albumTitle.lowercased()
            if !key.isEmpty, seen.insert(key).inserted { covers.append(track) }
        }
        return covers
    }
}

/// The cover of whatever is playing, for a tape that was started outside Spool.
struct TrackArtwork: View {
    let track: AppTrack
    let size: CGFloat

    var body: some View {
        if let artwork = track.musicKitSong?.artwork ?? track.musicKitTrack?.artwork {
            ArtworkImage(artwork, width: size)
        } else if let item = track.mpItem {
            LocalArtworkImage(cacheKey: track.id, size: size, artwork: item.artwork) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                KraftSleeve(title: track.albumTitle, size: size)
            }
        } else {
            KraftSleeve(title: track.albumTitle, size: size)
        }
    }
}

// MARK: - Palette

enum SpoolPalette {
    static let body        = Color(red: 0.102, green: 0.369, blue: 0.588) // #1A5E96
    static let bodyLight   = Color(red: 0.149, green: 0.463, blue: 0.698) // #2676B2
    static let strip       = Color(red: 0.690, green: 0.792, blue: 0.835) // #B0CAD5
    static let stripLight  = Color(red: 0.824, green: 0.890, blue: 0.914) // #D2E3E9
    static let key         = Color(red: 0.706, green: 0.733, blue: 0.753) // #B4BBC0
    static let keyLight    = Color(red: 0.898, green: 0.914, blue: 0.925) // #E5E9EC
    static let keySymbol   = Color(red: 0.149, green: 0.180, blue: 0.212) // #262E36
    static let accent      = Color(red: 0.937, green: 0.525, blue: 0.098) // #EF8619
    static let accentLight = Color(red: 0.984, green: 0.659, blue: 0.259) // #FBA842
    static let shellTop    = Color(red: 0.165, green: 0.161, blue: 0.180) // #2A292E
    static let shellBottom = Color(red: 0.098, green: 0.094, blue: 0.110) // #19181C
    static let window      = Color(red: 0.055, green: 0.051, blue: 0.063) // #0E0D10
    static let label       = Color(red: 0.925, green: 0.894, blue: 0.835) // #ECE4D5
    static let labelInk    = Color(red: 0.180, green: 0.141, blue: 0.110) // #2E241C
    static let tapeInner   = Color(red: 0.239, green: 0.086, blue: 0.063) // #3D1610
    static let tapeOuter   = Color(red: 0.420, green: 0.149, blue: 0.106) // #6B261B
    static let hub         = Color(red: 0.925, green: 0.925, blue: 0.918) // #ECECEA
    static let screw       = Color(red: 0.400, green: 0.400, blue: 0.420) // #66666B
    static let bay         = Color(red: 0.055, green: 0.180, blue: 0.290) // #0E2E4A
    static let doorRim     = Color(red: 0.780, green: 0.851, blue: 0.886) // #C7D9E2
    static let singleShellTop    = Color(red: 0.788, green: 0.231, blue: 0.188) // #C93B30
    static let singleShellBottom = Color(red: 0.537, green: 0.125, blue: 0.110) // #89201C
    static let mixtapeShellTop    = Color(red: 0.918, green: 0.906, blue: 0.878) // #EAE7E0
    static let mixtapeShellBottom = Color(red: 0.776, green: 0.761, blue: 0.729) // #C6C2BA
    /// Ballpoint blue, for what's written on a mixtape.
    static let pen         = Color(red: 0.137, green: 0.235, blue: 0.537) // #233C89
    static let mixtapeRule = Color(red: 0.420, green: 0.553, blue: 0.741).opacity(0.45)
    static let spokenWordShellTop    = Color(red: 0.165, green: 0.231, blue: 0.341) // #2A3B57
    static let spokenWordShellBottom = Color(red: 0.090, green: 0.133, blue: 0.208) // #172235
    /// The band on a spoken-word label.
    static let spokenWordBand = Color(red: 0.122, green: 0.494, blue: 0.494) // #1F7E7E
    /// The hand a mixtape is written in.
    static let handwriting = "Noteworthy-Bold"
}

#Preview {
    @Previewable @State var musicService = MusicService()
    SpoolPlayerView(musicService: musicService, themeSettings: ThemeSettings(),
                    foldMonitor: FoldPostureMonitor())
}
