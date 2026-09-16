//
//  ScrollWheelView.swift
//  Lyre
//
//  Created by Daniel Buzlea on 5/13/26.
//

import SwiftUI
import AudioToolbox
import OSLog

private let logger = Logger(subsystem: "com.pinkhatcreations.lyre", category: "ScrollWheel")

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
// The center circle is a separate Button (handleSelect) that is not part of the
// ring gesture layer.
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

    // Button press states for visual feedback
    @State private var isMenuPressed = false
    @State private var isPlayPressed = false
    @State private var isPreviousPressed = false
    @State private var isNextPressed = false
    @State private var isSelectPressed = false

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
    let isHoldEnabled: Bool
    let onInteraction: () -> Void
    
    // Constants for wheel interaction
    private let hapticStepSize: Double = 20.0 // Degrees per haptic tick
    private var scrollThreshold: Double { themeSettings.scrollSensitivity.scrollThreshold }
    private let scrubStep: Double = 5.0 // Seconds to seek per scroll tick in Now Playing
    // Angular movement (in degrees) before a touch is classified as a scroll rather than a tap.
    // Under this threshold the gesture ends as a tap; over it the ring enters scroll mode.
    private let scrollCommitAngle: Double = 5.0
    
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
                .accessibilityLabel("Scroll wheel")
                .accessibilityHint("Rotate to scroll. Tap top for Menu, bottom for Play/Pause, left for Previous, right for Next")
                .accessibilityAddTraits(.isButton)

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
            
            // Center select button
            Button(action: handleSelect) {
                Circle()
                    .fill(Color.clear)
                    .frame(width: 110, height: 110)
                    .contentShape(Circle())
            }
            .buttonStyle(PlainButtonPressStyle(isPressed: $isSelectPressed))
            .accessibilityLabel("Select")
            .accessibilityHint("Activate the current menu item")
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
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred(intensity: 0.6)
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
        case .albums, .playlists, .artists, .podcasts, .settings, .themeSelection, .screenSizeSelection, .highlightColorSelection, .scrollSensitivitySelection, .clickSoundSelection, .backlightDurationSelection:
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
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred()
        } else {
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            generator.prepare()
            generator.impactOccurred(intensity: 0.4)
        }
    }

    private func scrollDown() {
        let didScroll: Bool
        let maxIndex: Int

        switch currentScreen {
        case .menu:
            maxIndex = 8 // Now Playing, Songs, Recently Added, Recently Played, Albums, Artists, Playlists, Podcasts, Settings
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
            maxIndex = musicService.podcastShows.count - 1
            if menuSelection < maxIndex {
                menuSelection += 1
                didScroll = true
            } else {
                didScroll = false
            }
        case .settings:
            maxIndex = 6 // Theme, Screen Size, Highlight Color, Scroll Speed, Click Sound, Backlight, About
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
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred()
        } else {
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            generator.prepare()
            generator.impactOccurred(intensity: 0.4)
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
            case .albums, .artists, .playlists, .podcasts:
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
            case 1: menuTarget = .songs
            case 2: menuTarget = .recentlyAdded
            case 3: menuTarget = .recentlyPlayed
            case 4: menuTarget = .albums
            case 5: menuTarget = .artists
            case 6: menuTarget = .playlists
            case 7: menuTarget = .podcasts
            case 8: menuTarget = .settings
            default:
                _ = navigationStack.popLast()
                return
            }
            restoreSelectionState(for: menuTarget)
            withAnimation(.easeInOut(duration: 0.15)) { currentScreen = menuTarget }

        case .songs:
            if !musicService.songs.isEmpty && songSelection < musicService.songs.count {
                saveSelectionState()
                navigationStack.append(currentScreen)
                Task {
                    await musicService.play(tracks: musicService.songs, startingAt: songSelection)
                    await MainActor.run {
                        restoreSelectionState(for: .nowPlaying)
                        withAnimation(.easeInOut(duration: 0.15)) { currentScreen = .nowPlaying }
                    }
                }
            }

        case .recentlyAdded:
            if !musicService.recentlyAdded.isEmpty && songSelection < musicService.recentlyAdded.count {
                saveSelectionState()
                navigationStack.append(currentScreen)
                Task {
                    await musicService.play(tracks: musicService.recentlyAdded, startingAt: songSelection)
                    await MainActor.run {
                        restoreSelectionState(for: .nowPlaying)
                        withAnimation(.easeInOut(duration: 0.15)) { currentScreen = .nowPlaying }
                    }
                }
            }

        case .recentlyPlayed:
            if !musicService.recentlyPlayed.isEmpty && songSelection < musicService.recentlyPlayed.count {
                saveSelectionState()
                navigationStack.append(currentScreen)
                Task {
                    await musicService.play(tracks: musicService.recentlyPlayed, startingAt: songSelection)
                    await MainActor.run {
                        restoreSelectionState(for: .nowPlaying)
                        withAnimation(.easeInOut(duration: 0.15)) { currentScreen = .nowPlaying }
                    }
                }
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
            if !musicService.podcastShows.isEmpty && menuSelection < musicService.podcastShows.count {
                let show = musicService.podcastShows[menuSelection]
                saveSelectionState()
                navigationStack.append(currentScreen)
                let target = LyreScreen.podcastDetail(show)
                restoreSelectionState(for: target)
                withAnimation(.easeInOut(duration: 0.15)) { currentScreen = target }
            }

        case .podcastDetail(let show):
            let episodes = show.episodes
            if !episodes.isEmpty && detailSelection < episodes.count {
                saveSelectionState()
                navigationStack.append(currentScreen)
                Task {
                    await musicService.playPodcastEpisodes(items: episodes, startingAt: detailSelection, podcastShowTitle: show.title)
                    await MainActor.run {
                        restoreSelectionState(for: .nowPlaying)
                        withAnimation(.easeInOut(duration: 0.15)) { currentScreen = .nowPlaying }
                    }
                }
            }

        case .albumDetail(let album):
            saveSelectionState()
            navigationStack.append(currentScreen)
            Task {
                let tracks = await musicService.loadTracks(for: album)
                if detailSelection < tracks.count {
                    await musicService.play(tracks: tracks, startingAt: detailSelection)
                    await MainActor.run {
                        restoreSelectionState(for: .nowPlaying)
                        withAnimation(.easeInOut(duration: 0.15)) { currentScreen = .nowPlaying }
                    }
                }
            }

        case .playlistDetail(let playlist):
            saveSelectionState()
            navigationStack.append(currentScreen)
            Task {
                let tracks = await musicService.loadTracks(for: playlist)
                if detailSelection < tracks.count {
                    await musicService.play(tracks: tracks, startingAt: detailSelection, playlistID: playlist.id)
                    await MainActor.run {
                        restoreSelectionState(for: .nowPlaying)
                        withAnimation(.easeInOut(duration: 0.15)) { currentScreen = .nowPlaying }
                    }
                }
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
            case 6: settingsTarget = .about
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

        case .about:
            break

        case .nowPlaying:
            Task {
                if menuSelection == 0 {
                    await musicService.toggleShuffleMode()
                    await MainActor.run { menuSelection = 1 }
                } else {
                    await musicService.toggleRepeatMode()
                    await MainActor.run { menuSelection = 0 }
                }
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
        
        // Restart the current track if it's been playing for more than 3 seconds;
        // otherwise skip to the previous track (standard music player behavior).
        Task {
            if musicService.currentTime > 3 {
                await musicService.seek(to: 0)
            } else {
                await musicService.skipToPrevious()
            }
        }
    }
    
    private func handleNext() {
        if isHoldEnabled { return }
        onInteraction()
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        
        Task { await musicService.skipToNext() }
    }
}

// MARK: - Custom Button Styles

/// Simple button style that just tracks pressed state and provides visual feedback
struct PlainButtonPressStyle: ButtonStyle {
    @Binding var isPressed: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { oldValue, newValue in
                isPressed = newValue
            }
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
            isHoldEnabled: false,
            onInteraction: {}
        )
    }
}
