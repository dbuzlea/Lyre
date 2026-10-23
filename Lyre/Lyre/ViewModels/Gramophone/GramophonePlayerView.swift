//
//  GramophonePlayerView.swift
//  Lyre
//

import MediaPlayer
import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.pinkhatcreations.lyreapp", category: "GramophonePlayerView")

// MARK: - Gramophone Player
//
// The gramophone, shown in place of the click-wheel player when the player style is
// Gramophone. Like the Spool it drives the same MusicService, so switching styles
// mid-song keeps playing, and its queue follows the same rules.
//
// The machine is 3D (GramophoneStage), standing on a table, and seen three ways:
//
//   in front    the front panel: the play switch, the plate with the song playing and
//               the speed knob; the drawer the records are kept in; the crank on the
//               right-hand side; and, to the left, a rack of Up Next's records. SwiftUI
//               controls lie over each part, where the stage says it is on screen.
//   turntable   flipping the switch on (or looking in) moves the camera up over the
//               front edge and down onto the record; there the 2D turntable
//               (TurntableView) fades in exactly over the 3D one, with the brake, the
//               plate and the speed under it. Stopping, or stepping back, returns to
//               the front.
//   drawer      tapping the drawer pulls it out and looks down into it, where the crate
//               (the records, playlists and podcasts) is shown over the records lying
//               in it.
//   rack        tapping the bin of Up Next's records goes round to its front. Swiping
//               down flips the front record forward to the next one, as in a record
//               shop, and up flips it back; tapping plays it, holding opens Up Next to
//               reorder it, and swiping it left offers to take it out.
//
// Choosing a record carries the camera to the turntable, where the record comes out of
// its sleeve onto the platter and the arm swings over and lowers the needle onto it.
//
// Records
//   Each song is a band of grooves on the record (see GrooveMap), and the tonearm
//   rides the groove as the music plays. Lifting it pauses; carrying it and putting it
//   down on another band plays that song from where the needle lands; putting it back
//   on its rest stops. The brake starts and stops without lifting it.
//
//   The drawer holds a stack of records (RecordStackView) in their sleeves, behind
//   three dividers: albums, playlists as home recordings, and podcasts as broadcast
//   transcriptions. Swiping the top record right goes up the stack, left goes back
//   down it; holding it offers Play Next or Add to Queue; tapping it, or holding the one on the
//   turntable, opens its sleeve (RecordSleeveView) to choose a song. Along the drawer's
//   front, under the stack, an A–Z index (RecordIndexStrip) jumps to a letter.
//
//   The search field over the dividers narrows the stack to the records that match
//   what's typed, a song bringing up the album it's on (see ShelfSearchField). The
//   drawer's records lie under the keyboard while it's up, so the header names the top
//   match as it changes. Pressing Search, or handling the stack, puts the keyboard
//   away; closing the drawer clears the search.
//
// iPhone Duo, opened and turned so the fold runs across the middle (the inner screen
// taller than wide): the machine, with Up Next's rack beside it, takes the top half, and
// the bottom half is the covers in a row to swipe through (GramophoneCoverCarousel). Only
// the Duo reports a hinge, so no other iPhone ever shows it. Open on its side, the machine
// simply has the whole wider screen.
//
// Otherwise everything is laid out for a phone held upright, in every fold posture. With Reduce
// Motion on, the camera cuts between the two rather than moving.

struct GramophonePlayerView: View {
    @ObservedObject var musicService: MusicService
    let themeSettings: ThemeSettings
    let foldMonitor: FoldPostureMonitor

    /// The record on the turntable, as put there: its album (none for a shuffle) and
    /// its songs in band order.
    @State private var seated: SeatedRecord?
    /// The tonearm on its rest, off the record.
    @State private var isArmParked = true
    /// A record just put on, shown while its first song starts.
    @State private var isLoadingRecord = false
    @State private var isBrowsing = false
    @State private var openSleeve: AppAlbum?
    @State private var showSettings = false
    @State private var showPodcastSearch = false
    @State private var isQueueShown = false
    @State private var queueProgress: CGFloat = 0
    @State private var containerHeight: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var notice: String?
    @State private var noticeTask: Task<Void, Never>?
    /// The machine in 3D, and where the camera is: in front, on its way, looking down
    /// on the turntable (where the 2D turntable is shown over the record), or into the
    /// drawer (where the crate is).
    @State private var stage = GramophoneStage()
    @State private var vantage: Vantage = .front
    @State private var isOverheadShown = false
    /// Where closing the crate goes back to.
    @State private var crateReturn: GramophoneShot = .front
    /// A record on its way onto the turntable: the 3D arm is left to the animation.
    @State private var isPutting = false
    /// Where the machine's parts are on screen, for the controls laid over them.
    @State private var hotspots: [GramophoneHotspot: CGRect] = [:]
    @State private var crankAngle: Double = 0
    /// The play switch thrown, while the camera goes in and the record starts.
    @State private var isStarting = false
    /// The record at the front of the Up Next bin, by its place in Up Next.
    @State private var rackIndex = 0
    /// Which way a finger on the bin's front record is going.
    @State private var rackAxis: Axis?
    /// The front record pushed aside, with the button to take it out showing.
    @State private var isRemoveShown = false

    /// A record waiting to go on, as it would clear songs queued by hand.
    @State private var pendingPlay: PendingPlay?

    @AppStorage("GramophoneShelf") private var shelf: SpoolShelf = .albums
    /// What's typed over the crate, and the records it leaves on each shelf; nil when
    /// nothing is being searched for.
    @State private var crateQuery = ""
    @State private var crateMatches: ShelfSearchMatches?
    @FocusState private var isCrateSearchFocused: Bool
    @AppStorage("GramophoneAlbumFrontID") private var albumFrontID: String?
    @AppStorage("GramophoneRecordingFrontID") private var recordingFrontID: String?
    @AppStorage("GramophoneBroadcastFrontID") private var broadcastFrontID: String?

    @Environment(\.windowSafeArea) private var safeArea
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Vantage {
        case front, moving, turntable, drawer, rack

        init(_ shot: GramophoneShot) {
            switch shot {
            case .front: self = .front
            case .turntable: self = .turntable
            case .drawer: self = .drawer
            case .rack: self = .rack
            }
        }
    }

    private var theme: GramophoneTheme { themeSettings.gramophoneFinish.theme }
    private var model: GramophoneModel { themeSettings.gramophoneModel }
    private var library: ShelfLibrary { ShelfLibrary(musicService: musicService) }

    /// iPhone Duo open with its fold across the middle: the machine above, the covers below.
    private var isDuoSplit: Bool {
        foldMonitor.posture == .open && containerWidth > 0 && containerHeight > containerWidth
    }

    /// The covers' share of the screen, under the fold (its safe area besides).
    private var binHeight: CGFloat { isDuoSplit ? (containerHeight / 2).rounded() : 0 }

