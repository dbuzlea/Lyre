//
//  ArtistShelf.swift
//  Lyre
//

import Foundation
import MusicKit
import MediaPlayer

// MARK: - Artist Shelf
//
// The Spool's, Disc's and Gramophone's Artists shelf: each artist as one case, holding
// their songs, newest album first and in track order, with their photo on the front
// (TapeArtwork). Opened, a case lists the songs as an album's does; held, it queues them.
//
// A song is filed under its album's artist, so a song with a guest ("Artist & Guest")
// stays with the album's artist; on a compilation ("Various Artists"), under its own;
// a collaboration's album ("Noah Kahan & Hozier") with the first of its artists the
// shelf has.
// Built once for a library (MusicService.shelfArtists), not on each redraw.

nonisolated enum ArtistShelf {
    static func artists(albums: [AppAlbum], songs: [AppTrack]) -> [AppAlbum] {
        let albumsByTitle = Dictionary(grouping: albums) { $0.tapeTitle.lowercased() }
        struct Filed { var name: String; var tracks: [Entry] }
        var byKey: [String: Filed] = [:]

        for song in songs {
            let candidates = albumsByTitle[TapeFormat.displayTitle(song.albumTitle).lowercased()] ?? []
            let album = candidates.first { sameArtist(song.artistName, $0.artistName) }
                ?? (candidates.count == 1 ? candidates[0] : nil)
            let name: String
            if let album, !album.artistName.isEmpty, !isCompilation(album) {
                name = album.artistName
            } else {
                name = song.artistName
            }
            let key = name.trimmingCharacters(in: .whitespaces).lowercased()
            guard !key.isEmpty, key != "unknown artist" else { continue }
            // Disc and track numbers read once here: on a device file each is a lookup.
            let entry = Entry(track: song, album: album, disc: song.discNumber ?? 1, number: song.trackNumber ?? .max)
            byKey[key, default: Filed(name: name, tracks: [])].tracks.append(entry)
        }

        // A collaboration ("Noah Kahan & Hozier") goes in with the first of its artists
        // the shelf already has, rather than a case of its own for one song.
        let solo = Set(byKey.keys.filter { names(in: $0).count == 1 })
        for (key, filed) in byKey {
            let parts = names(in: key)
            guard parts.count > 1, let home = parts.first(where: solo.contains) else { continue }
            byKey[home]?.tracks += filed.tracks
            byKey[key] = nil
        }

        return byKey.map { key, filed in
            let ordered = filed.tracks.sorted(by: inAlbumOrder).map(\.track)
            // The first album's cover stands in until (or where there's no) photo.
            let cover = filed.tracks.lazy.compactMap(\.album).first { $0.musicKitAlbum?.artwork != nil || $0.mpArtwork != nil }
            return AppAlbum(id: "artist:\(key)", title: filed.name, artistName: "",
                            musicKitAlbum: cover?.musicKitAlbum, mpArtwork: cover?.mpArtwork,
                            preloadedTracks: ordered, isArtist: true)
        }
        .sorted { AppHelpers.sortsBefore($0.title, $1.title) }
    }

    /// The artists a credit names: "A & B", "A, B & C", "A feat. B".
    static func names(in credit: String) -> [String] {
        var parts = [credit.lowercased()]
        for separator in [" feat. ", " featuring ", " & ", ", "] {
            parts = parts.flatMap { $0.components(separatedBy: separator) }
        }
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// The same artist, allowing for a guest credit on either side.
    static func sameArtist(_ lhs: String, _ rhs: String) -> Bool {
        let a = lhs.lowercased(), b = rhs.lowercased()
        return !a.isEmpty && !b.isEmpty && (a == b || a.contains(b) || b.contains(a))
    }

    static func isCompilation(_ album: AppAlbum) -> Bool {
        album.musicKitAlbum?.isCompilation == true || album.artistName.lowercased() == "various artists"
    }

    private struct Entry {
        let track: AppTrack
        let album: AppAlbum?
        let disc: Int
        let number: Int
    }

    /// Newest album first (undated ones last, by name), then disc and track number.
    private static func inAlbumOrder(_ lhs: Entry, _ rhs: Entry) -> Bool {
        let leftAlbum = lhs.album?.id ?? lhs.track.albumTitle, rightAlbum = rhs.album?.id ?? rhs.track.albumTitle
        if leftAlbum != rightAlbum {
            switch (lhs.album?.releaseDate, rhs.album?.releaseDate) {
            case let (l?, r?) where l != r: return l > r
            case (.some, nil): return true
            case (nil, .some): return false
            default: return AppHelpers.sortsBefore(lhs.track.albumTitle, rhs.track.albumTitle)
            }
        }
        if lhs.disc != rhs.disc { return lhs.disc < rhs.disc }
        if lhs.number != rhs.number { return lhs.number < rhs.number }
        return AppHelpers.sortsBefore(lhs.track.title, rhs.track.title)
    }
}
