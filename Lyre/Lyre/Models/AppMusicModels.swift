//
//  AppMusicModels.swift
//  Lyre
//
//  Unified music types wrapping MusicKit objects.
//

import Foundation
import MusicKit

// MARK: - Overview
//
// Lightweight wrapper types that bridge MusicKit's catalogue objects to the rest of the app.
// MusicKit types (Song, Album, etc.) can only be created via async requests and carry heavy
// metadata; these structs extract only the data the UI needs while keeping an optional
// reference to the original MusicKit object for on-demand artwork lookups.
//
// All four types use id-based Equatable/Hashable so they work safely in Sets and as
// Dictionary keys without requiring @MainActor isolation. The `nonisolated` annotations
// on `==` and `hash(into:)` satisfy Swift Concurrency's strict actor-isolation rules.

// MARK: - AppTrack

struct AppTrack: Identifiable, Hashable {
    let id: String
    let title: String
    let artistName: String
    let albumTitle: String
    let duration: TimeInterval
    let musicKitSong: Song?
    let musicKitTrack: Track?

    init(
        id: String, title: String, artistName: String, albumTitle: String,
        duration: TimeInterval,
        musicKitSong: Song? = nil, musicKitTrack: Track? = nil
    ) {
        self.id = id; self.title = title; self.artistName = artistName
        self.albumTitle = albumTitle; self.duration = duration
        self.musicKitSong = musicKitSong; self.musicKitTrack = musicKitTrack
    }

    nonisolated static func == (lhs: AppTrack, rhs: AppTrack) -> Bool { lhs.id == rhs.id }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - AppAlbum

struct AppAlbum: Identifiable, Hashable {
    let id: String
    let title: String
    let artistName: String
    let releaseDate: Date?
    let musicKitAlbum: Album?
    var preloadedTracks: [AppTrack]

    init(
        id: String, title: String, artistName: String,
        releaseDate: Date? = nil, musicKitAlbum: Album? = nil,
        preloadedTracks: [AppTrack] = []
    ) {
        self.id = id; self.title = title; self.artistName = artistName
        self.releaseDate = releaseDate; self.musicKitAlbum = musicKitAlbum
        self.preloadedTracks = preloadedTracks
    }

    nonisolated static func == (lhs: AppAlbum, rhs: AppAlbum) -> Bool { lhs.id == rhs.id }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - AppArtist

struct AppArtist: Identifiable, Hashable {
    let id: String
    let name: String
    let musicKitArtist: Artist?
    var preloadedAlbums: [AppAlbum]

    init(
        id: String, name: String,
        musicKitArtist: Artist? = nil, preloadedAlbums: [AppAlbum] = []
    ) {
        self.id = id; self.name = name
        self.musicKitArtist = musicKitArtist; self.preloadedAlbums = preloadedAlbums
    }

    nonisolated static func == (lhs: AppArtist, rhs: AppArtist) -> Bool { lhs.id == rhs.id }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - AppPlaylist

struct AppPlaylist: Identifiable, Hashable {
    let id: String
    let name: String
    let curatorName: String?
    let musicKitPlaylist: Playlist?
    var preloadedTracks: [AppTrack]

    init(
        id: String, name: String,
        curatorName: String? = nil, musicKitPlaylist: Playlist? = nil,
        preloadedTracks: [AppTrack] = []
    ) {
        self.id = id; self.name = name
        self.curatorName = curatorName; self.musicKitPlaylist = musicKitPlaylist
        self.preloadedTracks = preloadedTracks
    }

    nonisolated static func == (lhs: AppPlaylist, rhs: AppPlaylist) -> Bool { lhs.id == rhs.id }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - MusicKit Convenience Initializers

extension AppTrack {
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

extension AppAlbum {
    init(from album: Album) {
        self.init(
            id: album.id.rawValue, title: album.title, artistName: album.artistName,
            releaseDate: album.releaseDate, musicKitAlbum: album
        )
    }
}

extension AppArtist {
    init(from artist: Artist) {
        self.init(
            id: artist.id.rawValue, name: artist.name,
            musicKitArtist: artist
        )
    }
}

extension AppPlaylist {
    init(from playlist: Playlist) {
        self.init(
            id: playlist.id.rawValue, name: playlist.name,
            curatorName: playlist.curatorName,
            musicKitPlaylist: playlist
        )
    }
}
