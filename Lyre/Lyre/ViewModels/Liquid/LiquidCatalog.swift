//
//  LiquidCatalog.swift
//  Lyre
//

import SwiftUI
import MusicKit

// MARK: - Liquid Catalogue
//
// What Apple Music's catalogue adds to Liquid's pages (see AppleMusicCatalog):
//
//   an artist's page   their biography, top songs and latest release above their albums,
//                      and artists like them below (LiquidArtistIntro, LiquidSimilarArtists)
//   an album's page    the audio it comes in (Dolby Atmos, Lossless) and an "E" on explicit
//                      songs, then Apple's write-up and the record label (AudioVariantBadges,
//                      ExplicitBadge, LiquidAlbumCredits)
//   search             the charts, while nothing's typed (LiquidCharts), and what
//                      Apple Music has for what is (LiquidCatalogSearch)
//
// A catalogue song plays from the library if it's there and streams if not, with a
// subscription; without one it's offered to be added (`LiquidNavigator.catalogSong`).
// A catalogue album opens its page if the library has it, and otherwise is offered to
// be played or added (`catalogAlbum`). Each part shows only once there's something in
// it, so without Apple Music access nothing appears.

/// The "E" Apple Music marks explicit songs with.
struct ExplicitBadge: View {
    var body: some View {
        Text("E")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.black.opacity(0.8))
            .frame(width: 15, height: 15)
            .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            .accessibilityLabel(String(localized: "catalog.explicit"))
    }
}

/// Dolby Atmos, Hi-Res Lossless or Lossless, as capsules.
struct AudioVariantBadges: View {
    let variants: [AudioVariant]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(variants, id: \.self) { variant in
                Label(Self.name(of: variant), systemImage: Self.symbol(of: variant))
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.14), in: Capsule())
            }
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("liquid.album.variants")
    }

    static func name(of variant: AudioVariant) -> String {
        switch variant {
        case .dolbyAtmos:             String(localized: "catalog.variant.atmos")
        case .highResolutionLossless: String(localized: "catalog.variant.hiRes")
        case .lossless:               String(localized: "catalog.variant.lossless")
        default:                      ""
        }
    }

    static func symbol(of variant: AudioVariant) -> String {
        variant == .dolbyAtmos ? "dot.radiowaves.left.and.right" : "waveform"
    }
}

/// A write-up, a few lines until tapped.
private struct ExpandableText: View {
    let text: String
    var lines = 4
    @State private var isExpanded = false

    var body: some View {
        Button { withAnimation(.easeInOut(duration: 0.25)) { isExpanded.toggle() } } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(isExpanded ? nil : lines)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !isExpanded {
                    Text(String(localized: "catalog.more"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text.lowercased())
            .font(.system(size: 24, weight: .medium))
            .tracking(-0.6)
            .foregroundStyle(.white)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A catalogue song as a row: its cover, name and artist, a tick when the library has
/// it (else a plus: it can be added), and an "E" when explicit. `rank` numbers a chart.
/// Tapped, it plays from there through `list` (named `listName`); held, it offers Play
/// Next, Add to Queue and Add to Playlist.
struct LiquidCatalogSongRow: View {
    @Environment(\.liquidNavigator) private var navigator
    let song: Song
    var rank: Int?
    var list: [Song] = []
    var listName = ""

    var body: some View {
        Button { navigator.catalogSong(song, list, listName.isEmpty ? song.title : listName) } label: {
            HStack(spacing: 12) {
                if let rank {
                    Text("\(rank)")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 26, alignment: .trailing)
                }
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(song.title).font(.system(size: 16)).lineLimit(1)
                        if song.contentRating == .explicit { ExplicitBadge() }
                    }
                    Text(song.artistName).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                Spacer(minLength: 6)
                let isMine = navigator.librarySong(song) != nil
                Image(systemName: isMine ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(isMine ? 0.5 : 0.8))
                    .accessibilityLabel(String(localized: isMine ? "catalog.inLibrary" : "catalog.notInLibrary"))
            }
            .foregroundStyle(.white)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("liquid.catalog.song")
        .contextMenu {
            Button { navigator.queue([navigator.catalogTrack(song)], .next, song.title) } label: {
                Label(String(localized: "queue.action.playNext"), systemImage: "text.insert")
            }
            Button { navigator.queue([navigator.catalogTrack(song)], .last, song.title) } label: {
                Label(String(localized: "queue.action.addToQueue"), systemImage: "text.append")
            }
            Button { PlaylistAdder.shared.offer(.song(song)) } label: {
                Label(String(localized: "playlist.add.action"), systemImage: "music.note.list")
            }
        }
    }

    @ViewBuilder private var artwork: some View {
        if let art = song.artwork {
            ArtworkImage(art, width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.1)).frame(width: 48, height: 48)
        }
    }
}

/// A catalogue album as a cover with its name under it.
struct LiquidCatalogAlbumTile: View {
    @Environment(\.liquidNavigator) private var navigator
    let album: Album
    var side: CGFloat = 140

    var body: some View {
        Button { navigator.catalogAlbum(album) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if let art = album.artwork {
                        ArtworkImage(art, width: side, height: side)
                    } else {
                        Color.white.opacity(0.1)
                    }
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(album.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                Text(album.artistName).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            .frame(width: side, alignment: .leading)
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

// MARK: Artist

/// Above an artist's albums: their biography, top songs and latest release.
struct LiquidArtistIntro: View {
    let name: String
    @State private var showsAll = false

    private var details: AppleMusicCatalog.ArtistDetails? { AppleMusicCatalog.shared.details(forArtist: name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let biography = details?.biography {
                ExpandableText(text: biography)
                    .accessibilityIdentifier("liquid.artist.biography")
            }
            if let songs = details?.topSongs, !songs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    SectionTitle(text: String(localized: "catalog.topSongs"))
                    ForEach(Array(songs.prefix(showsAll ? 10 : 5).enumerated()), id: \.element.id) { index, song in
                        LiquidCatalogSongRow(song: song, rank: index + 1, list: songs,
                                             listName: String(localized: "catalog.topSongs"))
                    }
                    if songs.count > 5 {
                        Button(String(localized: showsAll ? "catalog.showFewer" : "catalog.showAll")) {
                            withAnimation(.easeInOut(duration: 0.25)) { showsAll.toggle() }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.top, 4)
                    }
                }
                .accessibilityIdentifier("liquid.artist.topSongs")
            }
            if let latest = details?.latestRelease {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(text: String(localized: "catalog.latestRelease"))
                    LiquidCatalogAlbumTile(album: latest, side: 160)
                }
            }
            if details?.topSongs.isEmpty == false || details?.latestRelease != nil {
                SectionTitle(text: String(localized: "liquid.menu.albums"))
            }
        }
        .task(id: name) { await AppleMusicCatalog.shared.loadArtist(name) }
    }
}

/// Below an artist's albums: artists like them, as rounded-square photos.
struct LiquidSimilarArtists: View {
    let name: String

    var body: some View {
        if let artists = AppleMusicCatalog.shared.details(forArtist: name)?.similarArtists, !artists.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: String(localized: "catalog.similarArtists"))
                LiquidCatalogArtistStrip(artists: artists)
            }
            .accessibilityIdentifier("liquid.artist.similar")
        }
    }
}

