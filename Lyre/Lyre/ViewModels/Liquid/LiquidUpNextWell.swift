//
//  LiquidUpNextWell.swift
//  Lyre
//

import SwiftUI

// MARK: - Up Next, as Somewhere to Drop a Song
//
// A held bubble's songs spread out (TrackSpread) can be carried across the fold: let go
// on Now Playing, the song plays; let go on the Up Next bulge at its foot, it joins Up
// Next. The bulge answers as the fold's water does: it rises and leans toward a song
// carried near it, swells under it, and gulps it down when it's let go, the cover
// rippling from there.
//
// Now Playing's handle says where the bulge is; the spread says how near a song is, and
// when one's dropped in.

@Observable
@MainActor
final class LiquidUpNextWell {
    static let shared = LiquidUpNextWell()

    /// The Up Next handle on screen (global); zero while it isn't showing.
    var frame: CGRect = .zero
    /// How near a carried song is: 0 out of reach, 1 over the bulge.
    var pull: CGFloat = 0
    /// Which way the bulge leans, toward the song: -1 left … 1 right.
    var lean: CGFloat = 0
    /// Bumped each time a song is dropped in, for the bulge's gulp.
    var gulps = 0

    /// How far from the bulge a carried song starts to draw it.
    static let reach: CGFloat = 150
    /// How far round the handle a song still counts as over it.
    static let catchMargin: CGFloat = 28

    /// A song carried to `point`: the bulge drawn toward it.
    func follow(_ point: CGPoint) {
        let (pull, lean) = Self.draw(toward: point, frame: frame)
        guard pull != self.pull || lean != self.lean else { return }
        self.pull = pull
        self.lean = lean
    }

    /// The song gone from near it: the bulge settles.
    func release() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) {
            pull = 0
            lean = 0
        }
    }

    /// Whether a song let go at `point` falls into Up Next.
    func catches(_ point: CGPoint) -> Bool { Self.catches(point, frame: frame) }

    /// A song dropped in: the gulp.
    func swallow() {
        gulps += 1
        release()
    }

    nonisolated static func catches(_ point: CGPoint, frame: CGRect) -> Bool {
        frame.width > 0 && frame.insetBy(dx: -catchMargin, dy: -catchMargin).contains(point)
    }

    /// How strongly a song at `point` draws the bulge (0…1), and which way it leans.
    nonisolated static func draw(toward point: CGPoint, frame: CGRect) -> (pull: CGFloat, lean: CGFloat) {
        guard frame.width > 0 else { return (0, 0) }
        if catches(point, frame: frame) {
            return (1, max(-1, min(1, (point.x - frame.midX) / (frame.width / 2))))
        }
        let caught = frame.insetBy(dx: -catchMargin, dy: -catchMargin)
        let dx = max(caught.minX - point.x, 0, point.x - caught.maxX)
        let dy = max(caught.minY - point.y, 0, point.y - caught.maxY)
        let distance = hypot(dx, dy)
        guard distance < reach else { return (0, 0) }
        let near = 1 - distance / reach
        // Eased: a little from afar, then quickly as it comes close, as surface tension.
        let pull = near * near * 0.85
        let lean = max(-1, min(1, (point.x - frame.midX) / max(1, frame.width / 2)))
        return (pull, lean * near)
    }
}
