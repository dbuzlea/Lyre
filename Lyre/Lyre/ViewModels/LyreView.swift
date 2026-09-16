//
//  LyreView.swift
//  Lyre
//
//  Created by Daniel Buzlea on 5/13/26.
//

import SwiftUI
import MusicKit
import OSLog

private let logger = Logger(subsystem: "com.pinkhatcreations.lyre", category: "LyreView")

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
    @State private var isHoldEnabled = false
    @State private var isBacklightOn = true
    @State private var backlightTimer: Timer?
    @State private var showArtworkCarousel = false
    @State private var artworkCarouselMode: ArtworkCarouselMode = .albums
    // Tracks the index selected in Artwork Carousel independently of menu navigation
    @State private var artworkCarouselIndex: Int = 0
    @State private var playlistArtworkCarouselIndex: Int = 0
    @State private var podcastArtworkCarouselIndex: Int = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                bodyGradient
                    .ignoresSafeArea()

                LyreControls
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
        .onDisappear {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
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

    private var LyreControls: some View {
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
                    isBacklightOn: isBacklightOn
                )
                .frame(width: themeSettings.screenSize.dimensions.width,
                       height: themeSettings.screenSize.dimensions.height)
                .background(screenGradient)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
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
                isHoldEnabled: isHoldEnabled,
                onInteraction: resetBacklightTimer
            )
            .frame(width: themeSettings.screenSize.wheelSize,
                   height: themeSettings.screenSize.wheelSize)
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

    private func layoutScale(for size: CGSize) -> CGFloat {
        let estimatedHoldSwitchHeight: CGFloat = 28
        let fixedVerticalSpacing: CGFloat = 12 + 12 + 52 + 40
        let contentHeight = estimatedHoldSwitchHeight +
            themeSettings.screenSize.dimensions.height +
            themeSettings.screenSize.wheelSize +
            fixedVerticalSpacing

        guard contentHeight > size.height else { return 1 }
        return max(0.78, size.height / contentHeight)
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

    // MARK: - Backlight Management

    private func resetBacklightTimer() {
        isBacklightOn = true
        backlightTimer?.invalidate()

        guard let interval = themeSettings.backlightDuration.interval else { return }
        backlightTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.5)) {
                    isBacklightOn = false
                }
            }
        }
    }

    // MARK: - Shake to Shuffle

    private func handleShake() {
        guard !isHoldEnabled, !musicService.songs.isEmpty else { return }
        resetBacklightTimer()
        let shuffled = musicService.songs.shuffled()
        Task {
            await musicService.play(tracks: shuffled, startingAt: 0)
            await MainActor.run {
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
