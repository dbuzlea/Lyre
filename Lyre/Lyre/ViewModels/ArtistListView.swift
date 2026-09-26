//
//  ArtistListView.swift
//  Lyre
//

import SwiftUI

// Alphabetically sectioned artist list. Same structure as AlbumListView.
// Names that start with a non-letter character (numbers, symbols) are bucketed
// under the "#" section header.
struct ArtistListView: View {
    let artists: [AppArtist]
    @Binding var selection: Int
    let themeSettings: ThemeSettings
    /// Each row's section letter, precomputed by MusicService when the list changes.
    var sectionLetters: [String] = []


    @State private var showScrubber = false
    /// Restarted on every scroll step, so it must not be tracked state — see OneShotTimer.
    @State private var scrubberTimer = OneShotTimer()

    private var currentLetter: String {
        guard !artists.isEmpty, selection < artists.count else { return "A" }
        return firstLetter(artists[selection].name)
    }

    private func firstLetter(_ name: String) -> String {
        let first = String(name.prefix(1)).uppercased()
        return first.first?.isLetter == true ? first : "#"
    }

    /// The letter a row files under. Uses the precomputed letters when they line up
    /// with the list, and works it out directly otherwise.
    private func sectionLetter(at index: Int) -> String {
        sectionLetters.count == artists.count ? sectionLetters[index] : firstLetter(artists[index].name)
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
                Text("Artists")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Spacer()
                Text("\(artists.count) artist\(artists.count == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundStyle(themeSettings.currentTheme.screenSecondaryTextColor)
            }

            Divider().background(themeSettings.currentTheme.dividerColor)

            if artists.isEmpty {
                VStack {
                    Spacer()
                    Text(String(localized: "empty.artists"))
                        .font(.system(size: 14))
                        .foregroundStyle(themeSettings.currentTheme.screenTextColor.opacity(0.5))
                    Spacer()
                }
            } else {
                ZStack(alignment: .trailing) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                // Indices, not `Array(artists.enumerated())`: that copied the whole list
                                // on every redraw, thousands of rows for a large library.
                                ForEach(artists.indices, id: \.self) { index in
                                    let artist = artists[index]
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

                                    Text(artist.name)
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
