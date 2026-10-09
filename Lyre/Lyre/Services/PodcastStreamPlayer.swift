//
//  PodcastStreamPlayer.swift
//  Lyre
//

import AVFoundation
import MediaPlayer
import OSLog

private let logger = Logger(subsystem: "com.pinkhatcreations.lyreapp", category: "PodcastStream")

// MARK: - PodcastStreamPlayer
//
// Streams episodes of subscribed shows straight from their feed's audio URLs with
// AVPlayer, which starts playing as soon as enough has buffered.
//
// Everything else in the app plays through MPMusicPlayerController, which can only
// play media-library and Apple Music items — never a URL — so streamed episodes need
// this second engine. MusicService decides which engine is active and routes the
// transport controls; this type only plays.
//
// Unlike the application queue player, which MediaPlayer drives itself, an AVPlayer
// gets nothing from the lock screen, Control Center or headphones unless the app
// handles MPRemoteCommandCenter. Those handlers are registered only while this player
// is in use and removed when it stops, so they never sit in front of the music player.
//
// Main thread only.

final class PodcastStreamPlayer {
    /// Called whenever the episode, play state or duration changes.
    var onChange: (() -> Void)?
    /// Reads and writes how far into an episode the user got.
    var loadPosition: (String) -> TimeInterval = { _ in 0 }
    var savePosition: (TimeInterval, String) -> Void = { _, _ in }
    /// Where to play an episode from: its downloaded file when there is one.
    var playbackURL: (PodcastEpisode) -> URL? = { $0.streamURL }
    /// Called when an episode plays to its end.
    var onFinish: (PodcastEpisode) -> Void = { _ in }
    /// Called when an episode can't be played — most often, no connection.
    var onFailure: (PodcastEpisode, Error?) -> Void = { _, _ in }

    private(set) var episodes: [PodcastEpisode] = []
    private(set) var index = 0
    private(set) var isPlaying = false

    var current: PodcastEpisode? {
        episodes.indices.contains(index) ? episodes[index] : nil
    }

    var currentTime: TimeInterval {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : 0
    }

    /// The item's real duration once known; the feed's figure until then.
    var duration: TimeInterval {
        if let seconds = player.currentItem?.duration.seconds, seconds.isFinite, seconds > 0 {
            return seconds
        }
        return current?.duration ?? 0
    }

    static let skipForwardInterval: TimeInterval = 30
    static let skipBackwardInterval: TimeInterval = 15

    /// The episodes still to come after the one playing.
    var upcoming: ArraySlice<PodcastEpisode> {
        episodes.indices.contains(index) ? episodes[(index + 1)...] : []
    }

    /// The speed episodes play at, 1 for normal. Speech keeps its pitch.
    var rate: Float = 1 {
        didSet {
            player.defaultRate = rate
            if player.rate != 0 { player.rate = rate }
        }
    }

    private let player = AVPlayer()
    private var statusObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var periodicObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var remoteCommandTargets: [(MPRemoteCommand, Any)] = []

    init() {
        player.automaticallyWaitsToMinimizeStalling = true

        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            DispatchQueue.main.async {
                guard let self, self.isPlaying != playing else { return }
                self.isPlaying = playing
                if !playing { self.saveCurrentPosition() }
                self.onChange?()
            }
        }

