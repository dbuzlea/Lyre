//
//  LiquidRipple.swift
//  Lyre
//

import SwiftUI

// MARK: - Liquid Ripple
//
// Now Playing's cover as if it lay under water on a speaker: on each beat a ring runs out
// from near the middle, the first beat of every bar a little harder, and a tap sends one
// out from the finger. The rings are drawn by the `liquidRipple` shader
// (LiquidRipple.metal), which bends the cover through the moving surface.
//
// The music plays through the system's player, which lets no app hear it, so the beat is
// the song's tempo from its beats-per-minute tag, counted from the start of the song, as
// the side waves count it (see LiquidNowPlayingView). A song with no tempo tagged ripples
// at an easy 90.
//
// Still with Reduce Motion, in Low Power Mode and under a UI test, where a surface that
// never settles keeps XCUITest waiting for the app to go idle.

enum LiquidRipple {
    /// Where a ring starts, when, and how hard (0 to 1).
    struct Drop: Equatable {
        var center: CGPoint
        var start: Date
        var strength: Double
    }

    /// How long a ring runs before the water's still again.
    static let life: TimeInterval = 2.6
    /// The tempo for a song without one.
    static let defaultBeatsPerMinute = 90.0
    /// The most rings the shader is asked to draw at once.
    static let maxDrops = 12

    static let beatStrength = 0.5
    static let barStrength = 0.75
    static let tapStrength = 1.0

    /// Whether the cover ripples at all.
    static func isAllowed(reduceMotion: Bool) -> Bool {
        !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled && !AppEnvironment.isUITesting
    }

    /// The beats still rippling at `now`: one ring for every beat in the last `life`
    /// seconds, counted from `anchor`, none after `end` (when the music stopped). Each
    /// lands a little way from the middle, the same place for the same beat, so a ring
    /// doesn't jump about from frame to frame.
    static func beatDrops(anchor: Date, beatsPerMinute: Double?, now: Date, end: Date?,
                          size: CGSize) -> [Drop] {
        let period = 60 / (beatsPerMinute ?? defaultBeatsPerMinute)
        let last = min(now, end ?? now)
        let first = floor(now.addingTimeInterval(-life).timeIntervalSince(anchor) / period) + 1
        let latest = floor(last.timeIntervalSince(anchor) / period)
        guard latest >= first, latest >= 0 else { return [] }
        let beats = stride(from: max(first, 0, latest - Double(maxDrops - 1)), through: latest, by: 1)
        return beats.map { beat in
            let index = Int(beat)
            return Drop(center: landing(of: index, in: size),
                        start: anchor.addingTimeInterval(beat * period),
                        strength: index % 4 == 0 ? barStrength : beatStrength)
        }
    }

    /// Near the middle, a little above it, where the cover's subject usually is, and off
    /// it by up to a tenth of the width either way, the same for the same beat.
    static func landing(of beat: Int, in size: CGSize) -> CGPoint {
        func jitter(_ seed: Int) -> Double {
            // Cheap, steady noise in -1...1 from the beat number.
            let x = sin(Double(seed) * 12.9898 + 78.233) * 43_758.5453
            return (x - x.rounded(.down)) * 2 - 1
        }
        return CGPoint(x: size.width * (0.5 + 0.1 * jitter(beat)),
                       y: size.height * (0.42 + 0.06 * jitter(beat + 7919)))
    }

    /// The drops as the shader takes them: x, y, start (seconds since `epoch`), strength.
    static func shaderValues(_ drops: [Drop], epoch: Date) -> [Float] {
        drops.suffix(maxDrops).flatMap { drop in
            [Float(drop.center.x), Float(drop.center.y),
             Float(drop.start.timeIntervalSince(epoch)), Float(drop.strength)]
        }
    }
}

/// Runs the cover under the ripples while `isRunning`, each frame asking `drops` which
/// rings are out at that moment, given the moment and the cover's size. `still` draws
/// that one moment instead and stops there, for screenshots.
struct LiquidRippleEffect: ViewModifier {
    let isRunning: Bool
    let epoch: Date
    var still: Date?
    let drops: (Date, CGSize) -> [LiquidRipple.Drop]

    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !isRunning || still != nil)) { context in
            let date = still ?? context.date
            let values = isRunning || still != nil
                ? LiquidRipple.shaderValues(drops(date, size), epoch: epoch) : []
            content.visualEffect { content, proxy in
                content.layerEffect(
                    ShaderLibrary.liquidRipple(.float2(proxy.size),
                                               .float(date.timeIntervalSince(epoch)),
                                               .floatArray(values)),
                    maxSampleOffset: CGSize(width: 8, height: 8),
                    isEnabled: !values.isEmpty)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
    }
}
