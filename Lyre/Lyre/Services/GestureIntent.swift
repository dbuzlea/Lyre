//
//  GestureIntent.swift
//  Lyre
//

import CoreGraphics
import Foundation

// MARK: - What a Finger Means
//
// One touch on something that can be moved, among things that scroll: is it a swipe
// through them, or meant for the thing under the finger? Decided from the first few
// points of a touch, it's a guess, and a finger that sets off a little the wrong way
// gets the wrong one. iOS's own home gesture doesn't guess: it keeps the finger's speed,
// smoothed over the last moments, and how far it's come, and keeps naming what the
// gesture means (going home, or, paused, the app switcher) until it's lifted, showing
// each as it's named.
//
// Here the same for Lyre's bubbles (and anything like them): fed the finger's samples
// and the passing time, it names the touch's intent, each by the rule that named it.
//
//   moving off at once            a swipe through the field (scroll)
//   resting a moment              it's lifted, to be carried (liftByPausing)
//   lifted, then moved            carried anywhere (carry)
//   lifted, and resting on        held: its songs spread (spreadByHolding)
//   flicked toward Now Playing    carried there at once (pullByFlick); only where that
//                                 way isn't the field's own scrolling
//   lifted off quickly, still     a tap (tap), even just after it was lifted
//
// Pure: no touches, no clock of its own, so it's tested by replaying traces.

