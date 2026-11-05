//
//  ProblemReporter.swift
//  Lyre
//

import Foundation
import UIKit
import OSLog

private let logger = Logger(subsystem: "com.pinkhatcreations.lyreapp", category: "ProblemReporter")

// MARK: - Problem Reporter
//
// Sends problem reports to Lyre's relay (relay/README.md), which files them in Jira:
// a listener's own (Report a Problem, in every player's settings) and, from phase 2 and
// only if they've turned on Send Diagnostics Automatically, ones Lyre catches itself.
//
// A report carries what finds the cause and nothing personal: Lyre's version, build and
// binary UUID, the phone's model and iOS, the player in use, the diagnostics log's last
// lines (Diagnostics, which names no songs), and what the listener chose to add (their
// words, a screenshot). Each goes into an outbox on the phone first and is sent from
// there, so one written offline goes when Lyre next can.
//
// Where the relay is, and the key it asks for, come from Relay.plist (RelayURL, AppKey),
// which isn't committed. Without it, reports wait in the outbox.

nonisolated final class ProblemReporter: @unchecked Sendable {
    static let shared = ProblemReporter()

    /// The listener's choice to send what Lyre catches itself (phase 2): off until they
    /// turn it on.
    static let automaticKey = "SendDiagnosticsAutomatically"
    static var sendsAutomatically: Bool {
        get { UserDefaults.standard.bool(forKey: automaticKey) }
        set { UserDefaults.standard.set(newValue, forKey: automaticKey) }
    }

    struct Configuration {
        let relayURL: URL
        let appKey: String
    }

    let outbox: URL
    private let configuration: Configuration?
    private let session: URLSession
    private let queue = DispatchQueue(label: "com.pinkhatcreations.lyreapp.problem-reporter", qos: .utility)
    private var isSending = false

    /// Reports kept waiting at most; the oldest go first.
    static let maxWaiting = 30

    init(outbox: URL? = nil, configuration: Configuration? = ProblemReporter.bundledConfiguration(),
         session: URLSession = .shared) {
        self.outbox = outbox ?? Diagnostics.shared.directory.appendingPathComponent("Outbox", isDirectory: true)
        self.configuration = configuration
        self.session = session
        try? FileManager.default.createDirectory(at: self.outbox, withIntermediateDirectories: true)
    }

    static func bundledConfiguration() -> Configuration? {
        guard let url = Bundle.main.url(forResource: "Relay", withExtension: "plist"),
              let values = NSDictionary(contentsOf: url),
              let address = values["RelayURL"] as? String, let relayURL = URL(string: address),
              let appKey = values["AppKey"] as? String, !appKey.isEmpty else { return nil }
        return Configuration(relayURL: relayURL, appKey: appKey)
    }

    var isConfigured: Bool { configuration != nil }

    // MARK: Reports

    enum Kind: String { case user, metrickit, detector }

    /// A report, as the relay takes it (relay/src/report.ts).
    struct Report: Codable {
        struct App: Codable { let version, build: String; let binaryUUID: String?; let player: String? }
        struct Device: Codable { let model, os: String }
        struct File: Codable { let name, contentType, base64: String }
        let kind: String
        let title: String
        let description: String?
        let signature: String?
        let stack: String?
        let app: App
        let device: Device
        let installID: String
        let logTail: String?
        let files: [File]?
    }

    /// Makes a report with what every report carries, and the log's last lines. `build`
    /// is the build it happened in, when that's known and may not be this one (a
    /// MetricKit report arrives on a later launch, perhaps after an update).
    func makeReport(kind: Kind, title: String, description: String? = nil, signature: String? = nil,
                    stack: String? = nil, files: [Report.File] = [], player: String? = nil,
                    build: String? = nil) -> Report {
        let info = Bundle.main.infoDictionary
        return Report(
            kind: kind.rawValue,
            title: String(title.prefix(200)),
            description: description.map { String($0.prefix(5000)) },
            signature: signature,
            stack: stack,
            app: .init(version: info?["CFBundleShortVersionString"] as? String ?? "?",
                       build: build ?? info?["CFBundleVersion"] as? String ?? "?",
                       binaryUUID: Diagnostics.binaryUUID(),
                       player: player ?? UserDefaults.standard.string(forKey: "LyrePlayerStyle")),
            device: .init(model: Diagnostics.hardwareModel(),
                          os: "iOS \(ProcessInfo.processInfo.operatingSystemVersionString)"),
            installID: Self.installID(),
            logTail: Self.logTail(),
            files: files.isEmpty ? nil : files
        )
    }

    /// Puts a report in the outbox and sends what's waiting.
    func submit(_ report: Report) {
        queue.async {
            guard let data = try? JSONEncoder().encode(report) else { return }
            let name = "\(Diagnostics.fileTimestamp(Date()))-\(UUID().uuidString.prefix(8)).json"
            try? data.write(to: self.outbox.appendingPathComponent(name))
            self.trim()
            Diagnostics.shared.record(.app, "Problem report queued (\(report.kind))", level: .info)
        }
        sendWaiting()
    }

    /// The reports waiting, oldest first.
    func waiting() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: outbox, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func trim() {
        for old in waiting().dropLast(Self.maxWaiting) { try? FileManager.default.removeItem(at: old) }
    }

    /// Sends what's waiting, one at a time, oldest first; stops at the first that can't
    /// go (offline, the relay down), to try again later. A report the relay turns down
    /// as malformed is dropped rather than retried for ever.
    func sendWaiting() {
        queue.async {
            guard let configuration = self.configuration, !self.isSending else { return }
            self.isSending = true
            let files = self.waiting()
            Task.detached(priority: .utility) {
                for file in files {
                    guard let body = try? Data(contentsOf: file) else { continue }
                    var request = URLRequest(url: configuration.relayURL.appendingPathComponent("v1/reports"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(configuration.appKey, forHTTPHeaderField: "X-Lyre-Key")
                    request.httpBody = body
                    let status = (try? await self.session.data(for: request))
                        .flatMap { ($0.1 as? HTTPURLResponse)?.statusCode } ?? 0
                    if (200..<300).contains(status) || status == 400 || status == 413 {
                        try? FileManager.default.removeItem(at: file)
                        Diagnostics.shared.record(.app, "Problem report sent (\(status))", level: status < 300 ? .info : .error)
                    } else {
                        logger.notice("Problem report not sent (\(status)); kept for later")
                        break
                    }
                }
                self.queue.async { self.isSending = false }
            }
        }
    }

    // MARK: Parts

    /// A random id this install made for itself, for the relay's hourly limit: it
    /// names no one.
    static func installID() -> String {
        let key = "ProblemReporterInstallID"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    /// The diagnostics log's last lines.
    static func logTail(lines: Int = 60) -> String? {
        Diagnostics.shared.flush()
        guard let text = try? String(contentsOf: Diagnostics.shared.logURL, encoding: .utf8) else { return nil }
        return text.split(separator: "\n").suffix(lines).joined(separator: "\n")
    }
}

// MARK: - Asking Once

/// Asks the listener, once, whether Lyre may send its own reports of crashes and freezes
/// (ProblemReporter.sendsAutomatically): on a launch after the one that set Lyre up, a
/// few seconds in, so it isn't one more thing to answer while setting up. Either answer
/// counts as asked; Settings change it after.
enum DiagnosticsConsent {
    static let askedKey = "DiagnosticsConsentAsked"
    static let launchesKey = "DiagnosticsConsentLaunches"

    /// Counted at each launch (AppDelegate).
    static func countLaunch() {
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: launchesKey) + 1, forKey: launchesKey)
    }

    /// Whether to ask now: set up, not asked, past the first launch, not a UI test.
    static func isDue(onboarded: Bool, defaults: UserDefaults = .standard,
                      isUITesting: Bool = AppEnvironment.isUITesting) -> Bool {
        onboarded && !isUITesting && !defaults.bool(forKey: askedKey) && defaults.integer(forKey: launchesKey) >= 2
    }

    @MainActor
    static func askIfDue(onboarded: Bool) async {
        guard isDue(onboarded: onboarded) else { return }
        try? await Task.sleep(for: .seconds(4))
        guard isDue(onboarded: onboarded),
              let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first,
              var top = window.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        let alert = UIAlertController(title: String(localized: "diagnostics.ask.title"),
                                      message: String(localized: "diagnostics.ask.message"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "diagnostics.ask.notNow"), style: .cancel) { _ in
            answer(false)
        })
        let allow = UIAlertAction(title: String(localized: "diagnostics.ask.allow"), style: .default) { _ in answer(true) }
        alert.addAction(allow)
        alert.preferredAction = allow
        top.present(alert, animated: true)
    }

    private static func answer(_ sends: Bool) {
        UserDefaults.standard.set(true, forKey: askedKey)
        ProblemReporter.sendsAutomatically = sends
        Diagnostics.shared.record(.app, "Automatic diagnostics \(sends ? "allowed" : "declined")")
    }
}
