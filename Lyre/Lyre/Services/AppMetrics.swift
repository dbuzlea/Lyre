//
//  AppMetrics.swift
//  Lyre
//

import Foundation
import MetricKit
import OSLog

private let logger = Logger(subsystem: "com.pinkhatcreations.lyreapp", category: "Metrics")

final class AppMetrics: NSObject, MXMetricManagerSubscriber {
    static let shared = AppMetrics()

    private override init() {}

    func start() {
        MXMetricManager.shared.add(self)
        logger.info("MetricKit subscriber registered")
    }

    func stop() {
        MXMetricManager.shared.remove(self)
    }

    // Called immediately when diagnostics are available (iOS 15+)
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let crashCount = payload.crashDiagnostics?.count ?? 0
            let hangCount = payload.hangDiagnostics?.count ?? 0
            let diskCount = payload.diskWriteExceptionDiagnostics?.count ?? 0
            let cpuCount = payload.cpuExceptionDiagnostics?.count ?? 0

            if crashCount > 0 {
                logger.fault("Crash diagnostics received: \(crashCount) crash(es)")
            }
            if hangCount > 0 {
                logger.error("Hang diagnostics received: \(hangCount) hang(s)")
            }
            if diskCount > 0 {
                logger.warning("Disk write exceptions: \(diskCount)")
            }
            if cpuCount > 0 {
                logger.warning("CPU exceptions: \(cpuCount)")
            }

            if crashCount == 0 && hangCount == 0 && diskCount == 0 && cpuCount == 0 {
                logger.info("Diagnostic payload received (no issues)")
            }

            // Kept whole: its call stacks are what find the cause (Diagnostics).
            Diagnostics.shared.saveReport(payload.jsonRepresentation(), kind: "diagnostic")
            // And to Jira, if the listener has allowed it (ProblemReporter).
            MetricKitReports.report(payload)
            Diagnostics.shared.record(.metrics, "MetricKit diagnostics: \(crashCount) crash, \(hangCount) hang, "
                                      + "\(cpuCount) CPU, \(diskCount) disk write",
                                      level: crashCount + hangCount + cpuCount + diskCount > 0 ? .error : .info)
        }
    }

    // Called at most once per day with aggregated performance data
    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            logger.info("Daily metrics payload received")

            if let launch = payload.applicationLaunchMetrics {
                logger.info("Launch metrics — resumeTime histogram: \(launch.histogrammedApplicationResumeTime)")
            }
            if let memory = payload.memoryMetrics {
                logger.info("Memory metrics — peak: \(memory.peakMemoryUsage)")
            }
            if let exits = payload.applicationExitMetrics {
                let fg = exits.foregroundExitData
                logger.info("Exit metrics — foreground normal: \(fg.cumulativeNormalAppExitCount), abnormal: \(fg.cumulativeAbnormalExitCount)")
            }
            if let responsiveness = payload.applicationResponsivenessMetrics {
                logger.info("Responsiveness — hang time histogram: \(responsiveness.histogrammedApplicationHangTime)")
            }

            Diagnostics.shared.saveReport(payload.jsonRepresentation(), kind: "metrics")
            Diagnostics.shared.record(.metrics, "MetricKit daily metrics saved", level: .info)
            for (name, value) in MetricKitReports.dailyFigures(payload) { UsageStats.shared.dailyMetric(name, value: value) }
        }
    }
}

// MARK: - Automatic Reports

/// iOS's diagnostics, as problem reports (ProblemReporter), sent only if the listener has
/// turned on Send Diagnostics Automatically: a crash, a hang, a CPU or disk-write
/// exception, each with its kind, the build it happened in, Lyre's top frames as a
/// signature (so the relay groups the same problem, and only it), the call stack as text,
/// and the whole diagnostic attached.
enum MetricKitReports {
    struct Problem {
        let title: String
        let signature: String
        let stack: String
        let build: String?
        let json: Data
    }

    static func problems(in payload: MXDiagnosticPayload) -> [Problem] {
        var problems: [Problem] = []
        for crash in payload.crashDiagnostics ?? [] {
            let exception = [crash.exceptionType.map { "exception \($0)" }, crash.signal.map { "signal \($0)" }]
                .compactMap { $0 }.joined(separator: ", ")
            let reason = crash.terminationReason.map { ": \($0.prefix(80))" } ?? ""
            problems.append(problem("Crash (\(exception.isEmpty ? "unknown" : exception))\(reason)",
                                    kind: "crash \(exception)", tree: crash.callStackTree,
                                    build: crash.metaData.applicationBuildVersion, json: crash.jsonRepresentation()))
        }
        for hang in payload.hangDiagnostics ?? [] {
            let seconds = hang.hangDuration.converted(to: .seconds).value
            problems.append(problem(String(format: "Hang %.1f s", seconds), kind: "hang", tree: hang.callStackTree,
                                    build: hang.metaData.applicationBuildVersion, json: hang.jsonRepresentation()))
        }
        for cpu in payload.cpuExceptionDiagnostics ?? [] {
            let used = cpu.totalCPUTime.converted(to: .seconds).value
            let over = cpu.totalSampledTime.converted(to: .seconds).value
            problems.append(problem(String(format: "CPU exception: %.0f s of CPU over %.0f s", used, over), kind: "cpu",
                                    tree: cpu.callStackTree, build: cpu.metaData.applicationBuildVersion,
                                    json: cpu.jsonRepresentation()))
        }
        for disk in payload.diskWriteExceptionDiagnostics ?? [] {
            let megabytes = disk.totalWritesCaused.converted(to: .megabytes).value
            problems.append(problem(String(format: "Disk writes exception: %.0f MB", megabytes), kind: "disk",
                                    tree: disk.callStackTree, build: disk.metaData.applicationBuildVersion,
                                    json: disk.jsonRepresentation()))
        }
        return problems
    }

