//
//  PodcastSubscriptions.swift
//  Lyre
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.pinkhatcreations.lyreapp", category: "PodcastSubscriptions")

// MARK: - PodcastSubscriptions
//
// The shows the user has subscribed to, kept entirely on the device: each parsed feed
// is saved as JSON in Application Support, so subscriptions appear instantly at launch
// and their episode lists survive going offline. Nothing is synced anywhere.
//
// Also remembers how far into each streamed episode the user got, so an episode picks
// up where it was left.
//
// Main thread only, like MusicService which owns it.

final class PodcastSubscriptions {
    private(set) var feeds: [FeedShow]

    private nonisolated static var fileURL: URL {
        URL.applicationSupportDirectory.appending(path: "PodcastSubscriptions.json")
    }

    private static let positionsKey = "podcast.episodePositions"
    private var positions: [String: TimeInterval]

    init() {
        feeds = Self.loadFromDisk()
        positions = UserDefaults.standard.dictionary(forKey: Self.positionsKey) as? [String: TimeInterval] ?? [:]
    }

    func isSubscribed(_ feedURL: URL) -> Bool {
        feeds.contains { $0.feedURL == feedURL }
    }

    /// Adds a feed, or replaces the stored copy of one already subscribed to.
    func store(_ feed: FeedShow, replacing originalURL: URL? = nil) {
        let key = originalURL ?? feed.feedURL
        if let index = feeds.firstIndex(where: { $0.feedURL == key || $0.feedURL == feed.feedURL }) {
            feeds[index] = feed
        } else {
            feeds.append(feed)
        }
        save()
    }

    func remove(_ feedURL: URL) {
        feeds.removeAll { $0.feedURL == feedURL }
        save()
    }

    // MARK: Positions

    func position(for episodeID: String) -> TimeInterval {
        positions[episodeID] ?? 0
    }

    /// A position of zero forgets the episode, which is what finishing it does.
    func setPosition(_ time: TimeInterval, for episodeID: String) {
        if time > 0 { positions[episodeID] = time } else { positions[episodeID] = nil }
        UserDefaults.standard.set(positions, forKey: Self.positionsKey)
    }

    // MARK: Disk

    private static func loadFromDisk() -> [FeedShow] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            return try JSONDecoder().decode([FeedShow].self, from: data)
        } catch {
            logger.error("Could not read podcast subscriptions: \(error.localizedDescription)")
            return []
        }
    }

    private func save() {
        let snapshot = feeds
        Task.detached(priority: .utility) {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try FileManager.default.createDirectory(
                    at: URL.applicationSupportDirectory, withIntermediateDirectories: true
                )
                try data.write(to: Self.fileURL, options: .atomic)
            } catch {
                logger.error("Could not save podcast subscriptions: \(error.localizedDescription)")
            }
        }
    }
}
