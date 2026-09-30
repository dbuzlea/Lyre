//
//  OnboardingCustomizeSteps.swift
//  Lyre
//

import SwiftUI

// MARK: - Make It Yours
//
// The customizations that used to share one crowded screen, one per step. The live
// device preview above them belongs to OnboardingView, which keeps the same one on
// screen from step to step so each choice visibly transforms it:
//
//   MakeItYoursStep   the choice to customize now or keep the classic look
//   BodyStyleStep     the five body families, each described in a sentence
//   FinishStep        the colors within the chosen family
//   HighlightStep     the selection-bar color
//   ScreenSizeStep    Auto (recommended) or a fixed size
//   WheelFeelStep     scroll sensitivity and click sound, tried on a working wheel
//   BacklightStep     how long the screen stays lit
//   DoneStep          a summary, and where to change things later
//
// Every choice is written straight to ThemeSettings, which saves it; there is nothing
// to apply at the end, and going Back shows the choice already made.

// MARK: - Body Families

enum OnboardingBodyFamily: CaseIterable, Identifiable {
    case signature, pebble, slim, clip, retro

    var id: Self { self }

    var styles: [LyreThemeStyle] {
        switch self {
        case .signature: return [.porcelain, .onyx, .sterling, .crimson, .monochrome]
        case .pebble:    return [.pebbleSilver, .pebbleGold, .pebbleBlue, .pebblePink, .pebbleGreen]
        case .slim:      return [.slim, .slimSilver, .slimBlack, .slimGraphite, .slimBlue,
                                 .slimPink, .slimPurple, .slimGreen, .slimYellow, .slimOrange, .slimRed]
        case .clip:      return [.clipSilver, .clipBlue, .clipPink, .clipGreen, .clipOrange, .clipPurple, .clipGold]
        case .retro:     return [.phosphor, .spectrum]
        }
    }

    var name: String {
        switch self {
        case .signature: return String(localized: "onboarding.family.signature")
        case .pebble:    return String(localized: "onboarding.family.pebble")
        case .slim:      return String(localized: "onboarding.family.slim")
        case .clip:      return String(localized: "onboarding.family.clip")
        case .retro:     return String(localized: "onboarding.family.retro")
        }
    }

    var detail: String {
        switch self {
        case .signature: return String(localized: "onboarding.family.signature.detail")
        case .pebble:    return String(localized: "onboarding.family.pebble.detail")
        case .slim:      return String(localized: "onboarding.family.slim.detail")
        case .clip:      return String(localized: "onboarding.family.clip.detail")
        case .retro:     return String(localized: "onboarding.family.retro.detail")
        }
    }

    static func family(of style: LyreThemeStyle) -> OnboardingBodyFamily {
        allCases.first { $0.styles.contains(style) } ?? .signature
    }

    /// The color's plain name within its family.
    static func finishName(for style: LyreThemeStyle) -> String {
        switch style {
        case .porcelain:    return String(localized: "color.white")
        case .onyx:         return String(localized: "color.black")
        case .sterling:     return String(localized: "color.silver")
        case .crimson:      return String(localized: "color.crimson")
        case .monochrome:   return String(localized: "color.blackAndWhite")
        case .pebbleSilver, .slimSilver, .clipSilver: return String(localized: "color.silver")
        case .pebbleGold, .clipGold:                  return String(localized: "color.gold")
        case .pebbleBlue, .slimBlue, .clipBlue:       return String(localized: "color.blue")
        case .pebblePink, .slimPink, .clipPink:       return String(localized: "color.pink")
        case .pebbleGreen, .slimGreen, .clipGreen:    return String(localized: "color.green")
        case .slim:         return String(localized: "color.classic")
        case .slimBlack:    return String(localized: "color.black")
        case .slimGraphite: return String(localized: "color.graphite")
        case .slimPurple, .clipPurple: return String(localized: "color.purple")
        case .slimYellow:   return String(localized: "color.yellow")
        case .slimOrange, .clipOrange: return String(localized: "color.orange")
        case .slimRed:      return String(localized: "color.red")
        case .phosphor:     return String(localized: "color.greenScreen")
        case .spectrum:     return String(localized: "color.colorScreen")
        }
    }
}

// MARK: - Shared

