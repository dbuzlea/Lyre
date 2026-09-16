//
//  MusicService.swift
//  Lyre
//

import Foundation
import MusicKit
import MediaPlayer
import OSLog
internal import Combine

private let logger = Logger(subsystem: "com.pinkhatcreations.lyreapp", category: "MusicService")

// MARK: - MusicService
//
// MusicService owns all music data and playback state for the app. It uses MusicKit
// for catalogue queries (songs, albums, artists, playlists) and MPMusicPlayerController
// for local file playback of podcasts sourced from MPMediaLibrary.
//
// Library loading
//   `loadLibrary()` runs up to 3 attempts with exponential backoff delays [0, 2, 5]s.
//   The error is only surfaced to `lastError` after all retries are exhausted, so a
//   transient network blip never shows an error dialog.
//
// Playback
//   `play(tracks:startingAt:)` queues tracks in MPMusicPlayerController and starts
//   playback. Track progress is polled every 0.5 s via a Timer; the Combine import
//   is kept internal so callers don't need to import Combine.
//
// Thread safety
//   All @Published properties are mutated on the main actor via `await MainActor.run`.
//   Async methods that call MusicKit or MPMusicPlayerController are safe to call from
//   any async context.

// MARK: - MusicLoadError

// Typed error for library load failures. Carries a user-facing alertTitle, a
// localised description with actionable guidance, and an isRetryable flag so the
// UI can decide whether to show a Retry button or an "Open Settings" deep-link.
// The `from(_:)` factory maps raw Error values (URLError codes and message patterns)
// into one of four buckets: notAuthorized / noNetwork / serverError / unknown.
enum MusicLoadError: LocalizedError, Equatable {
    case notAuthorized
    case noNetwork
    case serverError
    case unknown

    var alertTitle: String {
        switch self {
        case .notAuthorized: return "Permission Required"
        case .noNetwork:     return "No Internet Connection"
        case .serverError:   return "Service Unavailable"
        case .unknown:       return "Something Went Wrong"
        }
    }

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Apple Music access was revoked. Go to Settings → Privacy → Media & Apple Music to restore access."
        case .noNetwork:
            return "No internet connection. Connect to Wi-Fi or cellular and try again."
        case .serverError:
            return "Apple Music servers are temporarily unavailable. Please try again in a moment."
        case .unknown:
            return "Could not load your music library. Please try again."
        }
    }

    // Auth errors are not retryable — the user must fix them in Settings.
    var isRetryable: Bool {
        switch self {
        case .notAuthorized:          return false
        case .noNetwork, .serverError, .unknown: return true
        }
    }

    static func from(_ error: Error) -> MusicLoadError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost,
                 .timedOut, .cannotConnectToHost, .dnsLookupFailed:
                return .noNetwork
            default:
                return .serverError
            }
        }
        let desc = error.localizedDescription.lowercased()
        if desc.contains("not authorized") || desc.contains("authorization") || desc.contains("permission") {
            return .notAuthorized
        }
        if desc.contains("network") || desc.contains("internet") || desc.contains("offline") || desc.contains("connection") {
            return .noNetwork
        }
        if desc.contains("server") || desc.contains("service") || desc.contains("unavailable") {
            return .serverError
        }
        return .unknown
    }
}

// MARK: - MusicService

class MusicService: ObservableObject {
    // MARK: - Library

    @Published var songs:        [AppTrack]    = []
    @Published var albums:       [AppAlbum]    = []
    @Published var artists:      [AppArtist]   = []
    @Published var playlists:    [AppPlaylist] = []
    @Published var podcastShows: [PodcastShow] = []

    // MARK: - Playback State

    @Published var isAuthorized  = false
    @Published var isLoading     = false
    @Published var currentTrack: AppTrack?
    @Published var currentMediaItem: MPMediaItem?
    @Published var isPlaying     = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration:    TimeInterval = 0
    @Published var isScrubbing  = false

    // MARK: - Error State

    @Published var lastError: MusicLoadError?

    // MARK: - Lyre classic features

    @Published var repeatMode:            RepeatMode  = .off
    @Published var shuffleMode:           ShuffleMode = .off
    @Published var currentPlaylistID:     String?
    @Published var currentPodcastShowTitle: String?
    @Published var recentlyAdded:  [AppTrack] = []
    @Published var recentlyPlayed: [AppTrack] = []

    // MARK: - Private

