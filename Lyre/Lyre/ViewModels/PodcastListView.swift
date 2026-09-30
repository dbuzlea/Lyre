//
//  PodcastListView.swift
//  Lyre
//
//  Created by Daniel Buzlea on 5/17/26.
//

import SwiftUI
import MediaPlayer

// Scrollable list of podcast shows, used for two screens that never share an episode:
//
//   .all         The Podcasts screen: the episodes of subscriptions that stream, with
//                downloaded ones left out (MusicService.streamingPodcastShows). Two
//                fixed rows come first — row 0
//                "Search Podcasts" opens PodcastSearchView, row 1 "Downloaded" opens
//                the downloaded screen — so show `n` sits at row `n + 2`
//                (`PodcastListView.fixedRows`).
//   .downloaded  Everything on the iPhone — Lyre's downloads and the device's own
//                podcast library (MusicService.downloadedPodcastShows) — with no fixed
//                rows.
//
// Each show row has a 28pt artwork thumbnail beside the title and episode count, drawn
// from MPMediaItem artwork for on-device shows and downloaded from the feed's artwork
// URL for streamed ones.
struct PodcastListView: View {
    enum Mode { case all, downloaded }

    /// Rows above the shows on the Podcasts screen: Search Podcasts, then Downloaded.
    static let fixedRows = 2
    static let searchRow = 0
    static let downloadedRow = 1

    var mode: Mode = .all
    let podcastShows: [PodcastShow]
    /// Episodes available offline, shown under the Downloaded row.
    var downloadedEpisodeCount = 0
    @Binding var selection: Int
    let themeSettings: ThemeSettings

    private var theme: LyreTheme { themeSettings.currentTheme }
    private var showOffset: Int { mode == .all ? Self.fixedRows : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.screenTextColor)
                Text(mode == .all ? String(localized: "menu.podcasts") : String(localized: "podcasts.downloaded"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.screenTextColor)
                Spacer()
            }

            Divider()
                .background(theme.dividerColor)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if mode == .all {
                            fixedRow(index: Self.searchRow, symbol: "magnifyingglass",
                                     title: String(localized: "podcasts.search"))
                            fixedRow(index: Self.downloadedRow, symbol: "arrow.down.circle.fill",
                                     title: String(localized: "podcasts.downloaded"),
                                     subtitle: episodeCount(downloadedEpisodeCount))
                        }

                        if podcastShows.isEmpty {
                            Text(mode == .all ? String(localized: "empty.podcasts") : String(localized: "empty.downloads"))
                                .font(.system(size: 11))
                                .foregroundStyle(theme.screenTextColor.opacity(0.5))
                                .padding(.horizontal, 8)
                                .padding(.top, 8)
                        }

                        ForEach(Array(podcastShows.enumerated()), id: \.offset) { offset, show in
                            showRow(show, index: offset + showOffset)
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
    }

    private func episodeCount(_ count: Int) -> String {
        "\(count) episode\(count == 1 ? "" : "s")"
    }

    private func showRow(_ show: PodcastShow, index: Int) -> some View {
        HStack(spacing: 8) {
            LocalArtworkImage(cacheKey: show.artworkCacheKey, size: 28, artwork: show.artwork, remoteURL: show.artworkURL) { image in
                image
                    .resizable()
                    .frame(width: 28, height: 28)
                    .cornerRadius(4)
            } placeholder: {
                RoundedRectangle(cornerRadius: 4)
                    .fill(theme.highlightColor.opacity(0.3))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.highlightTextColor)
                    }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(show.title)
                    .font(.system(size: 12))
                    .foregroundStyle(selection == index ? theme.highlightTextColor : theme.screenTextColor)
                    .lineLimit(1)
                Text(episodeCount(show.episodes.count))
                    .font(.system(size: 9))
                    .foregroundStyle(selection == index ? theme.highlightTextColor.opacity(0.7) : theme.screenSecondaryTextColor)
            }
            Spacer()
            if show.isStreamed {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 9))
                    .foregroundStyle(selection == index ? theme.highlightTextColor.opacity(0.7) : theme.screenSecondaryTextColor)
                    .accessibilityLabel("Streamed")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selection == index ? theme.highlightColor : Color.clear)
        .selectionBarRefraction(when: selection == index)
        .id(index)
    }

    private func fixedRow(index: Int, symbol: String, title: String, subtitle: String? = nil) -> some View {
        let isSelected = selection == index
        return HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4)
                .fill(theme.highlightColor.opacity(isSelected ? 0 : 0.3))
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? theme.highlightTextColor : theme.screenTextColor)
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? theme.highlightTextColor : theme.screenTextColor)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(isSelected ? theme.highlightTextColor.opacity(0.7) : theme.screenSecondaryTextColor)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isSelected ? theme.highlightTextColor.opacity(0.7) : theme.screenSecondaryTextColor)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? theme.highlightColor : Color.clear)
        .selectionBarRefraction(when: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .id(index)
    }
}

// MARK: - Podcasts Screen

/// Feeds PodcastListView for either screen. Watches the downloads as well as the
/// library, so the Downloaded row's count and list follow a download as it finishes.
struct PodcastsScreen: View {
    var mode: PodcastListView.Mode
    @ObservedObject var musicService: MusicService
    @ObservedObject private var downloads = PodcastDownloads.shared
    @Binding var selection: Int
    let themeSettings: ThemeSettings

    var body: some View {
        let downloaded = musicService.downloadedPodcastShows()
        PodcastListView(
            mode: mode,
            podcastShows: mode == .all ? musicService.streamingPodcastShows() : downloaded,
            downloadedEpisodeCount: downloaded.reduce(0) { $0 + $1.episodes.count },
            selection: $selection,
            themeSettings: themeSettings
        )
    }
}
