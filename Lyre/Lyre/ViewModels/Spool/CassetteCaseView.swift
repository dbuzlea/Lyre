//
//  CassetteCaseView.swift
//  Lyre
//

import SwiftUI

// MARK: - Cassette Case
//
// The clear plastic case an album's tape comes in. A mixtape's case holds a J-card
// written by hand, its songs listed side by side as they were taped. A podcast's case
// lists its episodes, newest first, with their dates and whether they're downloaded. In the rack it is closed, with the
// J-card's front — the album art, title and artist — showing through the lid. Chosen, it
// lifts out of the rack, grows to the middle of the screen and swings its lid open on the
// hinge, the way the Artwork Carousel opens a record's gatefold. Open, the lid holds the
// J-card's inside, the cover beside the track listing, and the tray below holds the
// cassette.
//
// Choosing a song sends the cassette from the tray into the deck to play from that song;
// Play and Shuffle, or tapping the cassette, send the whole tape. Holding a song offers to
// queue it instead. Tapping outside the case or its close button swings the lid shut and
// puts the case back in the rack.
//
// Opening is one driven value, `progress`: 0 is the closed case sitting where it was in
// the rack, 1 is the case open in the middle of the screen. Everything is computed from it
// each frame (through AnimatableFold, as the gatefold does), so the lid can close from
// wherever it has got to. It runs in two overlapping stages:
//
// • travel (0…0.45) lifts the case out of its slot to the middle of the screen;
// • swing (0.3…1) turns the lid half a revolution about the hinge: its outside faces up
//   while closed, its inside once it passes upright, and it grows from the tray's height
//   to its full height as it lies back.
//
// So the open case's lid swings in place, as a record's sleeve does, and dragging down
// from the top of the lid scrubs `progress` with the finger: the lid folds up after it
// and can be pushed back open, and letting go closes it or springs it back open.
//
// The case is laid out in SpoolPlayerView's coordinate space, filling the screen, so the
// rack's frames and the deck's seat can be used as they are. On an unfolded iPhone Duo it
// opens within the rack's half instead (`bounds`): the lid and its song list over the
// tray on the right, the open deck left in view on the left, so a song picked can be seen
// going across into the door.

struct CassetteCaseView: View {
    let album: AppAlbum
    /// 0 closed in the rack, 1 open.
    let progress: CGFloat
    /// The case's place in the rack, where it opens from and closes back to.
    let closedFrame: CGRect
    let loadTracks: () async -> [AppTrack]
    /// The tracks, the index to start from, and the cassette's frame in
    /// SpoolPlayerView's coordinate space.
    let onPick: ([AppTrack], Int, CGRect) -> Void
    /// Queues songs without touching what's playing.
    let onQueue: ([AppTrack], QueuePlacement) -> Void
    let onClose: () -> Void
    /// The id of the song or episode playing, marked in the listing.
    var playingID: String?
    /// A finger dragging the lid: the progress to show, to be set without animation.
    var onScrub: (CGFloat) -> Void = { _ in }
    /// The finger let go of the lid: true to close the case, false to spring it open.
    var onScrubEnd: (Bool) -> Void = { _ in }
    /// Called once the case has been drawn closed in its slot, which is when it can start
    /// to open: started any sooner, the open state is the first one drawn.
    var onReady: () -> Void = {}
    /// Where the case opens, in SpoolPlayerView's coordinate space; nil for the whole
    /// screen. An unfolded Duo's rack, so the deck beside it stays in view.
    var bounds: CGRect? = nil

    @Environment(\.windowSafeArea) private var safeArea

    @State private var tracks: [AppTrack]?
    /// The cassette in the tray, where a flight sets off from.
    @State private var cassetteFrame: CGRect = .zero
    /// The progress when a drag on the lid began; nil when no drag is scrubbing.
    @State private var lidDragStart: CGFloat?

    static let corner: CGFloat = 18
    private static let hingeGap: CGFloat = 16

