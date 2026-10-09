//
//  ScrollWheelView.swift
//  Lyre
//
//  Created by Daniel Buzlea on 5/13/26.
//

import SwiftUI
import AudioToolbox
import MediaPlayer
import OSLog

private let logger = Logger(subsystem: "com.pinkhatcreations.lyreapp", category: "ScrollWheel")

// MARK: - Scroll Wheel
//
// ScrollWheelView renders the circular input control and routes all gesture events
// for the Lyre interface. The ring supports two interaction modes:
//
// Scroll mode — the user drags around the ring to move the selection cursor.
//   Angular displacement is tracked in `accumulatedRotation`. Once it exceeds
//   `scrollThreshold`, the cursor moves by 1–5 steps depending on `angularVelocity`
//   (faster spin = more steps per threshold crossing). An exponential moving
//   average smooths the velocity so rapid direction changes don't over-accelerate.
//
// Button tap mode — a touch that never exceeds `scrollCommitAngle` (5°) of angular
//   movement is treated as a tap on whichever of the four cardinal zones the touch
//   started in (MENU/PLAY/PREV/NEXT), resolved by WheelTapZone.
//
// The intent is disambiguated lazily: the gesture starts as a potential tap, and
// only commits to scroll mode once total angular delta crosses the threshold. This
// prevents accidental scrolls when tapping near a button position.
//
// The center circle has its own gesture layer, separate from the ring, which splits
// the same two ways: a tap selects (handleSelect), while a rightward swipe adds the
// highlighted song to the queue (handleCenterSwipeRight). It uses the same lazy
// commit as the ring — the touch is a tap until it travels far enough sideways — so
// a slightly sloppy press never queues a song by accident.
//
// Now Playing scrubbing — when scroll mode commits while the Now Playing screen is
//   active, each scroll step seeks ±5 seconds through the track instead of moving
//   a list cursor. `musicService.startScrubbing()` is called when mode commits so
//   the UI can show the scrub indicator dot on the progress bar.
//
// Haptics and click sound fire on every cursor step (medium impact + system sound
// 1104). A different "bump" (rigid, low intensity) fires at list boundaries to give
// physical feedback that the edge has been reached.
//
// Visual extras — a radial-gradient "imprint" follows the touch point on the ring
// surface (like pressing a physical button). Button labels dim slightly when their
// zone is pressed.
struct ScrollWheelView: View {
    @Binding var rotation: Double
    @State private var lastRotation: Double = 0
    @State private var isDragging = false
    @State private var accumulatedRotation: Double = 0
    @State private var lastHapticStep: Int = 0
    @State private var scrollCommitted: Bool = false
    @State private var touchStartAngle: Double = 0
    @State private var totalAbsoluteAngularDelta: Double = 0
    @State private var lastRotationTime: Date = Date()
    @State private var angularVelocity: Double = 0
    /// Generators for the per-step feedback, created once and prepared at the start of
    /// each touch. A fresh generator per step paid the Taptic Engine's warm-up on every
    /// tick, which is also what made some ticks land late.
    @State private var haptics = WheelHaptics()

    // Button press states for visual feedback
    @State private var isMenuPressed = false
    @State private var isPlayPressed = false
    @State private var isPreviousPressed = false
    @State private var isNextPressed = false
    @State private var isSelectPressed = false

    // Center button gesture state (tap vs. swipe-right disambiguation)
    @State private var isCenterDragging = false
    @State private var centerSwipeFired = false

    // Touch imprint effect
    @State private var touchLocation: CGPoint = .zero
    @State private var imprintOpacity: Double = 0

    let musicService: MusicService
    let themeSettings: ThemeSettings
    @Binding var currentScreen: LyreScreen
    @Binding var navigationStack: [LyreScreen]
    @Binding var selectionMemory: [LyreScreen: SelectionState]
    @Binding var menuSelection: Int
    @Binding var songSelection: Int
    @Binding var detailSelection: Int
    /// Up Next offset of the row being carried on the Queue screen; nil while browsing.
    @Binding var queueMoveOffset: Int?
    let isHoldEnabled: Bool
    let onInteraction: () -> Void
    /// Shows a short message on the screen — the wheel has no display of its own, so
    /// this is how a queue action is confirmed or a refusal to play is explained.
    let onBanner: (String) -> Void
    /// Opens the sheet for finding and subscribing to podcasts.
    let onOpenPodcastSearch: () -> Void
    /// The Search screen's results, in the order it lists them.
    var searchResults: [LibrarySearchResult] = []

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true

    // Constants for wheel interaction
    private let hapticStepSize: Double = 20.0 // Degrees per haptic tick
    private var scrollThreshold: Double { themeSettings.scrollSensitivity.scrollThreshold }
    private let scrubStep: Double = 5.0 // Seconds to seek per scroll tick in Now Playing
    // Angular movement (in degrees) before a touch is classified as a scroll rather than a tap.
    // Under this threshold the gesture ends as a tap; over it the ring enters scroll mode.
    private let scrollCommitAngle: Double = 5.0
    // Sideways travel (in points) before a press on the center button is treated as a
    // swipe rather than a tap.
    private let centerSwipeCommitDistance: CGFloat = 26.0
    
