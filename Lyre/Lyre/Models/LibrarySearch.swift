//
//  LibrarySearch.swift
//  Lyre
//

import Foundation
import MusicKit
import os

// MARK: - Library Search
//
// Finding things in the library by typing, shared by every player style:
//
// • Classic — the Search screen lists matching artists, albums, songs, playlists and
//             podcasts, which the wheel scrolls and plays (see SearchView).
// • Spool and Gramophone — the search field over the shelf dividers narrows the rack
//             or the crate to the tapes and records that match (`shelfMatches`).
//
// A query matches when every word in it appears somewhere in an item's text, ignoring
// case and accents, so "beyonce lemonade" finds "Lemonade" by Beyoncé. Only the library
// MusicService has already loaded is searched; nothing goes to the network, which is
// what lets the results follow every keystroke.

/// One row of the Classic player's search results.
nonisolated enum LibrarySearchResult: Identifiable, Hashable {
    case artist(AppArtist)
    case album(AppAlbum)
    case song(AppTrack)
    case playlist(AppPlaylist)
    case podcast(PodcastShow)

    var id: String {
        switch self {
        case .artist(let artist):     return "artist.\(artist.id)"
        case .album(let album):       return "album.\(album.id)"
        case .song(let track):        return "song.\(track.id)"
        case .playlist(let playlist): return "playlist.\(playlist.id)"
        case .podcast(let show):      return "podcast.\(show.id)"
        }
    }

    var title: String {
        switch self {
        case .artist(let artist):     return artist.name
        case .album(let album):       return album.title
        case .song(let track):        return track.title
        case .playlist(let playlist): return playlist.name
        case .podcast(let show):      return show.title
        }
    }

    /// What kind of thing the row is, and who it's by where that's known.
    var subtitle: String {
        func byline(_ kind: String, _ name: String?) -> String {
            guard let name, !name.isEmpty else { return kind }
            return "\(kind) · \(name)"
        }
        // Apple Music's, streamed rather than the library's.
        let appleMusic = String(localized: "catalog.search.title")
        switch self {
        case .artist:                 return String(localized: "search.kind.artist")
        case .album(let album) where album.isCatalog:
            return byline(String(localized: "search.kind.album") + " · " + appleMusic, album.artistName)
        case .song(let track) where track.isStreamOnly:
            return byline(String(localized: "search.kind.song") + " · " + appleMusic, track.artistName)
        case .album(let album):       return byline(String(localized: "search.kind.album"), album.artistName)
        case .song(let track):        return byline(String(localized: "search.kind.song"), track.artistName)
        case .playlist(let playlist): return byline(String(localized: "search.kind.playlist"), playlist.curatorName)
        case .podcast:                return String(localized: "search.kind.podcast")
        }
    }

    var systemImage: String {
        switch self {
        case .artist:   return "music.mic"
        case .album:    return "square.stack"
        case .song:     return "music.note"
        case .playlist: return "music.note.list"
        case .podcast:  return "mic.fill"
        }
    }

    var song: AppTrack? {
        if case .song(let track) = self { return track }
        return nil
    }
}

/// What the search field leaves on each shelf of the Spool's rack or the Gramophone's
/// crate.
struct ShelfSearchMatches: Equatable {
    /// The search these are the matches for.
    var query = ""
    var albums: [AppAlbum] = []
    var artists: [AppAlbum] = []
    var mixtapes: [AppAlbum] = []
    var podcasts: [AppAlbum] = []
    /// Apple Music's albums for the query that the library hasn't, streamed when played.
    var appleMusic: [AppAlbum] = []

    func items(on shelf: SpoolShelf) -> [AppAlbum] {
        switch shelf {
        case .albums:     return albums
        case .artists:    return artists
        case .mixtapes:   return mixtapes
        case .podcasts:   return podcasts
        case .appleMusic: return appleMusic
        // A search looks through the library, not Discover.
        case .discover:   return []
        }
    }

    /// The dividers to show: the library's shelves, and Apple Music's when it has any.
    var shelves: [SpoolShelf] {
        appleMusic.isEmpty ? SpoolShelf.library : SpoolShelf.library + [.appleMusic]
    }

    /// The first shelf with anything on it, when `shelf` has nothing: where the rack
    /// should turn to so a search never lands on an empty shelf while another has hits.
    /// The library's shelves come first.
    func shelfWithMatches(preferring shelf: SpoolShelf) -> SpoolShelf? {
        guard items(on: shelf).isEmpty else { return nil }
        return shelves.first { !items(on: $0).isEmpty }
    }
}

