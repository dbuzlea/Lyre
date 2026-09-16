//
//  PlaylistListView.swift
//  Lyre
//

import SwiftUI

// Scrollable list of playlists. Unlike Songs/Albums/Artists, playlists are not
// alphabetically sectioned because they don't have a natural letter grouping.
// The selected row auto-scrolls to center on each selection change.
struct PlaylistListView: View {
    let playlists: [AppPlaylist]
    @Binding var selection: Int
    let themeSettings: ThemeSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Text("Playlists")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Spacer()
            }

            Divider().background(themeSettings.currentTheme.dividerColor)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(playlists.enumerated()), id: \.offset) { index, playlist in
                            Text(playlist.name)
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
                                .id(index)
                        }
                    }
                }
                .onAppear { proxy.scrollTo(selection, anchor: .center) }
                .onChange(of: selection) { _, newValue in
                    withAnimation { proxy.scrollTo(newValue, anchor: .center) }
                }
            }
        }
    }
}
