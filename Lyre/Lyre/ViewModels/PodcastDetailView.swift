//
//  PodcastDetailView.swift
//  Lyre
//
//  Created by Daniel Buzlea on 5/17/26.
//

import SwiftUI
import MediaPlayer

// Episode browser for a single podcast show. Episodes are already loaded on the
// PodcastShow model (no async fetch needed), so the list renders immediately.
// Duration is formatted as h:mm:ss for episodes over an hour, otherwise m:ss.
// Selecting an episode triggers playback via MusicService.playPodcastEpisodes.
// Streamed episodes show whether they are downloaded (see PodcastDownloads).
struct PodcastDetailView: View {
    let show: PodcastShow
    @Binding var selection: Int
    let themeSettings: ThemeSettings
    @ObservedObject private var downloads = PodcastDownloads.shared

    private var episodes: [PodcastEpisode] { show.episodes }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Text(show.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                    .lineLimit(1)
                Spacer()
            }

            Divider()
                .background(themeSettings.currentTheme.dividerColor)

            // Podcast header
            HStack(spacing: 8) {
                LocalArtworkImage(cacheKey: show.artworkCacheKey, size: 50, artwork: show.artwork, remoteURL: show.artworkURL) { image in
                    image
                        .resizable()
                        .frame(width: 50, height: 50)
                        .cornerRadius(4)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(themeSettings.currentTheme.highlightColor.opacity(0.3))
                        .frame(width: 50, height: 50)
                        .overlay {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(themeSettings.currentTheme.highlightTextColor)
                        }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(show.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                        .lineLimit(2)
                    Text("\(episodes.count) episode\(episodes.count == 1 ? "" : "s")")
                        .font(.system(size: 9))
                        .foregroundStyle(themeSettings.currentTheme.screenSecondaryTextColor)
                }
                Spacer()
            }
            .padding(.bottom, 4)

            Divider()
                .background(themeSettings.currentTheme.dividerColor.opacity(0.5))

            // Episode list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        PlayShuffleRows(selection: selection, themeSettings: themeSettings)
                        ForEach(Array(episodes.enumerated()), id: \.offset) { index, episode in
                            HStack {
                                if selection == index + PlayShuffleRows.count {
                                    Rectangle()
                                        .fill(themeSettings.currentTheme.highlightColor)
                                        .overlay {
                                            HStack {
                                                VStack(alignment: .leading, spacing: 0) {
                                                    Text(episode.title)
                                                        .font(.system(size: 11, weight: .medium))
                                                        .foregroundStyle(themeSettings.currentTheme.highlightTextColor)
                                                        .lineLimit(1)
                                                    Text(formatDuration(episode.duration))
                                                        .font(.system(size: 9))
                                                        .foregroundStyle(themeSettings.currentTheme.highlightTextColor.opacity(0.7))
                                                }
                                                Spacer()
                                                downloadBadge(for: episode, color: themeSettings.currentTheme.highlightTextColor)
                                            }
                                            .padding(.leading, 8)
                                            .padding(.trailing, 8)
                                            .padding(.vertical, 2)
                                        }
                                        .selectionBarRefraction()
                                } else {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 0) {
                                            Text(episode.title)
                                                .font(.system(size: 11))
                                                .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                                                .lineLimit(1)
                                            Text(formatDuration(episode.duration))
                                                .font(.system(size: 9))
                                                .foregroundStyle(themeSettings.currentTheme.screenSecondaryTextColor)
                                        }
                                        Spacer()
                                        downloadBadge(for: episode, color: themeSettings.currentTheme.screenSecondaryTextColor)
                                    }
                                    .padding(.leading, 8)
                                    .padding(.trailing, 8)
                                    .padding(.vertical, 2)
                                }
                            }
                            .frame(height: 32)
                            .id(index + PlayShuffleRows.count)
                        }
                    }
                }
                .onAppear {
                    proxy.scrollTo(selection, anchor: .center)
                }
                .onChange(of: selection) { oldValue, newValue in
                    withAnimation {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
        .onChange(of: selection) { _, newValue in
            if !episodes.isEmpty {
                if newValue < 0 { selection = 0 }
                else if newValue >= episodes.count + PlayShuffleRows.count {
                    selection = episodes.count + PlayShuffleRows.count - 1
                }
            }
        }
    }

    /// Marks a streamed episode that is saved on the device, or how far its download is.
    @ViewBuilder
    private func downloadBadge(for episode: PodcastEpisode, color: Color) -> some View {
        switch downloads.state(for: episode.id) {
        case .downloaded:
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(color)
                .accessibilityLabel("Downloaded")
        case .downloading(let progress):
            Text("\(Int(progress * 100))%")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(color)
                .accessibilityLabel("Downloading")
        case nil:
            EmptyView()
        }
    }

        private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
