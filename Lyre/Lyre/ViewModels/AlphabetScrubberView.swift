//
//  AlphabetScrubberView.swift
//  Lyre
//
//  Created by Daniel Buzlea on 5/14/26.
//

import SwiftUI

struct AlphabetScrubberView: View {
    let currentLetter: String
    let themeSettings: ThemeSettings

    private let alphabet = ["#", "A", "B", "C", "D", "E", "F", "G", "H", "I",
                            "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S",
                            "T", "U", "V", "W", "X", "Y", "Z"]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(alphabet, id: \.self) { letter in
                Spacer(minLength: 0)
                Text(letter)
                    .font(.system(size: 6))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor.opacity(0.4))
                    // Hide the small glyph for the active letter; the badge below replaces it.
                    .opacity(letter == currentLetter ? 0 : 1)
                    .frame(width: 10)
                    .overlay {
                        // Enlarged badge drawn as an overlay so it doesn't push
                        // neighbouring letters around as the section changes.
                        if letter == currentLetter {
                            Text(letter)
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(themeSettings.currentTheme.highlightTextColor)
                                .frame(width: 17, height: 17)
                                .background(
                                    Circle()
                                        .fill(themeSettings.currentTheme.highlightColor)
                                )
                                .fixedSize()
                        }
                    }
                    .zIndex(letter == currentLetter ? 1 : 0)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 12)
        .padding(.vertical, 2)
    }
}
