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
// MusicService owns all music data and playback state for the app. It reads the library
// from two sources and uses MPMusicPlayerController for playback of everything:
//
//   • MusicKit (MusicLibraryRequest) — richer metadata and catalogue artwork, but only
//     returns content for users with an active Apple Music subscription.
//   • MediaPlayer (MPMediaQuery)     — the on-device library: synced, purchased and
//     downloaded music plus podcasts. Always available once the user grants
//     "Media & Apple Music" access, subscription or not.
//
// Every load builds both snapshots and merges them per collection, preferring MusicKit
// when it returned something. That means a subscriber sees exactly what they saw before,
// and a non-subscriber sees their local music and podcasts instead of an empty app.
//
// Authorization
//   MusicKit and MediaPlayer each have their own authorization gate behind the same
//   system prompt. `requestAuthorization()` drives both — requesting only MusicKit
//   leaves MPMediaQuery returning nothing for the rest of the process lifetime, which
//   is why the library used to come up empty until the app was force-quit and relaunched.
//
// Library loading
//   `loadLibrary()` runs up to 3 attempts with exponential backoff delays [0, 2, 5]s.
//   The error is only surfaced to `lastError` after all retries are exhausted, so a
//   transient network blip never shows an error dialog. A load that succeeds but comes
//   back completely empty is also retried once, because the media library service can
//   briefly report nothing immediately after access is first granted.
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

// MARK: - Subscription State

// Whether the user can play Apple Music catalogue content. `.unknown` means the check
// has not completed yet (or failed); the UI treats it as "don't claim either way".
enum MusicSubscriptionState: Equatable {
    case unknown
    case subscribed
    case notSubscribed

    var isSubscribed: Bool { self == .subscribed }
}

// MARK: - Library Source

// Which source actually produced the library the user is looking at.
enum MusicLibrarySource: Equatable {
    case none
    case appleMusic
    case localMedia
    case mixed
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
    /// True once a load has finished, whatever it found. Lets the UI distinguish
    /// "no music" from "haven't looked yet".
    @Published var hasLoadedLibrary = false
    @Published var subscriptionState: MusicSubscriptionState = .unknown
    @Published var librarySource: MusicLibrarySource = .none
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
    private var libraryChangeObserver: NSObjectProtocol?
    private var playbackTimeUpdateTimer: Timer?

    private static let maxRetryAttempts = 3
    private static let retryDelays: [TimeInterval] = [0, 2, 5]

