//
//  LiquidFoldWater.swift
//  Lyre
//

import CoreHaptics
import SwiftUI

// MARK: - The Water at the Fold
//
// An iPhone Duo open, a bubble carried to the fold meets Now Playing's edge as a drop
// meets the surface of water:
//
//   reaching   the surface swells toward it, and close enough a neck of water reaches out
//              and joins them; pulled away again, the neck stretches thin and snaps, a
//              droplet falling back into the surface
//   pressing   the surface holds: the bubble flattens against it (keeping its volume, so
//              it widens as it flattens) and the surface bows in ahead of it, felt as a
//              hum that grows with the push; Now Playing ripples from where it presses
//   through    pushed past what the surface holds, it gives way with a pop, and the
//              bubble's colour spreads through Now Playing like ink in water
//
// Here, the arithmetic of it, kept apart from the drawing so it can be tested; the
// drawing is LiquidPlayerView's carried layer, and LiquidFoldWater.metal's shaders.
// Everything is measured along the way to Now Playing (across the fold), in points.

enum FoldWater {
    /// How far past the fold a bubble's leading edge is pushed (how far the finger would
    /// put it) before the surface gives way.
    static func breakDepth(radius: CGFloat) -> CGFloat { radius * 0.6 + 16 }

    /// The most the surface gives, short of breaking: however hard it's pushed, the
    /// bubble presses only this far in.
    static func give(radius: CGFloat) -> CGFloat { radius * 0.32 }

    /// Where the leading edge is shown for a push `raw`: as the finger has it on the
    /// bubbles' side; past the fold, held back by the surface, giving ever less.
    static func shownPush(_ raw: CGFloat, radius: CGFloat) -> CGFloat {
        raw <= 0 ? raw : LyreMotion.rubberBand(raw, limit: give(radius: radius))
    }

    /// How hard it's pushing, 0 (not touching) to 1 (about to break through).
    static func pressure(_ raw: CGFloat, radius: CGFloat) -> CGFloat {
        min(1, max(0, raw / breakDepth(radius: radius)))
    }

    static func breaks(_ raw: CGFloat, radius: CGFloat) -> Bool {
        raw >= breakDepth(radius: radius)
    }

    /// Pressed flat against the surface, along the way in, and as much wider across it:
    /// its area kept, as a drop's volume is.
    static func squash(_ pressure: CGFloat) -> (along: CGFloat, across: CGFloat) {
        let along = 1 - 0.26 * min(1, max(0, pressure))
        return (along, 1 / along)
    }

    /// The neck of water between the surface and the bubble.
    struct Neck: Equatable {
        private(set) var isJoined = false

        /// How near the surface starts reaching out for the bubble.
        static func reach(radius: CGFloat) -> CGFloat { 26 + radius * 0.25 }
        /// How far a joined neck stretches before it snaps.
        static func snapGap(radius: CGFloat) -> CGFloat { radius * 0.8 + 34 }

        /// The gap between the surface and the bubble now `gap`: joined at touching; true
        /// when it snaps, stretched past what it holds.
        mutating func update(gap: CGFloat, radius: CGFloat) -> Bool {
            if !isJoined, gap <= 4 {
                isJoined = true
            } else if isJoined, gap > Self.snapGap(radius: radius) {
                isJoined = false
                return true
            }
            return false
        }

        /// Let go of while joined (the bubble floating home): true, as it snaps.
        mutating func release() -> Bool {
            defer { isJoined = false }
            return isJoined
        }

        /// How wide the neck is: joined, wide at touching and ever thinner as it's pulled
        /// out; not yet, a little reach of water growing as the bubble nears.
        func width(gap: CGFloat, radius: CGFloat) -> CGFloat {
            if isJoined {
                let stretch = min(1, max(0, gap / Self.snapGap(radius: radius)))
                return radius * (0.9 - 0.78 * pow(stretch, 0.6))
            }
            let reach = Self.reach(radius: radius)
            guard gap < reach else { return 0 }
            return radius * 0.45 * pow(1 - gap / reach, 1.6)
        }
    }

    /// A droplet left by a neck snapping, falling back into the surface.
    struct Droplet: Identifiable {
        let id = UUID()
        /// Where it broke off, on screen.
        let from: CGPoint
        let radius: CGFloat
        let start = Date()
        static let life: TimeInterval = 0.5
    }

    /// A bubble taken in: its colour spreading through Now Playing from where it went in.
    struct Ink {
        let id = UUID()
        /// Where it went in, on screen.
        let origin: CGPoint
        let color: Color
        let seed = Float.random(in: 0...50)
        let start = Date()
        static let life: TimeInterval = 1.4
    }
}

// MARK: - The Push, Felt

/// The surface holding against the push, as a hum that grows with it, and its giving way
/// as a pop. On a phone without the Taptic Engine's finer control, nothing; the pop then
/// falls back to an ordinary impact.
@MainActor
final class FoldHaptics {
    static let shared = FoldHaptics()

    private let isSupported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var engine: CHHapticEngine?
    private var hum: CHHapticAdvancedPatternPlayer?
    private var lastSent = Date.distantPast

    /// Pushing at `pressure` (0 to 1); 0 lets go of it.
    func press(_ pressure: CGFloat) {
        guard isSupported else { return }
        guard pressure > 0.02 else { return release() }
        if hum == nil { startHum() }
        // A finger's moves come faster than the hum needs telling.
        let now = Date()
        guard now.timeIntervalSince(lastSent) > 1.0 / 40 else { return }
        lastSent = now
        try? hum?.sendParameters([
            CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: Float(0.15 + 0.6 * pressure), relativeTime: 0),
            CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: Float(0.1 + 0.35 * pressure), relativeTime: 0),
        ], atTime: CHHapticTimeImmediate)
    }

    func release() {
        try? hum?.stop(atTime: CHHapticTimeImmediate)
        hum = nil
    }

    /// The surface giving way.
    func pop() {
        release()
        guard isSupported, let engine = startedEngine() else {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            return
        }
        let events = [
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.55),
            ], relativeTime: 0),
            // The water closing behind it.
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.35),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2),
            ], relativeTime: 0.09),
        ]
        if let pattern = try? CHHapticPattern(events: events, parameters: []),
           let player = try? engine.makePlayer(with: pattern) {
            try? player.start(atTime: CHHapticTimeImmediate)
        }
    }

    private func startHum() {
        guard let engine = startedEngine() else { return }
        let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3),
        ], relativeTime: 0, duration: 30)
        guard let pattern = try? CHHapticPattern(events: [event], parameters: []),
              let player = try? engine.makeAdvancedPlayer(with: pattern) else { return }
        try? player.start(atTime: CHHapticTimeImmediate)
        hum = player
    }

    private func startedEngine() -> CHHapticEngine? {
        if let engine { return engine }
        guard let made = try? CHHapticEngine() else { return nil }
        made.isAutoShutdownEnabled = true
        made.resetHandler = { [weak self] in Task { @MainActor in self?.engine = nil; self?.hum = nil } }
        made.stoppedHandler = { [weak self] _ in Task { @MainActor in self?.engine = nil; self?.hum = nil } }
        try? made.start()
        engine = made
        return made
    }
}
