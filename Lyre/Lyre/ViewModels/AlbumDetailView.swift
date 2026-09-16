//
//  AlbumDetailView.swift
//  Lyre
//

import SwiftUI
import MusicKit

// Track browser for a single album. Tracks are loaded asynchronously via
// MusicService.loadTracks on appear; a spinner shows in the meantime. Once loaded,
// the view displays a compact artwork + artist/count header followed by a numbered
// track list. The selected row auto-scrolls to center as the scroll wheel moves.
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
                // Album info header
                HStack(spacing: 8) {
                    artworkView
                    VStack(alignment: .leading, spacing: 2) {
                        Text(album.artistName)
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
                                                        Text(formatDuration(track.duration))
                                                            .font(.system(size: 9))
                                                            .foregroundStyle(themeSettings.currentTheme.highlightTextColor.opacity(0.7))
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
                                                Text(formatDuration(track.duration))
                                                    .font(.system(size: 9))
                                                    .foregroundStyle(themeSettings.currentTheme.screenSecondaryTextColor)
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
        if let mkAlbum = album.musicKitAlbum, let artwork = mkAlbum.artwork {
            ArtworkImage(artwork, width: 50).cornerRadius(4)
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(themeSettings.currentTheme.screenTextColor.opacity(0.1))
                .frame(width: 50, height: 50)
                .overlay { Image(systemName: "music.note").font(.system(size: 20))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor.opacity(0.3)) }
        }
    }

    private func loadTracks() async {
        let loaded = await musicService.loadTracks(for: album)
        await MainActor.run { tracks = loaded; isLoading = false }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)
    }
}
