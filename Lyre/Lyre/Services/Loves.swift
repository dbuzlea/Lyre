//
//  Loves.swift
//  Lyre
//

import Foundation
import MusicKit
import MediaPlayer
import OSLog

private let logger = Logger(subsystem: "com.pinkhatcreations.lyreapp", category: "Loves")

// MARK: - Loves
//
// The ★ every player has for the song playing: favouriting a song tells Apple Music, as
// the Music app's Favorite does, so its recommendations (Discover's Made for You) learn
// from it. A favourite is a rating of 1: the Music app's favourites read back as one,
// checked on a device, so the star shows what the Music app shows. Through Apple Music's ratings (`/v1/me/ratings`), which MusicKit's data requests
// sign for the listener: a catalogue song by its Apple Music ID, a library song by its
// library ID. A song with neither (a file of the listener's own) can't be loved, and
// shows no ★.
//
// What's known is kept for as long as Lyre is open, each song asked about once, when
// it plays. A tap changes the heart at once and is put back if Apple Music says no.
// `-LoveSamples YES` (debug builds) keeps loves here alone, for UI tests, which can't
// reach Apple Music.

@MainActor
@Observable
final class Loves {
    static let shared = Loves()

    /// Each song's love, by its rating's path; absent until asked.
    private(set) var loved: [String: Bool] = [:]
    @ObservationIgnored private var asked: Set<String> = []
    /// Each song's rating path, by song: working it out reads its play parameters,
    /// too much to do on every redraw.
    @ObservationIgnored private var paths: [String: String?] = [:]

    private func path(for track: AppTrack) -> String? {
        if let known = paths[track.id] { return known }
        // The samples have no Apple Music IDs: with sample loves, every song can be loved.
        let path = Self.ratingPath(for: track) ?? (Self.usesSamples ? "samples/" + track.id : nil)
        paths[track.id] = path
        return path
    }

    private static var usesSamples: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "LoveSamples")
        #else
        return false
        #endif
    }

    /// Where a song's rating lives: `songs/<id>` for the catalogue's, `library-songs/<id>`
    /// for the library's; nil for a song Apple Music doesn't know.
    nonisolated static func ratingPath(for track: AppTrack) -> String? {
        if let id = catalogID(of: track) { return "songs/" + id }
        if let id = track.musicKitSong?.id.rawValue, id.hasPrefix("i.") { return "library-songs/" + id }
        return nil
    }

    nonisolated private static func catalogID(of track: AppTrack) -> String? {
        if let storeID = track.storeID, isCatalogID(storeID) { return storeID }
        if let id = track.playIDs.catalogID, isCatalogID(id) { return id }
        if let id = track.mpItem?.playbackStoreID, isCatalogID(id) { return id }
        return nil
    }

    /// A catalogue ID is all digits, and never 0 (what a file of the listener's own has).
    nonisolated static func isCatalogID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy(\.isNumber) && id != "0"
    }

    /// Whether a ★ is offered for this song at all.
    func canLove(_ track: AppTrack?) -> Bool {
        guard let track, path(for: track) != nil else { return false }
        return Self.usesSamples || AppleMusicCatalog.isAvailable
    }

    func isLoved(_ track: AppTrack?) -> Bool {
        guard let track, let path = path(for: track) else { return false }
        return loved[path] ?? false
    }

    /// Asks Apple Music whether the song is loved, once per launch.
    func load(_ track: AppTrack?) async {
        guard let track, canLove(track), let path = path(for: track),
              asked.insert(path).inserted, !Self.usesSamples else { return }
        do {
            let response = try await MusicDataRequest(urlRequest: Self.request(path)).response()
            loved[path] = Self.isLoved(ratingData: response.data)
        } catch {
            // No rating is a 404: not loved.
            if Self.status(of: error) == 404 { loved[path] = false; return }
            asked.remove(path)
            logger.debug("Rating lookup failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Loves the song, or takes the love back.
    func toggle(_ track: AppTrack?) async {
        guard let track, canLove(track), let path = path(for: track) else { return }
        UsageStats.shared.used(.love)
        let was = loved[path] ?? false
        loved[path] = !was
        guard !Self.usesSamples else { return }
        do {
            var request = Self.request(path)
            if was {
                request.httpMethod = "DELETE"
            } else {
                request.httpMethod = "PUT"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = Self.loveBody
            }
            _ = try await MusicDataRequest(urlRequest: request).response()
        } catch {
            loved[path] = was
            logger.error("Love failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Requests

    private static func request(_ path: String) -> URLRequest {
        URLRequest(url: URL(string: "https://api.music.apple.com/v1/me/ratings/" + path)!)
    }

    /// A love, as Apple Music's ratings have it: 1 (a dislike is -1).
    nonisolated static let loveBody = Data(#"{"type":"rating","attributes":{"value":1}}"#.utf8)

    /// Whether a rating's answer is a love.
    nonisolated static func isLoved(ratingData data: Data) -> Bool {
        struct Ratings: Decodable {
            struct Rating: Decodable {
                struct Attributes: Decodable { let value: Int }
                let attributes: Attributes
            }
            let data: [Rating]
        }
        return (try? JSONDecoder().decode(Ratings.self, from: data))?.data.first?.attributes.value == 1
    }

    private static func status(of error: Error) -> Int? {
        (error as? MusicDataRequest.Error)?.status
    }
}