    var body: some View {
        ZStack {
            // The room: a dark wall behind the table.
            LinearGradient(colors: [Color(red: 0.17, green: 0.11, blue: 0.08), Color(red: 0.06, green: 0.04, blue: 0.03)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            GramophoneStageView(stage: stage, topInset: safeArea.top + Self.topBarHeight,
                                bottomInset: safeArea.bottom + (isDuoSplit ? binHeight + 12 : 8))
                .ignoresSafeArea()

            if vantage == .front {
                frontControls
                    .transition(.opacity)
            }

            overhead
                .padding(safeArea)
                // Above the fold, on a Duo with the covers below.
                .padding(.bottom, binHeight)
                .frame(maxWidth: 560)
                // Laid out all along, so the camera knows where to come down to, but
                // only there while the camera's away from the front.
                .modifier(PresentIf(isPresent: isOverheadShown || vantage == .turntable))
                .opacity(isOverheadShown ? 1 : 0)
                .allowsHitTesting(isOverheadShown)
                .accessibilityHidden(!isOverheadShown)

            topBar
                .padding(.top, safeArea.top)
                .padding(.horizontal, max(safeArea.leading, safeArea.trailing))
                .frame(maxWidth: 560, maxHeight: .infinity, alignment: .top)
                .opacity(vantage == .rack ? 0 : 1)
                .allowsHitTesting(vantage != .rack)

            if isDuoSplit {
                GramophoneCoverCarousel(
                    library: library,
                    musicService: musicService,
                    onOpen: openRecord,
                    onPlaySong: putSong,
                    onQueueAlbum: { album, placement in queue(album, placement: placement) },
                    onQueueSong: { track, placement in queue([track], placement: placement, name: track.title) }
                )
                .frame(height: binHeight)
                .padding(.bottom, safeArea.bottom)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1.5)
            }

            if isBrowsing {
                crate
                    .transition(.opacity)
                    .zIndex(2)
            }

            if vantage == .rack {
                rackControls
                    .transition(.opacity)
                    .zIndex(2)
            }

            if let album = openSleeve {
                RecordSleeveView(
                    album: album,
                    loadTracks: { await library.tracks(for: album) },
                    onPick: { tracks, index, whole in
                        // Queued instead: the whole record for Play or Shuffle, else the song.
                        let queued = whole ? tracks : [tracks[index]]
                        put(album, tracks: tracks, startingAt: index,
                            addToQueue: album.isPodcast ? nil : {
                                queue(queued, placement: .last, name: whole ? album.tapeTitle : tracks[index].title)
                            })
                    },
                    onQueue: { tracks, placement in
                        queue(tracks, placement: placement, name: tracks.count == 1 ? tracks[0].title : album.tapeTitle)
                    },
                    onClose: { openSleeve = nil },
                    playingID: musicService.currentEpisode?.id ?? musicService.currentTrack?.id
                )
                .zIndex(3)
            }

            if isQueueShown {
                SpoolQueueTray(
                    musicService: musicService,
                    progress: queueProgress,
                    height: max(320, (containerHeight - safeArea.top - safeArea.bottom) * 0.72),
                    bottomInset: safeArea.bottom,
                    onScrub: { progress in
                        withTransaction(Transaction(animation: nil)) { queueProgress = progress }
                    },
                    onScrubEnd: { closes in closes ? closeQueue() : openQueue() },
                    onClose: closeQueue,
                    onNotice: showNotice,
                    onPick: { offset, _, _ in playFromQueue(at: offset) }
                )
                .environment(\.spoolTheme, theme.spoolTheme)
                .ignoresSafeArea(edges: .bottom)
                .zIndex(3.5)
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
                    .accessibilityIdentifier("gramophone.notice")
                    .zIndex(5)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: notice)
        .animation(.easeInOut(duration: 0.25), value: vantage)
        .environment(\.gramophoneTheme, theme)
        .environment(\.spoolTheme, theme.spoolTheme)
        // The crate is the Spool's rack, which reports frames in this space.
        .coordinateSpace(name: SpoolPlayerView.coordinateSpace)
        .onGeometryChange(for: CGSize.self) { $0.size } action: {
            containerHeight = $0.height
            containerWidth = $0.width
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: isDuoSplit)
        .sheet(isPresented: $showSettings) {
            GramophoneSettingsView(musicService: musicService, themeSettings: themeSettings,
                                   foldMonitor: foldMonitor) { showSettings = false }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPodcastSearch) {
            PodcastSearchView(musicService: musicService)
        }
        .replaceQueuePrompt($pendingPlay, count: musicService.listenerQueuedCount)
        .task(id: crackleIsOn) { await playSurfaceNoise() }
        // The 3D machine follows what's playing.
        .onChange(of: [model.rawValue, themeSettings.gramophoneFinish.rawValue], initial: true) {
            stage.configure(model: model, finish: themeSettings.gramophoneFinish)
        }
        .onChange(of: recordOnPlatter, initial: true) { _, record in
            stage.setRecord(record)
            syncArm(animated: false)
            Task { await showNowPlayingLabel() }
        }
        .task(id: musicService.currentMediaItem?.persistentID) { await showNowPlayingLabel() }
        .onChange(of: isArmParked) { syncArm(animated: true) }
        .onReceive(musicService.clock.$time) { _ in syncArm(animated: true) }
        .onChange(of: musicService.isPlaying && !reduceMotion, initial: true) { _, spinning in
            stage.setSpinning(spinning)
        }
        .onChange(of: isSwitchOn, initial: true) { _, on in stage.setSwitch(on: on) }
        .onChange(of: crankAngle) { _, angle in stage.setCrank(degrees: angle) }
        .task(id: RackWindow(ids: musicService.upcoming.map(\.id), index: rackIndex)) { await fillRack() }
        .task(id: "\(shelf.rawValue):\(frontID.wrappedValue ?? ""):\(crateMatches?.query ?? ""):\(crateItems.count)") { await fillDrawer() }
        .modifier(ShelfSearching(query: crateQuery, library: library, shelf: $shelf, matches: $crateMatches))
        .onChange(of: isBrowsing) { _, browsing in
            // The drawer opens on the whole shelf each time.
            guard !browsing else { return }
            isCrateSearchFocused = false
            crateQuery = ""
        }
        .onChange(of: [nowPlayingTitle, nowPlayingSubtitle], initial: true) {
            stage.setPlate(title: nowPlayingTitle, subtitle: nowPlayingSubtitle)
        }
        .onChange(of: [musicService.podcastRate, musicService.isPlayingPodcast ? 1 : 0], initial: true) {
            stage.setSpeed(rate: musicService.podcastRate, isEnabled: musicService.isPlayingPodcast)
        }
        .onAppear {
            _ = Self.resetCrateForUITests
            stage.onHotspots = { if hotspots != $0 { hotspots = $0 } }
            #if DEBUG
            // `-GramophoneShot turntable|drawer|rack` starts there, and `put` puts a shuffle on, for
            // screenshots.
            switch UserDefaults.standard.string(forKey: "GramophoneShot") {
            case "turntable": Task { await go(to: .turntable) }
            case "drawer": openCrate()
            case "rack":
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    openRack()
                }
            case "put":
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    shuffleAll()
                }
            default: break
            }
            // `--spool-sample-queue` fills Up Next with the first sample record's songs, so
            // the bin has records on a simulator with no music.
            if ProcessInfo.processInfo.arguments.contains("--spool-sample-queue"), musicService.upNext.isEmpty,
               let album = library.items(on: .albums).first {
                musicService.seedQueueForUITests(album.preloadedTracks)
            }
            #endif
            // Something already playing (started in another player) is on the
            // turntable with the needle down.
            if musicService.hasNowPlaying { isArmParked = false }
        }
        .onDisappear { noticeTask?.cancel() }
    }

