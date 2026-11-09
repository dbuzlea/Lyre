//
//  BubbleTilt.swift
//  Lyre
//

import SwiftUI
import CoreMotion
internal import Combine

// MARK: - Bubble Tilt
//
// Liquid's bubbles stay where they are, but answer to the phone being moved, as real
// ones would under a light that keeps still while the phone turns beneath it:
//
//   1  the highlight slides across each bubble against the tilt, and a glint runs round
//      the rim to the side the light now catches
//   2  the rainbow film round the top creeps round the rim and brightens as the angle
//      changes
//   3  the cover inside drifts a few points the other way, behind the curved film
//   4  each bubble's shadow on the page slides with the light
//   5  a quick flick of the phone sets them quivering, and they settle
//   6  they sag a touch towards whichever way is down, as a bubble's weight pulls it
//
// One reader for every bubble on screen: the phone's motion, 30 times a second, its
// tilt published 10 times a second and eased between (so the bubbles move smoothly
// without being redrawn each frame). The tilt is the change from how the phone's been
// held lately, which creeps after a held angle, so any way of holding it rests at
// neutral. Stopped when no bubble page is showing, while one scrolls, and with Reduce
// Motion or Low Power Mode on. Each effect is a layer moved, turned or stretched over
// the bubble's finished picture, never a redraw of the bubble.

@MainActor
final class BubbleTilt: ObservableObject {
    static let shared = BubbleTilt()

    /// The tilt from how the phone's been held lately, each way -1…1 (x right, y down).
    @Published private(set) var tilt: CGVector = .zero
    /// Which way is down on the screen, and how far the screen's from lying flat (0…1).
    @Published private(set) var down: CGVector = CGVector(dx: 0, dy: 0)
    /// Counts the flicks of the phone: each sets the bubbles quivering.
    @Published private(set) var jolts = 0

    /// Held still (a bubble page scrolling).
    var isPaused = false {
        didSet { if isPaused != oldValue { update() } }
    }

    private let motion = CMMotionManager()
    private var users = 0
    private var isRunning = false
    private var baseline: CGVector?
    private var smoothed: CGVector = .zero
    private var samples = 0
    private var lastJolt = Date.distantPast
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        for name in [UIAccessibility.reduceMotionStatusDidChangeNotification, .NSProcessInfoPowerStateDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            })
        }
    }

    /// A bubble page came on screen.
    func attach() {
        users += 1
        update()
    }

    /// A bubble page went.
    func detach() {
        users = max(0, users - 1)
        update()
    }

    private var shouldRun: Bool {
        users > 0 && !isPaused && motion.isDeviceMotionAvailable
            && !UIAccessibility.isReduceMotionEnabled && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private func update() {
        if shouldRun, !isRunning {
            isRunning = true
            motion.deviceMotionUpdateInterval = 1.0 / 30
            motion.startDeviceMotionUpdates(to: .main) { [weak self] reading, _ in
                guard let reading else { return }
                MainActor.assumeIsolated { self?.read(reading) }
            }
        } else if !shouldRun, isRunning {
            isRunning = false
            motion.stopDeviceMotionUpdates()
            baseline = nil
            // Back to rest, gently.
            withAnimation(.easeOut(duration: 0.4)) { tilt = .zero }
        }
    }

    private func read(_ reading: CMDeviceMotion) {
        let gravity = CGVector(dx: reading.gravity.x, dy: -reading.gravity.y)
        let base = BubbleTiltMath.creep(baseline ?? gravity, toward: gravity)
        baseline = base
        smoothed = BubbleTiltMath.ease(smoothed, toward: BubbleTiltMath.relativeTilt(gravity, baseline: base))
        let acceleration = reading.userAcceleration
        if BubbleTiltMath.isJolt(x: acceleration.x, y: acceleration.y, z: acceleration.z),
           Date().timeIntervalSince(lastJolt) > 0.7 {
            lastJolt = Date()
            jolts += 1
        }
        samples += 1
        // Published a third as often as read, and eased between, so the bubbles glide.
        guard samples.isMultiple(of: 3) else { return }
        let tilt = smoothed, down = BubbleTiltMath.down(gravity)
        withAnimation(.linear(duration: 0.1)) {
            self.tilt = tilt
            self.down = down
        }
    }
}

