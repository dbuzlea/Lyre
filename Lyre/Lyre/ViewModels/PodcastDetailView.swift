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
struct PodcastDetailView: View {
    let show: PodcastShow
    @Binding var selection: Int
    let themeSettings: ThemeSettings

    private var episodes: [MPMediaItem] { show.episodes }

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
                if let artwork = show.artwork,
                   let image = artwork.image(at: CGSize(width: 50, height: 50)) {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: 50, height: 50)
                        .cornerRadius(4)
                } else {
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
                        ForEach(Array(episodes.enumerated()), id: \.offset) { index, episode in
                            HStack {
                                if selection == index {
                                    Rectangle()
                                        .fill(themeSettings.currentTheme.highlightColor)
                                        .overlay {
                                            HStack {
                                                VStack(alignment: .leading, spacing: 0) {
                                                    Text(episode.title ?? "Episode \(index + 1)")
                                                        .font(.system(size: 11, weight: .medium))
                                                        .foregroundStyle(themeSettings.currentTheme.highlightTextColor)
                                                        .lineLimit(1)
                                                    Text(formatDuration(episode.playbackDuration))
                                                        .font(.system(size: 9))
                                                        .foregroundStyle(themeSettings.currentTheme.highlightTextColor.opacity(0.7))
                                                }
                                                Spacer()
                                            }
                                            .padding(.leading, 8)
                                            .padding(.vertical, 2)
                                        }
                                        .selectionBarRefraction()
                                } else {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 0) {
                                            Text(episode.title ?? "Episode \(index + 1)")
                                                .font(.system(size: 11))
                                                .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                                                .lineLimit(1)
                                            Text(formatDuration(episode.playbackDuration))
                                                .font(.system(size: 9))
                                                .foregroundStyle(themeSettings.currentTheme.screenSecondaryTextColor)
                                        }
                                        Spacer()
                                    }
                                    .padding(.leading, 8)
                                    .padding(.vertical, 2)
                                }
                            }
                            .frame(height: 32)
                            .id(index)
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
                else if newValue >= episodes.count { selection = episodes.count - 1 }
            }
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
