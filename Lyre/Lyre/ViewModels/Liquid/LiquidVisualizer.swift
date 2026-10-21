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

    @State private var color: Color = Color(red: 0.17, green: 0.29, blue: 0.48)
    @State private var anchor = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var track: AppTrack? { musicService.nowPlayingTrack }

    private var beatsPerMinute: Double? {
        guard let bpm = track?.mpItem?.beatsPerMinute, (40...220).contains(bpm) else { return nil }
        return Double(bpm)
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let side = min(size.width, size.height) * 0.5
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
                    }
                    // The cover, its edge dissolving, swelling a little on each beat.
                    if let track {
                        LiquidCover(source: .track(track))
                            .frame(width: side, height: side)
                            .mask(RadialGradient(colors: [.black, .black.opacity(0.85), .clear],
                                                 center: .center, startRadius: side * 0.2, endRadius: side * 0.52))
                            .scaleEffect(1 + 0.035 * swell)
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipped()
                // Laid over the screen, not in the ZStack: the drifting colours behind are
                // drawn larger than the screen, and would carry it off the bottom.
                .overlay(alignment: .bottom) {
                    VStack(spacing: 4) {
                        Text(track?.title ?? "")
                            .font(.system(size: 24, weight: .bold))
                        Text(track?.artistName ?? "")
                            .font(.system(size: 15))
                            .opacity(0.7)
                    }
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 30)
                    .padding(.bottom, 50)
                }
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: onWake)
        .task(id: track?.id) {
            anchor = Date()
            guard let track else { return }
            let found = await LiquidColors.shared.color(for: track)
            withAnimation(.easeInOut(duration: 1)) { color = found }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([track?.title, track?.artistName].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(String(localized: "liquid.visualizer.hint"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onWake() }
        .accessibilityIdentifier("liquid.visualizer")
    }
}