    var body: some View {
        // Read here, not inside the fold's closure: state read only in there isn't seen
        // as something this view depends on, and the list would never refresh.
        let tracks = self.tracks
        GeometryReader { geometry in
            let layout = Layout(size: geometry.size, safeArea: safeArea, bounds: bounds)
            AnimatableFold(progress: progress) { p in
                scene(p: p, layout: layout, tracks: tracks)
            }
        }
        .task {
            // Runs after the case is first drawn, closed in its slot: open from there.
            onReady()
            // Songs the album already carries show at once; the full load, which can
            // wait on the library, replaces them when it lands.
            if self.tracks == nil, !album.preloadedTracks.isEmpty { self.tracks = album.tapeSongs(album.preloadedTracks) }
            let loaded = await loadTracks()
            if !loaded.isEmpty || self.tracks == nil { self.tracks = loaded }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spool.jcard")
        .accessibilityAction(.escape) { onClose() }
    }

    // MARK: - Scene

    /// How far the case has come from its slot towards the middle of the screen.
    static func travel(_ p: CGFloat) -> CGFloat {
        let t = min(1, max(0, p / 0.45))
        return t * t * (3 - 2 * t)
    }

    /// How far the lid has swung open: 0 shut, 0.5 upright, 1 lying flat.
    static func swing(_ p: CGFloat) -> CGFloat {
        min(1, max(0, (p - 0.3) / 0.7))
    }

    private func scene(p: CGFloat, layout: Layout, tracks: [AppTrack]?) -> some View {
        let isOpen = p >= 0.999
        let travel = Self.travel(p)
        let swing = Self.swing(p)
        let tray = lerp(closedFrame, layout.tray, travel)
        // The lid covers the tray until it passes upright, then grows to its full height
        // as it lies back.
        let unfold = max(0, (swing - 0.5) / 0.5)
        let lidHeight = tray.height + (layout.lid.height - tray.height) * unfold * unfold
        let gap = Self.hingeGap * travel
        let lidBottom = tray.minY - gap
        let showsInside = swing > 0.5

        return ZStack(alignment: .topLeading) {
            Color.black.opacity(0.65 * p)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { if isOpen { onClose() } }
                .accessibilityHidden(true)

            Group {
                trayView(isOpen: isOpen, tracks: tracks)
                    .frame(width: tray.width, height: tray.height)
                    .position(x: tray.midX, y: tray.midY)

                if gap > 1 {
                    hinge
                        .frame(width: max(0, tray.width - 80), height: gap)
                        .position(x: tray.midX, y: tray.minY - gap / 2)
                }

                lidView(showsInside: showsInside, isOpen: isOpen, tracks: tracks)
                    .frame(width: tray.width, height: lidHeight)
                    .modifier(LidSwing(degrees: -180 * Double(1 - swing)))
                    .position(x: tray.midX, y: lidBottom - lidHeight / 2)
            }
        }
        // Simultaneous, so the buttons and songs under the lid's top still take taps.
        .simultaneousGesture(lidDrag(layout))
    }

    // MARK: - Lid

    @ViewBuilder
    private func lidView(showsInside: Bool, isOpen: Bool, tracks: [AppTrack]?) -> some View {
        if showsInside {
            lidInside(isOpen: isOpen, tracks: tracks)
        } else {
            // The outside, drawn upside down: the half turn that folds the lid over the
            // tray stands it the right way up.
            ClosedCaseFront(album: album)
                .scaleEffect(x: 1, y: -1)
        }
    }

    private func lidInside(isOpen: Bool, tracks: [AppTrack]?) -> some View {
        PlasticPanel {
            // The J-card, seen through the lid.
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    coverArt(size: 96)
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                        .accessibilityHidden(true)
                    if let stamp = album.tapeFormat.stamp {
                        Text(stamp.uppercased())
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(SpoolPalette.singleShellTop, in: RoundedRectangle(cornerRadius: 4))
                    }
                    if let blank = album.tapeBlank {
                        Text(blank)
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(SpoolPalette.label)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(SpoolPalette.labelInk, in: RoundedRectangle(cornerRadius: 4))
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(album.tapeTitle)
                        .font(album.isMixtape
                              ? .custom(SpoolPalette.handwriting, size: 21)
                              : .system(size: 18, weight: .bold, design: .serif))
                        .foregroundStyle(album.isMixtape ? SpoolPalette.pen : SpoolPalette.labelInk)
                        .lineLimit(2)
                        // Clear of the close button in the lid's corner.
                        .padding(.trailing, 28)
                    if let byline = album.caseByline {
                        Text(byline)
                            .font(.system(size: 14))
                            .opacity(0.7)
                            .lineLimit(1)
                            .padding(.top, 2)
                    }
                    Rectangle()
                        .fill(SpoolPalette.labelInk.opacity(0.3))
                        .frame(height: 1)
                        .padding(.vertical, 8)
                    if let tracks, !tracks.isEmpty {
                        playButtons(tracks)
                            .allowsHitTesting(isOpen)
                            .padding(.bottom, 6)
                    }
                    songList(tracks, scrolls: isOpen)
                }
            }
            .padding(12)
            .foregroundStyle(SpoolPalette.labelInk)
            .background(SpoolPalette.label, in: RoundedRectangle(cornerRadius: 4))
            .padding(12)
        }
        // A grip on the lid's top edge: drag down from there to fold the lid shut.
        .overlay(alignment: .top) {
            Capsule()
                .fill(.white.opacity(0.8))
                .frame(width: 40, height: 5)
                .padding(.top, 4)
                .opacity(isOpen ? 1 : 0)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(SpoolPalette.labelInk)
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.75), in: Circle())
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(String(localized: "spool.case.close"))
            .padding(14)
            .opacity(isOpen ? 1 : 0)
            .allowsHitTesting(isOpen)
        }
    }

    /// Play and Shuffle, at the head of the listing: the whole tape into the deck.
    private func playButtons(_ tracks: [AppTrack]) -> some View {
        HStack(spacing: 8) {
            Button { onPick(tracks, 0, cassetteFrame) } label: {
                // A podcast's first episode is its newest.
                Label(String(localized: album.isPodcast ? "spool.podcast.playLatest" : "detail.play"),
                      systemImage: "play.fill")
                    .foregroundStyle(SpoolPalette.label)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(SpoolPalette.labelInk, in: Capsule())
            }
            .accessibilityIdentifier("spool.case.play")
            // Episodes are for playing in order; only music shuffles.
            if !album.isPodcast {
            Button { onPick(tracks.shuffled(), 0, cassetteFrame) } label: {
                Label(String(localized: "detail.shuffle"), systemImage: "shuffle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .overlay(Capsule().strokeBorder(SpoolPalette.labelInk.opacity(0.6), lineWidth: 1.5))
            }
            .accessibilityIdentifier("spool.case.shuffle")
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .buttonStyle(.plain)
    }

    /// The track listing. While the lid is moving it is a plain stack: a scroll view
    /// inside a 3D turn is flattened to an image and draws smeared.
    @ViewBuilder
    private func songList(_ tracks: [AppTrack]?, scrolls: Bool) -> some View {
        if let tracks {
            if tracks.isEmpty {
                Text(String(localized: "spool.jcard.empty"))
                    .font(.system(size: 14))
                    .opacity(0.6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if scrolls {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) { rows(tracks, of: tracks) }
                }
            } else {
                VStack(alignment: .leading, spacing: 0) { rows(Array(tracks.prefix(14)), of: tracks) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The cover on the J-card: the album's, or a mixtape's cut-out covers.
    @ViewBuilder
    private func coverArt(size: CGFloat) -> some View {
        if album.isMixtape {
            MixtapeArtwork(album: album, size: size)
        } else {
            TapeArtwork(album: album, size: size)
        }
    }

    /// "SIDE A", "SIDE B": a mixtape's listing is split where the tape was turned over.
    private func sideHeading(_ key: String.LocalizationValue) -> some View {
        Text(String(localized: key).uppercased())
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .tracking(1.5)
            .opacity(0.55)
            .padding(.top, 10)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }

    private func rows(_ shown: [AppTrack], of tracks: [AppTrack]) -> some View {
        let sideB = album.isMixtape ? TapeFormat.sideBreak(in: tracks) : nil
        let episodes = album.podcast?.episodesNewestFirst
        // By place, not id: a mixtape can carry the same song twice.
        return ForEach(Array(shown.enumerated()), id: \.offset) { index, track in
            if sideB != nil, index == 0 { sideHeading("spool.mixtape.sideA") }
            if index == sideB { sideHeading("spool.mixtape.sideB") }
            Button { onPick(tracks, index, cassetteFrame) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if track.id == playingID {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 11))
                            .frame(width: 20, alignment: .trailing)
                            .accessibilityLabel(String(localized: "spool.case.playing"))
                    } else if !album.isPodcast {
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .opacity(0.5)
                            .frame(width: 20, alignment: .trailing)
                    }
                    if let episodes, episodes.indices.contains(index) {
                        episodeRow(episodes[index])
                    } else if album.isMixtape {
                        // Song and artist, written in.
                        VStack(alignment: .leading, spacing: 0) {
                            Text(track.title)
                                .font(.custom(SpoolPalette.handwriting, size: 15))
                                .foregroundStyle(SpoolPalette.pen)
                                .lineLimit(2)
                            Text(track.artistName)
                                .font(.system(size: 12))
                                .opacity(0.6)
                                .lineLimit(1)
                        }
                    } else {
                        Text(track.title)
                            .font(.system(size: 14))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    if album.isPodcast {
                        EpisodeDownloadMark(episodeID: track.id)
                    } else if track.duration > 0 {
                        Text(AppHelpers.formatTime(track.duration))
                            .font(.system(size: 12, design: .monospaced))
                            .opacity(0.5)
                    }
                }
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Swiped right, a song offers Play Next and Add to Queue, as every list in
            // Lyre does; an episode, its download.
            .rowSwipeActions(swipeActions(for: track), captionColor: SpoolPalette.labelInk.opacity(0.65))
            // Holding a song queues it rather than playing it; holding an episode, which
            // plays from the case, offers its download.
            .modifier(QueueMenu(isEnabled: !album.isPodcast, track: track,
                                episode: album.podcast?.episodes.first { $0.id == track.id },
                                onQueue: onQueue))
            .accessibilityActions {
                if !album.isPodcast {
                    Button(String(localized: "queue.action.playNext")) { onQueue([track], .next) }
                    Button(String(localized: "queue.action.addToQueue")) { onQueue([track], .last) }
                }
            }
            .accessibilityIdentifier("spool.jcard.track.\(index)")

            // Ruled like the card stock.
            Rectangle()
                .fill(SpoolPalette.labelInk.opacity(0.12))
                .frame(height: 1)
        }
    }

    private func swipeActions(for track: AppTrack) -> [RowSwipeAction] {
        if album.isPodcast {
            return album.podcast?.episodes.first { $0.id == track.id }.map(RowSwipeAction.download) ?? []
        }
        return RowSwipeAction.queue { onQueue([track], $0) }
    }

    /// An episode: its title, and the day it came out with how long it runs.
    private func episodeRow(_ episode: PodcastEpisode) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Marked if played before, or part way through.
            EpisodeTitle(episode.title, episode: episode)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(2)
            Text([episode.published.map(Self.episodeDate), episode.duration > 0 ? Self.runningTime(episode.duration) : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 12))
                .opacity(0.55)
        }
    }

    /// "30 Sep", or "30 Sep 2024" for an earlier year.
    nonisolated static func episodeDate(_ date: Date) -> String {
        let sameYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        return sameYear
            ? date.formatted(.dateTime.day().month(.abbreviated))
            : date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// "42 min", "1 hr 5 min".
    static func runningTime(_ duration: TimeInterval) -> String {
        Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    // MARK: - Hinge and Tray

    /// The case's spine, where the lid folds.
    private var hinge: some View {
        HStack(spacing: 12) {
            ForEach(0..<3) { _ in
                RoundedRectangle(cornerRadius: 3)
                    .fill(.white.opacity(0.35))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.white.opacity(0.5), lineWidth: 1))
                    .padding(.vertical, 2)
            }
        }
    }

    private func trayView(isOpen: Bool, tracks: [AppTrack]?) -> some View {
        PlasticPanel {
            GeometryReader { geometry in
                let size = geometry.size
                CassetteShell(
                    transport: CassetteShell.resting,
                    title: album.tapeTitle,
                    size: size,
                    labelArt: .album(album),
                    format: album.tapeFormat,
                    trackCount: album.tapeTrackCount,
                    blank: album.tapeBlank
                )
                .frame(width: size.width, height: size.height)
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(SpoolPlayerView.coordinateSpace))
                } action: { cassetteFrame = $0 }
                .shadow(color: .black.opacity(0.35), radius: 5, x: 0, y: 3)
                .contentShape(Rectangle())
                .onTapGesture {
                    // The whole tape, from the top.
                    if isOpen, let tracks, !tracks.isEmpty { onPick(tracks, 0, cassetteFrame) }
                }
                .accessibilityElement()
                .accessibilityLabel(album.tapeTitle)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(String(localized: "spool.carousel.insert"))
                .accessibilityIdentifier("spool.case.cassette")
            }
            .aspectRatio(CassetteView.aspectRatio, contentMode: .fit)
            .padding(.horizontal, Layout.trayInset.width)
            .padding(.vertical, Layout.trayInset.height)
        }
    }

    // MARK: - Gestures

    /// Dragging down from the top of the open lid folds it shut under the finger, as a
    /// record's sleeve closes; dragging back up opens it again. On release, a downward
    /// flick or a lid let go well on its way closes the case; anything else springs it
    /// back open.
    private func lidDrag(_ layout: Layout) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(SpoolPlayerView.coordinateSpace))
            .onChanged { value in
                if lidDragStart == nil {
                    guard progress >= 0.999, layout.grip.contains(value.startLocation),
                          value.translation.height > abs(value.translation.width) else { return }
                    lidDragStart = progress
                }
                guard let start = lidDragStart else { return }
                onScrub(min(1, max(0, start - value.translation.height / layout.lidTravel)))
            }
            .onEnded { value in
                guard lidDragStart != nil else { return }
                lidDragStart = nil
                let velocity = value.velocity.height
                let closes = velocity > 300 || (velocity > -300 && value.translation.height > 90)
                onScrubEnd(closes)
            }
    }

    // MARK: - Layout

    /// Where the open case's halves sit on screen.
    private struct Layout {
        static let margin: CGFloat = 16
        static let trayInset = CGSize(width: 22, height: 18)

        let tray: CGRect
        let lid: CGRect
        /// Where a drag can take hold of the open lid: its top edge and the header.
        var grip: CGRect { CGRect(x: lid.minX, y: lid.minY - 16, width: lid.width, height: 108) }
        /// Finger travel per unit of progress: the lid's top edge reaches the hinge, the
        /// lid standing upright, at progress 0.65, about where the finger has got to.
        var lidTravel: CGFloat { lid.height / 0.35 }

        init(size: CGSize, safeArea: EdgeInsets, bounds: CGRect? = nil) {
            let frame = bounds.map { $0.insetBy(dx: 4, dy: 4) }
                ?? CGRect(x: safeArea.leading + Self.margin, y: safeArea.top + 12,
                          width: size.width - safeArea.leading - safeArea.trailing - 2 * Self.margin,
                          height: size.height - safeArea.top - safeArea.bottom - 24)
            // The tray fits the cassette; the lid takes the rest, for the song list.
            let trayHeight = (frame.width - 2 * Self.trayInset.width) / CassetteView.aspectRatio
                + 2 * Self.trayInset.height
            tray = CGRect(x: frame.minX, y: frame.maxY - trayHeight, width: frame.width, height: trayHeight)
            lid = CGRect(x: frame.minX, y: frame.minY, width: frame.width,
                         height: max(trayHeight, tray.minY - CassetteCaseView.hingeGap - frame.minY))
        }
    }

    private func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * t,
               y: a.minY + (b.minY - a.minY) * t,
               width: a.width + (b.width - a.width) * t,
               height: a.height + (b.height - a.height) * t)
    }
}

