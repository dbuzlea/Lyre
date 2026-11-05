//
//  AppDelegate.swift
//  Lyre
//
//  Created by Daniel Buzlea on 5/14/26.
//

import UIKit
import OSLog

private let logger = Logger(subsystem: "com.pinkhatcreations.lyreapp", category: "AppDelegate")

class AppDelegate: NSObject, UIApplicationDelegate {
    // Set by LyreView's OrientationLock: the classic player may turn sideways to open the
    // Artwork Carousel, the other players stay upright. Some displays ignore it, iPhone
    // Duo's inner display among them, so nothing may depend on it being honoured.
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        applyUITestLaunchArguments()
        // Which Lyre this is, first in the log, so a report can be matched to its
        // debug symbols; then the watch on the main thread (Diagnostics).
        Diagnostics.shared.record(.app, "Launched: \(Diagnostics.buildSummary())")
        DiagnosticsConsent.countLaunch()
        // The App Attest key, enrolled ahead of the first report; and anything waiting sent.
        ProblemReporter.shared.prepare()
        HangWatcher.shared.start()
        AppMetrics.shared.start()
        // How Lyre's used, if they've said it may count (UsageStats).
        UsageStats.shared.start()
        logger.info("App launched")
        return true
    }

    private func applyUITestLaunchArguments() {
        let args = CommandLine.arguments
        if args.contains("--uitest-reset-onboarding") {
            UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
            UserDefaults.standard.set(0, forKey: "onboardingStep")
        } else if args.contains("--uitest-complete-onboarding") {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        }
    }

    /// iOS relaunches the app in the background when podcast downloads finish while
    /// it isn't running. Touching `shared` recreates the session that receives them.
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        PodcastDownloads.shared.backgroundCompletionHandler = completionHandler
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
}
