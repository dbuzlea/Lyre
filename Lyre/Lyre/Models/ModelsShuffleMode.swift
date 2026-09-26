//
//  ShuffleMode.swift
//  Lyre
//
//  Created by Daniel Buzlea on 5/14/26.
//

import Foundation
import MediaPlayer

enum ShuffleMode: String, CaseIterable {
    case off = "Off"
    case songs = "Songs"
    
    var icon: String {
        return "shuffle"
    }
    
    var mpShuffleMode: MPMusicShuffleMode {
        switch self {
        case .off: return .off
        case .songs: return .songs
        }
    }

    /// Reads the player's own shuffle setting. The system player starts out carrying
    /// whatever the Music app was set to, so this is how the app finds out rather
    /// than assuming Off — an inherited shuffle is why a queued song can appear to
    /// be skipped in favour of a random one. `.albums` has no separate mode here and
    /// is reported as Songs; `.default` cannot be resolved and is reported as Off.
    init(mpShuffleMode: MPMusicShuffleMode) {
        switch mpShuffleMode {
        case .songs, .albums: self = .songs
        default:              self = .off
        }
    }
}