    /// Snapshot of the media library's modification date at the time of the last
    /// successful load, so foreground refreshes can skip redundant work.
    private var lastLibraryModifiedDate: Date?
    private var subscriptionObserverTask: Task<Void, Never>?
    private var subscriptionRetryTask: Task<Void, Never>?
    /// Backoff for re-checking the subscription after `itunescloudd` was unreachable.
    private static let subscriptionRetryDelays: [TimeInterval] = [1, 3, 8]
    /// The in-flight load, if any. Scanning a large library is expensive and several
    /// triggers can fire at once at launch, so concurrent callers share one load.
    @MainActor private var loadTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        Task {
            await checkCurrentStatus()
            setupNotifications()
            startPlaybackTimeUpdates()
        }
        observeSubscriptionUpdates()
    }

    // MARK: - Authorization

    /// True when either authorization gate is open. MediaPlayer access alone is enough
    /// to show the user their on-device music and podcasts.
    static var hasAnyLibraryAccess: Bool {
        MusicAuthorization.currentStatus == .authorized
            || MPMediaLibrary.authorizationStatus() == .authorized
    }

    /// `MusicSubscription` only reports a meaningful value once MusicKit itself is
    /// authorized. Before that, `canPlayCatalogContent` is false for *every* app,
    /// subscriber or not — reading it early makes a paying subscriber look unsubscribed.
    private static var canQuerySubscription: Bool {
        MusicAuthorization.currentStatus == .authorized
    }

    private func checkCurrentStatus() async {
        let granted = Self.hasAnyLibraryAccess
        await MainActor.run { isAuthorized = granted }
        guard granted else { return }
        await refreshSubscriptionState()
        await loadLibrary()
    }

    func requestAuthorization() async {
        // Both frameworks gate on the same system prompt but track authorization
        // separately. MusicKit is requested first (it presents the prompt); the
        // MediaPlayer request then resolves immediately from the same decision.
        // Skipping the MediaPlayer request leaves every MPMediaQuery in this process
        // returning nothing until the app is relaunched.
        let musicKitStatus = await MusicAuthorization.request()
        let mediaLibraryStatus = await Self.requestMediaLibraryAuthorization()

        let granted = (musicKitStatus == .authorized) || (mediaLibraryStatus == .authorized)
        logger.notice("Authorization — MusicKit: \(String(describing: musicKitStatus)), MediaPlayer: \(mediaLibraryStatus.rawValue)")

        await MainActor.run { isAuthorized = granted }
        guard granted else { return }

        await refreshSubscriptionState()
        await loadLibrary()
    }

    private static func requestMediaLibraryAuthorization() async -> MPMediaLibraryAuthorizationStatus {
        let current = MPMediaLibrary.authorizationStatus()
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            MPMediaLibrary.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    // MARK: - Subscription

    /// Resolves the subscription state with a single fast attempt so the library load is
    /// never blocked waiting on `itunescloudd`.
    ///
    /// A thrown error is NOT evidence of "no subscription" — `MusicSubscription.current`
    /// fails whenever the iTunes cloud daemon is unreachable, which happens routinely in
    /// the first seconds after launch (ICError -7010). Treating that as `.notSubscribed`
    /// showed subscribers the on-device-only onboarding and filtered their cloud library
    /// out. On failure the state stays `.unknown`, which callers read as "assume catalogue
    /// playback is available", and a background retry settles it.
    func refreshSubscriptionState() async {
        guard Self.canQuerySubscription else {
            logger.notice("Subscription check skipped — MusicKit not authorized yet")
            await MainActor.run { self.subscriptionState = .unknown }
            return
        }
        // The caller loads the library immediately after, so never reload from here.
        if await attemptSubscriptionCheck(reloadIfNeeded: false) { return }
        await MainActor.run { self.subscriptionState = .unknown }
        retrySubscriptionStateInBackground()
    }

    /// Stores a newly resolved state and reports whether the change can actually alter
    /// what a load produces.
    ///
    /// Only `.notSubscribed` changes behaviour — it filters out undownloaded cloud items.
    /// `.unknown` and `.subscribed` both load everything, so settling between those two
    /// yields an identical library and must not trigger a reload: rescanning thousands of
    /// songs and republishing them stalls the interface for no visible change.
    @discardableResult
    private func setSubscriptionState(_ state: MusicSubscriptionState) async -> Bool {
        let previous = await MainActor.run { () -> MusicSubscriptionState in
            let previous = subscriptionState
            subscriptionState = state
            return previous
        }
        guard previous != state else { return false }
        logger.notice("Apple Music subscription: \(String(describing: previous)) → \(String(describing: state))")
        return previous == .notSubscribed || state == .notSubscribed
    }

    /// Returns true when the state was determined.
    private func attemptSubscriptionCheck(reloadIfNeeded: Bool) async -> Bool {
        do {
            let subscription = try await MusicSubscription.current
            let affectsContents = await setSubscriptionState(
                subscription.canPlayCatalogContent ? .subscribed : .notSubscribed
            )
            if reloadIfNeeded { await reloadForSubscriptionChange(affectsContents: affectsContents) }
            return true
        } catch {
            logger.notice("Subscription check failed (state stays unknown): \(error.localizedDescription)")
            return false
        }
    }

    private func reloadForSubscriptionChange(affectsContents: Bool) async {
        let isEmpty = await MainActor.run { isLibraryEmpty }
        guard affectsContents || isEmpty else { return }
        await loadLibrary()
    }

    private func retrySubscriptionStateInBackground() {
        guard subscriptionRetryTask == nil else { return }
        subscriptionRetryTask = Task { [weak self] () -> Void in
            defer { self?.subscriptionRetryTask = nil }
            for delay in Self.subscriptionRetryDelays {
                try? await Task.sleep(for: .seconds(delay))
                guard let self, !Task.isCancelled else { return }
                if await self.attemptSubscriptionCheck(reloadIfNeeded: true) { return }
            }
            logger.error("Subscription state still undetermined after retries — treating catalogue playback as available")
        }
    }

    private func observeSubscriptionUpdates() {
        subscriptionObserverTask = Task { [weak self] in
            for await subscription in MusicSubscription.subscriptionUpdates {
                guard let self else { return }
                // This stream starts emitting at launch, before onboarding has requested
                // access. Those early values always report no catalogue playback, so
                // acting on them latches a subscriber into the non-subscriber flow.
                guard Self.canQuerySubscription else {
                    logger.notice("Ignoring pre-authorization subscription update")
                    continue
                }
                let affectsContents = await self.setSubscriptionState(
                    subscription.canPlayCatalogContent ? .subscribed : .notSubscribed
                )
                await self.reloadForSubscriptionChange(affectsContents: affectsContents)
            }
        }
    }

    // MARK: - Refresh Triggers

    /// Loads the library if nothing has been loaded yet. Called when the main interface
    /// appears so finishing onboarding always lands on a populated library.
    func ensureLibraryLoaded() async {
        // An empty result counts as "not loaded". A load that ran while the media
        // daemons were still starting reports success with nothing in it, and gating
        // only on `hasLoadedLibrary` would leave the user staring at empty menus until
        // they force-quit the app.
        let shouldLoad = await MainActor.run {
            isAuthorized && !isLoading && (!hasLoadedLibrary || isLibraryEmpty)
        }
        guard shouldLoad else { return }
        logger.notice("ensureLibraryLoaded — triggering load")
        await loadLibrary()
    }

    /// Re-reads authorization on foreground and reloads only when something could have
    /// changed — access was newly granted, the library is empty, or the on-device
    /// library was modified since the last load.
    func refreshOnForeground() async {
        let granted = Self.hasAnyLibraryAccess
        let wasAuthorized = await MainActor.run { () -> Bool in
            let previous = isAuthorized
            isAuthorized = granted
            return previous
        }
        guard granted else { return }

        if !wasAuthorized { await refreshSubscriptionState() }

        let modifiedDate = MPMediaLibrary.default().lastModifiedDate
        let needsReload = await MainActor.run {
            !isLoading && (!hasLoadedLibrary || isLibraryEmpty || modifiedDate != lastLibraryModifiedDate)
        }
        guard needsReload else { return }

        await loadLibrary()
    }

    /// Reacts to the media library becoming available after a load came up empty.
    ///
    /// Deliberately does nothing once the library is populated: this notification also
    /// fires for routine playback bookkeeping, and rescanning a large library on every
    /// play count update would be wasteful. Those changes are picked up on foreground.
    private func handleMediaLibraryChanged() async {
        let granted = Self.hasAnyLibraryAccess
        await MainActor.run { isAuthorized = granted }
        guard granted else { return }

        let needsLoad = await MainActor.run { !isLoading && isLibraryEmpty }
        guard needsLoad else { return }

        logger.notice("Media library became available — reloading empty library")
        await loadLibrary()
    }

    @MainActor
    private var isLibraryEmpty: Bool {
        songs.isEmpty && albums.isEmpty && artists.isEmpty
            && playlists.isEmpty && podcastShows.isEmpty
    }

    // MARK: - Load Library

    func loadLibrary() async {
        let task = await MainActor.run { () -> Task<Void, Never> in
            if let inFlight = loadTask { return inFlight }
            let task = Task { [weak self] () -> Void in
                await self?.loadLibraryAttempt(attempt: 0)
            }
            loadTask = task
            return task
        }
        await task.value
        await MainActor.run { if loadTask == task { loadTask = nil } }
    }

    private func loadLibraryAttempt(attempt: Int) async {
        // Every query below returns nothing without access. Bailing out keeps an
        // unauthorized load from publishing an empty library and marking it as loaded,
        // which would suppress the real load later.
        guard Self.hasAnyLibraryAccess else {
            logger.notice("Skipping library load — media access not granted yet")
            await MainActor.run { isLoading = false }
            return
        }

        if attempt == 0 {
            await MainActor.run { isLoading = true; lastError = nil }
        } else {
            let delay = Self.retryDelays[min(attempt, Self.retryDelays.count - 1)]
            logger.info("Library load retry \(attempt)/\(Self.maxRetryAttempts - 1), waiting \(delay)s")
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
        }

        // The on-device library is the baseline. It needs no network, no subscription,
        // and it is the only source of podcasts.
        var local = loadLocalSongs()
        let podcastShowsFound = loadPodcastShows()

        // MusicKit is layered on top when it has anything to offer. A throw here is not
        // fatal as long as the local snapshot found something.
        var musicKit: LibrarySnapshot?
        var musicKitError: Error?
        do {
            musicKit = try await loadMusicKitSnapshot(localItemIndex: local.mpItemIndex)
        } catch {
            musicKitError = error
        }

        // Grouping the on-device library into albums, artists and playlists is the
        // expensive part, so it only runs for the collections MusicKit did not supply.
        if musicKit?.albums.isEmpty ?? true || musicKit?.artists.isEmpty ?? true || musicKit?.playlists.isEmpty ?? true {
            local.addLocalCollections(
                needsAlbums:    musicKit?.albums.isEmpty ?? true,
                needsArtists:   musicKit?.artists.isEmpty ?? true,
                needsPlaylists: musicKit?.playlists.isEmpty ?? true,
                isPlayable:     localItemFilter
            )
        }

        let merged = LibrarySnapshot.merging(preferred: musicKit, fallback: local)
        let source = LibrarySnapshot.source(preferred: musicKit, merged: merged)

        // -1 for a MusicKit count means the request threw rather than returned empty.
        logger.notice("""
            Load attempt \(attempt + 1)/\(Self.maxRetryAttempts) — \
            local: \(local.songs.count) songs/\(local.albums.count) albums/\(local.playlists.count) playlists, \
            musicKit: \(musicKit?.songs.count ?? -1) songs/\(musicKit?.albums.count ?? -1) albums/\(musicKit?.playlists.count ?? -1) playlists, \
            podcasts: \(podcastShowsFound.count)\(musicKitError.map { " — musicKit error: \($0.localizedDescription)" } ?? "")
            """)

        // Nothing anywhere: decide between retrying and reporting.
        if merged.isEmpty && podcastShowsFound.isEmpty {
            if let musicKitError {
                let loadError = MusicLoadError.from(musicKitError)
                logger.error("Library load attempt \(attempt + 1)/\(Self.maxRetryAttempts) failed [\(loadError.alertTitle)]: \(musicKitError)")

                if loadError.isRetryable && attempt + 1 < Self.maxRetryAttempts {
                    await loadLibraryAttempt(attempt: attempt + 1)
                    return
                }
                await MainActor.run {
                    self.isLoading = false
                    self.hasLoadedLibrary = true
                    self.lastError = loadError
                }
                return
            }

            // No error, just nothing returned. Immediately after access is first granted
            // the media daemons can report an empty library for several seconds, which is
            // what made the app look broken until it was force-quit. Use the full retry
            // budget before believing the library is really empty.
            if attempt + 1 < Self.maxRetryAttempts {
                logger.notice("Library empty with no error (attempt \(attempt + 1)/\(Self.maxRetryAttempts)) — retrying")
                await loadLibraryAttempt(attempt: attempt + 1)
                return
            }
            logger.notice("Library still empty after \(Self.maxRetryAttempts) attempts — no music or podcasts found")
        } else if let musicKitError {
            // Partial success: local content is available, so this is not user-facing.
            logger.info("MusicKit library unavailable, using on-device library: \(musicKitError.localizedDescription)")
        }

        let modifiedDate = MPMediaLibrary.default().lastModifiedDate

        await MainActor.run {
            self.songs          = merged.songs
            self.albums         = merged.albums
            self.artists        = merged.artists
            self.playlists      = merged.playlists
            self.recentlyAdded  = merged.recentlyAdded
            self.recentlyPlayed = merged.recentlyPlayed
            self.podcastShows   = podcastShowsFound
            self.librarySource  = source
            self.isLoading      = false
            self.hasLoadedLibrary = true
            self.lastError      = nil
            self.lastLibraryModifiedDate = modifiedDate
            logger.notice("Loaded \(self.songs.count) songs, \(self.albums.count) albums, \(self.artists.count) artists, \(self.playlists.count) playlists, \(self.podcastShows.count) podcasts from \(String(describing: source)) [subscription: \(String(describing: self.subscriptionState))]")
        }
    }

    // MARK: - Library Snapshots

    // An immutable view of one source's contribution to the library. Built off the main
    // actor and merged before a single publish, so the UI never sees a half-populated
    // library.
    private struct LibrarySnapshot {
        var songs:          [AppTrack]    = []
        var albums:         [AppAlbum]    = []
        var artists:        [AppArtist]   = []
        var playlists:      [AppPlaylist] = []
        var recentlyAdded:  [AppTrack]    = []
        var recentlyPlayed: [AppTrack]    = []
        /// Local MPMediaItems keyed by normalised title + artist, used to attach a
        /// playback handle to MusicKit-sourced tracks.
        var mpItemIndex: [String: MPMediaItem] = [:]

        var isEmpty: Bool {
            songs.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty
        }

        /// Prefers the MusicKit snapshot per collection, falling back to local content
        /// for anything MusicKit did not return.
        static func merging(preferred: LibrarySnapshot?, fallback: LibrarySnapshot) -> LibrarySnapshot {
            guard let preferred else { return fallback }
            var merged = LibrarySnapshot()
            merged.songs          = preferred.songs.isEmpty          ? fallback.songs          : preferred.songs
            merged.albums         = preferred.albums.isEmpty         ? fallback.albums         : preferred.albums
            merged.artists        = preferred.artists.isEmpty        ? fallback.artists        : preferred.artists
            merged.playlists      = preferred.playlists.isEmpty      ? fallback.playlists      : preferred.playlists
            merged.recentlyAdded  = preferred.recentlyAdded.isEmpty  ? fallback.recentlyAdded  : preferred.recentlyAdded
            merged.recentlyPlayed = preferred.recentlyPlayed.isEmpty ? fallback.recentlyPlayed : preferred.recentlyPlayed
            return merged
        }

        static func source(
            preferred: LibrarySnapshot?,
            merged: LibrarySnapshot
        ) -> MusicLibrarySource {
            if merged.isEmpty { return .none }
            guard let preferred, !preferred.isEmpty else { return .localMedia }
            // Mixed only when a collection actually fell through to the local snapshot.
            let usedFallback =
                (preferred.songs.isEmpty     && !merged.songs.isEmpty)     ||
                (preferred.albums.isEmpty    && !merged.albums.isEmpty)    ||
                (preferred.artists.isEmpty   && !merged.artists.isEmpty)   ||
                (preferred.playlists.isEmpty && !merged.playlists.isEmpty)
            return usedFallback ? .mixed : .appleMusic
        }

        /// Groups the on-device library into albums, artists and playlists. Only the
        /// collections MusicKit failed to supply are built, since this is the expensive
        /// part of a local load.
        mutating func addLocalCollections(
            needsAlbums: Bool,
            needsArtists: Bool,
            needsPlaylists: Bool,
            isPlayable: (MPMediaItem) -> Bool
        ) {
            if needsAlbums {
                albums = (MPMediaQuery.albums().collections ?? [])
                    .compactMap { collection -> AppAlbum? in
                        let items = collection.items.filter(isPlayable)
                        guard let representative = items.first else { return nil }
                        return AppAlbum(from: representative, tracks: items.map { AppTrack(from: $0) })
                    }
                    .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            }

            if needsArtists {
                artists = (MPMediaQuery.artists().collections ?? [])
                    .compactMap { collection -> AppArtist? in
                        let items = collection.items.filter(isPlayable)
                        guard let representative = items.first else { return nil }
                        // Group the artist's tracks into albums so ArtistDetailView has
                        // content without needing an (impossible) MusicKit round trip.
                        let albums = Dictionary(grouping: items, by: { $0.albumPersistentID })
                            .compactMap { _, albumItems -> AppAlbum? in
                                guard let albumRepresentative = albumItems.first else { return nil }
                                return AppAlbum(
                                    from: albumRepresentative,
                                    tracks: albumItems.map { AppTrack(from: $0) }
                                )
                            }
                            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                        return AppArtist(from: representative, albums: albums)
                    }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }

            if needsPlaylists {
                playlists = (MPMediaQuery.playlists().collections ?? [])
                    .compactMap { collection -> AppPlaylist? in
                        guard let playlist = collection as? MPMediaPlaylist else { return nil }
                        let items = playlist.items.filter(isPlayable)
                        guard !items.isEmpty else { return nil }
                        return AppPlaylist(from: playlist, tracks: items.map { AppTrack(from: $0) })
                    }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        }
    }

    /// Normalised key for matching a MusicKit song to its on-device counterpart.
    private static func matchKey(title: String, artist: String) -> String {
        "\(title.lowercased())\u{1}\(artist.lowercased())"
    }

    // MARK: - On-Device Library (MPMediaQuery)

    /// Without a subscription, cloud items that were never downloaded cannot play.
    /// Hiding them keeps every row in the interface actually playable.
    private var localItemFilter: (MPMediaItem) -> Bool {
        let playableOnly = !subscriptionStateAllowsCatalogPlayback
        return { item in
            guard playableOnly else { return true }
            return !item.isCloudItem || item.assetURL != nil
        }
    }

    /// Songs, recents and the playback index. Cheap enough to run on every load, and
    /// the index is what lets playback skip a per-track MPMediaQuery later.
    private func loadLocalSongs() -> LibrarySnapshot {
        var snapshot = LibrarySnapshot()
        let isPlayable = localItemFilter

        let songItems = (MPMediaQuery.songs().items ?? []).filter(isPlayable)
        guard !songItems.isEmpty else { return snapshot }

        snapshot.songs = songItems
            .sorted { ($0.title ?? "").localizedCaseInsensitiveCompare($1.title ?? "") == .orderedAscending }
            .map { AppTrack(from: $0) }

        snapshot.mpItemIndex = Dictionary(
            songItems.map { (Self.matchKey(title: $0.title ?? "", artist: $0.artist ?? ""), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        snapshot.recentlyAdded = songItems
            .sorted { $0.dateAdded > $1.dateAdded }
            .prefix(25)
            .map { AppTrack(from: $0) }

        snapshot.recentlyPlayed = songItems
            .filter { $0.lastPlayedDate != nil }
            .sorted { ($0.lastPlayedDate ?? .distantPast) > ($1.lastPlayedDate ?? .distantPast) }
            .prefix(25)
            .map { AppTrack(from: $0) }

        return snapshot
    }

    private func loadPodcastShows() -> [PodcastShow] {
        let items = MPMediaQuery.podcasts().items ?? []
        let grouped = Dictionary(grouping: items) {
            $0.podcastTitle ?? $0.albumTitle ?? "Unknown Podcast"
        }
        return grouped
            .map { title, episodes in
                PodcastShow(title: title, episodes: episodes.sorted { $0.dateAdded > $1.dateAdded })
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Reads `subscriptionState` without hopping to the main actor. `.unknown` is treated
    /// as "might be able to stream", so we don't hide cloud items before the check lands.
    private var subscriptionStateAllowsCatalogPlayback: Bool {
        subscriptionState != .notSubscribed
    }

    // MARK: - Apple Music Library (MusicKit)

    private func loadMusicKitSnapshot(localItemIndex: [String: MPMediaItem]) async throws -> LibrarySnapshot {
        var snapshot = LibrarySnapshot()

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

        // Attaching the local MPMediaItem up front means playback never has to run a
        // title query later, which was both slow and prone to matching the wrong item.
        func attachLocal(_ track: AppTrack) -> AppTrack {
            track.attaching(mpItem: localItemIndex[Self.matchKey(title: track.title, artist: track.artistName)])
        }

        snapshot.songs     = songResp.items.map { attachLocal(AppTrack(from: $0)) }
        snapshot.albums    = albumResp.items.map { AppAlbum(from: $0) }
        snapshot.artists   = artistResp.items.map { AppArtist(from: $0) }
        snapshot.playlists = playlistResp.items.map { AppPlaylist(from: $0) }

        // Recency lives in the on-device library, so order by MPMediaItem dates and use
        // the matching MusicKit song for its catalogue artwork where one exists.
        let songsByKey = Dictionary(
            snapshot.songs.map { (Self.matchKey(title: $0.title, artist: $0.artistName), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        func upgrade(_ item: MPMediaItem) -> AppTrack {
            songsByKey[Self.matchKey(title: item.title ?? "", artist: item.artist ?? "")]
                ?? AppTrack(from: item)
        }

        let localItems = Array(localItemIndex.values)
        snapshot.recentlyAdded = localItems
            .sorted { $0.dateAdded > $1.dateAdded }
            .prefix(25)
            .map(upgrade)

        snapshot.recentlyPlayed = localItems
            .filter { $0.lastPlayedDate != nil }
            .sorted { ($0.lastPlayedDate ?? .distantPast) > ($1.lastPlayedDate ?? .distantPast) }
            .prefix(25)
            .map(upgrade)

        return snapshot
    }

    // MARK: - Track/Album/Artist Loading

    // Locally-sourced items carry their children in `preloadedTracks` / `preloadedAlbums`
    // because there is no MusicKit object to expand. They are also the fallback when a
    // MusicKit expansion fails or comes back empty.

    func loadTracks(for album: AppAlbum) async -> [AppTrack] {
        guard let mkAlbum = album.musicKitAlbum else { return album.preloadedTracks }
        do {
            let detailed = try await mkAlbum.with([.tracks])
            let tracks = (detailed.tracks ?? []).map { AppTrack(from: $0) }
            return tracks.isEmpty ? album.preloadedTracks : tracks
        } catch {
            logger.error("Failed to load tracks for album '\(album.title)': \(error)")
            return album.preloadedTracks
        }
    }

    func loadTracks(for playlist: AppPlaylist) async -> [AppTrack] {
        guard let mkPlaylist = playlist.musicKitPlaylist else { return playlist.preloadedTracks }
        do {
            let detailed = try await mkPlaylist.with([.tracks])
            let tracks = (detailed.tracks ?? []).map { AppTrack(from: $0) }
            return tracks.isEmpty ? playlist.preloadedTracks : tracks
        } catch {
            logger.error("Failed to load tracks for playlist '\(playlist.name)': \(error)")
            return playlist.preloadedTracks
        }
    }

    func loadAlbums(for artist: AppArtist) async -> [AppAlbum] {
        guard let mkArtist = artist.musicKitArtist else { return artist.preloadedAlbums }
        do {
            let detailed = try await mkArtist.with([.albums])
            let albums = (detailed.albums ?? []).map { AppAlbum(from: $0) }
            return albums.isEmpty ? artist.preloadedAlbums : albums
        } catch {
            logger.error("Failed to load albums for artist '\(artist.name)': \(error)")
            return artist.preloadedAlbums
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
        let shows = loadPodcastShows()
        await MainActor.run { self.podcastShows = shows }
    }

    // MARK: - MPMediaItem Lookup (by persistent ID for reliability)

    private func getMPMediaItem(for track: AppTrack) -> MPMediaItem? {
        // Locally-sourced tracks (and MusicKit tracks matched at load time) already
        // carry their item, which is both faster and exact.
        if let item = track.mpItem { return item }

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

        // The media library can finish becoming available after our first load attempt,
        // which is the usual reason a fresh install comes up empty. This is the signal
        // that it is ready.
        MPMediaLibrary.default().beginGeneratingLibraryChangeNotifications()
        libraryChangeObserver = NotificationCenter.default.addObserver(
            forName: .MPMediaLibraryDidChange,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.handleMediaLibraryChanged() }
        }

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
        if let track = songs.first(where: { $0.mpItem?.persistentID == nowPlaying.persistentID }) {
            currentTrack = track
        } else if let track = songs.first(where: {
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
        subscriptionObserverTask?.cancel()
        subscriptionRetryTask?.cancel()
        MPMediaLibrary.default().endGeneratingLibraryChangeNotifications()
        if let o = playbackStateObserver { NotificationCenter.default.removeObserver(o) }
        if let o = nowPlayingObserver    { NotificationCenter.default.removeObserver(o) }
        if let o = libraryChangeObserver { NotificationCenter.default.removeObserver(o) }
    }
}
