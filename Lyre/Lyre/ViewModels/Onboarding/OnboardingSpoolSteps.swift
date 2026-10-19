//
//  OnboardingSpoolSteps.swift
//  Lyre
//

import SwiftUI

// MARK: - Choosing a Player
//
// After music access, onboarding asks which player to use: the classic click wheel or
// the Spool cassette deck. The rest of the journey follows the choice (see
// `OnboardingStep.path(for:)`):
//
//   Classic   meet the wheel → practice → shortcuts → make it yours → … → summary
//   Spool     meet the Spool → design and finish → summary
//   Gramophone  design and finish → summary
//   Disc      meet the Disc → finish → summary
//   Liquid    meet Liquid → summary (it has nothing to choose: the music colours it)
//
// The Spool's lessons are the acted-out tour the owner's manual keeps (SpoolTour), so
// what's learned here can be watched again later from the player itself.

struct ChoosePlayerStep: View {
    let themeSettings: ThemeSettings
    let onNext: () -> Void

    var body: some View {
        OnboardingPage(title: String(localized: "onboarding.player.title"), compact: true,
                       message: String(localized: "onboarding.player.message")) {
            VStack(spacing: 20) {
                // The player chosen, as it will look.
                ZStack {
                    if themeSettings.playerStyle == .spool {
                        SpoolOnboardingPreview(themeSettings: themeSettings, height: 160)
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    } else if themeSettings.playerStyle == .gramophone {
                        GramophoneOnboardingPreview(themeSettings: themeSettings, height: 160)
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    } else if themeSettings.playerStyle == .disc {
                        DiscOnboardingPreview(themeSettings: themeSettings, height: 160)
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    } else if themeSettings.playerStyle == .liquid {
                        LiquidOnboardingPreview(height: 160)
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    } else {
                        OnboardingDevicePreview(themeSettings: themeSettings, height: 160)
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    }
                }
                .frame(height: 170)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: themeSettings.playerStyle)

                VStack(spacing: 10) {
                    choice(.classic, symbol: "circle.circle",
                           detail: String(localized: "onboarding.player.classic.detail"))
                    choice(.spool, symbol: "recordingtape",
                           detail: String(localized: "onboarding.player.spool.detail"))
                    choice(.gramophone, symbol: "opticaldisc",
                           detail: String(localized: "onboarding.player.gramophone.detail"))
                    choice(.disc, symbol: "opticaldiscdrive",
                           detail: String(localized: "onboarding.player.disc.detail"))
                    choice(.liquid, symbol: "drop",
                           detail: String(localized: "onboarding.player.liquid.detail"))
                }
            }
        } footer: {
            continueButton(onNext)
        }
    }

    private func choice(_ style: PlayerStyle, symbol: String, detail: String) -> some View {
        ChoiceRow(title: style.displayName, detail: detail, isSelected: themeSettings.playerStyle == style) {
            guard themeSettings.playerStyle != style else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            themeSettings.playerStyle = style
        } leading: {
            Image(systemName: symbol)
                .font(.title)
                .foregroundStyle(.white)
                .frame(width: 44)
                .accessibilityHidden(true)
        }
        .accessibilityIdentifier("onboarding.player.\(style.rawValue)")
    }
}

// MARK: - Meet the Spool

struct MeetTheSpoolStep: View {
    let themeSettings: ThemeSettings
    let onNext: () -> Void

    var body: some View {
        OnboardingPage(title: String(localized: "onboarding.spool.title"), compact: true,
                       message: String(localized: "onboarding.spool.message")) {
            SpoolTourPager(theme: themeSettings.spoolFinish.theme, appearance: .onboarding)
        } footer: {
            continueButton(onNext)
        }
    }
}

// MARK: - Spool Design and Finish

struct SpoolStyleStep: View {
    let themeSettings: ThemeSettings
    let onNext: () -> Void

    var body: some View {
        OnboardingPage(title: String(localized: "onboarding.spoolStyle.title"), compact: true,
                       message: String(localized: "onboarding.spoolStyle.message")) {
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    ForEach(SpoolModel.allCases) { model in
                        ChoiceRow(title: model.displayName,
                                  detail: String(localized: model == .original
                                                 ? "onboarding.spoolStyle.original.detail"
                                                 : "onboarding.spoolStyle.slim.detail"),
                                  isSelected: themeSettings.spoolModel == model) {
                            themeSettings.spoolModel = model
                        } leading: {
                            DesignSketch(model: model, theme: themeSettings.spoolFinish.theme)
                                .scaleEffect(0.5)
                                .frame(width: 52, height: 46)
                                .accessibilityHidden(true)
                        }
                    }
                }

                LazyVGrid(columns: swatchColumns, spacing: 12) {
                    ForEach(SpoolFinish.allCases) { finish in
                        let theme = finish.theme
                        SwatchButton(name: finish.displayName,
                                     colors: [theme.bodyLight, theme.body],
                                     isSelected: themeSettings.spoolFinish == finish) {
                            themeSettings.spoolFinish = finish
                        }
                    }
                }
            }
        } footer: {
            continueButton(onNext)
        }
    }
}

// MARK: - Preview

/// The Spool as chosen so far: the manual's drawing of the design, in the finish,
/// scaled up to `height`. Purely visual.
struct SpoolOnboardingPreview: View {
    let themeSettings: ThemeSettings
    var height: CGFloat = 200

    /// The drawing's own height (see DesignSketch).
    private static let sketchHeight: CGFloat = 88

    var body: some View {
        DesignSketch(model: themeSettings.spoolModel, theme: themeSettings.spoolFinish.theme)
            .scaleEffect(height / Self.sketchHeight)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: themeSettings.spoolModel)
            .animation(.easeInOut(duration: 0.3), value: themeSettings.spoolFinish)
            .accessibilityHidden(true)
    }
}

