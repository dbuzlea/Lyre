//
//  SongTempos.swift
//  Lyre
//

import Foundation
import MusicKit
import OSLog
import os

private let logger = Logger(subsystem: "com.pinkhatcreations.lyreapp", category: "SongTempos")

// MARK: - Song Tempos
//
// Each song's tempo, for Liquid to move to (the cover's ripples and the visualizer). The
// music plays through the system's player, which no app can listen to,
// and Apple Music doesn't say a song's tempo, so it's asked of Deezer's public API
// (`DeezerTempo`), which needs no key or account:
//
//   • a song from Apple Music has an ISRC, the recording's own code: Deezer is asked for
//     that recording exactly
//   • any other song is searched for by artist and title, and a result counts only if
//     its title, artist and length all match, so a cover or a remix never lends its
//     tempo to the original; then that result is asked for its tempo
//
// What's sent is only that: the ISRC, or the artist and title. Turned off in Liquid's
// settings, nothing is (the tempos already kept here are still used: they don't leave).
//
// Every answer is kept, on this iPhone, in Application Support (not backed up): the
// tempo, or that Deezer doesn't know it, which is asked again after `retryAfter`. A
// request that fails (offline, the server) keeps nothing, so it's asked again later.
//
// Asking goes one request at a time, a little apart, to stay well inside Deezer's
// limit (50 requests every 5 seconds). The song playing goes to the front; the rest of
// the library is gone through behind it (`lookUp(_:)`), only while Lyre is open.

@MainActor
@Observable
final class SongTempos {
    static let shared = SongTempos()

    /// A tempo found, or 0 where Deezer doesn't know one, and when it was asked.
    struct Entry: Codable, Equatable {
        var bpm: Double
        var checked: Date
    }

    /// How long a song Deezer had no tempo for waits before it's asked again.
    static let retryAfter: TimeInterval = 60 * 86_400
    /// The tempos believed: anything outside is a mistake in the data.
    static let believable: ClosedRange<Double> = 40...220
    /// Time between requests: 8 a second at most, well inside Deezer's 10.
    private static let spacing: Duration = .milliseconds(150)

    private(set) var entries: [String: Entry] = [:]
    @ObservationIgnored private var waiting: [AppTrack] = []
    @ObservationIgnored private var asking: Set<String> = []
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var unsaved = 0
    /// When the library was last gone through, and how big it was.
    @ObservationIgnored private var lastScan: (count: Int, at: Date) = (-1, .distantPast)
    private static let rescanAfter: TimeInterval = 10 * 60
    @ObservationIgnored private let fileURL: URL?

