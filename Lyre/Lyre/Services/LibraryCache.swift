//
//  LibraryCache.swift
//  Lyre
//

import Foundation
import MediaPlayer
import OSLog

// `nonisolated` because every use is off the main thread.
nonisolated private let logger = Logger(subsystem: "com.pinkhatcreations.lyreapp", category: "LibraryCache")

// MARK: - LibraryCache
//
// A copy of the last loaded library, kept on disk so the menus are populated the moment
// the app launches instead of after a full rescan.
//
// What is stored
//   Only plain metadata: ids, titles, names, durations and the local persistent ID of
//   each track. MPMediaItem, MPMediaItemArtwork and MusicKit objects cannot be
//   serialised, so a restored library has no artwork and no MusicKit handles.
//
// How that is covered
//   The restored library is a bridge, not a replacement. MusicService still runs the
//   full load straight after restoring and swaps the live library in when it lands,
//   usually within a second or two. Until then:
//     • Playback resolves each track's item from its persistent ID (exact and fast).
//     • Album, artist and playlist contents wait for the live load, then use the live
//       object — see MusicService.liveAlbum(for:) and friends.
//     • Podcasts are not cached at all (episodes are MPMediaItems); they appear as soon
//       as the podcast scan finishes, which is one of the first things the load does.
//
// The file lives in Caches: it is fully regenerable, excluded from backups, and the
// system may purge it, which just means one launch without the head start.

nonisolated enum LibraryCache {

    /// Bump when the stored shape or list order changes. A mismatched file is ignored
    /// and replaced. 2: local lists sort ignoring leading articles.
    private static let formatVersion = 2

    private static var fileURL: URL? {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("LibrarySnapshot.plist")
    }

    struct Restored {
        var snapshot: LibrarySnapshot
        var source: MusicLibrarySource
    }

    // MARK: - Load

    @concurrent
    static func load() async -> Restored? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        do {
            let file = try PropertyListDecoder().decode(CacheFile.self, from: data)
            guard file.formatVersion == formatVersion else {
                logger.notice("Ignoring library cache with format \(file.formatVersion) (expected \(formatVersion))")
                return nil
            }
            let restored = file.restored()
            logger.notice("Restored \(restored.snapshot.songs.count) songs, \(restored.snapshot.albums.count) albums from the library cache")
            return restored
        } catch {
            logger.error("Library cache unreadable, discarding: \(error.localizedDescription)")
            clear()
            return nil
        }
    }

    // MARK: - Save

    @concurrent
    static func save(_ snapshot: LibrarySnapshot, source: MusicLibrarySource) async {
        guard let url = fileURL else { return }
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(CacheFile(snapshot: snapshot, source: source, formatVersion: formatVersion))
            // Most launches find the library unchanged. Rewriting several megabytes of
            // identical bytes each time is wasted flash wear and battery, so compare
            // first — reading is far cheaper than writing.
            if let existing = try? Data(contentsOf: url), existing == data {
                logger.info("Library unchanged — cache left as is")
                return
            }
            try data.write(to: url, options: [.atomic])
        } catch {
            logger.error("Could not write the library cache: \(error.localizedDescription)")
        }
    }

    /// Drops the cache — used when library access is revoked, so a later launch
    /// cannot show music the app is no longer allowed to read.
    static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - File Format
//
// Tracks are stored once in a table and referenced by id everywhere else. The local
// library lists every song in Songs, again in its album and again under its artist, so
// nesting them would roughly triple the file.

