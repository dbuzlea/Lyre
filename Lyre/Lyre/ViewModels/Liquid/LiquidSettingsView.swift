//
//  LiquidSettingsView.swift
//  Lyre
//

import SwiftUI

// MARK: - Liquid Settings
//
// The Liquid player's settings, as plain as the player: its tutorial (LiquidTour),
// playback, sound, whether Now Playing's cover ripples to the beat and whether songs'
// tempos are looked up for it (SongTempos), which player to use, and the version. No finishes to choose: the music colours it.

struct LiquidSettingsView: View {
    @ObservedObject var musicService: MusicService
    @Bindable var themeSettings: ThemeSettings
    let foldMonitor: FoldPostureMonitor
    let onDone: () -> Void

    /// Send Diagnostics Automatically (ProblemReporter): off until the listener turns it on.
    @AppStorage(ProblemReporter.automaticKey) private var sendsDiagnosticsAutomatically = false
    /// Share Usage Statistics (UsageStats): off until the listener turns it on.
    @AppStorage(UsageStats.enabledKey) private var sharesUsageStatistics = false

    var body: some View {
        NavigationStack {
            Form {
                // LYRE-28: set up without access to the music library, it can be given here.
                if MusicAccess.isNeeded || !musicService.isAuthorized {
                    Section {
                        AllowMusicAccessButton(musicService: musicService) {
                            Label(String(localized: "settings.allowMusicAccess"), systemImage: "music.note.list")
                        }
                    } footer: {
                        Text(String(localized: "settings.allowMusicAccess.detail"))
                    }
                }
                Section(String(localized: "spool.settings.tutorial")) {
                    LiquidTourPager(ink: .primary)
                        .padding(.vertical, 8)
                }

                Section(String(localized: "spool.settings.playback")) {
                    Toggle(String(localized: "spool.settings.shuffle"), isOn: Binding(
                        get: { musicService.shuffleMode != .off },
                        set: { _ in Task { await musicService.toggleShuffleMode() } }
                    ))
                    Toggle(String(localized: "settings.cleanVersions"), isOn: $themeSettings.cleanVersions)
                        .accessibilityHint(String(localized: "settings.cleanVersions.detail"))
                    Picker(String(localized: "spool.settings.repeat"), selection: Binding(
                        get: { musicService.repeatMode },
                        set: setRepeat
                    )) {
                        Text(String(localized: "spool.settings.repeat.off")).tag(RepeatMode.off)
                        Text(String(localized: "spool.settings.repeat.all")).tag(RepeatMode.all)
                        Text(String(localized: "spool.settings.repeat.one")).tag(RepeatMode.one)
                    }
                    Picker(String(localized: "spool.speed"), selection: Binding(
                        get: { musicService.podcastRate },
                        set: { musicService.setPodcastRate($0) }
                    )) {
                        ForEach(MusicService.podcastRates, id: \.self) { rate in
                            Text(SpoolPlayerView.speedText(rate)).tag(rate)
                        }
                    }
                }

                Section {
                    Toggle(String(localized: "spool.settings.soundEffects"), isOn: $themeSettings.clickSoundEnabled)
                        .accessibilityIdentifier("liquid.settings.sound")
                } header: {
                    Text(String(localized: "spool.settings.sound"))
                } footer: {
                    Text(String(localized: "liquid.settings.sound.detail"))
                }

                Section {
                    Toggle(String(localized: "liquid.settings.ripple"), isOn: $themeSettings.liquidRipple)
                        .accessibilityIdentifier("liquid.settings.ripple")
                    Toggle(String(localized: "liquid.settings.tempos"), isOn: $themeSettings.liquidTempoLookup)
                        .accessibilityIdentifier("liquid.settings.tempos")
                } header: {
                    Text(String(localized: "liquid.pool.nowPlaying"))
                } footer: {
                    Text(String(localized: "liquid.settings.ripple.detail") + " " + String(localized: "liquid.settings.tempos.detail"))
                }

                Section(String(localized: "spool.settings.player")) {
                    switchButton(.classic, symbol: "circle.circle")
                    switchButton(.spool, symbol: "recordingtape")
                    switchButton(.gramophone, symbol: "opticaldisc")
                    switchButton(.disc, symbol: "opticaldiscdrive")
                }

                #if DEBUG
                Section("Debug") {
                    Picker("Fold Posture", selection: Binding(
                        get: { foldMonitor.debugOverride },
                        set: { foldMonitor.debugOverride = $0 }
                    )) {
                        Text("Device").tag(FoldPosture?.none)
                        ForEach(FoldPosture.allCases) { posture in
                            Text(posture.debugName).tag(Optional(posture))
                        }
                    }
                }
                #endif

                // Lyre's logs and iOS's reports, to help find a problem (Diagnostics).
                Section {
                    // Lyre's own reports of crashes and freezes, sent only if this is on.
                    Toggle(String(localized: "settings.sendDiagnostics"), isOn: $sendsDiagnosticsAutomatically)
                        .accessibilityIdentifier("settings.sendDiagnostics")
                    // How Lyre's used, counted without names, only if this is on (UsageStats).
                    Toggle(String(localized: "settings.shareUsage"), isOn: $sharesUsageStatistics)
                        .accessibilityIdentifier("settings.shareUsage")
                    ReportProblemButton {
                        Label(String(localized: "settings.reportProblem"), systemImage: "exclamationmark.bubble")
                    }
                    ShareDiagnosticsButton {
                        Label(String(localized: "settings.shareDiagnostics"), systemImage: "doc.text.magnifyingglass")
                    }
                } footer: {
                    Text(String(localized: "settings.sendDiagnostics.detail") + " "
                         + String(localized: "settings.shareUsage.detail") + " "
                         + String(localized: "settings.reportProblem.detail"))
                }

                Section {
                    Text(String(localized: "about.version").replacingOccurrences(of: "%@", with: versionString))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle(PlayerStyle.liquid.displayName)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "spool.settings.done"), action: onDone)
                        .accessibilityIdentifier("liquid.settings.done")
                }
            }
        }
        .accessibilityIdentifier("liquid.settings.sheet")
    }

    private func switchButton(_ style: PlayerStyle, symbol: String) -> some View {
        Button {
            onDone()
            themeSettings.playerStyle = style
        } label: {
            Label(String(format: String(localized: "gramophone.settings.switchTo"), style.displayName),
                  systemImage: symbol)
        }
        .accessibilityIdentifier("liquid.settings.\(style.rawValue)")
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
