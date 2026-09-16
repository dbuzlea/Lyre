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

            if let json = String(data: payload.jsonRepresentation(), encoding: .utf8) {
                logger.debug("Diagnostic payload JSON: \(json)")
            }
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

            if let json = String(data: payload.jsonRepresentation(), encoding: .utf8) {
                logger.debug("Metric payload JSON: \(json)")
            }
        }
    }
}
