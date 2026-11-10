//
//  LiquidPlace.swift
//  Lyre
//

import SwiftUI

// MARK: - Where a List Was Left
//
// Each of Liquid's lists remembers the cover (or song, or artist) it was left on: the
// stack of covers (LiquidCardStack) opens on it again. The grid, the songs and the
// artists keep it too, as they scroll, so that switching to another player picks up
// there (LYRE-41, BrowseHandOver); and switching to Liquid from another player opens that
// section's list on the cover handed over, scrolled to it in the grid, on top of the stack.

@MainActor
enum LiquidPlace {
    /// Where list `list` was left, stored: the stack's own memory.
    static func key(_ list: String) -> String { "LiquidStackPlace." + list }

    /// The section a list is, for the players that file by section; nil for the lists
    /// they haven't (Recently Played, an artist's albums).
    static func shelf(forList list: String) -> SpoolShelf? {
        switch list {
        case "albums":    .albums
        case "playlists": .mixtapes
        case "podcasts":  .podcasts
        case "songs":     .songs
        case "artists":   .artists
        case "discover":  .discover
        default:          nil
        }
    }

    /// The list, and the page, for a section handed over from another player.
    static func list(for shelf: SpoolShelf) -> (list: String, route: LiquidRoute) {
        switch shelf {
        case .albums:   ("albums", .albums)
        case .mixtapes: ("playlists", .playlists)
        case .podcasts: ("podcasts", .podcasts)
        case .songs:    ("songs", .songs)
        case .artists:  ("artists", .artists)
        case .discover: ("discover", .discover)
        }
    }

    /// The other players' name for an artist (ArtistShelf): Liquid knows them by name.
    static func artistShelfID(_ name: String) -> String {
        "artist:" + name.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// The name of the artist another player handed over by its shelf ID, among `names`.
    static func artistName(forShelfID id: String, in names: [String]) -> String? {
        guard id.hasPrefix("artist:") else { return nil }
        let key = String(id.dropFirst("artist:".count))
        return names.first { $0.trimmingCharacters(in: .whitespaces).lowercased() == key }
    }

    /// List `list` is now at `id`: kept, and handed on to the next player switched to.
    static func save(_ id: String, list: String) {
        guard !list.isEmpty else { return }
        UserDefaults.standard.set(id, forKey: key(list))
        note(list: list, id: id)
    }

    /// List `list` is open, at wherever it was left: the section handed on.
    static func opened(list: String) {
        note(list: list, id: UserDefaults.standard.string(forKey: key(list)))
    }

    private static func note(list: String, id: String?) {
        guard let shelf = shelf(forList: list) else { return }
        let itemID = shelf == .artists ? id.map(artistShelfID) : id
        BrowseHandOver.shared.note(BrowsePosition(shelf: shelf, itemID: itemID))
    }

    // MARK: Handed Over

    /// A cover to scroll a list to as it opens, handed over from another player: taken
    /// once, by the list it's for.
    private static var scrollTarget: (list: String, id: String)?

    /// Opens list `list` on `id`, handed over from another player: the stack on top of
    /// it, the grid scrolled to it.
    static func handOver(_ id: String, list: String) {
        // The artists list keeps names, and is handed the other players' artist ID: it
        // finds the name itself as it opens.
        if list != "artists" { UserDefaults.standard.set(id, forKey: key(list)) }
        scrollTarget = (list, id)
    }

    /// The cover list `list` is to scroll to as it opens, once.
    static func takeScrollTarget(list: String) -> String? {
        guard let target = scrollTarget, target.list == list else { return nil }
        scrollTarget = nil
        return target.id
    }
}

/// Which row of a list is at the top, from the rows appearing and leaving as it scrolls;
/// kept where changing it redraws nothing.
final class LiquidTopRow {
    private var visible = Set<Int>()
    private(set) var top: Int?

    /// Row `index` came into view or left it; true if the top row changed.
    func update(_ index: Int, isVisible: Bool) -> Bool {
        if isVisible { visible.insert(index) } else { visible.remove(index) }
        let newTop = visible.min()
        guard newTop != top else { return false }
        top = newTop
        return newTop != nil
    }
}
