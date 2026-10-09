//
//  PlayerActions.swift
//  Lyre
//

import Foundation

// MARK: - Player Actions
//
// Actions every player style offers, kept in one place so the click wheel, the Spool's
// keys and the Gramophone's parts behave the same way:
//
// • Previous goes back to the start of the song once it's more than a few seconds in,
//   and to the song before otherwise.
// • On a podcast, back and forward jump within the episode, 15 seconds back and 30 on,
//   as the lock screen's buttons do, rather than skipping whole episodes.
// • An episode's download is started, cancelled or removed by the same toggle.

extension MusicService {
    /// How far into a song Previous goes back to its start rather than to the song before.
    static let restartThreshold: TimeInterval = 3

    /// Back to the start of the song, or to the song before when it has only just begun.
    func previousOrRestart() async {
        if currentTime > Self.restartThreshold {
            await seek(to: 0)
        } else {
            await skipToPrevious()
        }
    }

    /// Jumps within what's playing by `seconds`, staying inside it.
    func jump(by seconds: TimeInterval) async {
        guard duration > 0 else { return }
        let time = min(max(clock.time + seconds, 0), duration - 1)
        clock.time = time
        await seek(to: time)
    }

    /// Back or forward: within the episode on a podcast, otherwise a song.
    func skip(forward: Bool) async {
        if isPlayingPodcast {
            await jump(by: forward ? PodcastStreamPlayer.skipForwardInterval : -PodcastStreamPlayer.skipBackwardInterval)
        } else if forward {
            await skipToNext()
        } else {
            await previousOrRestart()
        }
    }
}

extension PodcastDownloads {
    /// Downloads `episode`, or cancels its download, or removes it once downloaded.
    /// Returns what happened, in the words the players show.
    @discardableResult
    func toggle(_ episode: PodcastEpisode) -> String {
        switch state(for: episode.id) {
        case nil:
            download(episode)
            return String(format: String(localized: "download.started"), episode.title)
        case .downloading:
            remove(episode.id)
            return String(localized: "download.cancelled")
        case .downloaded:
            remove(episode.id)
            return String(format: String(localized: "download.removed"), episode.title)
        }
    }

    /// The menu item for `episodeID`'s download: "Download", "Cancel Download" or
    /// "Remove Download", with its symbol.
    func actionTitle(for episodeID: String) -> (title: String, symbol: String) {
        switch state(for: episodeID) {
        case nil:          return (String(localized: "download.action.download"), "arrow.down.circle")
        case .downloading: return (String(localized: "download.action.cancel"), "xmark.circle")
        case .downloaded:  return (String(localized: "download.action.remove"), "trash")
        }
    }
}
