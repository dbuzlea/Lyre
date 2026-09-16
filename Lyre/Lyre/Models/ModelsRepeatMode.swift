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
}
