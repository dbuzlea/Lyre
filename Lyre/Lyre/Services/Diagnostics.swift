//
//  Diagnostics.swift
//  Lyre
//

import Foundation
import OSLog
import UIKit
import MachO

// MARK: - Diagnostics
//
// What Lyre keeps on the phone so a problem can be found afterwards, by the listener
// sharing it (Share Diagnostics, in every player's settings) rather than by reproducing
// it with a cable attached:
//
//   the log      notable events, a line each, in a file that rolls over at 1 MB (the
//                last two kept, so about 2 MB: several days of ordinary use). Each is
//                also sent to the system log under the same category.
//   breadcrumbs  launch, going to the background and back, the player switched to, the
//                pages, cards and shelves opened, library loads (how long, how many),
//                playback starting: what led up to whatever went wrong.
//   hangs        the main thread blocked for more than a quarter of a second, how long
//                and on which screen (HangWatcher).
//   MetricKit    iOS's own reports (crashes, hangs, CPU and disk exceptions, with call
//                stacks; and the daily metrics), saved whole as JSON, the newest 20.
//   the build    version, build and the binary's UUID, written at every launch, so a
//                crash report can be matched to the debug symbols that read it.
//
// Nothing personal goes in: no song, album, artist or playlist names, no account. A
// line names a kind of thing (a page, a shelf, a count), never what's in your library.
// Nothing leaves the phone unless the listener shares it.

nonisolated final class Diagnostics: @unchecked Sendable {
    static let shared = Diagnostics()

    enum Category: String, CaseIterable {
        case app, navigation, library, playback, artwork, hang, metrics, error
    }

    enum Level: String {
        case info, notice, error, fault
    }

    private let queue = DispatchQueue(label: "com.pinkhatcreations.lyreapp.diagnostics", qos: .utility)
    private let lock = NSLock()
    private var loggers: [Category: Logger] = [:]
    private var _screen = "launch"

    /// Each log file rolls over past this.
    static let maxLogBytes = 1_000_000
    /// MetricKit reports kept.
    static let maxReports = 20

    let directory: URL
    var logURL: URL { directory.appendingPathComponent("lyre.log") }
    var previousLogURL: URL { directory.appendingPathComponent("lyre.1.log") }
    var reportsDirectory: URL { directory.appendingPathComponent("MetricKit", isDirectory: true) }

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Diagnostics", isDirectory: true)
        self.directory = base
        try? FileManager.default.createDirectory(at: base.appendingPathComponent("MetricKit", isDirectory: true),
                                                 withIntermediateDirectories: true)
        var url = base
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// The screen showing, for the hang watcher and the log: kept up to date by the
    /// players as pages, cards and shelves open.
    var screen: String {
        get { lock.withLock { _screen } }
        set { lock.withLock { _screen = newValue } }
    }

    // MARK: Recording

    /// Writes a line to the log file and the system log. `message` must hold nothing
    /// personal (see above): it goes into the system log as public.
    func record(_ category: Category, _ message: String, level: Level = .notice) {
        let logger = lock.withLock { () -> Logger in
            if let logger = loggers[category] { return logger }
            let logger = Logger(subsystem: "com.pinkhatcreations.lyreapp", category: "Diagnostics." + category.rawValue)
            loggers[category] = logger
            return logger
        }
        switch level {
        case .info: logger.info("\(message, privacy: .public)")
        case .notice: logger.notice("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        case .fault: logger.fault("\(message, privacy: .public)")
        }
        let line = "\(Self.timestamp(Date())) [\(level.rawValue)] [\(category.rawValue)] \(message)\n"
        queue.async { self.append(line) }
    }

    /// The navigation breadcrumb and the screen the hang watcher names, at once.
    func show(_ screen: String) {
        self.screen = screen
        record(.navigation, screen, level: .info)
        if self === Diagnostics.shared { UsageStats.shared.screenShown(screen) }
    }

    /// Waits for the lines written so far to reach the file (sharing, tests).
    func flush() {
        queue.sync {}
    }

    private func append(_ line: String) {
        let data = Data(line.utf8)
        let manager = FileManager.default
        if let size = (try? manager.attributesOfItem(atPath: logURL.path))?[.size] as? Int, size + data.count > Self.maxLogBytes {
            try? manager.removeItem(at: previousLogURL)
            try? manager.moveItem(at: logURL, to: previousLogURL)
        }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: logURL)
        }
    }

    // MARK: MetricKit

    /// Keeps a MetricKit report whole, as iOS gave it, dropping the oldest past
    /// `maxReports`. `kind` is "diagnostic" or "metrics".
    func saveReport(_ json: Data, kind: String, date: Date = Date()) {
        queue.async {
            let name = "\(kind)-\(Self.fileTimestamp(date)).json"
            try? json.write(to: self.reportsDirectory.appendingPathComponent(name))
            let reports = self.savedReports()
            for old in reports.dropFirst(Self.maxReports) { try? FileManager.default.removeItem(at: old) }
        }
    }

    /// The saved MetricKit reports, newest first.
    func savedReports() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: reportsDirectory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    // MARK: The Build

    /// Which Lyre this is, on what: written at launch and at the top of what's shared.
    static func buildSummary() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let process = ProcessInfo.processInfo
        return "Lyre \(version) (\(build)), binary \(binaryUUID() ?? "?"), \(hardwareModel()), "
            + "iOS \(process.operatingSystemVersionString), \(process.isLowPowerModeEnabled ? "Low Power Mode" : "normal power"), "
            + "\(Locale.current.identifier)"
    }

    /// The main binary's UUID, as crash reports and debug symbols name it.
    static func binaryUUID() -> String? {
        guard let header = _dyld_get_image_header(0) else { return nil }
        var command = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
        for _ in 0..<header.pointee.ncmds {
            let load = command.assumingMemoryBound(to: load_command.self).pointee
            if load.cmd == LC_UUID {
                let uuid = command.assumingMemoryBound(to: uuid_command.self).pointee.uuid
                return UUID(uuid: uuid).uuidString
            }
            command = command.advanced(by: Int(load.cmdsize))
        }
        return nil
    }

    /// The model identifier (iPhone18,4), which names the exact phone.
    static func hardwareModel() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    // MARK: Sharing

    /// Everything to share, written fresh: a summary with this session's system log,
    /// the log files, and the MetricKit reports. Slow (it reads the system log), so it
    /// runs off the main thread.
    func exportFiles() async -> [URL] {
        flush()
        let summaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Lyre-Diagnostics-\(Self.fileTimestamp(Date())).txt")
        var text = "Lyre diagnostics, \(Self.timestamp(Date()))\n\(Self.buildSummary())\n"
        text += "Screen: \(screen)\n\n"
        text += "— This session's system log (notices and above) —\n"
        text += Self.sessionLog()
        try? text.write(to: summaryURL, atomically: true, encoding: .utf8)
        let logs = [previousLogURL, logURL].filter { FileManager.default.fileExists(atPath: $0.path) }
        return [summaryURL] + logs + savedReports()
    }

    /// Lyre's own entries in the system log since launch, notices and above.
    private static func sessionLog() -> String {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return "(unavailable)\n" }
        let predicate = NSPredicate(format: "subsystem == %@", "com.pinkhatcreations.lyreapp")
        guard let entries = try? store.getEntries(matching: predicate) else { return "(unavailable)\n" }
        var lines: [String] = []
        for case let entry as OSLogEntryLog in entries where entry.level.rawValue >= OSLogEntryLog.Level.notice.rawValue {
            lines.append("\(timestamp(entry.date)) [\(entry.category)] \(entry.composedMessage)")
        }
        return lines.suffix(2000).joined(separator: "\n") + "\n"
    }

    // MARK: Time

    private static let stampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .current
        return formatter
    }()

    static func timestamp(_ date: Date) -> String { stampFormatter.string(from: date) }

    static func fileTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss-SSS"
        return formatter.string(from: date)
    }
}

