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
}
