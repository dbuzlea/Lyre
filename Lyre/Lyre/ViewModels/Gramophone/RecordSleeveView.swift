//
//  RecordSleeveView.swift
//  Lyre
//

import SwiftUI

// MARK: - Record Sleeve
//
// A record taken out of the crate and turned over: its sleeve comes forward with the
// record slid partway out of the top, and the back of the sleeve lists the songs, one
// per band. Choosing a song sends the record to the turntable and drops the needle on
// that song's band; Play (or Play Latest, for a show) drops it on the first. Holding a
// song offers to queue it, as everywhere else. Tapping outside, or the close button,
// puts the sleeve back.
//
// Holding the record on the turntable opens its sleeve the same way.
//
// On an iPhone Duo open in portrait the sleeve keeps to the half below the fold, where
// the covers are, with a smaller record, so the gramophone stays in view above it
// (LYRE-16). Tapping that upper half puts the sleeve back, as tapping outside does.

struct RecordSleeveView: View {
    let album: AppAlbum
    let loadTracks: () async -> [AppTrack]
    /// The tracks, and the one to start from.
    /// The songs, the one to start from, and whether the whole record was asked for
    /// (Play, Shuffle) rather than one song.
    let onPick: ([AppTrack], Int, Bool) -> Void
    let onQueue: ([AppTrack], QueuePlacement) -> Void
    let onClose: () -> Void
    /// The song playing, marked in the list.
    var playingID: String?
    /// iPhone Duo open in portrait: the height of the half below the fold, and the safe
    /// area under it. The sleeve keeps to that half. Nil elsewhere: the whole screen.
    var lowerHalfHeight: CGFloat?
    var bottomInset: CGFloat = 0

    @Environment(\.gramophoneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.windowSafeArea) private var safeArea
    @State private var tracks: [AppTrack]?
    @State private var shown = false

    private var kind: RecordKind { RecordKind(album) }

    /// The sleeve's widest, and the room the front takes, record and all. In the lower
    /// half the record stands no higher than its room, so it never crosses the fold.
    private var frontSide: CGFloat { lowerHalfHeight == nil ? 300 : 112 }
    private var frontHeight: CGFloat { lowerHalfHeight == nil ? 230 : 150 }