/// Holding a song offers to queue it: next, or at the end. Holding a podcast episode,
/// which isn't queued, offers its download instead (Download, Cancel Download or Remove
/// Download), as the click wheel and the gatefold do. Shared by the Spool's cassette case
/// and the Gramophone's sleeve.
struct QueueMenu: ViewModifier {
    let isEnabled: Bool
    let track: AppTrack
    /// The episode the row is, when it is one.
    var episode: PodcastEpisode? = nil
    let onQueue: ([AppTrack], QueuePlacement) -> Void
    @ObservedObject private var downloads = PodcastDownloads.shared

    func body(content: Content) -> some View {
        if isEnabled {
            content.contextMenu {
                Button { onQueue([track], .next) } label: {
                    Label(String(localized: "queue.action.playNext"), systemImage: "text.insert")
                }
                Button { onQueue([track], .last) } label: {
                    Label(String(localized: "queue.action.addToQueue"), systemImage: "text.append")
                }
            }
        } else if let episode, episode.streamURL != nil {
            let action = downloads.actionTitle(for: episode.id)
            content
                .contextMenu {
                    Button { toggleDownload(episode) } label: {
                        Label(action.title, systemImage: action.symbol)
                    }
                }
                .accessibilityAction(named: action.title) { toggleDownload(episode) }
        } else {
            content
        }
    }

