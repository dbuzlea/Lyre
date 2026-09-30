//
//  ContentView.swift
//  Lyre
//
//  Created by Daniel Buzlea on 5/13/26.
//

import SwiftUI
import UIKit
import OSLog

private let logger = Logger(subsystem: "com.pinkhatcreations.lyreapp", category: "ContentView")

// MARK: - App Root View
//
// ContentView is the app's entry point after launch. It switches between
// OnboardingView (first run) and LyreView (returning users) based on the
// `hasCompletedOnboarding` AppStorage flag, with a smooth crossfade transition.
//
// It also owns the shared MusicService instance and surfaces MusicLoadError:
//   • .notAuthorized   → a full-screen AccessRecoveryView, matching onboarding's own
//                        chrome, since retrying cannot fix permissions and a system
//                        alert would leave a stale/empty menu visible behind it. Its
//                        visibility is owned by MusicService.isShowingAccessRecovery,
//                        not by this view, since access can be revoked and restored
//                        across an app relaunch (see MusicService.accessRecoveryPending).
//   • retryable errors → an alert with a "Retry" button that calls loadLibrary() again
//   • all other errors → an alert with a "Dismiss" cancel button to clear the state
struct ContentView: View {
    @StateObject private var musicService = MusicService()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Group {
                if hasCompletedOnboarding {
                    LyreView(musicService: musicService)
                        .ignoresSafeArea()
                } else {
                    OnboardingView(
                        hasCompletedOnboarding: $hasCompletedOnboarding,
                        musicService: musicService
                    )
                }
            }
            .animation(.easeInOut(duration: 0.4), value: hasCompletedOnboarding)

            // Deliberately NOT .ignoresSafeArea() here: OnboardingBackground's own
            // gradient already bleeds to the edges, but the symbol/title/message stack
            // inside OnboardingPage needs the top safe area respected so it clears the
            // Dynamic Island / notch instead of rendering underneath it.
            if musicService.isShowingAccessRecovery {
                AccessRecoveryView(musicService: musicService)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: musicService.isShowingAccessRecovery)
        .onAppear {
            logger.info("App started — onboarding completed: \(hasCompletedOnboarding)")
        }
        .onChange(of: hasCompletedOnboarding) { _, completed in
            if completed { logger.info("Onboarding completed") }
        }
        .onChange(of: scenePhase) { _, phase in
            // Picks up access granted in Settings while the app was backgrounded, and
            // any music added to the device since the last load.
            guard phase == .active else { return }
            Task { await musicService.refreshOnForeground() }
        }
        .onChange(of: musicService.lastError) { _, error in
            if let error { logger.error("Music service error presented: \(error.alertTitle)") }
        }
        .alert(
            musicService.lastError?.alertTitle ?? "Something Went Wrong",
            isPresented: .init(
                get: { musicService.lastError != nil && musicService.lastError != .notAuthorized },
                set: { if !$0 { musicService.lastError = nil } }
            )
        ) {
            if musicService.lastError?.isRetryable == true {
                Button("Retry") {
                    Task { await musicService.loadLibrary() }
                }
            }
            Button("Dismiss", role: .cancel) {
                musicService.lastError = nil
            }
        } message: {
            if let error = musicService.lastError {
                Text(error.localizedDescription)
            }
        }
    }
}

#Preview {
    ContentView()
}
