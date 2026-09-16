//
//  AlbumListView.swift
//  Lyre
//

import SwiftUI

// Alphabetically sectioned album list. Mirrors SongListView's pattern: letter
// section headers, ScrollViewReader-based auto-scroll to the active selection,
// and a transient alphabet scrubber that appears briefly on selection change.
struct AlbumListView: View {
    let albums: [AppAlbum]
    @Binding var selection: Int
    let themeSettings: ThemeSettings

    @State private var showScrubber = false
    @State private var scrubberTimer: Timer? = nil

    private var currentLetter: String {
        guard !albums.isEmpty, selection < albums.count else { return "A" }
        return firstLetter(albums[selection].title)
    }

    private func firstLetter(_ name: String) -> String {
        AppHelpers.firstLetter(of: name)
    }

    private func showAlphabetScrubber() {
        withAnimation(.easeIn(duration: 0.15)) { showScrubber = true }
        scrubberTimer?.invalidate()
        scrubberTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.4)) { showScrubber = false }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Text("Albums")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Spacer()
            }

            Divider().background(themeSettings.currentTheme.dividerColor)

            if albums.isEmpty {
                VStack {
                    Spacer()
                    Text(String(localized: "empty.albums"))
                        .font(.system(size: 14))
                        .foregroundStyle(themeSettings.currentTheme.screenTextColor.opacity(0.5))
                    Spacer()
                }
            } else {
                ZStack(alignment: .trailing) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(albums.enumerated()), id: \.offset) { index, album in
                                    if index == 0 || firstLetter(album.title) != firstLetter(albums[index - 1].title) {
                                        HStack(spacing: 4) {
                                            Text(firstLetter(album.title))
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(themeSettings.currentTheme.highlightColor)
                                                .frame(width: 10, alignment: .center)
                                            Rectangle()
                                                .fill(themeSettings.currentTheme.dividerColor)
                                                .frame(height: 0.5)
                                        }
                                        .padding(.leading, 2).padding(.trailing, 14)
                                        .padding(.top, index == 0 ? 0 : 4).padding(.bottom, 2)
                                    }

                                    Text(album.title)
                                        .font(.system(size: 12))
                                        .foregroundStyle(selection == index
                                            ? themeSettings.currentTheme.highlightTextColor
                                            : themeSettings.currentTheme.screenTextColor)
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(selection == index
                                            ? themeSettings.currentTheme.highlightColor
                                            : Color.clear)
                                        .selectionBarRefraction(when: selection == index)
                                        .id("item-\(index)")
                                }
                            }
                        }
                        .onAppear { proxy.scrollTo("item-\(selection)", anchor: .center) }
                        .onChange(of: selection) { _, newValue in
                            withAnimation { proxy.scrollTo("item-\(newValue)", anchor: .center) }
                            showAlphabetScrubber()
                        }
                    }

                    if showScrubber {
                        AlphabetScrubberView(currentLetter: currentLetter, themeSettings: themeSettings)
                            .transition(.opacity)
                    }
                }
            }
        }
        .onDisappear { scrubberTimer?.invalidate() }
    }
}
