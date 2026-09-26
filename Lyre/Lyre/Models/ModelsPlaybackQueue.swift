//
//  ModelsPlaybackQueue.swift
//  Lyre
//

import Foundation
import MediaPlayer

// MARK: - PlaybackQueue
//
// The app's own model of what MPMusicPlayerController is playing, in queue order.
//
// The player can be *given* a queue (`setQueue`, `append`) but offers no way to read
// or rearrange the queue it holds — only MPMusicPlayerApplicationController can do
// that, and Lyre plays through the system player so playback survives leaving the app.
// So the only way to show an Up Next list the user can reorder is to mirror the queue
// here and hand the player a rebuilt queue whenever the order changes.
//
// `tracks` holds every item the player was handed, with the playing one at
// `currentIndex`: everything after it is up next, everything before it has played.
// Mutations are expressed as up-next *offsets* (0 = the next track to play) because
// that is the only region the Queue screen exposes.
//
// Note this is queue order, not necessarily hearing order — with shuffle enabled the
// player picks its own path through the queue.
struct PlaybackQueue: Equatable {
    private(set) var tracks: [AppTrack]
    private(set) var currentIndex: Int

    init(tracks: [AppTrack] = [], currentIndex: Int = 0) {
        self.tracks = tracks
        self.currentIndex = tracks.isEmpty ? 0 : min(max(0, currentIndex), tracks.count - 1)
    }

    var isEmpty: Bool { tracks.isEmpty }

    var current: AppTrack? {
        tracks.indices.contains(currentIndex) ? tracks[currentIndex] : nil
    }

    /// The tracks that have not played yet, in queue order.
    var upNext: [AppTrack] {
        let start = currentIndex + 1
        guard start < tracks.count else { return [] }
        return Array(tracks[start...])
    }

    var upNextCount: Int { max(0, tracks.count - currentIndex - 1) }

    /// Adds a track to the bottom of the queue.
    mutating func append(_ track: AppTrack) {
        tracks.append(track)
    }

    /// Inserts tracks directly after the current one, in the order given — "Play Next".
    /// On an empty queue they simply become the queue.
    mutating func insertUpNext(_ newTracks: [AppTrack]) {
        guard !tracks.isEmpty else {
            tracks = newTracks
            return
        }
        tracks.insert(contentsOf: newTracks, at: currentIndex + 1)
    }

    /// Moves an up-next track to another up-next position. Offsets out of range are
    /// ignored so a cursor that has drifted past the end of the list cannot corrupt
    /// the order.
    mutating func moveUpNext(from origin: Int, to destination: Int) {
        let count = upNextCount
        guard origin != destination,
              (0..<count).contains(origin),
              (0..<count).contains(destination) else { return }
        let base = currentIndex + 1
        let track = tracks.remove(at: base + origin)
        tracks.insert(track, at: base + destination)
    }

    @discardableResult
    mutating func removeUpNext(at offset: Int) -> AppTrack? {
        guard (0..<upNextCount).contains(offset) else { return nil }
        return tracks.remove(at: currentIndex + 1 + offset)
    }

    /// Empties Up Next, leaving the current track and the history behind it alone.
    /// Returns how many tracks were dropped.
    @discardableResult
    mutating func removeAllUpNext() -> Int {
        let removed = upNextCount
        guard removed > 0 else { return 0 }
        tracks.removeSubrange((currentIndex + 1)...)
        return removed
    }

    /// Points `currentIndex` at the track backed by `persistentID`.
    ///
    /// The search starts at the current position so a queue holding the same song
    /// twice advances to the later copy instead of jumping back to the first one.
    /// Returns false when the player has moved to something outside this queue, which
    /// means the model no longer describes what is playing.
    @discardableResult
    mutating func advanceCurrent(toPersistentID persistentID: MPMediaEntityPersistentID) -> Bool {
        guard !tracks.isEmpty else { return false }
        let matches = { (track: AppTrack) in track.mpPersistentID == persistentID }
        if let index = tracks[currentIndex...].firstIndex(where: matches) {
            currentIndex = index
            return true
        }
        if let index = tracks.firstIndex(where: matches) {
            currentIndex = index
            return true
        }
        return false
    }
}
