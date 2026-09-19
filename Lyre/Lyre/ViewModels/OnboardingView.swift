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


// MARK: - Onboarding Flow
//
// OnboardingView guides a first-time user through four sequential pages:
//   0  WelcomePageView       — app introduction, "Get Started" CTA
//   1  AppleMusicAuthPageView — requests MusicKit authorization, then loads the library
//   2  ThemePickerPageView   — lets the user pick an Lyre color theme (saved to UserDefaults)
//   3  ReadyPageView         — brief usage tips, "Start Listening" CTA
//
// Navigation is strictly forward (advance() increments `page`). Each page slides in
// from the right and exits to the left via an asymmetric transition. Page indicator
// capsule dots animate their width (20pt selected, 6pt otherwise).
//
// Once the user taps "Start Listening", `hasCompletedOnboarding` is set to true in
// AppStorage, causing ContentView to permanently switch to LyreView.

// MARK: - Root Onboarding Container

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @ObservedObject var musicService: MusicService

    @State private var page = 0

    var body: some View {
        ZStack {
            darkBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Group {
                    switch page {
                    case 0:
                        WelcomePageView(onNext: advance)
                    case 1:
                        AppleMusicAuthPageView(musicService: musicService, onNext: advance)
                    case 2:
                        ThemePickerPageView(onNext: advance)
                    default:
                        ReadyPageView(onDone: { hasCompletedOnboarding = true })
                    }
                }
                .id(page)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Page indicator dots
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { i in
                        Capsule()
                            .fill(page == i ? Color.white : Color.white.opacity(0.28))
                            .frame(width: page == i ? 20 : 6, height: 6)
                            .animation(.easeInOut(duration: 0.2), value: page)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .animation(.easeInOut(duration: 0.32), value: page)
    }

    private func advance() {
        page = min(page + 1, 3)
    }

    private var darkBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.04, blue: 0.10),
                Color(red: 0.07, green: 0.07, blue: 0.16)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Page 1: Welcome (unchanged label kept for reference)

private struct WelcomePageView: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Color.white.opacity(0.12), Color.clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 80
                    ))
                    .frame(width: 160, height: 160)

                Image(systemName: "music.note")
                    .font(.system(size: 72, weight: .ultraLight))
                    .foregroundColor(.white)
            }
            .padding(.bottom, 36)

            Text(String(localized: "app.name"))
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.bottom, 12)

            Text(String(localized: "onboarding.tagline"))
                .font(.system(size: 17))
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer()

            OnboardingPrimaryButton(title: String(localized: "onboarding.getStarted"), action: onNext)
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Page 2: Music Access

private struct AppleMusicAuthPageView: View {
    @ObservedObject var musicService: MusicService
    let onNext: () -> Void

    @State private var authState = MusicAuthState.idle
    @State private var isShowingSubscriptionOffer = false
    @Environment(\.openURL) private var openURL

    enum MusicAuthState { case idle, requesting, authorized, denied }

    // MARK: - Derived State
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
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: iconName)
                .font(.system(size: 64, weight: .ultraLight))
                .foregroundColor(authState == .denied ? .orange : .white)
                .padding(.bottom, 32)
                .animation(.easeInOut, value: authState)

            Text(titleText)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.bottom, 14)

            Text(bodyText)
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
                .padding(.horizontal, 8)

            // Status indicator
            Group {
                if musicService.isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                        Text(String(localized: "onboarding.loadingLibraryStatus"))
                            .foregroundColor(.white.opacity(0.7))
                            .font(.system(size: 15))
                    }
                } else if isFinishedLoading {
                    HStack(spacing: 8) {
                        Image(systemName: foundNothing ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundColor(foundNothing ? .orange : .green)
                            .font(.system(size: 18))
                        Text(librarySummary)
                            .foregroundColor(.white.opacity(0.8))
                            .font(.system(size: 15, weight: .medium))
                    }
                } else if authState == .requesting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(1.3)
                }
            }
            .padding(.top, 24)
            .frame(height: 32)

            Spacer()

            VStack(spacing: 12) {
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
                            Button(String(localized: "onboarding.trySubscription")) {
                                isShowingSubscriptionOffer = true
                            }
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.55))
                            .padding(.top, 4)
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
            .padding(.horizontal, 32)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
        .musicSubscriptionOffer(isPresented: $isShowingSubscriptionOffer)
        .onAppear(perform: checkCurrentStatus)
        .onChange(of: musicService.isAuthorized) { _, authorized in
            if authorized { withAnimation { authState = .authorized } }
        }
    }

    private var skipButton: some View {
        Button(String(localized: "onboarding.skipForNow")) {
            logger.notice("Auth page: user skipped")
            onNext()
        }
            .font(.system(size: 15))
            .foregroundColor(.white.opacity(0.4))
            .padding(.top, 4)
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
            parts.append(String(format: String(localized: "onboarding.songsLoaded"), songCount))
        }
        if podcastCount > 0 {
            parts.append(String(format: String(localized: "onboarding.podcastsLoaded"), podcastCount))
        }
        return parts.isEmpty ? String(localized: "onboarding.libraryReady") : parts.joined(separator: " · ")
    }
}

// MARK: - Page 3: Theme Picker

private struct ThemePickerPageView: View {
    let onNext: () -> Void

    @State private var selected: LyreThemeStyle = .porcelain