    var body: some View {
        ZStack(alignment: lowerHalfHeight == nil ? .center : .bottom) {
            backdrop

            VStack(spacing: 0) {
                sleeveFront
                    .zIndex(1)
                liner
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 20)
            .padding(.vertical, lowerHalfHeight == nil ? 24 : 12)
            // Centred between the side insets, so nothing's under the status bar and
            // camera down one edge (an iPhone Duo closed).
            .padding(.leading, safeArea.leading)
            .padding(.trailing, safeArea.trailing)
            .frame(height: lowerHalfHeight)
            .padding(.bottom, lowerHalfHeight == nil ? 0 : bottomInset)
            .scaleEffect(shown ? 1 : 0.85)
            .opacity(shown ? 1 : 0)
        }
        .task {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.85)) {
                shown = true
            }
            if tracks == nil, !album.preloadedTracks.isEmpty { tracks = album.tapeSongs(album.preloadedTracks) }
            let loaded = await loadTracks()
            if !loaded.isEmpty || tracks == nil { tracks = loaded }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gramophone.sleeve")
        .accessibilityAction(.escape, close)
    }

    /// The room dimmed behind the sleeve; tapping it puts the sleeve back. In the lower half,
    /// only that half is dimmed and the gramophone above stays as it is.
    @ViewBuilder
    private var backdrop: some View {
        if let lowerHalfHeight {
            VStack(spacing: 0) {
                Color.clear
                Color.black.opacity(shown ? 0.6 : 0)
                    .frame(height: lowerHalfHeight + bottomInset)
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: close)
            .accessibilityHidden(true)
        } else {
            Color.black.opacity(shown ? 0.6 : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
                .accessibilityHidden(true)
        }
    }

    private func close() {
        withAnimation(.easeIn(duration: 0.2)) { shown = false } completion: { onClose() }
    }

    // MARK: Front

    /// The sleeve, with the record standing out of its top.
    private var sleeveFront: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, frontSide)
            ZStack(alignment: .bottom) {
                RecordDisc(kind: kind, title: album.tapeTitle, label: .album(album),
                           grooves: tracks.map { GrooveMap(durations: $0.map(\.duration)) },
                           diameter: side * 0.92)
                    .offset(y: shown ? -side * 0.42 : 0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.15), value: shown)
                sleeve(side: side)
                    .frame(width: side, height: side * 0.62, alignment: .bottom)
                    .clipped()
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
        }
        .frame(height: frontHeight)
        .accessibilityHidden(true)
    }

    private func sleeve(side: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            switch kind {
            case .album:
                TapeArtwork(album: album, size: side.rounded())
                    .frame(width: side, height: side)
            case .homeRecording:
                Rectangle().fill(Color(red: 0.76, green: 0.62, blue: 0.42))
                    .overlay(alignment: .top) {
                        Text(album.tapeTitle)
                            .font(.custom(SpoolPalette.handwriting, size: 26))
                            .foregroundStyle(SpoolPalette.pen)
                            .padding(.top, side * 0.45)
                    }
            case .transcription:
                Rectangle().fill(Color(red: 0.12, green: 0.18, blue: 0.3))
                    .overlay(alignment: .top) {
                        Text(String(localized: "gramophone.record.broadcast").uppercased())
                            .font(.system(size: 14, weight: .black, design: .serif))
                            .tracking(3)
                            .foregroundStyle(theme.metalLight)
                            .padding(.top, side * 0.48)
                    }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
    }

    // MARK: Back

    /// The back of the sleeve: the name, Play, and the songs band by band.
    private var liner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.tapeTitle)
                        .font(album.isMixtape ? .custom(SpoolPalette.handwriting, size: 22)
                              : .system(size: 20, weight: .bold, design: .serif))
                        .foregroundStyle(album.isMixtape ? SpoolPalette.pen : SpoolPalette.labelInk)
                        .lineLimit(2)
                    if let byline = album.caseByline {
                        Text(byline).font(.system(size: 13, design: .serif)).italic().opacity(0.7)
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
                .accessibilityLabel(String(localized: "gramophone.sleeve.close"))
                .accessibilityIdentifier("gramophone.sleeve.close")
            }

            if let tracks, !tracks.isEmpty {
                HStack(spacing: 8) {
                    Button { pick(tracks, 0, whole: true) } label: {
                        Label(String(localized: album.isPodcast ? "spool.podcast.playLatest" : "detail.play"),
                              systemImage: "play.fill")
                            .foregroundStyle(theme.paper)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(SpoolPalette.labelInk, in: Capsule())
                    }
                    .accessibilityIdentifier("gramophone.sleeve.play")
                    if !album.isPodcast {
                        Button { pick(tracks.shuffled(), 0, whole: true) } label: {
                            Label(String(localized: "detail.shuffle"), systemImage: "shuffle")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .overlay(Capsule().strokeBorder(SpoolPalette.labelInk.opacity(0.6), lineWidth: 1.5))
                        }
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(.plain)
            }

            songList
        }
        .foregroundStyle(SpoolPalette.labelInk)
        .padding(14)
        .frame(maxHeight: 360, alignment: .top)
        .background(theme.paper, in: RoundedRectangle(cornerRadius: 6))
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
                        Text("\(index + 1)").font(.system(size: 12, weight: .semibold, design: .serif)).opacity(0.5)
                    }
                }
                .frame(width: 22, alignment: .trailing)
                VStack(alignment: .leading, spacing: 1) {
                    // An episode's marked if played before, or part way through.
                    EpisodeTitle(track.title, episode: episode)
                        .font(album.isMixtape ? .custom(SpoolPalette.handwriting, size: 15) : .system(size: 14, design: .serif))
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
        .accessibilityIdentifier("gramophone.sleeve.track.\(index)")
        .overlay(alignment: .bottom) {
            Rectangle().fill(SpoolPalette.labelInk.opacity(0.12)).frame(height: 1)
        }
    }

    private func pick(_ tracks: [AppTrack], _ index: Int, whole: Bool) {
        withAnimation(.easeIn(duration: 0.2)) { shown = false }
        onPick(tracks, index, whole)
    }
}
