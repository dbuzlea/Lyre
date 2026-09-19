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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Text(playlist.name)
                    .font(.system(size: 12, weight: .semibold))
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
                        .font(.system(size: 10))
                        .foregroundStyle(themeSettings.currentTheme.screenSecondaryTextColor)
                    Spacer()
                }
            } else if tracks.isEmpty {
                VStack {
                    Spacer()
                    Text(String(localized: "empty.tracks"))
                        .font(.system(size: 12))
                        .foregroundStyle(themeSettings.currentTheme.screenTextColor.opacity(0.5))
                    Spacer()
                }
            } else {
                HStack(spacing: 8) {
                    artworkView
                    VStack(alignment: .leading, spacing: 2) {
                        Text(playlist.curatorName ?? "Playlist")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                            .lineLimit(1)
                        Text("\(tracks.count) song\(tracks.count == 1 ? "" : "s")")
                            .font(.system(size: 9))
                            .foregroundStyle(themeSettings.currentTheme.screenSecondaryTextColor)
                    }
                    Spacer()
                }
                .padding(.bottom, 4)

                Divider().background(themeSettings.currentTheme.dividerColor.opacity(0.5))

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                                HStack {
                                    if selection == index {
                                        Rectangle()
                                            .fill(themeSettings.currentTheme.highlightColor)
                                            .overlay {
                                                HStack {
                                                    Text("\(index + 1)")
                                                        .font(.system(size: 9, weight: .medium))
                                                        .foregroundStyle(themeSettings.currentTheme.highlightTextColor.opacity(0.7))
                                                        .frame(width: 20, alignment: .trailing)
                                                    VStack(alignment: .leading, spacing: 0) {
                                                        Text(track.title)
                                                            .font(.system(size: 11, weight: .medium))
                                                            .foregroundStyle(themeSettings.currentTheme.highlightTextColor)
                                                            .lineLimit(1)
                                                        Text(track.artistName)
                                                            .font(.system(size: 9))
                                                            .foregroundStyle(themeSettings.currentTheme.highlightTextColor.opacity(0.7))
                                                            .lineLimit(1)
                                                    }
                                                    Spacer()
                                                }
                                                .padding(.leading, 6).padding(.vertical, 2)
                                            }
                                            .selectionBarRefraction()
                                    } else {
                                        HStack {
                                            Text("\(index + 1)")
                                                .font(.system(size: 9))
                                                .foregroundStyle(themeSettings.currentTheme.screenTextColor.opacity(0.5))
                                                .frame(width: 20, alignment: .trailing)
                                            VStack(alignment: .leading, spacing: 0) {
                                                Text(track.title)
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                                                    .lineLimit(1)
                                                Text(track.artistName)
                                                    .font(.system(size: 9))
                                                    .foregroundStyle(themeSettings.currentTheme.screenSecondaryTextColor)
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                        }
                                        .padding(.leading, 6).padding(.vertical, 2)
                                    }
                                }
                                .frame(height: 32).id(index)
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
                else if newValue >= tracks.count { selection = tracks.count - 1 }
            }
        }
    }

    @ViewBuilder
    private var artworkView: some View {
        if let artwork = playlist.musicKitPlaylist?.artwork {
            ArtworkImage(artwork, width: 50).cornerRadius(4)
        } else if let uiImage = playlist.mpArtwork?.image(at: CGSize(width: 50, height: 50)) {
            Image(uiImage: uiImage).resizable().frame(width: 50, height: 50).cornerRadius(4)
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(themeSettings.currentTheme.highlightColor.opacity(0.3))
                .frame(width: 50, height: 50)
                .overlay { Image(systemName: "music.note.list").font(.system(size: 20))
                    .foregroundStyle(themeSettings.currentTheme.highlightTextColor) }
        }
    }

    private func loadTracks() async {
        let loaded = await musicService.loadTracks(for: playlist)
        await MainActor.run { tracks = loaded; isLoading = false }
    }
}