    private let player = MPMusicPlayerController.systemMusicPlayer
    private var playbackStateObserver: NSObjectProtocol?
    private var nowPlayingObserver:    NSObjectProtocol?
    private var playbackTimeUpdateTimer: Timer?

    private static let maxRetryAttempts = 3
    private static let retryDelays: [TimeInterval] = [0, 2, 5]

    // MARK: - Init

    init() {
        Task {
            await checkCurrentStatus()
            setupNotifications()
            startPlaybackTimeUpdates()
        }
    }

    // MARK: - Authorization

    private func checkCurrentStatus() async {
        let status = MusicAuthorization.currentStatus
        await MainActor.run { isAuthorized = (status == .authorized) }
        if status == .authorized { await loadLibrary() }
    }

    func requestAuthorization() async {
        let status = await MusicAuthorization.request()
        await MainActor.run { isAuthorized = (status == .authorized) }
        if isAuthorized { await loadLibrary() }
    }

    // MARK: - Load Library

    func loadLibrary() async {
        await loadLibraryAttempt(attempt: 0)
    }

    private func loadLibraryAttempt(attempt: Int) async {
        if attempt == 0 {
            await MainActor.run { isLoading = true; lastError = nil }
        } else {
            let delay = Self.retryDelays[min(attempt, Self.retryDelays.count - 1)]
            logger.info("Library load retry \(attempt)/\(Self.maxRetryAttempts - 1), waiting \(delay)s")
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
        }

        do {
            var songReq = MusicLibraryRequest<Song>()
            songReq.limit = 25000
            let songResp = try await songReq.response()

            var albumReq = MusicLibraryRequest<Album>()
            albumReq.limit = 5000
            let albumResp = try await albumReq.response()

            var artistReq = MusicLibraryRequest<Artist>()
            artistReq.limit = 5000
            let artistResp = try await artistReq.response()

            var playlistReq = MusicLibraryRequest<Playlist>()
            playlistReq.limit = 2000
            let playlistResp = try await playlistReq.response()

            let podcastQuery = MPMediaQuery.podcasts()
            let podcastItems = podcastQuery.items ?? []
            let grouped = Dictionary(grouping: podcastItems) {
                $0.podcastTitle ?? $0.albumTitle ?? "Unknown Podcast"
            }
            let shows = grouped.map { title, episodes in
                PodcastShow(title: title, episodes: episodes.sorted { $0.dateAdded > $1.dateAdded })
            }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

            let mkSongs = Array(songResp.items)
            let allMPItems = MPMediaQuery.songs().items ?? []

            let recentAddedTracks: [AppTrack] = allMPItems
                .sorted { $0.dateAdded > $1.dateAdded }
                .prefix(25)
                .compactMap { item in
                    guard let title = item.title else { return nil }
                    let artist = item.artist ?? ""
                    return mkSongs.first(where: { $0.title == title && $0.artistName == artist })
                        .map { AppTrack(from: $0) }
                }

            let recentPlayedTracks: [AppTrack] = allMPItems
                .filter { $0.lastPlayedDate != nil }
                .sorted { ($0.lastPlayedDate ?? .distantPast) > ($1.lastPlayedDate ?? .distantPast) }
                .prefix(25)
                .compactMap { item in
                    guard let title = item.title else { return nil }
                    let artist = item.artist ?? ""
                    return mkSongs.first(where: { $0.title == title && $0.artistName == artist })
                        .map { AppTrack(from: $0) }
                }

            await MainActor.run {
                self.songs     = Array(songResp.items).map    { AppTrack(from: $0) }
                self.albums    = Array(albumResp.items).map   { AppAlbum(from: $0) }
                self.artists   = Array(artistResp.items).map  { AppArtist(from: $0) }
                self.playlists = Array(playlistResp.items).map { AppPlaylist(from: $0) }
                self.podcastShows = shows
                self.recentlyAdded  = recentAddedTracks
                self.recentlyPlayed = recentPlayedTracks
                self.isLoading = false
                self.lastError = nil
                logger.info("Loaded \(self.songs.count) songs, \(self.albums.count) albums, \(self.artists.count) artists")
            }
        } catch {
            let loadError = MusicLoadError.from(error)
            logger.error("Library load attempt \(attempt + 1)/\(Self.maxRetryAttempts) failed [\(loadError.alertTitle)]: \(error)")

            if loadError.isRetryable && attempt + 1 < Self.maxRetryAttempts {
                await loadLibraryAttempt(attempt: attempt + 1)
            } else {
                await MainActor.run {
                    self.isLoading = false
                    self.lastError = loadError
                }
            }
        }
    }

