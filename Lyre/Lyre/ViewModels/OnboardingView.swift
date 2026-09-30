//
//  OnboardingView.swift
//  Lyre
//
//  Created by Daniel Buzlea on 5/17/26.
//

import SwiftUI
import MusicKit
import MediaPlayer
import UIKit
import OSLog

private let logger = Logger(subsystem: "com.pinkhatcreations.lyreapp", category: "Onboarding")

// MARK: - Onboarding Journey
//
// A first-time user is taken through three parts, one idea per screen:
//
//   Get to know Lyre   welcome → why Lyre asks for access → music access
//   Learn the wheel    meet the wheel → hands-on practice → shortcutscommit 
//   Make it yours      body style → finish → highlight → screen size → wheel feel
//                      → screen timeout, each with a live preview of the device
//
// then a summary of what they chose. The customization part can be skipped as a whole
// ("Use the Classic Look") or step by step, and every choice is saved the moment it is
// made, through the same ThemeSettings the app reads — nothing is applied at the end.
//
// Built to work for everyone:
//   • Text uses Dynamic Type styles and every page scrolls, so the largest sizes fit.
//   • Every control has a VoiceOver label; the practice wheel is adjustable (swipe up
//     or down) so the lesson works without spinning, and progress is announced.
//   • Reduce Motion swaps the sliding transitions and pulsing hints for fades.
//   • Back is on every step, the step count is always visible, and the step reached is
//     saved, so being interrupted mid-way resumes where the user was.
//   • Colors are always named, never shown as a swatch alone.
//
// Permissions: iOS is never asked for anything until PermissionsStep has explained,
// in plain words, what Lyre will ask for, why, what it never does with it, and what
// works without it. Its button then brings up the system prompt straight away, so the
// prompt arrives as the answer to a question the user just chose to answer — never
// at launch. (MusicService deliberately touches nothing that would prompt until
// access is granted.) Lyre needs one permission, Media & Apple Music; the page
// is where any future permission should be explained too.
//
// Motion: pages fade and rise in piece by piece, the progress bar springs forward
// with a tick, and page symbols bounce as they arrive. From "Make It Yours" onward a
// single device preview stays on screen above the pages (`OnboardingStep.previewHeight`),
// so each customization transforms the same device, and on the summary its screen
// powers on before it grows into the real app. See OnboardingAnimations.swift; Reduce
// Motion turns all of it into fades.
//
// The journey can be replayed from Settings → About, which clears
// `hasCompletedOnboarding`.

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case permissions
    case musicAccess
    case meetTheWheel
    case practice
    case shortcuts
    case makeItYours
    case bodyStyle
    case finish
    case highlight
    case screenSize
    case wheelFeel
    case backlight
    case done

    /// Steps counted in "Step n of m" — everything after the welcome.
    static var countedSteps: Int { allCases.count - 1 }

    /// How tall the shared device preview is on this step, or nil where it isn't shown.
    /// The wheel-feel step has its own working wheel instead.
    var previewHeight: CGFloat? {
        switch self {
        case .makeItYours:                  return 280
        case .bodyStyle, .finish, .highlight: return 190
        case .screenSize:                   return 210
        case .backlight:                    return 190
        case .done:                         return 220
        default:                            return nil
        }
    }
}

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @ObservedObject var musicService: MusicService

    /// The step reached, so an interrupted onboarding picks up where it left off.
    @AppStorage("onboardingStep") private var storedStep = 0
    @State private var step: OnboardingStep = .welcome
    @State private var movingForward = true
    @State private var themeSettings = ThemeSettings()
    /// The shared preview's backlight: dimmed by the screen-timeout demonstration, and
    /// switched on by the summary's power-on.
    @State private var previewScreenLevel: Double = 1
    /// Bumped when the preview is tapped, restarting the screen-timeout demonstration.
    @State private var previewWakeCount = 0
    /// True once "Start Listening" is pressed and the device is growing into the app.
    @State private var isLaunching = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            OnboardingBackground()

            VStack(spacing: 0) {
                if step != .welcome {
                    OnboardingTopBar(step: step, onBack: goBack)
                        .opacity(isLaunching ? 0 : 1)
                }

                if let previewHeight = step.previewHeight {
                    OnboardingDevicePreview(
                        themeSettings: themeSettings,
                        height: previewHeight,
                        screenLevel: previewScreenLevel,
                        onTap: step == .backlight ? { previewWakeCount += 1 } : nil
                    )
                    .scaleEffect(isLaunching ? 2.6 : 1)
                    .padding(.top, 10)
                    .zIndex(1)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }

                page
                    .id(step)
                    .transition(transition)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(isLaunching ? 0 : 1)
            }
        }
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.32), value: step)
        .task(id: backlightDemoKey) { await runBacklightDemo() }
        .onAppear {
            // Resuming lands on the saved step directly, without sliding past the welcome.
            var resume = Transaction()
            resume.disablesAnimations = true
            withTransaction(resume) { step = OnboardingStep(rawValue: storedStep) ?? .welcome }
            // A fresh install follows the body style's natural screen size until the
            // user picks one, so trying styles shows each at its intended size.
            if UserDefaults.standard.object(forKey: "LyreUseAutoScreenSize") == nil {
                themeSettings.useAutoScreenSize = true
            }
        }
        .onChange(of: step) { _, new in
            storedStep = new.rawValue
            logger.info("Onboarding step: \(String(describing: new))")
            UISelectionFeedbackGenerator().selectionChanged()
            if new == .done {
                Task { await powerOnPreview() }
            } else if new != .backlight, previewScreenLevel != 1 {
                withAnimation(.easeOut(duration: 0.3)) { previewScreenLevel = 1 }
            }
        }
    }

    // MARK: Preview Backlight

    /// Restarts the screen-timeout demonstration whenever the step, the chosen timeout
    /// or a wake-up tap changes.
    private var backlightDemoKey: String {
        step == .backlight ? "\(themeSettings.backlightDuration.rawValue)-\(previewWakeCount)" : "off"
    }

    /// Lights the preview, then dims it after the chosen timeout — sped up, so waiting
    /// half a minute isn't part of onboarding. It stays dim until tapped.
    private func runBacklightDemo() async {
        guard step == .backlight else { return }
        withAnimation(.easeOut(duration: 0.2)) { previewScreenLevel = 1 }
        let seconds: Double
        switch themeSettings.backlightDuration {
        case .fiveSeconds:   seconds = 1.2
        case .tenSeconds:    seconds = 2
        case .thirtySeconds: seconds = 3.5
        case .alwaysOn:      return
        }
        try? await Task.sleep(for: .seconds(seconds))
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.6)) { previewScreenLevel = 0.25 }
    }

    /// The summary's moment: the preview's screen flickers on with a click.
    private func powerOnPreview() async {
        var dark = Transaction()
        dark.disablesAnimations = true
        withTransaction(dark) { previewScreenLevel = 0.03 }
        try? await Task.sleep(for: .milliseconds(450))
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.4)) { previewScreenLevel = 1 }
        } else {
            for (level, ms) in [(0.6, 70), (0.15, 90), (0.8, 60), (0.35, 80)] {
                withAnimation(.easeOut(duration: 0.05)) { previewScreenLevel = level }
                try? await Task.sleep(for: .milliseconds(ms))
            }
            withAnimation(.easeOut(duration: 0.35)) { previewScreenLevel = 1 }
        }
        OnboardingClick.play(sound: themeSettings.clickSoundEnabled)
    }

    @ViewBuilder
    private var page: some View {
        switch step {
        case .welcome:
            WelcomeStep(themeSettings: themeSettings, onNext: advance)
        case .permissions:
            PermissionsStep(musicService: musicService, onNext: advance, onSkip: { go(to: .meetTheWheel) })
        case .musicAccess:
            MusicAccessStep(musicService: musicService, onNext: advance)
        case .meetTheWheel:
            MeetTheWheelStep(theme: themeSettings.currentTheme, onNext: advance)
        case .practice:
            PracticeStep(themeSettings: themeSettings, onNext: advance)
        case .shortcuts:
            ShortcutsStep(onNext: advance)
        case .makeItYours:
            MakeItYoursStep(themeSettings: themeSettings, onCustomize: advance, onSkip: { go(to: .done) })
        case .bodyStyle:
            BodyStyleStep(themeSettings: themeSettings, onNext: advance)
        case .finish:
            FinishStep(themeSettings: themeSettings, onNext: advance)
        case .highlight:
            HighlightStep(themeSettings: themeSettings, onNext: advance)
        case .screenSize:
            ScreenSizeStep(themeSettings: themeSettings, onNext: advance)
        case .wheelFeel:
            WheelFeelStep(themeSettings: themeSettings, onNext: advance)
        case .backlight:
            BacklightStep(themeSettings: themeSettings, onNext: advance)
        case .done:
            DoneStep(themeSettings: themeSettings, onFinish: finish)
        }
    }

    private var transition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: movingForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: movingForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        go(to: next)
    }

    private func goBack() {
        // From the summary, Back returns to wherever the user came from: the last
        // customization step, or the choice to skip customizing.
        let target: OnboardingStep?
        if step == .done, UserDefaults.standard.bool(forKey: "onboardingSkippedCustomization") {
            target = .makeItYours
        } else {
            target = OnboardingStep(rawValue: step.rawValue - 1)
        }
        guard let target else { return }
        movingForward = false
        step = target
    }

    private func go(to target: OnboardingStep) {
        UserDefaults.standard.set(step == .makeItYours && target == .done, forKey: "onboardingSkippedCustomization")
        movingForward = target.rawValue > step.rawValue
        step = target
    }

    /// The device grows toward the viewer as everything else fades, and the app takes
    /// over from it — so the last thing onboarding shows is the player itself.
    private func finish() {
        storedStep = 0
        guard !reduceMotion else {
            hasCompletedOnboarding = true
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeIn(duration: 0.45)) { isLaunching = true }
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            hasCompletedOnboarding = true
        }
    }
}

