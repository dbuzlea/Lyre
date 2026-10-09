//
//  SpoolSettingsView.swift
//  Lyre
//

import SwiftUI

// MARK: - Spool Settings
//
// The Spool's settings, opened from the original's orange hotline button or the slim's
// options button. It is laid out like the player's printed owner's manual: cream paper,
// numbered sections, and a drawing of each design in the chosen finish.
//
// Design and finish change the player behind the sheet as they're picked, so the
// effect can be seen without closing it.
//
// The first section is a tutorial: the same acted-out lessons onboarding shows when the
// Spool is chosen (see SpoolTour), to watch again whenever.

struct SpoolSettingsView: View {
    @ObservedObject var musicService: MusicService
    @Bindable var themeSettings: ThemeSettings
    let foldMonitor: FoldPostureMonitor
    let onDone: () -> Void

    private static let paper = Color(red: 0.957, green: 0.929, blue: 0.871) // #F4EDDE
    private static let ink = SpoolPalette.labelInk

    private var theme: SpoolTheme { themeSettings.spoolFinish.theme }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header

                section(1, String(localized: "spool.settings.tutorial")) {
                    SpoolTourPager(theme: theme, appearance: .manual)
                        .padding(.top, 4)
                }

                section(2, String(localized: "spool.design")) {
                    HStack(spacing: 12) {
                        ForEach(SpoolModel.allCases) { designCard($0) }
                    }
                }

