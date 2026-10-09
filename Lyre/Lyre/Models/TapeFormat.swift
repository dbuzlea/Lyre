//
//  TapeFormat.swift
//  Lyre
//

import Foundation
import MusicKit

// MARK: - Tape Format
//
// Which kind of tape the Spool draws for an album. A full album is a standard cassette;
// singles and EPs are cassingles — coloured shells with a short pack of tape and the
// format stamped on the label — so they stand out in the rack.
//
// Apple Music marks singles itself (`isSingle`), and both it and iTunes name singles and
// EPs "<Title> - Single" / "<Title> - EP", which is the only sign an EP or a local
// library item carries. Track count is deliberately not used: an album with one song in
// the library is a partly added album, not a single.
//
// A playlist goes in the rack as a mixtape: a blank tape in a white shell, its label and
// J-card written by hand, and the length of blank it would have been recorded on (C46 to
// C120) printed on it. Its songs are split over two sides, as they would have been taped.
//
// A podcast goes in as a spoken-word tape: a navy shell with the show's art on the label,
// "Spoken Word" printed where the side letter goes, and its episodes, newest first, as
// the tape's tracks.

nonisolated enum TapeFormat: Equatable {
    case album
    case single
    case ep
    /// A playlist, taped by hand.
    case mixtape
    /// A podcast.
    case spokenWord

    /// True for the cassingle formats.
    var isShort: Bool { self == .single || self == .ep }

    /// The word stamped on a cassingle's label, or nil for an album or a mixtape.
    var stamp: String? {
        switch self {
        case .album, .mixtape, .spokenWord: return nil
        case .single:          return String(localized: "spool.tape.single")
        case .ep:              return String(localized: "spool.tape.ep")
        }
    }

    /// The blank lengths a mixtape could be recorded on, in minutes for both sides.
    static let blankLengths = [46, 60, 90, 120]

    /// The shortest blank that holds `duration` of music: "C60", "C90". Nil when the
    /// length isn't known. Anything longer than the longest blank still goes on a C120.
    static func blank(for duration: TimeInterval) -> Int? {
        guard duration > 0 else { return nil }
        let minutes = duration / 60
        return blankLengths.first { Double($0) >= minutes } ?? blankLengths.last
    }

    /// "C90".
    static func blankName(_ minutes: Int) -> String { "C\(minutes)" }

    /// Where side B starts on a mixtape of `tracks`: the first song that wouldn't fit on
    /// side A, which holds half the blank. Nil when everything fits on one side, or the
    /// lengths aren't known.
    static func sideBreak(in tracks: [AppTrack]) -> Int? {
        let total = tracks.reduce(0) { $0 + $1.duration }
        guard tracks.count > 1, let blank = blank(for: total) else { return nil }
        let sideLength = Double(blank) * 60 / 2
        var elapsed: TimeInterval = 0
        for (index, track) in tracks.enumerated() {
            elapsed += track.duration
            if elapsed > sideLength { return index > 0 ? index : nil }
        }
        return nil
    }

    /// "1 song", "12 songs".
    static func songCount(_ count: Int) -> String {
        count == 1
            ? String(localized: "spool.tape.song")
            : String(format: String(localized: "spool.tape.songs"), count)
    }

    /// "1 episode", "42 episodes".
    static func episodeCount(_ count: Int) -> String {
        count == 1
            ? String(localized: "spool.tape.episode")
            : String(format: String(localized: "spool.tape.episodes"), count)
    }

    /// The count printed on a tape of this format.
    func count(_ count: Int) -> String {
        self == .spokenWord ? Self.episodeCount(count) : Self.songCount(count)
    }

    private static let suffixes: [(String, TapeFormat)] = [(" - Single", .single), (" - EP", .ep)]

    static func detect(title: String, isSingle: Bool?) -> TapeFormat {
        if let (_, format) = suffixes.first(where: { title.hasSuffixIgnoringCase($0.0) }) {
            return format
        }
        return isSingle == true ? .single : .album
    }

    /// The title without the store's " - Single" / " - EP" suffix; the shell and its
    /// stamp already say which it is.
    static func displayTitle(_ title: String) -> String {
        for (suffix, _) in suffixes where title.hasSuffixIgnoringCase(suffix) {
            return String(title.dropLast(suffix.count))
        }
        return title
    }
}