// MARK: - Chrome

/// Shared with `AccessRecoveryView` so a revoked-access prompt reads as the same
/// screen family as onboarding rather than a one-off alert.
struct OnboardingBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.04, green: 0.04, blue: 0.10), Color(red: 0.07, green: 0.07, blue: 0.16)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

/// Back button and progress through the journey.
private struct OnboardingTopBar: View {
    let step: OnboardingStep
    let onBack: () -> Void

    private var progress: Double {
        Double(step.rawValue) / Double(OnboardingStep.countedSteps)
    }

    private var stepLabel: String {
        String(format: String(localized: "onboarding.stepOf"), step.rawValue, OnboardingStep.countedSteps)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button(action: onBack) {
                    Label(String(localized: "onboarding.back"), systemImage: "chevron.left")
                        .font(.body.weight(.medium))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(.white)

                Spacer()

                Text(stepLabel)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
                    .contentTransition(.numericText(value: Double(step.rawValue)))
                    .accessibilityHidden(true)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule().fill(.white).frame(width: geo.size.width * progress)
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: progress)
            }
            .frame(height: 4)
            .accessibilityElement()
            .accessibilityLabel(stepLabel)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

/// The frame every step shares: an optional symbol, a heading, a short explanation, the
/// step's own content, and its buttons pinned to the bottom. The content scrolls so the
/// largest text sizes never push the buttons off screen.
struct OnboardingPage<Content: View, Footer: View>: View {
    var symbol: String? = nil
    let title: String
    /// Tighter heading and spacing for hands-on and choice steps, so the wheel or the
    /// options stay on screen next to their preview.
    var compact = false
    var message: String? = nil
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    @State private var symbolBounce = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: compact ? 10 : 16) {
                    if let symbol {
                        // Bounces once on arrival; changing symbol (access granted, say)
                        // morphs one into the other.
                        Image(systemName: symbol)
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(.white)
                            .contentTransition(.symbolEffect(.replace))
                            .symbolEffect(.bounce, value: symbolBounce)
                            .padding(.bottom, 4)
                            .accessibilityHidden(true)
                            .onboardingEntrance(0)
                            .task {
                                try? await Task.sleep(for: .milliseconds(250))
                                symbolBounce.toggle()
                            }
                    }
                    Text(title)
                        .font(.system(compact ? .title : .largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .onboardingEntrance(1)
                    if let message {
                        Text(message)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .onboardingEntrance(2)
                    }
                    content
                        .padding(.top, compact ? 4 : 8)
                        .onboardingEntrance(3)
                }
                .padding(.horizontal, 24)
                .padding(.top, compact ? 12 : 24)
                .padding(.bottom, 16)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 8) {
                footer
            }
            .onboardingEntrance(4)
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .frame(maxWidth: 560)
        }
    }
}

