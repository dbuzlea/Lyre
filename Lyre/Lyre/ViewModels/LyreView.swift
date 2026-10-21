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
// When Settings → Player Style is Spool, SpoolPlayerView takes the place of all of
// those layers; the shake, orientation and sheet handling below still apply.
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
//   Follows the shape of the window, not the orientation of the device: whenever the
//   classic player's window is wider than tall, `windowShapeChanged(isWide:)` presents
//   ArtworkCarouselView as a fullScreenCover, and when it becomes taller than wide again
//   the carousel closes onto Now Playing. On an ordinary iPhone that is the same as
//   turning the phone. On iPhone Duo it is also what unfolding does — the inner display
//   is wide, and it ignores orientation locks — so opening the phone opens the carousel.
//   The Liquid player turns sideways into it too. Like the classic player's lists, the
//   page it's on decides the covers (see LiquidLocation): albums (and artists and songs),
//   playlists or podcasts, turned to the album open; from Now Playing, the menu or
//   search, it opens on what's playing. The Spool, the
//   Gramophone and the Disc have none; those stay upright.
//
//   The carousel's Back button rotates the interface upright on a phone that honours the
//   request, and holds it there (`holdUpright`) until the device itself is turned upright,
//   so a phone still lying sideways does not swing straight back into the carousel. Where
//   the request is ignored, as on the Duo's inner display, Back just shows the wheel in
//   the wide window until it next becomes tall.
//
// Search
//   The Search screen is typed into on the keyboard. LyreView keeps the query and its
//   results (see LibrarySearch), so the screen can list them and the wheel can act on
//   them. While the keyboard is up the click wheel is lowered out of view, below the
//   bottom edge, and it rises back into place once the keyboard goes. Opening Search
//   from the main menu starts a new search; coming back to it from a result keeps it.
//
// Shake to Shuffle
//   ShakeDetector (UIViewControllerRepresentable) delivers shake events to
//   `handleShake()`, which shuffles all songs and starts playback if hold is off.
//   The Spool player has no shake to shuffle: there, a shake does nothing.
//   The hold state and the player style are handed to the detector as a plain value on every update and
//   checked there, before the callback runs: the callback is a closure kept by a UIKit
//   controller, and a closure kept that way can read a stale copy of this view's
//   @State — which is how a shake used to shuffle with hold on.

// MARK: - Shake Detection

private struct ShakeDetector: UIViewControllerRepresentable {
    /// Plain values, so every toggle of the hold switch, and every change of player
    /// style, reaches the controller.
    let isHoldEnabled: Bool
    let isShakeOff: Bool
    let onShake: () -> Void

    func makeUIViewController(context: Context) -> ShakeViewController {
        let vc = ShakeViewController()
        vc.isHoldEnabled = isHoldEnabled
        vc.isShakeOff = isShakeOff
        vc.onShake = onShake
        return vc
    }

    func updateUIViewController(_ uiViewController: ShakeViewController, context: Context) {
        uiViewController.isHoldEnabled = isHoldEnabled
        uiViewController.isShakeOff = isShakeOff
        uiViewController.onShake = onShake
    }
}

final class ShakeViewController: UIViewController {
    /// While hold is on, shakes are ignored here, before anything else sees them.
    var isHoldEnabled = false
    /// Set for a player style without shake to shuffle (the Spool). The controller then
    /// gives up first responder too: held by a controller with no text input, it makes
    /// the keyboard come up whenever a menu opens.
    var isShakeOff = false {
        didSet {
            guard isShakeOff != oldValue, isViewLoaded, view.window != nil else { return }
            if isShakeOff { resignFirstResponder() } else { becomeFirstResponder() }
        }
    }
    var onShake: (() -> Void)?

    override var canBecomeFirstResponder: Bool { !isShakeOff }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
        // Typing in a search field takes first responder from this controller, and
        // nothing gives it back when the keyboard goes; without it, shakes stop arriving.
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidHide),
                                               name: UIResponder.keyboardDidHideNotification, object: nil)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardDidHideNotification, object: nil)
    }

    @objc private func keyboardDidHide() {
        guard !isShakeOff, view.window != nil else { return }
        becomeFirstResponder()
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        guard motion == .motionShake, !isHoldEnabled, !isShakeOff else { return }
        onShake?()
    }
}

