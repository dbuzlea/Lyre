//
//  LyreView.swift
//  Lyre
//
//  Created by Daniel Buzlea on 5/13/26.
//

import SwiftUI
import MusicKit
import OSLog

private let logger = Logger(subsystem: "com.pinkhatcreations.lyreapp", category: "LyreView")

// MARK: - LyreView
//
// Root container that assembles the complete Lyre interface. It owns all navigation
// and selection state, delegates gesture interpretation to ScrollWheelView, and
// composes the visual layers (body gradient, screen, scroll wheel, hold switch).
// Key responsibilities:
//
// Navigation state
//   `currentScreen` — the active LyreScreen enum case
//   `navigationStack` — history stack for the back button
//   `selectionMemory` — [LyreScreen: SelectionState] for O(1) cursor save/restore
//
// Backlight management
//   Any scroll wheel interaction calls `resetBacklightTimer()`, which restarts a
//   Timer that fades the screen dark after the configured BacklightDuration. The
//   timer is cancelled when the duration is set to "Always On".
//
// Artwork Carousel
//   Landscape orientation triggers `handleOrientationChange()`, which locks the
//   interface orientation to landscape and presents ArtworkCarouselView as a fullScreenCover.
//   Returning to portrait dismisses Artwork Carousel and navigates to Now Playing.
//
// Shake to Shuffle
//   ShakeDetector (UIViewControllerRepresentable) delivers shake events to
//   `handleShake()`, which shuffles all songs and starts playback if hold is off.

// MARK: - Shake Detection

private struct ShakeDetector: UIViewControllerRepresentable {
    let onShake: () -> Void

    func makeUIViewController(context: Context) -> ShakeViewController {
        let vc = ShakeViewController()
        vc.onShake = onShake
        return vc
    }

    func updateUIViewController(_ uiViewController: ShakeViewController, context: Context) {
        uiViewController.onShake = onShake
    }
}

private final class ShakeViewController: UIViewController {
    var onShake: (() -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake { onShake?() }
    }
}

struct LyreView: View {
    @ObservedObject var musicService: MusicService
    @State private var themeSettings = ThemeSettings()
    @State private var currentScreen: LyreScreen = .menu
    @State private var navigationStack: [LyreScreen] = []
    @State private var selectionMemory: [LyreScreen: SelectionState] = [:]
    @State private var menuSelection: Int = 0
    @State private var songSelection: Int = 0
    @State private var detailSelection: Int = 0
    @State private var rotation: Double = 0
    /// Up Next offset of the row being carried on the Queue screen; nil while browsing.
    @State private var queueMoveOffset: Int?
    @State private var banner: String?
    @State private var bannerTask: Task<Void, Never>?
    @State private var isHoldEnabled = false
    @State private var isBacklightOn = true
    /// Restarted on every wheel touch event, so it must not be tracked state — see OneShotTimer.
    @State private var backlightTimer = OneShotTimer()
    @State private var showArtworkCarousel = false
    @State private var artworkCarouselMode: ArtworkCarouselMode = .albums
    // Tracks the index selected in Artwork Carousel independently of menu navigation
    @State private var artworkCarouselIndex: Int = 0
    @State private var playlistArtworkCarouselIndex: Int = 0
    @State private var podcastArtworkCarouselIndex: Int = 0
    /// Screen height while a corner is being dragged; nil when resting on a preset.
    @State private var liveScreenHeight: CGFloat?
    /// Screen height at the moment the current corner drag began.
    @State private var resizeStartHeight: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                bodyGradient
                    .ignoresSafeArea()

