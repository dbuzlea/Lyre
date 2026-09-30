//
//  AccessRecoveryView.swift
//  Lyre
//

import SwiftUI
import MusicKit
import UIKit

// MARK: - Access Recovery
//
// Fills the screen in place of the player whenever Media & Apple Music access is no
// longer granted for a user who already finished onboarding — access revoked in
// Settings, most commonly. Reuses OnboardingView's chrome (OnboardingBackground,
// OnboardingPrimaryButton, OnboardingSecondaryButton, OnboardingDevicePreview) so it
// reads as the same screen family instead of a system alert.
//
// Composes its own layout rather than reusing OnboardingPage: OnboardingPage puts its
// content in a ScrollView so long onboarding pages can scroll, which for this screen's
// short, fixed content meant the ScrollView claimed the whole page height and
// top-aligned it, leaving a dead gap along the bottom half whenever there was no footer
// to anchor. A plain VStack with a Spacer on each side of the content block centers it
// properly in the space above wherever the footer (if any) lands.
//
// Purely reactive to MusicService — it owns no phase state of its own, because
// MusicService.isShowingAccessRecovery already has to survive an app relaunch (see
// `MusicService.accessRecoveryPending`), so it's the one source of truth for whether
// this screen is on screen at all:
//   `isAuthorized == false`  Access is off. "Open Settings" fixes it now; "Not Now"
//                            (MusicService.skipAccessRecovery()) lets the user into the
//                            app without fixing it. The skip only silences the ask
//                            while access stays off — the moment the user re-enables it
//                            on their own, later, this screen reappears on its own to
//                            run the restoring animation below.
//   `isAuthorized == true`   Access came back. Shows the user's own mini player —
//                            their actual theme and highlight color — with their own
//                            covers flying in one by one while `isLoading` is true, so
//                            re-enabling access never drops the user straight into a
//                            menu that's still empty with no explanation why.
//                            MusicService keeps `isShowingAccessRecovery` true for a
//                            couple of seconds after the reload finishes before
//                            dismissing this view — long enough for real covers, not
//                            just placeholders, to have their moment (see
//                            MusicService.resolveAccessRecovery).
struct AccessRecoveryView: View {
    @ObservedObject var musicService: MusicService

    @Environment(\.openURL) private var openURL
    /// Mirrors the user's own onboarding choice, so the mini player is recognisably
    /// theirs — same theme, same highlight color — rather than a generic device.
    @State private var themeSettings = ThemeSettings()

    private static let previewHeight: CGFloat = 190

    var body: some View {
        ZStack {
            OnboardingBackground()

            VStack(spacing: 0) {
                Spacer(minLength: 20)

                VStack(spacing: 20) {
                    if musicService.isAuthorized {
                        ZStack {
                            OnboardingDevicePreview(themeSettings: themeSettings, height: Self.previewHeight)
                            CoverIntakeAnimation(albums: musicService.albums, deviceHeight: Self.previewHeight)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    } else {
                        Image(systemName: "lock.slash")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(.white)
                            .contentTransition(.symbolEffect(.replace))
                    }

                    VStack(spacing: 12) {
                        Text(musicService.isAuthorized
                             ? String(localized: "accessRecovery.restoredTitle")
                             : String(localized: "accessRecovery.title"))
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)

                        if !musicService.isAuthorized {
                            Text(String(localized: "accessRecovery.message"))
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if musicService.isAuthorized {
                        VStack(spacing: 14) {
                            LoadingBar(color: themeSettings.currentTheme.highlightColor)
                                .frame(maxWidth: 220)
                            Text(String(localized: "accessRecovery.reloading"))
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 560)

                Spacer(minLength: 20)

                if !musicService.isAuthorized {
                    VStack(spacing: 8) {
                        OnboardingPrimaryButton(title: String(localized: "accessRecovery.openSettings")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                        OnboardingSecondaryButton(title: String(localized: "accessRecovery.notNow")) {
                            musicService.skipAccessRecovery()
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                    .frame(maxWidth: 560)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut, value: musicService.isAuthorized)
        .onChange(of: musicService.isAuthorized) { _, granted in
            if granted { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        }
    }
}

// MARK: - Loading Bar

/// An indeterminate progress bar — a highlight-colored segment sweeping back and forth
/// in its track — tinted with the user's own highlight color so it reads as part of the
/// same device rather than a generic system control.
private struct LoadingBar: View {
    let color: Color

    @State private var leading = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let segmentFraction: CGFloat = 0.4

    var body: some View {
        GeometryReader { geo in
            let segmentWidth = geo.size.width * Self.segmentFraction
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule()
                    .fill(color)
                    .frame(width: segmentWidth)
                    .offset(x: leading ? geo.size.width - segmentWidth : 0)
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
        .task { await sweep() }
    }

    private func sweep() async {
        guard !reduceMotion else { return }
        while !Task.isCancelled {
            withAnimation(.easeInOut(duration: 0.9)) { leading = true }
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.9)) { leading = false }
            try? await Task.sleep(for: .milliseconds(900))
        }
    }
}

// MARK: - Cover Intake Animation

/// A single cover at a time drops from above into the mini player's screen, fading and
/// shrinking as it "lands" — then the next one starts. Loops for as long as it's on
/// screen, cycling through the user's own covers as they become available, so an early
/// cycle (before `albums` has loaded) shows placeholder tiles and a later one shows the
/// real thing — covers genuinely arriving "one by one" as the library actually loads.
private struct CoverIntakeAnimation: View {
    let albums: [AppAlbum]
    let deviceHeight: CGFloat

    @State private var index = 0
    @State private var arrived = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let tile: CGFloat = 46

    private var covers: [AppAlbum] {
        Array(albums.lazy.filter { $0.musicKitAlbum?.artwork != nil || $0.mpArtwork != nil }.prefix(8))
    }

    var body: some View {
        cover
            .frame(width: tile, height: tile)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.35), radius: 5, y: 3)
            .scaleEffect(arrived ? 0.4 : 1)
            .opacity(arrived ? 0 : 1)
            .offset(y: arrived ? -deviceHeight * 0.3 : -deviceHeight * 0.62)
            .accessibilityHidden(true)
            .task { await loop() }
    }

    @ViewBuilder
    private var cover: some View {
        if !covers.isEmpty {
            let album = covers[index % covers.count]
            if let artwork = album.musicKitAlbum?.artwork {
                ArtworkImage(artwork, width: tile)
            } else {
                LocalArtworkImage(cacheKey: "accessRecovery.\(album.id)", size: tile, artwork: album.mpArtwork) { image in
                    image.resizable()
                } placeholder: {
                    placeholderTile
                }
            }
        } else {
            placeholderTile
        }
    }

    private var placeholderTile: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.white.opacity(0.12))
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.6))
            )
    }

    private func loop() async {
        while !Task.isCancelled {
            arrived = false
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? .easeInOut(duration: 0.4) : .spring(response: 0.5, dampingFraction: 0.72)) {
                arrived = true
            }
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            index += 1
        }
    }
}