    /// `--gramophone-reset-crate` at launch forgets where the crate was left, once, so
    /// each UI test starts on the first album. Debug builds only.
    private static let resetCrateForUITests: Void = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--gramophone-reset-crate") {
            for key in ["GramophoneShelf", "GramophoneAlbumFrontID", "GramophoneRecordingFrontID",
                        "GramophoneBroadcastFrontID", "GramophoneBinDivider"]
                + GramophoneCoverCarousel.Divider.allCases.map({ "GramophoneBinPlace." + $0.rawValue }) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        #endif
    }()

    private static let topBarHeight: CGFloat = 52

    private var topBar: some View {
        HStack {
            if vantage == .turntable {
                Button {
                    Task { await go(to: .front) }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(theme.plateInk)
                        .frame(width: 36, height: 36)
                        .background(theme.metalGradient, in: Circle())
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(String(localized: "gramophone.stepBack"))
                .accessibilityIdentifier("gramophone.stepBack")
                .transition(.opacity)
            } else {
                Text(String(localized: "gramophone.brand").uppercased())
                    .font(.system(size: 13, weight: .heavy, design: .serif))
                    .tracking(5)
                    .foregroundStyle(theme.metalLight.opacity(0.85))
                    .accessibilityHidden(true)
            }
            Spacer()
            // Where it plays: the phone, or an AirPlay speaker. The glyph turns the
            // felt's colour while it's on one.
            AirPlayRouteButton(identifier: "gramophone.airplay") { isActive in
                Image(systemName: "airplayaudio")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isActive ? theme.felt : theme.plateInk)
                    .frame(width: 36, height: 36)
                    .background(theme.metalGradient, in: Circle())
                    .frame(width: 44, height: 44)
            }
            PlayerSwitchMenu(themeSettings: themeSettings, identifier: "gramophone.playerSwitch") { symbol in
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.plateInk)
                    .frame(width: 36, height: 36)
                    .background(theme.metalGradient, in: Circle())
                    .frame(width: 44, height: 44)
            }
            Button { showSettings = true } label: {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.plateInk)
                    .frame(width: 36, height: 36)
                    .background(theme.metalGradient, in: Circle())
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(String(localized: "gramophone.booklet"))
            .accessibilityIdentifier("gramophone.settings")
        }
        .frame(height: Self.topBarHeight)
        .padding(.horizontal, 18)
    }

    // MARK: - In Front
    //
    // The machine's parts are drawn in 3D; these are the controls laid over them, where
    // the stage says they are on screen.

    private var frontControls: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let screen = proxy.frame(in: .global)
            ZStack(alignment: .topLeading) {
                Color.clear
                spot(.turntable, origin, within: screen) {
                    Button(action: lookInside) { Color.clear.contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "gramophone.lookInside"))
                        .accessibilityHint(String(localized: "gramophone.lookInside.hint"))
                        .accessibilityIdentifier("gramophone.lookInside")
                }
                spot(.plate, origin) {
                    Color.clear
                        .accessibilityElement()
                        .accessibilityLabel(nowPlayingTitle)
                        .accessibilityValue(nowPlayingSubtitle)
                        .accessibilityIdentifier("gramophone.nameplate")
                }
                spot(.playSwitch, origin) {
                    Button(action: flipSwitch) { Color.clear.contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "gramophone.switch"))
                        .accessibilityValue(String(localized: isSwitchOn ? "gramophone.switch.on" : "gramophone.switch.off"))
                        .accessibilityIdentifier("gramophone.switch")
                }
                spot(.speed, origin) {
                    SpeedRegulator(isEnabled: musicService.isPlayingPodcast, rate: musicService.podcastRate,
                                   isDrawn: false, onSet: setSpeed)
                }
                spot(.crank, origin) {
                    GramophoneCrank(angle: $crankAngle, onTooth: {
                        GramophoneSound.ratchet.play()
                        UISelectionFeedbackGenerator().selectionChanged()
                    }, onWound: shuffleAll)
                }
                spot(.drawer, origin) {
                    Button(action: openCrate) { Color.clear.contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "gramophone.crate.open"))
                        .accessibilityIdentifier("gramophone.crate")
                }
                spot(.rack, origin, within: screen) {
                    Button(action: openRack) {
                        Color.clear.contentShape(Rectangle())
                            .overlay(alignment: .top) { rackTag.offset(y: -12) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "spool.queue.open"))
                    .accessibilityValue(musicService.upcoming.isEmpty ? ""
                                        : String(format: String(localized: "queue.upNextCount"), musicService.upcoming.count))
                    .accessibilityIdentifier("gramophone.upNext")
                }
            }
        }
        .ignoresSafeArea()
    }

    /// The control for a part of the machine, over where the part is on screen (or the
    /// part of it that's on screen), at least big enough for a finger.
    @ViewBuilder
    private func spot(_ hotspot: GramophoneHotspot, _ origin: CGPoint, within screen: CGRect = .infinite,
                      @ViewBuilder content: () -> some View) -> some View {
        if let whole = hotspots[hotspot], whole.width.isFinite, whole.height.isFinite {
            let shown = whole.intersection(screen)
            let rect = shown.isNull || shown.width < 44 ? whole : shown
            content()
                .frame(width: max(rect.width, 44), height: max(rect.height, 44))
                .position(x: rect.midX - origin.x, y: rect.midY - origin.y)
        }
    }

    /// The paper tag on the rack of records waiting.
    private var rackTag: some View {
        HStack(spacing: 4) {
            Text(String(localized: "spool.queue.title").uppercased())
                .tracking(1)
            if !musicService.upcoming.isEmpty {
                Text("\(musicService.upcoming.count)")
                    .monospacedDigit()
            }
        }
        .font(.system(size: 9, weight: .heavy, design: .serif))
        .foregroundStyle(theme.plateInk)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(theme.paper, in: RoundedRectangle(cornerRadius: 3))
        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        .fixedSize()
        .accessibilityHidden(true)
    }

    // MARK: - Overhead
    //
    // Looking down on the record: the turntable drawn in 2D, lying exactly over the 3D
    // record the camera came down to, with the controls under it.

    private var overhead: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: Self.topBarHeight)
            TurntableView(
                clock: musicService.clock,
                record: recordOnPlatter,
                isPlaying: musicService.isPlaying,
                isArmParked: isArmParked || recordOnPlatter == nil,
                onLift: liftNeedle,
                onDrop: dropNeedle,
                onHoldRecord: showSleeveOfRecord
            )
            .frame(maxHeight: .infinity)
            .overlay {
                // The bare wood under the record backs out to the front, as the chevron does.
                GeometryReader { proxy in
                    let (center, radius) = TurntableView.platter(in: proxy.size)
                    let top = center.y + radius * 1.14
                    BackOutArea { Task { await go(to: .front) } }
                        .frame(height: max(0, proxy.size.height - top))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: recordOnPlatter?.id)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                stage.setOverheadTurntable(frame: frame)
            }

            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    BrakeLever(isPlaying: musicService.isPlaying, action: brake)
                    Nameplate(title: nowPlayingTitle, subtitle: nowPlayingSubtitle)
                    SpeedRegulator(isEnabled: musicService.isPlayingPodcast, rate: musicService.podcastRate,
                                   onSet: setSpeed)
                }
                HStack(spacing: 14) {
                    UpNextPile(count: musicService.upcoming.count, action: openRack)
                    Button(action: openCrate) {
                        VStack(spacing: 6) {
                            Capsule()
                                .fill(theme.metalGradient)
                                .frame(width: 60, height: 8)
                                .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
                            Text(String(localized: "gramophone.crate").uppercased())
                                .font(.system(size: 12, weight: .heavy, design: .serif))
                                .tracking(3)
                                .foregroundStyle(theme.ink)
                        }
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(theme.woodGradient)
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.woodDark, lineWidth: 2))
                                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "gramophone.crate.open"))
                    .accessibilityIdentifier("gramophone.crate")
                }
            }
            .padding(14)
            .background(
                // The deck's front edge, nearest the camera.
                RoundedRectangle(cornerRadius: 16)
                    .fill(theme.woodGradient)
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(theme.woodDark, lineWidth: 3))
                    .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Moving Round the Machine

    /// Carries the camera to `target`. On the turntable the 2D turntable then takes
    /// over (unless `reveal` is false, for a record about to be put on); in the drawer,
    /// the crate is shown. Returns false if another move took over on the way.
    @discardableResult
    private func go(to target: GramophoneShot, reveal: Bool = true) async -> Bool {
        if vantage == Vantage(target) {
            if target == .turntable, reveal, !isOverheadShown { await revealTurntable() }
            return true
        }
        if isOverheadShown { await hideTurntable() }
        if vantage == .rack {
            // Leaving the bin, its records are flipped back to the front.
            isRemoveShown = false
            rackIndex = 0
            stage.setRackIndex(0, animated: !reduceMotion)
        }
        if isBrowsing {
            withAnimation(.easeInOut(duration: 0.25)) { isBrowsing = false }
            stage.setDrawerStackHidden(false)
        }
        vantage = .moving
        if (target == .drawer) != stage.isDrawerOpen {
            (target == .drawer ? GramophoneSound.drawerOpen : .drawerClose).play()
        }
        stage.setDrawer(open: target == .drawer, animated: !reduceMotion)
        guard await stage.move(to: target, duration: reduceMotion ? 0 : 1.4) else { return false }
        vantage = Vantage(target)
        switch target {
        case .turntable:
            if reveal { await revealTurntable() }
        case .drawer:
            // The stage says where the records are once it's drawn them there.
            try? await Task.sleep(for: .milliseconds(150))
            guard vantage == .drawer else { return true }
            withAnimation(.easeInOut(duration: 0.3)) { isBrowsing = true }
            try? await Task.sleep(for: .milliseconds(320))
            if vantage == .drawer { stage.setDrawerStackHidden(true) }
        case .front, .rack:
            break
        }
        return true
    }

    /// The 2D turntable fades in over the 3D one, and takes over.
    private func revealTurntable() async {
        withAnimation(.easeInOut(duration: 0.3)) { isOverheadShown = true }
        try? await Task.sleep(for: .milliseconds(320))
        if vantage == .turntable, isOverheadShown { stage.setTurntableHidden(true) }
    }

    private func hideTurntable() async {
        stage.setTurntableHidden(false)
        syncArm(animated: false)
        withAnimation(.easeInOut(duration: 0.25)) { isOverheadShown = false }
        try? await Task.sleep(for: .milliseconds(200))
    }

    private func lookInside() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task { await go(to: .turntable) }
    }

    /// The 3D arm where the 2D one is: riding the groove, or on its rest.
    private func syncArm(animated: Bool) {
        guard !isPutting else { return }
        let geometry = GramophoneStage.armGeometry
        let angle: Double
        if let record = recordOnPlatter, !isArmParked {
            angle = geometry.angle(forFraction: record.grooves.fraction(track: record.currentIndex,
                                                                        time: musicService.clock.time))
        } else {
            angle = geometry.restAngle
        }
        stage.setArm(angle: angle, lifted: false, animated: animated)
    }

    /// The play switch, thrown on while a record plays or is being started.
    private var isSwitchOn: Bool { musicService.isPlaying || isStarting }

    /// The play switch in front: off stops the record; on goes in to the turntable and
    /// starts it, or springs back when there's no record on.
    private func flipSwitch() {
        GramophoneSound.switchFlip.play()
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        if musicService.isPlaying {
            Task { await musicService.togglePlayPause() }
            return
        }
        guard recordOnPlatter != nil else {
            stage.setSwitch(on: true)
            Task {
                try? await Task.sleep(for: .milliseconds(220))
                stage.setSwitch(on: isSwitchOn)
            }
            showNotice(String(localized: "gramophone.noRecord"))
            return
        }
        isStarting = true
        Task {
            await go(to: .turntable)
            start()
            try? await Task.sleep(for: .milliseconds(800))
            isStarting = false
        }
    }

    private func setSpeed(_ rate: Float) {
        GramophoneSound.switchFlip.play()
        musicService.setPodcastRate(rate)
    }

    /// The drawer pulled out, and the camera looking down into it at the records.
    private func openCrate() {
        guard vantage == .front || vantage == .turntable else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        crateReturn = vantage == .turntable ? .turntable : .front
        Task { await go(to: .drawer) }
    }

    /// The picture of what's playing on the record's label.
    ///
    /// Only when the song playing is on the record shown. While a record is going on,
    /// what's playing is still the last record's song until the new one starts, and its
    /// cover used to end up on the new record's label; the stage labels the new record
    /// with its own cover meanwhile, and this runs again when its song starts.
    private func showNowPlayingLabel() async {
        guard !isPlayingOffAnotherRecord, let item = musicService.currentMediaItem,
              let artwork = item.artwork else { return }
        let image = await RecordLabelArt.image(for: artwork, id: item.persistentID)
        // A record may have gone on, or the song moved on, while the picture loaded.
        guard !isPlayingOffAnotherRecord, musicService.currentMediaItem?.persistentID == item.persistentID else { return }
        stage.setLabel(image)
    }

    /// Whether the record shown is the one put on, and what's playing isn't on it: the
    /// last record's song, still playing while the new record goes on.
    private var isPlayingOffAnotherRecord: Bool {
        guard let seated, recordOnPlatter?.id == seated.id, musicService.hasNowPlaying else { return false }
        // The same test as `recordOnPlatter`'s for the record put on being what's playing.
        return !(seated.album.map(library.isPlaying(from:)) ?? isSeatedShufflePlaying(seated))
    }

    /// The bin's records: the songs waiting, with the covers of those in view.
    private func fillRack() async {
        let tracks = musicService.upcoming
        stage.setRackQueue(ids: tracks.map(\.id))
        if rackIndex != stage.rackIndex { rackIndex = stage.rackIndex }
        guard !tracks.isEmpty else { return }
        let window = max(rackIndex - 5, 0)...min(rackIndex + 11, tracks.count - 1)
        // The front one first, then outward from it.
        for index in window.sorted(by: { abs($0 - rackIndex) < abs($1 - rackIndex) }) {
            let track = tracks[index]
            guard !stage.hasRackArt(id: track.id) else { continue }
            if let image = await RecordLabelArt.image(for: track, size: 300) {
                stage.setRackArt(image, id: track.id)
            }
            guard !Task.isCancelled else { return }
        }
    }

    // MARK: - The Up Next Bin

    /// Round to the front of the bin of Up Next's records.
    private func openRack() {
        guard vantage == .front || vantage == .turntable else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task { await go(to: .rack) }
    }

    private func closeRack() {
        guard vantage == .rack else { return }
        Task { await go(to: .front) }
    }

    private var rackControls: some View {
        let tracks = musicService.upcoming
        let front = tracks.indices.contains(rackIndex) ? tracks[rackIndex] : nil
        return GeometryReader { proxy in
            let bounds = proxy.frame(in: .global)
            let rect = rackRecordFrame(in: bounds)
            ZStack {
                // In front of the bin: puts a record slid aside back, or closes the bin.
                let floor = rect.maxY + 30 - bounds.minY
                BackOutArea { isRemoveShown ? showRemove(false) : closeRack() }
                    .frame(width: bounds.width, height: max(0, bounds.height - floor))
                    .position(x: bounds.width / 2, y: floor + max(0, bounds.height - floor) / 2)
                if let front {
                    rackRecord(front, count: tracks.count, rect: rect)
                        .frame(width: rect.width + 40, height: rect.height + 40)
                        .position(x: rect.midX - bounds.minX, y: rect.midY - bounds.minY)
                    if isRemoveShown {
                        Button(action: removeFromRack) {
                            VStack(spacing: 6) {
                                Image(systemName: "trash")
                                    .font(.system(size: 20, weight: .semibold))
                                Text(String(localized: "gramophone.rack.remove"))
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .frame(width: 84, height: 84)
                            .background(Color(red: 0.62, green: 0.14, blue: 0.1), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .accessibilityIdentifier("gramophone.rack.remove")
                        .position(x: rect.maxX - bounds.minX - 44, y: rect.midY - bounds.minY)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                } else {
                    Text(String(localized: "gramophone.rack.empty"))
                        .font(.system(size: 15, weight: .medium, design: .serif))
                        .italic()
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(18)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                        .position(x: rect.midX - bounds.minX, y: rect.midY - bounds.minY)
                }
                VStack(spacing: 0) {
                    rackHeader(front, count: tracks.count)
                    Spacer()
                    if front != nil {
                        Text(String(localized: "gramophone.rack.instructions"))
                            .font(.system(size: 13, weight: .medium, design: .serif))
                            .italic()
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, safeArea.top + 8)
                .padding(.bottom, safeArea.bottom + 8)
            }
        }
        .ignoresSafeArea()
        .background(
            LinearGradient(stops: [.init(color: .black.opacity(0.7), location: 0),
                                   .init(color: .clear, location: 0.22),
                                   .init(color: .clear, location: 0.85),
                                   .init(color: .black.opacity(0.5), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        )
    }

    private func rackHeader(_ front: AppTrack?, count: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "spool.queue.title").uppercased())
                    .font(.system(size: 11, weight: .heavy, design: .serif))
                    .tracking(2)
                    .foregroundStyle(theme.paper.opacity(0.8))
                Text(front?.title ?? String(localized: "spool.queue.title"))
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let front {
                    Text([front.artistName, String(format: String(localized: "gramophone.stack.position"), rackIndex + 1, count)]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.15), value: front?.id)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("gramophone.rack.nowShowing")
            Button(action: closeRack) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(theme.spoolTheme.keySymbol)
                    .frame(width: 34, height: 34)
                    .background(theme.spoolTheme.keyLight.opacity(0.85), in: Circle())
            }
            .accessibilityLabel(String(localized: "gramophone.rack.close"))
            .accessibilityIdentifier("gramophone.rack.close")
        }
    }

    /// The record at the front of the bin: what a finger works.
    private func rackRecord(_ track: AppTrack, count: Int, rect: CGRect) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                if isRemoveShown { showRemove(false) } else { playFromQueue(at: rackIndex) }
            }
            .onLongPressGesture(minimumDuration: 0.45, maximumDistance: 8) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showRemove(false)
                openQueue()
            }
            .simultaneousGesture(rackSwipe(count: count, height: rect.height))
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(track.title)
            .accessibilityValue(String(format: String(localized: "gramophone.stack.position"), rackIndex + 1, count))
            .accessibilityHint(String(localized: "gramophone.rack.hint"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: flipRack(by: 1, count: count)
                case .decrement: flipRack(by: -1, count: count)
                @unknown default: break
                }
            }
            .accessibilityAction(named: String(localized: "gramophone.rack.remove.action")) { removeFromRack() }
            .accessibilityAction(named: String(localized: "gramophone.rack.reorder")) { openQueue() }
            .accessibilityIdentifier("gramophone.rack.record")
    }

    /// Down flips the front record forward, onto the next; up flips the one before
    /// back. Left pushes it aside, to take it out.
    private func rackSwipe(count: Int, height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let move = value.translation
                if rackAxis == nil { rackAxis = abs(move.width) > abs(move.height) ? .horizontal : .vertical }
                switch rackAxis {
                case .vertical:
                    if isRemoveShown { showRemove(false) }
                    var pull = Float(move.height / max(height, 1)) * 1.4
                    // Nothing further that way: it gives a little, and no more.
                    if (pull > 0 && rackIndex >= count - 1) || (pull < 0 && rackIndex == 0) { pull *= 0.15 }
                    stage.setRackPull(pull)
                case .horizontal:
                    guard musicService.canEditUpcoming else { return }
                    let open: Float = isRemoveShown ? -0.07 : 0
                    stage.setRackSlide(min(0, max(-0.12, open + Float(move.width / 1000))), animated: false)
                default:
                    break
                }
            }
            .onEnded { value in
                defer { rackAxis = nil }
                switch rackAxis {
                case .vertical:
                    let move = value.translation.height, heading = value.predictedEndTranslation.height
                    let step = move > 0 ? 1 : -1
                    let committed = (abs(move) > 70 || abs(heading) > 180) && (heading > 0) == (move > 0)
                    if committed, (0..<count).contains(rackIndex + step) {
                        flipRack(by: step, count: count)
                    } else {
                        stage.setRackPull(0, animated: true)
                    }
                case .horizontal:
                    guard musicService.canEditUpcoming else { return }
                    let move = value.translation.width
                    showRemove(isRemoveShown ? move < 40 : move < -50)
                default:
                    break
                }
            }
    }

    private func flipRack(by step: Int, count: Int) {
        guard (0..<count).contains(rackIndex + step) else { return }
        GramophoneSound.flip.play()
        UISelectionFeedbackGenerator().selectionChanged()
        showRemove(false)
        rackIndex += step
        stage.setRackIndex(rackIndex, animated: !reduceMotion)
    }

    private func showRemove(_ shown: Bool) {
        guard shown != isRemoveShown || !shown else { return }
        withAnimation(.easeOut(duration: 0.2)) { isRemoveShown = shown }
        stage.setRackSlide(shown ? -0.07 : 0, animated: true)
    }

    /// The front record taken out of the bin, and out of Up Next.
    private func removeFromRack() {
        guard musicService.canEditUpcoming else { return }
        let index = rackIndex
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        withAnimation(.easeOut(duration: 0.2)) { isRemoveShown = false }
        stage.setRackSlide(-0.4, animated: !reduceMotion)
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 260))
            if let removed = musicService.removeFromQueue(at: index) {
                showNotice(String(format: String(localized: "queue.removed"), removed.title))
            } else {
                stage.setRackSlide(0, animated: true)
            }
        }
    }

    /// Where the bin's front record is on screen: where the stage says, once the camera's
    /// there, or about there until it says.
    private func rackRecordFrame(in bounds: CGRect) -> CGRect {
        if vantage == .rack, let rect = hotspots[.rackRecord], rect.width.isFinite, rect.width > 40 { return rect }
        let side = bounds.width * 0.8
        return CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
    }

    // MARK: - The Crate

    /// Fewer records than this are quick enough to swipe through, and get no index.
    private static let indexMinimumRecords = 12

    /// The records on the shelf in the drawer: those that match, while searching.
    private var crateItems: [AppAlbum] { crateMatches?.items(on: shelf) ?? library.items(on: shelf) }

    private var crate: some View {
        let albums = crateItems
        let front = albums.first { $0.id == frontID.wrappedValue } ?? albums.first
        return GeometryReader { proxy in
            let bounds = proxy.frame(in: .global)
            let frame = stackFrame(in: bounds)
            ZStack {
                // Below the records, the drawer's front and under it: closes the drawer.
                let below = frame.maxY + frame.width * 0.12 - bounds.minY
                BackOutArea(action: closeCrate)
                    .frame(width: bounds.width, height: max(0, bounds.height - below))
                    .position(x: bounds.width / 2, y: below + max(0, bounds.height - below) / 2)
                if albums.isEmpty {
                    emptyShelf
                        .frame(width: frame.width)
                        .position(x: frame.midX - proxy.frame(in: .global).minX,
                                  y: frame.midY - proxy.frame(in: .global).minY)
                } else {
                    RecordStackView(albums: albums, frame: frame, frontID: frontID,
                                    onOpen: openRecord,
                                    onQueue: { album, placement in queue(album, placement: placement) })
                        // Rebuilt for each search too, so it opens on a record that's there.
                        .id("\(shelf.rawValue):\(crateMatches?.query ?? "")")
                        .transition(.opacity)
                        // Handling the records is the sign typing is done.
                        .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { _ in
                            isCrateSearchFocused = false
                        })
                    // The A–Z index along the drawer's front, between the records and
                    // the part of the drawer that closes it.
                    if albums.count >= Self.indexMinimumRecords {
                        let height = max(30, frame.width * 0.13)
                        RecordIndexStrip(albums: albums, frontID: frontID)
                            .frame(width: max(0, bounds.width - 28), height: height)
                            // Clear of the sleeves under the top one, which lie askew.
                            .position(x: bounds.width / 2, y: frame.maxY + 12 + height / 2 - bounds.minY)
                            .transition(.opacity)
                    }
                }
                VStack(spacing: 10) {
                    ShelfSearchField(query: $crateQuery, prompt: String(localized: "gramophone.search.prompt"),
                                     isFocused: $isCrateSearchFocused)
                    ShelfDividers(
                        shelf: $shelf,
                        title: { ShelfSearchMatches.dividerTitle(Self.shelfTitle($0), on: $0, matches: crateMatches) },
                        onFindShows: { showPodcastSearch = true }
                    )
                    crateHeader(front)
                    Spacer()
                    if !albums.isEmpty {
                        Text(String(localized: "gramophone.stack.instructions"))
                            .font(.system(size: 13, weight: .medium, design: .serif))
                            .italic()
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, safeArea.top + 8)
                .padding(.bottom, safeArea.bottom + 8)
            }
        }
        .ignoresSafeArea()
        .background(
            // Shaded at the top and bottom for the dividers and the words, and clear
            // over the drawer, where the records are.
            LinearGradient(stops: [.init(color: .black.opacity(0.8), location: 0),
                                   .init(color: .black.opacity(0.45), location: 0.3),
                                   .init(color: .clear, location: 0.42),
                                   .init(color: .clear, location: 0.85),
                                   .init(color: .black.opacity(0.5), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        )
    }

    /// The name of the record on top of the stack, and closing the drawer.
    private func crateHeader(_ front: AppAlbum?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(front?.tapeTitle ?? String(localized: "gramophone.crate"))
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let front {
                    Text([front.caseByline, front.tapeTrackCount.map(front.tapeFormat.count)]
                            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.15), value: front?.id)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("gramophone.stack.nowShowing")
            Button(action: closeCrate) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(theme.spoolTheme.keySymbol)
                    .frame(width: 34, height: 34)
                    .background(theme.spoolTheme.keyLight.opacity(0.85), in: Circle())
            }
            .accessibilityLabel(String(localized: "gramophone.crate.close"))
            .accessibilityIdentifier("gramophone.crate.close")
        }
    }

    private var emptyShelf: some View {
        VStack(spacing: 14) {
            Text(crateMatches == nil ? Self.emptyText(on: shelf) : String(localized: "search.noResults"))
                .multilineTextAlignment(.center)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            if shelf == .podcasts, crateMatches == nil {
                Button(String(localized: "spool.shelf.findShows")) { showPodcastSearch = true }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.spoolTheme.keySymbol)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(theme.spoolTheme.keyLight.opacity(0.9), in: Capsule())
                    .accessibilityIdentifier("spool.shelf.emptyAction")
            }
        }
        .padding(18)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
    }

    /// Where the top record in the drawer is on screen: where the stage says, once the
    /// camera's looking into the drawer, or about there until it says.
    private func stackFrame(in bounds: CGRect) -> CGRect {
        if vantage == .drawer, let rect = hotspots[.stack], rect.width.isFinite, rect.width > 40 { return rect }
        let side = bounds.width * CGFloat(GramophoneStage.stackSleeveSide) / 0.42
        return CGRect(x: bounds.midX - side / 2, y: bounds.minY + bounds.height * 0.56 - side / 2,
                      width: side, height: side)
    }

    /// A record tapped in the drawer: its sleeve opens to choose a song (even a
    /// single's, so it can be queued from there too).
    /// A song from the bin: its album's record, put on at that song; a record of its own
    /// when its album isn't in the library.
    private func putSong(_ track: AppTrack) {
        let title = TapeFormat.displayTitle(track.albumTitle)
        let albums = library.albums.filter { $0.tapeTitle == title }
        guard let album = albums.first(where: { $0.artistName == track.artistName }) ?? albums.first else {
            put(nil, title: track.title, label: .track(track), tracks: [track], startingAt: 0,
                addToQueue: { queue([track], placement: .last, name: track.title) })
            return
        }
        Task {
            let tracks = await library.tracks(for: album)
            let index = tracks.firstIndex { $0.id == track.id } ?? tracks.firstIndex { $0.title == track.title } ?? 0
            put(album, tracks: tracks.isEmpty ? [track] : tracks, startingAt: tracks.isEmpty ? 0 : index,
                addToQueue: { queue([track], placement: .last, name: track.title) })
        }
    }

    private func openRecord(_ album: AppAlbum) {
        isCrateSearchFocused = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        openSleeve = album
    }

    /// The covers on the records lying in the drawer, the top one first: what the
    /// stack shows when the camera comes into the drawer, and leaves it.
    private func fillDrawer() async {
        let albums = crateItems
        let index = albums.firstIndex { $0.id == frontID.wrappedValue } ?? 0
        var art: [UIImage?] = []
        for album in albums.dropFirst(index).prefix(3) {
            art.append(RecordKind(album) == .album ? await RecordLabelArt.image(for: .album(album), size: 300) : nil)
            guard !Task.isCancelled else { return }
        }
        stage.setDrawerStack(art: art)
    }

    nonisolated private static func shelfTitle(_ shelf: SpoolShelf) -> String {
        switch shelf {
        case .albums:   return String(localized: "spool.shelf.albums")
        case .mixtapes: return String(localized: "gramophone.shelf.recordings")
        case .podcasts: return String(localized: "gramophone.shelf.broadcasts")
        }
    }

    private static func emptyText(on shelf: SpoolShelf) -> String {
        switch shelf {
        case .albums:   return String(localized: "spool.shelf.empty")
        case .mixtapes: return String(localized: "gramophone.shelf.recordings.empty")
        case .podcasts: return String(localized: "spool.shelf.podcasts.empty")
        }
    }

    private var frontID: Binding<String?> {
        switch shelf {
        case .albums:   return $albumFrontID
        case .mixtapes: return $recordingFrontID
        case .podcasts: return $broadcastFrontID
        }
    }

    /// The drawer pushed back in, and the camera back where it was.
    private func closeCrate() {
        guard vantage == .drawer else { return }
        Task { await go(to: crateReturn) }
    }

    // MARK: - The Record

    /// The record on the turntable now: the one put on, while it's what's playing; or,
    /// when something else is playing (started in another player, or from Up Next), a
    /// record of the queue around it.
    private var recordOnPlatter: RecordOnPlatter? {
        if let seated {
            let isSeatedPlaying = seated.album.map(library.isPlaying(from:)) ?? isSeatedShufflePlaying(seated)
            if isSeatedPlaying || isLoadingRecord || !musicService.hasNowPlaying {
                return platter(for: seated)
            }
        }
        if let episode = musicService.currentEpisode {
            return RecordOnPlatter(kind: .transcription, title: episode.showTitle, label: .plain,
                                   grooves: GrooveMap(durations: [episode.duration]), currentIndex: 0,
                                   id: "episode:\(episode.id)")
        }
        guard let current = musicService.currentTrack else { return seated.map(platter(for:)) }
        let queue = musicService.playbackQueue
        let tracks = queue.tracks.isEmpty ? [current] : queue.tracks
        let index = tracks.firstIndex { $0.id == current.id } ?? 0
        return RecordOnPlatter(kind: .album, title: TapeFormat.displayTitle(current.albumTitle),
                               label: .track(current), grooves: GrooveMap(durations: tracks.map(\.duration)),
                               currentIndex: index, id: "queue:\(tracks.first?.id ?? current.id)")
    }

    private func isSeatedShufflePlaying(_ seated: SeatedRecord) -> Bool {
        guard let id = musicService.currentTrack?.id else { return false }
        return seated.tracks.contains { $0.id == id }
    }

    private func platter(for seated: SeatedRecord) -> RecordOnPlatter {
        let playingID = musicService.currentEpisode?.id ?? musicService.currentTrack?.id
        let index = playingID.flatMap { id in seated.tracks.firstIndex { $0.id == id } } ?? 0
        return RecordOnPlatter(kind: RecordKind(seated.album), title: seated.title,
                               label: seated.label ?? seated.album.map(RecordLabel.album) ?? .plain,
                               grooves: GrooveMap(durations: seated.tracks.map(\.duration)),
                               currentIndex: index, id: seated.id)
    }

    /// Puts a record on the turntable and drops the needle on song `index`: the camera
    /// comes to the turntable, the record comes out of its sleeve and down onto the
    /// platter, the arm swings over and lowers the needle onto the song's band, and it
    /// plays.
    /// `addToQueue` is what to queue instead, offered when asking; `asks` is false for a
    /// record that plays on from Up Next rather than replacing it.
    private func put(_ album: AppAlbum?, title: String? = nil, label: RecordLabel? = nil,
                     tracks: [AppTrack], startingAt index: Int,
                     addToQueue: (() -> Void)? = nil, asks: Bool = true,
                     play start: (() async -> PlaybackStartOutcome)? = nil) {
        guard asks else {
            putRecord(album, title: title, label: label, tracks: tracks, startingAt: index, play: start)
            return
        }
        // A new record replaces Up Next: ask first if it holds songs queued by hand,
        // before the record on the turntable comes off.
        musicService.play(asking: { pendingPlay = $0 }, addToQueue: addToQueue) {
            putRecord(album, title: title, label: label, tracks: tracks, startingAt: index, play: start)
        }
    }

    private func putRecord(_ album: AppAlbum?, title: String?, label: RecordLabel?,
                           tracks: [AppTrack], startingAt index: Int,
                           play start: (() async -> PlaybackStartOutcome)?) {
        guard !tracks.isEmpty else {
            showNotice(String(localized: "playback.nothingPlayable"))
            return
        }
        openSleeve = nil
        isStarting = true
        Task {
            defer { isStarting = false }
            async let art = RecordLabelArt.image(for: label ?? album.map(RecordLabel.album) ?? .plain)
            guard await go(to: .turntable, reveal: false) else { return }
            isPutting = true
            defer { isPutting = false }
            if !isArmParked { GramophoneSound.needleLift.play() }
            await stage.liftRecordOff(animated: !reduceMotion)
            isArmParked = true
            seated = SeatedRecord(album: album, title: title ?? album?.tapeTitle ?? "", tracks: tracks, label: label)
            isLoadingRecord = true
            defer { isLoadingRecord = false }
            let band = GrooveMap(durations: tracks.map(\.duration)).fraction(track: index, time: 0)
            await stage.putRecord(kind: RecordKind(album), sleeveArt: await art,
                                  armTo: GramophoneStage.armGeometry.angle(forFraction: band),
                                  animated: !reduceMotion)
            GramophoneSound.needleDrop.play()
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            isArmParked = false
            let outcome: PlaybackStartOutcome
            if let start {
                outcome = await start()
            } else if let album {
                outcome = await library.play(album, tracks: tracks, startingAt: index)
            } else {
                outcome = await musicService.play(tracks: tracks, startingAt: index)
            }
            if outcome != .started {
                showNotice(String(localized: "playback.nothingPlayable"))
            }
            isPutting = false
            syncArm(animated: true)
            await revealTurntable()
        }
    }

    /// The whole record, from the crate: its songs load while it's carried over.
    private func putWhole(_ album: AppAlbum) {
        Task {
            let tracks = await library.tracks(for: album)
            put(album, tracks: tracks, startingAt: 0,
                addToQueue: album.isPodcast ? nil : { queue(tracks, placement: .last, name: album.tapeTitle) })
        }
    }

    private func showSleeveOfRecord() {
        guard let album = seated?.album, recordOnPlatter?.id == seated?.id else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        openSleeve = album
    }

    // MARK: - The Tonearm

    private func liftNeedle() {
        GramophoneSound.needleLift.play()
        if musicService.isPlaying {
            Task { await musicService.togglePlayPause() }
        }
    }

    /// The arm put down: on the record at `fraction`, playing that song from there, or
    /// on its rest (nil), stopped.
    private func dropNeedle(_ fraction: Double?) {
        guard let fraction, let record = recordOnPlatter else {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { isArmParked = true }
            return
        }
        let (index, time) = record.grooves.position(at: fraction)
        // Another song on the record put on starts the record again from there, which
        // replaces Up Next: ask first if it holds songs queued by hand. Said no to, the
        // arm goes back to the song that's playing.
        let startsAgain = seated.map { record.id == $0.id } == true
            && !(index == record.currentIndex && musicService.hasNowPlaying)
        if startsAgain, musicService.listenerQueuedCount > 0 {
            let song = seated.flatMap { $0.tracks.indices.contains(index) && $0.album?.isPodcast != true ? $0.tracks[index] : nil }
            pendingPlay = PendingPlay(action: { lowerNeedle(on: record, at: index, time: time) },
                                      addToQueue: song.map { song in { queue([song], placement: .last, name: song.title) } },
                                      onCancel: { syncArm(animated: true) })
            return
        }
        lowerNeedle(on: record, at: index, time: time)
    }

    /// The needle down on song `index` of `record`, `time` into it, and that song playing.
    private func lowerNeedle(on record: RecordOnPlatter, at index: Int, time: TimeInterval) {
        GramophoneSound.needleDrop.play()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        isArmParked = false
        Task {
            if index == record.currentIndex, musicService.hasNowPlaying {
                await musicService.seek(to: time)
                musicService.clock.time = time
                if !musicService.isPlaying { await musicService.togglePlayPause() }
                return
            }
            let outcome: PlaybackStartOutcome
            if let seated, record.id == seated.id {
                if let album = seated.album {
                    outcome = await library.play(album, tracks: seated.tracks, startingAt: index)
                } else {
                    outcome = await musicService.play(tracks: seated.tracks, startingAt: index)
                }
            } else if index > record.currentIndex,
                      musicService.upcoming.indices.contains(index - record.currentIndex - 1) {
                // A record of the queue: a later band is a song in Up Next.
                musicService.playUpcoming(at: index - record.currentIndex - 1)
                outcome = .started
            } else {
                let tracks = musicService.playbackQueue.tracks
                outcome = tracks.indices.contains(index)
                    ? await musicService.play(tracks: tracks, startingAt: index)
                    : .nothingPlayable
            }
            guard outcome == .started else {
                showNotice(String(localized: "playback.nothingPlayable"))
                return
            }
            if time > 1 {
                try? await Task.sleep(for: .milliseconds(400))
                await musicService.seek(to: time)
            }
        }
    }

    // MARK: - Controls

    /// The brake, looking down on the record: stops it, and steps back out to the
    /// front of the machine; or starts it again.
    private func brake() {
        GramophoneSound.switchFlip.play()
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        if musicService.isPlaying {
            Task {
                await musicService.togglePlayPause()
                await go(to: .front)
            }
            return
        }
        start()
    }

    /// Starts the record on the turntable: with the arm on its rest, it swings back onto
    /// the record first.
    private func start() {
        guard let record = recordOnPlatter else {
            showNotice(String(localized: "gramophone.noRecord"))
            return
        }
        if isArmParked {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { isArmParked = false }
        }
        Task {
            if musicService.hasNowPlaying {
                try? await Task.sleep(for: .milliseconds(350))
                GramophoneSound.needleDrop.play()
                if !musicService.isPlaying { await musicService.togglePlayPause() }
            } else if let seated, record.id == seated.id {
                put(seated.album, title: seated.title, tracks: seated.tracks, startingAt: 0)
            }
        }
    }

    /// The crank wound a full turn: every song, shuffled, on a fresh record.
    private func shuffleAll() {
        GramophoneSound.wound.play()
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        let songs = library.songs.shuffled()
        guard !songs.isEmpty else {
            showNotice(String(localized: "gramophone.shuffle.empty"))
            return
        }
        // Said now only if there's nothing to ask first.
        if musicService.listenerQueuedCount == 0 { showNotice(String(localized: "gramophone.shuffle.done")) }
        // The record shows the first few dozen; the rest follow in the queue.
        put(nil, title: String(localized: "gramophone.shuffle.title"),
            tracks: Array(songs.prefix(Self.recordLength)), startingAt: 0,
            addToQueue: { queue(songs, placement: .last, name: String(localized: "menu.songs")) }) {
            await musicService.play(tracks: songs, startingAt: 0)
        }
    }

    /// The most songs a record pressed from a list (a shuffle, or Up Next) shows; the
    /// rest still play, after it.
    private static let recordLength = 30

    // MARK: - Up Next

    private func openQueue() {
        guard !isBrowsing else { return }
        isQueueShown = true
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { queueProgress = 1 }
    }

    private func closeQueue() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
            queueProgress = 0
        } completion: {
            if queueProgress == 0 { isQueueShown = false }
        }
    }

    /// A record taken from the bin or Up Next, put on as one from the drawer is: the
    /// camera comes to the turntable, the old record comes off, this one goes down with
    /// its song's cover on the label, the needle drops, and it plays. The rest of Up Next
    /// stays, the songs that were ahead of it now behind it, so its bands are that song
    /// and then the rest of Up Next, as they'll play.
    private func playFromQueue(at offset: Int) {
        closeQueue()
        let upcoming = musicService.upcoming
        guard upcoming.indices.contains(offset) else { return }
        let track = upcoming[offset]
        let after = upcoming.indices.filter { $0 != offset }.map { upcoming[$0] }
        // Plays on from Up Next rather than replacing it, so nothing to ask.
        put(nil, title: TapeFormat.displayTitle(track.albumTitle), label: .track(track),
            tracks: Array(([track] + after).prefix(Self.recordLength)), startingAt: 0, asks: false) {
            musicService.playUpcoming(at: offset)
            return .started
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

    // MARK: - Surface Noise

    /// On while a record plays under the needle, when the setting is on.
    private var crackleIsOn: Bool {
        themeSettings.gramophoneSurfaceNoise && musicService.isPlaying && !isArmParked && recordOnPlatter != nil
    }

    /// The record's crackle and the turntable turning, faint under the music, in
    /// overlapping pieces; cut off as soon as the record stops.
    private func playSurfaceNoise() async {
        guard crackleIsOn else {
            GramophoneSound.stopSurfaceNoise()
            return
        }
        var count = 0
        while !Task.isCancelled {
            GramophoneSound.nextCrackle(after: count).play()
            GramophoneSound.nextRunning(after: count).play()
            count += 1
            try? await Task.sleep(for: GramophoneSound.crackleInterval)
        }
        GramophoneSound.stopSurfaceNoise()
    }

    // MARK: - Now Playing

    private var nowPlayingTitle: String {
        musicService.currentTrack?.title ?? musicService.currentEpisode?.title ?? String(localized: "gramophone.noRecord.title")
    }

    private var nowPlayingSubtitle: String {
        if let episode = musicService.currentEpisode { return episode.showTitle }
        if let track = musicService.currentTrack {
            return track.albumTitle.isEmpty ? track.artistName : "\(track.artistName) — \(track.albumTitle)"
        }
        return String(localized: "gramophone.noRecord.hint")
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

/// The view as it is, or hidden — still taking its room, but neither drawn nor found by
/// VoiceOver.
private struct PresentIf: ViewModifier {
    let isPresent: Bool

    func body(content: Content) -> some View {
        if isPresent { content } else { content.hidden() }
    }
}

/// Empty space around what the camera's looking at that backs out of it, as the
/// close button does. VoiceOver has the button.
private struct BackOutArea: View {
    let action: () -> Void

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .accessibilityHidden(true)
    }
}

/// The part of Up Next the bin shows: its covers load when it changes.
private struct RackWindow: Hashable {
    let ids: [String]
    let index: Int
}

/// The record put on the turntable.
private struct SeatedRecord {
    /// The album, playlist or show it was pressed from; none for a shuffle or a record
    /// taken from Up Next.
    let album: AppAlbum?
    let title: String
    let tracks: [AppTrack]
    /// What's on its label, when it isn't the album's: a record from Up Next has its
    /// first song's cover.
    var label: RecordLabel? = nil

    var id: String { album?.id ?? "shuffle:\(tracks.first?.id ?? "")" }
}

// MARK: - Record Card

/// A record in the crate, in its sleeve: an album's printed cover, a home recording's
/// plain sleeve with the label showing through, or a broadcast disc's.
struct RecordCard: View, Equatable {
    let album: AppAlbum
    let size: CGSize

    static func == (lhs: RecordCard, rhs: RecordCard) -> Bool {
        lhs.album.id == rhs.album.id && lhs.size == rhs.size
    }

    var body: some View {
        let side = size.width
        ZStack {
            switch RecordKind(album) {
            case .album:
                TapeArtwork(album: album, size: side.rounded())
                    .frame(width: side, height: side)
            case .homeRecording:
                Rectangle()
                    .fill(Color(red: 0.76, green: 0.62, blue: 0.42))
                    .overlay {
                        RecordDisc(kind: .homeRecording, title: album.tapeTitle, label: .album(album), diameter: side * 0.9)
                            .mask(Circle().frame(width: side * 0.42, height: side * 0.42))
                    }
            case .transcription:
                Rectangle()
                    .fill(Color(red: 0.12, green: 0.18, blue: 0.3))
                    .overlay {
                        TapeArtwork(album: album, size: (side * 0.42).rounded())
                            .frame(width: side * 0.42, height: side * 0.42)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(.black.opacity(0.4), lineWidth: 3))
                    }
                    .overlay(alignment: .bottom) {
                        Text(String(localized: "gramophone.record.broadcast").uppercased())
                            .font(.system(size: side * 0.05, weight: .black, design: .serif))
                            .tracking(side * 0.01)
                            .foregroundStyle(Color(red: 0.96, green: 0.88, blue: 0.64))
                            .padding(.bottom, side * 0.08)
                    }
            }
            // The sleeve's edge.
            RoundedRectangle(cornerRadius: side * 0.012)
                .strokeBorder(.white.opacity(0.25), lineWidth: 1)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.012))
        .background(
            RoundedRectangle(cornerRadius: side * 0.012)
                .fill(.black)
                .shadow(color: .black.opacity(0.45), radius: 8, x: 0, y: -2)
        )
    }
}
