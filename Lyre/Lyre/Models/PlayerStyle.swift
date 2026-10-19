//
//  PlayerStyle.swift
//  Lyre
//

import Foundation

/// Which player the app is dressed as.
///
/// Unlike `LyreThemeStyle`, which only refinishes the click-wheel player, this swaps the
/// whole control surface: `.spool` replaces the screen and wheel with a cassette deck and
/// transport keys (see `SpoolPlayerView`), and `.gramophone` with a turntable, tonearm and
/// crank (see `GramophonePlayerView`), and `.disc` with a portable CD player (see
/// `DiscPlayerView`). `.liquid` is the modern one: the cover full screen, songs changed
/// by a liquid wave (see `LiquidPlayerView`).
///
/// Raw values are persisted to `UserDefaults`; the user-facing names come from
/// `displayName`, so renaming one in the UI needs no migration.
enum PlayerStyle: String, CaseIterable, Identifiable {
    case classic
    case spool
    case gramophone
    case disc
    case liquid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return String(localized: "settings.playerStyle.classic")
        case .spool:   return String(localized: "settings.playerStyle.spool")
        case .gramophone: return String(localized: "settings.playerStyle.gramophone")
        case .disc:   return String(localized: "settings.playerStyle.disc")
        case .liquid: return String(localized: "settings.playerStyle.liquid")
        }
    }
}
