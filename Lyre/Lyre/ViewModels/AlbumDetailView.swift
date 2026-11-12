//
//  AlbumDetailView.swift
//  Lyre
//

import SwiftUI
import MusicKit
import MediaPlayer

// Track browser for a single album. Tracks are loaded asynchronously via
// MusicService.loadTracks on appear; a spinner shows in the meantime. Once loaded,
// the view displays a compact artwork + artist/count header followed by Play and
// Shuffle rows and a numbered track list. The selected row auto-scrolls to center as the scroll wheel moves.
//
// The `.onChange(of: selection)` guard clamps the cursor index after async load
// completes — without it, a pre-set selection could point out of bounds if the
// user scrolled before tracks arrived.
struct AlbumDetailView: View {
    let album: AppAlbum
    @ObservedObject var musicService: MusicService
    @Binding var selection: Int
    let themeSettings: ThemeSettings
    @State private var tracks: [AppTrack] = []
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Text(album.title)
                    .lyreFont(size: 12, weight: .semibold, maxScale: 1.5)
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                    .lineLimit(1)
                Spacer()
            }

            Divider().background(themeSettings.currentTheme.dividerColor)

            if isLoading {
                VStack {
                    Spacer()
                    ProgressView().scaleEffect(0.8).tint(themeSettings.currentTheme.screenTextColor)
                    Text("Loading tracks...")
                        .lyreFont(size: 10, maxScale: 1.5)
                        .foregroundStyle(themeSettings.currentTheme.screenSecondaryTextColor)
                    Spacer()
                }
            } else if tracks.isEmpty {
                VStack {
                    Spacer()
                    Text(String(localized: "empty.tracks"))
                        .lyreFont(size: 12, maxScale: 1.5)
                        .foregroundStyle(themeSettings.currentTheme.screenTextColor.opacity(0.5))
                    Spacer()
                }
            } else {
                // Album info header
                HStack(spacing: 8) {
                    artworkView
                    VStack(alignment: .leading, spacing: 2) {
                        Text(album.artistName)
                            .lyreFont(size: 10, weight: .medium, maxScale: 1.5)
                            .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                            .lineLimit(1)
                        Text("\(tracks.count) song\(tracks.count == 1 ? "" : "s")")
                            .lyreFont(size: 9, maxScale: 1.5)
                            .foregroundStyle(themeSettings.currentTheme.screenSecondaryTextColor)
                        if let released = album.releaseLine {
                            Text([released, album.genre].compactMap { $0 }.joined(separator: " · "))
                                .lyreFont(size: 9, maxScale: 1.5)
                                .foregroundStyle(themeSettings.currentTheme.screenSecondaryTextColor)
                                .lineLimit(1)
                                .accessibilityIdentifier("album.released")
                        }
                    }
                    Spacer()
                }
                .padding(.bottom, 4)

                Divider().background(themeSettings.currentTheme.dividerColor.opacity(0.5))

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            PlayShuffleRows(selection: selection, themeSettings: themeSettings)
                            ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                                // One layout for both states, with the highlight as a background:
                                // the text stays inside the row instead of overflowing an overlay,
                                // and the row isn't rebuilt (and cross-faded) as the cursor moves.
                                let isSelected = selection == index + PlayShuffleRows.count
                                HStack {
                                    Text("\(index + 1)")
                                        .lyreFont(size: 9, weight: isSelected ? .medium : .regular, maxScale: 1.5)
                                        .foregroundStyle(isSelected
                                            ? themeSettings.currentTheme.highlightTextColor.opacity(0.7)
                                            : themeSettings.currentTheme.screenTextColor.opacity(0.5))
                                        .frame(width: 20, alignment: .trailing)
                                    VStack(alignment: .leading, spacing: 0) {
                                        HStack(spacing: 4) {
                                            Text(track.title)
                                                .lyreFont(size: 11, weight: isSelected ? .medium : .regular, maxScale: 1.5)
                                                .lineLimit(1)
                                            if track.isExplicit { ExplicitTag().scaleEffect(0.85) }
                                        }
                                        .foregroundStyle(isSelected
                                            ? themeSettings.currentTheme.highlightTextColor
                                            : themeSettings.currentTheme.screenTextColor)
                                        Text(formatDuration(track.duration))
                                            .lyreFont(size: 9, maxScale: 1.5)
                                            .foregroundStyle(isSelected
                                                ? themeSettings.currentTheme.highlightTextColor.opacity(0.7)
                                                : themeSettings.currentTheme.screenSecondaryTextColor)
                                    }
                                    Spacer()
                                }
                                .padding(.leading, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: 32)
                                .background(isSelected ? themeSettings.currentTheme.highlightColor : Color.clear)
                                .selectionBarRefraction(when: isSelected)
                                .id(index + PlayShuffleRows.count)
                            }
                        }
                    }
                    .onAppear { proxy.scrollTo(selection, anchor: .center) }
                    .onChange(of: selection) { _, newValue in
                        withAnimation { proxy.scrollTo(newValue, anchor: .center) }
                    }
                }
            }
        }
        .task { await loadTracks() }
        .onChange(of: selection) { _, newValue in
            if !tracks.isEmpty {
                if newValue < 0 { selection = 0 }
                else if newValue >= tracks.count + PlayShuffleRows.count {
                    selection = tracks.count + PlayShuffleRows.count - 1
                }
            }
        }
    }

    /// The album, with its songs once they've loaded, for a mix whose collage needs them.
    private var coverAlbum: AppAlbum { Self.coverAlbum(album, tracks: tracks) }

    static func coverAlbum(_ album: AppAlbum, tracks: [AppTrack]) -> AppAlbum {
        guard var mixtape = album.mixtape, album.preloadedTracks.isEmpty, !tracks.isEmpty else { return album }
        mixtape.preloadedTracks = tracks
        return AppAlbum(mixtape: mixtape)
    }

    /// The cover, found wherever the album keeps one, as every other player finds it
    /// (LYRE-36): its own, a Discover playlist's, or a collage of its songs' covers for
    /// a mix, chart, genre or Replay, which have no cover of their own.
    private var artworkView: some View {
        LiquidCover(source: .album(coverAlbum))
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func loadTracks() async {
        let loaded = await musicService.loadTracks(for: album)
        await MainActor.run { tracks = loaded; isLoading = false }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)
    }
}
