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

    /// Returns the uppercased first letter of a name, or "#" if it's not a letter.
    static func firstLetter(of name: String) -> String {
        let first = String(name.prefix(1)).uppercased()
        return first.first?.isLetter == true ? first : "#"
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

    /// Returns true when battery is critically low and not charging/full.
    static func batteryIsLow(level: Float, state: UIDevice.BatteryState) -> Bool {
        level < 0.2 && state != .charging && state != .full
    }
}
