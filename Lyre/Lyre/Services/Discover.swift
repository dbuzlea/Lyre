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
//   Made for You     Apple Music's recommendations for the listener, a section per
//                    group; they learn from what's played and favourited (Loves) in
//                    Lyre too, since Lyre plays through Apple Music
//   Recently Played  the albums, playlists and stations played lately, on any device
//   New Releases     the latest releases of the artists played most (those the library
//                    has most of, before anything's been played), from the past year,
//                    newest first
//   Replay           the listener's latest Apple Music Replay: their top songs as a
//                    mixtape, and their top albums
//   Charts           each songs chart as a mixtape (the most played, the daily global
//                    top), then the albums and playlists charts (city charts among them)
//   Genres           each of Apple Music's genres as a mixtape of its top songs, filled
//                    in when it's opened (`tracks(forGenre:in:)`)
//
// A station is a mixtape of one: the station itself, which streams by its ID as any
// Apple Music song does, so every player plays it as it plays a playlist.
//
// Everything is an AppAlbum, as the shelves hold: an album (the library's copy where it
// has one, else the catalogue's, which streams), or a playlist as a mixtape. Asked for
// the first time Discover is shown, a section at a time as each answer arrives, and
// Made for You and New Releases again when Lyre comes back to the front after Apple
// Music has made its suggestions again (`refreshIfDue`); nothing is stored. `-DiscoverSamples YES` (debug builds) fills it with
// placeholders instead, for UI tests, which can't reach Apple Music.

