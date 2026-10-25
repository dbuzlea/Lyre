//
//  PlaylistAdder.swift
//  Lyre
//

import Foundation
import MusicKit
import MediaPlayer
import OSLog

private let logger = Logger(subsystem: "com.pinkhatcreations.lyreapp", category: "PlaylistAdder")

// MARK: - Playlist Adder
//
// Adds a song to one of the listener's own playlists: a song from the library (held in
// any player, "Add to Playlist…") or one from Apple Music's catalogue (Liquid's search,
// charts and artist pages). Whatever asks sets `pending`; the app's root shows the
// playlists to choose from (PlaylistPicker) and adds it there.
//
// Only playlists the listener made can be added to: not Apple's (editorial, personal
// mixes, Replay) nor ones from the device's own library without MusicKit (which it
// can't edit). A song only known to the device is found in the catalogue by its store
// ID; without one, it can't be added.

@MainActor
@Observable
final class PlaylistAdder {
    static let shared = PlaylistAdder()

    /// A song to add, from the library or the catalogue.
    enum Item: Identifiable {
        case track(AppTrack)
        case song(Song)

        var id: String {
            switch self {
            case .track(let track): "track:" + track.id
            case .song(let song): "song:" + song.id.rawValue
            }
        }
        var title: String {
            switch self {
            case .track(let track): track.title
            case .song(let song): song.title
            }
        }
    }

    /// What's waiting for a playlist to be chosen.
    var pending: Item?

    func offer(_ item: Item) { pending = item }

    enum AddError: LocalizedError {
        case notInAppleMusic
        case playlistNotFound

        var errorDescription: String? {
            switch self {
            case .notInAppleMusic: String(localized: "playlist.add.notInAppleMusic")
            case .playlistNotFound: String(localized: "playlist.add.notFound")
            }
        }
    }

    // MARK: Which playlists

    /// The playlists a song can be added to, by name.
    static func editable(_ playlists: [AppPlaylist]) -> [AppPlaylist] {
        playlists
            .filter { isEditable(id: $0.id, kind: $0.musicKitPlaylist?.kind, curatorName: $0.curatorName) }
            .sorted { AppHelpers.sortsBefore($0.name, $1.name) }
    }

    /// The listener's own: from MusicKit (not an `mp.` id), and not one of Apple's.
    static func isEditable(id: String, kind: Playlist.Kind?, curatorName: String?) -> Bool {
        guard !id.hasPrefix("mp.") else { return false }
        if let kind, kind != .userShared { return false }
        return curatorName?.localizedCaseInsensitiveContains("Apple Music") != true
    }

    // MARK: Adding

    /// Adds `item` to `playlist`.
    func add(_ item: Item, to playlist: AppPlaylist) async throws {
        let target = try await musicKitPlaylist(for: playlist)
        let song = try await musicKitSong(for: item)
        _ = try await MusicLibrary.shared.add(song, to: target)
        logger.debug("Added a song to a playlist")
    }

    private func musicKitPlaylist(for playlist: AppPlaylist) async throws -> Playlist {
        if let playlist = playlist.musicKitPlaylist { return playlist }
        // One restored from the cache carries only its ID.
        var request = MusicLibraryRequest<Playlist>()
        request.filter(matching: \.id, equalTo: MusicItemID(playlist.id))
        guard let found = try await request.response().items.first else { throw AddError.playlistNotFound }
        return found
    }

    private func musicKitSong(for item: Item) async throws -> Song {
        switch item {
        case .song(let song):
            return song
        case .track(let track):
            if let song = track.musicKitSong { return song }
            if !track.id.hasPrefix("mp.") {
                var request = MusicLibraryRequest<Song>()
                request.filter(matching: \.id, equalTo: MusicItemID(track.id))
                if let found = try await request.response().items.first { return found }
            }
            // Only the device knows it: Apple Music's copy, by its store ID.
            if let storeID = track.mpItem?.playbackStoreID, !storeID.isEmpty, storeID != "0" {
                let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(storeID))
                if let found = try await request.response().items.first { return found }
            }
            throw AddError.notInAppleMusic
        }
    }
}
