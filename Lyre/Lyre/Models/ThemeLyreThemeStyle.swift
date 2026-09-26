//
//  ThemeLyreThemeStyle.swift
//  Lyre
//
//  Created by Daniel Buzlea on 5/14/26.
//

import Foundation

/// The visual finish applied to the player body, screen, and wheel.
///
/// Raw values are the user-facing names shown in Settings → Theme and are
/// persisted to `UserDefaults`. Renaming a raw value requires a migration
/// entry in `ThemeSettings.migratedStyle(from:)`.
enum LyreThemeStyle: String, CaseIterable, Identifiable {
    // Signature finishes
    case porcelain = "Porcelain"
    case onyx = "Onyx"
    case sterling = "Sterling"
    case crimson = "Crimson"

    // Special screens
    case monochrome = "Monochrome"
    case phosphor = "Phosphor"
    case spectrum = "Spectrum"

    // Pebble — compact body, standard screen
    case pebbleSilver = "Pebble Silver"
    case pebbleGold = "Pebble Gold"
    case pebbleBlue = "Pebble Blue"
    case pebblePink = "Pebble Pink"
    case pebbleGreen = "Pebble Green"

    // Slim — tall screen
    case slim = "Slim"
    case slimSilver = "Slim Silver"
    case slimBlack = "Slim Black"
    case slimGraphite = "Slim Graphite"
    case slimBlue = "Slim Blue"
    case slimPink = "Slim Pink"
    case slimPurple = "Slim Purple"
    case slimGreen = "Slim Green"
    case slimYellow = "Slim Yellow"
    case slimOrange = "Slim Orange"
    case slimRed = "Slim Red"

    // Clip — small square screen
    case clipSilver = "Clip Silver"
    case clipBlue = "Clip Blue"
    case clipPink = "Clip Pink"
    case clipGreen = "Clip Green"
    case clipOrange = "Clip Orange"
    case clipPurple = "Clip Purple"
    case clipGold = "Clip Gold"

    var id: String { rawValue }

    /// Default screen size for this finish
    var defaultScreenSize: ScreenSize {
        switch self {
        case .porcelain, .onyx, .sterling, .crimson:
            return .standard
        case .slim,
             .slimSilver,
             .slimBlack,
             .slimGraphite,
             .slimBlue,
             .slimPink,
             .slimPurple,
             .slimGreen,
             .slimYellow,
             .slimOrange,
             .slimRed:
            return .nanoTall
        case .clipSilver,
             .clipBlue,
             .clipPink,
             .clipGreen,
             .clipOrange,
             .clipPurple,
             .clipGold,
             .monochrome,
             .pebbleSilver,
             .pebbleGold,
             .pebbleBlue,
             .pebblePink,
             .pebbleGreen,
             .phosphor:
            return .standard
        case .spectrum:
            return .large
        }
    }
}