    var body: some View {
        ZStack {
            // Outer circle (metallic look) - the touch-sensitive ring
            Circle()
                .fill(
                    RadialGradient(
                        colors: themeSettings.currentTheme.wheelOuterGradientColors,
                        center: .center,
                        startRadius: 70,
                        endRadius: 140
                    )
                )
                .overlay {
                    Circle()
                        .stroke(themeSettings.currentTheme.wheelStrokeColor, lineWidth: 2)
                }
                .overlay {
                    Circle()
                        .stroke(themeSettings.currentTheme.wheelStrokeColor.opacity(0.5), lineWidth: 1)
                        .padding(2)
                }
                .overlay {
                    // Top-left specular polish highlight on the wheel ring
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white.opacity(0.22), .clear],
                                center: UnitPoint(x: 0.3, y: 0.2),
                                startRadius: 0,
                                endRadius: 125
                            )
                        )
                        .blendMode(.overlay)
                        .allowsHitTesting(false)
                }

            // Center circle button (visual)
            Circle()
                .fill(
                    RadialGradient(
                        colors: themeSettings.currentTheme.wheelCenterGradientColors.map { color in
                            isSelectPressed ? color.opacity(0.8) : color
                        },
                        center: .center,
                        startRadius: 0,
                        endRadius: 60
                    )
                )
                .frame(width: 120, height: 120)
                .overlay {
                    Circle()
                        .stroke(themeSettings.currentTheme.wheelCenterStrokeColor, lineWidth: 1)
                        .frame(width: 120, height: 120)
                }
                .shadow(color: .black.opacity(isSelectPressed ? 0.1 : 0.3), radius: 4, x: 0, y: 2)
            
            // Ring gesture overlay — handles both scrolling and ring-button taps
            // via unified intent detection (see handleWheelRotation / handleWheelGestureEnded).
            Circle()
                .stroke(Color.clear, lineWidth: 70)
                .frame(width: 210, height: 210)
                .contentShape(Circle().stroke(lineWidth: 70))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            handleWheelRotation(value: value)
                        }
                        .onEnded { _ in
                            handleWheelGestureEnded()
                        }
                )
                // VoiceOver can't spin a ring, so the wheel is an adjustable element:
                // swipe up or down to scroll (or scrub, on Now Playing), with the four
                // ring buttons as named actions. The value reads out what is now
                // highlighted, so each swipe says where it landed.
                .accessibilityElement()
                .accessibilityLabel(String(localized: "wheel.a11y.label"))
                .accessibilityValue(accessibilitySelection)
                .accessibilityHint(String(localized: "wheel.a11y.hint"))
                .accessibilityAdjustableAction { direction in
                    guard !isHoldEnabled else { return }
                    onInteraction()
                    switch direction {
                    case .increment: scrollDown()
                    case .decrement: scrollUp()
                    @unknown default: break
                    }
                }
                .accessibilityAction(named: Text(String(localized: "wheel.menu"))) { accessibilityTap(.menu) }
                .accessibilityAction(named: Text(String(localized: "wheel.playPause"))) { accessibilityTap(.playPause) }
                .accessibilityAction(named: Text(String(localized: "wheel.previous"))) { accessibilityTap(.previous) }
                .accessibilityAction(named: Text(String(localized: "wheel.next"))) { accessibilityTap(.next) }

            // Tactile ring imprint — blends with the ring surface at the touch point
            Canvas { context, _ in
                guard imprintOpacity > 0 else { return }
                // Gesture view (210×210) is centered inside this 280×280 ZStack → offset by 35 pts
                let center = CGPoint(x: touchLocation.x + 35, y: touchLocation.y + 35)
                let r: CGFloat = 55
                let stops: [Gradient.Stop] = [
                    .init(color: .black.opacity(0.45), location: 0),
                    .init(color: .black.opacity(0.12), location: 0.38),
                    .init(color: .white.opacity(0.28), location: 0.62),
                    .init(color: .white.opacity(0.05), location: 0.85),
                    .init(color: .clear, location: 1.0)
                ]
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                    with: .radialGradient(Gradient(stops: stops), center: center, startRadius: 0, endRadius: r)
                )
            }
            .blendMode(.overlay)
            .opacity(imprintOpacity)
            .allowsHitTesting(false)

            // Button labels (non-interactive visuals — accessibility handled on the wheel gesture layer)
            // A generic menu glyph rather than a wordmark, so the wheel reads as
            // our own hardware rather than a recreation of someone else's.
            VStack(spacing: 2) {
                Image(systemName: "line.horizontal.3")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(isMenuPressed ? themeSettings.currentTheme.wheelButtonTextColor.opacity(0.9) : themeSettings.currentTheme.wheelButtonTextColor)
            .offset(y: -100)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            
            VStack(spacing: 2) {
                Image(systemName: musicService.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text(musicService.isPlaying ? "PAUSE" : "PLAY")
                    .font(.system(size: 8, weight: .semibold, design: .default))
                    .tracking(0.5)
            }
            .foregroundStyle(isPlayPressed ? themeSettings.currentTheme.wheelButtonTextColor.opacity(0.9) : themeSettings.currentTheme.wheelButtonTextColor)
            .offset(y: 100)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            
            VStack(spacing: 2) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("PREV")
                    .font(.system(size: 7, weight: .semibold, design: .default))
                    .tracking(0.3)
            }
            .foregroundStyle(isPreviousPressed ? themeSettings.currentTheme.wheelButtonTextColor.opacity(0.9) : themeSettings.currentTheme.wheelButtonTextColor)
            .offset(x: -100)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            
            VStack(spacing: 2) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("NEXT")
                    .font(.system(size: 7, weight: .semibold, design: .default))
                    .tracking(0.3)
            }
            .foregroundStyle(isNextPressed ? themeSettings.currentTheme.wheelButtonTextColor.opacity(0.9) : themeSettings.currentTheme.wheelButtonTextColor)
            .offset(x: 100)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            
            // Center select button — a gesture layer rather than a Button so a tap and
            // a rightward swipe (add to queue) can be told apart on the same surface.
            Circle()
                .fill(Color.clear)
                .frame(width: 110, height: 110)
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { handleCenterDragChanged(value: $0) }
                        .onEnded { handleCenterDragEnded(value: $0) }
                )
                .accessibilityElement()
                .accessibilityLabel("Select")
                .accessibilityHint("Activate the current menu item. Swipe right to add the highlighted song to the queue")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { handleSelect() }
                .accessibilityAction(named: "Add to Queue") { handleCenterSwipeRight() }
        }
        .frame(width: 280, height: 280)
    }
    
    private func handleWheelRotation(value: DragGesture.Value) {
        if isHoldEnabled { return }
        onInteraction()

        let center = CGPoint(x: 105, y: 105)
        let vector = CGVector(
            dx: value.location.x - center.x,
            dy: value.location.y - center.y
        )

        var angle = atan2(vector.dy, vector.dx) * 180 / .pi
        if angle < 0 { angle += 360 }

        if !isDragging {
            isDragging = true
            lastRotation = angle
            touchStartAngle = angle
            accumulatedRotation = 0
            totalAbsoluteAngularDelta = 0
            scrollCommitted = false
            lastHapticStep = 0
            angularVelocity = 0
            lastRotationTime = Date()
            haptics.prepare()
            // Show visual press feedback for the button zone the touch started in
            updatePressedState(zone: WheelTapZone(angle: angle))
            touchLocation = value.location
            withAnimation(.easeIn(duration: 0.06)) { imprintOpacity = 1 }
            return
        }

        var delta = angle - lastRotation
        if delta > 180 { delta -= 360 }
        else if delta < -180 { delta += 360 }

        totalAbsoluteAngularDelta += abs(delta)

        // Once angular movement passes the commit threshold, lock in scroll mode.
        // This prevents accidental scrolls when tapping near a button position.
        if !scrollCommitted && totalAbsoluteAngularDelta >= scrollCommitAngle {
            scrollCommitted = true
            accumulatedRotation = 0
            lastHapticStep = 0
            clearPressedStates()
            if case .nowPlaying = currentScreen {
                musicService.startScrubbing()
            }
        }

        guard scrollCommitted else {
            lastRotation = angle
            return
        }

        let now = Date()
        let timeDelta = now.timeIntervalSince(lastRotationTime)
        lastRotationTime = now
        if timeDelta > 0 && timeDelta < 0.15 {
            let instant = abs(delta) / timeDelta
            angularVelocity = angularVelocity * 0.6 + instant * 0.4
        } else {
            angularVelocity = 0
        }

        accumulatedRotation += delta

        let currentStep = Int(abs(accumulatedRotation) / hapticStepSize)
        if currentStep > lastHapticStep {
            haptics.tick.impactOccurred(intensity: 0.6)
            haptics.tick.prepare()
            lastHapticStep = currentStep
        }

        if abs(accumulatedRotation) >= scrollThreshold {
            let steps = scrollSteps(for: angularVelocity)
            for _ in 0..<steps {
                if accumulatedRotation > 0 {
                    scrollDown()
                } else {
                    scrollUp()
                }
            }
            accumulatedRotation = 0
            lastHapticStep = 0
        }

        touchLocation = value.location
        lastRotation = angle
    }

    private func handleWheelGestureEnded() {
        withAnimation(.easeOut(duration: 0.35)) { imprintOpacity = 0 }
        defer {
            isDragging = false
            accumulatedRotation = 0
            scrollCommitted = false
            totalAbsoluteAngularDelta = 0
            angularVelocity = 0
            clearPressedStates()
        }

        if scrollCommitted {
            if case .nowPlaying = currentScreen {
                musicService.stopScrubbing()
            }
        } else if isDragging {
            // Angular movement never exceeded commit threshold — treat as a tap
            // on whichever button zone the touch started in.
            fireTap(zone: WheelTapZone(angle: touchStartAngle))
        }
    }

    // MARK: - Center Button Gesture

    private func handleCenterDragChanged(value: DragGesture.Value) {
        if isHoldEnabled { return }

        if !isCenterDragging {
            isCenterDragging = true
            centerSwipeFired = false
            isSelectPressed = true
            onInteraction()
        }

        guard !centerSwipeFired else { return }

        // A clearly rightward drag is "add to queue". Requiring the horizontal
        // component to dominate keeps a finger sliding off the button diagonally from
        // counting as a swipe.
        if value.translation.width >= centerSwipeCommitDistance,
           abs(value.translation.width) > abs(value.translation.height) {
            centerSwipeFired = true
            isSelectPressed = false
            handleCenterSwipeRight()
        }

        // And a clearly leftward one is "play next".
        if value.translation.width <= -centerSwipeCommitDistance,
           abs(value.translation.width) > abs(value.translation.height) {
            centerSwipeFired = true
            isSelectPressed = false
            handleCenterSwipeLeft()
        }
    }

    private func handleCenterDragEnded(value: DragGesture.Value) {
        defer {
            isCenterDragging = false
            centerSwipeFired = false
            isSelectPressed = false
        }
        if isHoldEnabled || centerSwipeFired { return }

        // Only a touch that stayed put counts as a press; anything else was a drag
        // that never became a swipe, and does nothing.
        if abs(value.translation.width) < centerSwipeCommitDistance,
           abs(value.translation.height) < centerSwipeCommitDistance {
            handleSelect()
        }
    }

    // MARK: - Queue Actions

    /// Swiping right on the center button adds whatever the highlighted row stands for
    /// to the end of the queue, and swiping left plays it next: a song on a song list, a
    /// whole album or playlist on the collection lists. On the Queue screen a right swipe
    /// drops the row from the queue instead.
    ///
    /// Podcast episodes never join the queue, here or in any other player: a swipe right
    /// on a streamed episode saves it for offline listening instead, or undoes that.
    private func handleCenterSwipeRight() { handleCenterSwipe(placement: .last) }
    private func handleCenterSwipeLeft() { handleCenterSwipe(placement: .next) }

    private func handleCenterSwipe(placement: QueuePlacement) {
        if isHoldEnabled { return }
        onInteraction()

        switch currentScreen {
        case .songs:
            queueSong(from: musicService.songs, at: songSelection, placement: placement)
        case .recentlyAdded:
            queueSong(from: musicService.recentlyAdded, at: songSelection, placement: placement)
        case .recentlyPlayed:
            queueSong(from: musicService.recentlyPlayed, at: songSelection, placement: placement)

        case .albums:
            guard musicService.albums.indices.contains(menuSelection) else { break }
            let album = musicService.albums[menuSelection]
            queueCollection(named: album.title, placement: placement) { await musicService.loadTracks(for: album) }

        case .playlists:
            let playlists = Array(musicService.playlists)
            guard playlists.indices.contains(menuSelection) else { break }
            let playlist = playlists[menuSelection]
            queueCollection(named: playlist.name, placement: placement) { await musicService.loadTracks(for: playlist) }

        // On the Play and Shuffle rows of a detail list the swipe queues the whole
        // collection, the same as it does from the collection list.
        case .albumDetail(let album) where detailSelection < PlayShuffleRows.count:
            queueCollection(named: album.title, placement: placement) { await musicService.loadTracks(for: album) }
        case .playlistDetail(let playlist) where detailSelection < PlayShuffleRows.count:
            queueCollection(named: playlist.name, placement: placement) { await musicService.loadTracks(for: playlist) }
        case .podcastDetail where detailSelection < PlayShuffleRows.count:
            refuseEpisodes()

        case .albumDetail(let album):
            // The detail views load their own tracks, so the list has to be resolved
            // again here; both calls hit the same cached/preloaded data.
            let index = detailSelection - PlayShuffleRows.count
            Task {
                let tracks = await musicService.loadTracks(for: album)
                await MainActor.run { queueSong(from: tracks, at: index, placement: placement) }
            }
        case .playlistDetail(let playlist):
            let index = detailSelection - PlayShuffleRows.count
            Task {
                let tracks = await musicService.loadTracks(for: playlist)
                await MainActor.run { queueSong(from: tracks, at: index, placement: placement) }
            }
        case .podcastDetail(let show):
            let index = detailSelection - PlayShuffleRows.count
            guard show.episodes.indices.contains(index) else {
                bumpFeedback()
                break
            }
            let episode = show.episodes[index]
            if placement == .last, episode.streamURL != nil {
                toggleDownload(of: episode)
            } else {
                refuseEpisodes()
            }
        case .search:
            guard searchResults.indices.contains(menuSelection) else {
                bumpFeedback()
                break
            }
            switch searchResults[menuSelection] {
            case .song:
                queueSong(from: searchResults.compactMap(\.song),
                          at: searchResults[..<menuSelection].filter { $0.song != nil }.count,
                          placement: placement)
            case .album(let album):
                queueCollection(named: album.title, placement: placement) { await musicService.loadTracks(for: album) }
            case .playlist(let playlist):
                queueCollection(named: playlist.name, placement: placement) { await musicService.loadTracks(for: playlist) }
            case .artist, .podcast:
                bumpFeedback()
            }

        case .queue:
            // Right takes the song out; left plays it now, as tapping a song in Up Next
            // does on the other players. A song being carried is put down first.
            if queueMoveOffset != nil {
                bumpFeedback()
            } else if placement == .last, musicService.canEditUpcoming {
                removeSelectedFromQueue()
            } else if placement == .next, musicService.upcoming.indices.contains(songSelection) {
                successFeedback()
                musicService.playUpcoming(at: songSelection)
            } else {
                bumpFeedback()
            }
        default:
            // Nothing queueable on this screen.
            bumpFeedback()
        }
    }

    /// Episodes play from their show; they don't go in the queue.
    private func refuseEpisodes() {
        bumpFeedback()
        onBanner(String(localized: "queue.episodes"))
    }

    private func queueSong(from tracks: [AppTrack], at index: Int, placement: QueuePlacement) {
        guard tracks.indices.contains(index) else {
            bumpFeedback()
            return
        }
        let track = tracks[index]
        Task {
            let outcome = await musicService.addToQueue(track, placement: placement)
            await MainActor.run { report(outcome, name: track.title, requested: 1, placement: placement) }
        }
    }

    private func toggleDownload(of episode: PodcastEpisode) {
        let downloads = musicService.podcastDownloads
        switch downloads.state(for: episode.id) {
        case nil:
            downloads.download(episode)
            successFeedback()
            onBanner(String(format: String(localized: "download.started"), episode.title))
        case .downloading:
            downloads.remove(episode.id)
            bumpFeedback()
            onBanner(String(localized: "download.cancelled"))
        case .downloaded:
            downloads.remove(episode.id)
            bumpFeedback()
            onBanner(String(format: String(localized: "download.removed"), episode.title))
        }
    }

    /// Queues a whole album or playlist. The contents are loaded first — a collection
    /// row knows its name but not its tracks — and the banner reports a partial add
    /// rather than letting a half-queued album look complete.
    private func queueCollection(named name: String, placement: QueuePlacement,
                                 tracks load: @escaping () async -> [AppTrack]) {
        Task {
            let tracks = await load()
            let outcome = await musicService.addToQueue(tracks: tracks, placement: placement)
            await MainActor.run {
                report(outcome, name: name, requested: tracks.count, placement: placement, isCollection: true)
            }
        }
    }

    /// Says what a queue add did, in the words every player uses.
    private func report(_ outcome: QueueAddOutcome, name: String, requested: Int,
                        placement: QueuePlacement, isCollection: Bool = false) {
        if outcome.succeeded { successFeedback() } else { bumpFeedback() }
        onBanner(outcome.message(name: name, requested: requested, placement: placement,
                                 isCollection: isCollection))
    }

    private func removeSelectedFromQueue() {
        guard let removed = musicService.removeFromQueue(at: songSelection) else {
            bumpFeedback()
            return
        }
        // A carried row is no longer where the user left it, so drop it.
        queueMoveOffset = nil
        // Keep the cursor on the row that slid up into the removed one's place.
        songSelection = min(songSelection, max(0, musicService.upNext.count - 1))
        successFeedback()
        onBanner(String(format: String(localized: "queue.removed"), removed.title))
    }

    private func clearQueue() {
        let removed = musicService.clearQueue()
        guard removed > 0 else {
            bumpFeedback()
            return
        }
        songSelection = 0
        successFeedback()
        onBanner(String(localized: "queue.cleared"))
    }

    /// Moves the carried row by one position, returning false at the ends of the list.
    private func moveCarriedQueueRow(by delta: Int) -> Bool {
        guard let origin = queueMoveOffset else { return false }
        let destination = origin + delta
        guard (0..<musicService.upNext.count).contains(destination) else { return false }
        musicService.reorderUpNext(from: origin, to: destination)
        queueMoveOffset = destination
        songSelection = destination
        return true
    }

    /// Puts the carried row down and commits its new position to the player.
    private func dropCarriedQueueRow() {
        guard let offset = queueMoveOffset else { return }
        queueMoveOffset = nil
        musicService.commitQueueMove(to: offset)
        onBanner(String(localized: "queue.reordered"))
    }

    private func successFeedback() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }

    /// The same "you've hit a wall" tap used at the ends of a list.
    private func bumpFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred(intensity: 0.4)
    }

    private enum WheelTapZone {
        case menu, playPause, previous, next

        // Angle convention: 0° = right (3 o'clock), 90° = bottom, 180° = left, 270° = top
        init(angle: Double) {
            switch angle {
            case 225..<315: self = .menu       // top  (~270°)
            case 45..<135:  self = .playPause  // bottom (~90°)
            case 135..<225: self = .previous   // left  (~180°)
            default:        self = .next       // right (~0°/360°)
            }
        }
    }

    private func updatePressedState(zone: WheelTapZone) {
        isMenuPressed     = zone == .menu
        isPlayPressed     = zone == .playPause
        isPreviousPressed = zone == .previous
        isNextPressed     = zone == .next
    }

    private func clearPressedStates() {
        isMenuPressed     = false
        isPlayPressed     = false
        isPreviousPressed = false
        isNextPressed     = false
    }

    private func openPodcastShow(_ show: PodcastShow) {
        open(.podcastDetail(show))
    }

    /// Goes forward to `target`, so Menu comes back here.
    private func open(_ target: LyreScreen) {
        saveSelectionState()
        navigationStack.append(currentScreen)
        restoreSelectionState(for: target)
        withAnimation(.easeInOut(duration: 0.15)) { currentScreen = target }
    }

    private func accessibilityTap(_ zone: WheelTapZone) {
        guard !isHoldEnabled else { return }
        onInteraction()
        fireTap(zone: zone)
    }

    // MARK: - VoiceOver Selection

    /// What the wheel has highlighted on the current screen, for VoiceOver. Screens whose
    /// rows are loaded by their own view (album, playlist and artist contents) can only
    /// be described by position.
    private var accessibilitySelection: String {
        func pick(_ items: [String], _ index: Int) -> String {
            items.indices.contains(index) ? items[index] : ""
        }
        func track(_ tracks: [AppTrack], _ index: Int) -> String {
            guard tracks.indices.contains(index) else { return "" }
            let track = tracks[index]
            return track.artistName.isEmpty ? track.title : "\(track.title), \(track.artistName)"
        }
        func detailRow(_ row: Int, item: String) -> String {
            switch row {
            case PlayShuffleRows.playOffset:    return String(localized: "detail.play")
            case PlayShuffleRows.shuffleOffset: return String(localized: "detail.shuffle")
            default: return String(format: String(localized: "wheel.a11y.row"), item, row - PlayShuffleRows.count + 1)
            }
        }

        switch currentScreen {
        case .menu:
            return pick(MainMenuView.items, menuSelection)
        case .songs:
            return track(musicService.songs, songSelection)
        case .recentlyAdded:
            return track(musicService.recentlyAdded, songSelection)
        case .recentlyPlayed:
            return track(musicService.recentlyPlayed, songSelection)
        case .queue:
            return songSelection == QueueView.clearRowOffset
                ? String(localized: "queue.clear")
                : track(musicService.upcoming, songSelection)
        case .albums:
            return pick(musicService.albums.map(\.title), menuSelection)
        case .artists:
            return pick(musicService.artists.map(\.name), menuSelection)
        case .playlists:
            return pick(musicService.playlists.map(\.name), menuSelection)
        case .podcasts:
            switch menuSelection {
            case PodcastListView.searchRow:     return String(localized: "podcasts.search")
            case PodcastListView.downloadedRow: return String(localized: "podcasts.downloaded")
            default: return pick(musicService.streamingPodcastShows().map(\.title), menuSelection - PodcastListView.fixedRows)
            }
        case .downloadedPodcasts:
            return pick(musicService.downloadedPodcastShows().map(\.title), menuSelection)
        case .search:
            guard searchResults.indices.contains(menuSelection) else { return "" }
            let result = searchResults[menuSelection]
            return "\(result.title), \(result.subtitle)"
        case .podcastDetail(let show):
            return detailSelection < PlayShuffleRows.count
                ? detailRow(detailSelection, item: "")
                : pick(show.episodes.map(\.title), detailSelection - PlayShuffleRows.count)
        case .albumDetail, .playlistDetail:
            return detailRow(detailSelection, item: String(localized: "wheel.a11y.track"))
        case .artistDetail:
            return String(format: String(localized: "wheel.a11y.row"), String(localized: "wheel.a11y.album"), detailSelection + 1)
        case .settings:
            return pick(SettingsView.items, menuSelection)
        case .themeSelection:
            return pick(LyreThemeStyle.allCases.map(\.rawValue), menuSelection)
        case .screenSizeSelection:
            return menuSelection == 0
                ? String(localized: "onboarding.size.auto")
                : pick(ScreenSize.allCases.map(\.rawValue), menuSelection - 1)
        case .highlightColorSelection:
            return menuSelection == 0
                ? String(localized: "settings.highlightColor.default")
                : pick(LyreColors.finishColorOptions.map(\.name), menuSelection - 1)
        case .scrollSensitivitySelection:
            return pick(ScrollSensitivity.allCases.map(\.rawValue), menuSelection)
        case .clickSoundSelection:
            return pick([String(localized: "settings.clickSound.on"), String(localized: "settings.clickSound.off")], menuSelection)
        case .backlightDurationSelection:
            return pick(BacklightDuration.allCases.map(\.rawValue), menuSelection)
        case .playerStyleSelection:
            return pick(PlayerStyle.allCases.map(\.displayName), menuSelection)
        case .nowPlaying:
            // Scrolling here scrubs, so the position is what changed.
            return String(format: String(localized: "wheel.a11y.position"),
                          AppHelpers.formatTime(musicService.currentTime),
                          AppHelpers.formatTime(musicService.duration))
        case .about:
            return ""
        }
    }

    private func fireTap(zone: WheelTapZone) {
        switch zone {
        case .menu:      handleMenuButton()
        case .playPause: handlePlayPause()
        case .previous:  handlePrevious()
        case .next:      handleNext()
        }
    }
    
    private func scrollSteps(for velocity: Double) -> Int {
        let t = themeSettings.scrollSensitivity.velocityStepThresholds
        switch velocity {
        case ..<t.t1: return 1
        case t.t1..<t.t2: return 2
        case t.t2..<t.t3: return 3
        default: return 5
        }
    }

    private func scrollUp() {
        let didScroll: Bool

        switch currentScreen {
        case .menu:
            if menuSelection > 0 {
                menuSelection -= 1
                didScroll = true
            } else {
                didScroll = false
            }
        case .songs, .recentlyAdded, .recentlyPlayed:
            if songSelection > 0 {
                songSelection -= 1
                didScroll = true
            } else {
                didScroll = false
            }
        case .queue:
            // While carrying a row the wheel moves the song, not the cursor. The Clear
            // Queue row sits above the first song, so the cursor stops there.
            if queueMoveOffset != nil {
                didScroll = moveCarriedQueueRow(by: -1)
            } else if !musicService.upcoming.isEmpty,
                      songSelection > QueueView.topOffset(canEdit: musicService.canEditUpcoming) {
                songSelection -= 1
                didScroll = true
            } else {
                didScroll = false
            }
        case .albums, .playlists, .artists, .podcasts, .downloadedPodcasts, .search, .settings, .themeSelection, .screenSizeSelection, .highlightColorSelection, .scrollSensitivitySelection, .clickSoundSelection, .backlightDurationSelection, .playerStyleSelection:
            if menuSelection > 0 {
                menuSelection -= 1
                didScroll = true
            } else {
                didScroll = false
            }
        case .albumDetail, .playlistDetail, .artistDetail, .podcastDetail:
            if detailSelection > 0 {
                detailSelection -= 1
                didScroll = true
            } else {
                didScroll = false
            }
        case .nowPlaying:
            // In Now Playing, scrolling seeks backward through the track
            Task {
                await scrubBackward()
            }
            didScroll = true
        case .about:
            didScroll = false
        }
        
        if didScroll {
            if themeSettings.clickSoundEnabled {
                AudioServicesPlaySystemSound(1104)
            }
            haptics.step.impactOccurred()
            haptics.step.prepare()
        } else {
            haptics.edge.impactOccurred(intensity: 0.4)
            haptics.edge.prepare()
        }
    }

    private func scrollDown() {
        let didScroll: Bool
        let maxIndex: Int

        switch currentScreen {
        case .menu:
            maxIndex = MainMenuView.items.count - 1
            if menuSelection < maxIndex {
                menuSelection += 1
                didScroll = true
            } else {
                didScroll = false
            }
        case .songs:
            maxIndex = musicService.songs.count - 1
            if songSelection < maxIndex {
                songSelection += 1
                didScroll = true
            } else {
                didScroll = false
            }
        case .queue:
            maxIndex = max(0, musicService.upcoming.count - 1)
            if queueMoveOffset != nil {
                didScroll = moveCarriedQueueRow(by: 1)
            } else if songSelection < maxIndex {
                songSelection += 1
                didScroll = true
            } else {
                didScroll = false
            }
        case .recentlyAdded:
            maxIndex = max(0, musicService.recentlyAdded.count - 1)
            if songSelection < maxIndex {
                songSelection += 1
                didScroll = true
            } else {
                didScroll = false
            }
        case .recentlyPlayed:
            maxIndex = max(0, musicService.recentlyPlayed.count - 1)
            if songSelection < maxIndex {
                songSelection += 1
                didScroll = true
            } else {
                didScroll = false
            }
        case .albums:
            maxIndex = musicService.albums.count - 1
            if menuSelection < maxIndex {
                menuSelection += 1
                didScroll = true
            } else {
                didScroll = false
            }
        case .artists:
            maxIndex = musicService.artists.count - 1
            if menuSelection < maxIndex {
                menuSelection += 1
                didScroll = true
            } else {
                didScroll = false
            }
        case .playlists:
            maxIndex = musicService.playlists.count - 1
            if menuSelection < maxIndex {
                menuSelection += 1
                didScroll = true
            } else {
                didScroll = false
            }
        case .podcasts:
            // Search Podcasts and Downloaded come first; the shows follow them.
            maxIndex = musicService.streamingPodcastShows().count + PodcastListView.fixedRows - 1
            if menuSelection < maxIndex {
                menuSelection += 1
                didScroll = true
            } else {
                didScroll = false
            }
        case .downloadedPodcasts:
            maxIndex = musicService.downloadedPodcastShows().count - 1
            if menuSelection < maxIndex {
                menuSelection += 1
                didScroll = true
            } else {
                didScroll = false
            }
        case .search:
            maxIndex = searchResults.count - 1
            if menuSelection < maxIndex {
                menuSelection += 1
                didScroll = true
            } else {
                didScroll = false
            }
        case .settings:
            maxIndex = SettingsView.items.count - 1 // Theme … Backlight, Player Style, About
            if menuSelection < maxIndex {
                menuSelection += 1
                didScroll = true
            } else {
                didScroll = false
            }
        case .themeSelection:
            maxIndex = LyreThemeStyle.allCases.count - 1
            if menuSelection < maxIndex {
                menuSelection += 1
                didScroll = true
            } else {
                didScroll = false
            }
        case .screenSizeSelection:
            maxIndex = ScreenSize.allCases.count // Auto + all sizes
            if menuSelection < maxIndex {
                menuSelection += 1
                didScroll = true
            } else {
                didScroll = false
            }
        case .highlightColorSelection:
            maxIndex = LyreColors.finishColorOptions.count // Default + Lyre finish colors
            if menuSelection < maxIndex {
                menuSelection += 1
                didScroll = true
            } else {
                didScroll = false
            }
        case .scrollSensitivitySelection:
            maxIndex = ScrollSensitivity.allCases.count - 1
            if menuSelection < maxIndex {
                menuSelection += 1
                didScroll = true
            } else {
                didScroll = false
            }
        case .clickSoundSelection:
            maxIndex = 1 // On / Off
            if menuSelection < maxIndex {
                menuSelection += 1
                didScroll = true
            } else {
                didScroll = false
            }
        case .backlightDurationSelection:
            maxIndex = BacklightDuration.allCases.count - 1
            if menuSelection < maxIndex {
                menuSelection += 1
                didScroll = true
            } else {
                didScroll = false
            }
        case .playerStyleSelection:
            maxIndex = PlayerStyle.allCases.count - 1
            if menuSelection < maxIndex {
                menuSelection += 1
                didScroll = true
            } else {
                didScroll = false
            }
        case .nowPlaying:
            // In Now Playing, scrolling seeks forward through the track
            Task {
                await scrubForward()
            }
            didScroll = true
        case .albumDetail, .playlistDetail, .artistDetail, .podcastDetail:
            // For detail views, just increment and let the view clamp it
            detailSelection += 1
            didScroll = true
        case .about:
            didScroll = false
        }

        if didScroll {
            if themeSettings.clickSoundEnabled {
                AudioServicesPlaySystemSound(1104)
            }
            haptics.step.impactOccurred()
            haptics.step.prepare()
        } else {
            haptics.edge.impactOccurred(intensity: 0.4)
            haptics.edge.prepare()
        }
    }

    private func scrubForward() async {
        guard musicService.duration > 0 else { return }
        let newTime = min(musicService.currentTime + scrubStep, musicService.duration)
        await musicService.seek(to: newTime)
    }

    private func scrubBackward() async {
        guard musicService.duration > 0 else { return }
        let newTime = max(musicService.currentTime - scrubStep, 0)
        await musicService.seek(to: newTime)
    }

    private func handleMenuButton() {
        if isHoldEnabled { return }
        onInteraction()
        
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()

        // If we're on the main menu, do nothing
        if case .menu = currentScreen {
            return
        }

        // Carrying a queue row takes priority over navigating: put the row down and
        // stay put, so leaving the screen can never strand a half-finished move.
        if case .queue = currentScreen, queueMoveOffset != nil {
            dropCarriedQueueRow()
            return
        }

        // Save current selection state before navigating back
        saveSelectionState()
        
        // Pop back to the previous screen if there's a navigation history
        if !navigationStack.isEmpty {
            let previousScreen = navigationStack.removeLast()
            logger.debug("Navigating back to: \(String(describing: previousScreen))")
            restoreSelectionState(for: previousScreen)
            withAnimation(.easeInOut(duration: 0.15)) {
                currentScreen = previousScreen
            }
        } else {
            // If no history, go to menu (fallback)
            menuSelection = 0
            withAnimation(.easeInOut(duration: 0.15)) {
                currentScreen = .menu
            }
        }
    }
    
    private func saveSelectionState() {
        let state = SelectionState(
            menuSelection: menuSelection,
            songSelection: songSelection,
            detailSelection: detailSelection
        )
        selectionMemory[currentScreen] = state
        logger.debug("Saved selection for \(String(describing: self.currentScreen))")
    }
    
    private func restoreSelectionState(for screen: LyreScreen) {
        if let savedState = selectionMemory[screen] {
            menuSelection = savedState.menuSelection
            songSelection = savedState.songSelection
            detailSelection = savedState.detailSelection
            logger.debug("Restored selection for \(String(describing: screen))")
        } else {
            // For new screens, start at 0
            // Don't reset if we're already at valid positions
            // Reset appropriately based on screen type
            switch screen {
            case .menu:
                menuSelection = 0
                songSelection = 0
                detailSelection = 0
            case .songs, .nowPlaying:
                // Keep songSelection, reset others
                menuSelection = 0
                detailSelection = 0
            case .queue:
                // songSelection indexes Up Next, which changes as songs play, so the
                // cursor starts at the top rather than restoring a stale position.
                menuSelection = 0
                songSelection = 0
                detailSelection = 0
            case .search:
                // Results change with every search, so the cursor starts at the top.
                menuSelection = 0
                songSelection = 0
                detailSelection = 0
            case .albums, .artists, .playlists, .podcasts, .downloadedPodcasts:
                // Keep menuSelection for list position, reset others
                songSelection = 0
                detailSelection = 0
            case .settings, .themeSelection, .highlightColorSelection, .screenSizeSelection:
                // Reset all selections for settings screens
                menuSelection = 0
                songSelection = 0
                detailSelection = 0
            case .scrollSensitivitySelection:
                menuSelection = ScrollSensitivity.allCases.firstIndex(of: themeSettings.scrollSensitivity) ?? 0
                songSelection = 0
                detailSelection = 0
            case .clickSoundSelection:
                menuSelection = themeSettings.clickSoundEnabled ? 0 : 1
                songSelection = 0
                detailSelection = 0
            case .backlightDurationSelection:
                menuSelection = BacklightDuration.allCases.firstIndex(of: themeSettings.backlightDuration) ?? 0
                songSelection = 0
                detailSelection = 0
            case .playerStyleSelection:
                menuSelection = PlayerStyle.allCases.firstIndex(of: themeSettings.playerStyle) ?? 0
                songSelection = 0
                detailSelection = 0
            case .recentlyAdded, .recentlyPlayed:
                menuSelection = 0
                detailSelection = 0
            case .albumDetail, .playlistDetail, .artistDetail, .podcastDetail:
                // Keep detailSelection for track position, reset others
                menuSelection = 0
                songSelection = 0
            case .about:
                // No selections needed
                menuSelection = 0
                songSelection = 0
                detailSelection = 0
            }
        }
    }
    
    /// Plays the highlighted row of an album or playlist list: the whole list for the
    /// Play and Shuffle rows, otherwise the list from the chosen track on.
    private func playDetailRow(_ row: Int, of tracks: [AppTrack], playlistID: String? = nil) async -> PlaybackStartOutcome {
        switch row {
        case PlayShuffleRows.playOffset:
            return await musicService.playAll(tracks: tracks, shuffled: false, playlistID: playlistID)
        case PlayShuffleRows.shuffleOffset:
            return await musicService.playAll(tracks: tracks, shuffled: true, playlistID: playlistID)
        default:
            let index = row - PlayShuffleRows.count
            guard index < tracks.count else { return .nothingPlayable }
            return await musicService.play(tracks: tracks, startingAt: index, playlistID: playlistID)
        }
    }

    /// Starts playback and opens Now Playing, or stays put and says why it could not.
    ///
    /// The navigation push happens up front so Menu still returns to the list the song
    /// was chosen from, and is undone when playback does not start — otherwise a track
    /// that cannot play would leave a phantom entry in the back stack. Reporting the
    /// failure matters because the alternative, quietly playing the nearest playable
    /// track instead, looks like the wheel selected the wrong row.
    private func startPlayback(_ start: @escaping () async -> PlaybackStartOutcome) {
        saveSelectionState()
        navigationStack.append(currentScreen)
        Task {
            let outcome = await start()
            await MainActor.run {
                switch outcome {
                case .started:
                    restoreSelectionState(for: .nowPlaying)
                    withAnimation(.easeInOut(duration: 0.15)) { currentScreen = .nowPlaying }
                case .trackUnavailable:
                    _ = navigationStack.popLast()
                    bumpFeedback()
                    onBanner(String(localized: "playback.trackUnavailable"))
                case .nothingPlayable:
                    _ = navigationStack.popLast()
                    bumpFeedback()
                    onBanner(String(localized: "playback.nothingPlayable"))
                }
            }
        }
    }

    private func handleSelect() {
        if isHoldEnabled { return }
        onInteraction()
        
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        generator.impactOccurred()
        
        switch currentScreen {
        case .menu:
            saveSelectionState()
            navigationStack.append(currentScreen)
            let menuTarget: LyreScreen
            switch menuSelection {
            case 0: menuTarget = .nowPlaying
            case 1: menuTarget = .queue
            case 2: menuTarget = .songs
            case 3: menuTarget = .recentlyAdded
            case 4: menuTarget = .recentlyPlayed
            case 5: menuTarget = .albums
            case 6: menuTarget = .artists
            case 7: menuTarget = .playlists
            case 8: menuTarget = .podcasts
            case 9: menuTarget = .search
            case 10: menuTarget = .settings
            default:
                _ = navigationStack.popLast()
                return
            }
            restoreSelectionState(for: menuTarget)
            withAnimation(.easeInOut(duration: 0.15)) { currentScreen = menuTarget }

        case .songs:
            let songs = musicService.songs
            if songSelection < songs.count {
                startPlayback { await musicService.play(tracks: songs, startingAt: songSelection) }
            }

        case .queue:
            // One button, so reordering is pick-up / put-down: the first press lifts
            // the highlighted row, the wheel carries it, the next press drops it.
            // A podcast's episodes can't be moved: the press plays the one highlighted.
            if !musicService.canEditUpcoming {
                if musicService.upcoming.indices.contains(songSelection) {
                    musicService.playUpcoming(at: songSelection)
                } else {
                    bumpFeedback()
                }
            } else if queueMoveOffset != nil {
                dropCarriedQueueRow()
            } else if songSelection == QueueView.clearRowOffset {
                clearQueue()
            } else if songSelection < musicService.upNext.count {
                queueMoveOffset = songSelection
            } else {
                bumpFeedback()
            }

        case .recentlyAdded:
            let recentlyAdded = musicService.recentlyAdded
            if songSelection < recentlyAdded.count {
                startPlayback { await musicService.play(tracks: recentlyAdded, startingAt: songSelection) }
            }

        case .recentlyPlayed:
            let recentlyPlayed = musicService.recentlyPlayed
            if songSelection < recentlyPlayed.count {
                startPlayback { await musicService.play(tracks: recentlyPlayed, startingAt: songSelection) }
            }

        case .albums:
            if !musicService.albums.isEmpty && menuSelection < musicService.albums.count {
                let album = musicService.albums[menuSelection]
                saveSelectionState()
                navigationStack.append(currentScreen)
                let target = LyreScreen.albumDetail(album)
                restoreSelectionState(for: target)
                withAnimation(.easeInOut(duration: 0.15)) { currentScreen = target }
            }

        case .artists:
            if !musicService.artists.isEmpty && menuSelection < musicService.artists.count {
                let artist = musicService.artists[menuSelection]
                saveSelectionState()
                navigationStack.append(currentScreen)
                let target = LyreScreen.artistDetail(artist)
                restoreSelectionState(for: target)
                withAnimation(.easeInOut(duration: 0.15)) { currentScreen = target }
            }

        case .playlists:
            if !musicService.playlists.isEmpty && menuSelection < musicService.playlists.count {
                let playlist = Array(musicService.playlists)[menuSelection]
                saveSelectionState()
                navigationStack.append(currentScreen)
                let target = LyreScreen.playlistDetail(playlist)
                restoreSelectionState(for: target)
                withAnimation(.easeInOut(duration: 0.15)) { currentScreen = target }
            }

        case .podcasts:
            let showIndex = menuSelection - PodcastListView.fixedRows
            if menuSelection == PodcastListView.searchRow {
                onOpenPodcastSearch()
            } else if menuSelection == PodcastListView.downloadedRow {
                saveSelectionState()
                navigationStack.append(currentScreen)
                let target = LyreScreen.downloadedPodcasts
                restoreSelectionState(for: target)
                withAnimation(.easeInOut(duration: 0.15)) { currentScreen = target }
            } else {
                let shows = musicService.streamingPodcastShows()
                if shows.indices.contains(showIndex) { openPodcastShow(shows[showIndex]) }
            }

        case .downloadedPodcasts:
            let shows = musicService.downloadedPodcastShows()
            if shows.indices.contains(menuSelection) {
                openPodcastShow(shows[menuSelection])
            }

        case .search:
            guard searchResults.indices.contains(menuSelection) else {
                bumpFeedback()
                break
            }
            switch searchResults[menuSelection] {
            case .song(let track):
                // The songs found play in the order listed, from the one chosen, as a
                // song chosen from Songs plays on through the rest.
                let songs = searchResults.compactMap(\.song)
                let index = songs.firstIndex { $0.id == track.id } ?? 0
                startPlayback { await musicService.play(tracks: songs, startingAt: index) }
            case .album(let album):       open(.albumDetail(album))
            case .artist(let artist):     open(.artistDetail(artist))
            case .playlist(let playlist): open(.playlistDetail(playlist))
            case .podcast(let show):      openPodcastShow(show)
            }

        case .podcastDetail(let show):
            let episodes = show.episodes
            let row = detailSelection
            // Play and Shuffle start the whole show from its first episode, in order
            // or shuffled; any other row starts from that episode.
            let items: [PodcastEpisode]
            let startIndex: Int
            switch row {
            case PlayShuffleRows.playOffset:
                items = episodes
                startIndex = 0
            case PlayShuffleRows.shuffleOffset:
                items = episodes.shuffled()
                startIndex = 0
            default:
                items = episodes
                startIndex = row - PlayShuffleRows.count
            }
            if items.indices.contains(startIndex) {
                startPlayback {
                    await musicService.playPodcastEpisodes(
                        items, startingAt: startIndex, podcastShowTitle: show.title
                    )
                    return .started
                }
            }

        case .albumDetail(let album):
            let row = detailSelection
            startPlayback {
                let tracks = await musicService.loadTracks(for: album)
                return await playDetailRow(row, of: tracks)
            }

        case .playlistDetail(let playlist):
            let row = detailSelection
            startPlayback {
                let tracks = await musicService.loadTracks(for: playlist)
                return await playDetailRow(row, of: tracks, playlistID: playlist.id)
            }

        case .artistDetail(let artist):
            saveSelectionState()
            navigationStack.append(currentScreen)
            Task {
                let albums = await musicService.loadAlbums(for: artist)
                if detailSelection < albums.count {
                    let target = LyreScreen.albumDetail(albums[detailSelection])
                    await MainActor.run {
                        restoreSelectionState(for: target)
                        withAnimation(.easeInOut(duration: 0.15)) { currentScreen = target }
                    }
                }
            }

        case .settings:
            saveSelectionState()
            navigationStack.append(currentScreen)
            let settingsTarget: LyreScreen
            switch menuSelection {
            case 0: settingsTarget = .themeSelection
            case 1: settingsTarget = .screenSizeSelection
            case 2: settingsTarget = .highlightColorSelection
            case 3: settingsTarget = .scrollSensitivitySelection
            case 4: settingsTarget = .clickSoundSelection
            case 5: settingsTarget = .backlightDurationSelection
            case 6: settingsTarget = .playerStyleSelection
            case 7: settingsTarget = .about
            default:
                _ = navigationStack.popLast()
                return
            }
            restoreSelectionState(for: settingsTarget)
            withAnimation(.easeInOut(duration: 0.15)) { currentScreen = settingsTarget }

        case .themeSelection:
            if menuSelection < LyreThemeStyle.allCases.count {
                themeSettings.themeStyle = LyreThemeStyle.allCases[menuSelection]
                themeSettings.useAutoScreenSize = true
            }

        case .screenSizeSelection:
            if menuSelection == 0 {
                themeSettings.useAutoScreenSize = true
            } else if menuSelection <= ScreenSize.allCases.count {
                let sizeIndex = menuSelection - 1
                if sizeIndex < ScreenSize.allCases.count {
                    themeSettings.useAutoScreenSize = false
                    themeSettings.screenSize = ScreenSize.allCases[sizeIndex]
                }
            }

        case .highlightColorSelection:
            if menuSelection == 0 {
                themeSettings.useCustomHighlight = false
            } else if menuSelection <= LyreColors.finishColorOptions.count {
                let colorOptions = LyreColors.finishColorOptions
                let colorIndex = menuSelection - 1
                if colorIndex < colorOptions.count {
                    themeSettings.customHighlightColor = colorOptions[colorIndex].color
                    themeSettings.useCustomHighlight = true
                }
            }

        case .scrollSensitivitySelection:
            if menuSelection < ScrollSensitivity.allCases.count {
                themeSettings.scrollSensitivity = ScrollSensitivity.allCases[menuSelection]
            }

        case .clickSoundSelection:
            themeSettings.clickSoundEnabled = (menuSelection == 0)

        case .backlightDurationSelection:
            if menuSelection < BacklightDuration.allCases.count {
                themeSettings.backlightDuration = BacklightDuration.allCases[menuSelection]
            }

        case .playerStyleSelection:
            if menuSelection < PlayerStyle.allCases.count {
                themeSettings.playerStyle = PlayerStyle.allCases[menuSelection]
            }

        case .about:
            // Replays the introduction. ContentView swaps back to onboarding as soon as
            // the flag clears; the journey starts again from its first step.
            UserDefaults.standard.set(0, forKey: "onboardingStep")
            hasCompletedOnboarding = false

        case .nowPlaying:
            // Each press changes the highlighted row's setting and moves on to the next
            // row: Shuffle, Repeat, and while a podcast plays, Speed.
            let rows = musicService.isPlayingPodcast ? 3 : 2
            let row = min(menuSelection, rows - 1)
            Task {
                switch row {
                case 0:
                    await musicService.toggleShuffleMode()
                case 1:
                    await musicService.toggleRepeatMode()
                default:
                    let rates = MusicService.podcastRates
                    let at = rates.firstIndex(of: musicService.podcastRate) ?? 0
                    musicService.setPodcastRate(rates[(at + 1) % rates.count])
                }
                await MainActor.run { menuSelection = (row + 1) % rows }
            }
        }
    }
    
    private func handlePlayPause() {
        if isHoldEnabled { return }
        onInteraction()
        
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        
        Task { await musicService.togglePlayPause() }
    }
    
    private func handlePrevious() {
        if isHoldEnabled { return }
        onInteraction()
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        
        // Back to the start of the song once it's under way, else the song before; on a
        // podcast, 15 seconds back. The same on every player (see PlayerActions).
        Task { await musicService.skip(forward: false) }
    }
    
    private func handleNext() {
        if isHoldEnabled { return }
        onInteraction()
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        
        // The next song; on a podcast, 30 seconds on, as the lock screen does.
        Task { await musicService.skip(forward: true) }
    }
}

