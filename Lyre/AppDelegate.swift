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
    // Dynamically controlled so Artwork Carousel can lock to landscape
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
        } else if args.contains("--uitest-complete-onboarding") {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        }
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
}
