//
//  LyreApp.swift
//  Lyre
//
//  Created by Daniel Buzlea on 5/13/26.
//

import SwiftUI

/// Facts about how this process was started.
enum AppEnvironment {
    /// True when a UI test launched the app.
    ///
    /// Used to stand down animations that never stop on their own. XCUITest blocks
    /// every query until the app is quiescent, so a disc that turns for as long as
    /// music plays means it never is, and each query waits out the full idle timeout
    /// instead — minutes of it across a suite.
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("--uitest")

    /// A UI test asked for the sample shelves (`-SpoolSampleTapes YES`). The real
    /// library is then left unloaded, even on a phone that has one, so a test sees the
    /// same twelve tapes on a device as on a simulator with no music.
    static var usesOnlySampleLibrary: Bool {
        #if DEBUG
        isUITesting && UserDefaults.standard.bool(forKey: "SpoolSampleTapes")
        #else
        false
        #endif
    }
}

@main
struct LyreApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        Self.applyUITestLaunchArguments()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }

    /// Puts onboarding into a known state when a UI test asks for one.
    ///
    /// The UI tests have always passed these arguments but nothing read them, so every
    /// test started in whatever state the device happened to be in — a suite that
    /// passes on a device that has been used and fails on a fresh one. Reading them
    /// here makes the starting point explicit.
    ///
    /// Either one also forgets a player chosen in an earlier run, so a test that picks the
    /// Spool in onboarding can't leave the next test on it. A test that wants the Spool
    /// says so in its arguments (`-LyrePlayerStyle spool`), which still apply.
    private static func applyUITestLaunchArguments() {
        let arguments = ProcessInfo.processInfo.arguments
        let defaults = UserDefaults.standard
        if arguments.contains("--uitest-complete-onboarding") {
            defaults.set(true, forKey: "hasCompletedOnboarding")
            defaults.removeObject(forKey: "LyrePlayerStyle")
            // Held as a book, from the albums, not a section an earlier run left open.
            defaults.removeObject(forKey: "LiquidBookSection")
            defaults.removeObject(forKey: "LiquidBookRecent")
        } else if arguments.contains("--uitest-reset-onboarding") {
            defaults.set(false, forKey: "hasCompletedOnboarding")
            defaults.removeObject(forKey: "LyrePlayerStyle")
            // From the first step, not wherever an earlier run stopped.
            defaults.removeObject(forKey: "onboardingStep")
        }
        #if DEBUG
        // Podcasts subscribed to in an earlier run would otherwise carry into this one.
        if arguments.contains("--uitest-reset-subscriptions") {
            try? FileManager.default.removeItem(at: URL.applicationSupportDirectory.appending(path: "PodcastSubscriptions.json"))
        }
        UITestNetwork.install(from: defaults)
        #endif
    }
}
