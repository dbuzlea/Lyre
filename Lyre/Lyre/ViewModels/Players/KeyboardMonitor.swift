//
//  KeyboardMonitor.swift
//  Lyre
//

import SwiftUI
import UIKit

// MARK: - Keyboard Monitor
//
// Whether the on-screen keyboard is up, and how much of the window it covers.
//
// LyreView ignores the safe area so each player's body bleeds to the edges, and that
// includes the keyboard's: nothing moves out of its way on its own. The players read
// this instead, to make room for it themselves. The classic player lowers its click
// wheel out of view while typing and brings it back when the keyboard goes; the Spool's
// rack stops above it.
//
// Taken from the keyboard's own notifications rather than from a text field's focus, so
// a hardware keyboard, which leaves the screen uncovered, doesn't hide the wheel; the
// bar it leaves along the bottom edge doesn't either (see `isVisible`).

@Observable
final class KeyboardMonitor {
    /// Height of the keyboard over the bottom of the window; zero while it's down.
    private(set) var height: CGFloat = 0

    /// Whether a full keyboard is up. With a hardware keyboard attached, the on-screen one
    /// shrinks to its shortcuts bar along the bottom edge instead of going away; that bar
    /// is reported as a keyboard too, but it leaves the wheel's room, so it doesn't count.
    var isVisible: Bool { height > Self.shortcutsBarLimit }

    /// Taller than any shortcuts or accessory bar, shorter than any keyboard.
    private static let shortcutsBarLimit: CGFloat = 120

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated { self?.update(from: note) }
            },
            center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated { self?.update(from: note, hiding: true) }
            },
        ]
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    private func update(from note: Notification, hiding: Bool = false) {
        let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
        let screen = Self.screenBounds(for: note)
        // A floating or undocked keyboard, or one moved off the bottom, covers nothing
        // the players need to make room for.
        let covered = hiding ? 0 : max(0, screen.maxY - frame.minY)
        let newHeight = frame.maxY >= screen.maxY - 1 ? covered : 0
        guard newHeight != height else { return }

        let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        withAnimation(.easeInOut(duration: max(0.2, duration))) { height = newHeight }
    }

    private static func screenBounds(for note: Notification) -> CGRect {
        // The keyboard's own screen, which the notification names (on every iOS this
        // app runs on): not one picked from the app's scenes, which on an iPhone Duo
        // could be the other display.
        (note.object as? UIScreen)?.bounds ?? .zero
    }
}
