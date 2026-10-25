//
//  ArtistPhotos.swift
//  Lyre
//

import Foundation
import MusicKit
import OSLog

private let logger = Logger(subsystem: "com.pinkhatcreations.lyreapp", category: "ArtistPhotos")

// MARK: - Artist Photos
//
// Each artist's photo, from Apple Music's catalogue, for the artist lists and pages
// (see ArtistPhoto). An artist in the library seldom comes with its picture, so the
// catalogue is searched by name, and only an artist with the very same name counts: a
// shared credit ("21 Savage, Offset & Metro Boomin") or an artist only on this iPhone
// finds none, and is shown by its album's cover instead.
//
// Asked only as a row or page comes into view, one search at a time, and only with
// access to Apple Music granted. Every answer is kept on this iPhone (Application
// Support, not backed up): the picture, or that there is none, which is asked again
// after `retryAfter`. A search that fails keeps nothing, so it's asked again later.
// It goes to Apple Music, as the rest of Lyre does; nothing else is asked.

@MainActor
@Observable
final class ArtistPhotos {
    static let shared = ArtistPhotos()

    /// A picture found, or nil where Apple Music has none, and when it was asked.
    struct Entry: Codable {
        var artwork: Artwork?
        var checked: Date
    }

    static let retryAfter: TimeInterval = 30 * 86_400
    /// Time between searches, so a long list scrolled fast doesn't fire hundreds at once.
    private static let spacing: Duration = .milliseconds(120)

    private(set) var entries: [String: Entry] = [:]
    @ObservationIgnored private var waiting: [String] = []
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var unsaved = 0
    @ObservationIgnored private let fileURL: URL?

    init(fileURL: URL? = ArtistPhotos.defaultFileURL) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = stored
        }
    }

    nonisolated private static var defaultFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ArtistPhotos.json")
    }

    /// What an artist is filed under.
    static func key(for name: String) -> String? {
        let key = DeezerTempo.normalized(name)
        return key.isEmpty ? nil : key
    }

    /// The artist's picture, if one's been found.
    func artwork(for name: String) -> Artwork? {
        Self.key(for: name).flatMap { entries[$0]?.artwork }
    }

    func needsAsking(_ name: String, now: Date = .now) -> Bool {
        guard let key = Self.key(for: name) else { return false }
        guard let entry = entries[key] else { return true }
        return entry.artwork == nil && now.timeIntervalSince(entry.checked) > Self.retryAfter
    }

    /// Asks for the artist's picture, ahead of those already waiting (it's on screen now).
    func lookUp(_ name: String) {
        guard !AppEnvironment.isUITesting, MusicAuthorization.currentStatus == .authorized,
              needsAsking(name) else { return }
        waiting.removeAll { $0 == name }
        waiting.insert(name, at: 0)
        guard worker == nil else { return }
        worker = Task { await work() }
    }

    private func work() async {
        defer { worker = nil; save() }
        while !Task.isCancelled, !waiting.isEmpty {
            let name = waiting.removeFirst()
            guard let key = Self.key(for: name), needsAsking(name) else { continue }
            do {
                var request = MusicCatalogSearchRequest(term: name, types: [Artist.self])
                request.limit = 5
                let response = try await request.response()
                let match = response.artists.first { Self.key(for: $0.name) == key }
                record(match?.artwork, for: key)
            } catch {
                logger.debug("Artist search failed for \(name, privacy: .private): \(error.localizedDescription)")
            }
            try? await Task.sleep(for: Self.spacing)
        }
    }

    func record(_ artwork: Artwork?, for key: String, at date: Date = .now) {
        entries[key] = Entry(artwork: artwork, checked: date)
        unsaved += 1
        if unsaved >= 20 { save() }
    }

    func save() {
        guard unsaved > 0, let fileURL else { return }
        unsaved = 0
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
            var url = fileURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        } catch {
            logger.error("Could not save artist photos: \(error.localizedDescription)")
        }
    }
}
