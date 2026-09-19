//
//  NowPlayingView.swift
//  Lyre
//

import SwiftUI
import MusicKit
import MediaPlayer

// MARK: - Now Playing Screen
//
// Displays the currently active track or podcast episode with album art, metadata,
// a progress bar, playback status, and interactive Shuffle/Repeat rows.
//
// Layout (top → bottom):
//   Title bar → Album/podcast artwork → Track title & artist
//   → Progress bar (scrub dot when wheel is scrolling) → Elapsed/remaining times
//   → Playback status badge → Shuffle and Repeat rows
//
// Shuffle and Repeat rows are selectable via the scroll wheel: `selection` (bound
// from the parent) tracks which row is focused (0 = Shuffle, 1 = Repeat). Pressing
// the center button cycles the highlighted row's mode.
//
// The GeometryReader progress bar scales the highlight fill to a 0–1 fraction of
// the available width. The 8pt scrub indicator dot only appears while the wheel is
// actively seeking (`musicService.isScrubbing == true`) to avoid visual noise during
// normal playback.
struct NowPlayingView: View {
    @ObservedObject var musicService: MusicService
    let themeSettings: ThemeSettings
    @Binding var selection: Int

    private var progress: Double {
        guard musicService.duration > 0 else { return 0 }
        return musicService.currentTime / musicService.duration
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Text(String(localized: "nowPlaying.title"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Spacer()
            }

            Divider().background(themeSettings.currentTheme.dividerColor)

            if musicService.currentTrack != nil || musicService.currentMediaItem != nil {
                let track = musicService.currentTrack
                let mediaItem = musicService.currentMediaItem
                let title: String = track?.title ?? mediaItem?.title ?? "Unknown"
                let subtitle: String = track?.artistName ?? mediaItem?.podcastTitle ?? mediaItem?.artist ?? ""
                let isPodcast = track == nil

                VStack(spacing: 8) {
                    // Artwork
                    artworkView(track: track, mediaItem: mediaItem, isPodcast: isPodcast)
                        .accessibilityLabel(isPodcast ? "Podcast artwork" : "Album artwork")

                    VStack(spacing: 2) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                            .lineLimit(2).multilineTextAlignment(.center)
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(themeSettings.currentTheme.screenSecondaryTextColor)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(title), by \(subtitle)")

                    // Progress bar
                    VStack(spacing: 2) {
                        if musicService.isScrubbing {
                            Text(String(localized: "nowPlaying.scrubbing"))
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(themeSettings.currentTheme.highlightColor)
                                .accessibilityHidden(true)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(themeSettings.currentTheme.screenTextColor.opacity(0.2))
                                    .frame(height: 4)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(themeSettings.currentTheme.highlightColor)
                                    .frame(width: max(0, geo.size.width * progress), height: 4)
                                if musicService.isScrubbing {
                                    Circle()
                                        .fill(themeSettings.currentTheme.highlightColor)
                                        .frame(width: 8, height: 8)
                                        .offset(x: max(0, geo.size.width * progress - 4))
                                }
                            }
                        }
                        .frame(height: 8)
                        .accessibilityLabel("Playback progress")
                        .accessibilityValue("\(formatTime(musicService.currentTime)) of \(formatTime(musicService.duration))")
                        HStack {
                            Text(formatTime(musicService.currentTime))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(musicService.isScrubbing
                                    ? themeSettings.currentTheme.highlightColor
                                    : themeSettings.currentTheme.screenTextColor)
                                .accessibilityHidden(true)
                            Spacer()
                            Text("-\(formatTime(musicService.duration - musicService.currentTime))")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.horizontal, 4)

                    // Playback status
                    HStack {
                        Image(systemName: musicService.isPlaying ? "play.fill" : "pause.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                            .accessibilityHidden(true)
                        Text(musicService.isPlaying ? String(localized: "nowPlaying.playing") : String(localized: "nowPlaying.paused"))
                            .font(.system(size: 10))
                            .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                    }
                    .accessibilityLabel(musicService.isPlaying ? "Now playing" : "Paused")

                    Divider().background(themeSettings.currentTheme.dividerColor).padding(.vertical, 4)

                    // Shuffle / Repeat
                    VStack(alignment: .leading, spacing: 4) {
                        rowItem(icon: musicService.shuffleMode.icon, label: String(localized: "nowPlaying.shuffle"),
                                value: musicService.shuffleMode.rawValue, index: 0)
                        rowItem(icon: musicService.repeatMode.icon, label: String(localized: "nowPlaying.repeat"),
                                value: musicService.repeatMode.rawValue, index: 1)
                    }
                }
            } else {
                VStack {
                    Spacer()
                    Image(systemName: "music.note")
                        .font(.system(size: 50))
                        .foregroundStyle(themeSettings.currentTheme.screenTextColor.opacity(0.3))
                    Text(String(localized: "nowPlaying.nothingPlaying"))
                        .font(.system(size: 14))
                        .foregroundStyle(themeSettings.currentTheme.screenTextColor.opacity(0.5))
                    Spacer()
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func artworkView(track: AppTrack?, mediaItem: MPMediaItem?, isPodcast: Bool) -> some View {
        if let artwork = track?.musicKitSong?.artwork {
            ArtworkImage(artwork, width: 100).cornerRadius(8)
        } else if let artwork = (isPodcast ? mediaItem?.artwork : (track?.mpItem?.artwork ?? mediaItem?.artwork)),
                  let uiImage = artwork.image(at: CGSize(width: 100, height: 100)) {
            Image(uiImage: uiImage).resizable().frame(width: 100, height: 100).cornerRadius(8)
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(themeSettings.currentTheme.screenTextColor.opacity(0.1))
                .frame(width: 100, height: 100)
                .overlay {
                    Image(systemName: isPodcast ? "mic.fill" : "music.note")
                        .font(.system(size: 35))
                        .foregroundStyle(themeSettings.currentTheme.screenTextColor.opacity(0.3))
                }
        }
    }

    @ViewBuilder
    private func rowItem(icon: String, label: String, value: String, index: Int) -> some View {
        HStack {
            if selection == index {
                Rectangle()
                    .fill(themeSettings.currentTheme.highlightColor)
                    .overlay {
                        HStack {
                            Image(systemName: icon).font(.system(size: 10))
                                .foregroundStyle(themeSettings.currentTheme.highlightTextColor)
                            Text(label).font(.system(size: 11, weight: .medium))
                                .foregroundStyle(themeSettings.currentTheme.highlightTextColor)
                            Spacer()
                            Text(value).font(.system(size: 10))
                                .foregroundStyle(themeSettings.currentTheme.highlightTextColor.opacity(0.8))
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                    }
                    .selectionBarRefraction()
            } else {
                HStack {
                    Image(systemName: icon).font(.system(size: 10))
                        .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                    Text(label).font(.system(size: 11))
                        .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                    Spacer()
                    Text(value).font(.system(size: 10))
                        .foregroundStyle(themeSettings.currentTheme.screenSecondaryTextColor)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
            }
        }
        .frame(height: 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
        .accessibilityAddTraits(selection == index ? .isSelected : [])
    }

    private func formatTime(_ time: TimeInterval) -> String {
        AppHelpers.formatTime(time)
    }
}