// MARK: - Orientation Lock

/// Applies the supported orientations and rotation requests through this view's own
/// window scene. Replaces a walk of `UIApplication.shared.connectedScenes`, which picks
/// an arbitrary scene and need not be the one this view is in.
private struct OrientationLock: UIViewControllerRepresentable {
    let mask: UIInterfaceOrientationMask
    /// Bumped to ask for an upright interface now, rather than waiting for the device.
    let uprightRequest: Int

    func makeUIViewController(context: Context) -> OrientationLockController {
        OrientationLockController()
    }

    func updateUIViewController(_ controller: OrientationLockController, context: Context) {
        controller.apply(mask: mask, uprightRequest: uprightRequest)
    }
}

final class OrientationLockController: UIViewController {
    private var mask: UIInterfaceOrientationMask?
    private var appliedUprightRequest = 0
    private var pendingUprightRequest = 0

    func apply(mask: UIInterfaceOrientationMask, uprightRequest: Int) {
        pendingUprightRequest = uprightRequest
        if mask != self.mask {
            self.mask = mask
            AppDelegate.orientationLock = mask
        }
        flush()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Anything applied before this controller reached a window had no scene to go to.
        flush()
    }

    private func flush() {
        guard let window = view.window else { return }
        window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        guard pendingUprightRequest != appliedUprightRequest else { return }
        appliedUprightRequest = pendingUprightRequest
        // Ignored by displays that do not honour orientation locks, the Duo's inner one
        // among them; LyreView copes with that by following the window's shape.
        window.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
    }
}

struct LyreView: View {
    @ObservedObject var musicService: MusicService
    @State private var themeSettings = ThemeSettings()
    @State private var foldMonitor = FoldPostureMonitor()
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
    /// Whether the window is wider than tall — what opens the Artwork Carousel.
    @State private var isWindowWide = false
    /// Set by the carousel's Back button, so a window that is still wide shows the wheel
    /// instead of reopening the carousel. Cleared once the window is tall again.
    @State private var carouselDismissedWhileWide = false
    /// Keeps the interface upright after Back until the device is turned upright, so a
    /// phone still lying sideways does not rotate straight back into the carousel.
    @State private var holdUpright = false
    @State private var uprightRequest = 0
    @State private var artworkCarouselMode: ArtworkCarouselMode = .albums
    // Tracks the index selected in Artwork Carousel independently of menu navigation
    @State private var artworkCarouselIndex: Int = 0
    @State private var playlistArtworkCarouselIndex: Int = 0
    @State private var podcastArtworkCarouselIndex: Int = 0
    @State private var showPodcastSearch = false
    /// A play waiting to be confirmed, as it would clear songs queued by hand: a song
    /// chosen with the wheel, or a shake's shuffle.
    @State private var pendingPlay: PendingPlay?
    @State private var searchQuery = ""
    @State private var searchResults: [LibrarySearchResult] = []
    @State private var keyboard = KeyboardMonitor()
    /// Screen height while a corner is being dragged; nil when resting on a preset.
    @State private var liveScreenHeight: CGFloat?
    /// Screen height at the moment the current corner drag began.
    @State private var resizeStartHeight: CGFloat?
    /// This view ignores the safe area so the body bleeds to the edges; ContentView
    /// measures the insets instead. See `EnvironmentValues.windowSafeArea`.
    @Environment(\.windowSafeArea) private var safeArea

