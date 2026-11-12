//
//  LyreContrast.swift
//  Lyre
//

import SwiftUI

// MARK: - Contrast and Transparency, as the Reader Has Set Them
//
// Lyre's quieter things (secondary text faded back, buttons on a breath of white, panels
// of frosted glass) are part of its look. A person who's turned on Increase Contrast or
// Reduce Transparency (Settings > Accessibility > Display & Text Size) has said that look
// costs them: they need words that stand clear of what's behind them, controls with an
// edge, and backgrounds they can't see through. These follow those settings.
//
//   lyreFaded(0.6)              text faded back; at least 90% with Increase Contrast
//   lyreInk(.white, 0.6)        a faded colour for text or symbols, the same
//   lyreFill(.white, 0.1, in:)  a faint fill behind a control: with Increase Contrast a
//                               stronger fill and an outline; with Reduce Transparency
//                               solid, no longer seen through
//   lyreMaterial(_:in:solid:)   frosted glass; solid with Reduce Transparency

enum LyreContrast {
    /// How far faded text comes forward with Increase Contrast.
    static let fadedFloor = 0.9

    /// Debug builds: `--lyre-increase-contrast` and `--lyre-reduce-transparency` stand in
    /// for the settings (SwiftUI's values can't be set), for UI tests and screenshots.
    #if DEBUG
    static let forcesIncreased = ProcessInfo.processInfo.arguments.contains("--lyre-increase-contrast")
    static let forcesSolid = ProcessInfo.processInfo.arguments.contains("--lyre-reduce-transparency")
    #else
    static let forcesIncreased = false
    static let forcesSolid = false
    #endif

    static func isIncreased(_ contrast: ColorSchemeContrast) -> Bool { contrast == .increased || forcesIncreased }
    static func isSolid(_ reduceTransparency: Bool) -> Bool { reduceTransparency || forcesSolid }

    static func faded(_ opacity: Double, increased: Bool) -> Double {
        increased ? max(opacity, fadedFloor) : opacity
    }

    /// A faint fill's strength: firmer with Increase Contrast, and with Reduce
    /// Transparency, as it would look over the dark Lyre draws behind it, made solid.
    static func fill(_ opacity: Double, increased: Bool) -> Double {
        increased ? max(opacity * 2.5, 0.3) : opacity
    }
}

extension View {
    /// Text faded back to `opacity`; clearer with Increase Contrast.
    func lyreFaded(_ opacity: Double) -> some View {
        modifier(LyreFaded(opacity: opacity))
    }

    /// `color` faded to `opacity`, for text or symbols; clearer with Increase Contrast.
    func lyreInk(_ color: Color, _ opacity: Double) -> some View {
        modifier(LyreInk(color: color, opacity: opacity))
    }

    /// A faint `color` fill in `shape` behind a control.
    func lyreFill<S: Shape>(_ color: Color, _ opacity: Double, in shape: S) -> some View {
        modifier(LyreFill(color: color, opacity: opacity, shape: shape))
    }

    /// Frosted glass in `shape`; `solid` instead with Reduce Transparency.
    func lyreMaterial<S: Shape>(_ material: Material, in shape: S, solid: Color) -> some View {
        modifier(LyreMaterial(material: material, shape: shape, solid: solid))
    }
}

private struct LyreFaded: ViewModifier {
    let opacity: Double
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.opacity(LyreContrast.faded(opacity, increased: LyreContrast.isIncreased(contrast)))
    }
}

private struct LyreInk: ViewModifier {
    let color: Color
    let opacity: Double
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.foregroundStyle(color.opacity(LyreContrast.faded(opacity, increased: LyreContrast.isIncreased(contrast))))
    }
}

private struct LyreFill<S: Shape>: ViewModifier {
    let color: Color
    let opacity: Double
    let shape: S
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    static func ground(under color: Color) -> Color {
        if color == .white { return .black }
        if color == .black { return .white }
        return Color(uiColor: .systemBackground)
    }

    func body(content: Content) -> some View {
        let increased = LyreContrast.isIncreased(contrast)
        let strength = LyreContrast.fill(opacity, increased: increased)
        content
            .background {
                if LyreContrast.isSolid(reduceTransparency), opacity >= 0.25 {
                    // A scrim behind a symbol over a picture: solid, dark or light.
                    shape.fill(color == .black ? Color(white: 0.12) : color == .white ? Color(white: 0.88) : color)
                } else if LyreContrast.isSolid(reduceTransparency) {
                    // Solid: the fill as it looks over the ground it's meant for (a light
                    // fill over Lyre's dark, a dark one over a light page), not seen through.
                    shape.fill(Self.ground(under: color)).overlay(shape.fill(color.opacity(strength)))
                } else {
                    shape.fill(color.opacity(strength))
                }
            }
            .overlay {
                if increased { shape.stroke(color.opacity(0.7), lineWidth: 1) }
            }
    }
}

private struct LyreMaterial<S: Shape>: ViewModifier {
    let material: Material
    let shape: S
    let solid: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if LyreContrast.isSolid(reduceTransparency) {
            content.background(solid, in: shape)
        } else {
            content.background(material, in: shape)
        }
    }
}
