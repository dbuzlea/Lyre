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
            if !newValue { shared.discard(); shared.forgetOnboarding() }
        }
    }

    /// A page left this soon is a dead end.
    static let bounceSeconds: TimeInterval = 2
    /// Back to the screen before within this long: a loop (looked, and went back).
    static let loopSeconds: TimeInterval = 15
    /// A play this soon after a search settles is a play from it.
    static let searchPlaySeconds: TimeInterval = 120
    /// A song changed within this much of it is a skip.
    static let skipSeconds: TimeInterval = 30
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
    /// Screens shown this session before its first play, and the two before this one (for loops).
    private var screensBeforePlay = 0
    private var screenBefore: String?
    /// Where the music playing was started, and when; and the next play's a Shuffle.
    private var playSource: String?
    private var playStartedAt: Date?
    private var nextPlayIsShuffle = false
    /// A song skipped from Lyre's own controls just now: forward or back.
    private var inAppSkip: (back: Bool, at: Date)?
    /// Since when music has played without stopping, and whether Lyre went to the background meanwhile.
    private var playingSince: Date?
    private var playedInBackground = false
    /// The last search to settle: when, and whether anything was played from it yet.
    private var lastSearch: (at: Date, played: Bool)?
    /// The Classic wheel since its last press: steps turned, and turns back.
    private var wheelSteps = 0
    private var wheelReversals = 0
    private var wheelLastDown: Bool?
    /// The library's size and subscription, as last loaded (for the daily snapshot).
    private var libraryContext: [String] = []
    /// The daily snapshot of settings and accessibility (start() sets it; nil in tests).
    var snapshot: (() -> [(name: String, detail: String)])?
    private var tapWatcher: RepeatedTapWatcher?

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
        snapshot = { UsageSnapshot.current() }
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] _ in
            self?.becameActive()
            self?.watchTaps()
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
            screensBeforePlay = 0
        }
        searchEnded()
        reportOnboarding()
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
        lock.withLock {
            lastActive = now()
            if playingSince != nil { playedInBackground = true }
        }
        save()
    }

    /// A screen came up (from Diagnostics.show: a page's kind, a shelf, a player, never a
    /// name). The one before, left within two seconds, was a dead end.
    func screenShown(_ name: String) {
        let kind = Self.screenKind(name)
        if kind.hasPrefix("Player: ") { return playerShown(String(kind.dropFirst("Player: ".count))) }
        let left = lock.withLock { () -> (name: String, seconds: TimeInterval, looped: Bool)? in
            if !playedThisSession { screensBeforePlay += 1 }
            guard let current = screen else { screen = (kind, now()); return nil }
            guard current.name != kind else { return nil }
            defer { screenBefore = current.name; screen = (kind, now()) }
            return (current.name, now().timeIntervalSince(current.since), screenBefore == kind)
        }
        if let left, left.seconds < Self.bounceSeconds {
            record("bounce", screen: left.name, value: (left.seconds * 10).rounded() / 10)
        }
        // Back where it was just before, from a screen looked at and left: a loop.
        if let left, left.looped, left.seconds < Self.loopSeconds {
            record("loop", screen: left.name, value: left.seconds.rounded())
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
    /// `kind` says what was started: "library", "streamed" or "episode".
    func played(from source: String? = nil, kind: String? = nil) {
        let (source, first, screens, fromSearch) = lock.withLock { () -> (String, TimeInterval?, Int, TimeInterval?) in
            var source = source ?? Self.source(forScreen: screen?.name)
            if nextPlayIsShuffle { source = "shuffle"; nextPlayIsShuffle = false }
            playSource = source
            playStartedAt = now()
            var fromSearch: TimeInterval?
            if let search = lastSearch, !search.played, now().timeIntervalSince(search.at) < Self.searchPlaySeconds {
                fromSearch = now().timeIntervalSince(search.at)
                lastSearch?.played = true
            }
            guard !playedThisSession else { return (source, nil, 0, fromSearch) }
            playedThisSession = true
            return (source, now().timeIntervalSince(sessionStart), screensBeforePlay, fromSearch)
        }
        if let first {
            record("first_play", source: source, value: (first * 10).rounded() / 10)
            record("first_play_path", source: source, value: Double(screens))
        }
        if let fromSearch { record("search_play", detail: kind, value: (fromSearch * 10).rounded() / 10) }
        record("play", source: source, detail: kind)
    }

    // MARK: Listening

    /// Lyre's own skip buttons, just before the song changes.
    func skipped(back: Bool) {
        lock.withLock { inAppSkip = (back, now()) }
    }

    /// The song playing changed, seen while Lyre was in the foreground: how the last one
    /// went (skipped in its first 30 s, heard in part, or to the end), and from where it
    /// was started. Not counted when a new play replaced it.
    func songChanged(heard: TimeInterval, duration: TimeInterval) {
        guard duration > 0 else { return }
        let (source, outcome) = lock.withLock { () -> (String?, String?) in
            defer { inAppSkip = nil }
            if let started = playStartedAt, now().timeIntervalSince(started) < 3 { return (nil, nil) }
            let skip = inAppSkip.flatMap { now().timeIntervalSince($0.at) < 3 ? $0 : nil }
            if skip?.back == true { return (playSource, "back") }
            let outcome = heard >= min(duration - 10, duration * 0.9) ? "complete"
                : heard < Self.skipSeconds ? (skip == nil ? "skip-elsewhere" : "skip") : "partial"
            return (playSource, outcome)
        }
        guard let outcome else { return }
        record("song_end", source: source ?? "other", detail: outcome, value: heard.rounded())
    }

    /// Music started or stopped: a stretch of listening is counted when it stops, and
    /// whether it went on while Lyre was in the background.
    func playbackChanged(isPlaying: Bool) {
        let stretch = lock.withLock { () -> (TimeInterval, Bool)? in
            if isPlaying {
                if playingSince == nil { playingSince = now(); playedInBackground = false }
                return nil
            }
            guard let since = playingSince else { return nil }
            defer { playingSince = nil; playedInBackground = false }
            return (now().timeIntervalSince(since), playedInBackground)
        }
        if let (seconds, background) = stretch, seconds >= 5 {
            record("listen", source: lock.withLock { playSource } ?? "other",
                   detail: background ? "background" : "foreground", value: seconds.rounded())
        }
    }

    /// A search's results, as typing pauses: counted once it has for 1.5 s, as found
    /// something or nothing. Never the words.
    func searched(found: Bool, length: Int = 0) {
        let size = length <= 3 ? "1-3" : length <= 7 ? "4-7" : "8+"
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.searchEnded()
            self.lock.withLock { self.lastSearch = (self.now(), false) }
            self.record("search", source: size, detail: found ? "found" : "empty")
        }
        searchQueue.sync {
            pendingSearch?.cancel()
            pendingSearch = item
        }
        searchQueue.asyncAfter(deadline: .now() + 1.5, execute: item)
    }

    /// A search result chosen, by its place in the list (where a player lists them in order).
    func searchChosen(rank: Int) {
        record("search_rank", value: Double(rank + 1))
    }

    /// The last search, if nothing was played from it, counted as one that led nowhere.
    private func searchEnded() {
        let unplayed = lock.withLock { () -> Bool in
            defer { lastSearch = nil }
            return lastSearch.map { !$0.played } ?? false
        }
        if unplayed { record("search_no_play") }
    }

    // MARK: The Classic Wheel

    /// One step of the wheel: counted, and a turn back noted.
    func wheelStepped(down: Bool) {
        lock.withLock {
            wheelSteps += 1
            if let last = wheelLastDown, last != down { wheelReversals += 1 }
            wheelLastDown = down
        }
    }

    /// The centre pressed: how far the wheel turned to get there, and how often it turned
    /// back (overshooting), at the sensitivity it's set to.
    func wheelPressed(screen: String, sensitivity: String) {
        let (steps, reversals) = lock.withLock { () -> (Int, Int) in
            defer { wheelSteps = 0; wheelReversals = 0; wheelLastDown = nil }
            return (wheelSteps, wheelReversals)
        }
        guard steps > 0 else { return }
        record("wheel", screen: Self.screenKind(screen), source: sensitivity,
               detail: reversals >= 5 ? "reversals 5+" : "reversals \(reversals)", value: Double(steps))
    }

    // MARK: Repeated Taps

    /// Four taps in one spot within a second and a bit: something that looks tappable
    /// isn't, or is slow to answer. Not counted in the classic player, which is pressed
    /// over and over by design.
    func repeatedTaps() {
        guard lock.withLock({ player?.name }) != "classic" else { return }
        record("repeated_taps", screen: lock.withLock { screen?.name })
    }

    private func watchTaps() {
        guard enabled, tapWatcher == nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.tapWatcher == nil,
                  let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first
            else { return }
            let watcher = RepeatedTapWatcher { [weak self] in self?.repeatedTaps() }
            window.addGestureRecognizer(watcher)
            self.tapWatcher = watcher
        }
    }

    // MARK: Onboarding

    /// Onboarding happens before Lyre can ask, so its steps are kept on the phone, and
    /// sent only if Share Usage Statistics is turned on later (within 30 days).
    func onboardingStep(_ step: String) {
        var steps = defaults.array(forKey: "UsageStatsOnboarding") as? [[String: Any]] ?? []
        if steps.isEmpty { defaults.set(now(), forKey: "UsageStatsOnboardingStarted") }
        steps.append(["step": step, "at": now().timeIntervalSince1970])
        defaults.set(Array(steps.suffix(40)), forKey: "UsageStatsOnboarding")
    }

    func onboardingMusicAccess(granted: Bool) {
        defaults.set(granted ? "granted" : "denied", forKey: "UsageStatsOnboardingAccess")
    }

    func onboardingFinished(player: String) {
        defaults.set(player, forKey: "UsageStatsOnboardingPlayer")
        defaults.set(now(), forKey: "UsageStatsOnboardingFinished")
        if enabled { reportOnboarding() }
    }

    /// What onboarding kept, once it's finished and counting is on: the time on each
    /// step, the whole, music access, and the player chosen; and, a week on, whether
    /// that player's still the one in use.
    private func reportOnboarding() {
        if let finished = defaults.object(forKey: "UsageStatsOnboardingFinished") as? Date {
            if now().timeIntervalSince(finished) > 30 * 86_400 { return forgetOnboarding() }
            guard enabled else { return }
            let chosen = defaults.string(forKey: "UsageStatsOnboardingPlayer") ?? "unknown"
            let steps = (defaults.array(forKey: "UsageStatsOnboarding") as? [[String: Any]] ?? [])
                .compactMap { s -> (String, Double)? in
                    guard let step = s["step"] as? String, let at = s["at"] as? Double else { return nil }
                    return (step, at)
                }
            for (index, step) in steps.enumerated() {
                let next = index + 1 < steps.count ? steps[index + 1].1 : finished.timeIntervalSince1970
                record("onboarding_step", source: chosen, detail: step.0, value: max(0, next - step.1).rounded())
            }
            if let first = steps.first {
                record("onboarding_done", source: chosen, detail: chosen,
                       value: max(0, finished.timeIntervalSince1970 - first.1).rounded())
            }
            if let access = defaults.string(forKey: "UsageStatsOnboardingAccess") { record("music_access", detail: access) }
            defaults.set(chosen, forKey: "UsageStatsKeptPlayer")
            defaults.set(finished, forKey: "UsageStatsKeptSince")
            forgetOnboarding()
        }
        if enabled, let chosen = defaults.string(forKey: "UsageStatsKeptPlayer"),
           let since = defaults.object(forKey: "UsageStatsKeptSince") as? Date,
           now().timeIntervalSince(since) >= 7 * 86_400 {
            record("onboarding_kept", source: lock.withLock { player?.name } ?? "unknown", detail: chosen)
            defaults.removeObject(forKey: "UsageStatsKeptPlayer")
            defaults.removeObject(forKey: "UsageStatsKeptSince")
        }
    }

    fileprivate func forgetOnboarding() {
        for key in ["UsageStatsOnboarding", "UsageStatsOnboardingStarted", "UsageStatsOnboardingAccess",
                    "UsageStatsOnboardingPlayer", "UsageStatsOnboardingFinished"] {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: Performance and Context

    /// iOS's daily figures (MetricKit), each as a number: launch and resume times, hang
    /// time, scroll hitches, peak memory, and exits that weren't asked for.
    func dailyMetric(_ name: String, value: Double) {
        guard value.isFinite else { return }
        record("metric", detail: name, value: (value * 100).rounded() / 100)
    }

    /// The library as loaded: its size in broad bands, and whether there's a subscription.
    func libraryLoaded(songs: Int, subscribed: Bool?) {
        let band = songs < 500 ? "under 500" : songs < 2000 ? "500-2k" : songs < 10_000 ? "2k-10k" : "10k+"
        var context = ["library:\(band)"]
        if let subscribed { context.append("subscriber:\(subscribed ? "yes" : "no")") }
        lock.withLock { libraryContext = context }
    }

    func hang(milliseconds: Int, screen: String) {
        record("hang", screen: Self.screenKind(screen), value: Double(milliseconds))
    }

    func error(_ kind: String) {
        record("error", detail: kind)
    }

    enum Feature: String, CaseIterable {
        case songsShelf, discover, cardDeck, cardSwipe, cardFullScreen, shuffle, swipeToQueue,
             love, addToPlaylist, reportProblem, shareDiagnostics, search,
             artworkCarousel, lavaMenu, gramophoneDrawer, spoolTape, discInsert, podcastEpisode,
             podcastDownload, addToLibrary, similarArtist
    }

    /// A feature used: each use counted, and the first ever on this install too.
    func used(_ feature: Feature) {
        if feature == .shuffle { lock.withLock { nextPlayIsShuffle = true } }
        guard enabled else { return }
        let key = "UsageStatsFound.\(feature.rawValue)"
        if !defaults.bool(forKey: key) {
            defaults.set(true, forKey: key)
            record("feature_first", detail: feature.rawValue)
        }
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
        // Once a day too: the library's size, settings that differ from Lyre's, and accessibility.
        let context = lock.withLock { libraryContext }.map { (name: "context", detail: $0) } + (snapshot?() ?? [])
        for item in context { record(item.name, detail: item.detail) }
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
        if screen.hasPrefix("Classic: ") {
            if screen.hasSuffix("Detail") { return "page" }
            if screen.contains("discover") { return "discover" }
            if screen.hasSuffix("nowPlaying") || screen.hasSuffix("queue") { return "queue" }
            return screen == "Classic: menu" ? "menu" : "list"
        }
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

// MARK: - The Daily Snapshot

/// Settings set away from Lyre's own, and accessibility in use, as kinds ("theme:dark",
/// "voiceover:on"): which defaults are wrong, and how much each accessibility feature
/// is relied on. Read on the main thread, at most once a day.
nonisolated enum UsageSnapshot {
    /// The settings counted, by their saved key, with the name they're counted by.
    static let settings: [(key: String, name: String)] = [
        ("LyreThemeStyle", "theme"), ("LyreScreenSize", "screen-size"), ("LyreUseAutoScreenSize", "auto-screen-size"),
        ("LyreUseCustomHighlight", "custom-highlight"), ("LyreScrollSensitivity", "wheel-sensitivity"),
        ("LyreClickSoundEnabled", "click-sound"), ("LyreBacklightDuration", "backlight"),
        ("LyreCleanVersions", "clean-versions"), ("LyreLiquidTempoLookup", "tempo-lookup"),
        ("LyreLiquidRipple", "liquid-ripple"), ("LyreSpoolModel", "spool-model"), ("LyreSpoolFinish", "spool-finish"),
        ("LyreGramophoneModel", "gramophone-model"), ("LyreGramophoneFinish", "gramophone-finish"),
        ("LyreGramophoneSurfaceNoise", "surface-noise"), ("LyreDiscFinish", "disc-finish"),
        ("DiscShowsRemaining", "disc-remaining"),
    ]

    static func current(defaults: UserDefaults = .standard) -> [(name: String, detail: String)] {
        var items: [(name: String, detail: String)] = settings.compactMap { setting in
            guard let value = defaults.object(forKey: setting.key) else { return nil }
            return ("setting", "\(setting.name):\(word(value))")
        }
        guard Thread.isMainThread else { return items }
        MainActor.assumeIsolated {
            let on = { (flag: Bool) in flag ? "on" : "off" }
            items += [
                ("a11y", "voiceover:\(on(UIAccessibility.isVoiceOverRunning))"),
                ("a11y", "reduce-motion:\(on(UIAccessibility.isReduceMotionEnabled))"),
                ("a11y", "bold-text:\(on(UIAccessibility.isBoldTextEnabled))"),
                ("a11y", "text-size:\(textSize(UIApplication.shared.preferredContentSizeCategory))"),
            ]
            // Which display it's on (iPhone Duo's inner or outer), by its width in points.
            if let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first {
                items.append(("context", "width:\(Int(window.bounds.width))pt"))
            }
        }
        return items
    }

    /// A saved value as a short word: a Bool as on or off, anything else its letters and digits.
    static func word(_ value: Any) -> String {
        // A real Bool only: a saved number (a backlight of 1) would also read as one.
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "on" : "off" }
        let text = String(describing: value).filter { $0.isLetter || $0.isNumber || "._-".contains($0) }
        return text.isEmpty ? "set" : String(text.prefix(24))
    }

    static func textSize(_ category: UIContentSizeCategory) -> String {
        switch category {
        case .extraSmall, .small, .medium: "smaller"
        case .large: "default"
        case .extraLarge, .extraExtraLarge, .extraExtraExtraLarge: "larger"
        default: category.isAccessibilityCategory ? "accessibility" : "other"
        }
    }
}

// MARK: - Repeated Taps

/// Watches every touch in the window without taking part: four taps within 30 points
/// of each other inside 1.2 s calls `onRepeated`. It never recognises, so nothing
/// waits on it and every touch goes on to the app as usual.
final class RepeatedTapWatcher: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private let onRepeated: () -> Void
    private var taps: [(point: CGPoint, at: TimeInterval)] = []

    init(onRepeated: @escaping () -> Void) {
        self.onRepeated = onRepeated
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first, let view {
            let point = touch.location(in: view)
            let at = touch.timestamp
            taps = taps.filter { at - $0.at < 1.2 && hypot($0.point.x - point.x, $0.point.y - point.y) < 30 } + [(point, at)]
            if taps.count >= 4 {
                taps = []
                onRepeated()
            }
        }
        state = .failed
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
