//
//  GrooveMap.swift
//  Lyre
//

import CoreGraphics
import Foundation

// MARK: - Groove Map
//
// Where each song sits on a record. The songs are cut one after another from the outer
// edge inward, each a band of grooves as wide as the song is long, with a smooth gap
// between bands — the way an LP's tracks can be seen across its face. So a place on the
// record is a song and a time in it, and back again:
//
//   fraction 0 is the outer edge of the playing surface, 1 the innermost groove
//
// The needle follows the fraction as the record plays, and dropping the needle at a
// fraction plays that song from that time.

struct GrooveMap: Equatable {
    /// Each song's length. A song whose length isn't known counts as three minutes.
    let durations: [TimeInterval]

    static let unknownLength: TimeInterval = 180

    init(durations: [TimeInterval]) {
        self.durations = durations.map { $0 > 0 ? $0 : Self.unknownLength }
    }

    var total: TimeInterval { durations.reduce(0, +) }

    /// Where each song starts, as a fraction.
    var bandStarts: [Double] {
        guard total > 0 else { return [] }
        var elapsed: TimeInterval = 0
        return durations.map { duration in
            defer { elapsed += duration }
            return elapsed / total
        }
    }

    /// The fraction `time` seconds into song `index`.
    func fraction(track index: Int, time: TimeInterval) -> Double {
        guard total > 0, durations.indices.contains(index) else { return 0 }
        let before = durations[..<index].reduce(0, +)
        let within = min(max(time, 0), durations[index])
        return (before + within) / total
    }

    /// The song and the time in it at `fraction`.
    func position(at fraction: Double) -> (index: Int, time: TimeInterval) {
        guard total > 0, !durations.isEmpty else { return (0, 0) }
        var remaining = min(max(fraction, 0), 1) * total
        for (index, duration) in durations.enumerated() {
            if remaining < duration || index == durations.count - 1 {
                return (index, min(remaining, duration))
            }
            remaining -= duration
        }
        return (durations.count - 1, 0)
    }
}

// MARK: - Tonearm Geometry

/// The tonearm swinging on its pivot over the record. The arm is a fixed length, so the
/// needle traces an arc; for any distance from the record's centre there's one angle
/// that puts the needle there, found by the law of cosines. Angles are in radians, from
/// the +x axis, clockwise on screen.
struct TonearmGeometry: Equatable {
    let pivot: CGPoint
    let center: CGPoint
    let armLength: CGFloat
    /// The playing surface: the outermost and innermost grooves.
    let outerRadius: CGFloat
    let innerRadius: CGFloat

    /// The record laid out at `center` with radius `radius`, and the arm's pivot behind
    /// it to the upper right, long enough to reach the innermost groove.
    init(center: CGPoint, radius: CGFloat) {
        self.center = center
        pivot = CGPoint(x: center.x + radius * 0.98, y: center.y - radius * 0.82)
        armLength = radius * 1.18
        outerRadius = radius * 0.94
        innerRadius = radius * 0.36
    }

    private var pivotDistance: CGFloat { hypot(center.x - pivot.x, center.y - pivot.y) }
    private var towardCenter: Double { atan2(Double(center.y - pivot.y), Double(center.x - pivot.x)) }

    /// The arm's angle with the needle `radius` from the centre.
    func angle(forRadius radius: CGFloat) -> Double {
        let d = Double(pivotDistance), l = Double(armLength), r = Double(radius)
        let cosine = min(1, max(-1, (d * d + l * l - r * r) / (2 * d * l)))
        // Swung out to the right of the line to the centre, as an arm sweeps a record.
        return towardCenter - acos(cosine)
    }

    func needle(at angle: Double) -> CGPoint {
        CGPoint(x: pivot.x + armLength * CGFloat(cos(angle)), y: pivot.y + armLength * CGFloat(sin(angle)))
    }

    func radius(at angle: Double) -> CGFloat {
        let point = needle(at: angle)
        return hypot(point.x - center.x, point.y - center.y)
    }

    /// The arm on its rest, clear of the record.
    var restAngle: Double { angle(forRadius: outerRadius) - 0.42 }
    /// The arm at the innermost groove, as far in as it goes.
    var innerAngle: Double { angle(forRadius: innerRadius) }

    /// The arm's angle for a fraction across the playing surface.
    func angle(forFraction fraction: Double) -> Double {
        angle(forRadius: outerRadius - (outerRadius - innerRadius) * CGFloat(min(max(fraction, 0), 1)))
    }

    /// The fraction under the needle at `angle`, or nil when the needle is off the
    /// record — out past the edge, toward the rest.
    func fraction(at angle: Double) -> Double? {
        let radius = radius(at: angle)
        guard radius <= outerRadius + 4 else { return nil }
        return Double(min(1, max(0, (outerRadius - radius) / (outerRadius - innerRadius))))
    }

    /// Where a finger at `point` would put the arm: aimed at the finger, kept between
    /// its rest and the innermost groove.
    func angle(toward point: CGPoint) -> Double {
        var raw = atan2(Double(point.y - pivot.y), Double(point.x - pivot.x))
        // Measured around the middle of the arm's swing, so a finger up past the
        // spindle (where atan2 wraps round to negative) reads as further in, not out.
        let middle = (restAngle + innerAngle) / 2
        while raw < middle - .pi { raw += 2 * .pi }
        while raw > middle + .pi { raw -= 2 * .pi }
        return min(max(raw, restAngle), innerAngle)
    }
}