/// A tappable choice with a leading visual, a name, an optional explanation and a
/// checkmark when chosen. Large enough to hit easily, and read by VoiceOver as one
/// selectable button.
private struct ChoiceRow<Leading: View>: View {
    let title: String
    var detail: String? = nil
    var badge: String? = nil
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder var leading: Leading

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                leading
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(.white)
                    if let badge {
                        Text(badge)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Capsule().fill(.white.opacity(0.18)))
                            .foregroundStyle(.white)
                    }
                    if let detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.45))
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.white.opacity(isSelected ? 0.14 : 0.05))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(isSelected ? 0.8 : 0.12), lineWidth: isSelected ? 2 : 1))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A named color swatch in a grid.
private struct SwatchButton: View {
    let name: String
    let colors: [Color]
    /// A tiny screen with its highlight bar, drawn inside the body color. Finishes can
    /// share a body — Crimson is Black with a red highlight, Black & White is Black
    /// with a white screen — so the screen is what tells them apart.
    var screen: (background: [Color], highlight: Color)? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
                    if let screen {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(colors: screen.background, startPoint: .top, endPoint: .bottom))
                            .overlay {
                                Rectangle().fill(screen.highlight).frame(height: 5)
                            }
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(.black.opacity(0.3), lineWidth: 0.5))
                            .frame(width: 26, height: 18)
                    }
                    if isSelected {
                        Circle().stroke(.white, lineWidth: 3).padding(-5)
                        Image(systemName: "checkmark")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 2)
                    }
                }
                .frame(width: 52, height: 52)
                Text(name)
                    .font(.footnote.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(isSelected ? 1 : 0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private let swatchColumns = [GridItem(.adaptive(minimum: 84), spacing: 12)]

private func continueButton(_ action: @escaping () -> Void) -> some View {
    OnboardingPrimaryButton(title: String(localized: "onboarding.continue"), action: action)
}

// MARK: - Make It Yours

struct MakeItYoursStep: View {
    let themeSettings: ThemeSettings
    let onCustomize: () -> Void
    let onSkip: () -> Void

    var body: some View {
        OnboardingPage(title: String(localized: "onboarding.customize.title"),
                       message: String(localized: "onboarding.customize.message")) {
            EmptyView()
        } footer: {
            OnboardingPrimaryButton(title: String(localized: "onboarding.customize.start"), action: onCustomize)
            OnboardingSecondaryButton(title: String(localized: "onboarding.customize.skip"), action: onSkip)
        }
    }
}

// MARK: - Body Style

struct BodyStyleStep: View {
    let themeSettings: ThemeSettings
    let onNext: () -> Void

    private var current: OnboardingBodyFamily { .family(of: themeSettings.themeStyle) }

    var body: some View {
        OnboardingPage(title: String(localized: "onboarding.body.title"), compact: true,
                       message: String(localized: "onboarding.body.message")) {
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    ForEach(OnboardingBodyFamily.allCases) { family in
                        ChoiceRow(title: family.name, detail: family.detail, isSelected: current == family) {
                            guard current != family else { return }
                            themeSettings.themeStyle = family.styles[0]
                        } leading: {
                            familyThumbnail(family)
                        }
                    }
                }
            }
        } footer: {
            continueButton(onNext)
        }
    }

    /// The family's first few finishes, overlapping.
    private func familyThumbnail(_ family: OnboardingBodyFamily) -> some View {
        HStack(spacing: -10) {
            ForEach(Array(family.styles.prefix(3)), id: \.self) { style in
                let theme = LyreTheme.theme(for: style)
                Circle()
                    .fill(LinearGradient(colors: [theme.bodyGradientStart, theme.bodyGradientEnd],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Circle().stroke(.black.opacity(0.3), lineWidth: 1))
                    .frame(width: 26, height: 26)
            }
        }
        .frame(width: 58, alignment: .leading)
        .accessibilityHidden(true)
    }
}

// MARK: - Finish

struct FinishStep: View {
    let themeSettings: ThemeSettings
    let onNext: () -> Void

    private var family: OnboardingBodyFamily { .family(of: themeSettings.themeStyle) }

    var body: some View {
        OnboardingPage(title: String(localized: "onboarding.finish.title"), compact: true,
                       message: String(format: String(localized: "onboarding.finish.message"), family.name)) {
            VStack(spacing: 20) {
                LazyVGrid(columns: swatchColumns, spacing: 12) {
                    ForEach(family.styles, id: \.self) { style in
                        let theme = LyreTheme.theme(for: style)
                        SwatchButton(name: OnboardingBodyFamily.finishName(for: style),
                                     colors: [theme.bodyGradientStart, theme.bodyGradientEnd],
                                     screen: (theme.screenBackgroundLight, theme.highlightColor),
                                     isSelected: themeSettings.themeStyle == style) {
                            themeSettings.themeStyle = style
                        }
                    }
                }
            }
        } footer: {
            continueButton(onNext)
        }
    }
}

// MARK: - Highlight

struct HighlightStep: View {
    let themeSettings: ThemeSettings
    let onNext: () -> Void

    var body: some View {
        OnboardingPage(title: String(localized: "onboarding.highlight.title"), compact: true,
                       message: String(localized: "onboarding.highlight.message")) {
            VStack(spacing: 20) {

                ChoiceRow(title: String(localized: "onboarding.highlight.default"),
                          detail: String(localized: "onboarding.highlight.default.detail"),
                          badge: String(localized: "onboarding.recommended"),
                          isSelected: !themeSettings.useCustomHighlight) {
                    themeSettings.useCustomHighlight = false
                } leading: {
                    Circle()
                        .fill(LyreTheme.theme(for: themeSettings.themeStyle).highlightColor)
                        .frame(width: 30, height: 30)
                        .accessibilityHidden(true)
                }

                LazyVGrid(columns: swatchColumns, spacing: 12) {
                    ForEach(LyreColors.finishColorOptions) { option in
                        SwatchButton(name: option.name, colors: [option.color, option.color],
                                     isSelected: themeSettings.useCustomHighlight && Self.matches(themeSettings.customHighlightColor, option.color)) {
                            themeSettings.customHighlightColor = option.color
                            themeSettings.useCustomHighlight = true
                        }
                    }
                }
            }
        } footer: {
            continueButton(onNext)
        }
    }

    /// Same tolerance as the Highlight Color setting, which compares stored colors.
    private static func matches(_ a: Color, _ b: Color) -> Bool {
        let x = a.toStorableColor(), y = b.toStorableColor()
        return abs(x.red - y.red) < 0.1 && abs(x.green - y.green) < 0.1 && abs(x.blue - y.blue) < 0.1
    }
}

// MARK: - Screen Size

struct ScreenSizeStep: View {
    let themeSettings: ThemeSettings
    let onNext: () -> Void

    var body: some View {
        OnboardingPage(title: String(localized: "onboarding.size.title"), compact: true,
                       message: String(localized: "onboarding.size.message")) {
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    ChoiceRow(title: String(localized: "onboarding.size.auto"),
                              detail: String(format: String(localized: "onboarding.size.auto.detail"),
                                             themeSettings.themeStyle.defaultScreenSize.rawValue),
                              badge: String(localized: "onboarding.recommended"),
                              isSelected: themeSettings.useAutoScreenSize) {
                        themeSettings.useAutoScreenSize = true
                    } leading: {
                        sizeIcon(themeSettings.themeStyle.defaultScreenSize)
                    }
                    ForEach(ScreenSize.allCases) { size in
                        ChoiceRow(title: size.rawValue,
                                  isSelected: !themeSettings.useAutoScreenSize && themeSettings.screenSize == size) {
                            themeSettings.useAutoScreenSize = false
                            themeSettings.screenSize = size
                        } leading: {
                            sizeIcon(size)
                        }
                    }
                }
            }
        } footer: {
            continueButton(onNext)
        }
    }

    /// The screen's shape, drawn to scale.
    private func sizeIcon(_ size: ScreenSize) -> some View {
        let d = size.dimensions
        let scale = 34 / max(d.width, d.height)
        return RoundedRectangle(cornerRadius: 3)
            .stroke(.white.opacity(0.8), lineWidth: 1.5)
            .frame(width: d.width * scale, height: d.height * scale)
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)
    }
}

