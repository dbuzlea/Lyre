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
//   At launch the last loaded library is restored from LibraryCache first, so the menus
//   are populated immediately, and the full load then runs in the background and
//   replaces it. The scan itself lives in LibraryScanner and runs off the main thread.
//
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
//   Playback runs through `applicationQueuePlayer`, not the system player. The system
//   player drives the Music app on the app's behalf, which means it also inherits the
//   Music app's shuffle and repeat settings and lets the Music app's own queue (and its
//   autoplay) supersede ours — a song added to the queue would simply never play. The
//   application queue player owns its queue outright and is the only player that can
//   edit it in place, via `perform(queueTransaction:)`, so queueing never interrupts
//   what is playing. The trade-offs are that playback stops when the app is terminated
//   and does not continue the Music app's session, and that it needs the `audio`
//   background mode (set in Info.plist) to keep playing once the app is backgrounded.
//   Remote control events (lock screen, headphones, CarPlay) need no handling here:
//   MediaPlayer routes them to the player itself for application players.
//
//   Episodes of subscribed podcasts are the exception: they are remote URLs, which
//   the music player cannot play, so they stream through PodcastStreamPlayer instead.
//   See "Podcast Streaming" below for how the two engines take turns.
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

// Which source actually produced the library the user is looking at. `nonisolated` and
// Codable because LibraryScanner computes it off the main thread and LibraryCache
// stores it.
nonisolated enum MusicLibrarySource: String, Equatable, Codable {
    case none
    case appleMusic
    case localMedia
    case mixed
}

// MARK: - Playback Start Outcome

// Whether starting playback worked, so the UI can stay put and say something rather
// than navigating to Now Playing for a song that never started.
enum PlaybackStartOutcome: Equatable {
    case started
    /// The chosen track has no media item behind it — an undownloaded cloud item or
    /// Apple Music catalogue content, usually.
    case trackUnavailable
    /// Nothing in the list could be queued at all.
    case nothingPlayable
}

// MARK: - Queue Add Outcome

// What `addToQueue` actually did, so the UI can tell the user. The counts matter for
// collections: an album or playlist can be partly unplayable, and queueing 9 of 12
// tracks without saying so would look like the app lost three songs.
enum QueueAddOutcome: Equatable {
    /// Added to the bottom of the queue. `skipped` counts the tracks that had nothing
    /// playable behind them, plus any dropped for exceeding the per-add ceiling.
    case queued(count: Int, skipped: Int)
    /// Nothing was playing, so the tracks started playing instead of waiting their turn.
    case startedPlaying(count: Int, skipped: Int)
    /// Nothing in the request could be queued at all.
    case unavailable
    /// A podcast is playing. Up Next is then its episodes, so songs can't join it.
    case podcastPlaying

    /// True when some of what was asked for did not make it into the queue.
    var isPartial: Bool {
        switch self {
        case .queued(_, let skipped), .startedPlaying(_, let skipped): return skipped > 0
        case .unavailable, .podcastPlaying: return false
        }
    }

    /// True when anything went in, or started playing.
    var succeeded: Bool {
        switch self {
        case .queued, .startedPlaying: return true
        case .unavailable, .podcastPlaying: return false
        }
    }

    /// What to tell the user, in the same words in every player. `name` is the song or
    /// collection asked for, `requested` how many songs it held, and `isCollection`
    /// picks the wording when none of it could be queued.
    func message(name: String, requested: Int, placement: QueuePlacement, isCollection: Bool) -> String {
        switch self {
        case .queued(let count, _):
            switch (placement, isPartial) {
            case (.next, true):
                return String(format: String(localized: "queue.addedNextPartial"), count, requested, name)
            case (.next, false):
                return String(format: String(localized: "queue.addedNext"), name)
            case (.last, true):
                return String(format: String(localized: "queue.addedPartial"), count, requested, name)
            case (.last, false):
                return String(format: String(localized: "queue.added"), name)
            }
        case .startedPlaying(let count, _):
            return isPartial
                ? String(format: String(localized: "queue.addedPartial"), count, requested, name)
                : String(format: String(localized: "queue.playing"), name)
        case .unavailable:
            return String(localized: isCollection ? "queue.collectionUnavailable" : "queue.unavailable")
        case .podcastPlaying:
            return String(localized: "queue.podcastPlaying")
        }
    }
}

// MARK: - Queue Placement

/// Where added tracks go: straight after the current track, or at the bottom.
enum QueuePlacement {
    case next
    case last
}

// MARK: - Playback Notice

struct PlaybackNotice: Equatable {
    let id = UUID()
    let text: String
}

// MARK: - Playback Clock

/// The playback position on its own. Only views that show the position observe it.
final class PlaybackClock: ObservableObject {
    @Published var time: TimeInterval = 0
}

// MARK: - MusicService

class MusicService: ObservableObject {
    // MARK: - Library

    // Each list's alphabet-section letters are worked out once, whenever the list
    // changes, instead of twice per row on every redraw of the list.
    @Published var songs:        [AppTrack]    = [] { didSet { songSectionLetters = Self.sectionLetters(songs.map(\.title)) } }
    @Published var albums:       [AppAlbum]    = [] { didSet { albumSectionLetters = Self.sectionLetters(albums.map(\.title)) } }
    @Published var artists:      [AppArtist]   = [] { didSet { artistSectionLetters = Self.sectionLetters(artists.map(\.name)) } }
    @Published var playlists:    [AppPlaylist] = []
    @Published var podcastShows: [PodcastShow] = []

    // MARK: - Playback State

    @Published var isAuthorized  = false
    /// Drives the full-screen AccessRecoveryView in place of `lastError == .notAuthorized`
    /// alone, so the "access restored, reloading…" phase stays up through the reload that
    /// follows instead of disappearing the instant `lastError` clears. See `markAccessNeedsRecovery()`.
    @Published var isShowingAccessRecovery = false
    @Published var isLoading     = false
    /// True once a load has finished, whatever it found. Lets the UI distinguish
    /// "no music" from "haven't looked yet".
    @Published var hasLoadedLibrary = false
    @Published var subscriptionState: MusicSubscriptionState = .unknown
    @Published var librarySource: MusicLibrarySource = .none
    @Published var currentTrack: AppTrack?
    @Published var currentMediaItem: MPMediaItem?
    /// The episode being streamed, while the stream engine is active. `currentTrack`
    /// and `currentMediaItem` are nil then.
    @Published var currentEpisode: PodcastEpisode?
    /// A one-off message about playback for the screen to show, such as a stream
    /// failing offline. Each notice is distinct, so the same message twice still shows.
    @Published var playbackNotice: PlaybackNotice?

    /// Whether anything is loaded to show on Now Playing.
    var hasNowPlaying: Bool {
        currentTrack != nil || currentMediaItem != nil || currentEpisode != nil
    }
    /// Every path that starts or stops playback goes through this, so it is also where
    /// the progress ticker is switched on and off.
    @Published var isPlaying     = false {
        didSet {
            guard isPlaying != oldValue else { return }
            syncPlaybackTimeTicker()
        }
    }
    /// Playback position, published separately so its twice-a-second updates only
    /// redraw what reads it. As a `@Published` property here it redrew every screen
    /// observing the service — every menu and list — twice a second during playback.
    let clock = PlaybackClock()
    /// Read and written like a plain property. Reading it does not subscribe a view to
    /// updates; observe `clock` for that.
    var currentTime: TimeInterval {
        get { clock.time }
        set { clock.time = newValue }
    }
    @Published var duration:    TimeInterval = 0
    @Published var isScrubbing  = false

    // MARK: - Error State

    @Published var lastError: MusicLoadError?

    // MARK: - Lyre classic features

    @Published var repeatMode:            RepeatMode  = .off
    @Published var shuffleMode:           ShuffleMode = .off
    @Published var currentPlaylistID:     String?
    @Published var currentPodcastShowTitle: String?
    @Published var recentlyAdded:  [AppTrack] = [] { didSet { recentlyAddedSectionLetters = Self.sectionLetters(recentlyAdded.map(\.title)) } }
    @Published var recentlyPlayed: [AppTrack] = [] { didSet { recentlyPlayedSectionLetters = Self.sectionLetters(recentlyPlayed.map(\.title)) } }

    // MARK: - Section Letters
    //
    // Parallel to the lists above: the letter each row files under. Not published —
    // they only ever change alongside their list, which already publishes.

    private(set) var songSectionLetters:           [String] = []
    private(set) var albumSectionLetters:          [String] = []
    private(set) var artistSectionLetters:         [String] = []
    private(set) var recentlyAddedSectionLetters:  [String] = []
    private(set) var recentlyPlayedSectionLetters: [String] = []

    private static func sectionLetters(_ names: [String]) -> [String] {
        names.map { AppHelpers.firstLetter(of: $0) }
    }

    // MARK: - Queue

    /// Mirror of the player's queue, kept so the Queue screen can list and rearrange
    /// Up Next. See PlaybackQueue for why the app has to hold its own copy.
    @Published private(set) var playbackQueue = PlaybackQueue()

    /// The tracks waiting to play after the current one.
    var upNext: [AppTrack] { playbackQueue.upNext }

    /// What plays after the current item, whichever player has it: Up Next, or while an
    /// episode streams, the show's episodes after it, as tracks.
    var upcoming: [AppTrack] {
        activeEngine == .stream ? streamPlayer.upcoming.map(\.asTrack) : upNext
    }