    var body: some View {
        // Switching players plays out as a small show (see PlayerSwitchStage).
        PlayerSwitchStage(style: themeSettings.playerStyle, musicService: musicService) { style in
            playerView(for: style)
        }
        #if DEBUG
        // `-LyreSwitchDemo spool` switches to that player a few seconds after launch, to
        // film the switch.
        .task {
            guard let name = UserDefaults.standard.string(forKey: "LyreSwitchDemo"),
                  let target = PlayerStyle(rawValue: name) else { return }
            try? await Task.sleep(for: .seconds(4))
            themeSettings.playerStyle = target
        }
        #endif
        .modifier(HingeObserver(monitor: foldMonitor))
        .background(ShakeDetector(isHoldEnabled: isHoldEnabled,
                                  isShakeOff: themeSettings.playerStyle != .classic) { handleShake() })
        .background(OrientationLock(mask: orientationMask, uprightRequest: uprightRequest))
        .ignoresSafeArea()
        .background {
            // Measured outside the safe area so it is the window's own shape. `initial`
            // matters: a Duo already open at launch must start in the carousel.
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size.width > proxy.size.height, initial: true) { _, isWide in
                        isWindowWide = isWide
                    }
            }
            .ignoresSafeArea()
        }
        .onChange(of: isWindowWide) { _, isWide in
            windowShapeChanged(isWide: isWide)
        }
        .onChange(of: themeSettings.playerStyle) { _, _ in
            // Switching to the classic player inside a wide window, as on an open Duo,
            // should land in the carousel just as unfolding would have.
            windowShapeChanged(isWide: isWindowWide)
        }
        .onAppear {
            resetBacklightTimer()
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            #if DEBUG
            // `--uitest-open-search` starts on the Search screen, for UI tests: turning
            // the wheel to it with synthesized drags is not reliable enough to test with.
            if ProcessInfo.processInfo.arguments.contains("--uitest-open-search") {
                navigateTo(.search)
            }
            #endif
        }
        .task {
            // Covers the hand-off out of onboarding: if authorization was granted but
            // the library never populated, load it before the user sees empty menus.
            await musicService.ensureLibraryLoaded()
            #if DEBUG
            // `--uitest-open-podcast-search` brings up the podcast search sheet once the
            // library has loaded (pair it with `--uitest-hide-library-errors`: an error
            // alert arriving while the sheet is up takes the sheet down with it).
            if ProcessInfo.processInfo.arguments.contains("--uitest-open-podcast-search") {
                while musicService.isLoading {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                showPodcastSearch = true
            }
            #endif
        }
        .onDisappear {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            bannerTask?.cancel()
        }
        .onChange(of: musicService.playbackNotice) { _, notice in
            if let notice { showBanner(notice.text) }
        }
        .task(id: searchQuery) {
            // Brief pause so a burst of typing searches once, at the end of it.
            if !searchResults.isEmpty || !searchQuery.isEmpty {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
            }
            searchResults = LibrarySearch.results(for: searchQuery, in: musicService)
            if currentScreen == .search { menuSelection = 0 }
        }
        .onChange(of: searchQuery) {
            // Typing is using the player, as much as turning the wheel is.
            resetBacklightTimer()
        }
        .onChange(of: currentScreen) { oldScreen, newScreen in
            // Search opened from the main menu starts afresh; returning to it from a
            // result it found leaves it as it was.
            if newScreen == .search, oldScreen == .menu {
                searchQuery = ""
                selectionMemory[.search] = nil
            }
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
            releaseUprightHoldIfUpright()
        }
        .sheet(isPresented: $showPodcastSearch) {
            PodcastSearchView(musicService: musicService)
        }
        .replaceQueuePrompt($pendingPlay, count: musicService.listenerQueuedCount)
        .fullScreenCover(isPresented: $showArtworkCarousel) {
            switch artworkCarouselMode {
            case .albums:
                ArtworkCarouselView(
                    content: .albums(musicService.albums),
                    musicService: musicService,
                    selectedIndex: $artworkCarouselIndex,
                    onDismiss: { dismissArtworkCarousel() }
                )
            case .playlists:
                ArtworkCarouselView(
                    content: .playlists(Array(musicService.playlists)),
                    musicService: musicService,
                    selectedIndex: $playlistArtworkCarouselIndex,
                    onDismiss: { dismissArtworkCarousel() }
                )
            case .podcasts:
                ArtworkCarouselView(
                    content: .podcasts(musicService.mergedPodcastShows()),
                    musicService: musicService,
                    selectedIndex: $podcastArtworkCarouselIndex,
                    onDismiss: { dismissArtworkCarousel() }
                )
            }
        }
    }

    /// The player for a style, as the switch stage shows it.
    @ViewBuilder
    private func playerView(for style: PlayerStyle) -> some View {
        switch style {
        case .classic:
            classicPlayer
        case .spool:
            SpoolPlayerView(
                musicService: musicService,
                themeSettings: themeSettings,
                foldMonitor: foldMonitor
            )
            .transition(.opacity)
        case .gramophone:
            GramophonePlayerView(
                musicService: musicService,
                themeSettings: themeSettings,
                foldMonitor: foldMonitor
            )
            .transition(.opacity)
        case .disc:
            DiscPlayerView(
                musicService: musicService,
                themeSettings: themeSettings,
                foldMonitor: foldMonitor
            )
            .transition(.opacity)
        case .liquid:
            LiquidPlayerView(
                musicService: musicService,
                themeSettings: themeSettings,
                foldMonitor: foldMonitor
            )
            .transition(.opacity)
        }
    }

    private var classicPlayer: some View {
        GeometryReader { geometry in
            ZStack {
                bodyGradient
                    .ignoresSafeArea()

                lyreControls(in: geometry.size)
                    // Each side edge's own inset, read live. iOS 27.1 can put a vertical
                    // bar along one side for as long as a configuration lasts, and the
                    // controls must not sit under it. Zero on both sides of an upright
                    // iPhone, so the layout there is unchanged.
                    .padding(.leading, safeArea.leading)
                    .padding(.trailing, safeArea.trailing)
                    .scaleEffect(layoutScale(for: geometry.size), anchor: .top)
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height,
                        alignment: .top
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
                    banner: banner,
                    searchQuery: $searchQuery,
                    searchResults: searchResults
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
                onBanner: showBanner,
                onOpenPodcastSearch: { showPodcastSearch = true },
                searchResults: searchResults,
                onAskToPlay: { pendingPlay = $0 }
            )
            // ScrollWheelView draws itself at a fixed native size, so scale it
            // down to the layout's wheel size or it would spill past its frame
            // and off the bottom of the display. Its touch math works in local
            // coordinates, so hit testing follows the scaled drawing.
            .scaleEffect(min(1, displayedLayout(in: containerSize).wheelSize / Self.nativeWheelSize))
            .frame(width: displayedLayout(in: containerSize).wheelSize,
                   height: displayedLayout(in: containerSize).wheelSize)
            .animation(.easeInOut(duration: 0.3), value: themeSettings.screenSize)
            // Lowered out of view while the keyboard is up, and back when it goes. The
            // offset keeps its place in the layout, so the screen above doesn't move.
            // KeyboardMonitor animates the change alongside the keyboard.
            .offset(y: keyboard.isVisible ? wheelHiddenOffset(in: containerSize) : 0)
            .opacity(keyboard.isVisible ? 0 : 1)
            .allowsHitTesting(!keyboard.isVisible)
            .accessibilityHidden(keyboard.isVisible)
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

    /// How far down the wheel goes to be out of view: its own height, the gap under it,
    /// the home indicator, and a little more so its shadow clears the edge too.
    private func wheelHiddenOffset(in containerSize: CGSize) -> CGFloat {
        displayedLayout(in: containerSize).wheelSize + 40 + safeArea.bottom + 40
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

    /// The classic and Liquid players may turn sideways — that is how the carousel opens.
    /// The others stay upright, as does either of those just after Back.
    // TODO: Modernization - Consider adopting `prefersInterfaceOrientationLocked` (iOS 26+)
    // as the modern replacement for orientation locking via `supportedInterfaceOrientations`.
    private var orientationMask: UIInterfaceOrientationMask {
        guard Self.hasArtworkCarousel(themeSettings.playerStyle), !holdUpright else { return .portrait }
        return .allButUpsideDown
    }

    private func windowShapeChanged(isWide: Bool) {
        // Only the classic and Liquid players have the Artwork Carousel.
        guard Self.hasArtworkCarousel(themeSettings.playerStyle) else { return }

        if isWide {
            guard !showArtworkCarousel, !carouselDismissedWhileWide else { return }
            openArtworkCarousel()
        } else {
            carouselDismissedWhileWide = false
            guard showArtworkCarousel else { return }
            logger.info("Artwork Carousel dismissed, returning to now playing")
            showArtworkCarousel = false
            navigateTo(.nowPlaying)
        }
    }

    /// The players that turn sideways into the Artwork Carousel.
    private static func hasArtworkCarousel(_ style: PlayerStyle) -> Bool {
        style == .classic || style == .liquid
    }

    private func openArtworkCarousel() {
        if themeSettings.playerStyle == .liquid, let shelf = LiquidLocation.shared.shelf {
            // Liquid's page: its shelf's covers, turned to the album open, if one is.
            switch shelf {
            case .albums:    artworkCarouselMode = .albums
            case .playlists: artworkCarouselMode = .playlists
            case .podcasts:  artworkCarouselMode = .podcasts
            }
            pointCarouselAtNowPlaying()
            if let album = LiquidLocation.shared.album { pointCarousel(at: album) }
            return
        } else if themeSettings.playerStyle == .liquid {
            // Now Playing, the menu or search: open on what's playing.
            if musicService.currentPodcastShowTitle != nil {
                artworkCarouselMode = .podcasts
            } else if musicService.currentPlaylistID != nil {
                artworkCarouselMode = .playlists
            } else {
                artworkCarouselMode = .albums
            }
        } else {
            classicCarouselMode()
        }
        pointCarouselAtNowPlaying()
    }

    /// The classic player opens the carousel for the screen it's on.
    private func classicCarouselMode() {
        switch currentScreen {
        case .playlists, .playlistDetail:
            artworkCarouselMode = .playlists
        case .podcasts, .podcastDetail, .downloadedPodcasts:
            artworkCarouselMode = .podcasts
        case .nowPlaying:
            break // preserve last artworkCarouselMode when returning from artwork carousel
        default:
            artworkCarouselMode = .albums
        }
    }

    /// Turns the carousel to `album` (or playlist, or show), when the library has it.
    private func pointCarousel(at album: AppAlbum) {
        switch artworkCarouselMode {
        case .albums:
            if let index = musicService.albums.firstIndex(where: { $0.id == album.id }) {
                artworkCarouselIndex = index
            }
        case .playlists:
            if let id = album.mixtape?.id, let index = musicService.playlists.firstIndex(where: { $0.id == id }) {
                playlistArtworkCarouselIndex = index
            }
        case .podcasts:
            if let index = musicService.mergedPodcastShows().firstIndex(where: { $0.title == album.title }) {
                podcastArtworkCarouselIndex = index
            }
        }
    }

    /// Turns the carousel to what's playing, and opens it.
    private func pointCarouselAtNowPlaying() {
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
               let idx = musicService.mergedPodcastShows().firstIndex(where: { $0.title == showTitle }) {
                podcastArtworkCarouselIndex = idx
            }
        }
        logger.info("Artwork Carousel opened: \(String(describing: artworkCarouselMode))")
        showArtworkCarousel = true
    }

    /// The carousel's Back button. Asks for an upright interface and holds it there; where
    /// that is honoured the window turns tall and the wheel returns. Where it is not, the
    /// window stays wide and `carouselDismissedWhileWide` keeps the carousel from reopening.
    private func dismissArtworkCarousel() {
        carouselDismissedWhileWide = isWindowWide
        holdUpright = true
        uprightRequest += 1
        showArtworkCarousel = false
    }

    /// Not a layout decision: only lifts the upright hold once the device is physically
    /// upright, so the next turn sideways opens the carousel again. The window's shape,
    /// not the device, still decides what is shown.
    private func releaseUprightHoldIfUpright() {
        guard holdUpright, UIDevice.current.orientation.isPortrait else { return }
        holdUpright = false
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
        // A shuffle replaces Up Next: ask first if it holds songs queued by hand.
        musicService.play(asking: { pendingPlay = $0 }, addToQueue: { queueEverythingShuffled() }) {
            shuffleEverything()
        }
    }

    /// Every song, shuffled, onto the end of Up Next instead of playing them now.
    private func queueEverythingShuffled() {
        let shuffled = musicService.songs.shuffled()
        Task {
            let outcome = await musicService.addToQueue(tracks: shuffled, placement: .last)
            showBanner(outcome.message(name: String(localized: "menu.songs"), requested: shuffled.count,
                                       placement: .last, isCollection: true))
        }
    }

    private func shuffleEverything() {
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
