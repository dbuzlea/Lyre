//
//  LiquidSettingsView.swift
//  Lyre
//

import SwiftUI

// MARK: - Liquid Settings
//
// The Liquid player's settings, as plain as the player: its tutorial (LiquidTour),
// playback, sound, which player to use, and the version. No finishes to choose: the music colours it.

struct LiquidSettingsView: View {
    @ObservedObject var musicService: MusicService
    @Bindable var themeSettings: ThemeSettings
    let foldMonitor: FoldPostureMonitor
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "spool.settings.tutorial")) {
                    LiquidTourPager(ink: .primary)
                        .padding(.vertical, 8)
                }

                Section(String(localized: "spool.settings.playback")) {
                    Toggle(String(localized: "spool.settings.shuffle"), isOn: Binding(
                        get: { musicService.shuffleMode != .off },
                        set: { _ in Task { await musicService.toggleShuffleMode() } }
                    ))
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