    private static func problem(_ title: String, kind: String, tree: MXCallStackTree, build: String?, json: Data) -> Problem {
        problem(title, kind: kind, treeJSON: tree.jsonRepresentation(), build: build, json: json)
    }

    static func problem(_ title: String, kind: String, treeJSON: Data, build: String?, json: Data) -> Problem {
        let frames = frames(fromCallStackTree: treeJSON)
        let lyre = frames.filter { $0.binary == "Lyre" }.prefix(3).map { "+\($0.offset)" }
        return Problem(title: title, signature: ([kind] + lyre).joined(separator: " "),
                       stack: frames.prefix(40).enumerated()
                           .map { "\($0.offset) \($0.element.binary) +\($0.element.offset) (\($0.element.uuid))" }
                           .joined(separator: "\n"),
                       build: build, json: json)
    }

    struct Frame: Equatable {
        let binary: String
        let offset: Int
        let uuid: String
    }

    /// The frames of the thread MetricKit names as the culprit (else the first), from the
    /// top of the stack down: MetricKit nests each frame's caller in its `subFrames`.
    static func frames(fromCallStackTree data: Data) -> [Frame] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stacks = root["callStacks"] as? [[String: Any]], !stacks.isEmpty else { return [] }
        let stack = stacks.first { ($0["threadAttributed"] as? Bool) == true } ?? stacks[0]
        var frames: [Frame] = []
        var next = (stack["callStackRootFrames"] as? [[String: Any]])?.first
        while let frame = next, frames.count < 200 {
            frames.append(Frame(binary: frame["binaryName"] as? String ?? "?",
                                offset: frame["offsetIntoBinaryTextSegment"] as? Int ?? 0,
                                uuid: frame["binaryUUID"] as? String ?? "?"))
            next = (frame["subFrames"] as? [[String: Any]])?.first
        }
        return frames
    }

    /// Sends each problem in the payload, if the listener allows it.
    static func report(_ payload: MXDiagnosticPayload, reporter: ProblemReporter = .shared) {
        guard ProblemReporter.sendsAutomatically else { return }
        for problem in problems(in: payload) {
            let file = ProblemReporter.Report.File(name: "metrickit.json", contentType: "application/json",
                                                   base64: problem.json.base64EncodedString())
            reporter.submit(reporter.makeReport(kind: .metrickit, title: problem.title, signature: problem.signature,
                                                stack: problem.stack, files: [file], build: problem.build))
        }
    }

    /// The day's figures usage statistics count: average launch (to first frame) and
    /// resume times and hang time in ms, scroll hitches in ms per second scrolled, peak
    /// memory in MB, and exits in the foreground that weren't asked for.
    static func dailyFigures(_ payload: MXMetricPayload) -> [(String, Double)] {
        var figures: [(String, Double)] = []
        if let launch = payload.applicationLaunchMetrics {
            if let ms = mean(launch.histogrammedTimeToFirstDraw) { figures.append(("launch-ms", ms)) }
            if let ms = mean(launch.histogrammedApplicationResumeTime) { figures.append(("resume-ms", ms)) }
        }
        if let responsiveness = payload.applicationResponsivenessMetrics,
           let ms = mean(responsiveness.histogrammedApplicationHangTime) {
            figures.append(("hang-ms", ms))
        }
        if let animation = payload.animationMetrics {
            figures.append(("hitch-ms-per-s", animation.scrollHitchTimeRatio.value))
        }
        if let memory = payload.memoryMetrics {
            figures.append(("peak-memory-mb", memory.peakMemoryUsage.converted(to: .megabytes).value))
        }
        if let exits = payload.applicationExitMetrics {
            let foreground = exits.foregroundExitData
            figures.append(("foreground-exits-abnormal", Double(foreground.cumulativeAbnormalExitCount
                + foreground.cumulativeMemoryResourceLimitExitCount + foreground.cumulativeAppWatchdogExitCount)))
        }
        return figures
    }

    /// A histogram's average, in milliseconds, from each bucket's middle.
    static func mean(_ histogram: MXHistogram<UnitDuration>) -> Double? {
        var total = 0.0, count = 0.0
        for case let bucket as MXHistogramBucket<UnitDuration> in histogram.bucketEnumerator {
            let middle = (bucket.bucketStart.converted(to: .milliseconds).value
                          + bucket.bucketEnd.converted(to: .milliseconds).value) / 2
            total += middle * Double(bucket.bucketCount)
            count += Double(bucket.bucketCount)
        }
        return count > 0 ? total / count : nil
    }
}
