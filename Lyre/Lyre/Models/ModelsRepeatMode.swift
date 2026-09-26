//
//  RepeatMode.swift
//  Lyre
//
//  Created by Daniel Buzlea on 5/14/26.
//

import Foundation
import MediaPlayer

enum RepeatMode: String, CaseIterable {
    case off = "Off"
    case one = "One"
    case all = "All"
    
    var icon: String {
        switch self {
        case .off: return "repeat"
        case .one: return "repeat.1"
        case .all: return "repeat"
        }
    }
    
    var mpRepeatMode: MPMusicRepeatMode {
        switch self {
        case .off: return .none
        case .one: return .one
        case .all: return .all
        }
    }

    /// Reads the player's own repeat setting. The system player starts out carrying
    /// whatever the Music app was set to, so this is how the app finds out rather
    /// than assuming Off. `.default` means "whatever the user prefers", which is not
    /// a value that can be resolved — it is reported as Off.
    init(mpRepeatMode: MPMusicRepeatMode) {
        switch mpRepeatMode {
        case .one:  self = .one
        case .all:  self = .all
        default:    self = .off
        }
    }
}