    /// Whether `upcoming` can be reordered and taken from: only a queue of songs. A
    /// podcast's episodes play in the order the show put them out, streamed or not.
    var canEditUpcoming: Bool { activeEngine == .library && currentPodcastShowTitle == nil }

    /// What's playing, as a track: the song, or the episode streaming.
    var nowPlayingTrack: AppTrack? {
        activeEngine == .stream ? currentEpisode?.asTrack : currentTrack ?? playbackQueue.current
    }

    /// True while a podcast is the thing loaded, streamed or on the device. An
    /// on-device show counts until its episodes run out.
    var isPlayingPodcast: Bool {
        currentEpisode != nil || (currentPodcastShowTitle != nil && currentTrack != nil)
    }

    // MARK: - Podcast Speed

    /// The speeds podcasts can play at.
    static let podcastRates: [Float] = [0.75, 1, 1.25, 1.5, 1.75, 2]
    private static let podcastRateKey = "LyrePodcastRate"

    /// The speed podcasts play at. Music always plays at normal speed.
    @Published private(set) var podcastRate: Float =
        Float(UserDefaults.standard.object(forKey: "LyrePodcastRate") as? Double ?? 1)

    func setPodcastRate(_ rate: Float) {
        podcastRate = rate
        UserDefaults.standard.set(Double(rate), forKey: Self.podcastRateKey)
        streamPlayer.rate = rate
        applyLibraryRate()
        logger.info("Podcast speed: \(rate)x")
    }

    /// Sets the music player's speed for what it's playing: the podcast speed for an
    /// on-device episode, normal for music. Only while playing: a rate set on a paused
    /// player starts it.
    private func applyLibraryRate() {
        guard activeEngine == .library, didSetupNotifications, isPlaying else { return }
        let rate = currentPodcastShowTitle != nil ? podcastRate : 1
        if abs(player.currentPlaybackRate - rate) > 0.01 { player.currentPlaybackRate = rate }
    }

    // MARK: - Private

    /// Lazy, and first touched only once library access is granted, so nothing at
    /// launch can make iOS ask for access before onboarding does. See
    /// `setupNotificationsIfAuthorized()`.
    private lazy var player = MPMusicPlayerController.applicationQueuePlayer
    private var didSetupNotifications = false

    // MARK: - Podcast Streaming
    //
    // Episodes of subscribed shows stream through their own AVPlayer, because the music
    // player cannot play a URL. Only one engine is active at a time: starting either
    // pauses the other, and the music player's notifications are ignored while the
    // stream engine is active so its pause does not overwrite the podcast's state.

    private nonisolated enum PlaybackEngine { case library, stream }
    private var activeEngine: PlaybackEngine = .library
    private let streamPlayer = PodcastStreamPlayer()
    private let podcastSubscriptions = PodcastSubscriptions()
    let podcastDownloads = PodcastDownloads.shared
    /// Shows found in the on-device library; `podcastShows` adds the subscriptions.
    private var localPodcastShows: [PodcastShow] = []
    private var lastFeedRefresh: Date?
    private static let feedRefreshInterval: TimeInterval = 30 * 60
    /// Artwork for the lock screen while streaming, keyed by its URL.
    private var streamArtwork: (url: URL, artwork: MPMediaItemArtwork)?

    private var playbackStateObserver: NSObjectProtocol?
    private var nowPlayingObserver:    NSObjectProtocol?
    private var libraryChangeObserver: NSObjectProtocol?
    private var playbackTimeUpdateTimer: Timer?

    private static let maxRetryAttempts = 3
    private static let retryDelays: [TimeInterval] = [0, 2, 5]

    /// How long after handing the player a queue its now-playing reports are treated
    /// as unsettled. See `setPlayerQueue`.
    private static let queueSettlingWindow: TimeInterval = 3
    private var queueSettlingUntil: Date?

    /// Queue edits sent to the player that have not reported back yet.
    private var pendingQueueTransactions = 0

    // MARK: - Queue Windowing
    //
    // An application queue player serialises every item of its queue across to the
    // media server, so it cannot be handed a whole library: giving it ~6,400 songs
    // timed the XPC connection out ("ping did not pong") and blocked the main thread
    // for tens of seconds on every queue call. Only a window around the chosen track
    // is queued, and the rest of the list is fed in as playback approaches the end.

    /// Tracks handed to the player at once when playback starts or is topped up.
    private static let queueWindowSize = 150
    /// Tracks kept behind the chosen one, so skipping back still works.
    private static let queueHistorySize = 25
    /// Up Next length at which the next chunk of the source list is queued.
    private static let queueRefillThreshold = 25
    /// Ceiling on a single add. Comfortably larger than any album and most playlists,
    /// and small enough that the resulting queue stays far below the size that
    /// overwhelmed the player.
    private static let maxTracksPerAdd = 200

    /// The full list playback started from, and how far into it the player's queue
    /// already reaches.
    private var queueSourceTracks: [AppTrack] = []
    private var queueSourceNextIndex = 0

    /// True while the player is still settling onto a newly set queue.
    private var isQueueSettling: Bool {
        guard let queueSettlingUntil else { return false }
        guard Date() < queueSettlingUntil else {
            self.queueSettlingUntil = nil
            return false
        }
        return true
    }

    /// Snapshot of the media library's modification date at the time of the last
    /// successful load, so foreground refreshes can skip redundant work.
    private var lastLibraryModifiedDate: Date?

    /// On-device items from the last load, keyed by normalised title + artist. Kept so
    /// tracks fetched later — album and playlist contents — can be matched to a local
    /// item too. Written during a load, read from any thread afterwards.
    private var localItemIndex: [String: MPMediaItem] = [:]
    private var subscriptionObserverTask: Task<Void, Never>?
    private var subscriptionRetryTask: Task<Void, Never>?
    /// Backoff for re-checking the subscription after `itunescloudd` was unreachable.
    private static let subscriptionRetryDelays: [TimeInterval] = [1, 3, 8]
    /// The in-flight load, if any. Scanning a large library is expensive and several
    /// triggers can fire at once at launch, so concurrent callers share one load.
    @MainActor private var loadTask: Task<Void, Never>?
    /// True while the published library is the copy restored from LibraryCache rather
    /// than a live load. Restored objects carry no MusicKit or MPMediaItem handles, so
    /// anything that needs one waits for the live load first — see `liveAlbum(for:)`.
    private var isShowingCachedLibrary = false

    // MARK: - Init

    init() {
        Task {
            // Player state first. This used to run after the library load, so launching
            // while music was playing left Now Playing blank until the whole library had
            // been scanned. `setupNotifications` reads the player's current state, which
            // starts the progress ticker through `isPlaying` if something is playing.
            // Before access is granted this waits, so iOS doesn't prompt at launch.
            setupNotificationsIfAuthorized()
            setupStreamPlayer()
            await restoreCachedLibrary()
            await checkCurrentStatus()
        }
    }

    // MARK: - Launch Cache

    /// Publishes the library saved by the previous launch, so the menus are populated
    /// straight away. The live load that follows replaces it.
    private func restoreCachedLibrary() async {
        guard Self.hasAnyLibraryAccess else {
            // Access was revoked since the cache was written.
            LibraryCache.clear()
            return
        }
        guard let restored = await LibraryCache.load(), !restored.snapshot.isEmpty else { return }
        // A load that finished while the cache was being read is newer — keep it.
        guard !hasLoadedLibrary else { return }

        publish(restored.snapshot, source: restored.source)
        isShowingCachedLibrary = true
        hasLoadedLibrary = true
    }

    /// Replaces the published library in one go and re-points `currentTrack` at the
    /// new copy of whatever is playing.
    private func publish(_ snapshot: LibrarySnapshot, source: MusicLibrarySource) {
        songs          = snapshot.songs
        albums         = snapshot.albums
        artists        = snapshot.artists
        playlists      = snapshot.playlists
        recentlyAdded  = snapshot.recentlyAdded
        recentlyPlayed = snapshot.recentlyPlayed
        librarySource  = source
        if let nowPlaying = player.nowPlayingItem {
            currentTrack = libraryTrack(for: nowPlaying) ?? currentTrack
        }
    }

    /// Waits for an in-flight live load when the library on screen is still the
    /// cached copy. Returns immediately otherwise.
    private func waitForLiveLibrary() async {
        guard isShowingCachedLibrary, let loadTask else { return }
        await loadTask.value
    }

    /// The live counterpart of an album, playlist or artist the user picked from the
    /// cached library, which has no MusicKit object to expand and no artwork.
    private func liveAlbum(for album: AppAlbum) async -> AppAlbum {
        guard isShowingCachedLibrary else { return album }
        await waitForLiveLibrary()
        return albums.first { $0.id == album.id } ?? album
    }

    private func livePlaylist(for playlist: AppPlaylist) async -> AppPlaylist {
        guard isShowingCachedLibrary else { return playlist }
        await waitForLiveLibrary()
        return playlists.first { $0.id == playlist.id } ?? playlist
    }

    private func liveArtist(for artist: AppArtist) async -> AppArtist {
        guard isShowingCachedLibrary else { return artist }
        await waitForLiveLibrary()
        return artists.first { $0.id == artist.id } ?? artist
    }

    // MARK: - Authorization

