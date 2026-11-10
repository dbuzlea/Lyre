//
//  LyreMotion.swift
//  Lyre
//

import SwiftUI

// MARK: - Lyre's Motion
//
// One way of moving, the same in every player, after Apple's "Designing Fluid Interfaces"
// (WWDC18): springs described by how quickly they move and how much they bounce, never a
// duration, so anything moving can be caught and sent somewhere else from where it is.
//
//   tap       a tap's answer: quick, and no bounce (a tap carries no momentum)
//   light     light things moved for you (cards, bubbles, sheets): quick, a touch of give
//   heavy     heavy things (a tape, a disc, the Gramophone's camera): slower, settled
//   release   a drag let go: goes on at the finger's speed and lands with a little bounce
//             when it was flung, none when it was set down slowly
//
// Plus the soft wall a drag meets past its end (rubber banding), and the finger's speed
// turned into the spring's starting speed.

enum LyreMotion {
    static let tap = Animation.spring(response: 0.3, dampingFraction: 1)
    static let light = Animation.spring(response: 0.36, dampingFraction: 0.86)
    static let heavy = Animation.spring(response: 0.55, dampingFraction: 0.9)

    /// A drag let go, `distance` points from where it lands, moving at `velocity` points
    /// a second (positive towards the landing): it carries on at that speed, and bounces
    /// a little only if it was flung.
    /// `bounces: false` for a landing past an edge, where a bounce would only be waited on.
    static func release(velocity: CGFloat, distance: CGFloat, bounces: Bool = true) -> Animation {
        let initial = relativeVelocity(velocity, distance: distance)
        let flung = bounces && abs(velocity) > 600
        return .interpolatingSpring(duration: flung ? 0.42 : 0.36, bounce: flung ? 0.18 : 0,
                                    initialVelocity: initial)
    }

    /// The finger's speed as a share of the distance left a second, which is what a
    /// spring's initial velocity is measured in; capped, so a tiny distance can't send it off.
    static func relativeVelocity(_ velocity: CGFloat, distance: CGFloat) -> Double {
        guard abs(distance) > 0.5 else { return 0 }
        return Double(max(-30, min(30, velocity / distance)))
    }

    /// A drag past its end: it goes on giving, ever less, as a rubber band does, never
    /// past `limit`.
    static func rubberBand(_ overshoot: CGFloat, limit: CGFloat) -> CGFloat {
        guard limit > 0 else { return 0 }
        let sign: CGFloat = overshoot < 0 ? -1 : 1
        let x = abs(overshoot)
        return sign * (1 - 1 / (x * 0.55 / limit + 1)) * limit
    }
}

/// A button's answer to the touch itself, not the lift: it gives a little under the finger
/// at once, and comes back as the finger leaves, so a slide off the button reads as
/// letting go of it.
///
/// A row (`isRow`) only dims: a whole row shrinking would read as the list moving.
struct LyrePressStyle: ButtonStyle {
    var isRow = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(!isRow && configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? (isRow ? 0.55 : 0.75) : 1)
            // Down at once, back with the tap's spring.
            .animation(configuration.isPressed ? nil : LyreMotion.tap, value: configuration.isPressed)
    }
}

/// A hold shown as it builds: what's held sinks in over the hold's length, and springs
/// back if the finger lifts first, so a hold is seen happening and can be let go of.
struct HoldHint: ViewModifier {
    let isPressing: Bool
    var duration: Double = 0.5
    var depth: CGFloat = 0.06

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressing ? 1 - depth : 1)
            .brightness(isPressing ? 0.06 : 0)
            .animation(isPressing ? .easeIn(duration: duration) : LyreMotion.light, value: isPressing)
    }
}

/// A thing in flight drawn out along its way (`angle`, radians) and a little thinner
/// across it, by `amount` (0 to 1): the eye's own smear of something moving fast.
struct MotionStretch: GeometryEffect {
    var amount: Double
    let angle: Double
    /// How far `amount` 1 draws it out along its way, and thins it across.
    var along: Double = 0.08
    var across: Double = 0.04

    var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let along = 1 + self.along * amount
        let across = 1 - self.across * amount
        let centre = CGAffineTransform(translationX: -size.width / 2, y: -size.height / 2)
        let transform = centre
            .concatenating(CGAffineTransform(rotationAngle: -angle))
            .concatenating(CGAffineTransform(scaleX: along, y: across))
            .concatenating(CGAffineTransform(rotationAngle: angle))
            .concatenating(CGAffineTransform(translationX: size.width / 2, y: size.height / 2))
        return ProjectionTransform(transform)
    }
}
