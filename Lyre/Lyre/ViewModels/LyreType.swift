//
//  LyreType.swift
//  Lyre
//

import SwiftUI
import UIKit

// MARK: - Lyre's Type, at the Reader's Size
//
// Each player sets its own type, size by size, for its look: a J-card's serif, a sleeve's,
// Liquid's rounded titles. Those sizes are what the design means at the standard text
// size. A person who reads with larger (or smaller) text has set it once, in Settings, and
// expects every app to follow (Dynamic Type): Lyre's type grows with it the way the
// system's does, along the curve of the nearest text style (a caption grows faster than
// a large title), up to a cap where a layout would no longer hold (`maxScale`).
//
// Not for words that are part of a thing drawn on screen (a cassette's label, a record's,
// a Discman's display, the click wheel's): those are pictures of objects, and stay as
// drawn. Apple's guidance leaves those out too.

extension View {
    /// The system font at `size` points at the standard text size, scaled with the
    /// person's text size, no further than `maxScale` times.
    func lyreFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default,
                  maxScale: CGFloat = 2) -> some View {
        modifier(LyreScaledFont(size: size, weight: weight, design: design, maxScale: maxScale))
    }
}

private struct LyreScaledFont: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    let maxScale: CGFloat
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content.font(.system(size: LyreType.scaled(size, at: typeSize, maxScale: maxScale),
                             weight: weight, design: design))
    }
}

enum LyreType {
    /// `size` (at the standard text size) at text size `typeSize`: as the text style
    /// nearest that size grows, no more than `maxScale` times, and never below the
    /// smallest the system would draw it (`smallest` shrinks only so far).
    static func scaled(_ size: CGFloat, at typeSize: DynamicTypeSize, maxScale: CGFloat = 2) -> CGFloat {
        let metrics = UIFontMetrics(forTextStyle: style(for: size))
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize))
        let scaled = metrics.scaledValue(for: size, compatibleWith: traits)
        return min(scaled, size * maxScale)
    }

    /// The system's text style nearest a size, whose curve a size follows.
    static func style(for size: CGFloat) -> UIFont.TextStyle {
        switch size {
        case ..<11.5: .caption2
        case ..<12.5: .caption1
        case ..<13.5: .footnote
        case ..<15.5: .subheadline
        case ..<17.5: .body
        case ..<20.5: .title3
        case ..<24.5: .title2
        case ..<30.5: .title1
        default: .largeTitle
        }
    }
}