/// Catalogue artists in a row, as rounded-square photos with their names. One the
/// library has opens their page; one it hasn't, Apple Music.
struct LiquidCatalogArtistStrip: View {
    @Environment(\.liquidNavigator) private var navigator
    @Environment(\.openURL) private var openURL
    let artists: [Artist]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(artists) { artist in
                    Button {
                        if navigator.hasArtist(artist.name) {
                            navigator.push(.artist(artist.name))
                        } else if let url = artist.url {
                            openURL(url)
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Group {
                                if let art = artist.artwork {
                                    ArtworkImage(art, width: 96, height: 96)
                                } else {
                                    Color.white.opacity(0.1)
                                }
                            }
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: ArtistPhoto.cornerRadius(for: 96), style: .continuous))
                            Text(artist.name)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(width: 100)
                        }
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: Album

/// Under an album's songs: Apple's write-up, then the record label and copyright.
struct LiquidAlbumCredits: View {
    let album: AppAlbum

    var body: some View {
        let details = AppleMusicCatalog.shared.details(forAlbum: album)
        VStack(alignment: .leading, spacing: 14) {
            if let notes = details?.notes {
                ExpandableText(text: notes, lines: 5)
                    .accessibilityIdentifier("liquid.album.notes")
            }
            let credits = [details?.recordLabel, details?.copyright].compactMap { $0 }.filter { !$0.isEmpty }
            if !credits.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(credits, id: \.self) { line in
                        Text(line).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("liquid.album.credits")
            }
        }
    }
}

// MARK: Charts

/// The charts, for the search page while nothing's typed: the top songs, then albums.
struct LiquidCharts: View {
    var body: some View {
        let charts = AppleMusicCatalog.shared.charts
        VStack(alignment: .leading, spacing: 22) {
            if let songs = charts?.songs, !songs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    SectionTitle(text: String(localized: "catalog.charts.songs"))
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        LiquidCatalogSongRow(song: song, rank: index + 1, list: songs,
                                             listName: String(localized: "catalog.charts.songs"))
                    }
                }
                .accessibilityIdentifier("liquid.charts.songs")
            }
            if let albums = charts?.albums, !albums.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: String(localized: "catalog.charts.albums"))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(albums) { LiquidCatalogAlbumTile(album: $0) }
                        }
                    }
                }
            }
        }
        .task { await AppleMusicCatalog.shared.loadCharts() }
    }
}

// MARK: Search

/// Under the library's matches: what Apple Music has for the same words. Songs, then
/// albums and artists in rows.
struct LiquidCatalogSearch: View {
    let results: AppleMusicCatalog.SearchResults

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionTitle(text: String(localized: "catalog.search.title"))
                .accessibilityIdentifier("liquid.search.catalog")
            if !results.songs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(results.songs) { LiquidCatalogSongRow(song: $0, list: results.songs) }
                }
            }
            if !results.albums.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "liquid.menu.albums").lowercased())
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(results.albums) { LiquidCatalogAlbumTile(album: $0) }
                        }
                    }
                }
            }
            if !results.artists.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "liquid.menu.artists").lowercased())
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                    LiquidCatalogArtistStrip(artists: results.artists)
                }
            }
        }
    }
}