struct OnboardingPrimaryButton: View {
    let title: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.10))
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(isEnabled ? 1 : 0.35)))
        }
        .disabled(!isEnabled)
    }
}

struct OnboardingSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
    }
}

/// An icon beside a short heading and explanation — used for feature lists. The icon
/// is an SF Symbol, or any view (the Shortcuts step's gesture demos).
struct OnboardingInfoRow<Icon: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var icon: Icon

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            icon
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(.white)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

extension OnboardingInfoRow where Icon == OnboardingSymbolIcon {
    init(symbol: String, title: String, detail: String) {
        self.init(title: title, detail: detail) { OnboardingSymbolIcon(symbol: symbol) }
    }
}

struct OnboardingSymbolIcon: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol).font(.title2).foregroundStyle(.white)
    }
}

// MARK: - Step: Welcome

private struct WelcomeStep: View {
    let themeSettings: ThemeSettings
    let onNext: () -> Void

    // The device assembles itself: body, then screen, then the wheel spinning into
    // place with a click, then the backlight flickering on.
    @State private var screenShown = false
    @State private var wheelShown = false
    @State private var screenLevel: Double = 0.03
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OnboardingPage(title: String(localized: "onboarding.welcome.title"),
                       message: String(localized: "onboarding.welcome.message")) {
            VStack(spacing: 28) {
                OnboardingDevicePreview(themeSettings: themeSettings, height: 200,
                                        screenShown: screenShown, wheelShown: wheelShown,
                                        screenLevel: screenLevel)
                    .frame(maxWidth: .infinity)
                    .task { await assemble() }

                VStack(alignment: .leading, spacing: 22) {
                    OnboardingInfoRow(symbol: "music.note.list",
                                      title: String(localized: "onboarding.welcome.music.title"),
                                      detail: String(localized: "onboarding.welcome.music.detail"))
                        .onboardingEntrance(5)
                    OnboardingInfoRow(symbol: "circle.circle",
                                      title: String(localized: "onboarding.welcome.wheel.title"),
                                      detail: String(localized: "onboarding.welcome.wheel.detail"))
                        .onboardingEntrance(7)
                    OnboardingInfoRow(symbol: "paintpalette",
                                      title: String(localized: "onboarding.welcome.style.title"),
                                      detail: String(localized: "onboarding.welcome.style.detail"))
                        .onboardingEntrance(9)
                }
            }
        } footer: {
            OnboardingPrimaryButton(title: String(localized: "onboarding.getStarted"), action: onNext)
            Text(String(localized: "onboarding.welcome.duration"))
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    private func assemble() async {
        guard !reduceMotion else {
            withAnimation(.easeOut(duration: 0.4)) {
                screenShown = true
                wheelShown = true
                screenLevel = 1
            }
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { screenShown = true }
        try? await Task.sleep(for: .milliseconds(300))
        withAnimation(.spring(response: 0.7, dampingFraction: 0.72)) { wheelShown = true }
        try? await Task.sleep(for: .milliseconds(560))
        guard !Task.isCancelled else { return }
        OnboardingClick.play(sound: themeSettings.clickSoundEnabled)
        try? await Task.sleep(for: .milliseconds(150))
        for (level, ms) in [(0.55, 70), (0.12, 90), (0.75, 60), (0.3, 80)] {
            withAnimation(.easeOut(duration: 0.05)) { screenLevel = level }
            try? await Task.sleep(for: .milliseconds(ms))
        }
        withAnimation(.easeOut(duration: 0.35)) { screenLevel = 1 }
    }
}

// MARK: - Step: Permissions

/// Explains the permission Lyre is about to ask for before iOS asks it. "Allow Access"
/// brings up the system prompt; "Not Now" moves on without asking at all.
private struct PermissionsStep: View {
    @ObservedObject var musicService: MusicService
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var isRequesting = false
    /// Morphs from the raised hand to a checked shield once access is granted.
    @State private var symbol = "hand.raised"

    /// Already granted (on a replay of the introduction) or already answered, in which
    /// case iOS will not ask again and the page says so rather than offering a prompt.
    private var alreadyGranted: Bool { MusicService.hasAnyLibraryAccess }
    private var previouslyDenied: Bool {
        !alreadyGranted && [.denied, .restricted].contains(MusicAuthorization.currentStatus)
    }

    var body: some View {
        OnboardingPage(symbol: symbol,
                       title: String(localized: "onboarding.permissions.title"),
                       message: String(localized: "onboarding.permissions.message")) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "music.note.house")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 36)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "onboarding.permissions.media.title"))
                                .font(.headline)
                                .foregroundStyle(.white)
                            if alreadyGranted {
                                Label(String(localized: "onboarding.permissions.granted"), systemImage: "checkmark.circle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)

                    Divider().overlay(.white.opacity(0.15))

                    OnboardingInfoRow(symbol: "checkmark.circle",
                                      title: String(localized: "onboarding.permissions.why.title"),
                                      detail: String(localized: "onboarding.permissions.why.detail"))
                    OnboardingInfoRow(symbol: "lock.shield",
                                      title: String(localized: "onboarding.permissions.private.title"),
                                      detail: String(localized: "onboarding.permissions.private.detail"))
                    OnboardingInfoRow(symbol: "arrow.uturn.backward.circle",
                                      title: String(localized: "onboarding.permissions.optional.title"),
                                      detail: String(localized: "onboarding.permissions.optional.detail"))
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.07)))

                Text(String(localized: alreadyGranted || previouslyDenied
                            ? "onboarding.permissions.onlyOne"
                            : "onboarding.permissions.nextPrompt"))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        } footer: {
            if alreadyGranted || previouslyDenied {
                // Nothing to ask: iOS only ever shows the prompt once. The next page
                // shows the library, or how to turn access on in Settings.
                OnboardingPrimaryButton(title: String(localized: "onboarding.continue"), action: onNext)
            } else {
                OnboardingPrimaryButton(title: String(localized: "onboarding.permissions.allow"),
                                        isEnabled: !isRequesting) {
                    isRequesting = true
                    Task {
                        await musicService.requestAuthorization()
                        if musicService.isAuthorized {
                            withAnimation { symbol = "checkmark.shield" }
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            try? await Task.sleep(for: .milliseconds(700))
                        }
                        isRequesting = false
                        onNext()
                    }
                }
                OnboardingSecondaryButton(title: String(localized: "onboarding.permissions.notNow")) {
                    logger.notice("Permissions page: user chose Not Now")
                    onSkip()
                }
            }
        }
    }
}

