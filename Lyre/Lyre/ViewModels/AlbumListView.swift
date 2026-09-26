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
    /// Each row's section letter, precomputed by MusicService when the list changes.
    var sectionLetters: [String] = []


    @State private var showScrubber = false
    /// Restarted on every scroll step, so it must not be tracked state — see OneShotTimer.
    @State private var scrubberTimer = OneShotTimer()

    private var currentLetter: String {
        guard !albums.isEmpty, selection < albums.count else { return "A" }
        return firstLetter(albums[selection].title)
    }

    private func firstLetter(_ name: String) -> String {
        AppHelpers.firstLetter(of: name)
    }

    /// The letter a row files under. Uses the precomputed letters when they line up
    /// with the list, and works it out directly otherwise.
    private func sectionLetter(at index: Int) -> String {
        sectionLetters.count == albums.count ? sectionLetters[index] : firstLetter(albums[index].title)
    }

    private func showAlphabetScrubber() {
        // Only the first step of a scroll changes state; later steps just push the
        // fade-out back.
        if !showScrubber {
            withAnimation(.easeIn(duration: 0.15)) { showScrubber = true }
        }
        scrubberTimer.schedule(after: 1.5) {
            withAnimation(.easeOut(duration: 0.4)) { showScrubber = false }
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
                                // Indices, not `Array(albums.enumerated())`: that copied the whole list
                                // on every redraw, thousands of rows for a large library.
                                ForEach(albums.indices, id: \.self) { index in
                                    let album = albums[index]
                                    if index == 0 || sectionLetter(at: index) != sectionLetter(at: index - 1) {
                                        HStack(spacing: 4) {
                                            Text(sectionLetter(at: index))
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
        .onDisappear { scrubberTimer.cancel() }
    }
}