    init(fileURL: URL? = SongTempos.defaultFileURL) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = stored
        }
    }

    nonisolated private static var defaultFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SongTempos.json")
    }

    // MARK: Reading

    /// The song's tempo, if it's known and believable.
    func bpm(for track: AppTrack) -> Double? {
        guard let key = Self.key(for: track), let entry = entries[key],
              Self.believable.contains(entry.bpm) else { return nil }
        return entry.bpm
    }

    /// What a song is filed under: its ISRC when it has one, else its artist and title.
    /// Remembered per song: the ripples ask for the playing song's tempo every frame.
    static func key(for track: AppTrack) -> String? {
        if let known = keys[track.id] { return known }
        let key = computeKey(for: track)
        if keys.count > 20_000 { keys.removeAll(keepingCapacity: true) }
        keys[track.id] = .some(key)
        return key
    }

    private static var keys: [String: String?] = [:]

    private static func computeKey(for track: AppTrack) -> String? {
        if let isrc = isrc(of: track) { return "isrc:" + isrc.uppercased() }
        let title = DeezerTempo.normalized(track.title), artist = DeezerTempo.normalized(track.artistName)
        guard !title.isEmpty, !artist.isEmpty else { return nil }
        return "song:\(artist)|\(title)"
    }

    static func isrc(of track: AppTrack) -> String? {
        let code = track.musicKitSong?.isrc ?? track.musicKitTrack?.isrc
        return code.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Whether a song still needs asking: never asked, or Deezer didn't know and it's
    /// been long enough to ask again.
    func needsAsking(_ track: AppTrack, now: Date = .now) -> Bool {
        guard let key = Self.key(for: track) else { return false }
        guard let entry = entries[key] else { return true }
        return entry.bpm == 0 && now.timeIntervalSince(entry.checked) > Self.retryAfter
    }

    // MARK: Asking

    /// Asks for `first` (the song playing) ahead of everything, then `rest` (the library)
    /// behind whatever is already waiting. Songs already known are passed over.
    ///
    /// The library is gone through again only when it has changed or a while has
    /// passed, not every time the song changes (it's asked with every new song).
    func lookUp(_ first: AppTrack?, then rest: [AppTrack] = []) {
        if let first, needsAsking(first), let firstKey = Self.key(for: first) {
            waiting.removeAll { Self.key(for: $0) == firstKey }
            waiting.insert(first, at: 0)
        }
        let now = Date()
        if !rest.isEmpty, rest.count != lastScan.count || now.timeIntervalSince(lastScan.at) > Self.rescanAfter {
            lastScan = (rest.count, now)
            var queued = Set(waiting.compactMap(Self.key(for:)))
            for track in rest where needsAsking(track, now: now) {
                guard let key = Self.key(for: track), queued.insert(key).inserted else { continue }
                waiting.append(track)
            }
        }
        guard worker == nil, !waiting.isEmpty else { return }
        worker = Task { await work() }
    }

    /// Stops asking, as when it's turned off. What's known is kept.
    func stop() {
        worker?.cancel()
        worker = nil
        waiting.removeAll()
        lastScan = (-1, .distantPast)
        save()
    }

    private func work() async {
        defer { worker = nil; save() }
        while !Task.isCancelled, !waiting.isEmpty {
            let track = waiting.removeFirst()
            guard let key = Self.key(for: track), needsAsking(track), asking.insert(key).inserted else { continue }
            let isrc = Self.isrc(of: track)
            let title = track.title, artist = track.artistName, duration = track.duration
            do {
                let bpm = try await DeezerTempo.bpm(isrc: isrc, title: title, artist: artist, duration: duration)
                record(bpm, for: key)
            } catch {
                // Offline or the server: nothing kept, so it's asked again another time.
                logger.debug("Tempo lookup failed for \(title, privacy: .private): \(error.localizedDescription)")
                if (error as? URLError)?.code == .notConnectedToInternet { waiting.removeAll(); lastScan = (-1, .distantPast) }
            }
            asking.remove(key)
            try? await Task.sleep(for: Self.spacing)
        }
    }

    /// Keeps an answer: the tempo, or nil for "Deezer doesn't know".
    func record(_ bpm: Double?, for key: String, at date: Date = .now) {
        entries[key] = Entry(bpm: bpm ?? 0, checked: date)
        unsaved += 1
        if unsaved >= 25 { save() }
    }

    /// Writes what's known, encoded and written off the main thread (a library's worth
    /// of entries is a sizeable file). Writes go in order, so the last one wins.
    func save() {
        guard unsaved > 0, let fileURL else { return }
        unsaved = 0
        let entries = self.entries
        let previous = lastSave
        lastSave = Task.detached(priority: .utility) {
            await previous?.value
            Self.write(entries, to: fileURL)
        }
    }

    @ObservationIgnored private var lastSave: Task<Void, Never>?

    nonisolated private static func write(_ entries: [String: Entry], to fileURL: URL) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            var url = fileURL
            try JSONEncoder().encode(entries).write(to: url, options: .atomic)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        } catch {
            logger.error("Could not save song tempos: \(error.localizedDescription)")
        }
    }

    /// Waits for writes already started (for tests).
    func finishSaving() async { await lastSave?.value }
}

// MARK: - Deezer

