//
//  ArtistDetailView.swift
//  Lyre
//

import SwiftUI

// Album browser for a single artist. Loads that artist's albums asynchronously on
// appear. Selecting an album navigates deeper to AlbumDetailView (via handleSelect
// in ScrollWheelView). Release year is shown as a subtitle for each album row when
// the MusicKit metadata includes it.
struct ArtistDetailView: View {
    let artist: AppArtist
    @ObservedObject var musicService: MusicService
    @Binding var selection: Int
    let themeSettings: ThemeSettings
    @State private var albums: [AppAlbum] = []
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Text(artist.name)
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
                    Text("Loading albums...")
                        .font(.system(size: 10))
                        .foregroundStyle(themeSettings.currentTheme.screenSecondaryTextColor)
                    Spacer()
                }
            } else if albums.isEmpty {
                VStack {
                    Spacer()
                    Text(String(localized: "empty.albumsAvailable"))
                        .font(.system(size: 12))
                        .foregroundStyle(themeSettings.currentTheme.screenTextColor.opacity(0.5))
                    Spacer()
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Albums")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                    Text("\(albums.count) album\(albums.count == 1 ? "" : "s")")
                        .font(.system(size: 9))
                        .foregroundStyle(themeSettings.currentTheme.screenSecondaryTextColor)
                }
                .padding(.bottom, 4)

                Divider().background(themeSettings.currentTheme.dividerColor.opacity(0.5))

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(albums.enumerated()), id: \.offset) { index, album in
                                HStack {
                                    if selection == index {
                                        Rectangle()
                                            .fill(themeSettings.currentTheme.highlightColor)
                                            .overlay {
                                                HStack {
                                                    VStack(alignment: .leading, spacing: 0) {
                                                        Text(album.title)
                                                            .font(.system(size: 11, weight: .medium))
                                                            .foregroundStyle(themeSettings.currentTheme.highlightTextColor)
                                                            .lineLimit(1)
                                                        if let year = album.releaseDate?.formatted(.dateTime.year()) {
                                                            Text(year)
                                                                .font(.system(size: 9))
                                                                .foregroundStyle(themeSettings.currentTheme.highlightTextColor.opacity(0.7))
                                                        }
                                                    }
                                                    Spacer()
                                                }
                                                .padding(.leading, 6).padding(.vertical, 2)
                                            }
                                            .selectionBarRefraction()
                                    } else {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 0) {
                                                Text(album.title)
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                                                    .lineLimit(1)
                                                if let year = album.releaseDate?.formatted(.dateTime.year()) {
                                                    Text(year)
                                                        .font(.system(size: 9))
                                                        .foregroundStyle(themeSettings.currentTheme.screenSecondaryTextColor)
                                                }
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
        .task { await loadAlbums() }
        .onChange(of: selection) { _, newValue in
            if !albums.isEmpty {
                if newValue < 0 { selection = 0 }
                else if newValue >= albums.count { selection = albums.count - 1 }
            }
        }
    }

    private func loadAlbums() async {
        let loaded = await musicService.loadAlbums(for: artist)
        await MainActor.run { albums = loaded; isLoading = false }
    }
}