nonisolated struct DiscoverSection: Identifiable, Hashable {
    enum Kind: Int, CaseIterable {
        case madeForYou, recentlyPlayed, newReleases, replay, charts, genres
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
            group.addTask { await (.recentlyPlayed, self.recentlyPlayed(library: library)) }
            group.addTask { await (.newReleases, self.newReleases(in: musicService, library: library)) }
            group.addTask { await (.replay, self.replay(in: musicService, library: library)) }
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

    /// Forgets everything asked for, so the next time Discover shows it's asked again.
    func forget() async {
        guard !isLoading else { return }
        hasLoaded = false
        byKind = [:]
        genreTracks = [:]
        publish()
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
                    case .station(let station): return Self.station(station)
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

    // MARK: Recently Played

    /// The albums, playlists and stations played lately, on any of the listener's devices.
    private func recentlyPlayed(library: [String: AppAlbum]) async -> [DiscoverSection] {
        do {
            var request = MusicRecentlyPlayedContainerRequest()
            request.limit = Self.itemsPerSection
            let items = try await request.response().items.compactMap { item -> AppAlbum? in
                switch item {
                case .album(let album): return Self.album(album, library: library)
                case .playlist(let playlist): return Self.mixtape(playlist)
                case .station(let station): return Self.station(station)
                @unknown default: return nil
                }
            }
            guard !items.isEmpty else { return [] }
            return [DiscoverSection(id: "discover:recent", title: String(localized: "menu.recentlyPlayed"),
                                    kind: .recentlyPlayed, items: items)]
        } catch {
            logger.error("Recently played containers failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    // MARK: Replay

    /// The listener's latest Apple Music Replay (`/v1/me/music-summaries`): their top
    /// songs, as a mixtape, and their top albums. Nothing for someone with too little
    /// listening for one.
    private func replay(in musicService: MusicService, library: [String: AppAlbum]) async -> [DiscoverSection] {
        do {
            var components = URLComponents(string: "https://api.music.apple.com/v1/me/music-summaries")!
            components.queryItems = [URLQueryItem(name: "filter[year]", value: "latest"),
                                     URLQueryItem(name: "views", value: "top-songs,top-albums")]
            let response = try await MusicDataRequest(urlRequest: URLRequest(url: components.url!)).response()
            guard let summary = try Self.replaySummary(from: response.data) else { return [] }
            let title = summary.year.map { String(format: String(localized: "discover.replay.year"), $0) }
                ?? String(localized: "discover.replay")
            var items: [AppAlbum] = []
            let songs = await AppleMusicCatalog.shared.clean(summary.songs)
            if !songs.isEmpty {
                let tracks = songs.map { Self.track($0, in: musicService) }
                items.append(AppAlbum(mixtape: AppPlaylist(id: "discover:replay:songs", name: title,
                                                           curatorName: String(localized: "catalog.search.title"),
                                                           preloadedTracks: tracks)))
            }
            items += summary.albums.prefix(Self.itemsPerSection).map { Self.album($0, library: library) }
            guard !items.isEmpty else { return [] }
            return [DiscoverSection(id: "discover:replay", title: title, kind: .replay, items: items)]
        } catch {
            logger.debug("Replay failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    struct ReplaySummary {
        var year: Int?
        var songs: [Song]
        var albums: [Album]
    }

    /// The first summary in a music-summaries answer: its year, top songs and albums.
    nonisolated static func replaySummary(from data: Data) throws -> ReplaySummary? {
        struct Response: Decodable {
            struct Summary: Decodable {
                struct Attributes: Decodable { let year: Int? }
                struct Views: Decodable {
                    struct Songs: Decodable { let data: [Song] }
                    struct Albums: Decodable { let data: [Album] }
                    let topSongs: Songs?
                    let topAlbums: Albums?
                    enum CodingKeys: String, CodingKey {
                        case topSongs = "top-songs"
                        case topAlbums = "top-albums"
                    }
                }
                let attributes: Attributes?
                let views: Views?
            }
            let data: [Summary]
        }
        guard let summary = try JSONDecoder().decode(Response.self, from: data).data.first else { return nil }
        return ReplaySummary(year: summary.attributes?.year,
                             songs: summary.views?.topSongs?.data ?? [],
                             albums: summary.views?.topAlbums?.data ?? [])
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
            // The most played, and the daily global and city tops (which come as playlists).
            var request = MusicCatalogChartsRequest(kinds: [.mostPlayed, .dailyGlobalTop, .cityTop],
                                                    types: [Song.self, Album.self, Playlist.self])
            request.limit = 25
            let response = try await request.response()
            var sections: [DiscoverSection] = []
            // Each songs chart a mixtape; the most played is the Top Songs smart list.
            var songCharts: [AppAlbum] = []
            for chart in response.songCharts where !chart.items.isEmpty {
                let tracks = await AppleMusicCatalog.shared.clean(Array(chart.items)).map { Self.track($0, in: musicService) }
                songCharts.append(chart.kind == .mostPlayed
                    ? SmartList.topCharts.album(tracks)
                    : AppAlbum(mixtape: AppPlaylist(id: "discover:chart:" + chart.id, name: chart.title,
                                                    curatorName: String(localized: "catalog.search.title"),
                                                    preloadedTracks: tracks)))
            }
            if !songCharts.isEmpty {
                sections.append(DiscoverSection(id: "discover:charts:songs", title: SmartList.topCharts.title,
                                                kind: .charts, items: songCharts))
            }
            for (index, chart) in response.albumCharts.enumerated() where !chart.items.isEmpty {
                let albums = await AppleMusicCatalog.shared.clean(Array(chart.items.prefix(Self.itemsPerSection)))
                sections.append(DiscoverSection(id: "discover:charts:albums:\(index)",
                                                title: chart.kind == .mostPlayed ? String(localized: "catalog.charts.albums") : chart.title,
                                                kind: .charts,
                                                items: albums.map { Self.album($0, library: library) }))
            }
            for (index, chart) in response.playlistCharts.enumerated() where !chart.items.isEmpty {
                sections.append(DiscoverSection(id: "discover:charts:playlists:\(index)",
                                                title: chart.kind == .mostPlayed ? String(localized: "discover.topPlaylists") : chart.title,
                                                kind: .charts,
                                                items: chart.items.prefix(Self.itemsPerSection).map(Self.mixtape)))
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
            let songs = await AppleMusicCatalog.shared.clean(Array(try await request.response().songCharts.first?.items ?? []))
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

    /// A station, as a mixtape of one: the station, which streams by its ID.
    nonisolated static func station(_ station: Station) -> AppAlbum {
        let id = station.id.rawValue
        let track = AppTrack(id: stationPlaylistID(id), title: station.name,
                             artistName: station.stationProviderName ?? String(localized: "discover.station"),
                             albumTitle: "", duration: 0, storeID: id)
        return AppAlbum(mixtape: AppPlaylist(id: stationPlaylistID(id), name: station.name,
                                             curatorName: String(localized: "discover.station"),
                                             preloadedTracks: [track]))
    }

    nonisolated static func stationPlaylistID(_ id: String) -> String { "station:" + id }

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