    private func toggleDownload(_ episode: PodcastEpisode) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        downloads.toggle(episode)
    }
}

/// A downloaded episode's mark, or how far its download has got; nothing otherwise.
struct EpisodeDownloadMark: View {
    let episodeID: String
    @ObservedObject private var downloads = PodcastDownloads.shared

    var body: some View {
        switch downloads.state(for: episodeID) {
        case .downloaded:
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 13))
                .opacity(0.6)
                .accessibilityLabel(String(localized: "spool.podcast.downloaded"))
        case .downloading(let progress):
            Text("\(Int(progress * 100))%")
                .font(.system(size: 11, design: .monospaced))
                .opacity(0.6)
        case nil:
            EmptyView()
        }
    }
}

/// Turns the lid about its hinge along its bottom edge. Flat, it applies no 3D effect at
/// all, so the open lid's scroll view draws as itself.
private struct LidSwing: ViewModifier {
    let degrees: Double

    func body(content: Content) -> some View {
        if abs(degrees) < 0.01 {
            content
        } else {
            content.rotation3DEffect(.degrees(degrees), axis: (x: 1, y: 0, z: 0),
                                     anchor: .bottom, perspective: 0.4)
        }
    }
}

// MARK: - Closed Case

/// A closed case seen from the front: the J-card's cover panel behind clear plastic, with
/// the hinge along the top. The rack draws its albums with this, and it is the lid's
/// outside as the case opens.
struct ClosedCaseFront: View {
    let album: AppAlbum

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let inset = w * 0.03
            ZStack(alignment: .topLeading) {
                Group {
                    if album.isMixtape {
                        handwrittenCard(w: w, h: h, inset: inset)
                    } else {
                        printedCard(w: w, h: h, inset: inset)
                    }
                }
                .frame(width: w - 2 * inset, height: h - 2 * inset, alignment: .topLeading)
                .offset(x: inset, y: inset)

                // The plastic over it, with the hinge knuckles along the top edge.
                RoundedRectangle(cornerRadius: w * 0.035)
                    .strokeBorder(.white.opacity(0.65), lineWidth: max(1.5, w * 0.006))
                RoundedRectangle(cornerRadius: w * 0.035)
                    .fill(LinearGradient(stops: [
                        .init(color: .white.opacity(0.18), location: 0),
                        .init(color: .white.opacity(0.04), location: 0.35),
                        .init(color: .white.opacity(0), location: 0.5),
                        .init(color: .white.opacity(0.1), location: 0.75),
                        .init(color: .white.opacity(0), location: 0.85),
                    ], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .allowsHitTesting(false)
                HStack(spacing: w * 0.05) {
                    ForEach(0..<3) { _ in
                        Capsule()
                            .fill(.white.opacity(0.4))
                            .frame(height: max(2, h * 0.025))
                    }
                }
                .padding(.horizontal, w * 0.18)
                .offset(y: max(1, h * 0.01))
            }
            .frame(width: w, height: h)
            .background(RoundedRectangle(cornerRadius: w * 0.035).fill(.white.opacity(0.1)))
        }
    }