    /// True when either authorization gate is open. MediaPlayer access alone is enough
    /// to show the user their on-device music and podcasts.
    static var hasAnyLibraryAccess: Bool {
        MusicAuthorization.currentStatus == .authorized
            || MPMediaLibrary.authorizationStatus() == .authorized
    }

    /// Onboarding owns its own "access needed" screen, so the revoked-access prompt below
    /// only fires for a returning user — never on top of onboarding's own denied state.
    private static var onboardingCompleted: Bool {
        UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    }

    /// Persists across a relaunch, because toggling Media & Apple Music access in
    /// Settings routinely terminates the app — the in-memory `isShowingAccessRecovery`
    /// flag alone would be lost, and the very next launch would land straight on the
    /// main menu with no acknowledgement that access had ever been a problem.
    private static var accessRecoveryPending: Bool {
        get { UserDefaults.standard.bool(forKey: "accessRecoveryPending") }
        set { UserDefaults.standard.set(newValue, forKey: "accessRecoveryPending") }
    }

    /// Set when the user dismisses the denied-access prompt without fixing it, so it
    /// doesn't force its way back on screen on every subsequent launch or foreground
    /// while access is still off. Persisted for the same reason `accessRecoveryPending`
    /// is: the app can be relaunched before the user ever returns. Cleared the moment
    /// access is found granted again — see `beginAccessRecoveryIfPending()` — so the
    /// *next* time access is revoked, the prompt is back to showing itself right away.
    private static var accessRecoverySkipped: Bool {
        get { UserDefaults.standard.bool(forKey: "accessRecoverySkipped") }
        set { UserDefaults.standard.set(newValue, forKey: "accessRecoverySkipped") }
    }

    /// `MusicSubscription` only reports a meaningful value once MusicKit itself is
    /// authorized. Before that, `canPlayCatalogContent` is false for *every* app,
    /// subscriber or not — reading it early makes a paying subscriber look unsubscribed.
    private static var canQuerySubscription: Bool {
        MusicAuthorization.currentStatus == .authorized
    }

    /// Marks the full-screen recovery prompt pending, both for this session and (via
    /// UserDefaults) for whatever process eventually finds access granted again. Stays
    /// off screen if the user already skipped it for this revocation — `lastError` is
    /// still set, in case some other surface wants to know access is off, but nothing
    /// forces its way back in front of the user until access actually comes back.
    private func markAccessNeedsRecovery() async {
        guard Self.onboardingCompleted else { return }
        Self.accessRecoveryPending = true
        await MainActor.run {
            lastError = .notAuthorized
            if !Self.accessRecoverySkipped { isShowingAccessRecovery = true }
        }
    }

    /// Lets the user into the app without fixing access. Called by AccessRecoveryView's
    /// "Not Now" button.
    func skipAccessRecovery() {
        Self.accessRecoverySkipped = true
        isShowingAccessRecovery = false
    }

    /// True when this launch/foreground owes the user a recovery confirmation — either
    /// because the prompt is already on screen this session, or because a previous
    /// session left access pending and was killed before it could confirm the fix.
    /// Clears a prior skip: once access is actually back, the restoring screen is
    /// shown regardless — skipping only ever silenced the denied-access ask.
    private func beginAccessRecoveryIfPending() async -> Bool {
        let pending = await MainActor.run { isShowingAccessRecovery } || Self.accessRecoveryPending
        guard pending else { return false }
        Self.accessRecoverySkipped = false
        await MainActor.run {
            lastError = nil
            isShowingAccessRecovery = true
        }
        return true
    }

    /// Keeps the recovery prompt up for a couple of seconds after the reload finishes,
    /// so "access restored" is never just a flash before the menu appears underneath
    /// it. Albums are the last thing `loadLibraryAttempt` publishes, so the cover-intake
    /// animation has shown nothing but placeholder tiles up to this point — this settle
    /// is what gives the user's own covers, now available, a couple of real cycles
    /// on screen instead of never appearing at all.
    private func resolveAccessRecovery() async {
        try? await Task.sleep(for: .seconds(2))
        Self.accessRecoveryPending = false
        await MainActor.run { isShowingAccessRecovery = false }
    }

