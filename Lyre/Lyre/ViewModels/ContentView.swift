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
// It also owns the shared MusicService instance and surfaces MusicLoadError alerts
// with contextually appropriate actions:
//   • .notAuthorized  → "Open Settings" deep-link (retrying cannot fix permissions)
//   • retryable errors → "Retry" button that calls loadLibrary() again
//   • all errors       → "Dismiss" cancel button to clear the error state
struct ContentView: View {
    @StateObject private var musicService = MusicService()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
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
        .onAppear {
            logger.info("App started — onboarding completed: \(hasCompletedOnboarding)")
        }
        .onChange(of: hasCompletedOnboarding) { _, completed in
            if completed { logger.info("Onboarding completed") }
        }
        .onChange(of: musicService.lastError) { _, error in
            if let error { logger.error("Music service error presented: \(error.alertTitle)") }
        }
        .alert(
            musicService.lastError?.alertTitle ?? "Something Went Wrong",
            isPresented: .init(
                get: { musicService.lastError != nil },
                set: { if !$0 { musicService.lastError = nil } }
            )
        ) {
            // Auth errors cannot be fixed by retrying — send the user to Settings instead.
            if musicService.lastError == .notAuthorized {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } else if musicService.lastError?.isRetryable == true {
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
