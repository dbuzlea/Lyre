//
//  LiquidWave.swift
//  Lyre
//

import SwiftUI

// MARK: - Liquid Wave
//
// The wave the Liquid player turns songs with. Each side edge carries a small bulge with
// an arrow; dragging it stretches a liquid wave across the screen that carries the next
// (or previous) song's cover, and letting go either springs it back or floods the screen
// with it.
//
// The geometry is adapted from exyte's LiquidSwipe (MIT licence,
// https://github.com/exyte/LiquidSwipe), itself after Cuberto's liquid-swipe: the same
// bezier table and the same damped spring for the wave's width. Here it is sized from the
// view it's drawn in rather than the screen, so it works in any layout, and the wave is
// driven entirely by `progress` (0 resting, 1 covering the screen) and `centerY` (where
// the finger is), both animatable.

enum LiquidSide {
    case left
    case right
}

struct LiquidWaveGeometry {
    let side: LiquidSide
    let centerY: CGFloat
    let progress: CGFloat
    let size: CGSize

    static let minLedge: CGFloat = 12
    static let minHorizontalRadius: CGFloat = 44
    static let minVerticalRadius: CGFloat = 78
    static let buttonRadius: CGFloat = 22
    static let buttonMargin: CGFloat = 6
    /// How far a drag moves the wave, as a share of the drag.
    static let dragGain: CGFloat = 0.45
    /// Below this, letting go springs the wave back.
    static let cancelThreshold: CGFloat = 0.15

    var waveLedgeX: CGFloat {
        let ledge = Self.interpolate(Self.minLedge, size.width, progress, min: 0.2, max: 0.8)
        return side == .left ? ledge : size.width - ledge
    }

    var horizontalRadius: CGFloat {
        let p1: CGFloat = 0.4
        let full = size.width * 0.8
        if progress <= p1 { return Self.interpolate(Self.minHorizontalRadius, full, progress, max: p1) }
        if progress >= 1 { return full }
        // A damped spring, so the wave's bulge overshoots and settles as it floods.
        let t = Double((progress - p1) / (1 - p1))
        let m = 9.8
        let beta = 40.0 / (2 * m)
        let omega = (-(beta * beta) + pow(50.0 / m, 2)).squareRoot()
        return full * CGFloat(exp(-beta * t) * cos(omega * t))
    }

    var verticalRadius: CGFloat {
        Self.interpolate(Self.minVerticalRadius, size.height * 0.9, progress, max: 0.4)
    }

    /// The centre of the arrow button, riding the bulge.
    var buttonCenter: CGPoint {
        let sign: CGFloat = side == .left ? 1 : -1
        let inset = Self.buttonRadius + Self.buttonMargin
        return CGPoint(x: waveLedgeX + sign * (horizontalRadius - inset), y: centerY)
    }

    var buttonOpacity: Double { Double(max(1 - progress * 5, 0)) }

    static func interpolate(_ from: CGFloat, _ to: CGFloat, _ fraction: CGFloat,
                            min: CGFloat = 0, max: CGFloat = 1) -> CGFloat {
        if fraction <= min { return from }
        if fraction >= max { return to }
        return from + (to - from) * (fraction - min) / (max - min)
    }
}

struct LiquidWaveShape: Shape {
    let side: LiquidSide
    var centerY: CGFloat
    var progress: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(centerY, progress) }
        set {
            centerY = newValue.first
            progress = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let wave = LiquidWaveGeometry(side: side, centerY: centerY, progress: progress, size: rect.size)
        let ledge = wave.waveLedgeX
        let hr = wave.horizontalRadius
        let vr = wave.verticalRadius
        let curveStartY = vr + centerY
        let sign: CGFloat = side == .left ? 1 : -1
        let outside: CGFloat = side == .left ? -50 : rect.width + 50

        var path = Path()
        path.move(to: CGPoint(x: ledge, y: -100))
        path.addLine(to: CGPoint(x: outside, y: -100))
        path.addLine(to: CGPoint(x: outside, y: rect.height + 100))
        path.addLine(to: CGPoint(x: ledge, y: rect.height + 100))
        path.addLine(to: CGPoint(x: ledge, y: curveStartY))
        var index = 0
        while index < Self.curve.count {
            let c = Self.curve
            path.addCurve(to: CGPoint(x: ledge + sign * hr * c[index + 4], y: curveStartY - vr * c[index + 5]),
                          control1: CGPoint(x: ledge + sign * hr * c[index], y: curveStartY - vr * c[index + 1]),
                          control2: CGPoint(x: ledge + sign * hr * c[index + 2], y: curveStartY - vr * c[index + 3]))
            index += 6
        }
        path.closeSubpath()
        return path
    }

    /// The bulge, as cubic segments in units of the wave's radii (from LiquidSwipe).
    private static let curve: [CGFloat] = [
        0, 0.13461, 0.05341, 0.24127, 0.15615, 0.33223,
        0.23616, 0.40308, 0.33052, 0.45611, 0.50124, 0.53505,
        0.51587, 0.54182, 0.56641, 0.56503, 0.57493, 0.56896,
        0.72837, 0.63973, 0.80866, 0.68334, 0.87740, 0.73990,
        0.96534, 0.81226, 1, 0.89361, 1, 1,
        1, 1.10014, 0.95957, 1.18879, 0.86084, 1.27048,
        0.78521, 1.33305, 0.70338, 1.37958, 0.52911, 1.46651,
        0.52418, 1.46896, 0.50573, 1.47816, 0.50153, 1.48026,
        0.31874, 1.57142, 0.23320, 1.62041, 0.15411, 1.68740,
        0.05099, 1.77475, 0, 1.87092, 0, 2
    ]
}

/// The small bulge on the bottom edge that Up Next is pulled up by: the same liquid
/// shape, lying on its side and kept small.
struct LiquidBottomBulge: Shape {
    /// 0 resting; grows a little as a finger pulls it.
    var lift: CGFloat

    var animatableData: CGFloat {
        get { lift }
        set { lift = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let height = 7 + 22 * (1 + lift)
        let half: CGFloat = 46 + 30 * lift
        let mid = rect.midX
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.maxY))
        path.addLine(to: CGPoint(x: mid - half * 2, y: rect.maxY))
        path.addCurve(to: CGPoint(x: mid, y: rect.maxY - height),
                      control1: CGPoint(x: mid - half, y: rect.maxY),
                      control2: CGPoint(x: mid - half * 0.6, y: rect.maxY - height))
        path.addCurve(to: CGPoint(x: mid + half * 2, y: rect.maxY),
                      control1: CGPoint(x: mid + half * 0.6, y: rect.maxY - height),
                      control2: CGPoint(x: mid + half, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A wavy top edge, for surfaces that rise or melt into the next: the album's cover
/// melting into its page, the Tide rising over Now Playing.
struct LiquidEdgeShape: Shape {
    /// The wave's height, as a share of the shape's height.
    var amplitude: CGFloat = 0.5
    /// Moves the wave along, for a slow drift.
    var phase: CGFloat = 0

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let amp = rect.height * amplitude / 2
        let base = rect.minY + rect.height / 2
        path.move(to: CGPoint(x: rect.minX, y: base))
        let steps = 48
        for step in 0...steps {
            let x = rect.minX + rect.width * CGFloat(step) / CGFloat(steps)
            let t = CGFloat(step) / CGFloat(steps) * .pi * 2 * 1.3 + phase
            path.addLine(to: CGPoint(x: x, y: base + sin(t) * amp))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