                lyreControls(in: geometry.size)
                    .scaleEffect(layoutScale(for: geometry.size), anchor: .top)
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height,
                        alignment: .top
                    )
            }
        }
        .background(ShakeDetector { handleShake() })
        .ignoresSafeArea()
        .onAppear {
            resetBacklightTimer()
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        }
        .task {
            // Covers the hand-off out of onboarding: if authorization was granted but
            // the library never populated, load it before the user sees empty menus.
            await musicService.ensureLibraryLoaded()
        }
        .onDisappear {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            bannerTask?.cancel()
        }
        .onChange(of: currentScreen) { _, newScreen in
            // Left the Queue screen mid-move (orientation change, say). The model
            // already holds the new order, so commit it to the player rather than
            // leaving the two disagreeing.
            guard let offset = queueMoveOffset, newScreen != .queue else { return }
            queueMoveOffset = nil
            musicService.commitQueueMove(to: offset)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
        ) { _ in
            handleOrientationChange()
        }
        .fullScreenCover(isPresented: $showArtworkCarousel) {
            switch artworkCarouselMode {
            case .albums:
                ArtworkCarouselView(
                    content: .albums(musicService.albums),
                    musicService: musicService,
                    selectedIndex: $artworkCarouselIndex,
                    onDismiss: { forcePortrait(); showArtworkCarousel = false }
                )
            case .playlists:
                ArtworkCarouselView(
                    content: .playlists(Array(musicService.playlists)),
                    musicService: musicService,
                    selectedIndex: $playlistArtworkCarouselIndex,
                    onDismiss: { forcePortrait(); showArtworkCarousel = false }
                )
            case .podcasts:
                ArtworkCarouselView(
                    content: .podcasts(musicService.podcastShows),
                    musicService: musicService,
                    selectedIndex: $podcastArtworkCarouselIndex,
                    onDismiss: { forcePortrait(); showArtworkCarousel = false }
                )
            }
        }
    }

    private func lyreControls(in containerSize: CGSize) -> some View {
        VStack(spacing: 12) {
            // Top section with hold switch
            HStack {
                HoldSwitchView(isEnabled: $isHoldEnabled)
                    .padding(.leading, 20)
                Spacer()
            }
            .padding(.top, 52)

            // Screen
            VStack {
                LyreScreenView(
                    currentScreen: currentScreen,
                    musicService: musicService,
                    themeSettings: themeSettings,
                    menuSelection: $menuSelection,
                    songSelection: $songSelection,
                    detailSelection: $detailSelection,
                    isBacklightOn: isBacklightOn,
                    queueMoveOffset: queueMoveOffset,
                    banner: banner
                )
                .frame(width: displayedLayout(in: containerSize).dimensions.width,
                       height: displayedLayout(in: containerSize).dimensions.height)
                .background(screenGradient)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
                // Handles sit just outside each corner and along the bottom edge
                // so they never cover interactive screen content such as the
                // AirPlay button. The wheel is drawn later in the stack, so it
                // still wins any touch where the bottom strip overlaps it.
                .overlay(alignment: .bottomLeading) {
                    resizeHandle(in: containerSize)
                        .frame(width: Self.resizeHandleSize, height: Self.resizeHandleSize)
                        .offset(x: -Self.resizeHandleSize, y: Self.resizeHandleSize)
                }
                .overlay(alignment: .bottomTrailing) {
                    resizeHandle(in: containerSize)
                        .frame(width: Self.resizeHandleSize, height: Self.resizeHandleSize)
                        .offset(x: Self.resizeHandleSize, y: Self.resizeHandleSize)
                }
                .overlay(alignment: .bottom) {
                    resizeHandle(in: containerSize)
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.resizeHandleSize)
                        .offset(y: Self.resizeHandleSize)
                }
                .padding(.horizontal, 30)
                .animation(.easeInOut(duration: 0.3), value: themeSettings.screenSize)
                .animation(.easeInOut(duration: 0.5), value: isBacklightOn)
            }

            Spacer()

            // Scroll wheel
            ScrollWheelView(
                rotation: $rotation,
                musicService: musicService,
                themeSettings: themeSettings,
                currentScreen: $currentScreen,
                navigationStack: $navigationStack,
                selectionMemory: $selectionMemory,
                menuSelection: $menuSelection,
                songSelection: $songSelection,
                detailSelection: $detailSelection,
                queueMoveOffset: $queueMoveOffset,
                isHoldEnabled: isHoldEnabled,
                onInteraction: resetBacklightTimer,
                onBanner: showBanner
            )
            // ScrollWheelView draws itself at a fixed native size, so scale it
            // down to the layout's wheel size or it would spill past its frame
            // and off the bottom of the display. Its touch math works in local
            // coordinates, so hit testing follows the scaled drawing.
            .scaleEffect(min(1, displayedLayout(in: containerSize).wheelSize / Self.nativeWheelSize))
            .frame(width: displayedLayout(in: containerSize).wheelSize,
                   height: displayedLayout(in: containerSize).wheelSize)
            .animation(.easeInOut(duration: 0.3), value: themeSettings.screenSize)
            .padding(.bottom, 40)
        }
    }

    private var bodyGradient: some View {
        LinearGradient(
            colors: [
                themeSettings.currentTheme.bodyGradientStart,
                themeSettings.currentTheme.bodyGradientEnd
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var screenGradient: some View {
        LinearGradient(
            colors: isBacklightOn ?
                themeSettings.currentTheme.screenBackgroundLight :
                themeSettings.currentTheme.screenBackgroundDark,
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Smallest scale `layoutScale(for:)` will shrink the controls to.
    private static let minimumLayoutScale: CGFloat = 0.78

    /// Side length of the invisible corner drag targets, and the depth of the
    /// drag strip along the bottom edge.
    private static let resizeHandleSize: CGFloat = 44

    /// The fixed size ScrollWheelView lays itself out at.
    private static let nativeWheelSize: CGFloat = 280

    private func layoutScale(for size: CGSize) -> CGFloat {
        let layout = displayedLayout(in: size)
        let contentHeight = Self.contentHeight(screenHeight: layout.dimensions.height,
                                               wheelSize: layout.wheelSize)

        guard contentHeight > size.height else { return 1 }
        return max(Self.minimumLayoutScale, size.height / contentHeight)
    }

    /// Unscaled height of the whole control stack for a given screen and wheel.
    private static func contentHeight(screenHeight: CGFloat, wheelSize: CGFloat) -> CGFloat {
        let estimatedHoldSwitchHeight: CGFloat = 28
        let fixedVerticalSpacing: CGFloat = 12 + 12 + 52 + 40
        return estimatedHoldSwitchHeight + screenHeight + wheelSize + fixedVerticalSpacing
    }

    // MARK: - Drag to Resize

    /// Screen and wheel size currently on display — the live drag layout while a
    /// corner is being dragged, otherwise the selected preset (or the largest one
    /// that fits, if the selection is too big for this device).
    private func displayedLayout(in containerSize: CGSize) -> (dimensions: CGSize, wheelSize: CGFloat) {
        guard let liveScreenHeight else {
            let size = effectiveScreenSize(in: containerSize)
            return (size.dimensions, size.wheelSize)
        }
        return ScreenSize.interpolatedLayout(forHeight: liveScreenHeight,
                                             in: ScreenSize.heightLadder)
    }

    /// The selected preset if it fits this container, otherwise the tallest one
    /// that does, so the scroll wheel is never pushed off the display.
    private func effectiveScreenSize(in containerSize: CGSize) -> ScreenSize {
        let fitting = resizableSizes(in: containerSize)
        if fitting.contains(themeSettings.screenSize) { return themeSettings.screenSize }
        return fitting.last ?? themeSettings.screenSize
    }

    /// Presets that fit this container at the minimum layout scale — the only
    /// sizes shown, and the only ones a drag may settle on.
    private func resizableSizes(in containerSize: CGSize) -> [ScreenSize] {
        let fitting = ScreenSize.heightLadder.filter { size in
            let height = Self.contentHeight(screenHeight: size.dimensions.height,
                                            wheelSize: size.wheelSize)
            return height * Self.minimumLayoutScale <= containerSize.height
        }
        // Before the first layout pass the container can be zero-sized.
        return fitting.isEmpty ? Array(ScreenSize.heightLadder.prefix(1)) : fitting
    }

    /// Invisible touch target around the bottom of the screen; callers size and
    /// place it. Dragging it down grows the screen, dragging it up shrinks it.
    private func resizeHandle(in containerSize: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                // Global space keeps the translation steady while layoutScale
                // shrinks or grows the controls underneath the finger.
                DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .onChanged { value in
                        updateResize(translation: value.translation.height, in: containerSize)
                    }
                    .onEnded { _ in
                        finishResize(in: containerSize)
                    }
            )
    }

    private func updateResize(translation: CGFloat, in containerSize: CGSize) {
        let startHeight = resizeStartHeight
            ?? effectiveScreenSize(in: containerSize).dimensions.height
        if resizeStartHeight == nil { resizeStartHeight = startHeight }

        let ladder = resizableSizes(in: containerSize)
        guard let minHeight = ladder.first?.dimensions.height,
              let maxHeight = ladder.last?.dimensions.height else { return }

        // Follow the finger inside the range; past either end, resist.
        let rawHeight = startHeight + translation
        if rawHeight > maxHeight {
            liveScreenHeight = maxHeight + Self.rubberBand(rawHeight - maxHeight)
        } else if rawHeight < minHeight {
            liveScreenHeight = minHeight - Self.rubberBand(minHeight - rawHeight)
        } else {
            liveScreenHeight = rawHeight
        }
    }

    private func finishResize(in containerSize: CGSize) {
        defer { resizeStartHeight = nil }
        guard let liveScreenHeight else { return }

        let ladder = resizableSizes(in: containerSize)
        let target = ScreenSize.nearest(toHeight: liveScreenHeight, in: ladder)
            ?? themeSettings.screenSize

        // A spring gives the rubber-band snap. Disabling implicit animations stops
        // the screen's easeInOut `.animation(value: screenSize)` from overriding it.
        var transaction = Transaction(animation: .spring(response: 0.4, dampingFraction: 0.72))
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if target != themeSettings.screenSize {
                themeSettings.useAutoScreenSize = false
                themeSettings.screenSize = target
            }
            self.liveScreenHeight = nil
        }
    }

    /// Diminishing overshoot for drags past the size limits: the first points of
    /// overshoot track closely, then resistance builds toward `limit`.
    private static func rubberBand(_ overshoot: CGFloat, limit: CGFloat = 80) -> CGFloat {
        let coefficient: CGFloat = 0.55
        return (1 - 1 / (overshoot * coefficient / limit + 1)) * limit
    }

    // MARK: - Orientation Handling

    private func handleOrientationChange() {
        let orientation = UIDevice.current.orientation
        // Ignore ambiguous orientations (face up/down/unknown)
        guard orientation != .faceUp,
              orientation != .faceDown,
              orientation != .unknown else { return }

        if orientation.isLandscape && !showArtworkCarousel {
            AppDelegate.orientationLock = .landscape
            switch currentScreen {
            case .playlists, .playlistDetail:
                artworkCarouselMode = .playlists
            case .podcasts, .podcastDetail:
                artworkCarouselMode = .podcasts
            case .nowPlaying:
                break // preserve last artworkCarouselMode when returning from artwork carousel
            default:
                artworkCarouselMode = .albums
            }
            switch artworkCarouselMode {
            case .albums:
                if let track = musicService.currentTrack,
                   let idx = musicService.albums.firstIndex(where: { $0.title == track.albumTitle }) {
                    artworkCarouselIndex = idx
                }
            case .playlists:
                if let playlistID = musicService.currentPlaylistID,
                   let idx = musicService.playlists.firstIndex(where: { $0.id == playlistID }) {
                    playlistArtworkCarouselIndex = idx
                }
            case .podcasts:
                if let showTitle = musicService.currentPodcastShowTitle,
                   let idx = musicService.podcastShows.firstIndex(where: { $0.title == showTitle }) {
                    podcastArtworkCarouselIndex = idx
                }
            }
            logger.info("Artwork Carousel opened: \(String(describing: artworkCarouselMode))")
            showArtworkCarousel = true
        } else if orientation.isPortrait && showArtworkCarousel {
            logger.info("Artwork Carousel dismissed, returning to now playing")
            showArtworkCarousel = false
            AppDelegate.orientationLock = .portrait
            navigateTo(.nowPlaying)
        }
    }

    private func forcePortrait() {
        AppDelegate.orientationLock = .portrait
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }

    // MARK: - Navigation Helpers

    private func saveCurrentSelectionState() {
        let state = SelectionState(
            menuSelection: menuSelection,
            songSelection: songSelection,
            detailSelection: detailSelection
        )
        selectionMemory[currentScreen] = state
    }

    private func restoreSelectionState(for screen: LyreScreen) {
        if let savedState = selectionMemory[screen] {
            menuSelection = savedState.menuSelection
            songSelection = savedState.songSelection
            detailSelection = savedState.detailSelection
        } else {
            menuSelection = 0
            songSelection = 0
            detailSelection = 0
        }
    }

    private func navigateTo(_ screen: LyreScreen) {
        logger.debug("Navigate: \(String(describing: currentScreen)) → \(String(describing: screen))")
        saveCurrentSelectionState()
        navigationStack.append(currentScreen)
        currentScreen = screen
        restoreSelectionState(for: screen)
    }

    private func navigateBack() {
        guard !navigationStack.isEmpty else { return }
        let destination = navigationStack.last ?? .menu
        logger.debug("Navigate back: \(String(describing: currentScreen)) → \(String(describing: destination))")
        saveCurrentSelectionState()
        currentScreen = navigationStack.removeLast()
        restoreSelectionState(for: currentScreen)
    }

    // MARK: - Queue Feedback

    /// Shows a queue confirmation on the screen for a moment. Each message replaces
    /// the last, so queueing several songs quickly doesn't stack up banners.
    private func showBanner(_ message: String) {
        bannerTask?.cancel()
        banner = message
        bannerTask = Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            banner = nil
        }
    }

    // MARK: - Backlight Management

    /// Called on every wheel touch event. Writes state only when the backlight
    /// actually turns on, so a scroll does not redraw the whole interface per event.
    private func resetBacklightTimer() {
        if !isBacklightOn { isBacklightOn = true }

        guard let interval = themeSettings.backlightDuration.interval else {
            backlightTimer.cancel()
            return
        }
        backlightTimer.schedule(after: interval) {
            withAnimation(.easeOut(duration: 0.5)) {
                isBacklightOn = false
            }
        }
    }

    // MARK: - Shake to Shuffle

    private func handleShake() {
        guard !isHoldEnabled, !musicService.songs.isEmpty else { return }
        resetBacklightTimer()
        let shuffled = musicService.songs.shuffled()
        Task {
            let outcome = await musicService.play(tracks: shuffled, startingAt: 0)
            await MainActor.run {
                // Don't open Now Playing for a shuffle that never started.
                guard outcome == .started else {
                    showBanner(String(localized: "playback.nothingPlayable"))
                    return
                }
                saveCurrentSelectionState()
                navigationStack.append(currentScreen)
                withAnimation(.easeInOut(duration: 0.15)) {
                    currentScreen = .nowPlaying
                }
            }
        }
    }
}

private enum ArtworkCarouselMode {
    case albums, playlists, podcasts
}

// MARK: - Preview

#Preview {
    @Previewable @State var musicService = MusicService()
    LyreView(musicService: musicService)
}
