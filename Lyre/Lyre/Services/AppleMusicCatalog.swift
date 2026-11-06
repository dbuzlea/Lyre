//
//  AppleMusicCatalog.swift
//  Lyre
//

import Foundation
import MusicKit
import MediaPlayer
import OSLog

private let logger = Logger(subsystem: "com.pinkhatcreations.lyreapp", category: "AppleMusicCatalog")

// MARK: - Apple Music Catalogue
//
// What Apple Music's catalogue knows beyond the library, through MusicKit, the service
// Lyre already plays from:
//
//   an artist   their biography, top songs, latest release and similar artists
//   an album    its record label, copyright, Apple's write-up and the audio it comes in
//               (Dolby Atmos, Lossless, Hi-Res Lossless)
//   the charts  the most played songs and albums
//   search      songs, albums and artists for what's typed
//
// The library's own items seldom carry these, so the catalogue is searched for the same
// artist (the very same name) or album (the same title by the same artist). Answers are
// kept for as long as Lyre is open; nothing is stored.
//
// A catalogue song the library has is played from the library (`librarySong`); one it
// hasn't streams, with an Apple Music subscription (Docs/CATALOGUE-STREAMING.md), and
// can be added (`add(_:)`). Every request needs MusicKit enabled for the App ID.

@MainActor
@Observable
final class AppleMusicCatalog {
    static let shared = AppleMusicCatalog()

    struct ArtistDetails {
        var biography: String?
        var topSongs: [Song]
        var latestRelease: Album?
        var similarArtists: [Artist]
        /// Their albums, for the page of an artist the library hasn't.
        var albums: [Album] = []
    }

    struct AlbumDetails {
        var recordLabel: String?
        var copyright: String?
        var notes: String?
        var variants: [AudioVariant]
        var url: URL?
        var genres: [String] = []
        var releaseDate: Date?
        var isCompilation = false
        var isSingle = false
        /// The catalogue's album, for what's asked of it later (`loadMore`).
        var album: Album?
    }

    /// Other versions of an album (deluxe, remastered, live) and albums like it.
    struct AlbumMore {
        var otherVersions: [Album]
        var related: [Album]
    }

    struct Charts {
        var songs: [Song]
        var albums: [Album]
    }

    private(set) var artists: [String: ArtistDetails] = [:]
    private(set) var albums: [String: AlbumDetails] = [:]
    private(set) var moreByAlbum: [String: AlbumMore] = [:]
    private(set) var charts: Charts?
    @ObservationIgnored private var asked: Set<String> = []

    /// Whether the catalogue can be asked at all.
    static var isAvailable: Bool {
        !AppEnvironment.isUITesting && MusicAuthorization.currentStatus == .authorized
    }

    // MARK: Artists

    func details(forArtist name: String) -> ArtistDetails? {
        ArtistPhotos.key(for: name).flatMap { artists[$0] }
    }

    /// Looks up an artist, once per launch.
    func loadArtist(_ name: String) async {
        guard Self.isAvailable, let key = ArtistPhotos.key(for: name), asked.insert("artist:" + key).inserted else { return }
        do {
            var search = MusicCatalogSearchRequest(term: name, types: [Artist.self])
            search.limit = 5
            guard let found = try await search.response().artists.first(where: { ArtistPhotos.key(for: $0.name) == key }) else { return }
            let artist = try await found.with([.topSongs, .latestRelease, .similarArtists, .albums])
            artists[key] = ArtistDetails(biography: Self.plainText(artist.editorialNotes?.standard ?? artist.editorialNotes?.short),
                                         topSongs: await clean(Array(artist.topSongs?.prefix(10) ?? [])),
                                         latestRelease: artist.latestRelease,
                                         similarArtists: Array(artist.similarArtists?.prefix(12) ?? []),
                                         albums: await clean(Array(artist.albums?.prefix(25) ?? [])))
        } catch {
            asked.remove("artist:" + key)
            logger.debug("Artist details failed for \(name, privacy: .private): \(error.localizedDescription)")
        }
    }

    // MARK: Albums

    static func albumKey(title: String, artist: String) -> String {
        DeezerTempo.normalized(artist) + "|" + DeezerTempo.normalized(title)
    }

