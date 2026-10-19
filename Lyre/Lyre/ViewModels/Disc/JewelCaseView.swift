//
//  JewelCaseView.swift
//  Lyre
//

import SwiftUI

// MARK: - Jewel Case
//
// A case taken off the shelf and opened: it comes forward closed, then the lid swings
// over on its hinge like a book's cover, the booklet in the lid on the left and the
// disc in its tray on the right. Under them is the back insert: the name, Play and
// Shuffle, and the track list.
//
// The lid opens the way the Classic player's Artwork Carousel opens a sleeve (see
// "Opening an album" in ArtworkCarouselView): one driven value, `fold`, from 0 (shut)
// to 1 (lying open), with everything worked out from it each frame through
// AnimatableFold, so the lid can turn back from wherever it has got to. The lid swings
// left through 180° on its hinge, with perspective; its faces swap at 90°, the inside
// pre-turned to read the right way round. A band of light crosses the lid as it turns,
// its shadow draws back off the tray, and the hinge darkens most when the lid stands
// upright. The case slides from centred, shut, to centred, open, as it goes. Dragging
// the case to the right closes the lid after the finger.
//
// Choosing a song lifts the disc out of the tray and onto the player's spindle to play
// from that song; Play, Shuffle, or tapping the disc take the whole disc. Holding a song
// offers to queue it instead, as everywhere else. Tapping outside, or the close button,
// shuts the case and puts it back.
//
// A playlist's case holds a burned CD-R and an insert written by hand; a show's holds an
// enhanced CD, its episodes newest first with their dates and downloads.

struct JewelCaseView: View {
    let album: AppAlbum
    let loadTracks: () async -> [AppTrack]
    /// The songs, the one to start from, whether the whole disc was asked for (Play,
    /// Shuffle, the disc itself) rather than one song, and the disc's frame in
    /// SpoolPlayerView's coordinate space, where it sets off for the spindle.
    let onPick: ([AppTrack], Int, Bool, CGRect) -> Void
    let onQueue: ([AppTrack], QueuePlacement) -> Void
    let onClose: () -> Void
    /// The song playing, marked in the list.
    var playingID: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tracks: [AppTrack]?
    @State private var shown = false
    /// How far the lid has swung open: 0 shut over the tray, 1 lying open on the left.
    @State private var fold: CGFloat = 0
    /// The back insert, which comes in as the lid lands.
    @State private var insertShown = false
    /// The fold when a drag on the case began.
    @State private var foldDragStart: CGFloat?
    /// Hidden once picked: the parent flies a copy to the spindle.
    @State private var isDiscTaken = false
    @State private var discFrame: CGRect = .zero

    private var kind: DiscKind { DiscKind(album) }

    var body: some View {
        ZStack {
            Color.black.opacity(shown ? 0.6 : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                openCase
                    .zIndex(1)
                insertPanel
                    .opacity(insertShown ? 1 : 0)
                    .offset(y: insertShown ? 0 : -20)
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .scaleEffect(shown ? 1 : 0.85)
            .opacity(shown ? 1 : 0)
        }
        .task {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.85)) {
                shown = true
            }
            open()
            if tracks == nil, !album.preloadedTracks.isEmpty { tracks = album.tapeSongs(album.preloadedTracks) }
            let loaded = await loadTracks()
            if !loaded.isEmpty || tracks == nil { tracks = loaded }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("disc.case")
        .accessibilityAction(.escape, close)
    }

    // MARK: Opening

    /// The Artwork Carousel's sleeve timing: how long the lid takes to swing, and how
    /// much it settles.
    private static let openResponse: Double = 0.68
    private static let openDamping: Double = 0.74

