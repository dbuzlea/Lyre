//
//  AppleMusicRecents.swift
//  Lyre
//

import Foundation
import MusicKit
import OSLog

private let logger = Logger(subsystem: "com.pinkhatcreations.lyreapp", category: "AppleMusicRecents")

// MARK: - Apple Music's Recently Played
//
// The device's library knows when its own songs were last played, but not songs streamed
// from Apple Music that were never added, nor anything played on another device. Apple
// Music's own history (MusicRecentlyPlayedRequest) has those: its songs go first in
// Recently Played (each the library's copy where it has one, else streamed), then the
// device's, each song once. Asked for after each load of the library, in the background.

extension MusicService {
    /// Puts Apple Music's recently played songs at the front of Recently Played.
    func mergeAppleMusicRecents() async {
        guard AppleMusicCatalog.isAvailable else { return }
        do {
            var request = MusicRecentlyPlayedRequest<Song>()
            request.limit = 30
            let songs = try await request.response().items
            guard !songs.isEmpty else { return }
            let apple = songs.map { song in
                AppleMusicCatalog.librarySong(title: song.title, artist: song.artistName, duration: song.duration,
                                              explicit: song.contentRating.map { $0 == .explicit }, in: self)
                    ?? AppTrack(from: song, catalog: true)
            }
            let merged = Self.mergedRecents(apple: apple, device: deviceRecentlyPlayed)
            guard merged.map(\.id) != recentlyPlayed.map(\.id) else { return }
            recentlyPlayed = merged
        } catch {
            logger.debug("Recently played failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Apple Music's songs first, then the device's that aren't among them (the same
    /// title by the same artist), up to `limit`.
    nonisolated static func mergedRecents(apple: [AppTrack], device: [AppTrack], limit: Int = 100) -> [AppTrack] {
        func key(_ track: AppTrack) -> String {
            DeezerTempo.normalized(track.title) + "|" + DeezerTempo.normalized(track.artistName)
        }
        var seen: Set<String> = []
        return (apple + device).filter { seen.insert(key($0)).inserted }.prefix(limit).map { $0 }
    }
}
