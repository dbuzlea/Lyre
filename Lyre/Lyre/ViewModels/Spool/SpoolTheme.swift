//
//  SpoolTheme.swift
//  Lyre
//

import SwiftUI

// MARK: - Spool Designs
//
// The Spool comes in two bodies, after the two personal cassette players that defined
// the look, and a range of finishes that go on either:
//
// • Original (1979) — stood upright: a coloured body with a brushed-metal rail down the
//   right edge carrying the keys, an orange hotline button on top, and a solid door with
//   a small window, hinged down its left edge.
// • Slim (1983) — a metal slab with the keys along its top edge, a logo plate, and a
//   pill-shaped window over a tape lying flat. Its front panel tips open from the bottom.
//
// Names and trade dress stay the Spool's own: no maker's names or logos are reproduced.

enum SpoolModel: String, CaseIterable, Identifiable {
    case original
    case slim

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .original: return String(localized: "spool.design.original")
        case .slim:     return String(localized: "spool.design.slim")
        }
    }

    /// The axis the tape stands on in the deck.
    var tapeAxis: Axis { self == .original ? .vertical : .horizontal }
}

enum SpoolFinish: String, CaseIterable, Identifiable {
    case blue
    case silver
    case red
    case black
    case gold
    case sport

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blue:   return String(localized: "spool.finish.blue")
        case .silver: return String(localized: "spool.finish.silver")
        case .red:    return String(localized: "spool.finish.red")
        case .black:  return String(localized: "spool.finish.black")
        case .gold:   return String(localized: "spool.finish.gold")
        case .sport:  return String(localized: "spool.finish.sport")
        }
    }

    var theme: SpoolTheme {
        switch self {
        case .blue:
            // Denim blue body on a satin-silver rail, orange hotline.
            return SpoolTheme(
                body: Color(hex: 0x1A5E96), bodyLight: Color(hex: 0x2676B2),
                rail: Color(hex: 0xA9B0B6), railLight: Color(hex: 0xE3E6E8),
                key: Color(hex: 0xB4BBC0), keyLight: Color(hex: 0xE5E9EC), keySymbol: Color(hex: 0x262E36),
                accent: Color(hex: 0xEF8619), accentLight: Color(hex: 0xFBA842),
                ink: .white, logo: .white, isLight: false)
        case .silver:
            // Brushed aluminium with the red script of the slim players.
            return SpoolTheme(
                body: Color(hex: 0xB9BDC2), bodyLight: Color(hex: 0xE4E6E9),
                rail: Color(hex: 0x9A9EA4), railLight: Color(hex: 0xD3D6DA),
                key: Color(hex: 0xA9AEB4), keyLight: Color(hex: 0xEEF0F2), keySymbol: Color(hex: 0x2E3236),
                accent: Color(hex: 0xC8322B), accentLight: Color(hex: 0xE05A4E),
                ink: Color(hex: 0x3A3D42), logo: Color(hex: 0xB0302A), isLight: true)
        case .red:
            return SpoolTheme(
                body: Color(hex: 0x9E1F26), bodyLight: Color(hex: 0xC8333B),
                rail: Color(hex: 0xA9B0B6), railLight: Color(hex: 0xE3E6E8),
                key: Color(hex: 0xB4BBC0), keyLight: Color(hex: 0xE5E9EC), keySymbol: Color(hex: 0x2A1C1D),
                accent: Color(hex: 0x2A2A2E), accentLight: Color(hex: 0x4A4A50),
                ink: .white, logo: .white, isLight: false)
        case .black:
            // Gunmetal and black with a red play key.
            return SpoolTheme(
                body: Color(hex: 0x1B1C1F), bodyLight: Color(hex: 0x37393E),
                rail: Color(hex: 0x55585E), railLight: Color(hex: 0x8C9096),
                key: Color(hex: 0x2E3034), keyLight: Color(hex: 0x50535A), keySymbol: Color(hex: 0xE8E9EB),
                accent: Color(hex: 0xD8402C), accentLight: Color(hex: 0xEF6A52),
                ink: Color(hex: 0xC9CBCF), logo: Color(hex: 0xD8402C), isLight: false)
        case .gold:
            return SpoolTheme(
                body: Color(hex: 0xA8874A), bodyLight: Color(hex: 0xD9BC7E),
                rail: Color(hex: 0x6F5A33), railLight: Color(hex: 0xA28A58),
                key: Color(hex: 0xC9B48A), keyLight: Color(hex: 0xF0E3C4), keySymbol: Color(hex: 0x3A2E18),
                accent: Color(hex: 0x2B2620), accentLight: Color(hex: 0x4A4237),
                ink: Color(hex: 0x3A2E18), logo: Color(hex: 0x3A2E18), isLight: true)
        case .sport:
            // Safety yellow with grey rubber keys.
            return SpoolTheme(
                body: Color(hex: 0xEDB800), bodyLight: Color(hex: 0xFFD836),
                rail: Color(hex: 0x4F5359), railLight: Color(hex: 0x767B82),
                key: Color(hex: 0x575B61), keyLight: Color(hex: 0x7E838A), keySymbol: Color(hex: 0xF4F4F4),
                accent: Color(hex: 0x24272B), accentLight: Color(hex: 0x41454B),
                ink: Color(hex: 0x24272B), logo: Color(hex: 0x24272B), isLight: true)
        }
    }
}

/// The colours a finish gives the player's body. The cassette's own colours stay in
/// `SpoolPalette`; tapes look the same in every player.
struct SpoolTheme {
    /// The casing.
    let body: Color
    let bodyLight: Color
    /// Brushed metal: the original's key rail, the slim's logo plate and top edge.
    let rail: Color
    let railLight: Color
    let key: Color
    let keyLight: Color
    let keySymbol: Color
    /// The play key and the original's hotline button.
    let accent: Color
    let accentLight: Color
    /// Printing on the casing, and the captions over it.
    let ink: Color
    let logo: Color
    /// A light casing, which needs dark controls drawn over it.
    let isLight: Bool

    var bodyGradient: LinearGradient {
        LinearGradient(colors: [bodyLight, body], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var railGradient: LinearGradient {
        LinearGradient(colors: [railLight, rail], startPoint: .leading, endPoint: .trailing)
    }

    /// Glass and recess tints that read on this casing.
    var windowTint: Color { isLight ? Color.black.opacity(0.55) : Color.black.opacity(0.4) }
    var bay: Color { Color(hex: 0x0E1A26) }
}

extension EnvironmentValues {
    @Entry var spoolTheme: SpoolTheme = SpoolFinish.blue.theme
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