        // Saves the position now and then, so a crash or a killed app loses little.
        periodicObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 15, preferredTimescale: 1), queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveCurrentPosition() }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, (note.object as? AVPlayerItem) === self.player.currentItem else { return }
                self.episodeDidFinish()
            }
        }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map(AVAudioSession.InterruptionOptions.init(rawValue:))
            let ended = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.ended.rawValue
            MainActor.assumeIsolated {
                // AVPlayer pauses itself when interrupted; resume only if asked to.
                guard let self, ended, options?.contains(.shouldResume) == true, self.current != nil else { return }
                self.resume()
            }
        }
    }

    // MARK: - Playback

    func play(_ episodes: [PodcastEpisode], startingAt index: Int) {
        let playable = episodes.filter { $0.streamURL != nil }
        guard episodes.indices.contains(index),
              let start = playable.firstIndex(of: episodes[index]) else { return }
        saveCurrentPosition()
        self.episodes = playable
        enableRemoteCommands()
        load(start)
    }

    func pause() {
        player.pause()
    }

    func resume() {
        guard current != nil else { return }
        activateAudioSession()
        player.play()
    }

    /// Stops and forgets the episode, releasing the lock screen controls. Called when
    /// the music player takes over.
    func stop() {
        guard current != nil else { return }
        saveCurrentPosition()
        player.pause()
        player.replaceCurrentItem(with: nil)
        itemStatusObservation = nil
        episodes = []
        index = 0
        isPlaying = false
        disableRemoteCommands()
        onChange?()
    }

    func skipToNext() {
        guard index + 1 < episodes.count else { return }
        saveCurrentPosition()
        load(index + 1)
    }

    /// Restarts the episode, or goes back one when already near its start.
    func skipToPrevious() {
        if currentTime > 3 || index == 0 {
            seek(to: 0)
        } else {
            saveCurrentPosition()
            load(index - 1)
        }
    }

    func seek(to time: TimeInterval) {
        let clamped = max(0, duration > 0 ? min(time, duration - 1) : time)
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        onChange?()
    }

    // MARK: - Private

    private func load(_ newIndex: Int) {
        guard let episode = episodes.indices.contains(newIndex) ? episodes[newIndex] : nil,
              let url = playbackURL(episode) else { return }
        index = newIndex
        logger.info("Playing '\(episode.title)' from \(url.isFileURL ? "download" : url.absoluteString)")

        let item = AVPlayerItem(url: url)
        // Keeps a voice's pitch at any speed, without the warble music settings give it.
        item.audioTimePitchAlgorithm = .timeDomain
        // Duration only becomes known once the item is ready; report it then.
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let failed = item.status == .failed
            let error = item.error
            DispatchQueue.main.async {
                guard let self else { return }
                if failed, self.player.currentItem === item {
                    logger.error("Stream failed: \(error?.localizedDescription ?? "unknown error")")
                    self.player.pause()
                    self.isPlaying = false
                    self.onFailure(episode, error)
                }
                self.onChange?()
            }
        }
        player.replaceCurrentItem(with: item)

        let saved = loadPosition(episode.id)
        if saved > 5, episode.duration == 0 || saved < episode.duration - 15 {
            player.seek(to: CMTime(seconds: saved, preferredTimescale: 600))
        }

        activateAudioSession()
        player.play()
        onChange?()
    }

    private func episodeDidFinish() {
        if let current {
            savePosition(0, current.id)
            onFinish(current)
        }
        if index + 1 < episodes.count {
            load(index + 1)
        } else {
            isPlaying = false
            onChange?()
        }
    }

    private func saveCurrentPosition() {
        guard let current else { return }
        let time = currentTime
        // Within the last half minute counts as finished.
        let finished = duration > 0 && time > duration - 30
        savePosition(finished ? 0 : time, current.id)
    }

    private func activateAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
        } catch {
            logger.error("Could not activate the audio session: \(error.localizedDescription)")
        }
    }

    // MARK: - Remote Commands

    private func enableRemoteCommands() {
        guard remoteCommandTargets.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()

        center.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipForwardInterval)]
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipBackwardInterval)]

        func handle(_ command: MPRemoteCommand, _ action: @escaping (MPRemoteCommandEvent) -> Void) {
            command.isEnabled = true
            let target = command.addTarget { event in
                MainActor.assumeIsolated { action(event) }
                return .success
            }
            remoteCommandTargets.append((command, target))
        }

        handle(center.playCommand)  { [weak self] _ in self?.resume() }
        handle(center.pauseCommand) { [weak self] _ in self?.pause() }
        handle(center.togglePlayPauseCommand) { [weak self] _ in
            guard let self else { return }
            self.isPlaying ? self.pause() : self.resume()
        }
        handle(center.skipForwardCommand) { [weak self] _ in
            guard let self else { return }
            self.seek(to: self.currentTime + Self.skipForwardInterval)
        }
        handle(center.skipBackwardCommand) { [weak self] _ in
            guard let self else { return }
            self.seek(to: self.currentTime - Self.skipBackwardInterval)
        }
        handle(center.changePlaybackPositionCommand) { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return }
            self?.seek(to: event.positionTime)
        }
    }

    private func disableRemoteCommands() {
        for (command, target) in remoteCommandTargets {
            command.removeTarget(target)
        }
        remoteCommandTargets = []
    }

    deinit {
        if let periodicObserver { player.removeTimeObserver(periodicObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    }
}