// MARK: - Step: Music Access

private struct MusicAccessStep: View {
    @ObservedObject var musicService: MusicService
    let onNext: () -> Void

    @State private var authState = MusicAuthState.idle
    @State private var isShowingSubscriptionOffer = false
    /// The song count as shown — it counts up to the real number once loading ends.
    @State private var shownSongCount = 0
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum MusicAuthState { case idle, requesting, authorized, denied }

    // MARK: Derived State
    //
    // An Apple Music subscription is optional. Once access is granted the page reports
    // what was actually found on the device rather than assuming a streaming library.

    private var isFinishedLoading: Bool {
        authState == .authorized && !musicService.isLoading && musicService.hasLoadedLibrary
    }

    private var songCount: Int { musicService.songs.count }
    private var podcastCount: Int { musicService.podcastShows.count }
    private var foundNothing: Bool { isFinishedLoading && songCount == 0 && podcastCount == 0 }
    private var lacksSubscription: Bool { musicService.subscriptionState == .notSubscribed }

    var body: some View {
        OnboardingPage(symbol: iconName, title: titleText, message: bodyText) {
            VStack(spacing: 20) {
                statusView
                    .frame(minHeight: 32)
                    .animation(.easeInOut, value: authState)
                if authState == .authorized, !musicService.albums.isEmpty {
                    LibraryMosaic(albums: musicService.albums)
                }
            }
            .task(id: isFinishedLoading ? songCount : -1) { await countSongs() }
        } footer: {
            switch authState {
            case .idle:
                OnboardingPrimaryButton(title: String(localized: "onboarding.allowAccess")) {
                    Task { await requestAuth() }
                }
                skipButton

            case .requesting:
                EmptyView()

            case .authorized:
                if !musicService.isLoading {
                    OnboardingPrimaryButton(title: String(localized: "onboarding.continue"), action: onNext)

                    // Offer a subscription, but never require one — the app works
                    // fine on whatever is already stored on the device.
                    if isFinishedLoading && lacksSubscription {
                        OnboardingSecondaryButton(title: String(localized: "onboarding.trySubscription")) {
                            isShowingSubscriptionOffer = true
                        }
                    }
                }

            case .denied:
                OnboardingPrimaryButton(title: String(localized: "onboarding.openSettings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                skipButton
            }
        }
        .musicSubscriptionOffer(isPresented: $isShowingSubscriptionOffer)
        .onAppear(perform: checkCurrentStatus)
        .onChange(of: musicService.isAuthorized) { _, authorized in
            if authorized { withAnimation { authState = .authorized } }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if musicService.isLoading {
            HStack(spacing: 10) {
                ProgressView().tint(.white)
                Text(String(localized: "onboarding.loadingLibraryStatus"))
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.8))
            }
        } else if isFinishedLoading {
            HStack(spacing: 8) {
                Image(systemName: foundNothing ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(foundNothing ? .orange : .green)
                    .font(.title3)
                    .accessibilityHidden(true)
                Text(librarySummary)
                    .font(.callout.weight(.medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
                    .contentTransition(.numericText(value: Double(shownSongCount)))
            }
            .accessibilityElement(children: .combine)
        } else if authState == .requesting {
            ProgressView().tint(.white).scaleEffect(1.3)
        }
    }

    /// Rolls the displayed count up to the library's size over about a second.
    private func countSongs() async {
        guard isFinishedLoading else { return }
        let target = songCount
        guard !reduceMotion, target > 0 else {
            shownSongCount = target
            return
        }
        let steps = 24
        for step in 1...steps {
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.12)) {
                shownSongCount = Int((Double(target) * Double(step) / Double(steps)).rounded())
            }
        }
    }

    private var skipButton: some View {
        OnboardingSecondaryButton(title: String(localized: "onboarding.skipForNow")) {
            logger.notice("Auth page: user skipped")
            onNext()
        }
    }

    private func checkCurrentStatus() {
        logger.notice("Auth page appeared — MusicKit: \(String(describing: MusicAuthorization.currentStatus)), MediaPlayer: \(MPMediaLibrary.authorizationStatus().rawValue)")

        // MediaPlayer access on its own is enough to show the on-device library, so it
        // counts as authorized here even when MusicKit is not.
        if MusicService.hasAnyLibraryAccess {
            authState = .authorized
            logger.notice("Auth page state: already authorized (no prompt shown)")
            return
        }
        switch MusicAuthorization.currentStatus {
        case .denied, .restricted: authState = .denied
        default:                   authState = .idle
        }
        logger.notice("Auth page state: \(String(describing: self.authState))")
    }

    private func requestAuth() async {
        logger.notice("Auth page: user tapped Allow Music Access")
        withAnimation { authState = .requesting }
        await musicService.requestAuthorization()
        withAnimation {
            authState = musicService.isAuthorized ? .authorized : .denied
        }
        logger.notice("Auth page state after request: \(String(describing: self.authState))")
    }

    private var iconName: String {
        switch authState {
        case .denied:     return "lock.slash"
        case .authorized: if foundNothing { return "questionmark.folder" }
                          return lacksSubscription ? "iphone" : "music.note.list"
        default:          return "music.note.list"
        }
    }

    private var titleText: String {
        switch authState {
        case .idle:       return String(localized: "onboarding.connectMusic")
        case .requesting: return String(localized: "onboarding.requestingAccess")
        case .denied:     return String(localized: "onboarding.accessRequired")
        case .authorized:
            if musicService.isLoading { return String(localized: "onboarding.loadingLibrary") }
            if foundNothing           { return String(localized: "onboarding.noMusicFound") }
            if lacksSubscription      { return String(localized: "onboarding.onDeviceLibraryReady") }
            return String(localized: "onboarding.libraryConnected")
        }
    }

    private var bodyText: String {
        switch authState {
        case .idle:
            return String(localized: "onboarding.connectBody")
        case .requesting:
            return String(localized: "onboarding.waitingPermission")
        case .denied:
            return String(localized: "onboarding.deniedBody")
        case .authorized:
            if musicService.isLoading { return String(localized: "onboarding.fetchingLibrary") }
            if foundNothing           { return String(localized: "onboarding.noMusicFoundBody") }
            if lacksSubscription      { return String(localized: "onboarding.noSubscriptionBody") }
            return String(localized: "onboarding.libraryReady.body")
        }
    }

    /// One line describing what the load actually turned up, so the user is never left
    /// guessing whether the app found their music.
    private var librarySummary: String {
        if foundNothing { return String(localized: "onboarding.nothingFound") }

        var parts: [String] = []
        if songCount > 0 {
            parts.append(String(format: String(localized: "onboarding.songsLoaded"), shownSongCount))
        }
        if podcastCount > 0 {
            parts.append(String(format: String(localized: "onboarding.podcastsLoaded"), podcastCount))
        }
        return parts.isEmpty ? String(localized: "onboarding.libraryReady") : parts.joined(separator: " · ")
    }
}
