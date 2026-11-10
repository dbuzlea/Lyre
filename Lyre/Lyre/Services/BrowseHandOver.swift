//
//  BrowseHandOver.swift
//  Lyre
//

import SwiftUI

// MARK: - Browse Hand-Over
//
// LYRE-41: switching players picks up where the last one was left, the section (Albums,
// Songs, Podcasts, Artists, Playlists, Apple Music) and the cover at its front, or on
// Songs the song the list was scrolled to. The Spool, the Disc, the Gramophone and Liquid
// tell it where they are as that changes; switching players hands that over, and the
// player switched to takes it up once, as it appears.
//
// Only a switch hands it over. Reopening the app, each player opens where it was left
// itself: nothing is kept here across launches.

/// Where browsing was: a section, and the cover (or song) at its front there.
struct BrowsePosition: Equatable {
    var shelf: SpoolShelf
    /// The album, playlist, show or artist at the front; on Songs, the song at the top.
    var itemID: String?
}

@MainActor
final class BrowseHandOver {
    static let shared = BrowseHandOver()

    /// Where the player in use is now.
    private(set) var current: BrowsePosition?
    /// What a switch handed over, until the player switched to takes it up.
    private var pending: BrowsePosition?

    init() {}

    /// The player in use tells where it is. Ignored while a switch waits to be taken
    /// up, so the new player's own last place doesn't overwrite the one handed to it.
    func note(_ position: BrowsePosition) {
        guard pending == nil else { return }
        current = position
    }

    /// The player was switched: the next one to appear picks up from here.
    func playerSwitched() {
        pending = current
    }

    /// What a switch handed over, once; nil if there's nothing to pick up.
    func take() -> BrowsePosition? {
        defer { pending = nil }
        return pending
    }
}

/// A player's part in the hand-over: on appearing, it takes up what a switch handed it
/// (`adopt`); after that, it tells where it is as that changes. `position` is nil while
/// there's nowhere to tell (a search's results, which go with the search).
struct HandsOverBrowsing: ViewModifier {
    let position: BrowsePosition?
    let adopt: (BrowsePosition) -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                if let handed = BrowseHandOver.shared.take() {
                    adopt(handed)
                } else if let position {
                    BrowseHandOver.shared.note(position)
                }
            }
            .onChange(of: position) { _, position in
                if let position { BrowseHandOver.shared.note(position) }
            }
    }
}
