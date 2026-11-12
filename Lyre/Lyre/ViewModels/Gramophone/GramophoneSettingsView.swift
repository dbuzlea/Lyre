//
//  GramophoneSettingsView.swift
//  Lyre
//

import SwiftUI

// MARK: - Gramophone Settings
//
// The Gramophone's settings, opened from the booklet button at its top right. Laid out
// as the machine's instruction booklet: cream paper, serif type, numbered directions,
// and a drawing of each design in the chosen finish. Design and finish change the
// machine behind the sheet as they're picked. The first direction is the tutorial
// (GramophoneTour), as the Spool's owner's manual opens with its own.

struct GramophoneSettingsView: View {
    @ObservedObject var musicService: MusicService
    @Bindable var themeSettings: ThemeSettings
    let foldMonitor: FoldPostureMonitor
    let onDone: () -> Void
    @Environment(\.windowSafeArea) private var safeArea

    private var theme: GramophoneTheme { themeSettings.gramophoneFinish.theme }
    private var ink: Color { SpoolPalette.labelInk }

    /// Send Diagnostics Automatically (ProblemReporter): off until the listener turns it on.
    @AppStorage(ProblemReporter.automaticKey) private var sendsDiagnosticsAutomatically = false
    /// Share Usage Statistics (UsageStats): off until the listener turns it on.
    @AppStorage(UsageStats.enabledKey) private var sharesUsageStatistics = false

    var body: some View {
        settingsPage
            .overlay {
                SideRailButtons { SideRailDone(identifier: "gramophone.settings.done", font: .system(size: 16, weight: .semibold, design: .serif), action: onDone) }
            }
    }

    private var settingsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header