// MARK: - Wheel Feel

struct WheelFeelStep: View {
    let themeSettings: ThemeSettings
    let onNext: () -> Void

    @State private var selection = 0
    private let rows = (1...30).map { String(format: String(localized: "onboarding.feel.row"), $0) }

    var body: some View {
        OnboardingPage(title: String(localized: "onboarding.feel.title"), compact: true,
                       message: String(localized: "onboarding.feel.message")) {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "onboarding.feel.speed"))
                        .font(.headline)
                        .foregroundStyle(.white)
                    Picker(String(localized: "onboarding.feel.speed"), selection: Binding(
                        get: { themeSettings.scrollSensitivity },
                        set: { themeSettings.scrollSensitivity = $0 }
                    )) {
                        Text(String(localized: "onboarding.feel.low")).tag(ScrollSensitivity.low)
                        Text(String(localized: "onboarding.feel.medium")).tag(ScrollSensitivity.medium)
                        Text(String(localized: "onboarding.feel.high")).tag(ScrollSensitivity.high)
                    }
                    .pickerStyle(.segmented)
                    Text(speedDetail)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }

                OnboardingMiniScreen(theme: themeSettings.currentTheme, title: String(localized: "onboarding.feel.screenTitle"),
                                     rows: rows, selection: selection)
                    .frame(width: 220, height: 100)

                OnboardingPracticeWheel(
                    theme: themeSettings.currentTheme,
                    sensitivity: themeSettings.scrollSensitivity,
                    clickSound: themeSettings.clickSoundEnabled,
                    size: 200,
                    onScroll: { selection = min(max(selection + $0, 0), rows.count - 1) }
                )

                Toggle(isOn: Binding(
                    get: { themeSettings.clickSoundEnabled },
                    set: { themeSettings.clickSoundEnabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "onboarding.feel.click")).font(.headline).foregroundStyle(.white)
                        Text(String(localized: "onboarding.feel.click.detail"))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.05)))
            }
        } footer: {
            continueButton(onNext)
        }
    }

    private var speedDetail: String {
        switch themeSettings.scrollSensitivity {
        case .low:    return String(localized: "onboarding.feel.low.detail")
        case .medium: return String(localized: "onboarding.feel.medium.detail")
        case .high:   return String(localized: "onboarding.feel.high.detail")
        }
    }
}

