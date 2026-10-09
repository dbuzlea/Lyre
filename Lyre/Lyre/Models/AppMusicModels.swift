//
//  AppMusicModels.swift
//  Lyre
//
//  Unified music types wrapping MusicKit objects.
//

import Foundation
import MusicKit
import MediaPlayer

// MARK: - Overview
//
// Lightweight wrapper types that bridge MusicKit's catalogue objects to the rest of the app.
// MusicKit types (Song, Album, etc.) can only be created via async requests and carry heavy
// metadata; these structs extract only the data the UI needs while keeping an optional
// reference to the original MusicKit object for on-demand artwork lookups.
//
// Each type also carries an optional MediaPlayer backing reference (`mpItem` / `mpArtwork`).
// Users without an active Apple Music subscription have no MusicKit catalogue objects for
// their music, so the library is built from MPMediaQuery instead and these fields are the
// only source of artwork and the only reliable handle for queueing playback.
//
// All four types use id-based Equatable/Hashable so they work safely in Sets and as
// Dictionary keys.
//
// The types are `nonisolated`. The target defaults every declaration to the main actor,
// and these are built in bulk by LibraryScanner off the main thread — a main-actor
// initialiser would drag the whole library scan back onto the main thread.

// MARK: - AppTrack

nonisolated struct AppTrack: Identifiable, Hashable {
    let id: String
    let title: String
    let artistName: String
    let albumTitle: String
    let duration: TimeInterval
    let musicKitSong: Song?
    let musicKitTrack: Track?
    /// Local MediaPlayer item backing this track, when one exists. Used directly for
    /// playback queueing and as the artwork source for non-subscribers.
    let mpItem: MPMediaItem?
    /// Persistent ID of the local item. Kept separately from `mpItem` because it is the
    /// only part that survives the launch cache: a track restored from disk has no live
    /// item, and this is what lets playback look the exact item up again.
    let mpPersistentID: MPMediaEntityPersistentID?

    init(
        id: String, title: String, artistName: String, albumTitle: String,
        duration: TimeInterval,
        musicKitSong: Song? = nil, musicKitTrack: Track? = nil,
        mpItem: MPMediaItem? = nil,
        mpPersistentID: MPMediaEntityPersistentID? = nil
    ) {
        self.id = id; self.title = title; self.artistName = artistName
        self.albumTitle = albumTitle; self.duration = duration
        self.musicKitSong = musicKitSong; self.musicKitTrack = musicKitTrack
        self.mpItem = mpItem
        self.mpPersistentID = mpPersistentID ?? mpItem?.persistentID
    }

    /// Returns a copy with `mpItem` attached, preserving all other metadata.
    func attaching(mpItem item: MPMediaItem?) -> AppTrack {
        guard mpItem == nil, let item else { return self }
        return AppTrack(
            id: id, title: title, artistName: artistName, albumTitle: albumTitle,
            duration: duration, musicKitSong: musicKitSong, musicKitTrack: musicKitTrack,
            mpItem: item
        )
    }

    static func == (lhs: AppTrack, rhs: AppTrack) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - AppAlbum

nonisolated struct AppAlbum: Identifiable, Hashable {
    let id: String
    let title: String
    let artistName: String
    let releaseDate: Date?
    let musicKitAlbum: Album?
    let mpArtwork: MPMediaItemArtwork?
    var preloadedTracks: [AppTrack]
    /// Set when the Spool shows a playlist as a mixtape: the playlist it was made from.
    let mixtape: AppPlaylist?
    /// Set when the Spool shows a podcast as a spoken-word tape: the show it was made from.
    let podcast: PodcastShow?

    init(
        id: String, title: String, artistName: String,
        releaseDate: Date? = nil, musicKitAlbum: Album? = nil,
        mpArtwork: MPMediaItemArtwork? = nil,
        preloadedTracks: [AppTrack] = [],
        mixtape: AppPlaylist? = nil,
        podcast: PodcastShow? = nil
    ) {
        self.id = id; self.title = title; self.artistName = artistName
        self.releaseDate = releaseDate; self.musicKitAlbum = musicKitAlbum
        self.mpArtwork = mpArtwork
        self.preloadedTracks = preloadedTracks
        self.mixtape = mixtape
        self.podcast = podcast
    }

    static func == (lhs: AppAlbum, rhs: AppAlbum) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Duplicate Songs

nonisolated extension Array where Element == AppTrack {
    /// An album's songs with repeated copies of a song taken out. A library can list
    /// one song on an album more than once:
    ///
    /// • a stand-in with no length beside the real copy, on a local album; and
    /// • the same song added twice, as Apple Music does when it's added again from a
    ///   single or a playlist. Both copies have a length, and both play the same file.
    ///
    /// A copy with no length goes when the album has the same title with a length. A
    /// copy with a length goes when an earlier song has the same title and the same
    /// length, to within `lengthTolerance`. The first copy stays, in its place. Songs
    /// that really share a title (an interlude and its reprise) run for different
    /// lengths, so they stay, as do songs with no length at all.
    var withoutDuplicates: [AppTrack] {
        let timed = Set(filter { $0.duration > 0 }.map(\.titleKey))
        var kept: [AppTrack] = []
        for track in self {
            if track.duration > 0 {
                let isRepeat = kept.contains {
                    $0.titleKey == track.titleKey && abs($0.duration - track.duration) <= Self.lengthTolerance
                }
                if !isRepeat { kept.append(track) }
            } else if !timed.contains(track.titleKey) {
                kept.append(track)
            }
        }
        return kept
    }

    /// How far apart two copies' lengths can be and still be the same recording; the
    /// store and a local file can round the same song differently.
    static var lengthTolerance: TimeInterval { 2 }
}

private extension AppTrack {
    nonisolated var titleKey: String {
        title.trimmingCharacters(in: .whitespaces).lowercased()
    }
}

// MARK: - AppArtist

nonisolated struct AppArtist: Identifiable, Hashable {
    let id: String
    let name: String
    let musicKitArtist: Artist?
    let mpArtwork: MPMediaItemArtwork?
    var preloadedAlbums: [AppAlbum]

    init(
        id: String, name: String,
        musicKitArtist: Artist? = nil,
        mpArtwork: MPMediaItemArtwork? = nil,
        preloadedAlbums: [AppAlbum] = []
    ) {
        self.id = id; self.name = name
        self.musicKitArtist = musicKitArtist; self.mpArtwork = mpArtwork
        self.preloadedAlbums = preloadedAlbums
    }

    static func == (lhs: AppArtist, rhs: AppArtist) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - AppPlaylist

nonisolated struct AppPlaylist: Identifiable, Hashable {
    let id: String
    let name: String
    let curatorName: String?
    let musicKitPlaylist: Playlist?
    let mpArtwork: MPMediaItemArtwork?
    var preloadedTracks: [AppTrack]

    init(
        id: String, name: String,
        curatorName: String? = nil, musicKitPlaylist: Playlist? = nil,
        mpArtwork: MPMediaItemArtwork? = nil,
        preloadedTracks: [AppTrack] = []
    ) {
        self.id = id; self.name = name
        self.curatorName = curatorName; self.musicKitPlaylist = musicKitPlaylist
        self.mpArtwork = mpArtwork
        self.preloadedTracks = preloadedTracks
    }

    static func == (lhs: AppPlaylist, rhs: AppPlaylist) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - MusicKit Convenience Initializers

nonisolated extension AppTrack {
    init(from song: Song) {
        self.init(
            id: song.id.rawValue, title: song.title,
            artistName: song.artistName, albumTitle: song.albumTitle ?? "",
            duration: song.duration ?? 0,
            musicKitSong: song
        )
    }

    init(from track: Track) {
        switch track {
        case .song(let song):
            self.init(
                id: song.id.rawValue, title: song.title,
                artistName: song.artistName, albumTitle: song.albumTitle ?? "",
                duration: song.duration ?? 0,
                musicKitSong: song, musicKitTrack: track
            )
        case .musicVideo(let mv):
            self.init(
                id: mv.id.rawValue, title: mv.title,
                artistName: mv.artistName, albumTitle: mv.albumTitle ?? "",
                duration: mv.duration ?? 0,
                musicKitTrack: track
            )
        @unknown default:
            self.init(
                id: UUID().uuidString, title: track.title,
                artistName: track.artistName, albumTitle: "",
                duration: track.duration ?? 0,
                musicKitTrack: track
            )
        }
    }
}

nonisolated extension AppAlbum {
    init(from album: Album) {
        self.init(
            id: album.id.rawValue, title: album.title, artistName: album.artistName,
            releaseDate: album.releaseDate, musicKitAlbum: album
        )
    }
}

nonisolated extension AppArtist {
    init(from artist: Artist) {
        self.init(
            id: artist.id.rawValue, name: artist.name,
            musicKitArtist: artist
        )
    }
}

nonisolated extension AppPlaylist {
    init(from playlist: Playlist) {
        self.init(
            id: playlist.id.rawValue, name: playlist.name,
            curatorName: playlist.curatorName,
            musicKitPlaylist: playlist
        )
    }
}

// MARK: - MediaPlayer Convenience Initializers
//
// These build the same UI models from the on-device media library. They are the only
// source of library content for users without an active Apple Music subscription, and
// they also back the local fallback whenever a MusicKit library request comes up empty.

nonisolated extension AppTrack {
    init(from item: MPMediaItem) {
        self.init(
            id: "mp.\(item.persistentID)",
            title: item.title ?? "Unknown Track",
            artistName: item.artist ?? item.albumArtist ?? "Unknown Artist",
            albumTitle: item.albumTitle ?? "",
            duration: item.playbackDuration,
            mpItem: item
        )
    }
}

nonisolated extension AppAlbum {
    /// Builds an album from a local album collection. `representative` supplies the
    /// album-level metadata and artwork; `tracks` are preloaded so the detail view
    /// never needs an (impossible) MusicKit round trip.
    init(from representative: MPMediaItem, tracks: [AppTrack]) {
        self.init(
            id: "mp.album.\(representative.albumPersistentID)",
            title: representative.albumTitle ?? "Unknown Album",
            artistName: representative.albumArtist ?? representative.artist ?? "Unknown Artist",
            releaseDate: representative.releaseDate,
            mpArtwork: representative.artwork,
            preloadedTracks: tracks
        )
    }
}

nonisolated extension AppArtist {
    init(from representative: MPMediaItem, albums: [AppAlbum]) {
        self.init(
            id: "mp.artist.\(representative.artistPersistentID)",
            name: representative.albumArtist ?? representative.artist ?? "Unknown Artist",
            mpArtwork: representative.artwork,
            preloadedAlbums: albums
        )
    }
}

nonisolated extension AppPlaylist {
    init(from playlist: MPMediaPlaylist, tracks: [AppTrack]) {
        self.init(
            id: "mp.playlist.\(playlist.persistentID)",
            name: playlist.name ?? "Untitled Playlist",
            curatorName: nil,
            mpArtwork: playlist.representativeItem?.artwork,
            preloadedTracks: tracks
        )
    }
}
