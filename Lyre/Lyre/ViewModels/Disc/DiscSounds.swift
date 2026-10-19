//
//  DiscSounds.swift
//  Lyre
//

import Foundation

// MARK: - Disc Sounds
//
// The portable CD player's noises: a key going down, the lid's catch letting go and the
// lid snapping shut, a disc pressed onto the spindle, and the motor spinning it up. They
// are cut from recordings in Scripts/DiscSoundSources by Scripts/prepare_disc_sounds.sh
// into Sounds/. The keys use the Spool's key press, which has the right soft click.
//
// Like the Spool's and the Gramophone's, they play as system sounds (see
// MechanicalSoundBank), which mix over the music without pausing it, and follow the
// Sound Effects setting.

enum DiscSound: String, CaseIterable {
    /// A key going down: the Spool's press.
    case button = "spool_button_press"
    case lidOpen = "disc_lid_open"
    case lidClose = "disc_lid_close"
    /// A disc pressed down onto the spindle.
    case seat = "disc_seat"
    /// The motor bringing a new disc up to speed, before it plays.
    case spinUp = "disc_spin_up"

    @MainActor func play() {
        MechanicalSoundBank.play(rawValue)
    }
}
