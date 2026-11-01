//
//  AllowMusicAccessButton.swift
//  Lyre
//

import SwiftUI
import MusicKit
import UIKit

// MARK: - Allow Access to the Apple Music Library
//
// Lyre set up without access to the music library (LYRE-28): every player's settings
// offer it again, until it's given. Once refused, only the Settings app can give it, so
// the button opens Lyre's page there (Media & Apple Music). One never asked (set up
// skipped before the question) has no switch there yet: Apple's own question is asked
// instead. Coming back to Lyre reloads the library (ContentView's foreground refresh).

enum MusicAccess {
    /// Whether Lyre still needs access to the music library. `-ForceNeedsMusicAccess YES`
    /// (debug builds) says so regardless, for UI tests, which have access.
    static var isNeeded: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "ForceNeedsMusicAccess") { return true }
        #endif
        return MusicAuthorization.currentStatus != .authorized
    }

    /// Asks once if never asked; otherwise opens Lyre's page in the Settings app.
    @MainActor
    static func allow(musicService: MusicService) async {
        if MusicAuthorization.currentStatus == .notDetermined {
            _ = await MusicAuthorization.request()
            await musicService.refreshOnForeground()
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            await UIApplication.shared.open(url)
        }
    }
}

/// The settings' Allow Access button, drawn by each player in its own style (`label`),
/// shown only while access is needed.
struct AllowMusicAccessButton<Label: View>: View {
    @ObservedObject var musicService: MusicService
    @ViewBuilder let label: () -> Label

    var body: some View {
        // `isAuthorized` is read so the button goes once access is given and the
        // library reloads.
        if !musicService.isAuthorized || MusicAccess.isNeeded {
            Button { Task { await MusicAccess.allow(musicService: musicService) } } label: { label() }
                .accessibilityLabel(String(localized: "settings.allowMusicAccess"))
                .accessibilityHint(String(localized: "settings.allowMusicAccess.detail"))
                .accessibilityIdentifier("settings.allowMusicAccess")
        }
    }
}