// MARK: - Hang Watcher

/// Notices the main thread being blocked: every half second a background thread asks
/// the main thread to answer, and if it hasn't within a quarter of a second, waits for
/// it and logs how long it took and on which screen. Only while Lyre is active: a
/// suspended app's main thread doesn't answer either, and that isn't a hang.
nonisolated final class HangWatcher: @unchecked Sendable {
    static let shared = HangWatcher()

    /// Longer than this is a hang.
    static let threshold: TimeInterval = 0.25
    private let diagnostics: Diagnostics
    /// Only watched while Lyre is active (always, for a test, whose host isn't).
    private let requiresActive: Bool
    private let lock = NSLock()
    private var isActive = true
    private var thread: Thread?

    init(diagnostics: Diagnostics = .shared, requiresActive: Bool = true) {
        self.diagnostics = diagnostics
        self.requiresActive = requiresActive
    }

    func start() {
        guard thread == nil else { return }
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] _ in
            self?.lock.withLock { self?.isActive = true }
        }
        center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: nil) { [weak self] _ in
            self?.lock.withLock { self?.isActive = false }
        }
        let thread = Thread { [weak self] in self?.watch() }
        thread.name = "Lyre hang watcher"
        thread.qualityOfService = .utility
        thread.start()
        self.thread = thread
    }

    private var active: Bool { !requiresActive || lock.withLock { isActive } }

    private func watch() {
        while true {
            Thread.sleep(forTimeInterval: 0.5)
            guard active else { continue }
            let answered = DispatchSemaphore(value: 0)
            let asked = Date()
            DispatchQueue.main.async { answered.signal() }
            guard answered.wait(timeout: .now() + Self.threshold) == .timedOut else { continue }
            let screen = diagnostics.screen
            answered.wait()
            // Left the foreground meanwhile: the wait was the suspension, not a hang.
            guard active else { continue }
            let ms = Int(Date().timeIntervalSince(asked) * 1000)
            diagnostics.record(.hang, "Main thread blocked \(ms) ms on \(screen)",
                               level: ms >= 2000 ? .error : .notice)
            if diagnostics === Diagnostics.shared { UsageStats.shared.hang(milliseconds: ms, screen: screen) }
        }
    }
}
