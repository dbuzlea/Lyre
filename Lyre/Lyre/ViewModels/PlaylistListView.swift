//
//  PlaylistListView.swift
//  Lyre
//

import SwiftUI

// Scrollable list of playlists. Unlike Songs/Albums/Artists, playlists are not
// alphabetically sectioned because they don't have a natural letter grouping.
// The selected row auto-scrolls to center on each selection change. New Playlist… comes
// first (`newRow`), naming one with the keyboard; the playlists follow it.
struct PlaylistListView: View {
    /// New Playlist…, before the playlists, which start at `fixedRows`.
    static let newRow = 0
    static let fixedRows = 1

    let playlists: [AppPlaylist]
    @Binding var selection: Int
    let themeSettings: ThemeSettings
    /// Drives the "enable access in Settings" hint under the empty-library message.
    var isAuthorized: Bool = true

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

            row(String(localized: "playlist.new.action"), isSelected: selection == Self.newRow)
                .accessibilityIdentifier("playlist.new")
            if playlists.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Text(String(localized: "empty.playlists"))
                        .font(.system(size: 14))
                        .foregroundStyle(themeSettings.currentTheme.screenTextColor.opacity(0.5))
                    if !isAuthorized {
                        Text(String(localized: "empty.enableAccess"))
                            .font(.system(size: 11))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(themeSettings.currentTheme.screenTextColor.opacity(0.4))
                            .padding(.horizontal, 24)
                    }
                    Spacer()
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(playlists.enumerated()), id: \.offset) { offset, playlist in
                                let index = offset + Self.fixedRows
                                row(playlist.name, isSelected: selection == index)
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

    private func row(_ title: String, isSelected: Bool) -> some View {
        Text(title)
            .font(.system(size: 12))
            .foregroundStyle(isSelected
                ? themeSettings.currentTheme.highlightTextColor
                : themeSettings.currentTheme.screenTextColor)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? themeSettings.currentTheme.highlightColor : Color.clear)
            .selectionBarRefraction(when: isSelected)
    }
}