nonisolated enum LibrarySearch {
    /// Most rows of each kind the Classic results list. A short query can match much of
    /// a large library, and nobody scrolls a wheel through a thousand songs.
    static let songLimit = 100
    static let collectionLimit = 50

    /// The query's words, folded for comparison. Empty when there's nothing to search for.
    static func terms(_ query: String) -> [String] {
        fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Whether every term appears in at least one of `fields`.
    static func matches(_ terms: [String], _ fields: String?...) -> Bool {
        guard !terms.isEmpty else { return false }
        let text = fold(fields.compactMap { $0 }.joined(separator: " "))
        return terms.allSatisfy { text.contains($0) }
    }

    /// Whether `title` starts with the query, which puts it ahead of rows that only
    /// contain it somewhere.
    static func startsWith(_ terms: [String], _ title: String) -> Bool {
        guard let first = terms.first else { return false }
        return fold(title).hasPrefix(first)
    }

    /// Folded once per text and remembered: every keystroke searches the whole library
    /// again, and folding is the slow part.
    private static func fold(_ text: String) -> String {
        if let known = folded.withLock({ $0[text] }) { return known }
        let result = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        folded.withLock { cache in
            if cache.count > 80_000 { cache.removeAll(keepingCapacity: true) }
            cache[text] = result
        }
        return result
    }

    private static let folded = OSAllocatedUnfairLock<[String: String]>(initialState: [:])

    /// Matches first by whether their title starts with the query, otherwise in library order.
    private static func ranked<T>(_ items: [T], _ terms: [String], limit: Int, title: (T) -> String) -> [T] {
        let (leading, rest) = items.reduce(into: ([T](), [T]())) { result, item in
            if startsWith(terms, title(item)) { result.0.append(item) } else { result.1.append(item) }
        }
        return Array((leading + rest).prefix(limit))
    }

    // MARK: Classic

    /// Every kind of match, in the order the iPod listed them: artists, albums, songs,
    /// then playlists and podcasts.
    @MainActor
    static func results(for query: String, in musicService: MusicService) -> [LibrarySearchResult] {
        let terms = terms(query)
        guard !terms.isEmpty else { return [] }

        let artists = musicService.artists.filter { matches(terms, $0.name) }
        let albums = musicService.albums.filter { matches(terms, $0.title, $0.artistName) }
        let songs = musicService.songs.filter { matches(terms, $0.title, $0.artistName, $0.albumTitle) }
        let playlists = musicService.playlists.filter { matches(terms, $0.name, $0.curatorName) }
        let podcasts = musicService.podcastShows.filter { matches(terms, $0.title) }

        return ranked(artists, terms, limit: collectionLimit, title: \.name).map(LibrarySearchResult.artist)
            + ranked(albums, terms, limit: collectionLimit, title: \.title).map(LibrarySearchResult.album)
            + ranked(songs, terms, limit: songLimit, title: \.title).map(LibrarySearchResult.song)
            + ranked(playlists, terms, limit: collectionLimit, title: \.name).map(LibrarySearchResult.playlist)
            + ranked(podcasts, terms, limit: collectionLimit, title: \.title).map(LibrarySearchResult.podcast)
    }

    /// Apple Music's songs and albums for the query, after the library's results: the
    /// ones the library hasn't, streamed when chosen. None without a subscription.
    @MainActor
    static func appleMusicResults(for query: String, in musicService: MusicService) async -> [LibrarySearchResult] {
        guard musicService.canStream, let found = await AppleMusicCatalog.shared.search(query) else { return [] }
        let songs = found.songs
            .filter { AppleMusicCatalog.librarySong(title: $0.title, artist: $0.artistName, duration: $0.duration,
                                                    explicit: $0.contentRating.map { $0 == .explicit }, in: musicService) == nil }
            .map { LibrarySearchResult.song(AppTrack(from: $0, catalog: true)) }
        let albums = found.albums
            .filter { AppleMusicCatalog.libraryAlbum(title: $0.title, artist: $0.artistName, in: musicService.albums) == nil }
            .prefix(collectionLimit)
            .map { LibrarySearchResult.album(AppAlbum(from: $0, catalog: true)) }
        return songs + albums
    }

    // MARK: Shelves

    /// The tapes or records on each shelf that match `query`, or nil for an empty query.
    ///
    /// A shelf holds collections, not songs, so a song that matches brings up the album
    /// it's on, and an episode the show it's from. A playlist matches by its name, its
    /// curator or any song it already has loaded.
    @MainActor
    static func shelfMatches(for query: String, in library: ShelfLibrary) -> ShelfSearchMatches? {
        guard let matches = shelfFilter(for: query, songs: library.songs) else { return nil }
        let terms = terms(query)
        return ShelfSearchMatches(
            query: query,
            albums: library.albums.filter(matches),
            // An artist by name.
            artists: library.artists.filter { self.matches(terms, $0.title) },
            mixtapes: library.mixtapes.filter(matches),
            podcasts: library.podcasts.filter(matches)
        )
    }

    /// `items` narrowed to those matching `query` as `shelfMatches` matches them; all of
    /// them for an empty query.
    static func filter(_ items: [AppAlbum], matching query: String, songs: [AppTrack]) -> [AppAlbum] {
        guard let matches = shelfFilter(for: query, songs: songs) else { return items }
        return items.filter(matches)
    }

    private static func shelfFilter(for query: String, songs: [AppTrack]) -> ((AppAlbum) -> Bool)? {
        let terms = terms(query)
        guard !terms.isEmpty else { return nil }

        // Albums with a matching song, by the title the shelf files them under.
        let albumsWithSongs = Set(songs
            .filter { matches(terms, $0.title, $0.artistName) }
            .map { TapeFormat.displayTitle($0.albumTitle) })

        return { item in
            matches(terms, item.title, item.artistName, item.mixtape?.curatorName)
                || (item.mixtape == nil && !item.isPodcast && albumsWithSongs.contains(item.tapeTitle))
                || item.preloadedTracks.contains { matches(terms, $0.title, $0.artistName) }
        }
    }
}
