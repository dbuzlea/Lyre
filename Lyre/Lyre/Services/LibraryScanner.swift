//
//  LibraryScanner.swift
//  Lyre
//

import Foundation
import MusicKit
import MediaPlayer

// MARK: - LibraryScanner
//
// Builds the library off the main thread. The target defaults every declaration to the
// main actor, so before this existed the whole scan — thousands of MPMediaItem property
// reads, several full-library sorts and every MusicKit response mapping — ran on the
// main thread and froze the interface on every launch.
//
// Everything here is `nonisolated`, and the entry points are `@concurrent` so they run
// on the global executor whoever calls them.
//
// Cost model
//   An MPMediaItem fetches each property lazily from the media library daemon, so the
//   expensive thing is not the number of items but the number of property reads. The
//   local scan reads every property it needs exactly once into a `LocalRecord`; sorting
//   and grouping then work on those cached values. Albums and artists are grouped from
//   the same records instead of re-running `MPMediaQuery.albums()` / `.artists()`, each
//   of which would materialise the entire library again.

/// An immutable view of one source's contribution to the library. Built off the main
/// actor and merged before publishing, so the UI never sees a half-merged library.
nonisolated struct LibrarySnapshot {
    var songs:          [AppTrack]    = []
    var albums:         [AppAlbum]    = []
    var artists:        [AppArtist]   = []
    var playlists:      [AppPlaylist] = []
    var recentlyAdded:  [AppTrack]    = []
    var recentlyPlayed: [AppTrack]    = []
    /// Local MPMediaItems keyed by normalised title + artist, used to attach a
    /// playback handle to MusicKit-sourced tracks.
    var mpItemIndex: [String: MPMediaItem] = [:]

    var isEmpty: Bool {
        songs.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty
    }

    /// Prefers the MusicKit snapshot per collection, falling back to local content
    /// for anything MusicKit did not return.
    static func merging(preferred: LibrarySnapshot?, fallback: LibrarySnapshot) -> LibrarySnapshot {
        guard let preferred else { return fallback }
        var merged = LibrarySnapshot()
        merged.songs          = preferred.songs.isEmpty          ? fallback.songs          : preferred.songs
        merged.albums         = preferred.albums.isEmpty         ? fallback.albums         : preferred.albums
        merged.artists        = preferred.artists.isEmpty        ? fallback.artists        : preferred.artists
        merged.playlists      = preferred.playlists.isEmpty      ? fallback.playlists      : preferred.playlists
        merged.recentlyAdded  = preferred.recentlyAdded.isEmpty  ? fallback.recentlyAdded  : preferred.recentlyAdded
        merged.recentlyPlayed = preferred.recentlyPlayed.isEmpty ? fallback.recentlyPlayed : preferred.recentlyPlayed
        merged.mpItemIndex    = fallback.mpItemIndex
        return merged
    }

    static func source(preferred: LibrarySnapshot?, merged: LibrarySnapshot) -> MusicLibrarySource {
        if merged.isEmpty { return .none }
        guard let preferred, !preferred.isEmpty else { return .localMedia }
        // Mixed only when a collection actually fell through to the local snapshot.
        let usedFallback =
            (preferred.songs.isEmpty     && !merged.songs.isEmpty)     ||
            (preferred.albums.isEmpty    && !merged.albums.isEmpty)    ||
            (preferred.artists.isEmpty   && !merged.artists.isEmpty)   ||
            (preferred.playlists.isEmpty && !merged.playlists.isEmpty)
        return usedFallback ? .mixed : .appleMusic
    }
}