private nonisolated struct CacheFile: Codable {
    var formatVersion: Int
    var source: MusicLibrarySource
    var tracks: [CachedTrack]
    var songIDs: [String]
    var recentlyAddedIDs: [String]
    var recentlyPlayedIDs: [String]
    var albums: [CachedAlbum]
    var artists: [CachedArtist]
    var playlists: [CachedPlaylist]

    struct CachedTrack: Codable {
        var id: String
        var title: String
        var artistName: String
        var albumTitle: String
        var duration: TimeInterval
        /// Stored as a bit pattern: persistent IDs use the full unsigned 64-bit range,
        /// and property lists only hold signed integers.
        var persistentID: Int64?
    }

    struct CachedAlbum: Codable {
        var id: String
        var title: String
        var artistName: String
        var releaseDate: Date?
        var trackIDs: [String]
    }

    struct CachedArtist: Codable {
        var id: String
        var name: String
        var albums: [CachedAlbum]
    }

    struct CachedPlaylist: Codable {
        var id: String
        var name: String
        var curatorName: String?
        var trackIDs: [String]
    }

    init(snapshot: LibrarySnapshot, source: MusicLibrarySource, formatVersion: Int) {
        var table: [String: CachedTrack] = [:]
        func ids(_ tracks: [AppTrack]) -> [String] {
            for track in tracks where table[track.id] == nil {
                table[track.id] = CachedTrack(
                    id: track.id, title: track.title, artistName: track.artistName,
                    albumTitle: track.albumTitle, duration: track.duration,
                    persistentID: track.mpPersistentID.map { Int64(bitPattern: $0) }
                )
            }
            return tracks.map(\.id)
        }
        func album(_ album: AppAlbum) -> CachedAlbum {
            CachedAlbum(
                id: album.id, title: album.title, artistName: album.artistName,
                releaseDate: album.releaseDate, trackIDs: ids(album.preloadedTracks)
            )
        }

        self.formatVersion     = formatVersion
        self.source            = source
        self.songIDs           = ids(snapshot.songs)
        self.recentlyAddedIDs  = ids(snapshot.recentlyAdded)
        self.recentlyPlayedIDs = ids(snapshot.recentlyPlayed)
        self.albums            = snapshot.albums.map(album)
        self.artists           = snapshot.artists.map {
            CachedArtist(id: $0.id, name: $0.name, albums: $0.preloadedAlbums.map(album))
        }
        self.playlists         = snapshot.playlists.map {
            CachedPlaylist(id: $0.id, name: $0.name, curatorName: $0.curatorName, trackIDs: ids($0.preloadedTracks))
        }
        // Sorted so the same library always encodes to the same bytes, which is what
        // lets `save` skip rewriting an unchanged file.
        self.tracks            = table.values.sorted { $0.id < $1.id }
    }

    func restored() -> LibraryCache.Restored {
        let table = Dictionary(
            tracks.map { cached in
                (cached.id, AppTrack(
                    id: cached.id, title: cached.title, artistName: cached.artistName,
                    albumTitle: cached.albumTitle, duration: cached.duration,
                    mpPersistentID: cached.persistentID.map { UInt64(bitPattern: $0) }
                ))
            },
            uniquingKeysWith: { first, _ in first }
        )
        func resolve(_ ids: [String]) -> [AppTrack] { ids.compactMap { table[$0] } }
        func album(_ cached: CachedAlbum) -> AppAlbum {
            AppAlbum(
                id: cached.id, title: cached.title, artistName: cached.artistName,
                releaseDate: cached.releaseDate, preloadedTracks: resolve(cached.trackIDs)
            )
        }

        var snapshot = LibrarySnapshot()
        snapshot.songs          = resolve(songIDs)
        snapshot.recentlyAdded  = resolve(recentlyAddedIDs)
        snapshot.recentlyPlayed = resolve(recentlyPlayedIDs)
        snapshot.albums         = albums.map(album)
        snapshot.artists        = artists.map {
            AppArtist(id: $0.id, name: $0.name, preloadedAlbums: $0.albums.map(album))
        }
        snapshot.playlists      = playlists.map {
            AppPlaylist(id: $0.id, name: $0.name, curatorName: $0.curatorName, preloadedTracks: resolve($0.trackIDs))
        }
        return LibraryCache.Restored(snapshot: snapshot, source: source)
    }
}