                // LYRE-28: set up without access to the music library, it can be given here.
                AllowMusicAccessButton(musicService: musicService) {
                    HStack(spacing: 12) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 20, weight: .semibold))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(String(localized: "settings.allowMusicAccess"))
                                .lyreFont(size: 16, weight: .semibold, maxScale: 2)
                            Text(String(localized: "settings.allowMusicAccess.detail"))
                                .lyreFont(size: 12, maxScale: 2)
                                .lyreFaded(0.7)
                        }
                        .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .opacity(0.6)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).strokeBorder(lineWidth: 1.5).opacity(0.5))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(LyrePressStyle(isRow: true))

                section(1, String(localized: "spool.settings.tutorial")) {
                    GramophoneTourPager(theme: theme)
                        .frame(maxWidth: .infinity)
                }

                section(2, String(localized: "gramophone.settings.design")) {
                    HStack(spacing: 12) {
                        ForEach(GramophoneModel.allCases) { designCard($0) }
                    }
                }

                section(3, String(localized: "gramophone.settings.finish")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 16) {
                        ForEach(GramophoneFinish.allCases) { finishSwatch($0) }
                    }
                }

                section(4, String(localized: "spool.settings.sound")) {
                    VStack(alignment: .leading, spacing: 18) {
                        Toggle(isOn: $themeSettings.clickSoundEnabled) {
                            rowLabel(String(localized: "spool.settings.soundEffects"),
                                     detail: String(localized: "gramophone.settings.soundEffects.detail"))
                        }
                        .accessibilityIdentifier("gramophone.settings.sound")
                        Toggle(isOn: $themeSettings.gramophoneSurfaceNoise) {
                            rowLabel(String(localized: "gramophone.settings.surfaceNoise"),
                                     detail: String(localized: "gramophone.settings.surfaceNoise.detail"))
                        }
                        .disabled(!themeSettings.clickSoundEnabled)
                        .accessibilityIdentifier("gramophone.settings.surfaceNoise")
                    }
                }

                section(5, String(localized: "spool.settings.playback")) {
                    VStack(alignment: .leading, spacing: 18) {
                        Toggle(isOn: Binding(
                            get: { musicService.shuffleMode != .off },
                            set: { _ in Task { await musicService.toggleShuffleMode() } }
                        )) {
                            rowLabel(String(localized: "spool.settings.shuffle"))
                        }
                        Toggle(isOn: $themeSettings.cleanVersions) {
                            rowLabel(String(localized: "settings.cleanVersions"))
                        }
                        .accessibilityHint(String(localized: "settings.cleanVersions.detail"))
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
                            .accessibilityIdentifier("gramophone.settings.repeat")
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
                        }
                    }
                }

                section(6, String(localized: "spool.settings.player")) {
                    VStack(alignment: .leading, spacing: 14) {
                        playerButton(.classic, symbol: "circle.circle")
                        playerButton(.spool, symbol: "recordingtape")
                        playerButton(.disc, symbol: "opticaldiscdrive")
                        playerButton(.liquid, symbol: "drop")
                    }
                }

                // Send Diagnostics Automatically, Report a Problem and Share Diagnostics
                // (Diagnostics), then the version, as at the foot of every player's
                // settings.
                // Lyre's own reports of crashes and freezes, sent only if this is on
                // (ProblemReporter).
                Toggle(isOn: $sendsDiagnosticsAutomatically) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "settings.sendDiagnostics"))
                            .lyreFont(size: 15, weight: .semibold, maxScale: 2)
                        Text(String(localized: "settings.sendDiagnostics.detail"))
                            .lyreFont(size: 12, maxScale: 2)
                            .lyreFaded(0.7)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).strokeBorder(lineWidth: 1.5).opacity(0.5))
                .accessibilityIdentifier("settings.sendDiagnostics")
                Toggle(isOn: $sharesUsageStatistics) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "settings.shareUsage"))
                            .lyreFont(size: 15, weight: .semibold, maxScale: 2)
                        Text(String(localized: "settings.shareUsage.detail"))
                            .lyreFont(size: 12, maxScale: 2)
                            .lyreFaded(0.7)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).strokeBorder(lineWidth: 1.5).opacity(0.5))
                .accessibilityIdentifier("settings.shareUsage")
                GestureTipsButton()
                ReportProblemButton {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.bubble")
                            .font(.system(size: 18, weight: .semibold))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(String(localized: "settings.reportProblem"))
                                .lyreFont(size: 15, weight: .semibold, maxScale: 2)
                            Text(String(localized: "settings.reportProblem.detail"))
                                .lyreFont(size: 12, maxScale: 2)
                                .lyreFaded(0.7)
                        }
                        .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                            .opacity(0.6)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).strokeBorder(lineWidth: 1.5).opacity(0.5))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(LyrePressStyle(isRow: true))
                ShareDiagnosticsButton {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 18, weight: .semibold))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(String(localized: "settings.shareDiagnostics"))
                                .lyreFont(size: 15, weight: .semibold, maxScale: 2)
                            Text(String(localized: "settings.shareDiagnostics.detail"))
                                .lyreFont(size: 12, maxScale: 2)
                                .lyreFaded(0.7)
                        }
                        .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .opacity(0.6)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).strokeBorder(lineWidth: 1.5).opacity(0.5))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(LyrePressStyle(isRow: true))
                Text(String(localized: "about.version").replacingOccurrences(of: "%@", with: versionString))
                    .lyreFont(size: 11, maxScale: 2)
                    .lyreFaded(0.5)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("gramophone.settings.version")
            }
            .padding(24)
        }
        .foregroundStyle(ink)
        .tint(theme.metalDark)
        .background(theme.paper.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .accessibilityIdentifier("gramophone.settings.sheet")
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "gramophone.brand").uppercased())
                    .lyreFont(size: 30, weight: .heavy, design: .serif, maxScale: 2)
                    .tracking(4)
                    // One line, however large the text: the maker's name isn't broken.
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(String(localized: "gramophone.settings.booklet"))
                    .lyreFont(size: 12, weight: .semibold, design: .serif, maxScale: 2)
                    .italic()
                    .lyreFaded(0.65)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer()
            // Down the side column instead, on an iPhone Duo with its status bar there.
            if !SideRail.isOn(safeArea) {
                Button(String(localized: "spool.settings.done"), action: onDone)
                    .lyreFont(size: 16, weight: .semibold, design: .serif, maxScale: 2)
                    .accessibilityIdentifier("gramophone.settings.done")
            }
        }
        .overlay(alignment: .bottom) {
            // A double rule, as printed under a title.
            VStack(spacing: 2) {
                Rectangle().frame(height: 2)
                Rectangle().frame(height: 0.75)
            }
            .offset(y: 16)
        }
        .padding(.bottom, 8)
    }

    private func section<Content: View>(_ number: Int, _ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(Self.roman(number))
                    .lyreFont(size: 13, weight: .bold, design: .serif, maxScale: 2)
                    .frame(minWidth: 22, alignment: .leading)
                    .accessibilityHidden(true)
                Text(title.uppercased())
                    .lyreFont(size: 13, weight: .bold, design: .serif, maxScale: 2)
                    .tracking(1.5)
                    .accessibilityAddTraits(.isHeader)
            }
            content()
        }
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        guard let build = info?["CFBundleVersion"] as? String else { return version }
        return "\(version) (\(build))"
    }

    /// Directions numbered I, II, III, as the booklets were.
    private static func roman(_ number: Int) -> String {
        ["I.", "II.", "III.", "IV.", "V.", "VI.", "VII."][max(0, min(number - 1, 6))]
    }

    private func rowLabel(_ title: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).lyreFont(size: 16, weight: .medium, design: .serif, maxScale: 2)
            if let detail {
                Text(detail)
                    .lyreFont(size: 12, maxScale: 2)
                    .lyreFaded(0.65)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func designCard(_ model: GramophoneModel) -> some View {
        let isSelected = themeSettings.gramophoneModel == model
        return Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { themeSettings.gramophoneModel = model }
        } label: {
            VStack(spacing: 10) {
                GramophoneSketch(model: model, theme: theme)
                    .frame(height: 92)
                Text(model.displayName)
                    .lyreFont(size: 13, weight: .semibold, design: .serif, maxScale: 2)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(.white.opacity(isSelected ? 0.6 : 0.3), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(ink.opacity(isSelected ? 1 : 0.15), lineWidth: isSelected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(LyrePressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("gramophone.settings.design.\(model.rawValue)")
    }

    private func finishSwatch(_ finish: GramophoneFinish) -> some View {
        let isSelected = themeSettings.gramophoneFinish == finish
        let swatch = finish.theme
        return Button {
            withAnimation(.easeInOut(duration: 0.35)) { themeSettings.gramophoneFinish = finish }
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(swatch.woodGradient)
                    .overlay(Circle().strokeBorder(swatch.metalGradient, lineWidth: 5))
                    .overlay(Circle().fill(swatch.felt).frame(width: 12, height: 12))
                    .frame(width: 44, height: 44)
                    .padding(3)
                    .overlay(Circle().strokeBorder(ink.opacity(isSelected ? 1 : 0), lineWidth: 2))
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                Text(finish.displayName)
                    .lyreFont(size: 13, weight: isSelected ? .semibold : .regular, design: .serif, maxScale: 2)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(LyrePressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("gramophone.settings.finish.\(finish.rawValue)")
    }

    /// The player cycles repeat Off → All → One; step it round to the mode picked.
    private func setRepeat(_ mode: RepeatMode) {
        Task {
            for _ in RepeatMode.allCases where musicService.repeatMode != mode {
                await musicService.toggleRepeatMode()
            }
        }
    }

    private func playerButton(_ style: PlayerStyle, symbol: String) -> some View {
        Button {
            onDone()
            themeSettings.playerStyle = style
        } label: {
            HStack {
                rowLabel(String(format: String(localized: "gramophone.settings.switchTo"), style.displayName))
                Spacer(minLength: 8)
                Image(systemName: symbol).font(.system(size: 22))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(LyrePressStyle(isRow: true))
        .accessibilityIdentifier("gramophone.settings.player.\(style.rawValue)")
    }
}
