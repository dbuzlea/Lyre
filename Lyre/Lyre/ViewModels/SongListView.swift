//
//  SongListView.swift
//  Lyre
//

import SwiftUI

// Scrollable, alphabetically sectioned song list. Section headers (letter + hairline
// divider) appear wherever the first letter of consecutive song titles changes.
// The selected row auto-scrolls to center on each selection change driven by the
// scroll wheel.
//
// The alphabet scrubber overlay (AlphabetScrubberView) fades in for 1.5 seconds
// whenever the selection moves, showing which letter section is currently visible.
// A Timer is used — not a Combine publisher — to keep the auto-dismiss simple.
struct SongListView: View {
    let songs: [AppTrack]
    @Binding var selection: Int
    @ObservedObject var musicService: MusicService
    let themeSettings: ThemeSettings
    var title: String = "Songs"
    /// Each row's section letter, precomputed by MusicService when the list changes.
    var sectionLetters: [String] = []


    @State private var showScrubber = false
    /// Restarted on every scroll step, so it must not be tracked state — see OneShotTimer.
    @State private var scrubberTimer = OneShotTimer()

    private var currentLetter: String {
        guard !songs.isEmpty, selection < songs.count else { return "A" }
        return firstLetter(songs[selection].title)
    }

    private func firstLetter(_ name: String) -> String {
        AppHelpers.firstLetter(of: name)
    }

    /// The letter a row files under. Uses the precomputed letters when they line up
    /// with the list, and works it out directly otherwise.
    private func sectionLetter(at index: Int) -> String {
        sectionLetters.count == songs.count ? sectionLetters[index] : firstLetter(songs[index].title)
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
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Spacer()
                Text("\(songs.count) songs")
                    .font(.system(size: 10))
                    .foregroundStyle(themeSettings.currentTheme.screenSecondaryTextColor)
            }

            Divider().background(themeSettings.currentTheme.dividerColor)

            if songs.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Text(String(localized: "empty.songs"))
                        .font(.system(size: 14))
                        .foregroundStyle(themeSettings.currentTheme.screenTextColor.opacity(0.5))
                    if !musicService.isAuthorized {
                        Text(String(localized: "empty.enableAccess"))
                            .font(.system(size: 11))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(themeSettings.currentTheme.screenTextColor.opacity(0.4))
                            .padding(.horizontal, 24)
                    }
                    Spacer()
                }
            } else {
                ZStack(alignment: .trailing) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                // Indices, not `Array(songs.enumerated())`: that copied the whole list
                                // on every redraw, thousands of rows for a large library.
                                ForEach(songs.indices, id: \.self) { index in
                                    let song = songs[index]
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

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(song.title)
                                            .font(.system(size: 12))
                                            .foregroundStyle(selection == index
                                                ? themeSettings.currentTheme.highlightTextColor
                                                : themeSettings.currentTheme.screenTextColor)
                                            .lineLimit(1)
                                        Text(song.artistName)
                                            .font(.system(size: 10))
                                            .foregroundStyle(selection == index
                                                ? themeSettings.currentTheme.highlightTextColor.opacity(0.8)
                                                : themeSettings.currentTheme.screenSecondaryTextColor)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 8).padding(.vertical, 3)
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
