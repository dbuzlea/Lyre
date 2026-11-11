//
//  LiquidTrackSpread.swift
//  Lyre
//

import SwiftUI

// MARK: - A Bubble's Songs, Spread Around It
//
// An iPhone Duo open, an album's or a playlist's bubble held: its songs burst out around
// it as little bubbles, numbered, with one for the whole album's page first. The finger
// that held it slides to one and lets go to play the album from that song; or carries
// one on across the fold to play it in Now Playing. Lifted over none, they stay out to
// be tapped or carried; a tap anywhere else puts them away.
//
// Here, where the little bubbles go (kept apart from the drawing, so it can be tested);
// the drawing and the touches are LiquidPlayerView's.

enum TrackSpreadLayout {
    /// How wide a song's little bubble is.
    static let bubble: CGFloat = 48
    /// The space between two of them.
    static let gap: CGFloat = 12

    /// Where `count` little bubbles go around a held bubble `diameter` wide at `center`:
    /// packed close as a honeycomb around it, clear of it and wholly inside `bounds`, the
    /// nearest first and, as far out as each other, going round from the top, clockwise; so
    /// the numbers spiral out from the bubble, filling whatever room the page has on each
    /// side. Fewer than `count` if the page holds no more.
    static func slots(count: Int, around center: CGPoint, diameter: CGFloat, within bounds: CGRect) -> [CGPoint] {
        guard count > 0 else { return [] }
        let inset = bounds.insetBy(dx: bubble / 2 + 6, dy: bubble / 2 + 6)
        let step = bubble + gap
        let rise = step * sqrt(3) / 2
        let clear = diameter / 2 + bubble / 2 + gap
        var places: [(point: CGPoint, band: Int, angle: Double)] = []
        let reach = 10
        for row in -reach...reach {
            let shift = row.isMultiple(of: 2) ? 0 : step / 2
            for column in -reach...reach {
                let point = CGPoint(x: center.x + CGFloat(column) * step + shift, y: center.y + CGFloat(row) * rise)
                let dx = point.x - center.x, dy = point.y - center.y
                let distance = hypot(dx, dy)
                guard distance >= clear, inset.contains(point) else { continue }
                // Clockwise from straight up.
                var angle = atan2(Double(dx), Double(-dy))
                if angle < 0 { angle += 2 * .pi }
                places.append((point, Int(((distance - clear) / step).rounded(.down)), angle))
            }
        }
        places.sort { $0.band != $1.band ? $0.band < $1.band : $0.angle < $1.angle }
        return places.prefix(count).map(\.point)
    }

    /// The place nearest `point`, if it's on (or near enough) one of them.
    static func slot(at point: CGPoint, in slots: [CGPoint]) -> Int? {
        let reach = bubble * 0.75
        var nearest: (index: Int, distance: CGFloat)?
        for (index, slot) in slots.enumerated() {
            let distance = hypot(slot.x - point.x, slot.y - point.y)
            if distance <= reach, distance < (nearest?.distance ?? .infinity) { nearest = (index, distance) }
        }
        return nearest?.index
    }
}

/// A held bubble's songs, spread around it.
struct TrackSpread {
    let album: AppAlbum
    /// The held bubble, on screen.
    let center: CGPoint
    let diameter: CGFloat
    /// Its songs, once they've come.
    var tracks: [AppTrack] = []
    /// Where the little bubbles are, on screen: the album's page first, then the songs.
    var slots: [CGPoint] = []
    /// The one under the finger.
    var highlighted: Int?
    /// The one carried on toward Now Playing, and where.
    var carried: Int?
    var carriedAt: CGPoint = .zero
    /// The finger that held the bubble is still down.
    var isHeld = true
    /// Out (for their burst out of the held bubble, and back into it).
    var isOut = false

    /// The first slot is the album's page.
    static let pageSlot = 0

    func track(atSlot slot: Int) -> (index: Int, track: AppTrack)? {
        let index = slot - 1
        guard tracks.indices.contains(index) else { return nil }
        return (index, tracks[index])
    }
}
