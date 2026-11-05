//
//  PlaylistAdder.swift
//  Lyre
//

import Foundation
import MusicKit
import MediaPlayer
import UIKit
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
// ID; without one, it can't be added. A song already in the playlist isn't added again
// (`isDuplicate`).
//
// A song can be taken out of a playlist again (`remove`), each player's hold menu
// offering it in the listener's own playlists. Apple lets an app change only the
// playlists it made, and doesn't say which those are: a playlist Apple refuses is
// remembered (`refused`), and isn't offered again. Songs can't be deleted from the
// library itself: Apple gives apps no way to.

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

    func offer(_ item: Item) {
        UsageStats.shared.used(.addToPlaylist)
        pending = item
    }

    /// A new playlist waiting to be named (NewPlaylistPrompt), from a player's New
    /// Playlist button.
    var isNamingNewPlaylist = false

    func promptNewPlaylist() { isNamingNewPlaylist = true }

    /// Makes a playlist named `name` in the listener's library, with `item` in it if
    /// given, and puts it among the service's playlists at once (the next load of the
    /// library finds it there anyway).
    @discardableResult
    func createPlaylist(named name: String, adding item: Item? = nil, in musicService: MusicService) async throws -> AppPlaylist {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let playlist: Playlist
        if let item {
            let song = try await musicKitSong(for: item)
            playlist = try await MusicLibrary.shared.createPlaylist(name: trimmed, items: [song])
        } else {
            playlist = try await MusicLibrary.shared.createPlaylist(name: trimmed)
        }
        let made = AppPlaylist(from: playlist)
        noteEdited(made.id)
        musicService.playlists.append(made)
        logger.debug("Made a playlist")
        return made
    }

    enum AddError: LocalizedError {
        case notInAppleMusic
        case playlistNotFound
        /// The song's in the playlist already (named).
        case alreadyInPlaylist(song: String, playlist: String)
        /// Apple only lets Lyre change the playlists made in Lyre.
        case notLyres
        /// The playlist changed since it was shown (elsewhere, in the Music app).
        case playlistChanged

        var errorDescription: String? {
            switch self {
            case .notInAppleMusic: String(localized: "playlist.add.notInAppleMusic")
            case .playlistNotFound: String(localized: "playlist.add.notFound")
            case .alreadyInPlaylist(let song, let playlist):
                String(format: String(localized: "playlist.add.duplicate"), song, playlist)
            case .notLyres: String(localized: "playlist.remove.notLyres")
            case .playlistChanged: String(localized: "playlist.remove.changed")
            }
        }
    }

    // MARK: Which playlists

    /// The playlists a song can be added to, the last edited first (LYRE-26), then by
    /// name. `edited` is when each was last changed.
    static func editable(_ playlists: [AppPlaylist], edited: (AppPlaylist) -> Date?) -> [AppPlaylist] {
        playlists
            .filter { isEditable(id: $0.id, kind: $0.musicKitPlaylist?.kind, curatorName: $0.curatorName) }
            .map { ($0, edited($0)) }
            .sorted { a, b in
                switch (a.1, b.1) {
                case let (x?, y?) where x != y: return x > y
                case (.some, nil): return true
                case (nil, .some): return false
                default: return AppHelpers.sortsBefore(a.0.name, b.0.name)
                }
            }
            .map(\.0)
    }

    /// When Lyre last changed each playlist (added to it, took a song out, edited or made
    /// it), kept between launches: Apple's own date can lag a change Lyre just made.
    private(set) var lastEdited: [String: Date] =
        (UserDefaults.standard.dictionary(forKey: "PlaylistsLastEdited") as? [String: Date]) ?? [:]

    private func noteEdited(_ id: String) {
        lastEdited[id] = .now
        UserDefaults.standard.set(lastEdited, forKey: "PlaylistsLastEdited")
    }

    /// When a playlist was last changed: here, or anywhere Apple knows of.
    func edited(_ playlist: AppPlaylist) -> Date? {
        [lastEdited[playlist.id], playlist.musicKitPlaylist?.lastModifiedDate].compactMap { $0 }.max()
    }

    /// The listener's own: from MusicKit (not an `mp.` id), and not one of Apple's.
    static func isEditable(id: String, kind: Playlist.Kind?, curatorName: String?) -> Bool {
        guard !id.hasPrefix("mp.") else { return false }
        if let kind, kind != .userShared { return false }
        return curatorName?.localizedCaseInsensitiveContains("Apple Music") != true
    }

    // MARK: Adding

    /// Adds `item` to `playlist`, unless it's there already.
    func add(_ item: Item, to playlist: AppPlaylist) async throws {
        let target = try await musicKitPlaylist(for: playlist)
        let song = try await musicKitSong(for: item)
        let existing = (try? await target.with([.tracks]).tracks).map(Array.init) ?? []
        if Self.isDuplicate(Self.entry(song), among: existing.map(Self.entry)) {
            throw AddError.alreadyInPlaylist(song: song.title, playlist: playlist.name)
        }
        _ = try await MusicLibrary.shared.add(song, to: target)
        noteEdited(playlist.id)
        logger.debug("Added a song to a playlist")
    }

    /// What tells two songs in a playlist apart.
    struct Entry: Equatable {
        var id: String
        var title: String
        var artist: String
        var duration: TimeInterval?
    }

    nonisolated private static func entry(_ song: Song) -> Entry {
        Entry(id: song.id.rawValue, title: song.title, artist: song.artistName, duration: song.duration)
    }

    nonisolated private static func entry(_ track: Track) -> Entry {
        Entry(id: track.id.rawValue, title: track.title, artist: track.artistName, duration: track.duration)
    }

    /// Whether `song` is in the playlist already: the same item, or the same title by
    /// the same artist of much the same length (the library's copy and the catalogue's
    /// have different IDs). Another version (a remix, a live take) has its own title.
    nonisolated static func isDuplicate(_ song: Entry, among entries: [Entry]) -> Bool {
        let title = folded(song.title), artist = folded(song.artist)
        return entries.contains { entry in
            if entry.id == song.id { return true }
            guard folded(entry.title) == title, folded(entry.artist) == artist else { return false }
            guard let a = entry.duration, let b = song.duration, a > 0, b > 0 else { return true }
            return abs(a - b) <= DeezerTempo.lengthTolerance
        }
    }

    /// A title or name as compared: case, accents and spacing aside, but every word
    /// kept, brackets too, so "(Remix)" or "(Live)" makes another song.
    nonisolated private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: Removing

    /// The playlists Apple wouldn't let Lyre change, kept between launches.
    private(set) var refused: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "PlaylistsLyreCantChange") ?? [])

    /// Whether a song can be taken out of `album`, a playlist: one Lyre made (`canEdit`).
    func canRemove(from album: AppAlbum) -> Bool {
        album.mixtape.map(canEdit) ?? false
    }

    /// The name MusicKit files a playlist an app makes under, as its curator: what tells
    /// the playlists Lyre made (which Apple lets it change) from the Music app's (which
    /// it doesn't). Checked on a device: a playlist made in Lyre is curated by "Lyre",
    /// as one made by another app is by that app's name.
    nonisolated static let lyreCurator = "Lyre"

    /// Whether Lyre may change `playlist`: one of the listener's own that Lyre made, and
    /// that Apple hasn't refused it changing (LYRE-25). Others show no Edit or Remove.
    func canEdit(_ playlist: AppPlaylist) -> Bool {
        guard playlist.isLibrary, !refused.contains(playlist.id) else { return false }
        #if DEBUG
        if Self.isSample(playlist) { return true }
        #endif
        return playlist.curatorName?.caseInsensitiveCompare(Self.lyreCurator) == .orderedSame
    }

    // MARK: Editing

    /// Saves an edited playlist (LYRE-25): its name, if changed, and its songs, as given:
    /// reordered, some taken out, some added. Returns the playlist as it now is.
    func save(_ playlist: AppPlaylist, name: String, tracks: [AppTrack]) async throws -> AppPlaylist {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        #if DEBUG
        // The sample mixtapes are only in Lyre.
        if Self.isSample(playlist) {
            return AppPlaylist(id: playlist.id, name: name, curatorName: playlist.curatorName,
                               mpArtwork: playlist.mpArtwork, preloadedTracks: tracks)
        }
        #endif
        let target = try await musicKitPlaylist(for: playlist)
        var items: [Track] = []
        for track in tracks {
            if let item = track.musicKitTrack { items.append(item) }
            else { items.append(.song(try await musicKitSong(for: .track(track)))) }
        }
        do {
            let edited = try await MusicLibrary.shared.edit(target, name: name == target.name ? nil : name, items: items)
            noteEdited(playlist.id)
            logger.debug("Edited a playlist")
            return AppPlaylist(from: edited)
        } catch {
            if error is URLError || error is CancellationError { throw error }
            refused.insert(playlist.id)
            UserDefaults.standard.set(Array(refused), forKey: "PlaylistsLyreCantChange")
            throw AddError.notLyres
        }
    }

    /// What tells a song in a playlist from another, for one being added (`isDuplicate`).
    nonisolated static func entry(_ track: AppTrack) -> Entry {
        Entry(id: track.musicKitSong?.id.rawValue ?? track.id, title: track.title, artist: track.artistName,
              duration: track.duration > 0 ? track.duration : nil)
    }

    /// Takes the song at `index` (`track`) out of `album`'s playlist. Checks the playlist
    /// still has that song there first, so a playlist changed elsewhere since it was
    /// shown loses nothing it shouldn't.
    func remove(_ track: AppTrack, at index: Int, from album: AppAlbum) async throws {
        guard let playlist = album.mixtape else { return }
        #if DEBUG
        // The sample mixtapes are only in Lyre: the song goes from the list alone.
        if Self.isSample(playlist) { return }
        #endif
        let target = try await musicKitPlaylist(for: playlist)
        var items = Array(try await target.with([.tracks]).tracks ?? [])
        guard items.indices.contains(index),
              DeezerTempo.normalized(items[index].title) == DeezerTempo.normalized(track.title) else {
            throw AddError.playlistChanged
        }
        items.remove(at: index)
        do {
            _ = try await MusicLibrary.shared.edit(target, items: items)
            noteEdited(playlist.id)
            logger.debug("Took a song out of a playlist")
        } catch {
            // Offline isn't a refusal; anything else from Apple is.
            if error is URLError || error is CancellationError { throw error }
            refused.insert(playlist.id)
            UserDefaults.standard.set(Array(refused), forKey: "PlaylistsLyreCantChange")
            logger.error("Playlist edit refused: \(String(describing: error), privacy: .public)")
            throw AddError.notLyres
        }
    }

    /// Why the last removal didn't happen, for the app's root to say (NewPlaylistPrompt).
    var removalFailure: String?

    /// A hold menu's Remove from Playlist, for the song at `index` of `album`: nil where
    /// it can't be taken out. `onRemoved` takes the row out of the list showing.
    func removeAction(_ track: AppTrack, at index: Int, from album: AppAlbum,
                      onRemoved: @escaping () -> Void) -> (() -> Void)? {
        guard canRemove(from: album) else { return nil }
        return {
            Task {
                do {
                    try await self.remove(track, at: index, from: album)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onRemoved()
                } catch {
                    self.removalFailure = error.localizedDescription
                }
            }
        }
    }

    #if DEBUG
    private static func isSample(_ playlist: AppPlaylist) -> Bool { playlist.id.hasPrefix("sample-mix-") }
    #endif

    private func musicKitPlaylist(for playlist: AppPlaylist) async throws -> Playlist {
        if let playlist = playlist.musicKitPlaylist { return playlist }
        // One restored from the cache carries only its ID.
        var request = MusicLibraryRequest<Playlist>()
        request.filter(matching: \.id, equalTo: MusicItemID(playlist.id))
        guard let found = try await request.response().items.first else { throw AddError.playlistNotFound }
        return found
    }

    func musicKitSong(for item: Item) async throws -> Song {
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
