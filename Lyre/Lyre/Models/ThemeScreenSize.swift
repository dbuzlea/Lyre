//
//  ScreenSize.swift
//  Lyre
//
//  Created by Daniel Buzlea on 5/14/26.
//

import Foundation

enum ScreenSize: String, CaseIterable, Identifiable {
    case nanoTall = "Nano Tall"
    case standard = "Standard"
    case large = "Large"
    case extraLarge = "Extra Large"
    case tall = "Tall"
    case extraTall = "Extra Tall"
    case jumbo = "Jumbo"

    var id: String { rawValue }

    var dimensions: CGSize {
        switch self {
        case .nanoTall:
            return CGSize(width: 320, height: 420)
        case .standard:
            return CGSize(width: 280, height: 200)
        case .large:
            return CGSize(width: 320, height: 240)
        case .extraLarge:
            return CGSize(width: 360, height: 280)
        case .tall:
            return CGSize(width: 330, height: 480)
        case .extraTall:
            return CGSize(width: 340, height: 540)
        case .jumbo:
            return CGSize(width: 350, height: 600)
        }
    }

    var wheelSize: CGFloat {
        switch self {
        case .nanoTall:
            return 260
        case .standard:
            return 280
        case .large:
            return 300
        case .extraLarge:
            return 320
        case .tall:
            return 250
        case .extraTall:
            return 240
        case .jumbo:
            return 230
        }
    }

    // MARK: - Drag to Resize

    /// Every size ordered from shortest to tallest. Dragging a screen corner moves
    /// along this ladder, since the drag only changes the screen's height.
    static let heightLadder: [ScreenSize] = allCases.sorted {
        $0.dimensions.height < $1.dimensions.height
    }

    /// Screen and wheel dimensions for an arbitrary height partway through a drag.
    /// Width and wheel size are blended between the two presets either side of
    /// `height` so the device morphs smoothly instead of jumping. Past either end
    /// of `ladder` the height is used as given while width and wheel hold still.
    static func interpolatedLayout(
        forHeight height: CGFloat,
        in ladder: [ScreenSize]
    ) -> (dimensions: CGSize, wheelSize: CGFloat) {
        guard let first = ladder.first, let last = ladder.last else {
            return (CGSize(width: ScreenSize.standard.dimensions.width, height: height),
                    ScreenSize.standard.wheelSize)
        }
        if height <= first.dimensions.height {
            return (CGSize(width: first.dimensions.width, height: height), first.wheelSize)
        }
        if height >= last.dimensions.height {
            return (CGSize(width: last.dimensions.width, height: height), last.wheelSize)
        }

        for (lower, upper) in zip(ladder, ladder.dropFirst())
        where height <= upper.dimensions.height {
            let span = upper.dimensions.height - lower.dimensions.height
            let t = span > 0 ? (height - lower.dimensions.height) / span : 0
            let width = lower.dimensions.width + (upper.dimensions.width - lower.dimensions.width) * t
            let wheel = lower.wheelSize + (upper.wheelSize - lower.wheelSize) * t
            return (CGSize(width: width, height: height), wheel)
        }
        return (last.dimensions, last.wheelSize)
    }

    /// The preset in `ladder` whose height is closest to `height`.
    static func nearest(toHeight height: CGFloat, in ladder: [ScreenSize]) -> ScreenSize? {
        ladder.min { abs($0.dimensions.height - height) < abs($1.dimensions.height - height) }
    }
}
