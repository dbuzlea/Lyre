//
//  GestureIntentTests.swift
//  LyreTests
//

import CoreGraphics
import SwiftUI
import Testing
@testable import Lyre

/// Touches replayed through GestureIntent: each path of a finger, and what it should be
/// read as, by the rule iOS's own home gesture uses (speed smoothed, and a pause).
@Suite("Gesture intent")
struct GestureIntentTests {
    /// A finger from `from`, moving by `step` every frame (60 a second) for `frames`.
    private func move(_ intent: inout GestureIntent, from: CGPoint, step: CGVector, frames: Int, start: Double) -> Double {
        var t = start
        var p = from
        for _ in 0..<frames {
            t += 1.0 / 60
            p = CGPoint(x: p.x + step.dx, y: p.y + step.dy)
            intent.moved(to: p, time: t)
        }
        return t
    }

    /// The finger resting where it is, the clock ticking, for `seconds`.
    private func rest(_ intent: inout GestureIntent, seconds: Double, start: Double) -> Double {
        var t = start
        while t < start + seconds {
            t += 1.0 / 60
            intent.tick(at: t)
        }
        return t
    }

    @Test func movingOffAtOnceScrolls() {
        var intent = GestureIntent(pullDirection: CGVector(dx: -1, dy: 0))
        intent.began(at: .zero, time: 0)
        _ = move(&intent, from: .zero, step: CGVector(dx: 0, dy: -6), frames: 5, start: 0)
        #expect(intent.intent == .scroll)
    }

    @Test func restingAMomentLiftsAndThenItCarriesAnyWay() {
        var intent = GestureIntent(pullDirection: nil)
        intent.began(at: .zero, time: 0)
        var t = rest(&intent, seconds: 0.1, start: 0)
        #expect(intent.intent == .undecided, "Not yet: a moment is longer")
        t = rest(&intent, seconds: 0.1, start: t)
        #expect(intent.intent == .lift)
        // Down and to the right: neither way to Now Playing, and still carried.
        _ = move(&intent, from: .zero, step: CGVector(dx: 3, dy: 4), frames: 6, start: t)
        #expect(intent.intent == .carry)
    }

    @Test func restingOnHoldsItForItsSongs() {
        var intent = GestureIntent()
        intent.began(at: .zero, time: 0)
        _ = rest(&intent, seconds: 0.55, start: 0)
        #expect(intent.intent == .spread)
    }

    @Test func aFingerThatDriftsALittleStillRests() {
        var intent = GestureIntent()
        intent.began(at: .zero, time: 0)
        // A finger's tremor: a few points, slowly, never past the slop.
        var t = 0.0
        for frame in 0..<14 {
            t += 1.0 / 60
            intent.moved(to: CGPoint(x: frame.isMultiple(of: 2) ? 1 : -1, y: 0.2 * Double(frame)), time: t)
        }
        t = rest(&intent, seconds: 0.05, start: t)
        #expect(intent.intent == .lift)
    }

    @Test func aFlickTowardNowPlayingCarriesAtOnceOnlyWhereItIsntTheScroll() {
        // Held as a book: Now Playing on the left, the field scrolling up and down.
        var book = GestureIntent(pullDirection: CGVector(dx: -1, dy: 0))
        book.began(at: .zero, time: 0)
        // Leftward and a little up, well inside the cone.
        _ = move(&book, from: .zero, step: CGVector(dx: -8, dy: -3), frames: 3, start: 0)
        #expect(book.intent == .pull)

        // Turned: Now Playing above, which is the way the field scrolls: a swipe.
        var turned = GestureIntent(pullDirection: nil)
        turned.began(at: .zero, time: 0)
        _ = move(&turned, from: .zero, step: CGVector(dx: -8, dy: -3), frames: 3, start: 0)
        #expect(turned.intent == .scroll)
    }

    @Test func aQuickStillTouchIsATapEvenASlowOne() {
        var quick = GestureIntent()
        quick.began(at: .zero, time: 0)
        #expect(quick.ended(at: 0.08) == .tap)

        // Slow enough to have lifted, but never moved: still a tap.
        var slow = GestureIntent()
        slow.began(at: .zero, time: 0)
        let t = rest(&slow, seconds: 0.25, start: 0)
        #expect(slow.intent == .lift)
        #expect(slow.ended(at: t) == .tap)

        // Lifted and set down after a while: nothing.
        var long = GestureIntent()
        long.began(at: .zero, time: 0)
        let later = rest(&long, seconds: 0.4, start: 0)
        #expect(long.intent == .lift)
        #expect(long.ended(at: later) == .lift)
    }

    @Test func aShowsBubbleIsNeverLiftedOnlyHeld() {
        var show = GestureIntent(canCarry: false)
        show.began(at: .zero, time: 0)
        var t = rest(&show, seconds: 0.25, start: 0)
        #expect(show.intent == .undecided)
        t = rest(&show, seconds: 0.3, start: t)
        #expect(show.intent == .spread)
    }

    @Test func theSpeedIsSmoothedAndSettlesWhenTheFingerStops() {
        var intent = GestureIntent()
        intent.began(at: .zero, time: 0)
        let t = move(&intent, from: .zero, step: CGVector(dx: 0, dy: 5), frames: 10, start: 0)
        // 5 points a frame at 60 a second: about 300 points a second, eased toward it.
        #expect(intent.speed > 200 && intent.speed < 320)
        _ = rest(&intent, seconds: 0.3, start: t)
        #expect(intent.speed < GestureIntent.Thresholds().restSpeed / 4, "Settled well under resting")
    }

    /// Up Next's bubble reaches out toward what's carried, on that side only; and warps
    /// all round as it takes it in.
    @Test func upNextsEdgeReachesTowardTheSongAndWarps() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let still = UpNextReachShape(reach: 0, angle: 0, spread: 0.5, warp: 0, phase: 0).path(in: rect).boundingRect
        #expect(abs(still.width - 100) < 2 && abs(still.height - 100) < 2, "At rest, round")
        // Reaching right (angle 0) by 30: out on the right, not on the left.
        let right = UpNextReachShape(reach: 30, angle: 0, spread: 0.5, warp: 0, phase: 0).path(in: rect).boundingRect
        #expect(right.maxX > 125)
        #expect(abs(right.minX) < 2)
        // Down (angle π/2): out at the bottom.
        let down = UpNextReachShape(reach: 30, angle: .pi / 2, spread: 0.5, warp: 0, phase: 0).path(in: rect).boundingRect
        #expect(down.maxY > 125 && down.maxX < 103)
        // Warped: no longer round.
        let warped = UpNextReachShape(reach: 0, angle: 0, spread: 0.5, warp: 1, phase: 0).path(in: rect).boundingRect
        #expect(warped.width > 104 || warped.height > 104)
    }
}