/// The arithmetic of the tilt, apart from the motion reader, so it can be tried.
nonisolated enum BubbleTiltMath {
    /// How quickly the held angle is forgotten: about 8 s to settle at 30 readings a second.
    static let creepRate = 0.004
    /// How far a tilt has to go to reach full effect (gravity's share of the screen axis).
    static let fullTilt = 0.35

    static func creep(_ baseline: CGVector, toward gravity: CGVector, rate: Double = creepRate) -> CGVector {
        CGVector(dx: baseline.dx + (gravity.dx - baseline.dx) * rate,
                 dy: baseline.dy + (gravity.dy - baseline.dy) * rate)
    }

    /// The tilt from the held angle, each way -1…1.
    static func relativeTilt(_ gravity: CGVector, baseline: CGVector) -> CGVector {
        CGVector(dx: max(-1, min(1, (gravity.dx - baseline.dx) / fullTilt)),
                 dy: max(-1, min(1, (gravity.dy - baseline.dy) / fullTilt)))
    }

    static func ease(_ current: CGVector, toward target: CGVector, by amount: Double = 0.25) -> CGVector {
        CGVector(dx: current.dx + (target.dx - current.dx) * amount,
                 dy: current.dy + (target.dy - current.dy) * amount)
    }

    /// Down on the screen: its direction, as long as gravity's pull across the screen
    /// (0 lying flat, 1 standing upright).
    static func down(_ gravity: CGVector) -> CGVector {
        let length = hypot(gravity.dx, gravity.dy)
        return length > 1 ? CGVector(dx: gravity.dx / length, dy: gravity.dy / length) : gravity
    }

    /// A flick: the phone moved hard, past walking and turning it over in a hand.
    static func isJolt(x: Double, y: Double, z: Double) -> Bool {
        (x * x + y * y + z * z).squareRoot() > 0.9
    }

    /// The sag towards down: the angle to stretch along, and how much (1 = none).
    static func sag(_ down: CGVector, amount: Double = 0.025) -> (angle: Angle, stretch: CGFloat) {
        let pull = min(1, hypot(down.dx, down.dy))
        return (.radians(atan2(down.dx, down.dy)), 1 + CGFloat(pull * amount))
    }
}

// MARK: - The Effects

/// Moves a layer with the tilt: `reach` points at full tilt, each way.
struct TiltShift: ViewModifier {
    let reach: CGSize
    @ObservedObject private var motion = BubbleTilt.shared

    func body(content: Content) -> some View {
        content.offset(x: motion.tilt.dx * reach.width, y: motion.tilt.dy * reach.height)
    }
}

/// Turns a layer with the sideways tilt, and brightens it with how far the phone's tilted.
struct TiltTurn: ViewModifier {
    let degrees: Double
    var brightens: ClosedRange<Double>? = nil
    @ObservedObject private var motion = BubbleTilt.shared

    func body(content: Content) -> some View {
        let amount = min(1, hypot(motion.tilt.dx, motion.tilt.dy))
        content
            .rotationEffect(.degrees(motion.tilt.dx * degrees - motion.tilt.dy * degrees * 0.4))
            .opacity(brightens.map { $0.lowerBound + ($0.upperBound - $0.lowerBound) * amount } ?? 1)
    }
}

/// A bubble's shadow on the page, sliding with the light: a soft dark disc under it.
struct TiltShadow: View {
    let diameter: CGFloat
    @ObservedObject private var motion = BubbleTilt.shared

    var body: some View {
        Circle()
            .fill(.black.opacity(0.42))
            .frame(width: diameter * 0.92, height: diameter * 0.92)
            .blur(radius: diameter / 16)
            .offset(x: motion.tilt.dx * diameter * 0.06, y: diameter / 26 + motion.tilt.dy * diameter * 0.05)
    }
}

/// The sag towards down, and the quiver after a flick: the whole bubble stretched, never
/// redrawn.
struct BubbleWeight: ViewModifier {
    let seed: String
    @ObservedObject private var motion = BubbleTilt.shared

    func body(content: Content) -> some View {
        let sag = BubbleTiltMath.sag(motion.down)
        content
            // Stretched along down, without turning: turn, stretch, turn back.
            .rotationEffect(-sag.angle)
            .scaleEffect(x: 2 - sag.stretch, y: sag.stretch)
            .rotationEffect(sag.angle)
            .keyframeAnimator(initialValue: CGSize(width: 1, height: 1), trigger: motion.jolts) { view, scale in
                view.scaleEffect(x: scale.width, y: scale.height)
            } keyframes: { _ in
                // Each a moment apart, so they don't quiver in step.
                KeyframeTrack(\.width) {
                    LinearKeyframe(1, duration: Self.delay(seed))
                    SpringKeyframe(1.05, duration: 0.12, spring: .bouncy)
                    SpringKeyframe(0.97, duration: 0.14, spring: .bouncy)
                    SpringKeyframe(1.015, duration: 0.14, spring: .bouncy)
                    SpringKeyframe(1, duration: 0.3, spring: .smooth)
                }
                KeyframeTrack(\.height) {
                    LinearKeyframe(1, duration: Self.delay(seed))
                    SpringKeyframe(0.95, duration: 0.12, spring: .bouncy)
                    SpringKeyframe(1.03, duration: 0.14, spring: .bouncy)
                    SpringKeyframe(0.985, duration: 0.14, spring: .bouncy)
                    SpringKeyframe(1, duration: 0.3, spring: .smooth)
                }
            }
    }

    static func delay(_ seed: String) -> Double {
        Double(seed.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value } % 12) / 100
    }
}
