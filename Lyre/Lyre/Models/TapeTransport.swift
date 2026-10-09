//
//  TapeTransport.swift
//  Lyre
//

import Foundation

// MARK: - Tape Transport
//
// The geometry of a cassette playing a song, as a pure function of the playback position.
//
// The song is the whole tape: at 0 s it is all wound on the supply (left) reel, at the end
// all on the take-up (right) reel. Tape area is conserved, so a reel holding fraction `x`
// of the tape has radius  r = √(h² + x·(R² − h²))  for hub radius h and full radius R.
//
// Tape runs past the head at a constant speed v, so a reel turns at v / r: the emptier
// reel spins faster, as on a real deck. Integrating that over the song gives each reel's
// angle in closed form (∫ dx / √(h² + xA) = 2√(h² + xA) / A), which means the angle is
// exact at any position — scrubbing or skipping winds the reels straight to where they
// belong, with no accumulated state to drift or jump.
//
// All lengths are in units of the full reel radius (R = 1).

nonisolated struct TapeTransport: Equatable {
    /// Hub radius as a fraction of a full reel.
    static let hubRadius: Double = 0.42
    /// Tape speed in reel radii per second. Puts a half-full reel at roughly one turn
    /// every two seconds: lively without blurring.
    static let tapeSpeed: Double = 2.4

    /// Fraction of the song played, 0…1.
    let progress: Double
    /// Radius of the tape pack on each reel, hubRadius…1.
    let supplyRadius: Double
    let takeUpRadius: Double
    /// Rotation of each reel's hub in radians. Both turn the same way, as on a real deck.
    let supplyAngle: Double
    let takeUpAngle: Double

    init(time: TimeInterval, duration: TimeInterval) {
        let h = Self.hubRadius
        let area = 1 - h * h
        let v = Self.tapeSpeed

        // With no known length (a live stream), leave the tape where it is and just turn
        // the reels at the speed their current packs imply.
        guard duration > 0 else {
            progress = 0
            supplyRadius = 1
            takeUpRadius = h
            supplyAngle = v * time
            takeUpAngle = v * time / h
            return
        }

        let x = min(max(time / duration, 0), 1)
        progress = x
        supplyRadius = (h * h + (1 - x) * area).squareRoot()
        takeUpRadius = (h * h + x * area).squareRoot()

        let tapeLength = v * duration
        takeUpAngle = 2 * tapeLength * takeUpRadius / area
        supplyAngle = 2 * tapeLength * (1 - supplyRadius) / area
    }
}
