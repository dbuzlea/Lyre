//
//  AlbumInfo.swift
//  Lyre
//

import Foundation
import MusicKit
import MediaPlayer

// MARK: - Album Info
//
// What's known about an album, for every player: when it came out, its genre, how many
// songs and how long, and from Apple Music (AppleMusicCatalog) the record label,
// copyright, Apple's write-up, the audio it comes in, whether it's a single or a
// compilation, other versions and albums like it.
//
// Each player shows the release date where it already lists an album (`releaseLine`).
// Holding an album anywhere offers Album Info, one sheet with all of it (AlbumInfoSheet):
// whatever asks sets `pending`, and the app's root shows the sheet. What the library
// knows is there at once; what Apple Music knows is asked for when the sheet opens.

@MainActor
@Observable
final class AlbumInfoCenter {
    static let shared = AlbumInfoCenter()

    /// The album whose info is waiting to be shown.
    var pending: AppAlbum?

    func show(_ album: AppAlbum) {
        guard album.hasAlbumInfo else { return }
        pending = album
    }
}

nonisolated extension AppAlbum {
    /// An album, as against a playlist shown as a mixtape or a podcast show.
    var hasAlbumInfo: Bool { !isMixtape && !isPodcast }

    /// When it came out, written out ("July 24, 2020"); nil for a playlist or a show.
    var releaseLine: String? {
        guard hasAlbumInfo, let releaseDate else { return nil }
        return Self.releaseText(releaseDate)
    }

    /// Release dates are calendar days kept as midnight UTC: read in UTC, or west of
    /// Greenwich they'd fall on the day before.
    static func releaseText(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .long, time: .omitted)
        style.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return date.formatted(style)
    }

    /// Its genre, from Apple Music's album or the songs' own tags.
    var genre: String? {
        if let name = AppleMusicCatalog.genres(musicKitAlbum?.genreNames ?? []).first { return name }
        return preloadedTracks.lazy.compactMap { $0.mpItem?.genre }.first { !$0.isEmpty }
    }
}

nonisolated enum AlbumInfoText {
    /// A running time as hours and minutes ("1 hr 3 min"), or minutes alone.
    static func length(_ seconds: TimeInterval) -> String? {
        guard seconds >= 60 else { return nil }
        let minutes = Int(seconds / 60)
        return Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

nonisolated extension AppTrack {
    /// Who wrote it, where that's known.
    var composer: String? {
        let name = musicKitSong?.composerName ?? mpItem?.composer
        return name.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Its disc and place on the album, where known.
    var discNumber: Int? { musicKitSong?.discNumber ?? mpItem.flatMap { $0.discNumber > 0 ? $0.discNumber : nil } }
    var trackNumber: Int? { musicKitSong?.trackNumber ?? mpItem.flatMap { $0.albumTrackNumber > 0 ? $0.albumTrackNumber : nil } }
}
