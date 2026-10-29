//
//  SmartList.swift
//  Lyre
//

import Foundation

// MARK: - Smart Lists
//
// The lists Liquid has beside the library, made for every player: what was played
// lately, what was added lately, what's played most, and Apple Music's top songs. Each is
// a playlist Lyre makes itself (`album`), so the Spool, Disc and Gramophone file them at
// the front of their Mixtapes shelf, and the classic player opens them from its menu,
// as any playlist opens. MusicService keeps them (`smartLists`), built in the background.

nonisolated enum SmartList: String, CaseIterable {
    case recentlyPlayed
    case recentlyAdded
    case mostPlayed
    case topCharts

    var id: String { "smart:\(rawValue)" }

    init?(id: String) {
        guard id.hasPrefix("smart:"), let list = SmartList(rawValue: String(id.dropFirst(6))) else { return nil }
        self = list
    }

    var title: String {
        switch self {
        case .recentlyPlayed: String(localized: "menu.recentlyPlayed")
        case .recentlyAdded:  String(localized: "menu.recentlyAdded")
        case .mostPlayed:     String(localized: "liquid.menu.mostPlayed")
        case .topCharts:      String(localized: "catalog.charts.songs")
        }
    }

    /// Who made it, as a mixtape's card says.
    var maker: String {
        self == .topCharts ? String(localized: "catalog.search.title") : String(localized: "smart.maker")
    }

    /// The list as a playlist, so it plays, queues and shows as any playlist does.
    func album(_ tracks: [AppTrack]) -> AppAlbum {
        AppAlbum(mixtape: AppPlaylist(id: id, name: title, curatorName: maker, preloadedTracks: tracks))
    }
}
