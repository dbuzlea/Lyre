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
    /// The whole window and its safe region, measured here, outside LyreView's
    /// `.ignoresSafeArea()`, which hides the insets from everything inside it. See
    /// `EnvironmentValues.windowSafeArea`.
    @State private var fullFrame: CGRect = .zero
    @State private var safeFrame: CGRect = .zero

    /// GeometryProxy.safeAreaInsets reads zero once the safe area is ignored anywhere
    /// above, so the insets come from comparing the two frames instead.
    private var windowSafeArea: EdgeInsets {
        guard fullFrame != .zero, safeFrame != .zero else { return EdgeInsets() }
        return EdgeInsets(top: max(0, safeFrame.minY - fullFrame.minY),
                          leading: max(0, safeFrame.minX - fullFrame.minX),
                          bottom: max(0, fullFrame.maxY - safeFrame.maxY),
                          trailing: max(0, fullFrame.maxX - safeFrame.maxX))
    }

    var body: some View {
        ZStack {
            Group {
                if hasCompletedOnboarding {
                    LyreView(musicService: musicService)
                        .ignoresSafeArea()
                        .environment(\.windowSafeArea, windowSafeArea)
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
        .background {
            ZStack {
                frameReader { fullFrame = $0 }
                    .ignoresSafeArea()
                // The keyboard is left out: these insets are the status bar's and the
                // home indicator's. With it in, bringing the keyboard up re-laid out
                // the Gramophone's stage against an inset that moved on every frame of
                // the keyboard's animation, which never settled and hung the app. A
                // player that needs room for the keyboard asks KeyboardMonitor.
                frameReader { safeFrame = $0 }
                    .ignoresSafeArea(.keyboard)
            }
        }
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
                get: { musicService.lastError != nil && musicService.lastError != .notAuthorized && !Self.hidesLibraryErrors },
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

private extension ContentView {
    /// `--uitest-hide-library-errors` keeps the library's load errors off screen, for UI
    /// tests about something else: the simulator has no library, so its error alert
    /// turns up at unpredictable moments and takes any open sheet down with it.
    static var hidesLibraryErrors: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--uitest-hide-library-errors")
        #else
        false
        #endif
    }

    func frameReader(_ update: @escaping (CGRect) -> Void) -> some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            Color.clear
                .onAppear { update(frame) }
                .onChange(of: frame) { _, frame in update(frame) }
        }
    }
}

extension EnvironmentValues {
    /// The window's safe area, for views that draw edge to edge under
    /// `.ignoresSafeArea()` but still need to keep content clear of the status bar
    /// and home indicator. Inside such a view SwiftUI reports zero insets.
    @Entry var windowSafeArea = EdgeInsets()
}

#Preview {
    ContentView()
}