    /// An album's J-card front: the cover on the left, the name printed beside it.
    private func printedCard(w: CGFloat, h: CGFloat, inset: CGFloat) -> some View {
        let artSide = h - 2 * inset - h * 0.08
        return HStack(alignment: .top, spacing: w * 0.04) {
            TapeArtwork(album: album, size: artSide.rounded())
                .frame(width: artSide, height: artSide)
                .clipShape(RoundedRectangle(cornerRadius: w * 0.012))
                .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
            VStack(alignment: .leading, spacing: h * 0.02) {
                Text(album.tapeTitle)
                    .font(.system(size: h * 0.1, weight: .bold, design: .serif))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if let byline = album.caseByline {
                    Text(byline)
                        .font(.system(size: h * 0.075))
                        .opacity(0.75)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                detail(h: h)
            }
            .foregroundStyle(.white)
            .padding(.vertical, h * 0.02)
            Spacer(minLength: 0)
        }
        .padding(h * 0.04)
        .background(
            LinearGradient(colors: [Color(white: 0.16), Color(white: 0.08)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: w * 0.015)
        )
    }

    /// A mixtape's J-card: plain card, the covers cut out and stuck on at an angle, and
    /// the name written beside them in pen.
    private func handwrittenCard(w: CGFloat, h: CGFloat, inset: CGFloat) -> some View {
        let artSide = (h - 2 * inset) * 0.78
        return HStack(alignment: .top, spacing: w * 0.05) {
            MixtapeArtwork(album: album, size: artSide.rounded())
                .frame(width: artSide, height: artSide)
                .clipped()
                // A white border, as if cut from a magazine and glued on.
                .padding(max(2, w * 0.008))
                .background(.white)
                .shadow(color: .black.opacity(0.3), radius: 1.5, x: 0, y: 1)
                .rotationEffect(.degrees(-3))
                .padding(.top, h * 0.03)
            VStack(alignment: .leading, spacing: h * 0.01) {
                Text(album.tapeTitle)
                    .font(.custom(SpoolPalette.handwriting, size: h * 0.12))
                    .foregroundStyle(SpoolPalette.pen)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .rotationEffect(.degrees(-1.5), anchor: .leading)
                if let byline = album.caseByline {
                    Text(byline)
                        .font(.custom(SpoolPalette.handwriting, size: h * 0.075))
                        .foregroundStyle(SpoolPalette.pen.opacity(0.8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                detail(h: h)
                    .foregroundStyle(SpoolPalette.labelInk)
            }
            .padding(.vertical, h * 0.03)
            Spacer(minLength: 0)
        }
        .padding(h * 0.05)
        .background(
            // Card stock, ruled faintly.
            RoundedRectangle(cornerRadius: w * 0.015)
                .fill(SpoolPalette.label)
                .overlay(alignment: .top) {
                    VStack(spacing: h * 0.14) {
                        ForEach(0..<6, id: \.self) { _ in
                            Rectangle().fill(SpoolPalette.mixtapeRule).frame(height: 1)
                        }
                    }
                    .padding(.top, h * 0.18)
                }
                .clipShape(RoundedRectangle(cornerRadius: w * 0.015))
        )
    }

    @ViewBuilder
    private func detail(h: CGFloat) -> some View {
        if let detail = album.tapeDetail {
            Text(detail.uppercased())
                .font(.system(size: h * 0.06, weight: .bold, design: .rounded))
                .tracking(1)
                .opacity(0.65)
        }
    }
}

extension AppAlbum {
    /// The line under the name on a case: the artist, or who made a mixtape.
    var caseByline: String? {
        if isPodcast {
            // When the newest episode came out, so a new one shows from the rack.
            return releaseDate.map {
                String(format: String(localized: "spool.podcast.latest"), CassetteCaseView.episodeDate($0))
            } ?? String(localized: "spool.podcast")
        }
        guard isMixtape else { return artistName }
        return artistName.isEmpty ? nil : String(format: String(localized: "spool.mixtape.madeBy"), artistName)
    }
}

// MARK: - Plastic

/// Half of an open case: clear plastic with a moulded rim, a sheen, and a glint across
/// it, over whatever it holds.
private struct PlasticPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CassetteCaseView.corner)
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                shape.fill(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0.14)],
                                          startPoint: .top, endPoint: .bottom))
                    .background(.ultraThinMaterial, in: shape)
            )
            .overlay(shape.strokeBorder(.white.opacity(0.7), lineWidth: 2))
            .overlay(
                RoundedRectangle(cornerRadius: CassetteCaseView.corner - 6)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                    .padding(6)
            )
            .overlay(
                LinearGradient(stops: [
                    .init(color: .white.opacity(0), location: 0.0),
                    .init(color: .white.opacity(0.16), location: 0.32),
                    .init(color: .white.opacity(0), location: 0.46),
                    .init(color: .white.opacity(0.08), location: 0.7),
                    .init(color: .white.opacity(0), location: 0.8),
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
                .clipShape(shape)
                .allowsHitTesting(false)
            )
            .shadow(color: .black.opacity(0.3), radius: 14, x: 0, y: 8)
    }
}
