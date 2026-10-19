//
//  PlayerSwitchStage.swift
//  Lyre
//

import SwiftUI

// MARK: - Player Switch
//
// Changing the player style (from any player's settings, or the wheel's menu) is a small
// show, in three parts, so it's plain the music never stopped:
//
//   1. The old player bows out: it shrinks back, its corners round, and it sinks away
//      into the dark, with its own sound (the Spool's eject, the Gramophone's needle
//      lifting, the Disc's lid popping).
//   2. The song hands over: what's playing lifts out of the old player as its cover —
//      off the cassette, the record, the disc, the screen — and flies to its place in the
//      new one, taking that place's shape (a record's or a disc's round, the Liquid
//      player's whole screen).
//   3. The new player makes its entrance, each its own way: the Classic's backlight
//      fades up; the Spool slides up into place as its door clunks shut; the Gramophone
//      swings level as the needle drops; the Disc opens out from its deck as the lid
//      snaps shut and it spins up; Liquid floods out from the cover.
//
// With nothing playing there's no song to hand over, so the old player bows out and the
// new one comes in. Under Reduce Motion the two simply cross-fade.

struct PlayerSwitchStage<Content: View>: View {
    /// The player chosen.
    let style: PlayerStyle
    @ObservedObject var musicService: MusicService
    @ViewBuilder let content: (PlayerStyle) -> Content

    /// The player on screen, which lags `style` while the switch plays out.
    @State private var shown: PlayerStyle?
    /// How far the old player has bowed out: 0 in place, 1 gone.
    @State private var bowOut: CGFloat = 0
    /// How far the new player has come in: 0 not yet, 1 in place.
    @State private var entrance: CGFloat = 1
    @State private var card: Card?
    @State private var run: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Card {
        let track: AppTrack
        var frame: CGRect
        var corner: CGFloat
        var opacity: Double = 0
        var lift: CGFloat = 1
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let current = shown ?? style
            ZStack {
                Color.black

                content(current)
                    // Bowing out.
                    .scaleEffect(1 - 0.14 * bowOut)
                    .offset(y: bowOut * size.height * 0.12)
                    .clipShape(RoundedRectangle(cornerRadius: bowOut > 0 ? 44 * bowOut : 0, style: .continuous))
                    .brightness(-0.25 * bowOut)
                    .opacity(1 - Double(bowOut))
                    // Coming in.
                    .modifier(Entrance(style: current, progress: entrance, size: size))
                    .allowsHitTesting(bowOut == 0 && entrance == 1)

                if let card {
                    LiquidCover(source: .track(card.track))
                        .frame(width: card.frame.width, height: card.frame.height)
                        .clipShape(RoundedRectangle(cornerRadius: card.corner, style: .continuous))
                        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
                        .scaleEffect(card.lift)
                        .position(x: card.frame.midX, y: card.frame.midY)
                        .opacity(card.opacity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            // Held from the start, so a change of style can't show the new player before
            // the old one has bowed out.
            .onAppear { if shown == nil { shown = style } }
            .onChange(of: style) { old, new in
                play(from: shown ?? old, to: new, size: size)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: The Show

    private func play(from old: PlayerStyle, to new: PlayerStyle, size: CGSize) {
        run?.cancel()
        guard old != new else { return }
        guard !reduceMotion else {
            withAnimation(.easeInOut(duration: 0.3)) { shown = new }
            return
        }
        let track = musicService.nowPlayingTrack
        run = Task { @MainActor in
            // 1. The song lifts out of the old player as the player bows out.
            if let track {
                let from = Self.place(for: old, in: size)
                card = Card(track: track, frame: from.frame, corner: from.corner)
                withAnimation(.easeOut(duration: 0.25)) {
                    card?.opacity = 1
                    card?.lift = 1.08
                }
            }
            Self.exitSound(for: old)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.easeIn(duration: 0.4)) { bowOut = 1 }
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return settle(on: new) }

            // The new player, out of sight until its entrance.
            var swap = Transaction()
            swap.disablesAnimations = true
            withTransaction(swap) {
                shown = new
                entrance = 0
                bowOut = 0
            }

            // 2. The song flies to its place in the new player.
            if track != nil {
                let to = Self.place(for: new, in: size)
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                    card?.frame = to.frame
                    card?.corner = to.corner
                    card?.lift = 1
                }
                try? await Task.sleep(for: .milliseconds(460))
                guard !Task.isCancelled else { return settle(on: new) }
            }

            // 3. The new player's entrance.
            Self.entranceSound(for: new)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.easeOut(duration: 0.6)) { entrance = 1 }
            withAnimation(.easeIn(duration: 0.3).delay(0.3)) { card?.opacity = 0 }
            try? await Task.sleep(for: .milliseconds(650))
            settle(on: new)
        }
    }

    /// However the show ended, the new player in place and nothing left over.
    private func settle(on style: PlayerStyle) {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            shown = style
            bowOut = 0
            entrance = 1
            card = nil
        }
    }

