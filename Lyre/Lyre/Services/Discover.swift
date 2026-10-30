//
//  Discover.swift
//  Lyre
//

import Foundation
import MusicKit
import OSLog

private let logger = Logger(subsystem: "com.pinkhatcreations.lyreapp", category: "Discover")

// MARK: - Discover
//
// What Apple Music offers beyond the library, in a place of its own in every player
// (Liquid's Discover page, the DISCOVER shelf of the Spool, Disc and Gramophone, the
// classic player's Discover row):
//
//   Made for You   Apple Music's recommendations for the listener, a section per group;
//                  they learn from what's played and loved (Loves) in Lyre too, since
//                  Lyre plays through Apple Music
//   New Releases   the latest releases of the artists played most (those the library
//                  has most of, before anything's been played), from the past year,
//                  newest first
//   Charts         the top songs as a mixtape, then the most played albums and playlists
//   Genres         each of Apple Music's genres as a mixtape of its top songs, filled in
//                  when it's opened (`tracks(forGenre:in:)`)
//
// Everything is an AppAlbum, as the shelves hold: an album (the library's copy where it
// has one, else the catalogue's, which streams), or a playlist as a mixtape. Asked for
// the first time Discover is shown, a section at a time as each answer arrives, and
// Made for You and New Releases again when Lyre comes back to the front after Apple
// Music has made its suggestions again (`refreshIfDue`); nothing is stored. `-DiscoverSamples YES` (debug builds) fills it with
// placeholders instead, for UI tests, which can't reach Apple Music.

