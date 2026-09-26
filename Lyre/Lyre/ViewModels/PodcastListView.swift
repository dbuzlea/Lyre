//
//  PodcastListView.swift
//  Lyre
//
//  Created by Daniel Buzlea on 5/17/26.
//

import SwiftUI
import MediaPlayer

// Scrollable list of podcast shows sourced from the device's local media library
// (MPMediaLibrary via MusicService.refreshPodcasts). Each row shows a 28pt artwork
// thumbnail beside the show title and episode count. Artwork is drawn from
// MPMediaItem metadata rather than MusicKit because podcasts are handled entirely
// through the MediaPlayer framework.
struct PodcastListView: View {
    let podcastShows: [PodcastShow]
    @Binding var selection: Int
    let themeSettings: ThemeSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Text("Podcasts")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Spacer()
            }

            Divider()
                .background(themeSettings.currentTheme.dividerColor)

            if podcastShows.isEmpty {
                VStack {
                    Spacer()
                    Text(String(localized: "empty.podcasts"))
                        .font(.system(size: 12))
                        .foregroundStyle(themeSettings.currentTheme.screenTextColor.opacity(0.5))
                    Spacer()
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(podcastShows.enumerated()), id: \.offset) { index, show in
                                HStack(spacing: 8) {
                                    LocalArtworkImage(cacheKey: "podcast.\(show.title)", size: 28, artwork: show.artwork) { image in
                                        image
                                            .resizable()
                                            .frame(width: 28, height: 28)
                                            .cornerRadius(4)
                                    } placeholder: {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(themeSettings.currentTheme.highlightColor.opacity(0.3))
                                            .frame(width: 28, height: 28)
                                            .overlay {
                                                Image(systemName: "mic.fill")
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(themeSettings.currentTheme.highlightTextColor)
                                            }
                                    }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(show.title)
                                            .font(.system(size: 12))
                                            .foregroundStyle(selection == index ? themeSettings.currentTheme.highlightTextColor : themeSettings.currentTheme.screenTextColor)
                                            .lineLimit(1)
                                        Text("\(show.episodes.count) episode\(show.episodes.count == 1 ? "" : "s")")
                                            .font(.system(size: 9))
                                            .foregroundStyle(selection == index ? themeSettings.currentTheme.highlightTextColor.opacity(0.7) : themeSettings.currentTheme.screenSecondaryTextColor)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(selection == index ? themeSettings.currentTheme.highlightColor : Color.clear)
                                .selectionBarRefraction(when: selection == index)
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
        }
    }
}
