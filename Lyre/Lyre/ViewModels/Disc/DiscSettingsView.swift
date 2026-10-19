//
//  DiscSettingsView.swift
//  Lyre
//

import SwiftUI

// MARK: - Disc Settings
//
// The Disc's settings, opened from the button beside AirPlay. Laid out like the
// operating instructions folded into a player's box: white paper, numbered sections, and
// a swatch of each finish. A finish changes the player behind the sheet as it's picked.
//
// The first section is the tutorial (see DiscTour), the same lessons onboarding shows
// when the Disc is chosen.

struct DiscSettingsView: View {
    @ObservedObject var musicService: MusicService
    @Bindable var themeSettings: ThemeSettings
    let foldMonitor: FoldPostureMonitor
    let onDone: () -> Void

    private static let paper = Color(red: 0.965, green: 0.965, blue: 0.95)
    private static let ink = SpoolPalette.labelInk

    private var theme: DiscTheme { themeSettings.discFinish.theme }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header

                section(1, String(localized: "spool.settings.tutorial")) {
                    DiscTourPager(theme: theme)
                        .padding(.top, 4)
                }

                section(2, String(localized: "disc.settings.finish")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 16) {
                        ForEach(DiscFinish.allCases) { finishSwatch($0) }
                    }
                }

                section(3, String(localized: "spool.settings.sound")) {
                    Toggle(isOn: $themeSettings.clickSoundEnabled) {
                        rowLabel(String(localized: "spool.settings.soundEffects"),
                                 detail: String(localized: "disc.settings.soundEffects.detail"))
                    }
                    .accessibilityIdentifier("disc.settings.sound")
                }

                section(4, String(localized: "spool.settings.playback")) {
                    VStack(alignment: .leading, spacing: 18) {
                        Toggle(isOn: Binding(
                            get: { musicService.shuffleMode != .off },
                            set: { _ in Task { await musicService.toggleShuffleMode() } }
                        )) {
                            rowLabel(String(localized: "disc.random.label"))
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
                            .accessibilityIdentifier("disc.settings.speed")
                        }
                    }
                }

                section(5, String(localized: "spool.settings.player")) {
                    VStack(alignment: .leading, spacing: 14) {
                        switchButton(.classic, title: String(localized: "spool.switchToClassic"),
                                     detail: String(localized: "spool.settings.classic.detail"), symbol: "circle.circle")
                        switchButton(.spool, symbol: "recordingtape")
                        switchButton(.gramophone, symbol: "opticaldisc")
                        switchButton(.liquid, symbol: "drop")
                    }
                }

                #if DEBUG
                section(6, "Debug") {
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
        .tint(theme.accent)
        .background(Self.paper.ignoresSafeArea())
        // Paper is paper, in dark mode too.
        .environment(\.colorScheme, .light)
        .accessibilityIdentifier("disc.settings.sheet")
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "disc.brand"))
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .italic()
                    .tracking(4)
                Text(String(localized: "disc.settings.manual"))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2)
                    .opacity(0.6)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(String(localized: "spool.settings.done"), action: onDone)
                .font(.system(size: 16, weight: .semibold))
                .accessibilityIdentifier("disc.settings.done")
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

    private func switchButton(_ style: PlayerStyle, title: String? = nil, detail: String? = nil,
                              symbol: String) -> some View {
        Button {
            onDone()
            themeSettings.playerStyle = style
        } label: {
            HStack {
                rowLabel(title ?? String(format: String(localized: "gramophone.settings.switchTo"), style.displayName),
                         detail: detail)
                Spacer(minLength: 8)
                Image(systemName: symbol)
                    .font(.system(size: 22))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("disc.settings.\(style.rawValue)")
    }

    private func finishSwatch(_ finish: DiscFinish) -> some View {
        let isSelected = themeSettings.discFinish == finish
        return Button {
            withAnimation(.easeInOut(duration: 0.35)) { themeSettings.discFinish = finish }
        } label: {
            VStack(spacing: 6) {
                DiscFinishSwatch(theme: finish.theme)
                    .frame(width: 50, height: 50)
                    .padding(4)
                    .overlay(Circle().strokeBorder(Self.ink.opacity(isSelected ? 1 : 0), lineWidth: 2))
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
        .accessibilityIdentifier("disc.settings.finish.\(finish.rawValue)")
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

/// A finish in a circle: the body round the edge, the lid in the middle, and the LCD's
/// colour in a band across it.
struct DiscFinishSwatch: View {
    let theme: DiscTheme

    var body: some View {
        ZStack {
            Circle().fill(theme.bodyGradient)
            Circle().fill(theme.lid.opacity(0.75)).padding(7)
            Capsule().fill(theme.lcd).frame(width: 24, height: 7).offset(y: 12)
            Circle().fill(theme.accent).frame(width: 8, height: 8).offset(x: 13, y: -13)
        }
        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
        .accessibilityHidden(true)
    }
}

/// A small drawing of the player in a finish: the round deck under its lid, the display
/// and the keys.
struct DiscSketch: View {
    let theme: DiscTheme

    /// The drawing's own height.
    static let height: CGFloat = 88

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().fill(LinearGradient(colors: [theme.bodyDark, theme.bodyLight],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                Circle().fill(theme.lid.opacity(0.8)).padding(3)
                Circle().fill(theme.bodyLight).frame(width: 7, height: 7)
            }
            .frame(width: 50, height: 50)
            Capsule().fill(theme.lcd).frame(width: 34, height: 8)
            HStack(spacing: 3) {
                Capsule().fill(theme.buttonLight).frame(width: 10, height: 6)
                Capsule().fill(theme.accent).frame(width: 12, height: 7)
                Capsule().fill(theme.buttonLight).frame(width: 10, height: 6)
            }
        }
        .padding(6)
        .frame(width: 66, height: Self.height)
        .background(theme.bodyGradient, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
        .accessibilityHidden(true)
    }
}