#Preview {
    @Previewable @State var rotation: Double = 0
    @Previewable @State var currentScreen: LyreScreen = .menu
    @Previewable @State var navigationStack: [LyreScreen] = []
    @Previewable @State var selectionMemory: [LyreScreen: SelectionState] = [:]
    @Previewable @State var menuSelection = 0
    @Previewable @State var songSelection = 0
    @Previewable @State var detailSelection = 0
    @Previewable @State var queueMoveOffset: Int? = nil

    ZStack {
        Color.black.ignoresSafeArea()
        ScrollWheelView(
            rotation: $rotation,
            musicService: MusicService(),
            themeSettings: ThemeSettings(),
            currentScreen: $currentScreen,
            navigationStack: $navigationStack,
            selectionMemory: $selectionMemory,
            menuSelection: $menuSelection,
            songSelection: $songSelection,
            detailSelection: $detailSelection,
            queueMoveOffset: $queueMoveOffset,
            isHoldEnabled: false,
            onInteraction: {},
            onBanner: { _ in },
            onOpenPodcastSearch: {}
        )
    }
}

// MARK: - Wheel Haptics

/// The wheel's per-step haptic generators, kept for the life of the view. A class held
/// in `@State` so the generators persist without their use counting as a state change.
final class WheelHaptics {
    /// The light detent felt while turning.
    let tick = UIImpactFeedbackGenerator(style: .light)
    /// A selection moving one row.
    let step = UIImpactFeedbackGenerator(style: .medium)
    /// Turning against the end of a list.
    let edge = UIImpactFeedbackGenerator(style: .rigid)

    /// Wakes the Taptic Engine so the first tick of a touch is not late.
    func prepare() {
        tick.prepare()
        step.prepare()
        edge.prepare()
    }
}
