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
//   → Playback status badge → AirPlay device (when routed) → Shuffle and Repeat rows
//
// The title bar carries an AirPlay button (see AirPlayButton) for choosing where
// audio plays.
//
// Shuffle and Repeat rows, and while a podcast plays a Speed row, are selectable via the
// scroll wheel: `selection` (bound from the parent) tracks which row is focused (0 =
// Shuffle, 1 = Repeat, 2 = Speed). Pressing the center button cycles the highlighted
// row's setting; Speed steps through the same speeds the other players offer.
//
// The artwork is the largest element: it grows to fill whatever height the screen has
// left after everything below it, up to the screen's width, so it scales with the
// screen size (and the Nano Tall / Duo layouts) without pushing the Shuffle and Repeat
// rows off screen. Only when even the 100pt minimum doesn't fit does the screen scroll.
//
// The GeometryReader progress bar scales the highlight fill to a 0–1 fraction of
// the available width. The 8pt scrub indicator dot only appears while the wheel is
// actively seeking (`musicService.isScrubbing == true`) to avoid visual noise during
// normal playback.
struct NowPlayingView: View {
    @ObservedObject var musicService: MusicService
    let themeSettings: ThemeSettings
    @Binding var selection: Int
    @ObservedObject private var routeMonitor = AudioRouteMonitor.shared

    /// Height of everything under the artwork, measured so the artwork can take the rest.
    /// Nil until the first layout, when the artwork is drawn at its minimum.
    @State private var detailsHeight: CGFloat?

    /// The artwork never shrinks below this; on screens too short even for it, the
    /// details scroll instead.
    private static let minArtworkSide: CGFloat = 100
    /// Gap between the artwork and the details, matching the details' own spacing.
    private static let artworkSpacing: CGFloat = 8
    /// Library and podcast artwork is decoded once at this size and scaled to fit, so a
    /// resize doesn't decode (and cache) the cover again at every new size.
    private static let artworkDecodeSize: CGFloat = 400

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
                AirPlayButton(themeSettings: themeSettings)
            }

            Divider().background(themeSettings.currentTheme.dividerColor)

            if musicService.hasNowPlaying {
                let track = musicService.currentTrack
                let mediaItem = musicService.currentMediaItem
                let episode = musicService.currentEpisode
                let title: String = track?.title ?? mediaItem?.title ?? episode?.title ?? "Unknown"
                let subtitle: String = track?.artistName ?? mediaItem?.podcastTitle ?? mediaItem?.artist ?? episode?.showTitle ?? ""
                let isPodcast = track == nil

                GeometryReader { viewport in
                    VStack(spacing: Self.artworkSpacing) {
                        // Artwork
                        artworkView(track: track, mediaItem: mediaItem, episode: episode, isPodcast: isPodcast,
                                    side: artworkSide(in: viewport.size))
                            .accessibilityLabel(isPodcast ? "Podcast artwork" : "Album artwork")

                        VStack(spacing: 8) {
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

                            // Progress bar. A separate view observing only the clock, so the
                            // position ticking does not redraw the rest of the screen.
                            PlaybackProgressView(
                                clock: musicService.clock,
                                duration: musicService.duration,
                                isScrubbing: musicService.isScrubbing,
                                themeSettings: themeSettings
                            )
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

                            // Output device, only when audio has left the phone.
                            if let device = routeMonitor.airPlayDeviceName {
                                HStack(spacing: 3) {
                                    Image(systemName: "airplayaudio")
                                        .font(.system(size: 8))
                                        .accessibilityHidden(true)
                                    Text(device)
                                        .font(.system(size: 9))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(themeSettings.currentTheme.highlightColor)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(String(format: String(localized: "airPlay.playingOn"), device))
                            }

                            Divider().background(themeSettings.currentTheme.dividerColor).padding(.vertical, 4)

                            // Shuffle / Repeat, and a podcast's speed
                            VStack(alignment: .leading, spacing: 4) {
                                rowItem(icon: musicService.shuffleMode.icon, label: String(localized: "nowPlaying.shuffle"),
                                        value: musicService.shuffleMode.rawValue, index: 0)
                                rowItem(icon: musicService.repeatMode.icon, label: String(localized: "nowPlaying.repeat"),
                                        value: musicService.repeatMode.rawValue, index: 1)
                                if musicService.isPlayingPodcast {
                                    rowItem(icon: "gauge.with.dots.needle.67percent", label: String(localized: "nowPlaying.speed"),
                                            value: SpoolPlayerView.speedText(musicService.podcastRate), index: 2)
                                }
                            }
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { detailsHeight = $0 }
                    }
                    // On the shorter screen sizes this content is taller than the screen.
                    // Scrolling it under the pinned title bar keeps the title bar (and its
                    // AirPlay button) on screen instead of pushing it off the top.
                    .modifier(ScrollsToSelection(selection: selection))
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
                Spacer()
            }
        }
    }

    /// The largest square that fits beside the details in `viewport`: as wide as the
    /// screen, as tall as the space the details leave, never under the minimum.
    private func artworkSide(in viewport: CGSize) -> CGFloat {
        guard let detailsHeight else { return Self.minArtworkSide }
        let fitting = min(viewport.width, viewport.height - detailsHeight - Self.artworkSpacing)
        return max(Self.minArtworkSide, fitting.rounded(.down))
    }

    @ViewBuilder
    private func artworkView(track: AppTrack?, mediaItem: MPMediaItem?, episode: PodcastEpisode?, isPodcast: Bool, side: CGFloat) -> some View {
        let radius = max(8, side * 0.04)
        if let episode {
            // Streamed: the artwork comes from the feed.
            LocalArtworkImage(cacheKey: "episode.\(episode.id)", size: Self.artworkDecodeSize, artwork: nil, remoteURL: episode.artworkURL) { image in
                image.resizable().scaledToFill().frame(width: side, height: side).clipShape(.rect(cornerRadius: radius))
            } placeholder: {
                artworkPlaceholder(isPodcast: true, side: side, radius: radius)
            }
        } else if let artwork = track?.musicKitSong?.artwork {
            ArtworkImage(artwork, width: side, height: side).clipShape(.rect(cornerRadius: radius))
        } else if let item = isPodcast ? mediaItem : (track?.mpItem ?? mediaItem) {
            LocalArtworkImage(cacheKey: "mp.\(item.persistentID)", size: Self.artworkDecodeSize, artwork: item.artwork) { image in
                image.resizable().scaledToFill().frame(width: side, height: side).clipShape(.rect(cornerRadius: radius))
            } placeholder: {
                artworkPlaceholder(isPodcast: isPodcast, side: side, radius: radius)
            }
        } else {
            artworkPlaceholder(isPodcast: isPodcast, side: side, radius: radius)
        }
    }

    private func artworkPlaceholder(isPodcast: Bool, side: CGFloat, radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(themeSettings.currentTheme.screenTextColor.opacity(0.1))
            .frame(width: side, height: side)
            .overlay {
                Image(systemName: isPodcast ? "mic.fill" : "music.note")
                    .font(.system(size: side * 0.35))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor.opacity(0.3))
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
        .id(index)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
        .accessibilityAddTraits(selection == index ? .isSelected : [])
    }
}