                section(3, String(localized: "spool.finish")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 16) {
                        ForEach(SpoolFinish.allCases) { finishSwatch($0) }
                    }
                }

                section(4, String(localized: "spool.settings.sound")) {
                    Toggle(isOn: $themeSettings.clickSoundEnabled) {
                        rowLabel(String(localized: "spool.settings.soundEffects"),
                                 detail: String(localized: "spool.settings.soundEffects.detail"))
                    }
                    .accessibilityIdentifier("spool.settings.sound")
                }

                section(5, String(localized: "spool.settings.playback")) {
                    VStack(alignment: .leading, spacing: 18) {
                        Toggle(isOn: Binding(
                            get: { musicService.shuffleMode != .off },
                            set: { _ in Task { await musicService.toggleShuffleMode() } }
                        )) {
                            rowLabel(String(localized: "spool.settings.shuffle"))
                        }
                        HStack {
                            rowLabel(String(localized: "spool.settings.repeat"))
                            Spacer(minLength: 16)
                            Picker(String(localized: "spool.settings.repeat"), selection: Binding(
                                get: { musicService.repeatMode },
                                set: setRepeat
                            )) {
                                Text(String(localized: "spool.settings.repeat.off")).tag(RepeatMode.off)
                                Text(String(localized: "spool.settings.repeat.all")).tag(RepeatMode.all)
                                Text(String(localized: "spool.settings.repeat.one")).tag(RepeatMode.one)
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 190)
                        }
                        HStack {
                            rowLabel(String(localized: "spool.speed"))
                            Spacer(minLength: 16)
                            Picker(String(localized: "spool.speed"), selection: Binding(
                                get: { musicService.podcastRate },
                                set: { musicService.setPodcastRate($0) }
                            )) {
                                ForEach(MusicService.podcastRates, id: \.self) { rate in
                                    Text(SpoolPlayerView.speedText(rate)).tag(rate)
                                }
                            }
                            .pickerStyle(.menu)
                            .accessibilityIdentifier("spool.settings.speed")
                        }
                    }
                }

                section(6, String(localized: "spool.settings.player")) {
                    Button {
                        onDone()
                        themeSettings.playerStyle = .classic
                    } label: {
                        HStack {
                            rowLabel(String(localized: "spool.switchToClassic"),
                                     detail: String(localized: "spool.settings.classic.detail"))
                            Spacer(minLength: 8)
                            Image(systemName: "circle.circle")
                                .font(.system(size: 22))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("spool.settings.classic")

                    Button {
                        onDone()
                        themeSettings.playerStyle = .gramophone
                    } label: {
                        HStack {
                            rowLabel(String(format: String(localized: "gramophone.settings.switchTo"),
                                            PlayerStyle.gramophone.displayName))
                            Spacer(minLength: 8)
                            Image(systemName: "opticaldisc")
                                .font(.system(size: 22))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                    .accessibilityIdentifier("spool.settings.gramophone")
                }

                #if DEBUG
                section(7, "Debug") {
                    Picker("Fold Posture", selection: Binding(
                        get: { foldMonitor.debugOverride },
                        set: { foldMonitor.debugOverride = $0 }
                    )) {
                        Text("Device").tag(FoldPosture?.none)
                        ForEach(FoldPosture.allCases) { posture in
                            Text(posture.debugName).tag(Optional(posture))
                        }
                    }
                    .pickerStyle(.segmented)
                }
                #endif

                footer
            }
            .padding(24)
        }
        .foregroundStyle(Self.ink)
        .tint(theme.isLight ? theme.logo : theme.accent)
        .background(Self.paper.ignoresSafeArea())
        // Paper is paper, in dark mode too.
        .environment(\.colorScheme, .light)
        .accessibilityIdentifier("spool.settings.sheet")
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "spool.brand"))
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .tracking(4)
                Text(String(localized: "spool.settings.manual"))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2)
                    .opacity(0.6)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(String(localized: "spool.settings.done"), action: onDone)
                .font(.system(size: 16, weight: .semibold))
                .accessibilityIdentifier("spool.settings.done")
        }
        .overlay(alignment: .bottom) {
            Rectangle().frame(height: 2).offset(y: 14)
        }
        .padding(.bottom, 8)
    }

    private func section<Content: View>(_ number: Int, _ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("\(number)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Self.paper)
                    .frame(width: 20, height: 20)
                    .background(Self.ink, in: Circle())
                    .accessibilityHidden(true)
                Text(title.uppercased())
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.5)
                    .accessibilityAddTraits(.isHeader)
            }
            content()
        }
    }

    private func rowLabel(_ title: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
            if let detail {
                Text(detail)
                    .font(.system(size: 12))
                    .opacity(0.6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func designCard(_ model: SpoolModel) -> some View {
        let isSelected = themeSettings.spoolModel == model
        return Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { themeSettings.spoolModel = model }
        } label: {
            VStack(spacing: 10) {
                DesignSketch(model: model, theme: theme)
                    .frame(height: 92)
                Text(model.displayName)
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(.white.opacity(isSelected ? 0.6 : 0.3), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Self.ink.opacity(isSelected ? 1 : 0.15), lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("spool.settings.design.\(model.rawValue)")
    }

    private func finishSwatch(_ finish: SpoolFinish) -> some View {
        let isSelected = themeSettings.spoolFinish == finish
        let swatch = finish.theme
        return Button {
            withAnimation(.easeInOut(duration: 0.35)) { themeSettings.spoolFinish = finish }
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(swatch.bodyGradient)
                    .overlay(Circle().strokeBorder(swatch.railGradient, lineWidth: 5))
                    .overlay(alignment: .topTrailing) {
                        Circle().fill(swatch.accent).frame(width: 10, height: 10).offset(x: -4, y: 4)
                    }
                    .frame(width: 46, height: 46)
                    .padding(4)
                    .overlay(Circle().strokeBorder(Self.ink.opacity(isSelected ? 1 : 0), lineWidth: 2))
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                Text(finish.displayName)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("spool.settings.finish.\(finish.rawValue)")
    }

    private var footer: some View {
        Text(String(localized: "about.version").replacingOccurrences(of: "%@", with: versionString))
            .font(.system(size: 11))
            .opacity(0.5)
            .frame(maxWidth: .infinity)
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        guard let build = info?["CFBundleVersion"] as? String else { return version }
        return "\(version) (\(build))"
    }

    /// The player cycles repeat Off → All → One; step it round to the mode picked.
    private func setRepeat(_ mode: RepeatMode) {
        Task {
            for _ in RepeatMode.allCases where musicService.repeatMode != mode {
                await musicService.toggleRepeatMode()
            }
        }
    }
}

// MARK: - Design Sketch

/// A small drawing of one of the designs in a finish, as in the manual's diagrams.
struct DesignSketch: View {
    let model: SpoolModel
    let theme: SpoolTheme

    var body: some View {
        switch model {
        case .original: original
        case .slim:     slim
        }
    }

    /// Upright body, a door with a small window, and the rail of keys down the right.
    private var original: some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 6)
                .fill(theme.bodyGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(.black.opacity(0.25), lineWidth: 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(theme.bay)
                                .frame(width: 16, height: 26)
                        )
                        .padding(7)
                )
                .frame(width: 44)
            VStack(spacing: 2) {
                Capsule().fill(theme.accent).frame(width: 10, height: 5)
                Spacer(minLength: 0)
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1.5).fill(theme.keyLight).frame(width: 10, height: 9)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .frame(width: 14)
            .background(theme.railGradient, in: RoundedRectangle(cornerRadius: 5))
        }
        .frame(height: 88)
        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
        .accessibilityHidden(true)
    }

    /// Keys along the top edge, the logo plate, and a pill-shaped window.
    private var slim: some View {
        VStack(spacing: 5) {
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1.5).fill(theme.keyLight).frame(width: 11, height: 6)
                }
                Spacer(minLength: 0)
            }
            RoundedRectangle(cornerRadius: 2)
                .fill(theme.railGradient)
                .frame(height: 10)
            Capsule()
                .fill(theme.bay)
                .frame(height: 22)
                .padding(.horizontal, 4)
            Spacer(minLength: 0)
        }
        .padding(7)
        .frame(width: 96, height: 72)
        .background(theme.bodyGradient, in: RoundedRectangle(cornerRadius: 7))
        .frame(height: 88)
        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
        .accessibilityHidden(true)
    }
}