    func details(forAlbum album: AppAlbum) -> AlbumDetails? {
        albums[Self.albumKey(title: album.tapeTitle, artist: album.artistName)]
    }

    /// Looks up an album (not a playlist or show), once per launch. One from the
    /// catalogue already is the catalogue's; one from the library is searched for.
    func loadAlbum(_ album: AppAlbum) async {
        guard Self.isAvailable, album.hasAlbumInfo else { return }
        let key = Self.albumKey(title: album.tapeTitle, artist: album.artistName)
        guard asked.insert("album:" + key).inserted else { return }
        do {
            let found: Album
            if album.isCatalog, let catalogue = album.musicKitAlbum {
                found = catalogue
            } else {
                var search = MusicCatalogSearchRequest(term: "\(album.artistName) \(album.tapeTitle)", types: [Album.self])
                search.limit = 10
                let results = try await search.response().albums
                guard let match = results.first(where: { Self.albumKey(title: $0.title, artist: $0.artistName) == key }) else { return }
                found = match
            }
            albums[key] = AlbumDetails(recordLabel: found.recordLabelName,
                                       copyright: found.copyright,
                                       notes: Self.plainText(found.editorialNotes?.standard ?? found.editorialNotes?.short),
                                       variants: Self.badges(found.audioVariants ?? []),
                                       url: found.url,
                                       genres: Self.genres(found.genreNames),
                                       releaseDate: found.releaseDate,
                                       isCompilation: found.isCompilation ?? false,
                                       isSingle: found.isSingle ?? false,
                                       album: found)
        } catch {
            asked.remove("album:" + key)
            logger.debug("Album details failed for \(album.title, privacy: .private): \(error.localizedDescription)")
        }
    }

    /// Other versions and albums like it, once per launch, after `loadAlbum` (only
    /// asked for when Album Info opens: it's a request of its own).
    func loadMore(forAlbum album: AppAlbum) async {
        let key = Self.albumKey(title: album.tapeTitle, artist: album.artistName)
        guard Self.isAvailable, let found = albums[key]?.album, asked.insert("more:" + key).inserted else { return }
        do {
            let detailed = try await found.with([.otherVersions, .relatedAlbums])
            moreByAlbum[key] = AlbumMore(otherVersions: Array(detailed.otherVersions?.prefix(12) ?? []),
                                         related: Array(detailed.relatedAlbums?.prefix(12) ?? []))
        } catch {
            asked.remove("more:" + key)
            logger.debug("More for \(album.title, privacy: .private) failed: \(error.localizedDescription)")
        }
    }

    func more(forAlbum album: AppAlbum) -> AlbumMore? {
        moreByAlbum[Self.albumKey(title: album.tapeTitle, artist: album.artistName)]
    }

    /// The genres worth naming: Apple files everything under "Music" too.
    nonisolated static func genres(_ names: [String]) -> [String] {
        names.filter { $0 != "Music" }
    }

    /// The variants worth a badge, best first: Dolby Atmos, then Hi-Res Lossless, else
    /// Lossless (Hi-Res is Lossless too).
    static func badges(_ variants: [AudioVariant]) -> [AudioVariant] {
        var shown: [AudioVariant] = []
        if variants.contains(.dolbyAtmos) { shown.append(.dolbyAtmos) }
        if variants.contains(.highResolutionLossless) { shown.append(.highResolutionLossless) }
        else if variants.contains(.lossless) { shown.append(.lossless) }
        return shown
    }

    // MARK: Charts

