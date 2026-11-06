//
//  ArtistCatalogSections.swift
//  Lyre
//

import SwiftUI
import MusicKit

// MARK: - Artist Catalogue Sections
//
// What Apple Music knows about an artist (AppleMusicCatalog), for the Spool's, Disc's
// and Gramophone's artist cases, as Liquid's artist page has it:
//
//   ArtistCatalogHeader   above their songs: their biography (a few lines, tapped for
//                         all of it), Top Songs and Latest Release
//   ArtistCatalogFooter   below them: artists like them
//
// A top song plays from the library if it's there and streams if not, with the rest
// of the top songs after it. The latest release and a similar artist open in the case
// when the library has them (an album's case, an artist's case); otherwise the latest
// release opens in Album Info, which can stream it, and an artist in Apple Music.
// Each part shows only once there's something in it, so without Apple Music access
// the case is as it was. Drawn in the case's own ink.

struct ArtistCatalogHeader: View {
    let name: String
    @ObservedObject var musicService: MusicService
    /// Plays these songs from this one.
    let onPlay: ([AppTrack], Int) -> Void
    /// Opens a case of the library's: an album, or an artist.
    let onOpen: (AppAlbum) -> Void
    @State private var showsAllNotes = false

    private var details: AppleMusicCatalog.ArtistDetails? { AppleMusicCatalog.shared.details(forArtist: name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let biography = details?.biography {
                Button { withAnimation(.easeInOut(duration: 0.2)) { showsAllNotes.toggle() } } label: {
                    Text(biography)
                        .font(.system(size: 13))
                        .lineLimit(showsAllNotes ? nil : 3)
                        .multilineTextAlignment(.leading)
                        .opacity(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("artist.biography")
            }
            if let songs = details?.topSongs, !songs.isEmpty {
                ArtistSectionTitle(text: String(localized: "catalog.topSongs"))
                let tracks = songs.prefix(5).map(track)
                ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                    Button { onPlay(Array(tracks), index) } label: {
                        HStack(spacing: 8) {
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .opacity(0.5)
                                .frame(width: 18, alignment: .trailing)
                            if let art = songs[index].artwork {
                                ArtworkImage(art, width: 30, height: 30)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                            Text(track.title).font(.system(size: 14)).lineLimit(1)
                            if track.isExplicit { ExplicitTag() }
                            Spacer(minLength: 4)
                            // Streamed from Apple Music, the library hasn't it.
                            if track.isStreamOnly {
                                Image(systemName: "cloud")
                                    .font(.system(size: 11))
                                    .opacity(0.45)
                                    .accessibilityLabel(String(localized: "catalog.notInLibrary"))
                            }
                        }
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("artist.topSong.\(index)")
                }
            }
            if let latest = details?.latestRelease {
                ArtistSectionTitle(text: String(localized: "catalog.latestRelease"))
                Button { open(latest) } label: {
                    HStack(spacing: 10) {
                        Group {
                            if let art = latest.artwork { ArtworkImage(art, width: 52, height: 52) }
                            else { Color.secondary.opacity(0.2) }
                        }
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(latest.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                            if let date = latest.releaseDate {
                                Text(AppAlbum.releaseText(date)).font(.system(size: 11)).opacity(0.6)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("artist.latestRelease")
            }
        }
        .padding(.bottom, details == nil ? 0 : 6)
        .task(id: name) { await AppleMusicCatalog.shared.loadArtist(name) }
    }

    /// A catalogue song as a track: the library's copy, else streamed.
    private func track(_ song: Song) -> AppTrack {
        AppleMusicCatalog.librarySong(title: song.title, artist: song.artistName, duration: song.duration,
                                      explicit: song.contentRating.map { $0 == .explicit }, in: musicService)
            ?? AppTrack(from: song, catalog: true)
    }

    private func open(_ album: Album) {
        if let mine = AppleMusicCatalog.libraryAlbum(title: album.title, artist: album.artistName, in: musicService.albums) {
            onOpen(mine)
        } else {
            AlbumInfoCenter.shared.show(AppAlbum(from: album, catalog: true))
        }
    }
}

struct ArtistCatalogFooter: View {
    let name: String
    @ObservedObject var musicService: MusicService
    let onOpen: (AppAlbum) -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let artists = AppleMusicCatalog.shared.details(forArtist: name)?.similarArtists, !artists.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ArtistSectionTitle(text: String(localized: "catalog.similarArtists"))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(artists) { artist in
                            Button { open(artist) } label: {
                                VStack(spacing: 4) {
                                    Group {
                                        if let art = artist.artwork { ArtworkImage(art, width: 64, height: 64) }
                                        else { Color.secondary.opacity(0.2) }
                                    }
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: ArtistPhoto.cornerRadius(for: 64)))
                                    Text(artist.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .frame(width: 70)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.top, 14)
            .accessibilityIdentifier("artist.similar")
        }
    }

    /// One the shelf has opens their case; one it hasn't, Apple Music.
    private func open(_ artist: Artist) {
        UsageStats.shared.used(.similarArtist)
        let key = artist.name.lowercased()
        if let mine = musicService.shelfArtists.first(where: { $0.title.lowercased() == key }) {
            onOpen(mine)
        } else if let url = artist.url {
            openURL(url)
        }
    }
}

private struct ArtistSectionTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercasedKeepingAppleMusic)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .tracking(0.6)
            .opacity(0.6)
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The "E" an explicit song is marked with, drawn in whatever ink it's on.
struct ExplicitTag: View {
    var body: some View {
        Text("E")
            .font(.system(size: 9, weight: .bold))
            .frame(width: 13, height: 13)
            .overlay(RoundedRectangle(cornerRadius: 2.5).strokeBorder(lineWidth: 1))
            .opacity(0.6)
            .accessibilityLabel(String(localized: "catalog.explicit"))
    }
}
