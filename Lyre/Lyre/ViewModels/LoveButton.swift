//
//  LoveButton.swift
//  Lyre
//

import SwiftUI

// MARK: - Love Button
//
// The ♥ for the song playing (Loves), drawn by each player in its own style, as the
// AirPlay button is: `label` is handed whether the song's loved. Only there for a song
// Apple Music knows, with access to it; a file of the listener's own, a podcast, or
// nothing playing shows nothing.

struct LoveButton<Label: View>: View {
    let track: AppTrack?
    let identifier: String
    @ViewBuilder let label: (_ isLoved: Bool) -> Label

    var body: some View {
        let loves = Loves.shared
        if loves.canLove(track) {
            let isLoved = loves.isLoved(track)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task { await loves.toggle(track) }
            } label: {
                label(isLoved)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isLoved ? String(localized: "love.loved") : String(localized: "love.label"))
            .accessibilityAddTraits(isLoved ? .isSelected : [])
            .accessibilityIdentifier(identifier)
            .task(id: track?.id) { await loves.load(track) }
        }
    }

    /// The heart: filled once loved.
    static func symbol(_ isLoved: Bool) -> String { isLoved ? "heart.fill" : "heart" }
}