nonisolated enum LibraryScanner {

    /// Normalised key for matching a MusicKit song to its on-device counterpart.
    static func matchKey(title: String, artist: String) -> String {
        "\(title.lowercased())\u{1}\(artist.lowercased())"
    }

    // MARK: - Local Scan

    /// One on-device song with every property the load needs read exactly once.
    struct LocalRecord {
        let item: MPMediaItem
        let track: AppTrack
        let matchKey: String
        let dateAdded: Date
        let lastPlayed: Date?
        let albumID: MPMediaEntityPersistentID
        let artistID: MPMediaEntityPersistentID
        let discNumber: Int
        let trackNumber: Int
    }

    struct LocalScan {
        /// Songs, recents and the match index. Albums, artists and playlists are only
        /// built on demand, by `localCollections`.
        var snapshot = LibrarySnapshot()
        /// Every playable song, in query order.
        var records: [LocalRecord] = []
        /// Newest first. Kept whole so the MusicKit pass can upgrade the same order.
        var byDateAdded: [LocalRecord] = []
        var byLastPlayed: [LocalRecord] = []
    }

    private static let recentsLimit = 25

    /// Without a subscription, cloud items that were never downloaded cannot play, so
    /// `playableOnly` hides them and every row in the interface stays playable.
    /// `isCloudItem` is checked first because `assetURL` is the slower of the two.
    static func isPlayable(_ item: MPMediaItem, playableOnly: Bool) -> Bool {
        guard playableOnly, item.isCloudItem else { return true }
        return item.assetURL != nil
    }

    @concurrent
    static func scanLocal(playableOnly: Bool) async -> LocalScan {
        var scan = LocalScan()
        let items = MPMediaQuery.songs().items ?? []
        guard !items.isEmpty else { return scan }

        var records: [LocalRecord] = []
        records.reserveCapacity(items.count)
        for item in items where isPlayable(item, playableOnly: playableOnly) {
            let rawTitle = item.title
            let rawArtist = item.artist
            let track = AppTrack(
                id: "mp.\(item.persistentID)",
                title: rawTitle ?? "Unknown Track",
                artistName: rawArtist ?? item.albumArtist ?? "Unknown Artist",
                albumTitle: item.albumTitle ?? "",
                duration: item.playbackDuration,
                mpItem: item
            )
            records.append(LocalRecord(
                item: item,
                track: track,
                matchKey: matchKey(title: rawTitle ?? "", artist: rawArtist ?? ""),
                dateAdded: item.dateAdded,
                lastPlayed: item.lastPlayedDate,
                albumID: item.albumPersistentID,
                artistID: item.artistPersistentID,
                discNumber: item.discNumber,
                trackNumber: item.albumTrackNumber
            ))
        }
        guard !records.isEmpty else { return scan }

        scan.records = records
        scan.snapshot.mpItemIndex = Dictionary(
            records.map { ($0.matchKey, $0.item) },
            uniquingKeysWith: { first, _ in first }
        )
        scan.snapshot.songs = records
            .map(\.track)
            .sorted { AppHelpers.sortsBefore($0.title, $1.title) }

        scan.byDateAdded = records.sorted { $0.dateAdded > $1.dateAdded }
        scan.byLastPlayed = records
            .filter { $0.lastPlayed != nil }
            .sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        scan.snapshot.recentlyAdded  = scan.byDateAdded.prefix(recentsLimit).map(\.track)
        scan.snapshot.recentlyPlayed = scan.byLastPlayed.prefix(recentsLimit).map(\.track)
        return scan
    }

    /// Groups the on-device library into albums, artists and playlists. Only the
    /// collections MusicKit failed to supply are built.
    @concurrent
    static func localCollections(
        from scan: LocalScan,
        needsAlbums: Bool,
        needsArtists: Bool,
        needsPlaylists: Bool,
        playableOnly: Bool
    ) async -> (albums: [AppAlbum], artists: [AppArtist], playlists: [AppPlaylist]) {
        let albums = needsAlbums ? groupedAlbums(scan.records) : []

        var artists: [AppArtist] = []
        if needsArtists {
            artists = Dictionary(grouping: scan.records, by: \.artistID)
                .values
                .compactMap { artistRecords -> AppArtist? in
                    // Grouping the artist's tracks into albums gives ArtistDetailView
                    // content without an (impossible) MusicKit round trip.
                    let artistAlbums = groupedAlbums(artistRecords)
                    guard let representative = artistRecords.min(by: albumOrder) else { return nil }
                    return AppArtist(from: representative.item, albums: artistAlbums)
                }
                .sorted { AppHelpers.sortsBefore($0.name, $1.name) }
        }

        var playlists: [AppPlaylist] = []
        if needsPlaylists {
            // Playlist membership cannot be derived from the song list, so this one
            // query stays. Tracks already built by the song scan are reused.
            let trackByID = Dictionary(
                scan.records.map { ($0.item.persistentID, $0.track) },
                uniquingKeysWith: { first, _ in first }
            )
            playlists = (MPMediaQuery.playlists().collections ?? [])
                .compactMap { collection -> AppPlaylist? in
                    guard let playlist = collection as? MPMediaPlaylist else { return nil }
                    let tracks = playlist.items.compactMap { item -> AppTrack? in
                        if let known = trackByID[item.persistentID] { return known }
                        guard isPlayable(item, playableOnly: playableOnly) else { return nil }
                        return AppTrack(from: item)
                    }
                    guard !tracks.isEmpty else { return nil }
                    return AppPlaylist(from: playlist, tracks: tracks)
                }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        return (albums, artists, playlists)
    }

    /// Disc then track number, the order an album's tracks are listed in.
    private static func albumOrder(_ lhs: LocalRecord, _ rhs: LocalRecord) -> Bool {
        if lhs.discNumber != rhs.discNumber { return lhs.discNumber < rhs.discNumber }
        if lhs.trackNumber != rhs.trackNumber { return lhs.trackNumber < rhs.trackNumber }
        return lhs.track.title.localizedCaseInsensitiveCompare(rhs.track.title) == .orderedAscending
    }

    private static func groupedAlbums(_ records: [LocalRecord]) -> [AppAlbum] {
        Dictionary(grouping: records, by: \.albumID)
            .values
            .compactMap { albumRecords -> AppAlbum? in
                let ordered = albumRecords.sorted(by: albumOrder)
                guard let representative = ordered.first else { return nil }
                return AppAlbum(from: representative.item, tracks: ordered.map(\.track))
            }
            .sorted { AppHelpers.sortsBefore($0.title, $1.title) }
    }

    // MARK: - Podcasts

    @concurrent
    static func scanPodcasts() async -> [PodcastShow] {
        let episodes = (MPMediaQuery.podcasts().items ?? []).map { item in
            (item: item,
             show: item.podcastTitle ?? item.albumTitle ?? "Unknown Podcast",
             added: item.dateAdded)
        }
        return Dictionary(grouping: episodes, by: \.show)
            .map { title, showEpisodes in
                PodcastShow(
                    title: title,
                    localEpisodes: showEpisodes.sorted { $0.added > $1.added }.map(\.item)
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: - Apple Music Library (MusicKit)

    struct MusicKitLibrary {
        var songs: [Song]
        var albums: [Album]
        var artists: [Artist]
        var playlists: [Playlist]
    }

    /// Fetches the four collections concurrently. They used to be requested one after
    /// another, so the load waited on the sum of four round trips instead of the longest.
    @concurrent
    static func fetchMusicKitLibrary() async throws -> MusicKitLibrary {
        async let songs     = libraryItems(Song.self,     limit: 25_000)
        async let albums    = libraryItems(Album.self,    limit: 5_000)
        async let artists   = libraryItems(Artist.self,   limit: 5_000)
        async let playlists = libraryItems(Playlist.self, limit: 2_000)
        return try await MusicKitLibrary(
            songs: songs, albums: albums, artists: artists, playlists: playlists
        )
    }

    @concurrent
    private static func libraryItems<Item: MusicLibraryRequestable>(
        _ type: Item.Type, limit: Int
    ) async throws -> [Item] {
        var request = MusicLibraryRequest<Item>()
        request.limit = limit
        return Array(try await request.response().items)
    }

    /// Maps the MusicKit responses into a snapshot, attaching the local MPMediaItem to
    /// each song up front so playback never has to run a title query later.
    @concurrent
    static func musicKitSnapshot(from library: MusicKitLibrary, local: LocalScan) async -> LibrarySnapshot {
        var snapshot = LibrarySnapshot()
        let index = local.snapshot.mpItemIndex

        snapshot.songs = library.songs.map { song in
            AppTrack(from: song).attaching(mpItem: index[matchKey(title: song.title, artist: song.artistName)])
        }
        snapshot.albums    = library.albums.map { AppAlbum(from: $0) }
        snapshot.artists   = library.artists.map { AppArtist(from: $0) }
        snapshot.playlists = library.playlists.map { AppPlaylist(from: $0) }

        // Recency lives in the on-device library, so order by MPMediaItem dates and use
        // the matching MusicKit song for its catalogue artwork where one exists.
        let songsByKey = Dictionary(
            snapshot.songs.map { (matchKey(title: $0.title, artist: $0.artistName), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        func upgraded(_ ordered: [LocalRecord]) -> [AppTrack] {
            var seen = Set<String>()
            var result: [AppTrack] = []
            for record in ordered where seen.insert(record.matchKey).inserted {
                result.append(songsByKey[record.matchKey] ?? record.track)
                if result.count == recentsLimit { break }
            }
            return result
        }
        snapshot.recentlyAdded  = upgraded(local.byDateAdded)
        snapshot.recentlyPlayed = upgraded(local.byLastPlayed)
        return snapshot
    }
}