    private func open() {
        let spring: Animation = reduceMotion
            ? .easeOut(duration: 0.25)
            : .spring(response: Self.openResponse, dampingFraction: Self.openDamping)
        withAnimation(spring.delay(0.15)) { fold = 1 }
        withAnimation(.easeOut(duration: 0.3).delay(0.15 + Self.openResponse * 0.7)) { insertShown = true }
        guard !reduceMotion else { return }
        // The haptics are timed off the spring, as the carousel's are: a tick as the lid
        // passes upright, and a soft one as it lands.
        Task {
            try? await Task.sleep(for: .seconds(0.15 + Self.openResponse * 0.8))
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            try? await Task.sleep(for: .seconds(Self.openResponse * 0.43))
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }

    private func close() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeIn(duration: 0.15)) { insertShown = false }
        withAnimation(reduceMotion ? .easeIn(duration: 0.2) : .spring(response: 0.34, dampingFraction: 0.86)) {
            fold = 0
        } completion: {
            withAnimation(.easeIn(duration: 0.18)) { shown = false } completion: { onClose() }
        }
    }

    /// Dragging the case to the right turns the lid back after the finger; letting go
    /// shuts it or lets it fall open again.
    private func lidDrag(side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                // A song being swiped aside isn't the case being shut.
                if RowSwipeCoordinator.shared.isSwiping {
                    if let start = foldDragStart {
                        foldDragStart = nil
                        withAnimation(.spring(response: Self.openResponse, dampingFraction: Self.openDamping)) { fold = start }
                    }
                    return
                }
                guard foldDragStart != nil || abs(value.translation.width) > abs(value.translation.height) else { return }
                if foldDragStart == nil { foldDragStart = fold }
                let progress = (foldDragStart ?? 1) - value.translation.width / (side * 1.6)
                withTransaction(Transaction(animation: nil)) { fold = min(1, max(0, progress)) }
            }
            .onEnded { value in
                guard foldDragStart != nil else { return }
                foldDragStart = nil
                if value.predictedEndTranslation.width > side * 0.8 || fold < 0.5 {
                    close()
                } else {
                    withAnimation(.spring(response: Self.openResponse, dampingFraction: Self.openDamping)) { fold = 1 }
                }
            }
    }

    // MARK: Case

    /// The case: the tray on the right, and the lid hinged on its left edge, lying over
    /// the tray while shut and swung over to the left once open. Shut, the case is
    /// centred; it slides right by half a panel as it opens, so the open pair is centred.
    private var openCase: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width / 2, 190)
            AnimatableFold(progress: fold) { p in
                caseAssembly(side: side, p: p)
                    .offset(x: -side / 2 * (1 - p))
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(lidDrag(side: side))
        }
        .frame(height: 190)
    }

    private func caseAssembly(side: CGFloat, p: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: side, height: side)
            ZStack {
                tray(side: side)
                    .overlay { castShadow(p: p).clipShape(RoundedRectangle(cornerRadius: side * 0.02)) }
                    // Reachable only with the lid out of the way.
                    .allowsHitTesting(p > 0.98)

                if reduceMotion {
                    // No hinge: the lid fades from over the tray to its place on the left.
                    lidInside(side: side)
                        .offset(x: -side)
                        .opacity(Double(p))
                    lidOutside(side: side, p: p, showsSweep: false)
                        .opacity(Double(1 - p))
                        .allowsHitTesting(false)
                } else {
                    lid(side: side, p: p)
                }

                hingeShadow(p: p)
                    .frame(width: 44, height: side)
                    .offset(x: -side / 2)
                    .allowsHitTesting(false)
            }
            .frame(width: side, height: side)
        }
        .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
    }

    /// The lid on its hinge. SwiftUI draws both sides of a turned view, so its two faces
    /// swap at 90° and the inside is turned round beforehand to read the right way.
    /// Never hit-testable: turned, it still takes touches where it lay over the tray.
    private func lid(side: CGFloat, p: CGFloat) -> some View {
        ZStack {
            lidOutside(side: side, p: p, showsSweep: true)
                .opacity(p < 0.5 ? 1 : 0)
            lidInside(side: side)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(p >= 0.5 ? 1 : 0)
            // The lid's clear edge, seen only edge-on.
            HStack(spacing: 0) {
                Rectangle()
                    .fill(.white.opacity(0.7))
                    .frame(width: 3)
                Spacer(minLength: 0)
            }
            .opacity(Double(max(0, 1 - abs(p - 0.5) * 8)))
        }
        .frame(width: side, height: side)
        .rotation3DEffect(.degrees(-Double(p) * 180), axis: (x: 0, y: 1, z: 0),
                          anchor: .leading, perspective: 0.5)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The shut case's front: the booklet's cover behind the clear lid, and the light
    /// crossing it as it turns.
    private func lidOutside(side: CGFloat, p: CGFloat, showsSweep: Bool) -> some View {
        JewelCaseCard(album: album, size: CGSize(width: side, height: side))
            .overlay {
                if showsSweep { specularSweep(side: side, p: p) }
            }
            .clipShape(RoundedRectangle(cornerRadius: side * 0.02))
            .accessibilityHidden(true)
    }

    /// The open lid: the booklet held in it by its tabs, seen through the plastic.
    private func lidInside(side: CGFloat) -> some View {
        JewelCaseCard(album: album, size: CGSize(width: side, height: side), hingeEdge: .trailing)
            .overlay(alignment: .leading) {
                // The tabs that hold the booklet, along the edge away from the hinge.
                VStack(spacing: side * 0.5) {
                    ForEach(0..<2, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(.white.opacity(0.35))
                            .frame(width: side * 0.03, height: side * 0.14)
                    }
                }
                .padding(.leading, side * 0.015)
            }
            .clipShape(RoundedRectangle(cornerRadius: side * 0.02))
            .accessibilityHidden(true)
    }

    /// A band of light that crosses the lid as it turns, tied to the fold rather than
    /// the clock, so turning the lid back takes it back.
    private func specularSweep(side: CGFloat, p: CGFloat) -> some View {
        Rectangle()
            .fill(LinearGradient(stops: [.init(color: .white.opacity(0), location: 0.38),
                                         .init(color: .white.opacity(0.62), location: 0.5),
                                         .init(color: .white.opacity(0), location: 0.62)],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(width: side * 2.2, height: side * 2.2)
            .rotationEffect(.degrees(14))
            .offset(x: (-1.2 + 2.5 * p) * side)
            .blendMode(.screen)
            .opacity(Double((1 - abs(2 * p - 1)) * 0.9))
            .allowsHitTesting(false)
    }

    /// The lid's shadow lying across the tray, drawing back off it as the lid lifts.
    private func castShadow(p: CGFloat) -> some View {
        let lift = max(0, min(1, (p - 0.3) / 0.45))
        let edge = max(0.0, min(1.0, Double(1 - p)))
        return Rectangle()
            .fill(LinearGradient(stops: [.init(color: .black.opacity(0.88), location: 0),
                                         .init(color: .black.opacity(0.88), location: edge),
                                         .init(color: .black.opacity(0.1), location: min(1, edge + 0.22)),
                                         .init(color: .black.opacity(0.04), location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
            .opacity(Double(p > 0.001 ? 1 - 0.92 * lift : 0))
            .allowsHitTesting(false)
    }

    /// The hinge's shadow: deepest with the lid upright, and never quite gone.
    private func hingeShadow(p: CGFloat) -> some View {
        Rectangle()
            .fill(LinearGradient(stops: [.init(color: .black.opacity(0), location: 0),
                                         .init(color: .black.opacity(0.85), location: 0.48),
                                         .init(color: .black, location: 0.5),
                                         .init(color: .black.opacity(0.85), location: 0.52),
                                         .init(color: .black.opacity(0), location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
            .opacity(sin(Double.pi * Double(p)) * 0.42 + 0.09 * Double(p))
    }

    /// The tray: black plastic with the rosette the disc clips onto, and the disc.
    private func tray(side: CGFloat) -> some View {
        let disc = side * 0.9
        return ZStack {
            RoundedRectangle(cornerRadius: side * 0.02)
                .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.06)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: side * 0.02).strokeBorder(.white.opacity(0.3), lineWidth: 1))
            Circle()
                .strokeBorder(.white.opacity(0.08), lineWidth: side * 0.02)
                .frame(width: disc * 1.02, height: disc * 1.02)
            ForEach(0..<12, id: \.self) { tooth in
                Capsule()
                    .fill(Color(white: 0.25))
                    .frame(width: side * 0.012, height: side * 0.05)
                    .offset(y: -side * 0.055)
                    .rotationEffect(.degrees(Double(tooth) * 30))
            }
            Button {
                if let tracks, !tracks.isEmpty { pick(tracks, 0, whole: true) }
            } label: {
                DiscSpinner(isSpinning: false) {
                    CompactDisc(kind: kind, art: .album(album), title: album.tapeTitle, diameter: disc)
                }
                .overlay(DiscSheen(diameter: disc))
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .opacity(isDiscTaken ? 0 : 1)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(SpoolPlayerView.coordinateSpace))
            } action: { discFrame = $0 }
            .accessibilityLabel(String(localized: album.isPodcast ? "spool.podcast.playLatest" : "detail.play"))
            .accessibilityIdentifier("disc.case.disc")
        }
        .clipShape(RoundedRectangle(cornerRadius: side * 0.02))
        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
    }

    // MARK: Insert

    /// The back insert: the name, Play and Shuffle, and the songs.
    private var insertPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.tapeTitle)
                        .font(album.isMixtape ? .custom(SpoolPalette.handwriting, size: 22)
                              : .system(size: 20, weight: .bold))
                        .foregroundStyle(album.isMixtape ? SpoolPalette.pen : SpoolPalette.labelInk)
                        .lineLimit(2)
                    if let byline = album.caseByline {
                        Text(byline).font(.system(size: 13)).opacity(0.7)
                    }
                }
                Spacer(minLength: 8)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(SpoolPalette.labelInk.opacity(0.1), in: Circle())
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "disc.case.close"))
                .accessibilityIdentifier("disc.case.close")
            }

            if let tracks, !tracks.isEmpty {
                HStack(spacing: 8) {
                    Button { pick(tracks, 0, whole: true) } label: {
                        Label(String(localized: album.isPodcast ? "spool.podcast.playLatest" : "detail.play"),
                              systemImage: "play.fill")
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(SpoolPalette.labelInk, in: Capsule())
                    }
                    .accessibilityIdentifier("disc.case.play")
                    if !album.isPodcast {
                        Button { pick(tracks.shuffled(), 0, whole: true) } label: {
                            Label(String(localized: "detail.shuffle"), systemImage: "shuffle")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .overlay(Capsule().strokeBorder(SpoolPalette.labelInk.opacity(0.6), lineWidth: 1.5))
                        }
                        .accessibilityIdentifier("disc.case.shuffle")
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(.plain)
            }

            songList
        }
        .foregroundStyle(SpoolPalette.labelInk)
        .padding(14)
        .frame(maxHeight: 380, alignment: .top)
        .background(Color(red: 0.97, green: 0.97, blue: 0.95), in: RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
    }

    @ViewBuilder
    private var songList: some View {
        if let tracks {
            if tracks.isEmpty {
                Text(String(localized: "spool.jcard.empty"))
                    .font(.system(size: 14))
                    .opacity(0.6)
            } else {
                let episodes = album.podcast?.episodesNewestFirst
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                            row(track, index: index, of: tracks,
                                episode: episodes.flatMap { $0.indices.contains(index) ? $0[index] : nil })
                        }
                    }
                }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 80)
        }
    }

    private func row(_ track: AppTrack, index: Int, of tracks: [AppTrack], episode: PodcastEpisode?) -> some View {
        Button { pick(tracks, index, whole: false) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Group {
                    if track.id == playingID {
                        Image(systemName: "speaker.wave.2.fill").font(.system(size: 11))
                    } else {
                        Text(String(format: "%02d", index + 1))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .opacity(0.5)
                    }
                }
                .frame(width: 24, alignment: .trailing)
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(album.isMixtape ? .custom(SpoolPalette.handwriting, size: 15) : .system(size: 14))
                        .foregroundStyle(album.isMixtape ? SpoolPalette.pen : SpoolPalette.labelInk)
                        .lineLimit(2)
                    if album.isMixtape || album.isPodcast {
                        Text(album.isPodcast ? (episode?.published.map(CassetteCaseView.episodeDate) ?? "") : track.artistName)
                            .font(.system(size: 11)).opacity(0.6).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if album.isPodcast {
                    EpisodeDownloadMark(episodeID: track.id)
                }
                if track.duration > 0 {
                    Text(album.isPodcast ? CassetteCaseView.runningTime(track.duration) : AppHelpers.formatTime(track.duration))
                        .font(.system(size: 12, design: .monospaced))
                        .opacity(0.5)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Swiped right, a song offers Play Next and Add to Queue, as every list in Lyre
        // does; an episode, its download.
        .rowSwipeActions(album.isPodcast ? episode.map(RowSwipeAction.download) ?? []
                                         : RowSwipeAction.queue { onQueue([track], $0) },
                         captionColor: SpoolPalette.labelInk.opacity(0.65))
        // Holding a song offers to queue it; holding an episode, its download.
        .modifier(QueueMenu(isEnabled: !album.isPodcast, track: track, episode: episode, onQueue: onQueue))
        .accessibilityIdentifier("disc.case.track.\(index)")
        .overlay(alignment: .bottom) {
            Rectangle().fill(SpoolPalette.labelInk.opacity(0.12)).frame(height: 1)
        }
    }

    private func pick(_ tracks: [AppTrack], _ index: Int, whole: Bool) {
        let frame = discFrame
        isDiscTaken = true
        withAnimation(.easeIn(duration: 0.2)) { shown = false }
        onPick(tracks, index, whole, frame)
    }
}
