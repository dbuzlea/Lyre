//
//  UsageStats.swift
//  Lyre
//

import Foundation
import UIKit
import OSLog

private let logger = Logger(subsystem: "com.pinkhatcreations.lyreapp", category: "UsageStats")

// MARK: - Usage Statistics
//
// How people find their way around Lyre, counted so it can be made easier: which players
// they use and keep, how long it takes to get to music and from where, which screens they
// back straight out of, which searches find nothing, where it freezes, and which features
// they ever find. Only if they've turned on Share Usage Statistics (off unless they do).
//
// What's sent are small events, each a kind of thing and a number, never a name: no song,
// album, artist or playlist, no search words, nothing typed, no screenshots. Most of the
// working-out happens here, so only the conclusion goes ("the first song played 6 s after
// launch, from a card"), not every tap that led to it.
//
// There's no lasting identifier for a person: an event says which week Lyre was installed
// and how many days ago, which is enough to see who comes back, without anything that
// follows anyone. Events wait on the phone and go to the relay once a day, signed as
// problem reports are (relay: POST /v1/usage).

nonisolated final class UsageStats: @unchecked Sendable {
    static let shared = UsageStats()

    static let enabledKey = "ShareUsageStatistics"
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            if !newValue { shared.discard() }
        }
    }

    /// A page left this soon is a dead end.
    static let bounceSeconds: TimeInterval = 2
    /// Back after this long away, a new session: its first play counts again.
    static let sessionGap: TimeInterval = 30 * 60
    /// At most this many events wait; past it, the oldest go.
    static let maxWaiting = 3000
    /// Sent at most this often.
    static let sendInterval: TimeInterval = 20 * 3600

    struct Event: Codable, Equatable {
        let name: String
        var player: String
        var screen: String?
        var source: String?
        var detail: String?
        var value: Double?
        var date: String
        var day: Int
        var cohort: String
        var version: String
        var build: String
        var device: String
        var os: String
    }

    private let lock = NSLock()
    private let defaults: UserDefaults
    private let fileURL: URL
    private let now: () -> Date
    private var events: [Event] = []
    private var sessionStart: Date
    private var playedThisSession = false
    private var screen: (name: String, since: Date)?
    private var player: (name: String, since: Date)?
    private var lastActive: Date?
    private var playersToday: Set<String> = []
    private var pendingSearch: DispatchWorkItem?
    private let searchQueue = DispatchQueue(label: "com.pinkhatcreations.lyreapp.usage-search")

    init(defaults: UserDefaults = .standard, fileURL: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.fileURL = fileURL ?? Diagnostics.shared.directory.appendingPathComponent("usage-waiting.json")
        self.now = now
        sessionStart = now()
        if let data = try? Data(contentsOf: self.fileURL), let saved = try? JSONDecoder().decode([Event].self, from: data) {
            events = saved
        }
        if defaults.object(forKey: "UsageStatsInstallDate") == nil { defaults.set(now(), forKey: "UsageStatsInstallDate") }
    }

    private var enabled: Bool { defaults.bool(forKey: Self.enabledKey) }

    /// At launch (AppDelegate): the player in use, the session's start, and its comings
    /// and goings from now on; and yesterday's events sent.
    func start() {
        playerShown(defaults.string(forKey: "LyrePlayerStyle") ?? "classic")
        sessionBegan()
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] _ in
            self?.becameActive()
            self?.sendIfDue()
        }
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
            self?.resignedActive()
        }
        sendIfDue()
    }

    // MARK: What's Recorded

    /// Lyre launched, or back after a while away: a session, whose first play is timed.
    func sessionBegan() {
        lock.withLock {
            sessionStart = now()
            playedThisSession = false
        }
        // The first session counted on this phone: how many there are to find each feature.
        if enabled, !defaults.bool(forKey: "UsageStatsCountedInstall") {
            defaults.set(true, forKey: "UsageStatsCountedInstall")
            record("install")
        }
        record("launch")
    }

    /// Back in the foreground: a new session if it's been away a while.
    func becameActive() {
        let away = lock.withLock { lastActive.map { now().timeIntervalSince($0) } ?? 0 }
        if away >= Self.sessionGap { sessionBegan() }
    }

    func resignedActive() {
        lock.withLock { lastActive = now() }
        save()
    }

    /// A screen came up (from Diagnostics.show: a page's kind, a shelf, a player, never a
    /// name). The one before, left within two seconds, was a dead end.
    func screenShown(_ name: String) {
        let kind = Self.screenKind(name)
        if kind.hasPrefix("Player: ") { return playerShown(String(kind.dropFirst("Player: ".count))) }
        let left = lock.withLock { () -> (String, TimeInterval)? in
            defer { screen = (kind, now()) }
            guard let screen, screen.name != kind else { return nil }
            return (screen.name, now().timeIntervalSince(screen.since))
        }
        if let (previous, seconds) = left, seconds < Self.bounceSeconds {
            record("bounce", screen: previous, value: (seconds * 10).rounded() / 10)
        }
        record("screen", screen: kind)
        if let feature = Self.feature(forScreen: kind) { used(feature) }
    }

    /// The player in use (at launch, or switched to): a switch says how long the last one was used.
    func playerShown(_ name: String) {
        let switched = lock.withLock { () -> (String, TimeInterval)? in
            defer { player = (name, now()); playersToday.insert(name) }
            guard let player, player.name != name else { return nil }
            return (player.name, now().timeIntervalSince(player.since))
        }
        if let (from, seconds) = switched {
            record("player_switch", detail: from, value: seconds.rounded())
        }
    }

    /// Playback started from inside Lyre: where from (the screen showing, unless it was
    /// Up Next), and for the session's first, how long it took to get there.
    func played(from source: String? = nil) {
        let source = source ?? Self.source(forScreen: lock.withLock { screen?.name })
        let first = lock.withLock { () -> TimeInterval? in
            guard !playedThisSession else { return nil }
            playedThisSession = true
            return now().timeIntervalSince(sessionStart)
        }
        if let first { record("first_play", source: source, value: (first * 10).rounded() / 10) }
        record("play", source: source)
    }

    /// A search's results, as typing pauses: counted once it has for 1.5 s, as found
    /// something or nothing. Never the words.
    func searched(found: Bool) {
        let item = DispatchWorkItem { [weak self] in self?.record("search", detail: found ? "found" : "empty") }
        searchQueue.sync {
            pendingSearch?.cancel()
            pendingSearch = item
        }
        searchQueue.asyncAfter(deadline: .now() + 1.5, execute: item)
    }

    func hang(milliseconds: Int, screen: String) {
        record("hang", screen: Self.screenKind(screen), value: Double(milliseconds))
    }

    func error(_ kind: String) {
        record("error", detail: kind)
    }

    enum Feature: String, CaseIterable {
        case songsShelf, discover, cardDeck, cardSwipe, cardFullScreen, shuffle, swipeToQueue,
             love, addToPlaylist, reportProblem, shareDiagnostics, search
    }

    /// A feature used: each use counted, and the first ever on this install too.
    func used(_ feature: Feature) {
        let key = "UsageStatsFound.\(feature.rawValue)"
        let first = !defaults.bool(forKey: key)
        if first { defaults.set(true, forKey: key) }
        if first { record("feature_first", detail: feature.rawValue) }
        record("feature", detail: feature.rawValue)
    }

    private func record(_ name: String, screen: String? = nil, source: String? = nil, detail: String? = nil, value: Double? = nil) {
        guard enabled else { return }
        let event = makeEvent(name, screen: screen, source: source, detail: detail, value: value)
        lock.withLock {
            events.append(event)
            if events.count > Self.maxWaiting { events.removeFirst(events.count - Self.maxWaiting) }
        }
    }

    private func makeEvent(_ name: String, screen: String?, source: String?, detail: String?, value: Double?) -> Event {
        let info = Bundle.main.infoDictionary
        let today = now()
        let installed = defaults.object(forKey: "UsageStatsInstallDate") as? Date ?? today
        let calendar = Calendar(identifier: .iso8601)
        let week = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: installed)
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return Event(name: name, player: lock.withLock { player?.name } ?? defaults.string(forKey: "LyrePlayerStyle") ?? "classic",
                     screen: screen, source: source, detail: detail, value: value,
                     date: Self.dayString(today),
                     day: max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: installed),
                                                         to: calendar.startOfDay(for: today)).day ?? 0),
                     cohort: String(format: "%04d-W%02d", week.yearForWeekOfYear ?? 0, week.weekOfYear ?? 0),
                     version: info?["CFBundleShortVersionString"] as? String ?? "?",
                     build: info?["CFBundleVersion"] as? String ?? "?",
                     device: Self.device,
                     os: "\(os.majorVersion)")
    }

    // MARK: Waiting and Sending

    /// What's waiting to go.
    func waiting() -> [Event] { lock.withLock { events } }

    /// Each player used today, as an "active" event (once a day each), then the batch.
    func takeBatch() -> [Event] {
        let players = lock.withLock { () -> Set<String> in
            let today = playersToday
            playersToday = player.map { [$0.name] } ?? []
            return today
        }
        for name in players.sorted() {
            if enabled {
                var event = makeEvent("active", screen: nil, source: nil, detail: nil, value: nil)
                event.player = name
                lock.withLock { events.append(event) }
            }
        }
        return lock.withLock { () -> [Event] in
            defer { events = [] }
            return events
        }
    }

    /// Written down on leaving for the background; turned off meanwhile, thrown away instead.
    func save() {
        guard enabled else { return discard() }
        let snapshot = waiting()
        if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: fileURL, options: .atomic) }
    }

    private func discard() {
        lock.withLock { events = [] }
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Sends what's waiting, if it's been a day since the last: signed, as reports are.
    func sendIfDue(configuration: ProblemReporter.Configuration? = ProblemReporter.bundledConfiguration(),
                   attestor: AppAttestor? = .shared, session: URLSession = .shared) {
        guard enabled, let configuration, !AppEnvironment.isUITesting else { return }
        let last = defaults.object(forKey: "UsageStatsLastSent") as? Date ?? .distantPast
        guard now().timeIntervalSince(last) >= Self.sendInterval else { return }
        let batch = takeBatch()
        guard !batch.isEmpty, let body = try? JSONEncoder().encode(["events": batch]) else { return }
        Task.detached(priority: .utility) {
            var request = URLRequest(url: configuration.relayURL.appendingPathComponent("v1/usage"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(configuration.appKey, forHTTPHeaderField: "X-Lyre-Key")
            if let attestor {
                await attestor.enrol(with: configuration, session: session)
                if let signed = await attestor.sign(body) {
                    request.setValue(signed.keyID, forHTTPHeaderField: "X-Lyre-Key-ID")
                    request.setValue(signed.assertion, forHTTPHeaderField: "X-Lyre-Assertion")
                }
            }
            request.httpBody = body
            let status = (try? await session.data(for: request)).flatMap { ($0.1 as? HTTPURLResponse)?.statusCode } ?? 0
            if (200..<300).contains(status) || status == 400 {
                self.defaults.set(self.now(), forKey: "UsageStatsLastSent")
                logger.info("Usage statistics sent (\(status)), \(batch.count) events")
            } else {
                // Not taken: back in the queue for next time (tomorrow, if it's had its share today).
                if status == 429 { self.defaults.set(self.now(), forKey: "UsageStatsLastSent") }
                self.lock.withLock {
                    self.events.insert(contentsOf: batch, at: 0)
                    if self.events.count > Self.maxWaiting { self.events.removeFirst(self.events.count - Self.maxWaiting) }
                }
                self.save()
            }
        }
    }

    // MARK: Kinds

    /// A screen's kind, with any count taken off ("Liquid: card deck, 12 cards" → "Liquid: card deck").
    static func screenKind(_ name: String) -> String {
        name.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? name
    }

    /// Where a play started, from the screen showing.
    static func source(forScreen screen: String?) -> String {
        guard let screen else { return "other" }
        if screen.contains("card deck") { return "card" }
        if screen.hasSuffix("search") { return "search" }
        if screen.hasSuffix("discover") { return "discover" }
        if screen.hasPrefix("Shelf: ") { return "shelf" }
        if ["Liquid: album", "Liquid: playlist", "Liquid: show", "Liquid: artist"].contains(screen) { return "page" }
        if screen.hasPrefix("Liquid: ") { return screen == "Liquid: menu" ? "menu" : "list" }
        return "other"
    }

    static func feature(forScreen screen: String) -> Feature? {
        if screen == "Shelf: songs" { return .songsShelf }
        if screen.hasSuffix("discover") { return .discover }
        if screen.contains("card deck") { return .cardDeck }
        if screen.hasSuffix("search") { return .search }
        return nil
    }

    /// Phone or iPad (the model's family, never the model).
    static let device: String = {
        let model = Diagnostics.hardwareModel()
        return model.hasPrefix("iPad") ? "pad" : model.hasPrefix("iPhone") ? "phone" : "other"
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func dayString(_ date: Date) -> String { dayFormatter.string(from: date) }
}
