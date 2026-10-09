//
//  ModelsPodcastShow.swift
//  Lyre
//
//  Created by Daniel Buzlea on 5/17/26.
//

import MediaPlayer
import Foundation

// MARK: - Podcast Model
//
// A show comes from one of two places:
//
//   • The on-device media library — episodes synced or downloaded to the phone, which
//     are MPMediaItems and play through the music player like songs.
//   • A subscribed RSS feed — episodes are remote audio URLs, streamed by
//     PodcastStreamPlayer. No account with any podcast service is involved.
//
// PodcastEpisode wraps both so the lists, the carousel and Now Playing can treat a
// show the same way whichever source it came from.

/// One episode, either on the device or streamed from its feed.
/// `nonisolated` so LibraryScanner can build shows off the main thread.
nonisolated struct PodcastEpisode: Identifiable, Hashable {
    enum Source {
        case local(MPMediaItem)
        case remote(URL)
    }

    let id: String
    let title: String
    let showTitle: String
    let duration: TimeInterval
    let published: Date?
    /// Remote artwork for the episode, or its show's when the episode has none.
    let artworkURL: URL?
    let source: Source

    var mediaItem: MPMediaItem? {
        if case .local(let item) = source { return item }
        return nil
    }

    var streamURL: URL? {
        if case .remote(let url) = source { return url }
        return nil
    }

    init(item: MPMediaItem) {
        id = "mp.\(item.persistentID)"
        title = item.title ?? "Episode"
        showTitle = item.podcastTitle ?? item.albumTitle ?? "Unknown Podcast"
        duration = item.playbackDuration
        published = item.releaseDate ?? item.dateAdded
        artworkURL = nil
        source = .local(item)
    }

    init(feedEpisode: FeedEpisode, show: FeedShow) {
        id = "feed.\(feedEpisode.guid)"
        title = feedEpisode.title
        showTitle = show.title
        duration = feedEpisode.duration ?? 0
        published = feedEpisode.published
        artworkURL = feedEpisode.artworkURL ?? show.artworkURL
        source = .remote(feedEpisode.audioURL)
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: PodcastEpisode, rhs: PodcastEpisode) -> Bool { lhs.id == rhs.id }

    /// The episode as a track, for lists of what's playing and what's next. Shares the
    /// episode's id.
    var asTrack: AppTrack {
        AppTrack(id: id, title: title, artistName: showTitle, albumTitle: showTitle,
                 duration: duration, mpItem: mediaItem)
    }
}

nonisolated struct PodcastShow: Identifiable, Hashable, Equatable {
    /// The title for an on-device show (as before), the feed URL for a subscription.
    let id: String
    let title: String
    let episodes: [PodcastEpisode]
    /// Set for subscribed shows, which stream their episodes.
    let feedURL: URL?
    let artworkURL: URL?

    var isStreamed: Bool { feedURL != nil }

    /// On-device artwork. Remote shows draw `artworkURL` instead.
    var artwork: MPMediaItemArtwork? { episodes.lazy.compactMap(\.mediaItem).first?.artwork }

    var hasArtwork: Bool { artworkURL != nil || artwork != nil }

    /// Key for LocalArtworkImage. On-device shows keep the key they always had.
    var artworkCacheKey: String { "podcast.\(id)" }

    init(title: String, localEpisodes: [MPMediaItem]) {
        id = title
        self.title = title
        episodes = localEpisodes.map(PodcastEpisode.init(item:))
        feedURL = nil
        artworkURL = nil
    }

    /// A show made of chosen episodes: the Downloaded screen's merge of a show's
    /// on-device episodes with those saved from its feed, or a subscription with its
    /// downloaded episodes taken out for the main Podcasts list.
    init(id: String, title: String, episodes: [PodcastEpisode], feedURL: URL? = nil, artworkURL: URL?) {
        self.id = id
        self.title = title
        self.episodes = episodes
        self.feedURL = feedURL
        self.artworkURL = artworkURL
    }

    init(feed: FeedShow) {
        id = "feed:\(feed.feedURL.absoluteString)"
        title = feed.title
        episodes = feed.episodes.map { PodcastEpisode(feedEpisode: $0, show: feed) }
        feedURL = feed.feedURL
        artworkURL = feed.artworkURL
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: PodcastShow, rhs: PodcastShow) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Feed Records
//
// What a subscription stores on disk: the parsed feed, so subscribed shows are on
// screen instantly at launch and still listed offline.

nonisolated struct FeedEpisode: Codable, Hashable {
    let guid: String
    let title: String
    let audioURL: URL
    let published: Date?
    let duration: TimeInterval?
    let artworkURL: URL?
}

nonisolated struct FeedShow: Codable, Hashable {
    let feedURL: URL
    let title: String
    let author: String?
    let artworkURL: URL?
    /// Newest first.
    let episodes: [FeedEpisode]
    let lastRefreshed: Date
}
