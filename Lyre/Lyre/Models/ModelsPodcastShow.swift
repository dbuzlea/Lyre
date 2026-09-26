//
//  ModelsPodcastShow.swift
//  Lyre
//
//  Created by Daniel Buzlea on 5/17/26.
//

import MediaPlayer
import Foundation

/// `nonisolated` so LibraryScanner can build shows off the main thread.
nonisolated struct PodcastShow: Identifiable, Hashable, Equatable {
    let title: String
    let episodes: [MPMediaItem]

    var id: String { title }

    var artwork: MPMediaItemArtwork? { episodes.first?.artwork }

    func hash(into hasher: inout Hasher) {
        hasher.combine(title)
    }

    static func == (lhs: PodcastShow, rhs: PodcastShow) -> Bool {
        lhs.title == rhs.title
    }
}
