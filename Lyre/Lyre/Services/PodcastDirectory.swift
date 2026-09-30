//
//  PodcastDirectory.swift
//  Lyre
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.pinkhatcreations.lyreapp", category: "PodcastDirectory")

// MARK: - PodcastDirectory
//
// Finding and reading podcasts without any podcast service account.
//
//   • Search goes to Apple's public iTunes Search API. It needs no key or sign-in and
//     returns each show's RSS feed URL — Lyre uses nothing else from Apple Podcasts.
//   • Feeds are fetched and parsed here directly. Every public podcast is an RSS feed
//     whose items point at the episode audio (`<enclosure url=…>`), which is what
//     PodcastStreamPlayer streams.

nonisolated enum PodcastDirectory {
    static let maxEpisodes = 300

    struct SearchResult: Identifiable, Hashable {
        let title: String
        let author: String
        let feedURL: URL
        let artworkURL: URL?

        var id: URL { feedURL }
    }

    enum DirectoryError: LocalizedError {
        case badResponse
        case notAFeed
        case noEpisodes

        var errorDescription: String? {
            switch self {
            case .badResponse: return "The podcast couldn't be reached. Try again in a moment."
            case .notAFeed:    return "That address isn't a podcast feed."
            case .noEpisodes:  return "That feed has no playable episodes."
            }
        }
    }

    // MARK: Search

    @concurrent
    static func search(_ term: String) async throws -> [SearchResult] {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "media", value: "podcast"),
            URLQueryItem(name: "entity", value: "podcast"),
            URLQueryItem(name: "limit", value: "30"),
            URLQueryItem(name: "term", value: term),
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw DirectoryError.badResponse }

        struct Response: Decodable {
            struct Item: Decodable {
                let collectionName: String?
                let artistName: String?
                let feedUrl: String?
                let artworkUrl600: String?
                let artworkUrl100: String?
            }
            let results: [Item]
        }
        return try JSONDecoder().decode(Response.self, from: data).results.compactMap { item in
            // Some directory entries have no public feed; they can't be streamed.
            guard let feed = item.feedUrl.flatMap(URL.init(string:)) else { return nil }
            return SearchResult(
                title: item.collectionName ?? "Untitled",
                author: item.artistName ?? "",
                feedURL: feed,
                artworkURL: (item.artworkUrl600 ?? item.artworkUrl100).flatMap(URL.init(string:))
            )
        }
    }

    // MARK: Feeds

    @concurrent
    static func fetchFeed(_ url: URL) async throws -> FeedShow {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            logger.error("Feed \(url.absoluteString) returned \(http.statusCode)")
            throw DirectoryError.badResponse
        }

        let parser = FeedParser()
        guard let parsed = parser.parse(data) else { throw DirectoryError.notAFeed }
        guard !parsed.episodes.isEmpty else { throw DirectoryError.noEpisodes }

        return FeedShow(
            // The address subscribed to stays the key, even if the server redirects.
            feedURL: url,
            title: parsed.title.isEmpty ? (url.host() ?? "Podcast") : parsed.title,
            author: parsed.author,
            artworkURL: parsed.artworkURL,
            // Long-running daily shows carry thousands of items; the newest few hundred
            // are plenty to scroll through with a wheel.
            episodes: Array(parsed.episodes
                .sorted { ($0.published ?? .distantPast) > ($1.published ?? .distantPast) }
                .prefix(Self.maxEpisodes)),
            lastRefreshed: Date()
        )
    }
}

// MARK: - FeedParser

/// A small RSS 2.0 reader covering what podcast feeds use: channel title, author and
/// artwork, and per item the title, guid, enclosure, date, duration and artwork.
private nonisolated final class FeedParser: NSObject, XMLParserDelegate {
    struct Result {
        var title = ""
        var author: String?
        var artworkURL: URL?
        var episodes: [FeedEpisode] = []
    }

    private var result = Result()
    private var sawChannel = false
    private var text = ""
    private var path: [String] = []

    // The item being read.
    private var inItem = false
    private var itemTitle = ""
    private var itemGUID: String?
    private var itemAudio: URL?
    private var itemDate: Date?
    private var itemDuration: TimeInterval?
    private var itemArtwork: URL?

    func parse(_ data: Data) -> Result? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() || !result.episodes.isEmpty, sawChannel else { return nil }
        return result
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        path.append(name)
        text = ""
        switch name {
        case "channel":
            sawChannel = true
        case "item":
            inItem = true
            itemTitle = ""; itemGUID = nil; itemAudio = nil
            itemDate = nil; itemDuration = nil; itemArtwork = nil
        case "enclosure" where inItem:
            itemAudio = attributes["url"].flatMap(Self.url(from:))
        case "itunes:image":
            let href = attributes["href"].flatMap(Self.url(from:))
            if inItem { itemArtwork = href } else if result.artworkURL == nil { result.artworkURL = href }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = path.dropLast().last
        defer { path.removeLast(); text = "" }

        if inItem {
            switch name {
            case "title" where parent == "item":  itemTitle = value
            case "guid":                          itemGUID = value.isEmpty ? nil : value
            case "pubDate":                       itemDate = Self.date(from: value)
            case "itunes:duration":               itemDuration = Self.duration(from: value)
            case "item":
                inItem = false
                guard let audio = itemAudio else { return }
                result.episodes.append(FeedEpisode(
                    guid: itemGUID ?? audio.absoluteString,
                    title: itemTitle.isEmpty ? "Episode" : itemTitle,
                    audioURL: audio,
                    published: itemDate,
                    duration: itemDuration,
                    artworkURL: itemArtwork
                ))
            default: break
            }
            return
        }

        switch name {
        case "title" where parent == "channel":
            result.title = value
        case "itunes:author" where parent == "channel":
            result.author = value
        case "url" where parent == "image":
            // The plain RSS <image>, used when there is no itunes:image.
            if result.artworkURL == nil { result.artworkURL = Self.url(from: value) }
        default:
            break
        }
    }

    // MARK: Values

    private static func url(from string: String) -> URL? {
        URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static let dateFormatters: [DateFormatter] = [
        "EEE, dd MMM yyyy HH:mm:ss Z",
        "EEE, dd MMM yyyy HH:mm:ss zzz",
        "EEE, dd MMM yyyy HH:mm Z",
        "dd MMM yyyy HH:mm:ss Z",
        "EEE, d MMM yyyy HH:mm:ss Z",
    ].map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }

    private static func date(from string: String) -> Date? {
        for formatter in dateFormatters {
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }

    /// `itunes:duration` is seconds, `MM:SS` or `HH:MM:SS`.
    private static func duration(from string: String) -> TimeInterval? {
        let parts = string.split(separator: ":").compactMap { Double($0) }
        guard !parts.isEmpty else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }
}