    /// The most played songs and albums, once per launch.
    func loadCharts() async {
        guard Self.isAvailable, asked.insert("charts").inserted else { return }
        do {
            var request = MusicCatalogChartsRequest(kinds: [.mostPlayed], types: [Song.self, Album.self])
            request.limit = 25
            let response = try await request.response()
            charts = Charts(songs: await clean(Array(response.songCharts.first?.items ?? [])),
                            albums: await clean(Array(response.albumCharts.first?.items ?? [])))
        } catch {
            asked.remove("charts")
            logger.error("Charts failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Search

    struct SearchResults {
        var songs: [Song]
        var albums: [Album]
        var artists: [Artist]

        var isEmpty: Bool { songs.isEmpty && albums.isEmpty && artists.isEmpty }
    }

    /// What's worth asking the catalogue for: the query trimmed, two letters or more.
    static func searchTerm(_ query: String) -> String? {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.count >= 2 ? term : nil
    }

    /// Searches the catalogue for songs, albums and artists; nil when it can't be asked
    /// or the search fails.
    func search(_ query: String) async -> SearchResults? {
        guard let term = Self.searchTerm(query) else { return nil }
        guard Self.isAvailable else {
            logger.debug("Catalogue search skipped: Apple Music access is \(String(describing: MusicAuthorization.currentStatus), privacy: .public)")
            return nil
        }
        do {
            var search = MusicCatalogSearchRequest(term: term, types: [Song.self, Album.self, Artist.self])
            search.limit = 10
            let response = try await search.response()
            logger.debug("Catalogue search: \(response.songs.count) songs, \(response.albums.count) albums, \(response.artists.count) artists")
            return SearchResults(songs: Array(await clean(Array(response.songs)).prefix(8)),
                                 albums: await clean(Array(response.albums)),
                                 artists: Array(response.artists))
        } catch {
            logger.error("Catalogue search failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Forgets the charts and artists' top songs, so they're asked for again (after
    /// Clean Versions is turned on or off).
    func forgetSongLists() {
        charts = nil
        artists = [:]
        asked = asked.filter { !$0.hasPrefix("artist:") && $0 != "charts" }
    }

    // MARK: Suggestions

    /// What Apple Music suggests searching for as `query` is typed: each a term to show
    /// and the one to search. Empty when it can't be asked.
    func suggestions(for query: String) async -> [(display: String, search: String)] {
        guard let term = Self.searchTerm(query) else { return [] }
        #if DEBUG
        // `-SearchSuggestionSamples YES`: made-up suggestions, for UI tests (the
        // simulator can't reach Apple Music).
        if UserDefaults.standard.bool(forKey: "SearchSuggestionSamples") {
            return ["\(term) songs", "\(term) live"].map { ($0, $0) }
        }
        #endif
        guard Self.isAvailable else { return [] }
        var request = MusicCatalogSearchSuggestionsRequest(term: term)
        request.limit = 6
        let suggestions = (try? await request.response().suggestions) ?? []
        return suggestions.map { ($0.displayTerm, $0.searchTerm) }
    }

    // MARK: Clean Versions

    /// Whether the listener wants clean versions of Apple Music's explicit songs and
    /// albums (Settings: Clean Versions). The library's own aren't changed.
    static var prefersClean: Bool { UserDefaults.standard.bool(forKey: ThemeSettings.cleanVersionsKey) }

    /// `songs` with each explicit one swapped for its clean version, by Apple Music's
    /// `restrict=explicit`, and any with none left out. As they are when clean versions
    /// aren't wanted, or none is explicit.
    func clean(_ songs: [Song]) async -> [Song] {
        await clean(songs, path: "songs") { $0.contentRating == .explicit }
    }

    /// The same for albums.
    func clean(_ albums: [Album]) async -> [Album] {
        await clean(albums, path: "albums") { $0.contentRating == .explicit }
    }

    private func clean<Item: MusicItem & Decodable>(_ items: [Item], path: String,
                                                    isExplicit: (Item) -> Bool) async -> [Item] {
        guard Self.prefersClean, Self.isAvailable else { return items }
        let explicit = items.filter(isExplicit)
        guard !explicit.isEmpty else { return items }
        var substitutes: [MusicItemID: Item] = [:]
        do {
            let storefront = try await MusicDataRequest.currentCountryCode
            var components = URLComponents(string: "https://api.music.apple.com/v1/catalog/\(storefront)/\(path)")!
            components.queryItems = [URLQueryItem(name: "ids", value: explicit.map(\.id.rawValue).joined(separator: ",")),
                                     URLQueryItem(name: "restrict", value: "explicit")]
            let data = try await MusicDataRequest(urlRequest: URLRequest(url: components.url!)).response().data
            let found = try JSONDecoder().decode(CatalogResponse<Item>.self, from: data).data
            // Answered in the order asked; a clean version has an ID of its own.
            for (original, answer) in zip(explicit, found) where !isExplicit(answer) {
                substitutes[original.id] = answer
            }
        } catch {
            logger.debug("Clean versions failed: \(String(describing: error), privacy: .public)")
        }
        return items.compactMap { isExplicit($0) ? substitutes[$0.id] : $0 }
    }

    // MARK: The library

    /// The library's copy of a catalogue song: the same title by the same artist, of
    /// much the same length. Looked up in the service's title index.
    static func librarySong(title: String, artist: String, duration: TimeInterval?, explicit: Bool? = nil,
                            in musicService: MusicService) -> AppTrack? {
        librarySong(title: title, artist: artist, duration: duration, explicit: explicit,
                    in: musicService.librarySongs(normalizedTitle: DeezerTempo.normalized(title)))
    }

    /// The same, among `songs`. With `explicit` (the catalogue song's rating), only the
    /// same version counts: a clean song isn't the library's explicit one.
    static func librarySong(title: String, artist: String, duration: TimeInterval?, explicit: Bool? = nil,
                            in songs: [AppTrack]) -> AppTrack? {
        let wantedTitle = DeezerTempo.normalized(title), wantedArtist = DeezerTempo.normalized(artist)
        return songs.first { track in
            guard DeezerTempo.normalized(track.title) == wantedTitle else { return false }
            if let explicit, track.isExplicit != explicit { return false }
            let theirs = DeezerTempo.normalized(track.artistName)
            guard theirs.contains(wantedArtist) || wantedArtist.contains(theirs) else { return false }
            if let duration, duration > 0, track.duration > 0 {
                return abs(track.duration - duration) <= DeezerTempo.lengthTolerance
            }
            return true
        }
    }

    /// The library's copy of a catalogue album: the same title by the same artist.
    static func libraryAlbum(title: String, artist: String, in albums: [AppAlbum]) -> AppAlbum? {
        let key = albumKey(title: title, artist: artist)
        return albums.first { albumKey(title: $0.tapeTitle, artist: $0.artistName) == key }
    }

    enum AddError: LocalizedError {
        case needsSubscription
        var errorDescription: String? { String(localized: "catalog.add.needsSubscription") }
    }

    /// Adds a song or album to the library. Needs an Apple Music subscription; without
    /// one, Apple's trial is offered for it.
    func add<Item: MusicLibraryAddable>(_ item: Item, subscribed: Bool) async throws {
        guard subscribed else {
            SubscriptionOffer.shared.offer(itemID: item.id.rawValue, toPlay: false)
            throw AddError.needsSubscription
        }
        try await MusicLibrary.shared.add(item)
        UsageStats.shared.used(.addToLibrary)
    }

    // MARK: Text

    /// Apple's write-ups carry a little markup (`<i>…</i>`, `<br />`): plain text, with
    /// line breaks kept.
    static func plainText(_ html: String?) -> String? {
        guard var text = html, !text.isEmpty else { return nil }
        text = text.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        for (entity, character) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// A catalogue answer's resources (`{"data": […]}`).
private struct CatalogResponse<Item: Decodable>: Decodable {
    let data: [Item]
}

extension AppTrack {
    /// Marked explicit: as Apple Music rates it where it does (a clean version is rated
    /// clean), else as the file says.
    var isExplicit: Bool {
        if let rating = musicKitSong?.contentRating { return rating == .explicit }
        return mpItem?.isExplicitItem == true
    }

    /// How many times it's been played, as the library counts.
    var playCount: Int {
        max(musicKitSong?.playCount ?? 0, mpItem?.playCount ?? 0)
    }

    /// The most played songs, most first: the top `limit` played at least twice.
    static func mostPlayed(_ songs: [AppTrack], limit: Int = 100,
                           count: (AppTrack) -> Int = { $0.playCount }) -> [AppTrack] {
        songs.map { ($0, count($0)) }
            .filter { $0.1 >= 2 }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : AppHelpers.sortsBefore($0.0.title, $1.0.title) }
            .prefix(limit).map(\.0)
    }
}
