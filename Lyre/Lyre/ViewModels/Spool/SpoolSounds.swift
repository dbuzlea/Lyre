//
//  SpoolSounds.swift
//  Lyre
//

import AudioToolbox
import Foundation

// MARK: - Spool Sounds
//
// The mechanism's noises: a key going down, a held key let go, a tape ejected and
// inserted, the door shutting, and the whir of rewinding. They are cut from recordings
// in Scripts/SpoolSoundSources by Scripts/prepare_spool_sounds.sh into Sounds/.
//
// They play as system sounds, like the scroll wheel's click: those mix over whatever is
// playing without touching the app's audio session, so a sound effect can never pause
// the music or a podcast. Like the click, they follow the Click Sound setting and the
// ringer switch.

enum SpoolSound: String, CaseIterable {
    /// One of the four transport keys going down.
    case buttonPress = "spool_button_press"
    /// A key that was held, let go.
    case buttonRelease = "spool_button_release"
    /// The door opening and the tape in it coming out.
    case cassetteEject = "spool_cassette_eject"
    case cassetteInsert = "spool_cassette_insert"
    case doorClose = "spool_door_close"
    /// Pieces of the rewind whir, retriggered in turn while a wind key is held (see
    /// `nextRewind`).
    case rewind1 = "spool_rewind_1"
    case rewind2 = "spool_rewind_2"
    case rewind3 = "spool_rewind_3"

    /// The pieces of the whir, in the order they're played.
    static let rewind: [SpoolSound] = [.rewind1, .rewind2, .rewind3]

    /// How often a new piece of the whir starts: a little less than a piece lasts, so
    /// each fades in under the end of the one before.
    static let rewindInterval: Duration = .milliseconds(600)

    /// The piece of the whir that follows `count` pieces already played.
    static func nextRewind(after count: Int) -> SpoolSound {
        rewind[count % rewind.count]
    }

    @MainActor func play() {
        MechanicalSoundBank.play(rawValue)
    }
}

/// Plays the players' mechanical sounds (the Spool's and the Gramophone's) as system
/// sounds, registering each once, on first use, for the life of the app. They follow
/// the same switch as the wheel's click, on unless turned off, and the ringer switch.
enum MechanicalSoundBank {
    @MainActor private static var ids: [String: SystemSoundID] = [:]

    @MainActor static func play(_ name: String) {
        guard UserDefaults.standard.object(forKey: "LyreClickSoundEnabled") as? Bool ?? true,
              let id = id(for: name) else { return }
        AudioServicesPlaySystemSound(id)
    }

    /// Cuts a sound off if it's playing. A system sound can only be stopped by disposing
    /// of it; it's registered again the next time it plays.
    @MainActor static func stop(_ name: String) {
        guard let id = ids.removeValue(forKey: name) else { return }
        AudioServicesDisposeSystemSoundID(id)
    }

    @MainActor private static func id(for name: String) -> SystemSoundID? {
        if let id = ids[name] { return id }
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return nil }
        var id: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(url as CFURL, &id) == kAudioServicesNoError else { return nil }
        ids[name] = id
        return id
    }
}