    private func checkCurrentStatus() async {
        let granted = Self.hasAnyLibraryAccess
        await MainActor.run { isAuthorized = granted }
        guard granted else {
            await markAccessNeedsRecovery()
            return
        }
        let isRecovering = await beginAccessRecoveryIfPending()
        setupNotificationsIfAuthorized()
        await refreshSubscriptionState()
        await loadLibrary()
        if isRecovering { await resolveAccessRecovery() }
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
        setupNotificationsIfAuthorized()

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

    /// Listening for subscription changes makes iOS ask for Apple Music access, so it
    /// starts only once MusicKit is authorized — never on a fresh install's welcome
    /// screen, before onboarding has asked.
    private func observeSubscriptionUpdatesIfAuthorized() {
        guard subscriptionObserverTask == nil, Self.canQuerySubscription else { return }
        observeSubscriptionUpdates()
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
        // Subscribed feeds need no library access, and new episodes are what an
        // automatic download waits on. Throttled, so this is cheap on most returns.
        Task { await refreshSubscribedFeeds() }

        let granted = Self.hasAnyLibraryAccess
        let wasAuthorized = await MainActor.run { () -> Bool in
            let previous = isAuthorized
            isAuthorized = granted
            return previous
        }
        guard granted else {
            await markAccessNeedsRecovery()
            return
        }
        let isRecovering = await beginAccessRecoveryIfPending()
        setupNotificationsIfAuthorized()

        if !wasAuthorized { await refreshSubscriptionState() }

        let modifiedDate = MPMediaLibrary.default().lastModifiedDate
        let needsReload = await MainActor.run {
            !isLoading && (!hasLoadedLibrary || isLibraryEmpty || modifiedDate != lastLibraryModifiedDate)
        }
        // A recovery always reloads, even if nothing about the on-device library looks
        // different: it's the signal AccessRecoveryView waits on to know the library is
        // genuinely current again, not just a heuristic for whether a reload is worth it.
        if needsReload || isRecovering { await loadLibrary() }

        if isRecovering { await resolveAccessRecovery() }
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

        let playableOnly = !subscriptionStateAllowsCatalogPlayback
        let hadNothingOnScreen = isLibraryEmpty

        // All three sources are read concurrently and off the main thread. They used to
        // run one after another on the main thread, which froze the interface on every
        // launch. The on-device library is the baseline: it needs no network and no
        // subscription, and it is the only source of podcasts. MusicKit is layered on
        // top when it has anything to offer.
        async let localScan     = LibraryScanner.scanLocal(playableOnly: playableOnly)
        async let podcastScan   = LibraryScanner.scanPodcasts()
        async let musicKitFetch = LibraryScanner.fetchMusicKitLibrary()

        // Podcasts are never cached, so they go on screen the moment they exist.
        let podcastShowsFound = await podcastScan
        setPodcastShowsIfChanged(podcastShowsFound)

        var local = await localScan

        // With nothing on screen yet — a first launch, or no usable cache — show the
        // on-device songs now instead of after MusicKit's round trips. Skipped when the
        // cached library is showing, which would only swap it for a partial one.
        if hadNothingOnScreen && !local.snapshot.songs.isEmpty {
            songs          = local.snapshot.songs
            recentlyAdded  = local.snapshot.recentlyAdded
            recentlyPlayed = local.snapshot.recentlyPlayed
        }

        // A throw here is not fatal as long as the local snapshot found something.
        var musicKit: LibrarySnapshot?
        var musicKitError: Error?
        do {
            let library = try await musicKitFetch
            musicKit = await LibraryScanner.musicKitSnapshot(from: library, local: local)
        } catch {
            musicKitError = error
        }

        // Grouping the on-device library into albums, artists and playlists only runs
        // for the collections MusicKit did not supply.
        let needsAlbums    = musicKit?.albums.isEmpty ?? true
        let needsArtists   = musicKit?.artists.isEmpty ?? true
        let needsPlaylists = musicKit?.playlists.isEmpty ?? true
        if needsAlbums || needsArtists || needsPlaylists {
            let collections = await LibraryScanner.localCollections(
                from: local,
                needsAlbums: needsAlbums,
                needsArtists: needsArtists,
                needsPlaylists: needsPlaylists,
                playableOnly: playableOnly
            )
            local.snapshot.albums    = collections.albums
            local.snapshot.artists   = collections.artists
            local.snapshot.playlists = collections.playlists
        }

        let merged = LibrarySnapshot.merging(preferred: musicKit, fallback: local.snapshot)
        let source = LibrarySnapshot.source(preferred: musicKit, merged: merged)

        // -1 for a MusicKit count means the request threw rather than returned empty.
        logger.notice("""
            Load attempt \(attempt + 1)/\(Self.maxRetryAttempts) — \
            local: \(local.snapshot.songs.count) songs/\(local.snapshot.albums.count) albums/\(local.snapshot.playlists.count) playlists, \
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
                isLoading = false
                hasLoadedLibrary = true
                // The cached library is still a better thing to show than an error
                // about a library the user can already see.
                if isShowingCachedLibrary {
                    logger.notice("Live load failed — keeping the cached library on screen")
                } else {
                    lastError = loadError
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

        // Replacing the library redraws every screen, so skip it when a refresh found
        // exactly what is already showing. The cached copy is always replaced, though:
        // it lacks the live artwork and MusicKit handles.
        let isUnchanged = !isShowingCachedLibrary && matchesPublishedLibrary(merged, source: source)
        if isUnchanged {
            logger.info("Refresh found no changes — keeping the published library")
        } else {
            publish(merged, source: source)
        }
        isLoading               = false
        hasLoadedLibrary        = true
        lastError               = nil
        lastLibraryModifiedDate = MPMediaLibrary.default().lastModifiedDate
        localItemIndex          = merged.mpItemIndex
        isShowingCachedLibrary  = false
        logger.notice("Loaded \(self.songs.count) songs, \(self.albums.count) albums, \(self.artists.count) artists, \(self.playlists.count) playlists, \(self.podcastShows.count) podcasts from \(String(describing: source)) [subscription: \(String(describing: self.subscriptionState))]")

        // Written in the background so nothing waiting on this load waits on the disk.
        // `save` itself skips the write when the file already holds this library.
        if !isUnchanged {
            Task { await LibraryCache.save(merged, source: source) }
        }
    }

    // MARK: - Change Detection

    /// True when `snapshot` would put the same rows on screen as the published library.
    /// Compares what the rows show, not just ids, so a renamed song still counts.
    private func matchesPublishedLibrary(_ snapshot: LibrarySnapshot, source: MusicLibrarySource) -> Bool {
        func sameTracks(_ lhs: [AppTrack], _ rhs: [AppTrack]) -> Bool {
            lhs.elementsEqual(rhs) {
                $0.id == $1.id && $0.title == $1.title
                    && $0.artistName == $1.artistName && $0.albumTitle == $1.albumTitle
            }
        }
        return source == librarySource
            && sameTracks(songs, snapshot.songs)
            && sameTracks(recentlyAdded, snapshot.recentlyAdded)
            && sameTracks(recentlyPlayed, snapshot.recentlyPlayed)
            && albums.elementsEqual(snapshot.albums) {
                $0.id == $1.id && $0.title == $1.title && $0.artistName == $1.artistName
                    && sameTracks($0.preloadedTracks, $1.preloadedTracks)
            }
            && artists.elementsEqual(snapshot.artists) {
                $0.id == $1.id && $0.name == $1.name
                    && $0.preloadedAlbums.map(\.id) == $1.preloadedAlbums.map(\.id)
            }
            && playlists.elementsEqual(snapshot.playlists) {
                $0.id == $1.id && $0.name == $1.name
                    && sameTracks($0.preloadedTracks, $1.preloadedTracks)
            }
    }

    /// Publishes podcast shows only when they differ from what is showing. PodcastShow
    /// equality is by title alone, so episodes are compared here too — a new episode
    /// has to get through.
    private func setPodcastShowsIfChanged(_ shows: [PodcastShow]) {
        localPodcastShows = shows
        publishPodcastShows()
    }

    /// Publishes the on-device shows and the subscriptions as one alphabetical list.
    private func publishPodcastShows() {
        let merged = (localPodcastShows + podcastSubscriptions.feeds.map(PodcastShow.init(feed:)))
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        let unchanged = podcastShows.elementsEqual(merged) {
            $0.id == $1.id && $0.episodes.map(\.id) == $1.episodes.map(\.id)
        }
        if !unchanged { podcastShows = merged }
    }

    /// Reads `subscriptionState` for the load. `.unknown` is treated as "might be able
    /// to stream", so cloud items are not hidden before the check lands.
    private var subscriptionStateAllowsCatalogPlayback: Bool {
        subscriptionState != .notSubscribed
    }

    // MARK: - Track/Album/Artist Loading

    // Locally-sourced items carry their children in `preloadedTracks` / `preloadedAlbums`
    // because there is no MusicKit object to expand. They are also the fallback when a
    // MusicKit expansion fails or comes back empty.

    /// Attaches the on-device item for a track when the library has one.
    ///
    /// The library load does this for the Songs list, but album and playlist contents
    /// are fetched separately and so arrive with no media item at all. Without this
    /// they fall through to `mediaItem(for:)`'s exact-title query, which misses songs
    /// the user owns whenever the catalogue and local titles differ even slightly —
    /// and a track with no item is dropped from playback entirely.
    private func attachingLocalItem(to track: AppTrack) -> AppTrack {
        track.attaching(mpItem: localItemIndex[LibraryScanner.matchKey(title: track.title, artist: track.artistName)])
    }

    /// An album's songs, each once: a library can hold a song on an album more than
    /// once (see `withoutDuplicates`), and every player lists, plays and queues the same
    /// songs. A playlist's repeats are left alone; they're put there on purpose.
    func loadTracks(for album: AppAlbum) async -> [AppTrack] {
        await loadAllTracks(for: album).withoutDuplicates
    }

    private func loadAllTracks(for album: AppAlbum) async -> [AppTrack] {
        // Picked from the cached library: it has no MusicKit album to expand.
        let album = await liveAlbum(for: album)
        guard let mkAlbum = album.musicKitAlbum else { return album.preloadedTracks }
        do {
            let detailed = try await mkAlbum.with([.tracks])
            let tracks = (detailed.tracks ?? []).map { attachingLocalItem(to: AppTrack(from: $0)) }
            return tracks.isEmpty ? album.preloadedTracks : tracks
        } catch {
            logger.error("Failed to load tracks for album '\(album.title)': \(error)")
            return album.preloadedTracks
        }
    }

    func loadTracks(for playlist: AppPlaylist) async -> [AppTrack] {
        let playlist = await livePlaylist(for: playlist)
        guard let mkPlaylist = playlist.musicKitPlaylist else { return playlist.preloadedTracks }
        do {
            let detailed = try await mkPlaylist.with([.tracks])
            let tracks = (detailed.tracks ?? []).map { attachingLocalItem(to: AppTrack(from: $0)) }
            return tracks.isEmpty ? playlist.preloadedTracks : tracks
        } catch {
            logger.error("Failed to load tracks for playlist '\(playlist.name)': \(error)")
            return playlist.preloadedTracks
        }
    }

    func loadAlbums(for artist: AppArtist) async -> [AppAlbum] {
        let artist = await liveArtist(for: artist)
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

    @discardableResult
    func play(tracks: [AppTrack], startingAt index: Int = 0, playlistID: String? = nil) async -> PlaybackStartOutcome {
        guard index < tracks.count else { return .nothingPlayable }
        logger.info("Starting playback: \(tracks.count) track(s), index \(index)")

        // Only a window around the chosen track goes to the player; the rest is fed in
        // by refillQueueIfNeeded() as playback gets near the end of it. Resolving media
        // items for just the window also keeps the per-track MPMediaQuery fallback from
        // running thousands of times before the first note plays.
        let windowStart = max(0, index - Self.queueHistorySize)
        let windowEnd = min(tracks.count, index + Self.queueWindowSize)
        // Tracks with no media item behind them cannot be queued, so the requested
        // start position is resolved against the tracks that survived the filter
        // rather than reused as-is — a dropped earlier track would otherwise shift
        // playback onto the wrong song.
        let window = await Self.resolveForPlayback(Array(tracks[windowStart..<windowEnd]))
        guard !window.items.isEmpty else {
            logger.warning("No MPMediaItems resolved for playback queue")
            return .nothingPlayable
        }

        // The chosen track being missing from the resolved window means it has nothing
        // the player can queue. Falling back to another track would quietly play a song
        // the user did not pick, so this reports the failure instead.
        guard let startIndex = window.tracks.firstIndex(of: tracks[index]) else {
            logger.warning("Cannot play '\(tracks[index].title)' — no media item backs it")
            return .trackUnavailable
        }

        await MainActor.run {
            queueSourceTracks = tracks
            queueSourceNextIndex = windowEnd
            playbackQueue = PlaybackQueue(tracks: window.tracks, currentIndex: startIndex)
            setPlayerQueue(items: window.items, startItem: window.items[startIndex], thenPlay: true)
            currentTrack = window.tracks[startIndex]
            isPlaying = true
            currentPlaylistID = playlistID
            currentPodcastShowTitle = nil
            logger.info("Queued \(window.items.count) of \(tracks.count) track(s); now playing: \(window.tracks[startIndex].title)")
        }
        return .started
    }

    /// Attaches a media item to each track, dropping the ones that cannot be played.
    /// Returns the survivors and their items in matching order. Runs off the main
    /// thread, because the per-track lookup can hit MPMediaQuery.
    @concurrent
    private nonisolated static func resolveForPlayback(_ tracks: [AppTrack]) async -> (tracks: [AppTrack], items: [MPMediaItem]) {
        var resolvedTracks: [AppTrack] = []
        var items: [MPMediaItem] = []
        for track in tracks {
            guard let item = mediaItem(for: track) else { continue }
            resolvedTracks.append(track.attaching(mpItem: item))
            items.append(item)
        }
        return (resolvedTracks, items)
    }

    /// Tops the player's queue up from the list playback started with, so a windowed
    /// queue still plays through a whole library. Main thread only.
    private func refillQueueIfNeeded() {
        guard queueSourceNextIndex < queueSourceTracks.count,
              playbackQueue.upNextCount <= Self.queueRefillThreshold,
              pendingQueueTransactions == 0 else { return }

        let end = min(queueSourceTracks.count, queueSourceNextIndex + Self.queueWindowSize)
        let slice = Array(queueSourceTracks[queueSourceNextIndex..<end])
        // Claim the range before doing any work, so the next now-playing notification
        // cannot start a second refill of the same tracks.
        queueSourceNextIndex = end
        let remaining = queueSourceTracks.count - end

        Task { [weak self] in
            guard let self else { return }
            let chunk = await Self.resolveForPlayback(slice)
            guard !chunk.items.isEmpty else { return }
            await MainActor.run {
                for track in chunk.tracks { self.playbackQueue.append(track) }
                // Read on the main thread: a music player must not be touched from
                // inside the transaction block.
                let currentItem = self.player.nowPlayingItem
                logger.info("Refilled queue with \(chunk.items.count) item(s), \(remaining) left to come")
                self.performQueueTransaction("refill \(chunk.items.count) item(s)") { queue in
                    queue.insert(Self.queueDescriptor(for: chunk.items), after: queue.items.last)

                    // Drop long-since-played tracks. Without this the queue only ever
                    // grows, and playing through a large library would end up back at
                    // the size that overwhelmed the player in the first place.
                    guard let currentItem,
                          let currentIndex = queue.items.firstIndex(where: {
                              $0.persistentID == currentItem.persistentID
                          }),
                          currentIndex > Self.queueHistorySize else { return }
                    let stale = Array(queue.items.prefix(currentIndex - Self.queueHistorySize))
                    for item in stale { queue.remove(item) }
                }
            }
        }
    }

    @discardableResult
    func play(track: AppTrack) async -> PlaybackStartOutcome {
        await play(tracks: [track], startingAt: 0)
    }

    /// Plays a whole collection from the top, or in a random order. The list itself is
    /// shuffled rather than the player's shuffle mode switched on, because the player
    /// only ever holds a window of the queue and could only shuffle within that.
    ///
    /// No particular track was asked for here, so an unplayable first track just moves
    /// the start on to the next one instead of failing the way picking a row does.
    @discardableResult
    func playAll(tracks: [AppTrack], shuffled: Bool, playlistID: String? = nil) async -> PlaybackStartOutcome {
        let ordered = shuffled ? tracks.shuffled() : tracks
        var outcome = PlaybackStartOutcome.nothingPlayable
        for index in ordered.indices {
            outcome = await play(tracks: ordered, startingAt: index, playlistID: playlistID)
            if outcome != .trackUnavailable { break }
        }
        return outcome
    }

#if DEBUG
    // MARK: - Catalogue Spike Hooks
    //
    // The player is private, so these hand it to CatalogueQueueSpike. Compiled out of
    // release builds; delete along with the spike. See Docs/CATALOGUE-QUEUE-SPIKE.md.

    @MainActor
    func spikeAppendAsCatalogue(_ track: AppTrack) {
        CatalogueQueueSpike.appendToCurrentQueue(track, player: player)
    }

    @MainActor
    func spikePlayAllAsCatalogue(_ tracks: [AppTrack], startingAt index: Int) {
        CatalogueQueueSpike.playAllAsCatalogue(tracks, startingAt: index, player: player)
    }

    @MainActor
    func spikeReportNowPlaying() {
        CatalogueQueueSpike.reportNowPlaying(player: player)
    }
#endif

    /// Plays episodes of a show: on-device episodes through the music player, streamed
    /// ones through the stream engine.
    func playPodcastEpisodes(_ episodes: [PodcastEpisode], startingAt index: Int = 0, podcastShowTitle: String? = nil) async {
        guard episodes.indices.contains(index) else { return }
        guard episodes[index].streamURL != nil else {
            // An on-device show. Any episode without a media item behind it is dropped,
            // and the start index is found again among the survivors.
            let local = episodes.filter { $0.mediaItem != nil }
            guard let start = local.firstIndex(of: episodes[index]) else { return }
            await playPodcastEpisodes(items: local.compactMap(\.mediaItem), startingAt: start, podcastShowTitle: podcastShowTitle)
            return
        }

        logger.info("Streaming podcast '\(podcastShowTitle ?? "unknown")': \(episodes.count) episode(s) at index \(index)")
        await MainActor.run {
            activateStreamEngine()
            streamPlayer.play(episodes, startingAt: index)
            currentPlaylistID = nil
            currentPodcastShowTitle = podcastShowTitle
        }
    }

    private func playPodcastEpisodes(items: [MPMediaItem], startingAt index: Int = 0, podcastShowTitle: String? = nil) async {
        guard !items.isEmpty, index < items.count else { return }
        logger.info("Playing podcast '\(podcastShowTitle ?? "unknown")': \(items.count) episode(s) at index \(index)")
        let startItem = items[index]
        await MainActor.run {
            // An episode list is short enough to queue whole, and clearing the source
            // stops a previous song queue from refilling podcast playback with music.
            queueSourceTracks = []
            queueSourceNextIndex = 0
            playbackQueue = PlaybackQueue(tracks: items.map { AppTrack(from: $0) }, currentIndex: index)
            setPlayerQueue(items: items, startItem: startItem, thenPlay: true)
            isPlaying = true
            currentPlaylistID = nil
            currentPodcastShowTitle = podcastShowTitle
        }
    }

    // MARK: - Queue

    /// Adds a track to the bottom of the queue, or starts playing it when nothing is
    /// playing. The model is updated first so the Queue screen reacts immediately, then
    /// the same change is made to the player's queue in place — playback is untouched.
    @discardableResult
    func addToQueue(_ track: AppTrack, placement: QueuePlacement = .last) async -> QueueAddOutcome {
        await addToQueue(tracks: [track], placement: placement)
    }

    /// Adds tracks to the bottom of the queue in one edit, keeping their order — this
    /// is how a whole album or playlist is queued.
    ///
    /// Unplayable tracks are skipped rather than failing the whole add, and counted in
    /// the outcome so the UI can say that a collection went in partly. The add is
    /// capped at `maxTracksPerAdd`: a queue transaction carries every item across to
    /// the media server, and an unbounded add would put us back where a whole library
    /// in one queue did (`_establishConnectionIfNeeded timeout`, seconds of frozen UI).
    @discardableResult
    func addToQueue(tracks: [AppTrack], placement: QueuePlacement = .last) async -> QueueAddOutcome {
        // While a podcast plays, Up Next is its episodes: songs queued now would go into
        // the music player's queue behind it, where they'd never be heard.
        guard await MainActor.run(body: { !isPlayingPodcast }) else {
            logger.info("Not queueing \(tracks.count) track(s): a podcast is playing")
            return .podcastPlaying
        }
        guard !tracks.isEmpty else { return .unavailable }

        let accepted = Array(tracks.prefix(Self.maxTracksPerAdd))
        let overflow = tracks.count - accepted.count
        // Resolution can fall back to a per-track MPMediaQuery, so keep it off the
        // main thread — a 200-track album would be a visible stall otherwise.
        let resolved = await Self.resolveForPlayback(accepted)
        let skipped = (accepted.count - resolved.items.count) + overflow

        guard !resolved.items.isEmpty else {
            logger.warning("Cannot queue \(tracks.count) track(s) — nothing playable behind them")
            return .unavailable
        }

        let isIdle = await MainActor.run { player.nowPlayingItem == nil }
        guard !isIdle else {
            // Nothing playing, so the tracks start rather than waiting their turn —
            // but only report that if playback actually started.
            let started = await play(tracks: resolved.tracks) == .started
            return started ? .startedPlaying(count: resolved.tracks.count, skipped: skipped) : .unavailable
        }

        return await MainActor.run {
            // The player is playing something the model doesn't know about — only
            // possible if a queue was set outside `play(tracks:)`. Seed the model so
            // the new tracks have something to sit behind.
            if playbackQueue.isEmpty, let nowPlaying = player.nowPlayingItem {
                playbackQueue = PlaybackQueue(tracks: [AppTrack(from: nowPlaying)])
            }
            switch placement {
            case .last:
                for track in resolved.tracks { playbackQueue.append(track) }
                performQueueTransaction("append \(resolved.items.count) track(s)") { queue in
                    queue.insert(Self.queueDescriptor(for: resolved.items), after: queue.items.last)
                }

            case .next:
                // Read before the model changes and on the main thread: a music player
                // must not be touched from inside the transaction block.
                let currentItem = player.nowPlayingItem
                let modelIndex = playbackQueue.currentIndex
                playbackQueue.insertUpNext(resolved.tracks)
                performQueueTransaction("insert \(resolved.items.count) track(s) next") { queue in
                    // The same song can sit in the queue more than once, so anchor to the
                    // copy nearest the model's current position rather than the first
                    // one, which may be long since played.
                    let anchor = currentItem.flatMap { current in
                        queue.items.indices
                            .filter { queue.items[$0].persistentID == current.persistentID }
                            .min { abs($0 - modelIndex) < abs($1 - modelIndex) }
                            .map { queue.items[$0] }
                    }
                    // Without an anchor the best available is the bottom: never in
                    // front of the song that is playing.
                    queue.insert(Self.queueDescriptor(for: resolved.items), after: anchor ?? queue.items.last)
                }
            }
            logger.info("Queued \(resolved.items.count) track(s) \(placement == .next ? "next" : "last"), skipped \(skipped); Up Next is now \(self.playbackQueue.upNextCount)")
            return .queued(count: resolved.tracks.count, skipped: skipped)
        }
    }

    /// Moves an Up Next track within the model only, leaving the player alone so
    /// carrying a row through the list stays instant. Call `commitQueueMove(to:)` once
    /// the move is committed. Main thread only.
    func reorderUpNext(from origin: Int, to destination: Int) {
        guard canEditUpcoming else { return }
        playbackQueue.moveUpNext(from: origin, to: destination)
    }

    /// Applies a finished reorder to the player: the moved track is taken out of the
    /// queue and put back after whatever now precedes it in the model, both inside one
    /// transaction so the change is atomic and playback continues untouched.
    /// Main thread only.
    func commitQueueMove(to offset: Int) {
        guard canEditUpcoming else { return }
        let upNext = playbackQueue.upNext
        guard upNext.indices.contains(offset), let movedItem = upNext[offset].mpItem else { return }
        // Up Next offset 0 sits directly after the current track, so there is always a
        // preceding track to anchor the insert to.
        let precedingItem = playbackQueue.tracks[playbackQueue.currentIndex + offset].mpItem

        logger.info("Moving '\(upNext[offset].title)' to Up Next position \(offset + 1)")
        performQueueTransaction("move '\(upNext[offset].title)'") { queue in
            guard let existing = queue.items.first(where: { $0.persistentID == movedItem.persistentID }) else { return }
            let anchor = precedingItem.flatMap { preceding in
                queue.items.first { $0.persistentID == preceding.persistentID }
            }
            queue.remove(existing)
            queue.insert(Self.queueDescriptor(for: [existing]), after: anchor)
        }
    }

    /// Removes an Up Next track from the model and the player's queue.
    /// Main thread only.
    @discardableResult
    func removeFromQueue(at offset: Int) -> AppTrack? {
        guard canEditUpcoming, let removed = playbackQueue.removeUpNext(at: offset) else { return nil }
        logger.info("Removed '\(removed.title)' from the queue")
        if let item = removed.mpItem {
            performQueueTransaction("remove '\(removed.title)'", refillAfter: true) { queue in
                guard let existing = queue.items.first(where: { $0.persistentID == item.persistentID }) else { return }
                queue.remove(existing)
            }
        }
        return removed
    }

    /// Empties Up Next, leaving the current track playing. Returns how many tracks
    /// were dropped. Main thread only.
    @discardableResult
    func clearQueue() -> Int {
        guard canEditUpcoming else { return 0 }
        let removed = playbackQueue.removeAllUpNext()
        guard removed > 0 else { return 0 }

        // Forget the list playback came from as well. Clearing only the loaded window
        // would leave the refill free to put the rest of that library straight back,
        // which is not what "clear the queue" can reasonably mean.
        queueSourceTracks = []
        queueSourceNextIndex = 0

        // Read on the main thread: a music player must not be touched from inside the
        // transaction block.
        let currentItem = player.nowPlayingItem
        performQueueTransaction("clear \(removed) item(s)") { queue in
            let upcoming: [MPMediaItem]
            if let currentItem,
               let currentIndex = queue.items.firstIndex(where: { $0.persistentID == currentItem.persistentID }) {
                upcoming = Array(queue.items.suffix(from: currentIndex + 1))
            } else {
                // Nothing is playing, so there is no track to keep.
                upcoming = queue.items
            }
            for item in upcoming { queue.remove(item) }
        }
        logger.info("Cleared \(removed) track(s) from the queue")
        return removed
    }

    /// Jumps straight to an Up Next track. The tracks before it are passed over and stay
    /// behind it in the queue, as if they had played. Main thread only.
    /// Plays an item from `upcoming`: an Up Next track, or a later episode of the show
    /// streaming. Main thread only.
    func playUpcoming(at offset: Int) {
        guard activeEngine == .stream else { return playUpNext(at: offset) }
        let upcoming = streamPlayer.upcoming
        guard upcoming.indices.contains(upcoming.startIndex + offset) else { return }
        logger.info("Jumping to episode '\(upcoming[upcoming.startIndex + offset].title)'")
        // The whole list stays, so going back from the episode still works.
        streamPlayer.play(streamPlayer.episodes, startingAt: streamPlayer.index + 1 + offset)
    }

    func playUpNext(at offset: Int) {
        let upNext = playbackQueue.upNext
        guard activeEngine == .library, upNext.indices.contains(offset),
              let item = upNext[offset].mpItem else { return }
        logger.info("Jumping to '\(upNext[offset].title)' in Up Next")
        player.nowPlayingItem = item
        player.play()
    }

    #if DEBUG
    /// Fills the queue model with tracks that have nothing behind them, so Up Next can be
    /// shown and UI-tested on a simulator with no music. The player is left alone.
    func seedQueueForUITests(_ tracks: [AppTrack]) {
        playbackQueue = PlaybackQueue(tracks: tracks, currentIndex: 0)
    }
    #endif

    /// Runs one queue edit against the player and reconciles the model with the result.
    ///
    /// Editing in place is the reason the app uses `applicationQueuePlayer`: the whole
    /// point is that adding or reordering never interrupts what is playing. The queue
    /// reported to the completion handler is authoritative, so the model is rebuilt
    /// from it rather than trusting that the edit landed exactly as asked.
    private func performQueueTransaction(
        _ description: String,
        refillAfter: Bool = false,
        _ edit: @escaping (MPMusicPlayerControllerMutableQueue) -> Void
    ) {
        pendingQueueTransactions += 1
        player.perform(queueTransaction: edit) { [weak self] queue, error in
            // The queue object must not escape the handler, so read it here and hand
            // the plain items over to the main thread.
            let items = queue.items
            DispatchQueue.main.async {
                guard let self else { return }
                self.pendingQueueTransactions -= 1
                if let error {
                    logger.error("Queue transaction (\(description)) failed: \(error.localizedDescription)")
                }
                // Queueing several songs in a row leaves earlier transactions
                // reporting a queue that is already out of date, so only the last one
                // still in flight gets to rewrite the model.
                guard self.pendingQueueTransactions == 0 else { return }
                self.syncQueueModel(with: items)
                // Only a shrinking edit (removing a track) can leave Up Next short
                // enough to need topping up again — an append/insert only grows it, and
                // refilling there bulk-added the rest of `queueSourceTracks` onto the
                // single song a user had just deliberately added, the moment Up Next
                // happened to already be at or under the refill threshold.
                if refillAfter { self.refillQueueIfNeeded() }
            }
        }
    }

    /// Rebuilds the queue model from the player's actual queue, keeping the richer
    /// AppTrack the app already holds for each item so MusicKit artwork and metadata
    /// are not downgraded to what MPMediaItem alone can say. Main thread only.
    private func syncQueueModel(with items: [MPMediaItem]) {
        guard !items.isEmpty else {
            playbackQueue = PlaybackQueue()
            return
        }
        let known = Dictionary(
            playbackQueue.tracks.compactMap { track in track.mpItem.map { ($0.persistentID, track) } },
            uniquingKeysWith: { first, _ in first }
        )
        let tracks = items.map { known[$0.persistentID] ?? AppTrack(from: $0) }
        let currentIndex = player.nowPlayingItem
            .flatMap { nowPlaying in items.firstIndex { $0.persistentID == nowPlaying.persistentID } }
            ?? playbackQueue.currentIndex
        playbackQueue = PlaybackQueue(tracks: tracks, currentIndex: currentIndex)
    }

    private static func queueDescriptor(for items: [MPMediaItem]) -> MPMusicPlayerMediaItemQueueDescriptor {
        MPMusicPlayerMediaItemQueueDescriptor(itemCollection: MPMediaItemCollection(items: items))
    }

    /// Replaces the player's queue wholesale. Only starting fresh playback does this —
    /// changes to an existing queue are edits, made through `performQueueTransaction`.
    ///
    /// A new queue makes the player briefly report a missing or stale now-playing item;
    /// `queueSettlingUntil` stops those transient notifications from being read as
    /// "playback left our queue", which would throw away the queue being applied.
    ///
    /// `thenPlay` starts playback immediately and then, once the player confirms the
    /// queue, checks it landed on the right track.
    ///
    /// Starting from inside `prepareToPlay`'s completion instead looked tidier but left
    /// playback dead whenever that handler was slow or never arrived — every control
    /// that starts a song went with it. Playing first and correcting after is worse in
    /// theory and far more robust in practice: `setQueue` can be accepted after `play()`
    /// has begun, leaving the player on the head of the queue rather than on
    /// `startItem`, and that case is repaired rather than prevented.
    private func setPlayerQueue(items: [MPMediaItem], startItem: MPMediaItem, thenPlay: Bool = false) {
        activateLibraryEngine()
        let descriptor = MPMusicPlayerMediaItemQueueDescriptor(
            itemCollection: MPMediaItemCollection(items: items)
        )
        descriptor.startItem = startItem
        queueSettlingUntil = Date().addingTimeInterval(Self.queueSettlingWindow)
        player.setQueue(with: descriptor)

        guard thenPlay else {
            player.prepareToPlay()
            return
        }
        player.play()
        player.prepareToPlay { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    logger.error("Preparing the queue failed: \(error.localizedDescription)")
                }
                guard self.player.nowPlayingItem?.persistentID != startItem.persistentID else { return }
                logger.notice("Queue settled on the wrong track — moving to '\(startItem.title ?? "unknown")'")
                self.player.nowPlayingItem = startItem
                self.player.play()
            }
        }
    }

    // MARK: - Transport Controls

    func togglePlayPause() async {
        await MainActor.run {
            if activeEngine == .stream {
                streamPlayer.isPlaying ? streamPlayer.pause() : streamPlayer.resume()
                return
            }
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
        await MainActor.run {
            if activeEngine == .stream { streamPlayer.skipToNext() } else { player.skipToNextItem() }
        }
    }

    func skipToPrevious() async {
        logger.info("Skipping to previous track")
        await MainActor.run {
            if activeEngine == .stream { streamPlayer.skipToPrevious() } else { player.skipToPreviousItem() }
        }
    }

    func seek(to time: TimeInterval) async {
        await MainActor.run {
            if activeEngine == .stream {
                streamPlayer.seek(to: time)
            } else {
                player.currentPlaybackTime = time
            }
            currentTime = time
        }
    }

    func startScrubbing() { isScrubbing = true  }
    func stopScrubbing()  { isScrubbing = false }

    // MARK: - Podcasts

    func refreshPodcasts() async {
        // Runs on every visit to the Podcasts screen, so an unchanged scan must not
        // republish and redraw everything.
        setPodcastShowsIfChanged(await LibraryScanner.scanPodcasts())
        await refreshSubscribedFeeds()
    }

    /// True when a playback error comes down to having no connection. AVFoundation
    /// wraps the network error, so the underlying errors are searched too.
    private static func isOffline(_ error: Error?) -> Bool {
        var next = error as NSError?
        while let current = next {
            if current.domain == NSURLErrorDomain, [
                NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
                NSURLErrorDataNotAllowed, NSURLErrorInternationalRoamingOff,
                NSURLErrorCannotFindHost, NSURLErrorTimedOut,
            ].contains(current.code) {
                return true
            }
            next = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    // MARK: - Streaming and Downloaded
    //
    // `podcastShows` holds everything. The Podcasts screen splits it in two with no
    // episode in both: what streams (`streamingPodcastShows`) and what is on the
    // iPhone (`downloadedPodcastShows`). On-device library episodes count as
    // downloaded — they already are.

    /// Subscriptions with their downloaded episodes taken out. A subscription whose
    /// every episode is downloaded has nothing left here and is listed only under
    /// Downloaded until a new episode comes out.
    func streamingPodcastShows() -> [PodcastShow] {
        podcastShows.compactMap { show in
            guard show.isStreamed else { return nil }
            let streaming = show.episodes.filter { podcastDownloads.state(for: $0.id) != .downloaded }
            guard !streaming.isEmpty else { return nil }
            guard streaming.count != show.episodes.count else { return show }
            return PodcastShow(id: show.id, title: show.title, episodes: streaming,
                               feedURL: show.feedURL, artworkURL: show.artworkURL)
        }
    }

    /// Every show with something playable offline: on-device shows whole, and the
    /// downloaded episodes of subscriptions. A podcast that is both on the iPhone and
    /// subscribed to in Lyre is listed once, with an episode saved both ways listed once.
    func downloadedPodcastShows() -> [PodcastShow] {
        var groups: [String: (title: String, episodes: [PodcastEpisode], artworkURL: URL?)] = [:]
        for show in podcastShows {
            let offline = show.isStreamed
                ? show.episodes.filter { podcastDownloads.state(for: $0.id) == .downloaded }
                : show.episodes
            guard !offline.isEmpty else { continue }
            let key = show.title.lowercased()
            var group = groups[key] ?? (show.title, [], nil)
            group.episodes += offline
            group.artworkURL = group.artworkURL ?? show.artworkURL
            groups[key] = group
        }
        return groups.map { key, group in
            // On-device copies come first, so they win when an episode is in both.
            var seen = Set<String>()
            let episodes = group.episodes
                .sorted { ($0.mediaItem != nil ? 0 : 1) < ($1.mediaItem != nil ? 0 : 1) }
                .filter { seen.insert($0.title.lowercased()).inserted }
                .sorted { ($0.published ?? .distantPast) > ($1.published ?? .distantPast) }
            return PodcastShow(id: "downloaded:\(key)", title: group.title, episodes: episodes, artworkURL: group.artworkURL)
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Whether this episode is the one loaded in either player.
    func isCurrentEpisode(_ episode: PodcastEpisode) -> Bool {
        if let currentEpisode { return currentEpisode.id == episode.id }
        guard let item = episode.mediaItem, let current = currentMediaItem else { return false }
        return item.persistentID == current.persistentID
    }

    func isSubscribed(to feedURL: URL) -> Bool {
        podcastSubscriptions.isSubscribed(feedURL)
    }

    /// Fetches a feed and adds it to the subscriptions. Throws when the feed can't be
    /// read, so the caller can say why.
    func subscribe(to feedURL: URL) async throws {
        let feed = try await PodcastDirectory.fetchFeed(feedURL)
        podcastSubscriptions.store(feed, replacing: feedURL)
        publishPodcastShows()
        logger.notice("Subscribed to '\(feed.title)' (\(feed.episodes.count) episodes)")
    }

    func unsubscribe(from feedURL: URL) {
        // Saved episodes of a show the user has dropped would only waste space.
        if let feed = podcastSubscriptions.feeds.first(where: { $0.feedURL == feedURL }) {
            podcastDownloads.remove(episodeIDs: PodcastShow(feed: feed).episodes.map(\.id))
        }
        podcastSubscriptions.remove(feedURL)
        publishPodcastShows()
        logger.notice("Unsubscribed from \(feedURL.absoluteString)")
    }

    /// Subscribes to every feed in an OPML file that isn't subscribed already. Returns
    /// how many were added and how many couldn't be read.
    func importSubscriptions(from feedURLs: [URL]) async -> (added: Int, failed: Int) {
        let new = feedURLs.filter { !podcastSubscriptions.isSubscribed($0) }
        var added = 0, failed = 0
        // A few at a time: an export from another app can list hundreds of shows.
        for batch in stride(from: 0, to: new.count, by: 6).map({ Array(new[$0..<min($0 + 6, new.count)]) }) {
            let feeds = await withTaskGroup(of: FeedShow?.self) { group in
                for url in batch { group.addTask { try? await PodcastDirectory.fetchFeed(url) } }
                var feeds: [FeedShow] = []
                for await feed in group { if let feed { feeds.append(feed) } }
                return feeds
            }
            for feed in feeds { podcastSubscriptions.store(feed) }
            added += feeds.count
            failed += batch.count - feeds.count
            publishPodcastShows()
        }
        logger.notice("OPML import: \(added) added, \(failed) failed, \(feedURLs.count - new.count) already subscribed")
        return (added, failed)
    }

    /// The subscriptions as an OPML document, for moving them to another app.
    func exportSubscriptionsOPML() -> String {
        OPML.document(for: podcastSubscriptions.feeds)
    }

    /// Re-reads every subscribed feed for new episodes, at most every half hour unless
    /// forced. A feed that fails keeps its last copy.
    func refreshSubscribedFeeds(force: Bool = false) async {
        if !force, let lastFeedRefresh, Date().timeIntervalSince(lastFeedRefresh) < Self.feedRefreshInterval { return }
        let urls = podcastSubscriptions.feeds.map(\.feedURL)
        guard !urls.isEmpty else { return }
        lastFeedRefresh = Date()

        let refreshed = await withTaskGroup(of: (URL, FeedShow?).self) { group in
            for url in urls {
                group.addTask { (url, try? await PodcastDirectory.fetchFeed(url)) }
            }
            var results: [(URL, FeedShow)] = []
            for await (url, feed) in group {
                if let feed { results.append((url, feed)) }
            }
            return results
        }
        // A show unsubscribed while its feed was loading stays unsubscribed.
        for (url, feed) in refreshed where podcastSubscriptions.isSubscribed(url) {
            if podcastDownloads.autoDownloadNew { autoDownloadNewEpisodes(of: feed, replacing: url) }
            podcastSubscriptions.store(feed, replacing: url)
        }
        publishPodcastShows()
        logger.info("Refreshed \(refreshed.count) of \(urls.count) podcast feed(s)")
    }

    /// Downloads the episodes a refresh found that weren't in the feed before — at
    /// most a few per show, so a feed that republishes its whole back catalogue can't
    /// fill the phone. Wi‑Fi only.
    private func autoDownloadNewEpisodes(of feed: FeedShow, replacing url: URL) {
        guard let previous = podcastSubscriptions.feeds.first(where: { $0.feedURL == url }) else { return }
        let known = Set(previous.episodes.map(\.guid))
        let fresh = feed.episodes.filter { !known.contains($0.guid) }.prefix(3)
        for episode in fresh {
            podcastDownloads.download(PodcastEpisode(feedEpisode: episode, show: feed), onlyOnWiFi: true)
        }
        if !fresh.isEmpty { logger.info("Auto-downloading \(fresh.count) new episode(s) of '\(feed.title)'") }
    }

    // MARK: - Engine Switching

    private func setupStreamPlayer() {
        streamPlayer.loadPosition = { [weak self] id in self?.podcastSubscriptions.position(for: id) ?? 0 }
        streamPlayer.savePosition = { [weak self] time, id in self?.podcastSubscriptions.setPosition(time, for: id) }
        streamPlayer.onChange = { [weak self] in self?.syncFromStreamPlayer() }
        streamPlayer.rate = podcastRate
        streamPlayer.playbackURL = { [weak self] episode in
            self?.podcastDownloads.localFile(for: episode.id) ?? episode.streamURL
        }
        streamPlayer.onFinish = { [weak self] episode in
            guard let self, self.podcastDownloads.removeAfterPlaying else { return }
            self.podcastDownloads.remove(episode.id)
        }
        streamPlayer.onFailure = { [weak self] _, error in
            self?.playbackNotice = PlaybackNotice(
                text: Self.isOffline(error) ? String(localized: "stream.offline") : String(localized: "stream.failed")
            )
        }
        publishPodcastShows()
    }

    /// Hands playback to the stream engine, pausing the music player.
    private func activateStreamEngine() {
        guard activeEngine != .stream else { return }
        // Switch first, so the music player's pause notification is ignored.
        activeEngine = .stream
        // Streaming needs no library access; don't create the music player just to
        // pause it, which would prompt for access that was skipped.
        if didSetupNotifications { player.pause() }
        currentTrack = nil
        currentMediaItem = nil
    }

    /// Hands playback back to the music player, stopping any stream.
    private func activateLibraryEngine() {
        guard activeEngine != .library else { return }
        activeEngine = .library
        streamPlayer.stop()
        currentEpisode = nil
    }

    /// Mirrors the stream player's state into the published properties.
    private func syncFromStreamPlayer() {
        guard activeEngine == .stream else { return }
        currentEpisode = streamPlayer.current
        duration = streamPlayer.duration
        isPlaying = streamPlayer.isPlaying
        if !isScrubbing { currentTime = streamPlayer.currentTime }
        updateNowPlayingInfoCenter()
    }

    // MARK: - MPMediaItem Lookup (by persistent ID for reliability)

    private nonisolated static func mediaItem(for track: AppTrack) -> MPMediaItem? {
        // Locally-sourced tracks (and MusicKit tracks matched at load time) already
        // carry their item, which is both faster and exact.
        if let item = track.mpItem { return item }

        // Restored from the launch cache: the item is gone but its persistent ID is
        // not, and looking that up is exact where the title match below is not.
        if let persistentID = track.mpPersistentID {
            let query = MPMediaQuery()
            query.addFilterPredicate(MPMediaPropertyPredicate(
                value: NSNumber(value: persistentID),
                forProperty: MPMediaItemPropertyPersistentID
            ))
            if let item = query.items?.first { return item }
        }

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

    /// Starts watching the music player and media library once there is access to
    /// them — at launch for a returning user, or the moment onboarding is granted it.
    private func setupNotificationsIfAuthorized() {
        observeSubscriptionUpdatesIfAuthorized()
        guard !didSetupNotifications, Self.hasAnyLibraryAccess else { return }
        didSetupNotifications = true
        setupNotifications()
    }

    private func setupNotifications() {
        player.beginGeneratingPlaybackNotifications()

        // An untouched player reports `.default` — "whatever the user prefers" — which
        // can mean shuffle is already on before the app has played anything. Pinning
        // both modes to the app's own starting state keeps the first queue playing in
        // the order the Queue screen shows.
        player.shuffleMode = shuffleMode.mpShuffleMode
        player.repeatMode  = repeatMode.mpRepeatMode

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
        // While streaming, the music player's state is not what is playing.
        guard activeEngine == .library else { return }
        isPlaying = (player.playbackState == .playing)
        applyLibraryRate()
        syncPlaybackModesFromPlayer()
        updateNowPlayingInfoCenter()
    }

    /// Reads shuffle and repeat back off the player.
    ///
    /// MediaPlayer handles remote control events for an application player itself, so
    /// these can change without the app asking — from the lock screen, CarPlay or a
    /// headset. Reading them back keeps Now Playing honest, and matters for the queue:
    /// with shuffle on the player picks its own next track rather than the one at the
    /// top of Up Next.
    private func syncPlaybackModesFromPlayer() {
        let playerRepeat  = RepeatMode(mpRepeatMode: player.repeatMode)
        let playerShuffle = ShuffleMode(mpShuffleMode: player.shuffleMode)
        if playerRepeat  != repeatMode  { repeatMode  = playerRepeat }
        if playerShuffle != shuffleMode { shuffleMode = playerShuffle }
    }

    private func updateNowPlayingItem() {
        guard activeEngine == .library else { return }
        currentMediaItem = player.nowPlayingItem
        guard let nowPlaying = player.nowPlayingItem else {
            currentTrack = nil; duration = 0
            // `playbackQueue` is deliberately left alone. The player reports no item
            // both while a new queue is being applied and once the last track ends,
            // and neither is a reason to throw away what the user queued up.
            updateNowPlayingInfoCenter()
            return
        }
        duration = nowPlaying.playbackDuration
#if DEBUG
        // Answers Q3 of the catalogue spike as tracks change, without needing a
        // trigger at the right moment. Delete with the spike.
        logger.notice("""
            Q3 — nowPlayingItem persistentID=\(nowPlaying.persistentID) \
            isCloud=\(nowPlaying.isCloudItem) title=\(nowPlaying.title ?? "nil")
            """)
#endif
        // Advance the queue cursor to whatever is playing now.
        if playbackQueue.advanceCurrent(toPersistentID: nowPlaying.persistentID) {
            queueSettlingUntil = nil
            refillQueueIfNeeded()
        } else if !isQueueSettling {
            // Playback moved to a track outside our queue — started from the Music
            // app, or the system carried on past the end of ours — so the model has
            // to follow rather than keep describing a queue that is no longer playing.
            logger.notice("Playback left the app's queue — resetting the queue model")
            playbackQueue = PlaybackQueue(tracks: [AppTrack(from: nowPlaying)])
        }
        currentTrack = libraryTrack(for: nowPlaying)
        updateNowPlayingInfoCenter()
    }

    /// The library's track for a media item: by persistent ID, then title and artist,
    /// then title alone.
    private func libraryTrack(for item: MPMediaItem) -> AppTrack? {
        songs.first(where: { $0.mpPersistentID == item.persistentID })
            ?? songs.first(where: { $0.title == item.title && $0.artistName == item.artist })
            ?? songs.first(where: { $0.title == item.title })
    }

    // MARK: - Playback Time Updates

    /// Runs the progress ticker only while something is playing.
    ///
    /// It used to start at launch and run until the service was deallocated, waking the
    /// main thread twice a second forever to republish a time that was not moving. That
    /// costs battery for nothing, and it means the app never goes idle — which UI tests
    /// wait for before every single query.
    private func syncPlaybackTimeTicker() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.syncPlaybackTimeTicker() }
            return
        }

        guard isPlaying else {
            playbackTimeUpdateTimer?.invalidate()
            playbackTimeUpdateTimer = nil
            return
        }
        guard playbackTimeUpdateTimer == nil else { return }

        playbackTimeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, !self.isScrubbing else { return }
            let time = self.activeEngine == .stream ? self.streamPlayer.currentTime : self.player.currentPlaybackTime
            // A stream only learns its real duration once it has buffered.
            if self.activeEngine == .stream, self.duration != self.streamPlayer.duration {
                self.duration = self.streamPlayer.duration
            }
            // The timer fires on the main run loop already. Skipping unchanged values
            // keeps a paused-but-ticking edge case from republishing the same time.
            if self.clock.time != time { self.clock.time = time }
        }
    }

    // MARK: - Now Playing Info Center (lockscreen / control center)

    private func updateNowPlayingInfoCenter() {
        if activeEngine == .stream {
            updateNowPlayingInfoCenterForStream()
            return
        }
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

    /// The lock screen for a streamed episode. Nothing fills this in for an AVPlayer,
    /// so the elapsed time is written with the rate and the system extrapolates it.
    private func updateNowPlayingInfoCenterForStream() {
        guard let episode = currentEpisode else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: episode.title,
            MPMediaItemPropertyArtist: episode.showTitle,
            MPMediaItemPropertyAlbumTitle: episode.showTitle,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: streamPlayer.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let artworkURL = episode.artworkURL {
            if let streamArtwork, streamArtwork.url == artworkURL {
                info[MPMediaItemPropertyArtwork] = streamArtwork.artwork
            } else {
                loadStreamArtwork(artworkURL)
            }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadStreamArtwork(_ url: URL) {
        Task { [weak self] in
            let key = LocalArtworkCache.key(url.absoluteString, size: 600)
            guard let image = await LocalArtworkCache.shared.image(from: url, key: key, size: 600) else { return }
            await MainActor.run {
                guard let self else { return }
                self.streamArtwork = (url, MPMediaItemArtwork(boundsSize: image.size) { _ in image })
                self.updateNowPlayingInfoCenter()
            }
        }
    }

    deinit {
        if didSetupNotifications { player.endGeneratingPlaybackNotifications() }
        playbackTimeUpdateTimer?.invalidate()
        subscriptionObserverTask?.cancel()
        subscriptionRetryTask?.cancel()
        if didSetupNotifications { MPMediaLibrary.default().endGeneratingLibraryChangeNotifications() }
        if let o = playbackStateObserver { NotificationCenter.default.removeObserver(o) }
        if let o = nowPlayingObserver    { NotificationCenter.default.removeObserver(o) }
        if let o = libraryChangeObserver { NotificationCenter.default.removeObserver(o) }
    }
}
