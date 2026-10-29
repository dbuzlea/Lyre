//
//  ArtistDetailView.swift
//  Lyre
//

import SwiftUI
import MusicKit

// Album browser for a single artist, under their photo (ArtistPhoto). Loads that
// artist's albums asynchronously on appear. Selecting an album navigates deeper to AlbumDetailView (via handleSelect
// in ScrollWheelView). Release year is shown as a subtitle for each album row when
// the MusicKit metadata includes it.
//
// Above the albums, what Apple Music knows of them, as the other players show it:
// Top Songs and their Latest Release (`extraRows`), each opening as an album's list
// does; songs the library hasn't stream.
struct ArtistDetailView: View {
    let artist: AppArtist
    @ObservedObject var musicService: MusicService
    @Binding var selection: Int
    let themeSettings: ThemeSettings
    @State private var albums: [AppAlbum] = []
    @State private var isLoading = true

    var body: some View {
        // Read here, not in the lazy list below, so the rows appear when Apple Music's
        // answer arrives (read only inside the list, it went unnoticed).
        let extras = Self.extraRows(for: artist.name)
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

            // Their photo beside their name, as a small player's screen has room for.
            HStack(spacing: 10) {
                ArtistPhoto(name: artist.name, fallback: albums.first, size: 46)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(format: String(localized: "artist.photo"), artist.name))
                    .accessibilityAddTraits(.isImage)
                    .accessibilityIdentifier("artist.photo")
                Text(artist.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
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
                if let biography = AppleMusicCatalog.shared.details(forArtist: artist.name)?.biography {
                    Text(biography)
                        .font(.system(size: 9))
                        .foregroundStyle(themeSettings.currentTheme.screenSecondaryTextColor)
                        .lineLimit(2)
                        .accessibilityIdentifier("artist.biography")
                }
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
                            ForEach(Array(extras.enumerated()), id: \.offset) { index, extra in
                                row(title: extra.title, subtitle: extra.subtitle, isSelected: selection == index)
                                    .frame(height: 32).id(index)
                                    .accessibilityIdentifier(extra.identifier)
                            }
                            ForEach(Array(albums.enumerated()), id: \.offset) { offset, album in
                                let index = extras.count + offset
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
        .task(id: artist.name) { await AppleMusicCatalog.shared.loadArtist(artist.name) }
        .onChange(of: selection) { _, newValue in
            let count = Self.extraRows(for: artist.name).count + albums.count
            if count > 0 {
                if newValue < 0 { selection = 0 }
                else if newValue >= count { selection = count - 1 }
            }
        }
    }

    /// A row of the artist's list: its name and, under it, what it holds.
    @ViewBuilder
    private func row(title: String, subtitle: String?, isSelected: Bool) -> some View {
        let theme = themeSettings.currentTheme
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? theme.highlightTextColor : theme.screenTextColor)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(isSelected ? theme.highlightTextColor.opacity(0.7) : theme.screenSecondaryTextColor)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(isSelected ? theme.highlightTextColor : theme.screenSecondaryTextColor)
                .padding(.trailing, 6)
        }
        .padding(.leading, 6).padding(.vertical, 2)
        .frame(maxHeight: .infinity)
        .background { if isSelected { Rectangle().fill(theme.highlightColor).selectionBarRefraction() } }
    }

    /// Apple Music's rows above the albums, when it knows them: Top Songs, Latest Release.
    enum ExtraRow {
        case topSongs(Int)
        case latestRelease(Album)

        var title: String {
            switch self {
            case .topSongs: String(localized: "catalog.topSongs")
            case .latestRelease: String(localized: "catalog.latestRelease")
            }
        }
        var subtitle: String? {
            switch self {
            case .topSongs(let count): String(format: String(localized: "count.songs"), count)
            case .latestRelease(let album): album.title
            }
        }
        var identifier: String {
            switch self {
            case .topSongs: "artist.topSongs"
            case .latestRelease: "artist.latestRelease"
            }
        }
    }

    static func extraRows(for name: String) -> [ExtraRow] {
        guard let details = AppleMusicCatalog.shared.details(forArtist: name) else { return [] }
        var rows: [ExtraRow] = []
        if !details.topSongs.isEmpty { rows.append(.topSongs(details.topSongs.count)) }
        if let latest = details.latestRelease { rows.append(.latestRelease(latest)) }
        return rows
    }

    /// What a row opens, as an album's list: the top songs (the library's copies where
    /// it has them, else streamed), or the latest release (the library's, else Apple
    /// Music's).
    static func album(for row: ExtraRow, artist: String, in musicService: MusicService) -> AppAlbum? {
        switch row {
        case .topSongs:
            let songs = AppleMusicCatalog.shared.details(forArtist: artist)?.topSongs ?? []
            let tracks = songs.map { song in
                AppleMusicCatalog.librarySong(title: song.title, artist: song.artistName, duration: song.duration,
                                              explicit: song.contentRating.map { $0 == .explicit }, in: musicService)
                    ?? AppTrack(from: song, catalog: true)
            }
            return AppAlbum(id: "topSongs:\(artist)", title: String(localized: "catalog.topSongs"),
                            artistName: artist, preloadedTracks: tracks)
        case .latestRelease(let latest):
            return AppleMusicCatalog.libraryAlbum(title: latest.title, artist: latest.artistName, in: musicService.albums)
                ?? AppAlbum(from: latest, catalog: true)
        }
    }

    private func loadAlbums() async {
        let loaded = await musicService.loadAlbums(for: artist)
        await MainActor.run { albums = loaded; isLoading = false }
    }
}
