//
//  CatalogueQueueSpike.swift
//  Lyre
//

#if DEBUG

import Foundation
import MediaPlayer
import MusicKit
import OSLog

private let logger = Logger(subsystem: "com.pinkhatcreations.lyreapp", category: "CatalogueSpike")

// MARK: - Catalogue Queue Spike
//
// Throwaway diagnostic, DEBUG-only, not reachable from the shipping UI. It answers the
// four questions that decide how Apple Music catalogue tracks can be queued, none of
// which are answerable from the documentation:
//
//   Q1  Does inserting a play-parameters descriptor into a queue that was set from
//       MPMediaItems actually work — does the track play?
//   Q2  What does `queue.items` report for such an entry? Is it there at all, and does
//       it carry a usable `persistentID`?
//   Q3  What does `player.nowPlayingItem` report while a catalogue entry plays?
//   Q4  Does a queue built entirely from play parameters work (setQueue +
//       startItemPlayParameters)?
//
// Q2 and Q3 are the decisive ones. PlaybackQueue identifies tracks by
// `MPMediaItem.persistentID`, and `syncQueueModel(with:)` rebuilds the model from
// `queue.items` after every transaction. If catalogue entries have no stable persistent
// ID, that identity has to be replaced before catalogue support is possible — see
// Docs/CATALOGUE-QUEUE-SPIKE.md.
//
// Delete this file once the questions are answered.
enum CatalogueQueueSpike {

    /// Bridges MusicKit's opaque `PlayParameters` into MediaPlayer's equivalent. This
    /// is the documented route: `MPMusicPlayerPlayParameters(dictionary:)` takes "the
    /// JSON information returned from a MusicKit query", and `PlayParameters` is
    /// `Codable`, so JSON is the only shared representation.
    static func playParameters(for track: AppTrack) -> MPMusicPlayerPlayParameters? {
        let source: PlayParameters?
        if let song = track.musicKitSong {
            source = song.playParameters
        } else if let mkTrack = track.musicKitTrack {
            source = mkTrack.playParameters
        } else {
            source = nil
        }
        guard let source else {
            logger.notice("No MusicKit object on '\(track.title)' — cannot build play parameters")
            return nil
        }

        do {
            let data = try JSONEncoder().encode(source)
            guard let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                logger.error("Play parameters for '\(track.title)' did not encode to a dictionary")
                return nil
            }
            logger.notice("Play parameters for '\(track.title)': \(dictionary)")
            return MPMusicPlayerPlayParameters(dictionary: dictionary)
        } catch {
            logger.error("Encoding play parameters for '\(track.title)' failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Q1 / Q2 / Q3 — mixing a catalogue track into a media-item queue

    /// Appends `track` to whatever the player is currently playing, using play
    /// parameters, then reports what the queue and the now-playing item look like.
    /// Run this with a local queue already playing, then skip forward to the appended
    /// track and call `reportNowPlaying()`.
    @MainActor
    static func appendToCurrentQueue(_ track: AppTrack, player: MPMusicPlayerApplicationController) {
        guard let parameters = playParameters(for: track) else { return }
        let descriptor = MPMusicPlayerPlayParametersQueueDescriptor(playParametersQueue: [parameters])

        logger.notice("Q1 — appending catalogue track '\(track.title)' to the live queue")
        player.perform(queueTransaction: { queue in
            queue.insert(descriptor, after: queue.items.last)
        }, completionHandler: { queue, error in
            let items = queue.items
            if let error {
                logger.error("Q1 FAILED — transaction error: \(error.localizedDescription)")
            }
            logger.notice("Q2 — queue now holds \(items.count) item(s)")
            for (index, item) in items.enumerated().suffix(3) {
                logger.notice("""
                    Q2 — [\(index)] persistentID=\(item.persistentID) \
                    isCloud=\(item.isCloudItem) assetURL=\(item.assetURL != nil) \
                    title=\(item.title ?? "nil")
                    """)
            }
        })
    }

    /// Call while the catalogue track is playing.
    @MainActor
    static func reportNowPlaying(player: MPMusicPlayerApplicationController) {
        guard let item = player.nowPlayingItem else {
            logger.notice("Q3 — nowPlayingItem is nil (model identity by persistentID is impossible)")
            return
        }
        logger.notice("""
            Q3 — nowPlayingItem persistentID=\(item.persistentID) \
            isCloud=\(item.isCloudItem) title=\(item.title ?? "nil") \
            indexOfNowPlayingItem=\(player.indexOfNowPlayingItem)
            """)
    }

    // MARK: - Q4 — an all-catalogue queue

    /// Replaces the queue with `tracks` as play parameters and starts at `index`.
    /// Use a playlist whose tracks are all catalogue-only (an editorial playlist).
    @MainActor
    static func playAllAsCatalogue(_ tracks: [AppTrack], startingAt index: Int,
                                   player: MPMusicPlayerApplicationController) {
        let parameters = tracks.compactMap(playParameters(for:))
        guard !parameters.isEmpty else {
            logger.error("Q4 — no play parameters could be built from \(tracks.count) track(s)")
            return
        }
        logger.notice("Q4 — setting an all-catalogue queue of \(parameters.count) of \(tracks.count) track(s)")

        let descriptor = MPMusicPlayerPlayParametersQueueDescriptor(playParametersQueue: parameters)
        if parameters.indices.contains(index) {
            descriptor.startItemPlayParameters = parameters[index]
        }
        player.setQueue(with: descriptor)
        player.prepareToPlay { error in
            if let error {
                logger.error("Q4 FAILED — prepareToPlay: \(error.localizedDescription)")
                return
            }
            DispatchQueue.main.async {
                player.play()
                logger.notice("Q4 — playing; nowPlayingItem=\(player.nowPlayingItem?.title ?? "nil")")
            }
        }
    }
}

#endif