/// Deezer's public API, asked only for a song's tempo.
nonisolated enum DeezerTempo {
    enum LookupError: Error { case badResponse }

    /// How far apart two lengths may be and still be the same recording, in seconds.
    static let lengthTolerance: TimeInterval = 4

    /// The tempo of the recording with `isrc`, or failing that (no ISRC, or Deezer hasn't
    /// it under that code) of the song by `artist` called `title`. Nil when Deezer
    /// doesn't know it; throws when Deezer couldn't be asked.
    @concurrent
    static func bpm(isrc: String?, title: String, artist: String, duration: TimeInterval) async throws -> Double? {
        if let isrc {
            let url = URL(string: "https://api.deezer.com/track/isrc:\(isrc.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? isrc)")!
            if let track = try await fetchTrack(url) { return track.tempo }
        }
        var components = URLComponents(string: "https://api.deezer.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: "\(artist) \(title)"),
                                 URLQueryItem(name: "limit", value: "10")]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw LookupError.badResponse }
        guard let match = bestMatch(in: data, title: title, artist: artist, duration: duration) else { return nil }
        return try await fetchTrack(URL(string: "https://api.deezer.com/track/\(match)")!)?.tempo
    }

    /// A track as Deezer describes it, as far as Lyre reads it.
    struct Track: Decodable {
        let id: Int
        let title: String
        let duration: Double?
        let bpm: Double?
        let artist: Artist?

        struct Artist: Decodable { let name: String }

        /// The tempo, unless Deezer gives 0 (unknown) or something unbelievable.
        var tempo: Double? {
            guard let bpm, bpm >= 40, bpm <= 220 else { return nil }
            return bpm
        }
    }

    /// The track at `url`, or nil when Deezer has none ("no data").
    private static func fetchTrack(_ url: URL) async throws -> Track? {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw LookupError.badResponse }
        return track(from: data)
    }

    /// Deezer answers an unknown track with `{"error": …}` and status 200.
    static func track(from data: Data) -> Track? {
        try? JSONDecoder().decode(Track.self, from: data)
    }

    /// The id of the search result that is this song: the same title and artist, and,
    /// where both lengths are known, within `lengthTolerance` of it. The first such.
    static func bestMatch(in data: Data, title: String, artist: String, duration: TimeInterval) -> Int? {
        struct Results: Decodable { let data: [Track] }
        guard let results = try? JSONDecoder().decode(Results.self, from: data) else { return nil }
        let wantedTitle = normalized(title), wantedArtist = normalized(artist)
        return results.data.first { result in
            guard normalized(result.title) == wantedTitle, let name = result.artist?.name else { return false }
            let theirs = normalized(name)
            guard !theirs.isEmpty, wantedArtist.contains(theirs) || theirs.contains(wantedArtist) else { return false }
            if duration > 0, let length = result.duration, length > 0 {
                return abs(length - duration) <= lengthTolerance
            }
            return true
        }?.id
    }

    /// A title or name reduced to what identifies it: lower case, no accents, without
    /// what's in brackets ("(Remastered 2011)", "[Live]"), " - Single" and the like, or
    /// a "feat." credit, and only letters and digits.
    ///
    /// Each text is worked out once and remembered: matching a song against the
    /// library, filing its tempo and every frame of the ripples ask again and again,
    /// and the regular expressions are slow (a library's worth took over a second).
    static func normalized(_ text: String) -> String {
        if let known = normalizedCache.withLock({ $0[text] }) { return known }
        let result = computeNormalized(text)
        normalizedCache.withLock { cache in
            // A library's titles and names fit many times over; this only stops a
            // long-running search from growing it without end.
            if cache.count > 60_000 { cache.removeAll(keepingCapacity: true) }
            cache[text] = result
        }
        return result
    }

    private static let normalizedCache = OSAllocatedUnfairLock<[String: String]>(initialState: [:])

    /// Works out every title and artist ahead of time, off the main thread, so the
    /// first look through the library doesn't.
    @concurrent
    static func prepare(_ tracks: [AppTrack]) async {
        for track in tracks {
            _ = normalized(track.title)
            _ = normalized(track.artistName)
        }
    }

    private static func computeNormalized(_ text: String) -> String {
        var s = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        s = s.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+-\s+(single|ep|remaster(ed)?.*|radio edit.*)$"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+(feat\.?|ft\.?|featuring)\s+.*$"#, with: "", options: .regularExpression)
        return String(s.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}
