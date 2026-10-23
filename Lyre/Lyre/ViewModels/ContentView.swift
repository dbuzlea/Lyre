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
//   Both alerts are presented over whatever is on screen, so an open sheet stays open
//   (see `presentLibraryError`).
struct ContentView: View {
    @StateObject private var musicService = MusicService()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase
    /// The whole window and its safe region, measured here, outside LyreView's
    /// `.ignoresSafeArea()`, which hides the insets from everything inside it. See
    /// `EnvironmentValues.windowSafeArea`.
    @State private var fullFrame: CGRect = .zero
    @State private var safeFrame: CGRect = .zero
    /// A view in this window, for presenting the library error alert there rather than
    /// in whichever scene happens to be key.
    @State private var windowAnchor = WindowAnchor()

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
                WindowAnchorView(anchor: windowAnchor)
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
            presentLibraryError(error)
        }
    }

    /// The library's load error, as an alert over whatever is on screen.
    ///
    /// Presented through UIKit from the top-most view controller rather than with
    /// SwiftUI's `.alert` here at the root (LYRE-2): every player puts up its own sheets
    /// (podcast search, settings, the carousel), and a root alert arriving while one was
    /// open took the sheet down with it, and anything typed in it.
    private func presentLibraryError(_ error: MusicLoadError?) {
        guard let error, error != .notAuthorized, !Self.hidesLibraryErrors else {
            LibraryErrorAlert.dismiss()
            return
        }
        LibraryErrorAlert.present(error, in: windowAnchor.window, retry: {
            Task { await musicService.loadLibrary() }
        }, dismiss: {
            musicService.lastError = nil
        })
    }
}

private extension ContentView {
    /// `--uitest-hide-library-errors` keeps the library's load errors off screen, for UI
    /// tests about something else: the simulator has no library, so its error alert
    /// turns up at unpredictable moments, over whatever the test is driving.
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

// MARK: - Library Error Alert

/// The library error alert, presented by UIKit on top of whatever is showing, so a
/// sheet underneath stays open. One at a time: a second error while it's up replaces
/// nothing.
private enum LibraryErrorAlert {
    private static weak var shown: UIAlertController?

    static func present(_ error: MusicLoadError, in window: UIWindow?,
                        retry: @escaping () -> Void, dismiss: @escaping () -> Void) {
        guard shown == nil, let top = topViewController(in: window) else { return }
        let alert = UIAlertController(title: error.alertTitle, message: error.localizedDescription,
                                      preferredStyle: .alert)
        if error.isRetryable {
            alert.addAction(UIAlertAction(title: "Retry", style: .default) { _ in
                dismiss()
                retry()
            })
        }
        alert.addAction(UIAlertAction(title: "Dismiss", style: .cancel) { _ in dismiss() })
        shown = alert
        top.present(alert, animated: true)
    }

    static func dismiss() {
        shown?.dismiss(animated: true)
        shown = nil
    }

    /// What's on top in `window`: its root, then whatever it's presenting, all the way up.
    private static func topViewController(in window: UIWindow?) -> UIViewController? {
        var top = window?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed {
            top = next
        }
        return top
    }
}

// MARK: - Window Anchor

/// Holds on to a view in ContentView's window, so UIKit work (the library error alert)
/// goes to that window. Walking every connected scene for the key one picks the wrong
/// window once there's more than one, as on an iPhone Duo or iPad.
final class WindowAnchor {
    fileprivate weak var view: UIView?
    var window: UIWindow? { view?.window }
}

private struct WindowAnchorView: UIViewRepresentable {
    let anchor: WindowAnchor

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        anchor.view = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}
}
