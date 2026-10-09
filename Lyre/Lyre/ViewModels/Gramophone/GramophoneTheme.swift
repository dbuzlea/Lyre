//
//  GramophoneTheme.swift
//  Lyre
//

import SwiftUI

// MARK: - Gramophone Designs and Finishes
//
// The Gramophone comes in two designs, like the Spool:
//
//   horn      a tabletop machine with a flared horn rising over the turntable
//   cabinet   an upright console: the turntable under a lid, louvered doors in front
//             that swing open while a record plays, and a record compartment below
//
// and four finishes, each a wood with its hardware: brass or nickel for the tonearm,
// crank, levers and nameplate, and a felt for the turntable. Any finish goes on either
// design.
//
// The record crate and the Up Next tray are the Spool's (see TapeCarousel and
// SpoolQueueTray), so a finish also supplies a SpoolTheme for them, in its wood, felt
// and brass (`spoolTheme`).

enum GramophoneModel: String, CaseIterable, Identifiable {
    case horn
    case cabinet

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .horn:    return String(localized: "gramophone.design.horn")
        case .cabinet: return String(localized: "gramophone.design.cabinet")
        }
    }
}

enum GramophoneFinish: String, CaseIterable, Identifiable {
    case mahogany
    case oak
    case walnut
    case lacquer

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mahogany: return String(localized: "gramophone.finish.mahogany")
        case .oak:      return String(localized: "gramophone.finish.oak")
        case .walnut:   return String(localized: "gramophone.finish.walnut")
        case .lacquer:  return String(localized: "gramophone.finish.lacquer")
        }
    }

    var theme: GramophoneTheme {
        switch self {
        case .mahogany:
            // Deep red-brown with brass and a maroon felt.
            return GramophoneTheme(
                woodLight: Color(hex: 0x7A3420), wood: Color(hex: 0x5A2414), woodDark: Color(hex: 0x34130A),
                metalLight: Color(hex: 0xF3D88A), metal: Color(hex: 0xC9A04A), metalDark: Color(hex: 0x8A6A26),
                felt: Color(hex: 0x6E1A22))
        case .oak:
            // Golden oak with brass and a green felt.
            return GramophoneTheme(
                woodLight: Color(hex: 0xC08A4E), wood: Color(hex: 0x9C6A36), woodDark: Color(hex: 0x6A4520),
                metalLight: Color(hex: 0xF3D88A), metal: Color(hex: 0xC9A04A), metalDark: Color(hex: 0x8A6A26),
                felt: Color(hex: 0x1F4A2E))
        case .walnut:
            // Dark walnut with nickel and a bottle-green felt.
            return GramophoneTheme(
                woodLight: Color(hex: 0x6A4A32), wood: Color(hex: 0x4E3422), woodDark: Color(hex: 0x2E1E13),
                metalLight: Color(hex: 0xEEF0F2), metal: Color(hex: 0xB4B9BE), metalDark: Color(hex: 0x6E7479),
                felt: Color(hex: 0x173828))
        case .lacquer:
            // Black lacquer with brass and a red felt.
            return GramophoneTheme(
                woodLight: Color(hex: 0x2E2A2A), wood: Color(hex: 0x181616), woodDark: Color(hex: 0x080707),
                metalLight: Color(hex: 0xF3D88A), metal: Color(hex: 0xC9A04A), metalDark: Color(hex: 0x8A6A26),
                felt: Color(hex: 0x7A141A))
        }
    }
}

struct GramophoneTheme {
    let woodLight: Color
    let wood: Color
    let woodDark: Color
    /// The hardware: brass or nickel.
    let metalLight: Color
    let metal: Color
    let metalDark: Color
    /// The turntable's mat.
    let felt: Color

    /// Lettering on the wood, and the captions over it.
    var ink: Color { Color(hex: 0xF4EBD8) }
    /// Engraving on the brass nameplate.
    var plateInk: Color { Color(hex: 0x2E1E10) }
    /// Paper: record labels, sleeves and the instruction booklet.
    var paper: Color { Color(hex: 0xF1E6CF) }

    var woodGradient: LinearGradient {
        LinearGradient(colors: [woodLight, wood, woodDark], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var metalGradient: LinearGradient {
        LinearGradient(colors: [metalLight, metal, metalDark], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The same finish for the parts shared with the Spool: the crate, its shelf
    /// dividers and the Up Next tray.
    var spoolTheme: SpoolTheme {
        SpoolTheme(body: wood, bodyLight: woodLight,
                   rail: metalDark, railLight: metalLight,
                   key: metal, keyLight: paper, keySymbol: plateInk,
                   accent: metal, accentLight: metalLight,
                   ink: ink, logo: metal, isLight: false)
    }
}

extension EnvironmentValues {
    @Entry var gramophoneTheme: GramophoneTheme = GramophoneFinish.mahogany.theme
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