    // MARK: - Track/Album/Artist Loading

    func loadTracks(for album: AppAlbum) async -> [AppTrack] {
        guard let mkAlbum = album.musicKitAlbum else { return [] }
        do {
            let detailed = try await mkAlbum.with([.tracks])
            return (detailed.tracks ?? []).map { AppTrack(from: $0) }
        } catch {
            logger.error("Failed to load tracks for album '\(album.title)': \(error)")
            return []
        }
    }

    func loadTracks(for playlist: AppPlaylist) async -> [AppTrack] {
        guard let mkPlaylist = playlist.musicKitPlaylist else { return [] }
        do {
            let detailed = try await mkPlaylist.with([.tracks])
            return (detailed.tracks ?? []).map { AppTrack(from: $0) }
        } catch {
            logger.error("Failed to load tracks for playlist '\(playlist.name)': \(error)")
            return []
        }
    }

    func loadAlbums(for artist: AppArtist) async -> [AppAlbum] {
        guard let mkArtist = artist.musicKitArtist else { return [] }
        do {
            let detailed = try await mkArtist.with([.albums])
            return (detailed.albums ?? []).map { AppAlbum(from: $0) }
        } catch {
            logger.error("Failed to load albums for artist '\(artist.name)': \(error)")
            return []
        }
    }

    // MARK: - Playback

    func play(tracks: [AppTrack], startingAt index: Int = 0, playlistID: String? = nil) async {
        guard index < tracks.count else { return }
        logger.info("Starting playback: \(tracks.count) track(s), index \(index)")

        var mediaItems: [MPMediaItem] = []
        for track in tracks {
            if let item = getMPMediaItem(for: track) {
                mediaItems.append(item)
            }
        }
        guard !mediaItems.isEmpty else {
            logger.warning("No MPMediaItems resolved for playback queue")
            return
        }

        let startItem = index < mediaItems.count ? mediaItems[index] : mediaItems[0]
        await MainActor.run {
            player.setQueue(with: MPMediaItemCollection(items: mediaItems))
            player.nowPlayingItem = startItem
            player.play()
            currentTrack = tracks[min(index, tracks.count - 1)]
            isPlaying = true
            currentPlaylistID = playlistID
            currentPodcastShowTitle = nil
            logger.info("Now playing: \(tracks[min(index, tracks.count - 1)].title)")
        }
    }

    func play(track: AppTrack) async {
        await play(tracks: [track], startingAt: 0)
    }

    func playPodcastEpisodes(items: [MPMediaItem], startingAt index: Int = 0, podcastShowTitle: String? = nil) async {
        guard !items.isEmpty, index < items.count else { return }
        logger.info("Playing podcast '\(podcastShowTitle ?? "unknown")': \(items.count) episode(s) at index \(index)")
        let startItem = items[index]
        await MainActor.run {
            let collection  = MPMediaItemCollection(items: items)
            let descriptor  = MPMusicPlayerMediaItemQueueDescriptor(itemCollection: collection)
            descriptor.startItem = startItem
            player.setQueue(with: descriptor)
            player.prepareToPlay()
            player.play()
            isPlaying = true
            currentPlaylistID = nil
            currentPodcastShowTitle = podcastShowTitle
        }
    }

    // MARK: - Transport Controls

    func togglePlayPause() async {
        await MainActor.run {
            if isPlaying { player.pause(); isPlaying = false; logger.info("Playback paused") }
            else         { player.play();  isPlaying = true;  logger.info("Playback resumed") }
        }
    }

    func toggleRepeatMode() async {
        await MainActor.run {
            let modes: [RepeatMode] = [.off, .all, .one]
            if let i = modes.firstIndex(of: repeatMode) {
                repeatMode = modes[(i + 1) % modes.count]
                player.repeatMode = repeatMode.mpRepeatMode
                logger.info("Repeat mode: \(self.repeatMode.rawValue)")
            }
        }
    }

    func toggleShuffleMode() async {
        await MainActor.run {
            shuffleMode = shuffleMode == .off ? .songs : .off
            player.shuffleMode = shuffleMode.mpShuffleMode
            logger.info("Shuffle mode: \(self.shuffleMode.rawValue)")
        }
    }