    private let groups: [(String, [LyreThemeStyle])] = [
        ("Signature", [.porcelain, .onyx, .sterling, .crimson, .monochrome]),
        ("Pebble",    [.pebbleSilver, .pebbleGold, .pebbleBlue, .pebblePink, .pebbleGreen]),
        ("Slim",      [.slim, .slimSilver, .slimBlack, .slimGraphite, .slimBlue,
                       .slimPink, .slimPurple, .slimGreen, .slimYellow, .slimOrange, .slimRed]),
        ("Clip",      [.clipSilver, .clipBlue, .clipPink, .clipGreen,
                       .clipOrange, .clipPurple, .clipGold]),
        ("Retro",     [.phosphor, .spectrum])
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "paintpalette")
                    .font(.system(size: 44, weight: .ultraLight))
                    .foregroundColor(.white)
                    .padding(.top, 52)

                Text(String(localized: "onboarding.pickYourLyre"))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text(String(localized: "onboarding.chooseStyle"))
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.65))
            }
            .padding(.bottom, 24)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(groups.indices, id: \.self) { i in
                        let label = groups[i].0
                        let styles = groups[i].1
                        VStack(alignment: .leading, spacing: 10) {
                            Text(label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.4))
                                .tracking(1.2)
                                .textCase(.uppercase)
                                .padding(.horizontal, 24)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(styles) { style in
                                        ThemeSwatchView(
                                            style: style,
                                            isSelected: selected == style
                                        ) {
                                            selected = style
                                            UserDefaults.standard.set(
                                                style.rawValue,
                                                forKey: "LyreThemeStyle"
                                            )
                                        }
                                    }
                                }
                                .padding(.horizontal, 24)
                            }
                        }
                    }
                }
                .padding(.bottom, 12)
            }

            OnboardingPrimaryButton(title: String(localized: "onboarding.continue"), action: onNext)
                .padding(.horizontal, 32)
                .padding(.top, 8)
                .padding(.bottom, 16)
        }
        .onAppear {
            if let saved = UserDefaults.standard.string(forKey: "LyreThemeStyle"),
               let style = LyreThemeStyle(rawValue: saved) {
                selected = style
            }
        }
    }
}

private struct ThemeSwatchView: View {
    let style: LyreThemeStyle
    let isSelected: Bool
    let onTap: () -> Void

    private var theme: LyreTheme { LyreTheme.theme(for: style) }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [theme.bodyGradientStart, theme.bodyGradientEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 54, height: 54)
                        .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)

                    Circle()
                        .strokeBorder(
                            isSelected ? Color.white : Color.white.opacity(0.15),
                            lineWidth: isSelected ? 2.5 : 1
                        )
                        .frame(width: 54, height: 54)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.4), radius: 2)
                    }
                }

                Text(shortName(for: style))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.4))
                    .lineLimit(1)
                    .frame(width: 62)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private func shortName(for style: LyreThemeStyle) -> String {
        switch style {
        case .porcelain:      return "White"
        case .onyx:           return "Black"
        case .sterling:       return "Silver"
        case .crimson:        return "Crimson"
        case .monochrome:     return "B&W"
        case .pebbleSilver:   return "Silver"
        case .pebbleGold:     return "Gold"
        case .pebbleBlue:     return "Blue"
        case .pebblePink:     return "Pink"
        case .pebbleGreen:    return "Green"
        case .slim:           return "Default"
        case .slimSilver:     return "Silver"
        case .slimBlack:      return "Black"
        case .slimGraphite:   return "Graphite"
        case .slimBlue:       return "Blue"
        case .slimPink:       return "Pink"
        case .slimPurple:     return "Purple"
        case .slimGreen:      return "Green"
        case .slimYellow:     return "Yellow"
        case .slimOrange:     return "Orange"
        case .slimRed:        return "Red"
        case .clipSilver:  return "Silver"
        case .clipBlue:    return "Blue"
        case .clipPink:    return "Pink"
        case .clipGreen:   return "Green"
        case .clipOrange:  return "Orange"
        case .clipPurple:  return "Purple"
        case .clipGold:    return "Gold"
        case .phosphor:    return "Green"
        case .spectrum:    return "Color"
        }
    }
}

// MARK: - Page 4 (default): Ready

private struct ReadyPageView: View {
    let onDone: () -> Void

    private let tips: [(String, String)] = [
        ("arrow.clockwise",    String(localized: "onboarding.tip.scroll")),
        ("circle.inset.filled", String(localized: "onboarding.tip.select")),
        ("arrow.backward",     String(localized: "onboarding.tip.back"))
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundColor(.green)
                .padding(.bottom, 28)

            Text(String(localized: "onboarding.allSet"))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.bottom, 12)

            Text(String(localized: "onboarding.fewThingsToKnow"))
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.55))
                .padding(.bottom, 36)

            VStack(alignment: .leading, spacing: 22) {
                ForEach(tips, id: \.0) { icon, tip in
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: icon)
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 28)

                        Text(tip)
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 40)

            Spacer()

            OnboardingPrimaryButton(title: String(localized: "onboarding.startListening"), action: onDone)
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Shared Button

private struct OnboardingPrimaryButton: View {
    let title: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color(red: 0.04, green: 0.04, blue: 0.10))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.white)
                .cornerRadius(14)
        }
    }
}
