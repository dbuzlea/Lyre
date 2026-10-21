//
//  EpisodeHistory.swift
//  Lyre
//

import SwiftUI
import MediaPlayer
internal import Combine

// MARK: - Episode History
//
// Which podcast episodes have been listened to: started (heard past the first half
// minute) or played (heard to within its last half minute, or to the end). Every
// player's episode list marks them (EpisodeTitle), as Apple Podcasts does.
//
// Lyre writes down what it plays itself. For an episode in the media library, the
// play history iOS keeps (its play count and saved place, from Apple Podcasts or any
// player) counts too, so an episode finished elsewhere shows as played here.
//
// Episodes are known by show and title, not by id: a show's downloaded and streamed
// copies of an episode have different ids (see MusicService.mergedPodcastShows) but
// are the same episode, heard once.

@MainActor
final class EpisodeHistory: ObservableObject {
    static let shared = EpisodeHistory()

    enum State: Int {
        case started = 1
        case played = 2
    }

    private static let storageKey = "podcast.episodeHistory"
    /// How far in an episode counts as started, and how near its end as played.
    static let startedAfter: TimeInterval = 30
    static let playedWithin: TimeInterval = 30

    @Published private var states: [String: Int]

    private init() {
        // Numbers, as saved; or text, as a launch argument gives them (UI tests).
        let saved = UserDefaults.standard.dictionary(forKey: Self.storageKey) ?? [:]
        states = saved.compactMapValues { ($0 as? Int) ?? ($0 as? String).flatMap(Int.init) }
    }

    /// How far the episode's been heard, if at all.
    func state(for episode: PodcastEpisode) -> State? {
        let own = states[Self.key(for: episode)].flatMap(State.init(rawValue:))
        if own == .played { return .played }
        if let item = episode.mediaItem {
            if item.playCount > 0 { return .played }
            if item.bookmarkTime > Self.startedAfter { return .started }
        }
        return own
    }

    /// Writes down that `episode` has been heard to `time` of `duration`. A played
    /// episode stays played if it's started again.
    func record(_ episode: PodcastEpisode, time: TimeInterval, duration: TimeInterval) {
        let length = duration > 0 ? duration : episode.duration
        if length > 0, time >= length - Self.playedWithin {
            markPlayed(episode)
        } else if time > Self.startedAfter {
            set(.started, for: episode)
        }
    }

    /// Heard to the end.
    func markPlayed(_ episode: PodcastEpisode) {
        set(.played, for: episode)
    }

    private func set(_ state: State, for episode: PodcastEpisode) {
        let key = Self.key(for: episode)
        let current = states[key] ?? 0
        guard state.rawValue > current else { return }
        states[key] = state.rawValue
        UserDefaults.standard.set(states, forKey: Self.storageKey)
    }

    private static func key(for episode: PodcastEpisode) -> String {
        episode.showTitle.lowercased() + "|" + episode.title.lowercased()
    }
}

// MARK: - Episode Title

/// An episode's title with its mark after the last word: a tick once it's been played,
/// half a circle while it's part way through; just the title for one not yet heard (or
/// for a song). Part of the text, so a title that wraps takes its mark with it. Styled
/// like any Text: font, colour and line limit from outside.
struct EpisodeTitle: View {
    let episode: PodcastEpisode?
    let title: String
    @ObservedObject private var history = EpisodeHistory.shared

    init(_ title: String, episode: PodcastEpisode?) {
        self.title = title
        self.episode = episode
    }

    var body: some View {
        let state = episode.flatMap { history.state(for: $0) }
        if let state {
            let symbol = state == .played ? "checkmark.circle.fill" : "circle.lefthalf.filled"
            let mark = Text(Image(systemName: symbol)).font(.caption2).foregroundStyle(.secondary)
            Text("\(Text(verbatim: title)) \(mark)")
                .accessibilityLabel(title + ", " + String(localized: state == .played ? "episode.played" : "episode.inProgress"))
        } else {
            Text(verbatim: title)
        }
    }
}
