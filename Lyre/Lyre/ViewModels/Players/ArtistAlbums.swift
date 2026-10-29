//
//  ArtistAlbums.swift
//  Lyre
//

import SwiftUI

// MARK: - Artist Albums
//
// An artist's case (ArtistShelf) lists their songs album by album. These are what lets
// it read as albums, the same in the Spool's cassette case, the Disc's jewel case and the
// Gramophone's sleeve:
//
//   ArtistAlbumStrip     their albums' covers in a row under Play and Shuffle; tapped,
//                        an album's own case opens in its place
//   ArtistAlbumHeading   over each album's songs, its cover, name and year
//
// Which album a run of songs is from is worked out once per artist's songs and kept
// (`sections`), not on each redraw.

@MainActor
enum ArtistAlbums {
    /// A run of songs off one album: where it starts in the list, its name, and the
    /// library's album, where there is one to open.
    struct Section: Identifiable {
        let start: Int
        let title: String
        let album: AppAlbum?

        var id: Int { start }
        var year: String? { album?.releaseDate.map(ArtistAlbums.year) }
    }

    /// The year an album came out, read in UTC as release dates are kept.
    nonisolated static func year(_ date: Date) -> String {
        var style = Date.FormatStyle().year()
        style.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return date.formatted(style)
    }

    private static var memo: [String: [Section]] = [:]

    /// The runs of songs from the same album, in the order listed.
    static func sections(of tracks: [AppTrack], for artist: AppAlbum, in albums: [AppAlbum]) -> [Section] {
        guard artist.isArtist, !tracks.isEmpty else { return [] }
        let key = "\(artist.id)#\(tracks.count)#\(tracks.first?.id ?? "")#\(albums.count)"
        if let known = memo[key] { return known }
        let byTitle = Dictionary(grouping: albums) { $0.tapeTitle.lowercased() }
        var sections: [Section] = []
        for (index, track) in tracks.enumerated() {
            let title = TapeFormat.displayTitle(track.albumTitle)
            if title == sections.last?.title { continue }
            let candidates = byTitle[title.lowercased()] ?? []
            let album = candidates.first { ArtistShelf.sameArtist(track.artistName, $0.artistName) } ?? candidates.first
            sections.append(Section(start: index, title: title.isEmpty ? String(localized: "artist.otherSongs") : title,
                                    album: album))
        }
        if memo.count > 200 { memo.removeAll() }
        memo[key] = sections
        return sections
    }

    /// Each album once, in the order listed, for the row of covers.
    static func albums(in sections: [Section]) -> [AppAlbum] {
        var seen = Set<String>()
        return sections.compactMap(\.album).filter { seen.insert($0.id).inserted }
    }
}

/// An artist's albums as a row of covers; tapping one opens that album.
struct ArtistAlbumStrip: View {
    let albums: [AppAlbum]
    let onOpen: (AppAlbum) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(albums) { album in
                    Button { onOpen(album) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            TapeArtwork(album: album, size: 64)
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Text(album.tapeTitle)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(2)
                            if let date = album.releaseDate {
                                Text(ArtistAlbums.year(date))
                                    .font(.system(size: 10))
                                    .opacity(0.6)
                            }
                        }
                        .frame(width: 64, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(album.tapeTitle)
                    .accessibilityHint(String(localized: "artist.openAlbum.hint"))
                    .accessibilityIdentifier("artist.album.\(album.id)")
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityIdentifier("artist.albums")
    }
}

/// Over an album's songs in an artist's case: its cover, name and year. Tapped, the
/// album opens.
struct ArtistAlbumHeading: View {
    let section: ArtistAlbums.Section
    let onOpen: (AppAlbum) -> Void

    var body: some View {
        Button { if let album = section.album { onOpen(album) } } label: {
            HStack(spacing: 8) {
                if let album = section.album {
                    TapeArtwork(album: album, size: 28)
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(section.title)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                    if let year = section.year {
                        Text(year).font(.system(size: 10)).opacity(0.55)
                    }
                }
                Spacer(minLength: 4)
                if section.album != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .opacity(0.4)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(section.album == nil)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("artist.heading.\(section.start)")
    }
}