    func skipToNext() async {
        logger.info("Skipping to next track")
        await MainActor.run { player.skipToNextItem() }
    }

    func skipToPrevious() async {
        logger.info("Skipping to previous track")
        await MainActor.run { player.skipToPreviousItem() }
    }

    func seek(to time: TimeInterval) async {
        await MainActor.run {
            player.currentPlaybackTime = time
            currentTime = time
        }
    }

    func startScrubbing() { isScrubbing = true  }
    func stopScrubbing()  { isScrubbing = false }

    // MARK: - Podcasts

    func refreshPodcasts() async {
        let query = MPMediaQuery.podcasts()
        let items = query.items ?? []
        let grouped = Dictionary(grouping: items) {
            $0.podcastTitle ?? $0.albumTitle ?? "Unknown Podcast"
        }
        let shows = grouped.map { title, episodes in
            PodcastShow(title: title, episodes: episodes.sorted { $0.dateAdded > $1.dateAdded })
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        await MainActor.run { self.podcastShows = shows }
    }

    // MARK: - MPMediaItem Lookup (by persistent ID for reliability)

    private func getMPMediaItem(for track: AppTrack) -> MPMediaItem? {
        let query = MPMediaQuery.songs()
        query.addFilterPredicate(
            MPMediaPropertyPredicate(value: track.title, forProperty: MPMediaItemPropertyTitle,
                                     comparisonType: .equalTo)
        )
        if let items = query.items, !items.isEmpty {
            return items.first(where: { $0.artist == track.artistName && $0.albumTitle == track.albumTitle })
                ?? items.first(where: { $0.artist == track.artistName })
                ?? items.first
        }
        return nil
    }

    // MARK: - Playback Notifications

    private func setupNotifications() {
        player.beginGeneratingPlaybackNotifications()

        playbackStateObserver = NotificationCenter.default.addObserver(
            forName: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: player, queue: .main
        ) { [weak self] _ in self?.updatePlaybackState() }

        nowPlayingObserver = NotificationCenter.default.addObserver(
            forName: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: player, queue: .main
        ) { [weak self] _ in self?.updateNowPlayingItem() }

        updatePlaybackState()
        updateNowPlayingItem()
    }

    private func updatePlaybackState() {
        isPlaying = (player.playbackState == .playing)
        updateNowPlayingInfoCenter()
    }

    private func updateNowPlayingItem() {
        currentMediaItem = player.nowPlayingItem
        guard let nowPlaying = player.nowPlayingItem else {
            currentTrack = nil; duration = 0
            updateNowPlayingInfoCenter()
            return
        }
        duration = nowPlaying.playbackDuration
        if let track = songs.first(where: {
            $0.title == nowPlaying.title && $0.artistName == nowPlaying.artist
        }) {
            currentTrack = track
        } else if let track = songs.first(where: { $0.title == nowPlaying.title }) {
            currentTrack = track
        } else {
            currentTrack = nil
        }
        updateNowPlayingInfoCenter()
    }

    // MARK: - Playback Time Updates

    private func startPlaybackTimeUpdates() {
        playbackTimeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, !self.isScrubbing else { return }
            let time = self.player.currentPlaybackTime
            DispatchQueue.main.async { self.currentTime = time }
        }
    }

    // MARK: - Now Playing Info Center (lockscreen / control center)

    private func updateNowPlayingInfoCenter() {
        var info: [String: Any] = [:]

        let title    = currentTrack?.title     ?? currentMediaItem?.title     ?? ""
        let artist   = currentTrack?.artistName ?? currentMediaItem?.artist    ?? ""
        let album    = currentTrack?.albumTitle ?? currentMediaItem?.albumTitle ?? ""
        let dur      = duration > 0 ? duration : (currentMediaItem?.playbackDuration ?? 0)

        info[MPMediaItemPropertyTitle]            = title
        info[MPMediaItemPropertyArtist]           = artist
        info[MPMediaItemPropertyAlbumTitle]       = album
        info[MPMediaItemPropertyPlaybackDuration] = dur
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        if let artwork = currentMediaItem?.artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    deinit {
        player.endGeneratingPlaybackNotifications()
        playbackTimeUpdateTimer?.invalidate()
        if let o = playbackStateObserver { NotificationCenter.default.removeObserver(o) }
        if let o = nowPlayingObserver    { NotificationCenter.default.removeObserver(o) }
    }
}