// MARK: - Gramophone Design and Finish

struct GramophoneStyleStep: View {
    let themeSettings: ThemeSettings
    let onNext: () -> Void

    var body: some View {
        OnboardingPage(title: String(localized: "onboarding.spoolStyle.title"), compact: true,
                       message: String(localized: "onboarding.gramophoneStyle.message")) {
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    ForEach(GramophoneModel.allCases) { model in
                        ChoiceRow(title: model.displayName,
                                  detail: String(localized: model == .horn
                                                 ? "onboarding.gramophoneStyle.horn.detail"
                                                 : "onboarding.gramophoneStyle.cabinet.detail"),
                                  isSelected: themeSettings.gramophoneModel == model) {
                            themeSettings.gramophoneModel = model
                        } leading: {
                            GramophoneSketch(model: model, theme: themeSettings.gramophoneFinish.theme)
                                .scaleEffect(0.5)
                                .frame(width: 52, height: 46)
                                .accessibilityHidden(true)
                        }
                    }
                }

                LazyVGrid(columns: swatchColumns, spacing: 12) {
                    ForEach(GramophoneFinish.allCases) { finish in
                        let theme = finish.theme
                        SwatchButton(name: finish.displayName,
                                     colors: [theme.woodLight, theme.woodDark],
                                     isSelected: themeSettings.gramophoneFinish == finish) {
                            themeSettings.gramophoneFinish = finish
                        }
                    }
                }
            }
        } footer: {
            continueButton(onNext)
        }
    }
}

/// The Gramophone as chosen so far: the booklet's drawing of the design, in the
/// finish, scaled up to `height`. Purely visual.
struct GramophoneOnboardingPreview: View {
    let themeSettings: ThemeSettings
    var height: CGFloat = 200

    var body: some View {
        GramophoneSketch(model: themeSettings.gramophoneModel, theme: themeSettings.gramophoneFinish.theme)
            .scaleEffect(height / 88)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: themeSettings.gramophoneModel)
            .animation(.easeInOut(duration: 0.3), value: themeSettings.gramophoneFinish)
            .accessibilityHidden(true)
    }
}

// MARK: - Meet the Disc

struct MeetTheDiscStep: View {
    let themeSettings: ThemeSettings
    let onNext: () -> Void

    var body: some View {
        OnboardingPage(title: String(localized: "onboarding.disc.title"), compact: true,
                       message: String(localized: "onboarding.disc.message")) {
            DiscTourPager(theme: themeSettings.discFinish.theme, ink: .white)
        } footer: {
            continueButton(onNext)
        }
    }
}

// MARK: - Disc Finish

struct DiscStyleStep: View {
    let themeSettings: ThemeSettings
    let onNext: () -> Void

    var body: some View {
        OnboardingPage(title: String(localized: "onboarding.spoolStyle.title"), compact: true,
                       message: String(localized: "onboarding.discStyle.message")) {
            LazyVGrid(columns: swatchColumns, spacing: 12) {
                ForEach(DiscFinish.allCases) { finish in
                    let theme = finish.theme
                    SwatchButton(name: finish.displayName,
                                 colors: [theme.bodyLight, theme.bodyDark],
                                 isSelected: themeSettings.discFinish == finish) {
                        themeSettings.discFinish = finish
                    }
                }
            }
        } footer: {
            continueButton(onNext)
        }
    }
}

/// The Disc as chosen so far, in its finish, scaled up to `height`. Purely visual.
struct DiscOnboardingPreview: View {
    let themeSettings: ThemeSettings
    var height: CGFloat = 200

    var body: some View {
        DiscSketch(theme: themeSettings.discFinish.theme)
            .scaleEffect(height / DiscSketch.height)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.3), value: themeSettings.discFinish)
            .accessibilityHidden(true)
    }
}

// MARK: - Liquid

/// The Liquid player in miniature: a cover filling a phone, with the wave on its right
/// edge pulled part way in, carrying the next one. Purely visual.
struct LiquidOnboardingPreview: View {
    var height: CGFloat = 200

    var body: some View {
        let width = height * 0.5
        ZStack {
            LinearGradient(colors: [Color(red: 0.17, green: 0.29, blue: 0.48), Color(red: 0.09, green: 0.14, blue: 0.22)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(Color(red: 0.91, green: 0.54, blue: 0.23))
                .frame(width: width * 0.5)
                .offset(x: -width * 0.12, y: -height * 0.14)
            LinearGradient(colors: [Color(red: 0.54, green: 0.23, blue: 0.29), Color(red: 0.16, green: 0.08, blue: 0.13)],
                           startPoint: .top, endPoint: .bottom)
                .mask(LiquidWaveShape(side: .right, centerY: height * 0.45, progress: 0.24))
            VStack(alignment: .leading, spacing: 3) {
                Spacer()
                Capsule().fill(.white).frame(width: width * 0.5, height: 5)
                Capsule().fill(.white.opacity(0.6)).frame(width: width * 0.32, height: 4)
                Capsule().fill(.white.opacity(0.35)).frame(height: 2).padding(.top, 6)
            }
            .padding(10)
            .padding(.bottom, 8)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: width * 0.14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: width * 0.14, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 1.5))
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

// MARK: - Meet Liquid

struct MeetLiquidStep: View {
    let onNext: () -> Void

    var body: some View {
        OnboardingPage(title: String(localized: "onboarding.liquid.title"), compact: true,
                       message: String(localized: "onboarding.liquid.message")) {
            LiquidTourPager(ink: .white)
        } footer: {
            continueButton(onNext)
        }
    }
}
