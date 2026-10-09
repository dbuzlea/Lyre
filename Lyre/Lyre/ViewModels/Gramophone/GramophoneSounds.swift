//
//  GramophoneSounds.swift
//  Lyre
//

import Foundation

// MARK: - Gramophone Sounds
//
// The machine's noises: the switch thrown, the drawer sliding open and shut, a record
// flipped over in the bin or the drawer, the needle landing and lifting, each tooth of
// the crank's ratchet and the spring wound tight, and, under the music, the record's
// surface noise and the turntable turning.
//
// Most are cut from recordings in Scripts/GramophoneSoundSources by
// Scripts/prepare_gramophone_sounds.sh. The needle lifting, the ratchet and the spring
// have no recording yet: they're placeholders made by Scripts/make_gramophone_sounds.py.
//
// Like the Spool's, they play as system sounds (see MechanicalSoundBank), which mix
// over the music without pausing it, and follow the Sound Effects setting.

enum GramophoneSound: String, CaseIterable {
    /// The play switch, and the brake and speed levers.
    case switchFlip = "gramophone_switch"
    case drawerOpen = "gramophone_drawer_open"
    case drawerClose = "gramophone_drawer_close"
    /// A record tipped over to the next, in the bin or the drawer's stack.
    case flip = "gramophone_flip"
    case needleDrop = "gramophone_needle_drop"
    case needleLift = "gramophone_needle_lift"
    /// One tooth of the crank's ratchet.
    case ratchet = "gramophone_ratchet"
    /// The spring wound a full turn.
    case wound = "gramophone_wound"
    /// Pieces of surface noise, played in turn under the music (see `nextCrackle`).
    case crackle1 = "gramophone_crackle_1"
    case crackle2 = "gramophone_crackle_2"
    case crackle3 = "gramophone_crackle_3"
    /// Pieces of the turntable's running, played in turn under the crackle.
    case running1 = "gramophone_running_1"
    case running2 = "gramophone_running_2"
    case running3 = "gramophone_running_3"

    static let crackle: [GramophoneSound] = [.crackle1, .crackle2, .crackle3]
    static let running: [GramophoneSound] = [.running1, .running2, .running3]

    /// How often a new piece of crackle and running starts: a little less than a piece
    /// lasts (4 s), so each fades in under the end of the one before.
    static let crackleInterval: Duration = .milliseconds(3750)

    static func nextCrackle(after count: Int) -> GramophoneSound {
        crackle[count % crackle.count]
    }

    static func nextRunning(after count: Int) -> GramophoneSound {
        running[count % running.count]
    }

    /// Silences the crackle and running at once: a piece lasts seconds, and shouldn't
    /// carry on after the record stops.
    @MainActor static func stopSurfaceNoise() {
        for sound in crackle + running { MechanicalSoundBank.stop(sound.rawValue) }
    }

    @MainActor func play() {
        MechanicalSoundBank.play(rawValue)
    }
}
