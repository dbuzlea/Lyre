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
                    .font(.system(size: 6, weight: letter == currentLetter ? .heavy : .regular))
                    .foregroundStyle(
                        letter == currentLetter
                            ? themeSettings.currentTheme.highlightColor
                            : themeSettings.currentTheme.screenTextColor.opacity(0.4)
                    )
                    .frame(width: 10)
                    .background(
                        Capsule()
                            .fill(letter == currentLetter
                                  ? themeSettings.currentTheme.highlightColor.opacity(0.15)
                                  : Color.clear)
                    )
            }
            Spacer(minLength: 0)
        }
        .frame(width: 12)
        .padding(.vertical, 2)
    }
}
