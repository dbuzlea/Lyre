//
//  DiscBooklet.swift
//  Lyre
//

import SwiftUI

// MARK: - Booklet
//
// iPhone Duo, opened as a portable CD player (see DiscPlayerView's Discman layout): the
// booklet of the disc in the tray, tucked into the lid beside the disc, open at its
// track list. Tapping a song plays the disc from there; holding it, or swiping it right,
// queues it, as in every list.

struct DiscBooklet: View {
    let album: AppAlbum?
    let loadTracks: (AppAlbum) async -> [AppTrack]
    let playingID: String?
    let onPick: (AppAlbum, [AppTrack], Int) -> Void
    let onQueue: ([AppTrack], QueuePlacement) -> Void
    /// What to say with no disc in the tray.
    let emptyText: String

    @State private var tracks: [AppTrack]?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let album {
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.tapeTitle)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(2)
                    if let byline = album.caseByline ?? (album.artistName.isEmpty ? nil : album.artistName) {
                        Text(byline)
                            .font(.system(size: 12))
                            .opacity(0.6)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)
                Rectangle().fill(SpoolPalette.labelInk.opacity(0.18)).frame(height: 1).padding(.horizontal, 14)
                if let tracks {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            let episodes = album.podcast?.episodesNewestFirst
                            ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                                row(track, index: index, album: album, tracks: tracks,
                                    episode: episodes.flatMap { $0.indices.contains(index) ? $0[index] : nil })
                            }
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                Text(emptyText)
                    .font(.system(size: 14))
                    .multilineTextAlignment(.center)
                    .opacity(0.65)
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(SpoolPalette.labelInk)
        .background(SpoolPalette.label, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        // The booklet's fold, down its left edge.
        .overlay(alignment: .leading) {
            LinearGradient(colors: [.black.opacity(0.18), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 10)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10))
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        .task(id: album?.id) {
            tracks = nil
            guard let album else { return }
            let loaded = await loadTracks(album)
            tracks = loaded
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("disc.booklet")
    }

    private func row(_ track: AppTrack, index: Int, album: AppAlbum, tracks: [AppTrack],
                     episode: PodcastEpisode?) -> some View {
        Button { onPick(album, tracks, index) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Group {
                    if track.id == playingID {
                        Image(systemName: "speaker.wave.2.fill").font(.system(size: 10))
                    } else {
                        Text(String(format: "%02d", index + 1))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .opacity(0.5)
                    }
                }
                .frame(width: 22, alignment: .trailing)
                EpisodeTitle(track.title, episode: episode)
                    .font(.system(size: 14, weight: track.id == playingID ? .semibold : .regular))
                    .lineLimit(2)
                Spacer(minLength: 4)
                if track.duration > 0 {
                    Text(AppHelpers.formatTime(track.duration))
                        .font(.system(size: 11, design: .monospaced))
                        .opacity(0.5)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rowSwipeActions(album.isPodcast ? episode.map(RowSwipeAction.download) ?? []
                                         : RowSwipeAction.queue { onQueue([track], $0) },
                         captionColor: SpoolPalette.labelInk.opacity(0.65))
        .modifier(QueueMenu(isEnabled: !album.isPodcast, track: track, episode: episode,
                            onQueue: { tracks, placement in onQueue(tracks, placement) }))
        .accessibilityIdentifier("disc.booklet.track.\(index)")
    }
}