// MARK: - Backlight

struct BacklightStep: View {
    let themeSettings: ThemeSettings
    let onNext: () -> Void

    var body: some View {
        OnboardingPage(title: String(localized: "onboarding.backlight.title"), compact: true,
                       message: String(localized: "onboarding.backlight.message")) {
            VStack(spacing: 10) {
                Text(String(localized: "onboarding.backlight.demo"))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 4)
                ForEach(BacklightDuration.allCases, id: \.self) { duration in
                    ChoiceRow(title: title(for: duration),
                              detail: detail(for: duration),
                              badge: duration == .tenSeconds ? String(localized: "onboarding.recommended") : nil,
                              isSelected: themeSettings.backlightDuration == duration) {
                        themeSettings.backlightDuration = duration
                    } leading: {
                        Image(systemName: duration == .alwaysOn ? "sun.max.fill" : "timer")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 36)
                            .accessibilityHidden(true)
                    }
                }
            }
        } footer: {
            continueButton(onNext)
        }
    }

    private func title(for duration: BacklightDuration) -> String {
        switch duration {
        case .fiveSeconds:   return String(localized: "onboarding.backlight.5")
        case .tenSeconds:    return String(localized: "onboarding.backlight.10")
        case .thirtySeconds: return String(localized: "onboarding.backlight.30")
        case .alwaysOn:      return String(localized: "onboarding.backlight.always")
        }
    }

    private func detail(for duration: BacklightDuration) -> String? {
        switch duration {
        case .thirtySeconds: return String(localized: "onboarding.backlight.30.detail")
        case .alwaysOn:      return String(localized: "onboarding.backlight.always.detail")
        default:             return nil
        }
    }
}

// MARK: - Done

struct DoneStep: View {
    let themeSettings: ThemeSettings
    let onFinish: () -> Void

    var body: some View {
        OnboardingPage(title: String(localized: "onboarding.allSet"), compact: true,
                       message: String(localized: "onboarding.done.message")) {
            VStack(spacing: 20) {
                VStack(spacing: 0) {
                    summaryRow("onboarding.done.style",
                               "\(OnboardingBodyFamily.family(of: themeSettings.themeStyle).name) · \(OnboardingBodyFamily.finishName(for: themeSettings.themeStyle))")
                    summaryRow("onboarding.done.highlight",
                               themeSettings.useCustomHighlight ? String(localized: "onboarding.done.custom") : String(localized: "onboarding.highlight.default"))
                    summaryRow("onboarding.done.size",
                               themeSettings.useAutoScreenSize ? String(localized: "onboarding.size.auto") : themeSettings.screenSize.rawValue)
                    summaryRow("onboarding.done.speed", themeSettings.scrollSensitivity.rawValue)
                    summaryRow("onboarding.done.click",
                               themeSettings.clickSoundEnabled ? String(localized: "onboarding.on") : String(localized: "onboarding.off"))
                    summaryRow("onboarding.done.backlight", themeSettings.backlightDuration.rawValue, last: true)
                }
                .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06)))

                Text(String(localized: "onboarding.done.replay"))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
            }
        } footer: {
            OnboardingPrimaryButton(title: String(localized: "onboarding.startListening"), action: onFinish)
        }
    }

    private func summaryRow(_ label: String.LocalizationValue, _ value: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: label)).font(.body).foregroundStyle(.white.opacity(0.8))
                Spacer(minLength: 12)
                Text(value).font(.body.weight(.semibold)).foregroundStyle(.white).multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .accessibilityElement(children: .combine)
            if !last { Divider().overlay(.white.opacity(0.12)).padding(.leading, 16) }
        }
    }
}