nonisolated extension AppAlbum {
    /// A playlist as a mixtape. Its id is kept apart from the albums' so the two racks
    /// never confuse one for the other.
    init(mixtape playlist: AppPlaylist) {
        self.init(id: "mixtape:\(playlist.id)", title: playlist.name,
                  artistName: playlist.curatorName ?? "",
                  mpArtwork: playlist.mpArtwork,
                  preloadedTracks: playlist.preloadedTracks,
                  mixtape: playlist)
    }

    /// A podcast as a spoken-word tape. Its tracks are the episodes, newest first, in the
    /// order `PodcastShow.episodesNewestFirst` gives them, so a track's place is its
    /// episode's place.
    init(podcast show: PodcastShow) {
        let episodes = show.episodesNewestFirst
        self.init(id: "podcast:\(show.id)", title: show.title, artistName: "",
                  releaseDate: episodes.first?.published,
                  preloadedTracks: episodes.map(\.asTrack),
                  podcast: show)
    }

    var isMixtape: Bool { mixtape != nil }
    var isPodcast: Bool { podcast != nil }

    var tapeFormat: TapeFormat {
        if isMixtape { return .mixtape }
        if isPodcast { return .spokenWord }
        return TapeFormat.detect(title: title, isSingle: musicKitAlbum?.isSingle)
    }

    /// A mixtape keeps its name as written; an album loses the store's suffix.
    var tapeTitle: String { isMixtape || isPodcast ? title : TapeFormat.displayTitle(title) }

    /// The tape's songs as they go on it. An album lists each song once; a mixtape keeps
    /// whatever was put on it, repeats included, since a song taped twice is meant.
    func tapeSongs(_ tracks: [AppTrack]) -> [AppTrack] {
        isMixtape || isPodcast ? tracks : tracks.withoutDuplicates
    }

    /// Songs on the tape, when known without loading it.
    var tapeTrackCount: Int? {
        if let count = musicKitAlbum?.trackCount, count > 0 { return count }
        let tracks = tapeSongs(preloadedTracks)
        return tracks.isEmpty ? nil : tracks.count
    }

    /// The blank a mixtape is on, when its songs are known: "C90".
    var tapeBlank: String? {
        guard isMixtape else { return nil }
        return TapeFormat.blank(for: preloadedTracks.reduce(0) { $0 + $1.duration })
            .map(TapeFormat.blankName)
    }

    /// An album or mixtape of several songs, which the rack keeps in its plastic case. A
    /// count not yet known counts as several: few albums in a library are one song. A
    /// podcast always comes in its case, to choose an episode from.
    var comesInCase: Bool {
        if isPodcast { return true }
        return (tapeFormat == .album || tapeFormat == .mixtape) && (tapeTrackCount ?? 2) > 1
    }

    /// "12 songs", the format for a cassingle, or "C90 · 23 songs" for a mixtape: the
    /// line under a tape's name.
    var tapeDetail: String? {
        if let stamp = tapeFormat.stamp { return stamp }
        let parts = [tapeBlank, tapeTrackCount.map(tapeFormat.count)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private extension String {
    nonisolated func hasSuffixIgnoringCase(_ suffix: String) -> Bool {
        range(of: suffix, options: [.caseInsensitive, .anchored, .backwards]) != nil
    }
}

nonisolated extension PodcastShow {
    /// The episodes, newest first; those with no date go last, in the order given.
    var episodesNewestFirst: [PodcastEpisode] {
        episodes.enumerated()
            .sorted { lhs, rhs in
                switch (lhs.element.published, rhs.element.published) {
                case let (l?, r?) where l != r: return l > r
                case (.some, nil):              return true
                case (nil, .some):              return false
                default:                        return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }
}
