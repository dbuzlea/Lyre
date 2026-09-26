//
//  PlayShuffleRows.swift
//  Lyre
//

import SwiftUI

// The Play and Shuffle rows at the top of the album, playlist and podcast track lists.
// They take cursor positions 0 and 1, so every track in those lists sits `count` rows
// further down than its index — ScrollWheelView subtracts it before looking a track up.
struct PlayShuffleRows: View {
    static let playOffset = 0
    static let shuffleOffset = 1
    static let count = 2

    let selection: Int
    let themeSettings: ThemeSettings

    var body: some View {
        row(offset: Self.playOffset, icon: "play.fill", label: String(localized: "detail.play"))
        row(offset: Self.shuffleOffset, icon: "shuffle", label: String(localized: "detail.shuffle"))
    }

    private func row(offset: Int, icon: String, label: String) -> some View {
        let isSelected = selection == offset

        return HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .frame(width: 20, alignment: .trailing)
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .lineLimit(1)
            Spacer()
        }
        .foregroundStyle(isSelected
            ? themeSettings.currentTheme.highlightTextColor
            : themeSettings.currentTheme.screenTextColor)
        .padding(.leading, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 32)
        .background(isSelected ? themeSettings.currentTheme.highlightColor : Color.clear)
        .selectionBarRefraction(when: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .id(offset)
    }
}