nonisolated struct DiscoverSection: Identifiable, Hashable {
    enum Kind: Int, CaseIterable {
        case madeForYou, newReleases, charts, genres
    }

    let id: String
    let title: String
    let kind: Kind
    let items: [AppAlbum]

    static func == (lhs: DiscoverSection, rhs: DiscoverSection) -> Bool {
        lhs.id == rhs.id && lhs.items.map(\.id) == rhs.items.map(\.id)
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// A genre's mixtape: its playlist's ID, from which the genre is known again.
    static func genrePlaylistID(_ genreID: String) -> String { "discover:genre:" + genreID }

    static func genreID(ofPlaylist id: String) -> String? {
        id.hasPrefix("discover:genre:") ? String(id.dropFirst(15)) : nil
    }

    /// Every section's items in one run, as a shelf holds them, each once.
    static func shelfItems(_ sections: [DiscoverSection]) -> [AppAlbum] {
        var seen: Set<String> = []
        return sections.flatMap(\.items).filter { seen.insert($0.id).inserted }
    }
}

@MainActor
@Observable
final class Discover {
    static let shared = Discover()

    /// What's arrived so far, in the order of `DiscoverSection.Kind`.
    private(set) var sections: [DiscoverSection] = []
    /// `sections`' items in one run, for the shelves; kept with them, not worked out
    /// on every redraw.
    private(set) var shelfItems: [AppAlbum] = []
    /// Asking Apple Music, with nothing back yet.
    private(set) var isLoading = false

    @ObservationIgnored private var hasLoaded = false
    /// When Apple Music makes its suggestions again: the soonest of the groups' times.
    @ObservationIgnored private var nextRefresh: Date?
    @ObservationIgnored private var byKind: [DiscoverSection.Kind: [DiscoverSection]] = [:]
    @ObservationIgnored private var genres: [String: Genre] = [:]
    @ObservationIgnored private var genreTracks: [String: [AppTrack]] = [:]

    /// How many of each kind: enough to browse, few enough to ask for at once.
    private static let itemsPerSection = 12
    private static let newReleaseArtists = 15

    /// What an empty Discover says: still asking, nothing found, or no access to ask.
    static var emptyText: String {
        if shared.isLoading { return String(localized: "discover.loading") }
        return AppleMusicCatalog.isAvailable ? String(localized: "discover.empty") : String(localized: "discover.needsAccess")
    }

    /// Asks Apple Music for everything, once per launch (again later if it couldn't be
    /// asked: no access yet).
    func load(in musicService: MusicService) async {
        guard !hasLoaded else { return }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "DiscoverSamples") {
            hasLoaded = true
            for section in Self.samples { byKind[section.kind, default: []].append(section) }
            publish()
            return
        }
        #endif
        guard AppleMusicCatalog.isAvailable else { return }
        hasLoaded = true
        isLoading = true
        // The library's albums by name, built off the main thread, so a catalogue album
        // the library has opens as the library's.
        let albums = musicService.albums
        let library = await Task.detached(priority: .utility) { Self.albumIndex(albums) }.value
        await withTaskGroup(of: (DiscoverSection.Kind, [DiscoverSection]).self) { group in
            group.addTask { await (.madeForYou, self.madeForYou(library: library)) }
            group.addTask { await (.newReleases, self.newReleases(in: musicService, library: library)) }
            group.addTask { await (.charts, self.charts(in: musicService, library: library)) }
            group.addTask { await (.genres, self.genreSections()) }
            for await (kind, found) in group {
                byKind[kind] = found
                isLoading = false
                publish()
            }
        }
        isLoading = false
    }

    /// Asks again for what's made for the listener, once Apple Music has made it again
    /// (or, with no time given, a day on): Made for You, and New Releases, whose most
    /// played artists may have changed. Only once Discover's been shown.
    func refreshIfDue(in musicService: MusicService, now: Date = .now) async {
        guard hasLoaded, !isLoading, Self.isDue(nextRefresh, now: now), AppleMusicCatalog.isAvailable else { return }
        nextRefresh = now.addingTimeInterval(Self.fallbackRefresh)
        let albums = musicService.albums
        let library = await Task.detached(priority: .utility) { Self.albumIndex(albums) }.value
        async let made = madeForYou(library: library)
        async let new = newReleases(in: musicService, library: library)
        let (madeForYou, newReleases) = await (made, new)
        if !madeForYou.isEmpty { byKind[.madeForYou] = madeForYou }
        if !newReleases.isEmpty { byKind[.newReleases] = newReleases }
        publish()
    }

    /// How long suggestions are kept when Apple Music doesn't say.
    nonisolated static let fallbackRefresh: TimeInterval = 86_400

    nonisolated static func isDue(_ refresh: Date?, now: Date) -> Bool {
        guard let refresh else { return false }
        return now >= refresh
    }

    private func publish() {
        let ordered = DiscoverSection.Kind.allCases.flatMap { byKind[$0] ?? [] }
        guard ordered != sections else { return }
        sections = ordered
        shelfItems = DiscoverSection.shelfItems(ordered)
    }

    // MARK: Made for You

    private func madeForYou(library: [String: AppAlbum]) async -> [DiscoverSection] {
        do {
            var request = MusicPersonalRecommendationsRequest()
            request.limit = 8
            let response = try await request.response()
            nextRefresh = response.recommendations.compactMap(\.nextRefreshDate).min()
                ?? Date.now.addingTimeInterval(Self.fallbackRefresh)
            return response.recommendations.compactMap { recommendation in
                let items = recommendation.items.prefix(Self.itemsPerSection).compactMap { item -> AppAlbum? in
                    switch item {
                    case .album(let album): return Self.album(album, library: library)
                    case .playlist(let playlist): return Self.mixtape(playlist)
                    // A station has no songs to list; Apple Music plays those.
                    case .station: return nil
                    @unknown default: return nil
                    }
                }
                guard !items.isEmpty else { return nil }
                return DiscoverSection(id: "discover:made:" + recommendation.id.rawValue,
                                       title: recommendation.title ?? String(localized: "discover.madeForYou"),
                                       kind: .madeForYou, items: items)
            }
        } catch {
            logger.error("Recommendations failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    // MARK: New Releases

    private func newReleases(in musicService: MusicService, library: [String: AppAlbum]) async -> [DiscoverSection] {
        let shelf = musicService.shelfArtists
        let names = await Task.detached(priority: .utility) {
            Self.mostPlayedArtists(shelf, limit: Self.newReleaseArtists)
        }.value
        await withTaskGroup(of: Void.self) { group in
            for name in names { group.addTask { await AppleMusicCatalog.shared.loadArtist(name) } }
        }
        let releases = names.compactMap { AppleMusicCatalog.shared.details(forArtist: $0)?.latestRelease }
        let items = Self.recent(releases, now: .now).map { Self.album($0, library: library) }
        guard !items.isEmpty else { return [] }
        return [DiscoverSection(id: "discover:new", title: String(localized: "discover.newReleases"),
                                kind: .newReleases, items: items)]
    }

    /// The artists played most, by their songs' plays added up; those with more songs
    /// first where plays are level (as all are before anything's been played).
    nonisolated static func mostPlayedArtists(_ artists: [AppAlbum], limit: Int,
                                              plays: (AppTrack) -> Int = { $0.playCount }) -> [String] {
        artists
            .map { artist in (artist.title, artist.preloadedTracks.reduce(0) { $0 + plays($1) }, artist.preloadedTracks.count) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 > $1.2 }
            .prefix(limit).map(\.0)
    }

    /// Releases from the past year, newest first, each once.
    nonisolated static func recent(_ albums: [Album], now: Date) -> [Album] {
        let since = now.addingTimeInterval(-365 * 86_400)
        var seen: Set<MusicItemID> = []
        return albums
            .filter { ($0.releaseDate ?? .distantPast) >= since && seen.insert($0.id).inserted }
            .sorted { ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast) }
    }

    // MARK: Charts

    private func charts(in musicService: MusicService, library: [String: AppAlbum]) async -> [DiscoverSection] {
        do {
            var request = MusicCatalogChartsRequest(kinds: [.mostPlayed], types: [Song.self, Album.self, Playlist.self])
            request.limit = 25
            let response = try await request.response()
            var sections: [DiscoverSection] = []
            let songs = Array(response.songCharts.first?.items ?? [])
            if !songs.isEmpty {
                let tracks = songs.map { Self.track($0, in: musicService) }
                sections.append(DiscoverSection(id: "discover:charts:songs", title: SmartList.topCharts.title,
                                                kind: .charts, items: [SmartList.topCharts.album(tracks)]))
            }
            let albums = (response.albumCharts.first?.items ?? []).prefix(Self.itemsPerSection)
            if !albums.isEmpty {
                sections.append(DiscoverSection(id: "discover:charts:albums", title: String(localized: "catalog.charts.albums"),
                                                kind: .charts, items: albums.map { Self.album($0, library: library) }))
            }
            let playlists = (response.playlistCharts.first?.items ?? []).prefix(Self.itemsPerSection)
            if !playlists.isEmpty {
                sections.append(DiscoverSection(id: "discover:charts:playlists", title: String(localized: "discover.topPlaylists"),
                                                kind: .charts, items: playlists.map(Self.mixtape)))
            }
            return sections
        } catch {
            logger.error("Discover charts failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    // MARK: Genres

    private func genreSections() async -> [DiscoverSection] {
        do {
            let found = try await MusicCatalogResourceRequest<Genre>().response().items
            // Apple files everything under "Music" too.
            let named = found.filter { !AppleMusicCatalog.genres([$0.name]).isEmpty }
            for genre in named { genres[genre.id.rawValue] = genre }
            let items = named.map { genre in
                AppAlbum(mixtape: AppPlaylist(id: DiscoverSection.genrePlaylistID(genre.id.rawValue), name: genre.name,
                                              curatorName: String(localized: "catalog.search.title")))
            }
            guard !items.isEmpty else { return [] }
            return [DiscoverSection(id: "discover:genres", title: String(localized: "discover.genres"),
                                    kind: .genres, items: items)]
        } catch {
            logger.error("Genres failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// A genre's top songs, asked for when its mixtape is opened, once per launch.
    func tracks(forGenre id: String, in musicService: MusicService) async -> [AppTrack] {
        if let known = genreTracks[id] { return known }
        guard let genre = genres[id] else { return [] }
        do {
            var request = MusicCatalogChartsRequest(genre: genre, kinds: [.mostPlayed], types: [Song.self])
            request.limit = 25
            let songs = try await request.response().songCharts.first?.items ?? []
            let tracks = songs.map { Self.track($0, in: musicService) }
            genreTracks[id] = tracks
            return tracks
        } catch {
            logger.error("Genre chart failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    // MARK: Items

    /// The library's albums by artist and title, as `AppleMusicCatalog.albumKey` has them.
    nonisolated static func albumIndex(_ albums: [AppAlbum]) -> [String: AppAlbum] {
        Dictionary(albums.map { (key(title: $0.tapeTitle, artist: $0.artistName), $0) }, uniquingKeysWith: { first, _ in first })
    }

    nonisolated private static func key(title: String, artist: String) -> String {
        DeezerTempo.normalized(artist) + "|" + DeezerTempo.normalized(title)
    }

    /// A catalogue album: the library's copy, else the catalogue's, which streams.
    nonisolated static func album(_ album: Album, library: [String: AppAlbum]) -> AppAlbum {
        library[key(title: album.title, artist: album.artistName)] ?? AppAlbum(from: album, catalog: true)
    }

    /// A catalogue playlist as a mixtape; its songs are asked for when it's opened.
    nonisolated static func mixtape(_ playlist: Playlist) -> AppAlbum {
        AppAlbum(mixtape: AppPlaylist(from: playlist))
    }

    /// A catalogue song: the library's copy, else streamed.
    private static func track(_ song: Song, in musicService: MusicService) -> AppTrack {
        AppleMusicCatalog.librarySong(title: song.title, artist: song.artistName, duration: song.duration,
                                      explicit: song.contentRating.map { $0 == .explicit }, in: musicService)
            ?? AppTrack(from: song, catalog: true)
    }

    #if DEBUG
    /// Placeholders for UI tests: an album and a playlist in a Made for You group, and
    /// a genre. Their songs have nothing behind them, so they list but won't play.
    static var samples: [DiscoverSection] {
        let tracks = (1...6).map { number in
            AppTrack(id: "discover-sample-\(number)", title: "Discover Song \(number)", artistName: "Lyre",
                     albumTitle: "Discover Album", duration: 180)
        }
        let album = AppAlbum(id: "discover-sample-album", title: "Discover Album", artistName: "Lyre",
                             preloadedTracks: tracks)
        let playlist = AppAlbum(mixtape: AppPlaylist(id: "discover-sample-mix", name: "Discover Mix",
                                                     curatorName: "Apple Music", preloadedTracks: tracks))
        let genre = AppAlbum(mixtape: AppPlaylist(id: DiscoverSection.genrePlaylistID("sample"), name: "Sample Genre",
                                                  curatorName: "Apple Music", preloadedTracks: tracks))
        return [DiscoverSection(id: "discover:made:sample", title: String(localized: "discover.madeForYou"),
                                kind: .madeForYou, items: [album, playlist]),
                DiscoverSection(id: "discover:genres", title: String(localized: "discover.genres"),
                                kind: .genres, items: [genre])]
    }
    #endif
}
