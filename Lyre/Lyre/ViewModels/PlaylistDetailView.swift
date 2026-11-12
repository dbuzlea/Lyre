//
//  PlaylistDetailView.swift
//  Lyre
//

import SwiftUI
import MusicKit
import MediaPlayer

// Track browser for a single playlist. Mirrors AlbumDetailView in structure —
// artwork header, numbered track list with title and artist — but loads tracks
// via MusicService.loadTracks(for:playlist). The curator name (or "Playlist" as
// fallback) appears in the header in place of an artist name.
struct PlaylistDetailView: View {
    let playlist: AppPlaylist
    @ObservedObject var musicService: MusicService
    @Binding var selection: Int
    let themeSettings: ThemeSettings
    @State private var tracks: [AppTrack] = []
    @State private var isLoading = true

    /// A playlist Lyre made starts with an Edit Playlist row (LYRE-25), which opens the
    /// sheet every player edits a playlist in; Play, Shuffle and the songs follow it.
    static func editRows(for playlist: AppPlaylist) -> Int {
        PlaylistAdder.shared.canEdit(playlist) ? 1 : 0
    }
    private var editRows: Int { Self.editRows(for: playlist) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Text(playlist.name)
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
                HStack(spacing: 8) {
                    artworkView
                    VStack(alignment: .leading, spacing: 2) {
                        Text(playlist.curatorName ?? "Playlist")
                            .lyreFont(size: 10, weight: .medium, maxScale: 1.5)
                            .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                            .lineLimit(1)
                        Text("\(tracks.count) song\(tracks.count == 1 ? "" : "s")")
                            .lyreFont(size: 9, maxScale: 1.5)
                            .foregroundStyle(themeSettings.currentTheme.screenSecondaryTextColor)
                    }
                    Spacer()
                }
                .padding(.bottom, 4)

                Divider().background(themeSettings.currentTheme.dividerColor.opacity(0.5))

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            if editRows == 1 { editRow.id(0) }
                            PlayShuffleRows(selection: selection - editRows, themeSettings: themeSettings, rowsAbove: editRows)
                            ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                                // One layout for both states, with the highlight as a background:
                                // the text stays inside the row instead of overflowing an overlay,
                                // and the row isn't rebuilt (and cross-faded) as the cursor moves.
                                let isSelected = selection == index + PlayShuffleRows.count + editRows
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
                                        Text(track.artistName)
                                            .lyreFont(size: 9, maxScale: 1.5)
                                            .foregroundStyle(isSelected
                                                ? themeSettings.currentTheme.highlightTextColor.opacity(0.7)
                                                : themeSettings.currentTheme.screenSecondaryTextColor)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.leading, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: 32)
                                .background(isSelected ? themeSettings.currentTheme.highlightColor : Color.clear)
                                .selectionBarRefraction(when: isSelected)
                                .id(index + PlayShuffleRows.count + editRows)
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
        // An edit saved: the playlist's songs as they now are.
        .onChange(of: PlaylistEditCenter.shared.revision) {
            Task { await loadTracks() }
        }
        .onChange(of: selection) { _, newValue in
            if !tracks.isEmpty {
                let rows = tracks.count + PlayShuffleRows.count + editRows
                if newValue < 0 { selection = 0 }
                else if newValue >= rows { selection = rows - 1 }
            }
        }
    }

    private var editRow: some View {
        let isSelected = selection == 0
        return HStack(spacing: 6) {
            Image(systemName: "pencil")
                .font(.system(size: 10))
                .frame(width: 20, alignment: .trailing)
            Text(String(localized: "playlist.edit.action"))
                .lyreFont(size: 11, weight: isSelected ? .semibold : .medium, maxScale: 1.5)
                .lineLimit(1)
            Spacer()
        }
        .foregroundStyle(isSelected ? themeSettings.currentTheme.highlightTextColor : themeSettings.currentTheme.screenTextColor)
        .padding(.leading, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 32)
        .background(isSelected ? themeSettings.currentTheme.highlightColor : Color.clear)
        .selectionBarRefraction(when: isSelected)
        .accessibilityIdentifier("playlist.edit.row")
    }

    /// The playlist, with its songs once they've loaded, for the collage.
    private var coverPlaylist: AppPlaylist {
        guard playlist.preloadedTracks.isEmpty, !tracks.isEmpty else { return playlist }
        var copy = playlist
        copy.preloadedTracks = tracks
        return copy
    }

    /// The playlist's cover as every other player shows it (LYRE-36): a collage of its
    /// songs' covers, which a playlist without artwork of its own still has.
    private var artworkView: some View {
        LiquidCover(source: .album(AppAlbum(mixtape: coverPlaylist)))
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func loadTracks() async {
        let loaded = await musicService.loadTracks(for: playlist)
        await MainActor.run { tracks = loaded; isLoading = false }
    }
}
