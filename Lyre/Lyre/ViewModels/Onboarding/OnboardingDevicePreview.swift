//
//  OnboardingDevicePreview.swift
//  Lyre
//

import SwiftUI

// MARK: - Device Preview
//
// A live miniature of Lyre as the user's choices currently stand — body finish, screen
// size and colors, highlight and wheel. OnboardingView keeps a single one on screen
// across the customization steps, so choosing a body, color or size transforms the
// same device rather than showing a new one on every page.
//
// Drawn at the real layout's proportions (screen dimensions and wheel size come from
// ScreenSize) and scaled down to `height`. It animates on its own when a choice lands:
// a small pulse when the style changes, and the highlight bar sweeping down the list
// when the highlight color changes. Its owner controls the rest:
//
//   screenShown / wheelShown   the welcome page assembles the device part by part
//   screenLevel                the backlight — 1 lit, near 0 dark — for the power-on
//                              at the end and the screen-timeout demonstration
//   onTap                      wakes the screen during that demonstration
//
// Purely visual: hidden from VoiceOver, which hears the choice itself from the option
// that was picked.

struct OnboardingDevicePreview: View {
    let themeSettings: ThemeSettings
    var height: CGFloat = 300
    var screenShown = true
    var wheelShown = true
    var screenLevel: Double = 1
    var onTap: (() -> Void)? = nil

    @State private var pulse = false
    /// The row the highlight passes through while sweeping; nil when resting.
    @State private var sweepRow: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let rows = [
        String(localized: "menu.nowPlaying"),
        String(localized: "menu.songs"),
        String(localized: "menu.albums"),
        String(localized: "menu.podcasts"),
        String(localized: "menu.settings"),
    ]
    private static let restingRow = 1

    private var theme: LyreTheme { themeSettings.currentTheme }
    private var screen: CGSize { themeSettings.screenSize.dimensions }
    private var wheel: CGFloat { themeSettings.screenSize.wheelSize }

    /// The device at full size: screen and wheel stacked with the body's margins.
    private var native: CGSize {
        CGSize(width: max(screen.width, wheel) + 48, height: screen.height + wheel + 84)
    }

    private var scale: CGFloat { height / native.height }

    var body: some View {
        VStack(spacing: 30) {
            OnboardingMiniScreen(theme: theme, title: String(localized: "app.name"), rows: rows,
                                 selection: sweepRow ?? Self.restingRow, fontScale: 1.25)
                .overlay {
                    // The backlight: dark when off, lit when on.
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.black.opacity((1 - screenLevel) * 0.82))
                        .allowsHitTesting(false)
                }
                .frame(width: screen.width, height: screen.height)
                .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
                .opacity(screenShown ? 1 : 0)
                .offset(y: screenShown ? 0 : -40)

            OnboardingPracticeWheel(theme: theme, size: wheel)
                .allowsHitTesting(false)
                .rotationEffect(.degrees(wheelShown ? 0 : -160))
                .scaleEffect(wheelShown ? 1 : 0.4)
                .opacity(wheelShown ? 1 : 0)
        }
        .padding(.vertical, 24)
        .frame(width: native.width, height: native.height)
        .background(
            RoundedRectangle(cornerRadius: 44)
                .fill(LinearGradient(colors: [theme.bodyGradientStart, theme.bodyGradientEnd],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
        )
        .scaleEffect(scale * (pulse ? 1.03 : 1))
        .frame(width: native.width * scale, height: height)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .animation(.easeInOut(duration: 0.3), value: themeSettings.themeStyle)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: themeSettings.screenSize)
        .onChange(of: themeSettings.themeStyle) { pulseOnce() }
        .onChange(of: theme.highlightColor) { sweepHighlight() }
        .accessibilityHidden(true)
    }

    private func pulseOnce() {
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) { pulse = true }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { pulse = false }
        }
    }

    /// Runs the new highlight color down the list and back to its resting row.
    private func sweepHighlight() {
        guard !reduceMotion else { return }
        Task {
            for row in [0, 1, 2, 3, 4, 3, 2] {
                sweepRow = row
                try? await Task.sleep(for: .milliseconds(55))
            }
            sweepRow = nil
        }
    }
}
