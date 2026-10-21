//
//  AppHelpers.swift
//  Lyre
//

import Foundation
import UIKit

// MARK: - AppHelpers
//
// Stateless utility functions shared across multiple views. Centralising them here
// avoids duplicating time-formatting, alphabet-bucketing, and battery-icon logic
// in every file that needs it.
enum AppHelpers {

    // MARK: - Time Formatting

    static func formatTime(_ time: TimeInterval) -> String {
        String(format: "%d:%02d", Int(time) / 60, Int(time) % 60)
    }

    // MARK: - Alphabet Helpers

    /// Returns the uppercased first letter a name files under, or "#" if it's not a
    /// letter. Leading articles are skipped (see `sortKey`), so the letter always
    /// matches the name's position in a sorted list.
    static func firstLetter(of name: String) -> String {
        let first = String(sortKey(for: name).prefix(1)).uppercased()
        return first.first?.isLetter == true ? first : "#"
    }

    private static let leadingArticles = ["the ", "a ", "an "]

    /// The name as the Music library sorts it: a leading "The", "A" or "An" is
    /// ignored, so "The Weeknd" files under W. MusicKit returns lists in this order,
    /// and local lists are sorted by this key so both sources agree.
    ///
    /// Called for every name in a sort or an index, so it looks at the first few
    /// characters only, lowercased once, rather than lowercasing and counting the whole
    /// name for each article.
    static func sortKey(for name: String) -> Substring {
        let head = name.prefix(4).lowercased()
        for article in leadingArticles where head.hasPrefix(article) {
            let rest = name.dropFirst(article.count)
            if !rest.isEmpty { return rest.drop(while: \.isWhitespace) }
        }
        return Substring(name)
    }

    /// Orders two names the way the Music library does. See `sortKey`.
    static func sortsBefore(_ lhs: String, _ rhs: String) -> Bool {
        sortKey(for: lhs).localizedCaseInsensitiveCompare(sortKey(for: rhs)) == .orderedAscending
    }

    // MARK: - Battery Helpers

    static func batteryIconName(level: Float, state: UIDevice.BatteryState) -> String {
        if state == .charging || state == .full {
            return "battery.100.bolt"
        }
        let percentage = Int(level * 100)
        switch percentage {
        case 90...100: return "battery.100"
        case 75..<90:  return "battery.75"
        case 50..<75:  return "battery.50"
        case 25..<50:  return "battery.25"
        default:       return "battery.0"
        }
    }

    /// Returns true when battery is critically low and not charging/full. A battery
    /// that can't be read (level -1, state unknown: a Mac with no battery, or the
    /// simulator) is never low.
    static func batteryIsLow(level: Float, state: UIDevice.BatteryState) -> Bool {
        level >= 0 && level < 0.2 && state == .unplugged
    }
}

// MARK: - OneShotTimer

/// A restartable one-shot timer that lives outside SwiftUI's tracked state.
///
/// Keeping a `Timer` in `@State` and replacing it on every restart counts as a state
/// change, so the view redraws each time. The wheel restarts the backlight timer on
/// every touch event, which redrew the entire interface 60–120 times a second while
/// scrolling. Hold one of these in `@State` instead: the reference never changes, so
/// restarting it is invisible to SwiftUI.
final class OneShotTimer {
    private var timer: Timer?

    /// Cancels any pending fire and schedules `action` after `interval` seconds.
    func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            // Scheduled on the main run loop, so this is already the main thread.
            MainActor.assumeIsolated { action() }
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}
