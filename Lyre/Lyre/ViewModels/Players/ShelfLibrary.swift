//
//  ShelfLibrary.swift
//  Lyre
//

import Foundation

// MARK: - Shelf Library
//
// The library as the Spool and the Gramophone show it: albums, playlists and podcasts as
// things on a shelf (tapes in the Spool's rack, records in the Gramophone's crate), each
// filed by name, and how each kind loads and plays.
//
// Kept apart from either player so both handle a mixtape or a podcast the same way:
//
//   • an album's songs come each once; a playlist's as the playlist has them; a show's
//     episodes newest first (see `AppAlbum.init(podcast:)`)
//   • a playlist plays tagged with its ID, so "is this what's playing" can tell
//   • a show's episodes play through the podcast players, newest first
//
// `-SpoolSampleTapes YES` at launch (debug builds) fills an empty library with
// placeholders on every shelf, so the players can be seen and UI-tested on a simulator
// with no music. Their songs have nothing behind them, so they list but won't play.

@MainActor
struct ShelfLibrary {
    let musicService: MusicService

    private var usesSamples: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "SpoolSampleTapes")
        #else
        return false
        #endif
    }

    /// The albums.
    var albums: [AppAlbum] {
        #if DEBUG
        if musicService.albums.isEmpty, usesSamples {
            // Mostly albums, with a single and an EP to show the cassingle. The tracks
            // have nothing behind them, so they list on the J-card but won't play.
            return (1...12).map { index in
                let (title, songs) = switch index {
                case 3:  ("Sample Single \(index) - Single", 1)
                case 5:  ("Sample EP \(index) - EP", 4)
                default: ("Sample Tape \(index)", 8 + index % 5)
                }
                let tracks = (1...songs).map { number in
                    AppTrack(id: "sample-\(index)-\(number)", title: "Sample Song \(number)",
                             artistName: "Lyre", albumTitle: title, duration: 150 + Double(number * 17))
                }
                return AppAlbum(id: "sample-\(index)", title: title, artistName: "Lyre",
                                preloadedTracks: tracks)
            }
        }
        #endif
        return musicService.albums
    }

    /// The playlists, as mixtapes, filed by name like the albums.
    var mixtapes: [AppAlbum] {
        #if DEBUG
        // With sample tapes on, an empty library gets a few sample mixtapes too: songs
        // from different albums, one taped twice, long enough to need a side B.
        if musicService.playlists.isEmpty, usesSamples {
            return [("Road Trip", "Sam", 14), ("Late Night", nil, 9), ("Summer '89", "Alex", 22)]
                .enumerated().map { index, sample in
                    let (name, curator, songs) = sample
                    var tracks = (1...songs).map { number in
                        AppTrack(id: "sample-mix-\(index)-\(number)", title: "Mix Song \(number)",
                                 artistName: "Artist \(number % 5 + 1)", albumTitle: "Album \(number % 6 + 1)",
                                 duration: 180 + Double(number * 23 % 90))
                    }
                    tracks.append(tracks[0])
                    let playlist = AppPlaylist(id: "sample-mix-\(index)", name: name, curatorName: curator,
                                               preloadedTracks: tracks)
                    return AppAlbum(mixtape: playlist)
                }
                .sorted { AppHelpers.sortsBefore($0.title, $1.title) }
        }
        #endif
        return musicService.playlists
            .map(AppAlbum.init(mixtape:))
            .sorted { AppHelpers.sortsBefore($0.title, $1.title) }
    }

    /// The podcasts, as spoken-word tapes or broadcast discs, filed by name.
    var podcasts: [AppAlbum] {
        #if DEBUG
        // Sample shows for the simulator, which has none. Their episodes point nowhere,
        // so they list but won't play.
        if musicService.podcastShows.isEmpty, usesSamples {
            return ["The Daily Spin", "Cassette Culture"].enumerated().map { index, title in
                let feedURL = URL(string: "https://example.invalid/feed-\(index).xml")!
                let episodes = (1...12).map { number in
                    FeedEpisode(guid: "sample-\(index)-\(number)", title: "Episode \(13 - number): Sample Episode",
                                audioURL: URL(string: "https://example.invalid/\(index)-\(number).mp3")!,
                                published: Date(timeIntervalSinceNow: -Double(number) * 7 * 86_400),
                                duration: 1_800 + Double(number * 97), artworkURL: nil)
                }
                return AppAlbum(podcast: PodcastShow(feed: FeedShow(
                    feedURL: feedURL, title: title, author: nil, artworkURL: nil,
                    episodes: episodes, lastRefreshed: .now)))
            }
            .sorted { AppHelpers.sortsBefore($0.title, $1.title) }
        }
        #endif
        return musicService.podcastShows
            .map(AppAlbum.init(podcast:))
            .sorted { AppHelpers.sortsBefore($0.title, $1.title) }
    }

    /// Every song, for a shuffle of them all; the sample albums' songs when samples
    /// stand in for an empty library.
    var songs: [AppTrack] {
        if musicService.songs.isEmpty, usesSamples { return albums.flatMap(\.preloadedTracks) }
        return musicService.songs
    }

    func items(on shelf: SpoolShelf) -> [AppAlbum] {
        switch shelf {
        case .albums:   return albums
        case .mixtapes: return mixtapes
        case .podcasts: return podcasts
        }
    }

    static func emptyText(on shelf: SpoolShelf) -> String {
        switch shelf {
        case .albums:   return String(localized: "spool.shelf.empty")
        case .mixtapes: return String(localized: "spool.shelf.mixtapes.empty")
        case .podcasts: return String(localized: "spool.shelf.podcasts.empty")
        }
    }

    // MARK: Playing

    /// An item's songs as they go on it: an album's each once (see `withoutDuplicates`),
    /// a playlist's as the playlist has them, a show's episodes newest first.
    func tracks(for album: AppAlbum) async -> [AppTrack] {
        if let playlist = album.mixtape {
            return await musicService.loadTracks(for: playlist)
        }
        // A podcast's episodes are already on its show.
        if album.isPodcast { return album.preloadedTracks }
        return await musicService.loadTracks(for: album)
    }

    /// Plays `tracks` of `album` from `index`.
    func play(_ album: AppAlbum, tracks: [AppTrack], startingAt index: Int) async -> PlaybackStartOutcome {
        if let show = album.podcast {
            // Episodes play through the podcast players, newest first as the shelf lists them.
            let episodes = show.episodesNewestFirst
            guard episodes.indices.contains(index) else { return .nothingPlayable }
            await musicService.playPodcastEpisodes(episodes, startingAt: index, podcastShowTitle: show.title)
            return .started
        }
        return await musicService.play(tracks: tracks, startingAt: index, playlistID: album.mixtape?.id)
    }

    /// Whether `track`, playing now, came off `album`: a mixtape by the playlist that's
    /// playing, a show by its title, an album by the song's album.
    func isPlaying(_ track: AppTrack, from album: AppAlbum) -> Bool {
        if let playlist = album.mixtape { return musicService.currentPlaylistID == playlist.id }
        if let show = album.podcast { return musicService.currentPodcastShowTitle == show.title }
        return TapeFormat.displayTitle(track.albumTitle) == album.tapeTitle
    }

    /// Whether what's playing came off `album`.
    func isPlaying(from album: AppAlbum) -> Bool {
        if let track = musicService.currentTrack { return isPlaying(track, from: album) }
        if let show = album.podcast, musicService.currentEpisode != nil {
            return musicService.currentPodcastShowTitle == show.title
        }
        return false
    }
}
