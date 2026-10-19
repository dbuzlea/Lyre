//
//  DiscTheme.swift
//  Lyre
//

import SwiftUI

// MARK: - Disc Finishes
//
// The Disc is a portable CD player: a round lid over the disc, an LCD, and rubber keys.
// It comes in four finishes, after the players of the late nineties:
//
//   silver     brushed aluminium, a smoked lid and a yellow-green LCD
//   graphite   charcoal with a blue backlit LCD
//   ice        frosted clear plastic, the parts showing through, with an amber LCD
//   sport      safety yellow with grey rubber keys, built to be dropped
//
// Names and trade dress stay the Disc's own: no maker's names or logos are reproduced.
//
// The jewel-case rack and the Up Next tray are the Spool's (see TapeCarousel and
// SpoolQueueTray), so a finish also supplies a SpoolTheme for them (`spoolTheme`).

enum DiscFinish: String, CaseIterable, Identifiable {
    case silver
    case graphite
    case ice
    case sport

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .silver:   return String(localized: "disc.finish.silver")
        case .graphite: return String(localized: "disc.finish.graphite")
        case .ice:      return String(localized: "disc.finish.ice")
        case .sport:    return String(localized: "disc.finish.sport")
        }
    }

    var theme: DiscTheme {
        switch self {
        case .silver:
            return DiscTheme(
                bodyLight: Color(hex: 0xE6E8EB), body: Color(hex: 0xBFC3C8), bodyDark: Color(hex: 0x8D9298),
                lid: Color(hex: 0x3A3F46), button: Color(hex: 0xA7ACB2), buttonLight: Color(hex: 0xEDEFF1),
                buttonSymbol: Color(hex: 0x2B2F34), accent: Color(hex: 0x2F6FD0), accentLight: Color(hex: 0x5C93E6),
                ink: Color(hex: 0x34383E), lcd: Color(hex: 0xB9C68A), lcdInk: Color(hex: 0x1E2614),
                isLight: true)
        case .graphite:
            return DiscTheme(
                bodyLight: Color(hex: 0x4A4D53), body: Color(hex: 0x2A2C30), bodyDark: Color(hex: 0x141518),
                lid: Color(hex: 0x0E0F12), button: Color(hex: 0x3A3D42), buttonLight: Color(hex: 0x5A5E65),
                buttonSymbol: Color(hex: 0xE4E6E9), accent: Color(hex: 0xE0602A), accentLight: Color(hex: 0xF2834F),
                ink: Color(hex: 0xC9CCD1), lcd: Color(hex: 0x1B3E78), lcdInk: Color(hex: 0xA9D8FF),
                isLight: false)
        case .ice:
            return DiscTheme(
                bodyLight: Color(hex: 0xDDF1F7), body: Color(hex: 0x9FC9D8), bodyDark: Color(hex: 0x5E93A8),
                lid: Color(hex: 0x6FA9BE), button: Color(hex: 0xB9DCE8), buttonLight: Color(hex: 0xF2FBFE),
                buttonSymbol: Color(hex: 0x1C4252), accent: Color(hex: 0x7C4DC9), accentLight: Color(hex: 0xA27BE6),
                ink: Color(hex: 0x1C4252), lcd: Color(hex: 0xE9B04C), lcdInk: Color(hex: 0x3A2306),
                isLight: true, isClear: true)
        case .sport:
            return DiscTheme(
                bodyLight: Color(hex: 0xFFD836), body: Color(hex: 0xEDB800), bodyDark: Color(hex: 0xB78A00),
                lid: Color(hex: 0x2C2F33), button: Color(hex: 0x575B61), buttonLight: Color(hex: 0x7E838A),
                buttonSymbol: Color(hex: 0xF4F4F4), accent: Color(hex: 0x24272B), accentLight: Color(hex: 0x41454B),
                ink: Color(hex: 0x24272B), lcd: Color(hex: 0xA9C28A), lcdInk: Color(hex: 0x16200F),
                isLight: true)
        }
    }
}

struct DiscTheme {
    let bodyLight: Color
    let body: Color
    let bodyDark: Color
    /// The lid's tinted plastic, which the disc is seen through.
    let lid: Color
    /// The rubber keys.
    let button: Color
    let buttonLight: Color
    let buttonSymbol: Color
    /// The play key, and the lid's open catch.
    let accent: Color
    let accentLight: Color
    /// Printing on the casing, and the captions over it.
    let ink: Color
    /// The display's backlight, and its segments.
    let lcd: Color
    let lcdInk: Color
    /// A light casing, which needs dark controls drawn over it.
    let isLight: Bool
    /// Clear plastic: the casing is drawn translucent, showing what's inside.
    var isClear = false

    var bodyGradient: LinearGradient {
        LinearGradient(colors: [bodyLight, body, bodyDark], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The same finish for the parts shared with the Spool: the rack, its shelf
    /// dividers and the Up Next tray.
    var spoolTheme: SpoolTheme {
        SpoolTheme(body: body, bodyLight: bodyLight,
                   rail: bodyDark, railLight: bodyLight,
                   key: button, keyLight: buttonLight, keySymbol: buttonSymbol,
                   accent: accent, accentLight: accentLight,
                   ink: ink, logo: ink, isLight: isLight)
    }
}

extension EnvironmentValues {
    @Entry var discTheme: DiscTheme = DiscFinish.silver.theme
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
