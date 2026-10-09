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
        AppMetrics.shared.start()
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