nonisolated struct GestureIntent {
    enum Intent: Equatable {
        /// Not yet named.
        case undecided
        /// A swipe through the field: the touch is the scroll's.
        case scroll
        /// Rested on a moment: it's lifted, held still.
        case lift
        /// Lifted and moved: it goes where the finger takes it.
        case carry
        /// Flicked toward where it's dropped, from the start: carried at once.
        case pull
        /// Lifted and rested on: held, for its songs.
        case spread
        /// Touched and let go, still and quick.
        case tap
        /// Let go without meaning anything else.
        case none

        /// The rule that named it, as iOS names its outcomes: for the tuning overlay.
        var rule: String {
            switch self {
            case .undecided: "undecided"
            case .scroll: "scrollByMovingAtOnce"
            case .lift: "liftByPausing"
            case .carry: "carryAfterLift"
            case .pull: "pullByFlick"
            case .spread: "spreadByHolding"
            case .tap: "tapByQuickRelease"
            case .none: "none"
            }
        }
    }

    struct Thresholds {
        /// How far the finger can wander and still be resting (points).
        var slop: CGFloat = 10
        /// Slower than this, smoothed, it's resting (points a second).
        var restSpeed: CGFloat = 60
        /// Resting this long lifts it.
        var liftAfter: TimeInterval = 0.16
        /// Lifted and resting this long (from the touch) holds it, for its songs.
        var spreadAfter: TimeInterval = 0.5
        /// How widely a flick can stray from the way to where it's dropped (radians).
        var pullCone: CGFloat = .pi * 40 / 180
        /// The smoothing of the finger's speed: how far back it reaches (seconds).
        var smoothing: TimeInterval = 0.08
        /// Held this long, a touch is no longer a tap.
        var tapWithin: TimeInterval = 0.35
    }

    var thresholds = Thresholds()
    /// The ways a flick carries it (unit vectors), none of them the way the field scrolls:
    /// a bubble's toward Now Playing; a rack's tape left into the deck or right to queue.
    /// Empty where the only way is the scroll's (then only a pause lifts it).
    var pullDirections: [CGVector] = []
    /// The one way a flick carries it, for a single drop target.
    var pullDirection: CGVector? {
        get { pullDirections.first }
        set { pullDirections = newValue.map { [$0] } ?? [] }
    }
    /// Whether it can be lifted and carried at all (a show's bubble can't, only held).
    var canCarry = true

    private(set) var intent: Intent = .undecided
    private(set) var start: CGPoint = .zero
    private(set) var startTime: TimeInterval = 0
    private(set) var location: CGPoint = .zero
    /// The finger's velocity, smoothed (points a second).
    private(set) var velocity: CGVector = .zero
    /// Where it was lifted, for how far it's moved since.
    private(set) var liftPoint: CGPoint = .zero
    private var lastTime: TimeInterval = 0

    init(pullDirection: CGVector? = nil, canCarry: Bool = true, thresholds: Thresholds = Thresholds()) {
        self.pullDirections = pullDirection.map { [$0] } ?? []
        self.canCarry = canCarry
        self.thresholds = thresholds
    }

    var speed: CGFloat { hypot(velocity.dx, velocity.dy) }
    var moved: CGFloat { hypot(location.x - start.x, location.y - start.y) }

    /// A finger down at `point`.
    mutating func began(at point: CGPoint, time: TimeInterval) {
        intent = .undecided
        start = point
        location = point
        startTime = time
        lastTime = time
        velocity = .zero
    }

    /// The finger at `point`, at `time`. Returns the intent, if that changed it.
    @discardableResult
    mutating func moved(to point: CGPoint, time: TimeInterval) -> Intent {
        let dt = max(time - lastTime, 0.001)
        let instant = CGVector(dx: (point.x - location.x) / dt, dy: (point.y - location.y) / dt)
        let keep = exp(-dt / thresholds.smoothing)
        velocity = CGVector(dx: velocity.dx * keep + instant.dx * (1 - keep),
                            dy: velocity.dy * keep + instant.dy * (1 - keep))
        location = point
        lastTime = time
        decide(at: time)
        return intent
    }

    /// Time passing with the finger still: its speed settles, and a pause can name it.
    @discardableResult
    mutating func tick(at time: TimeInterval) -> Intent {
        let dt = max(time - lastTime, 0)
        if dt > 0 {
            let keep = exp(-dt / thresholds.smoothing)
            velocity = CGVector(dx: velocity.dx * keep, dy: velocity.dy * keep)
            lastTime = time
        }
        decide(at: time)
        return intent
    }

    /// The finger lifted: a tap, if it was quick and still; otherwise what it already was.
    @discardableResult
    mutating func ended(at time: TimeInterval) -> Intent {
        // Lifted but never moved, and let go quickly: it was a tap after all (a slow one).
        if intent == .lift, time - startTime <= thresholds.tapWithin, moved <= thresholds.slop {
            intent = .tap
        } else if intent == .undecided {
            intent = time - startTime <= thresholds.tapWithin && moved <= thresholds.slop ? .tap : .none
        }
        return intent
    }

    private mutating func decide(at time: TimeInterval) {
        let t = thresholds
        switch intent {
        case .undecided:
            if moved > t.slop {
                // Off at once: toward where it's dropped, a flick carries it; any other way
                // is the field's.
                let way = offset(from: start)
                if canCarry, pullDirections.contains(where: { angle(between: way, and: $0) <= t.pullCone }) {
                    intent = .pull
                } else {
                    intent = .scroll
                }
            } else if time - startTime >= t.liftAfter, speed < t.restSpeed {
                liftPoint = location
                intent = canCarry ? .lift : (time - startTime >= t.spreadAfter ? .spread : .undecided)
            }
        case .lift:
            if hypot(location.x - liftPoint.x, location.y - liftPoint.y) > t.slop {
                intent = .carry
            } else if time - startTime >= t.spreadAfter {
                intent = .spread
            }
        default:
            break
        }
    }

    private func offset(from point: CGPoint) -> CGVector {
        CGVector(dx: location.x - point.x, dy: location.y - point.y)
    }

    private func angle(between a: CGVector, and b: CGVector) -> CGFloat {
        let la = hypot(a.dx, a.dy), lb = hypot(b.dx, b.dy)
        guard la > 0, lb > 0 else { return .pi }
        return acos(max(-1, min(1, (a.dx * b.dx + a.dy * b.dy) / (la * lb))))
    }
}
