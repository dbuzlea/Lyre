//
//  LiquidSongCarry.swift
//  Lyre
//

import SwiftUI

// MARK: - A Song Lifted Out of a List
//
// An iPhone Duo open: a song in one of Liquid's lists (the songs, the recent lists, an
// album's page) rested on a moment lifts (GestureIntent), as a bubble does in the field.
// Carried on, it's a little bubble of its own, its title beside it: across the fold into
// Now Playing, it plays as tapping it would; onto Up Next's bubble, which comes up at the
// foot of the page, it joins Up Next after the songs queued by hand; let go anywhere else,
// it goes back. Tapping still plays it, swiping still queues it, and holding on still
// opens its menu.
//
// The row says it's lifted and where the finger goes; the player (LiquidPlayerView) draws
// it and decides where it's dropped.

@Observable
@MainActor
final class LiquidSongCarry {
    struct Carried {
        let track: AppTrack
        /// Plays it as tapping its row does, from its place in its list.
        let play: () -> Void
        /// Whether it can go in Up Next (a show's episode can't).
        let canQueue: Bool
        var at: CGPoint
        var isOverUpNext = false
        /// Let go on Up Next or Now Playing, and going into it.
        var isGone = false
        var opacity: Double = 1
        var scale: CGFloat = 1
    }

    var carried: Carried?
    /// Where Up Next's bubble comes up while a song's carried, on screen.
    var upNextSpot: CGPoint?
    var upNextSize: CGFloat = 96
    /// Bumped as Up Next's bubble swallows a song, for its gulp.
    var gulps = 0

    /// The player's: a song lifted out of its row and carried; moved on; let go.
    @ObservationIgnored var onBegin: (AppTrack, Bool, @escaping () -> Void, CGPoint) -> Void = { _, _, _, _ in }
    @ObservationIgnored var onMove: (CGPoint) -> Void = { _ in }
    @ObservationIgnored var onEnd: (CGPoint) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Where a lifted song can be carried, on an iPhone Duo open; nil where there's nowhere.
    @Entry var liquidSongCarry: LiquidSongCarry?
}

/// A song's row that can be lifted and carried (LiquidSongCarry): rested on a moment it
/// rises a little; carried on, the player takes it. Its tap, swipes and menu are its own.
struct LiquidSongLift: ViewModifier {
    let track: AppTrack
    /// Whether it can go in Up Next (a show's episode can't).
    var canQueue = true
    /// What tapping the row plays.
    let play: () -> Void
    @Environment(\.liquidSongCarry) private var carry
    @State private var isLifted = false
    @State private var state = LiftState()

    final class LiftState { var isCarrying = false; var isHolding = false }

    func body(content: Content) -> some View {
        if let carry, #available(iOS 18.0, *) {
            content
                .scaleEffect(isLifted ? 1.03 : 1)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(isLifted ? 0.12 : 0)))
                // Lists scroll up and down, and swipe sideways: only a pause lifts a song.
                // (A UIKit recognizer, alongside the row's own touches until it's lifted.)
                .gesture(GestureIntentTouch(diameter: 0, pullDirection: nil, canCarry: true,
                                                        isFieldMoving: { false }) { phase, _, _, finger, _ in
                    touch(phase, finger: finger, carry: carry)
                })
        } else {
            content
        }
    }

    @available(iOS 18.0, *)
    private func touch(_ phase: GestureIntentTouch.Phase, finger: CGPoint, carry: LiquidSongCarry) {
        switch phase {
        case .lifted:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(LyreMotion.tap) { isLifted = true }
        case .moved:
            guard !state.isHolding else { return }
            if state.isCarrying {
                carry.onMove(finger)
            } else {
                state.isCarrying = true
                withAnimation(LyreMotion.tap) { isLifted = false }
                carry.onBegin(track, canQueue, play, finger)
            }
        case .held:
            // Rested on: its menu's (the row's own hold), not a carry.
            state.isHolding = true
            withAnimation(LyreMotion.tap) { isLifted = false }
        case .released:
            if state.isCarrying { carry.onEnd(finger) }
            state.isCarrying = false
            state.isHolding = false
            withAnimation(LyreMotion.light) { isLifted = false }
        case .tapped:
            // The row's own button plays it.
            withAnimation(LyreMotion.light) { isLifted = false }
        }
    }
}
