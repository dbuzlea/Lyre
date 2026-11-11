//
//  LiquidVisualizer.swift
//  Lyre
//

import SwiftUI
import MediaPlayer

// MARK: - Visualizer
//
// iPhone Duo, stood half open on a table and left alone: the whole inner screen gives
// itself to the song. The cover sits in the middle, its edge dissolving into the dark;
// rings of its colour spread from it on every beat (the song's tempo, from its beats-
// per-minute tag, or a slow breath with none tagged), and the cover's colours drift
// behind, out of focus. A touch anywhere brings the player back.
//
// Drawn 30 times a second, and only while the music plays; paused, it holds still.

struct LiquidVisualizer: View {
    @ObservedObject var musicService: MusicService
    let onWake: () -> Void
    /// Now Playing for a Duo stood half open (held as a book, as a tent): not woken from,
    /// but played from, its keys under the title; the cover sits higher to make room.
    var standing = false
    var onOpenQueue: () -> Void = {}

    @State private var color: Color = Color(red: 0.17, green: 0.29, blue: 0.48)
    @State private var anchor = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var track: AppTrack? { musicService.nowPlayingTrack }

    /// Its own tag, else what Deezer said (SongTempos).
    private var beatsPerMinute: Double? {
        guard let track else { return nil }
        if let bpm = track.mpItem?.beatsPerMinute, (40...220).contains(bpm) { return Double(bpm) }
        return SongTempos.shared.bpm(for: track)
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let side = standing ? min(size.width * 0.5, size.height * 0.36) : min(size.width, size.height) * 0.5
            // Standing, the cover and its rings sit above the title and keys.
            let lift = standing ? -size.height * 0.14 : 0
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !musicService.isPlaying || reduceMotion)) { context in
                let t = context.date.timeIntervalSince(anchor)
                let beats = beatsPerMinute.map { t * $0 / 60 } ?? t / 1.6
                let phase = beats.truncatingRemainder(dividingBy: 1)
                let swell = pow((1 + cos(2 * .pi * phase)) / 2, 1.6)
                ZStack {
                    Color.black
                    // The cover's colours, drifting behind, out of focus.
                    if let track {
                        LiquidCover(source: .track(track))
                            .frame(width: size.width * 1.4, height: size.height * 1.4)
                            .blur(radius: 60)
                            .opacity(0.45)
                            .rotationEffect(.degrees(t * 3))
                            .scaleEffect(1 + 0.04 * sin(t * 0.4))
                    }
                    // Rings on the beat, spreading and fading.
                    ForEach(0..<3, id: \.self) { ring in
                        let age = (phase + Double(ring)) / 3
                        Circle()
                            .strokeBorder(color.opacity(0.55 * (1 - age)), lineWidth: 3)
                            .frame(width: side * (1 + 1.6 * age), height: side * (1 + 1.6 * age))
                            .offset(y: lift)
                    }
                    // The cover, its edge dissolving, swelling a little on each beat.
                    if let track {
                        LiquidCover(source: .track(track))
                            .frame(width: side, height: side)
                            .mask(RadialGradient(colors: [.black, .black.opacity(0.85), .clear],
                                                 center: .center, startRadius: side * 0.2, endRadius: side * 0.52))
                            .scaleEffect(1 + 0.035 * swell)
                            .offset(y: lift)
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipped()
                // Laid over the screen, not in the ZStack: the drifting colours behind are
                // drawn larger than the screen, and would carry it off the bottom.
                .overlay(alignment: .bottom) {
                    VStack(spacing: standing ? 14 : 0) {
                        VStack(spacing: 4) {
                            Text(track?.title ?? "")
                                .font(.system(size: standing ? 22 : 24, weight: .bold))
                            Text(track?.artistName ?? "")
                                .font(.system(size: 15))
                                .opacity(0.7)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        if standing { keys }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, standing ? 20 : 30)
                    .padding(.bottom, standing ? 26 : 50)
                }
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { if !standing { onWake() } }
        .task(id: track?.id) {
            anchor = Date()
            guard let track else { return }
            let found = await LiquidColors.shared.color(for: track)
            withAnimation(.easeInOut(duration: 1)) { color = found }
        }
        .modifier(VisualizerAccessibility(standing: standing, title: [track?.title, track?.artistName].compactMap { $0 }.joined(separator: ", "),
                                          onWake: onWake))
    }

    /// Standing: back, play or pause, next, and Up Next; closer together, then a little
    /// smaller, on a page too narrow for them as they are.
    private var keys: some View {
        ViewThatFits(in: .horizontal) {
            keyRow(spacing: 18, size: 44, play: 60)
            keyRow(spacing: 8, size: 44, play: 56)
            keyRow(spacing: 4, size: 38, play: 48)
        }
    }

    private func keyRow(spacing: CGFloat, size: CGFloat, play: CGFloat) -> some View {
        HStack(spacing: spacing) {
            key("backward.fill", label: "liquid.previous", id: "liquid.standing.previous", size: size) {
                Task { await musicService.skipToPrevious() }
            }
            Button { Task { await musicService.togglePlayPause() } } label: {
                Image(systemName: musicService.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: play * 0.4, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: play, height: play)
                    .background(.white, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(LyrePressStyle())
            .accessibilityLabel(String(localized: musicService.isPlaying ? "spool.pause" : "spool.play"))
            .accessibilityIdentifier("liquid.playPause")
            key("forward.fill", label: "liquid.next", id: "liquid.standing.next", size: size) {
                Task { await musicService.skipToNext() }
            }
            key("list.bullet", label: "spool.queue.open", id: "liquid.upNext", size: size, action: onOpenQueue)
        }
    }

    private func key(_ symbol: String, label: String, id: String, size: CGFloat,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(.white.opacity(0.14), in: Circle())
                // A touch target no smaller than 44 points, however small the key looks.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(LyrePressStyle())
        .accessibilityLabel(String(localized: String.LocalizationValue(label)))
        .accessibilityIdentifier(id)
    }
}

/// Resting, the whole visualizer is one thing to wake; standing, its keys are each their own.
private struct VisualizerAccessibility: ViewModifier {
    let standing: Bool
    let title: String
    let onWake: () -> Void

    func body(content: Content) -> some View {
        if standing {
            content
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("liquid.standing")
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityHint(String(localized: "liquid.visualizer.hint"))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onWake() }
                .accessibilityIdentifier("liquid.visualizer")
        }
    }
}