// MARK: - Scrolling

/// Wraps the Now Playing details in a scroll view that keeps the wheel-selected
/// Shuffle/Repeat row (tagged with `.id(index)`) in view. When everything fits, as on
/// Nano Tall, the content sits at the top and does not scroll.
private struct ScrollsToSelection: ViewModifier {
    let selection: Int

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                content.frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onAppear { proxy.scrollTo(selection) }
            .onChange(of: selection) { _, newValue in
                withAnimation(.easeInOut(duration: 0.15)) { proxy.scrollTo(newValue) }
            }
        }
    }
}

// MARK: - Progress

/// Progress bar and elapsed/remaining times. The only part of Now Playing that changes
/// every tick, so it is the only part that observes the playback clock.
private struct PlaybackProgressView: View {
    @ObservedObject var clock: PlaybackClock
    let duration: TimeInterval
    let isScrubbing: Bool
    let themeSettings: ThemeSettings

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return clock.time / duration
    }

    var body: some View {
        VStack(spacing: 2) {
            if isScrubbing {
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
                    if isScrubbing {
                        Circle()
                            .fill(themeSettings.currentTheme.highlightColor)
                            .frame(width: 8, height: 8)
                            .offset(x: max(0, geo.size.width * progress - 4))
                    }
                }
            }
            .frame(height: 8)
            .accessibilityLabel("Playback progress")
            .accessibilityValue("\(AppHelpers.formatTime(clock.time)) of \(AppHelpers.formatTime(duration))")
            HStack {
                Text(AppHelpers.formatTime(clock.time))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(isScrubbing
                        ? themeSettings.currentTheme.highlightColor
                        : themeSettings.currentTheme.screenTextColor)
                    .accessibilityHidden(true)
                Spacer()
                Text("-\(AppHelpers.formatTime(duration - clock.time))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                    .accessibilityHidden(true)
            }
        }
    }
}