    /// Where a player keeps the song it's playing, roughly, on a screen of `size`: the
    /// Classic's screen, the cassette in the Spool's door, the record on the Gramophone's
    /// turntable, the disc in the Disc's deck, the whole of Liquid's Now Playing.
    private static func place(for style: PlayerStyle, in size: CGSize) -> (frame: CGRect, corner: CGFloat) {
        let w = size.width, h = size.height
        func square(_ side: CGFloat, x: CGFloat, y: CGFloat) -> CGRect {
            CGRect(x: x - side / 2, y: y - side / 2, width: side, height: side)
        }
        switch style {
        case .classic:
            return (square(w * 0.36, x: w * 0.5, y: h * 0.22), 8)
        case .spool:
            // The original stands its tape in a door on the left; the slim lays it flat
            // in the middle.
            if UserDefaults.standard.string(forKey: "LyreSpoolModel") == SpoolModel.slim.rawValue {
                return (square(w * 0.4, x: w * 0.5, y: h * 0.55), 6)
            }
            return (square(w * 0.34, x: w * 0.38, y: h * 0.5), 6)
        case .gramophone:
            let side = w * 0.34
            return (square(side, x: w * 0.5, y: h * 0.5), side / 2)
        case .disc:
            let side = min(w - 56, h * 0.44) * 0.86
            return (square(side, x: w * 0.5, y: h * 0.37), side / 2)
        case .liquid:
            return (CGRect(origin: .zero, size: size), 0)
        }
    }

    private static func exitSound(for style: PlayerStyle) {
        switch style {
        case .spool:      SpoolSound.cassetteEject.play()
        case .gramophone: GramophoneSound.needleLift.play()
        case .disc:       DiscSound.lidOpen.play()
        case .classic, .liquid: break
        }
    }

    private static func entranceSound(for style: PlayerStyle) {
        switch style {
        case .spool:      SpoolSound.doorClose.play()
        case .gramophone: GramophoneSound.needleDrop.play()
        case .disc:
            DiscSound.lidClose.play()
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                DiscSound.spinUp.play()
            }
        case .classic, .liquid: break
        }
    }
}

/// Each player's own way in, as `progress` goes from 0 (not yet) to 1 (in place).
private struct Entrance: ViewModifier, Animatable {
    let style: PlayerStyle
    var progress: CGFloat
    let size: CGSize

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let p = progress
        let reach = (size.width * size.width + size.height * size.height).squareRoot() * 2.2
        // Where a round reveal opens from: the Disc's deck, or the middle for Liquid.
        let revealCentre = style == .disc
            ? CGPoint(x: size.width / 2, y: size.height * 0.37)
            : CGPoint(x: size.width / 2, y: size.height / 2)
        let reveals = style == .disc || style == .liquid
        content
            // The Spool slides up into place.
            .offset(y: style == .spool ? (1 - p) * size.height * 0.3 : 0)
            // The Gramophone swings level.
            .rotationEffect(.degrees(style == .gramophone ? -9 * Double(1 - p) : 0), anchor: .bottom)
            .scaleEffect(style == .gramophone ? 0.9 + 0.1 * p : 1)
            .opacity(style == .spool || style == .gramophone ? Double(min(1, p * 1.6)) : 1)
            // The Disc and Liquid open out in a circle.
            .mask {
                if reveals {
                    Circle()
                        .frame(width: reach, height: reach)
                        .scaleEffect(max(0.001, p))
                        .position(revealCentre)
                } else {
                    Rectangle()
                }
            }
            // The Classic's backlight fades up.
            .overlay {
                if style == .classic {
                    Color.black.opacity(Double(1 - p)).allowsHitTesting(false)
                }
            }
    }
}
