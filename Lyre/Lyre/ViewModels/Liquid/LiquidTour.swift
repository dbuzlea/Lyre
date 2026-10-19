//
//  LiquidTour.swift
//  Lyre
//

import SwiftUI

// MARK: - Liquid Tour
//
// Liquid's tutorial, acted out on a miniature phone: the waves that change songs, tapping
// the cover, Up Next from the bottom, swiping down to go back, the lava menu, swiping a
// song to queue it, a list one cover at a time, and the record at the bottom of the library. Shown in Liquid's
// settings and when Liquid is chosen in onboarding, in the shared TourPager.

enum LiquidLesson: CaseIterable, TourLesson {
    case changeSongs
    case notches
    case upNext
    case goBack
    case lava
    case queueSwipe
    case oneAtATime
    case droplet

    // Each key is written out so the strings are found and localized.
    var title: String {
        switch self {
        case .changeSongs: return String(localized: "liquid.tour.changeSongs.title")
        case .notches:     return String(localized: "liquid.tour.notches.title")
        case .upNext:      return String(localized: "liquid.tour.upNext.title")
        case .goBack:      return String(localized: "liquid.tour.goBack.title")
        case .lava:        return String(localized: "liquid.tour.lava.title")
        case .queueSwipe:  return String(localized: "liquid.tour.queueSwipe.title")
        case .oneAtATime:  return String(localized: "liquid.tour.oneAtATime.title")
        case .droplet:     return String(localized: "liquid.tour.droplet.title")
        }
    }

    var detail: String {
        switch self {
        case .changeSongs: return String(localized: "liquid.tour.changeSongs.detail")
        case .notches:     return String(localized: "liquid.tour.notches.detail")
        case .upNext:      return String(localized: "liquid.tour.upNext.detail")
        case .goBack:      return String(localized: "liquid.tour.goBack.detail")
        case .lava:        return String(localized: "liquid.tour.lava.detail")
        case .queueSwipe:  return String(localized: "liquid.tour.queueSwipe.detail")
        case .oneAtATime:  return String(localized: "liquid.tour.oneAtATime.detail")
        case .droplet:     return String(localized: "liquid.tour.droplet.detail")
        }
    }
}

struct LiquidTourPager: View {
    var ink: Color = .white

    var body: some View {
        TourPager(lessons: LiquidLesson.allCases, ink: ink, idPrefix: "liquid.tour") { lesson, replay in
            LiquidTourScene(lesson: lesson, replay: replay)
        }
    }
}

/// The miniature: a phone showing Now Playing, the lava menu or a list, as the lesson
/// needs, and a fingertip working it.
struct LiquidTourScene: View {
    let lesson: LiquidLesson
    let replay: Int

    private enum Screen { case nowPlaying, lava, list, stack }

    @State private var screen: Screen = .nowPlaying
    @State private var finger: CGPoint?
    @State private var isPressed = false
    @State private var cover = 0
    @State private var waveProgress: CGFloat = 0
    @State private var notchesAway = false
    @State private var tide: CGFloat = 0
    @State private var drop: CGFloat = 0
    @State private var flood: (color: Color, scale: CGFloat)?
    @State private var rowSwipe: CGFloat = 0
    /// The list one at a time: whether it's stacked, the cover on top, the one swiped
    /// off and how far, and how far the top one has swung open.
    @State private var stacked = false
    @State private var stackTop = 0
    @State private var flung: CGFloat = 0
    @State private var swing: CGFloat = 0

    private static let size = CGSize(width: 150, height: 290)
    private static let covers: [[Color]] = [
        [Color(red: 0.17, green: 0.29, blue: 0.48), Color(red: 0.09, green: 0.14, blue: 0.22)],
        [Color(red: 0.54, green: 0.23, blue: 0.29), Color(red: 0.16, green: 0.08, blue: 0.13)],
        [Color(red: 0.2, green: 0.45, blue: 0.32), Color(red: 0.07, green: 0.16, blue: 0.12)]
    ]
    private static let lava = Color(red: 0.98, green: 0.55, blue: 0.27)

    var body: some View {
        ZStack {
            // What's under Now Playing when it's dragged down.
            lavaScreen
            if screen == .list {
                listScreen
            } else if screen == .stack {
                stackScreen
            } else if screen == .nowPlaying {
                nowPlayingScreen
                    .clipShape(RoundedRectangle(cornerRadius: drop > 0 ? 18 : 0))
                    .offset(y: drop)
            }
            if let flood {
                Circle()
                    .fill(flood.color)
                    .frame(width: 700, height: 700)
                    .scaleEffect(flood.scale)
                    .position(finger ?? CGPoint(x: Self.size.width / 2, y: Self.size.height / 2))
            }
            TourFingertip(point: finger, isPressed: isPressed)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.3), lineWidth: 2))
        .frame(maxWidth: .infinity)
        .task(id: "\(lesson)-\(replay)") { await act() }
    }

    // MARK: Screens

    private func coverFill(_ index: Int) -> LinearGradient {
        let colors = Self.covers[index % Self.covers.count]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var nowPlayingScreen: some View {
        ZStack {
            coverFill(cover)
            // The next song's wave on the right, the song before's on the left.
            coverFill(cover + 1)
                .mask(LiquidWaveShape(side: .right, centerY: 120, progress: waveProgress))
                .opacity(notchesAway ? 0 : 1)
            coverFill(cover + 2)
                .mask(LiquidWaveShape(side: .left, centerY: 120, progress: 0))
                .opacity(notchesAway ? 0 : 1)
            VStack(alignment: .leading, spacing: 4) {
                Spacer()
                Capsule().fill(.white).frame(width: 70, height: 7)
                Capsule().fill(.white.opacity(0.6)).frame(width: 46, height: 5)
                Capsule().fill(.white.opacity(0.35)).frame(height: 2).padding(.top, 8)
                LiquidBottomBulge(lift: 0)
                    .fill(.white.opacity(0.25))
                    .frame(height: 16)
                    .padding(.horizontal, -12)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 12)
            // Up Next, rising.
            VStack(spacing: 4) {
                Capsule().fill(.white.opacity(0.4)).frame(width: 24, height: 3).padding(.top, 6)
                ForEach(0..<4, id: \.self) { band in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Self.covers[band % 3][0])
                        .frame(height: 22)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: Self.size.height * 0.75)
            .background(Color(white: 0.09), in: UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14))
            .frame(maxHeight: .infinity, alignment: .bottom)
            .offset(y: (1 - tide) * Self.size.height * 0.8)
        }
    }

    private var lavaScreen: some View {
        ZStack {
            Color.liquidGround
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(LinearGradient(colors: [Self.lava.opacity(0.95), Self.lava.opacity(0.7)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: [52, 42, 46, 38][index], height: [52, 42, 46, 38][index])
                    .position(lavaBlob(index))
            }
            // The record at the bottom.
            Capsule()
                .fill(Color(red: 0.25, green: 0.35, blue: 0.5))
                .frame(height: 30)
                .overlay(alignment: .leading) {
                    Circle().fill(coverFill(cover)).frame(width: 22, height: 22).padding(.leading, 4)
                }
                .padding(.horizontal, 8)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 10)
        }
    }

    private func lavaBlob(_ index: Int) -> CGPoint {
        [CGPoint(x: 52, y: 62), CGPoint(x: 104, y: 112), CGPoint(x: 50, y: 160), CGPoint(x: 102, y: 208)][index]
    }

    private var listScreen: some View {
        ZStack(alignment: .topLeading) {
            Color.liquidGround
            VStack(alignment: .leading, spacing: 0) {
                Capsule().fill(.white).frame(width: 60, height: 9).padding(.bottom, 14)
                ForEach(0..<6, id: \.self) { row in
                    ZStack(alignment: .leading) {
                        if row == 1 {
                            HStack(spacing: 0) {
                                Color(red: 0.42, green: 0.32, blue: 0.86).frame(width: rowSwipe / 2)
                                Color(red: 0.93, green: 0.52, blue: 0.2).frame(width: rowSwipe / 2)
                            }
                        }
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 4).fill(Self.covers[row % 3][0]).frame(width: 22, height: 22)
                            Capsule().fill(.white.opacity(0.7)).frame(width: 60, height: 5)
                        }
                        .offset(x: row == 1 ? rowSwipe : 0)
                    }
                    .frame(height: 34)
                }
            }
            .padding(14)
            .padding(.top, 14)
        }
    }

    private var stackScreen: some View {
        ZStack(alignment: .topLeading) {
            Color.liquidGround
            // The name, and the switch beside it.
            Capsule().fill(.white).frame(width: 60, height: 9).position(x: 44, y: 34)
            Circle().fill(.white.opacity(0.18)).frame(width: 18, height: 18)
                .overlay(Image(systemName: stacked ? "square.grid.2x2" : "rectangle.stack")
                    .font(.system(size: 8, weight: .bold)).foregroundStyle(.white))
                .position(x: 128, y: 34)
            if stacked {
                ZStack {
                    ForEach((1...2).reversed(), id: \.self) { depth in
                        RoundedRectangle(cornerRadius: 10)
                            .fill(coverFill(stackTop + depth))
                            .frame(width: 96, height: 96)
                            .rotationEffect(.degrees(depth == 1 ? -5 : 4))
                            .offset(x: depth == 1 ? -6 : 7, y: CGFloat(depth) * 5)
                            .brightness(-0.1 * Double(depth))
                            .opacity(Double(1 - swing))
                    }
                    // The inside of the cover, and under it the songs, as it swings open.
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(white: 0.16))
                        .frame(width: 66, height: 120)
                        .overlay(VStack(spacing: 6) {
                            ForEach(0..<6, id: \.self) { _ in Capsule().fill(.white.opacity(0.5)).frame(width: 40, height: 3) }
                        })
                        .offset(x: 34)
                        .opacity(swing > 0 ? 1 : 0)
                    RoundedRectangle(cornerRadius: 10)
                        .fill(swing > 0.5 ? AnyShapeStyle(Color(white: 0.22)) : AnyShapeStyle(coverFill(stackTop)))
                        .frame(width: 96 - 30 * swing, height: 96 + 24 * swing)
                        // Its inside: the cover small, and Play. Turned round beforehand
                        // to read the right way once it's over.
                        .overlay {
                            if swing > 0.5 {
                                VStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: 4).fill(coverFill(stackTop)).frame(width: 30, height: 30)
                                    Capsule().fill(.white.opacity(0.8)).frame(width: 36, height: 4)
                                    Capsule().fill(.white).frame(width: 44, height: 12).padding(.top, 14)
                                }
                                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                            }
                        }
                        // Turned on its own left edge, which ends up down the middle.
                        .rotation3DEffect(.degrees(-180 * Double(swing)), axis: (x: 0, y: 1, z: 0),
                                          anchor: .leading, perspective: 0.5)
                        .offset(x: 34 * swing)
                    if flung != 0 {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(coverFill(stackTop - 1))
                            .frame(width: 96, height: 96)
                            .rotationEffect(.degrees(Double(flung) / 10))
                            .offset(x: flung)
                    }
                }
                .position(x: 75, y: 130)
                Capsule().fill(.white).frame(width: 54, height: 6).position(x: 75, y: 200).opacity(1 - swing)
                Capsule().fill(.white.opacity(0.5)).frame(width: 36, height: 4).position(x: 75, y: 212).opacity(1 - swing)
            } else {
                // Every cover at once.
                VStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: 8) {
                            ForEach(0..<2, id: \.self) { column in
                                RoundedRectangle(cornerRadius: 6).fill(coverFill(row * 2 + column)).frame(width: 56, height: 56)
                            }
                        }
                    }
                }
                .position(x: 75, y: 150)
            }
        }
    }

    // MARK: Acting

    private func reset() {
        switch lesson {
        case .lava, .droplet: screen = .lava
        case .queueSwipe: screen = .list
        case .oneAtATime: screen = .stack
        default: screen = .nowPlaying
        }
        stacked = false
        stackTop = 0
        flung = 0
        swing = 0
        finger = nil
        isPressed = false
        cover = 0
        waveProgress = 0
        notchesAway = false
        tide = 0
        drop = 0
        flood = nil
        rowSwipe = 0
    }

    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }

    private func move(to point: CGPoint) async -> Bool {
        withAnimation(.easeInOut(duration: 0.4)) { finger = point }
        return await pause(0.45)
    }

    private func press(_ down: Bool) {
        withAnimation(.easeOut(duration: 0.1)) { isPressed = down }
    }

    /// Floods the miniature with `color` from the fingertip, then shows `then`.
    private func floodTo(_ color: Color, then change: @escaping () -> Void) async -> Bool {
        flood = (color, 0.01)
        withAnimation(.easeIn(duration: 0.35)) { flood?.scale = 1 }
        guard await pause(0.4) else { return false }
        change()
        withAnimation(.easeOut(duration: 0.3)) { flood = nil }
        return await pause(0.35)
    }

    private func act() async {
        reset()
        guard await pause(0.5) else { return }
        switch lesson {
        case .changeSongs:
            guard await move(to: CGPoint(x: 136, y: 120)) else { return }
            press(true)
            withAnimation(.easeInOut(duration: 0.5)) {
                finger = CGPoint(x: 70, y: 124)
                waveProgress = 0.3
            }
            guard await pause(0.55) else { return }
            press(false)
            withAnimation(.easeOut(duration: 0.4)) { waveProgress = 1 }
            guard await pause(0.45) else { return }
            cover = 1
            waveProgress = 0
            withAnimation { finger = nil }

        case .notches:
            guard await move(to: CGPoint(x: 75, y: 90)) else { return }
            press(true)
            guard await pause(0.15) else { return }
            press(false)
            withAnimation(.easeInOut(duration: 0.45)) { notchesAway = true }
            guard await pause(1) else { return }
            press(true)
            guard await pause(0.15) else { return }
            press(false)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { notchesAway = false }
            guard await pause(0.5) else { return }
            withAnimation { finger = nil }

        case .upNext:
            guard await move(to: CGPoint(x: 75, y: 278)) else { return }
            press(true)
            withAnimation(.easeInOut(duration: 0.6)) {
                finger = CGPoint(x: 75, y: 120)
                tide = 1
            }
            guard await pause(0.65) else { return }
            press(false)
            withAnimation { finger = nil }

        case .goBack:
            guard await move(to: CGPoint(x: 75, y: 70)) else { return }
            press(true)
            withAnimation(.easeInOut(duration: 0.55)) {
                finger = CGPoint(x: 75, y: 230)
                drop = 170
            }
            guard await pause(0.6) else { return }
            press(false)
            withAnimation(.easeOut(duration: 0.25)) { drop = Self.size.height + 20 }
            guard await pause(0.3) else { return }
            screen = .lava
            drop = 0
            withAnimation { finger = nil }

        case .lava:
            guard await move(to: lavaBlob(1)) else { return }
            press(true)
            guard await pause(0.15) else { return }
            press(false)
            guard await floodTo(Self.lava, then: { screen = .list }) else { return }
            withAnimation { finger = nil }

        case .queueSwipe:
            guard await move(to: CGPoint(x: 40, y: 94)) else { return }
            press(true)
            withAnimation(.easeInOut(duration: 0.45)) {
                finger = CGPoint(x: 110, y: 94)
                rowSwipe = 80
            }
            guard await pause(0.5) else { return }
            press(false)
            withAnimation { finger = nil }

        case .oneAtATime:
            // The switch beside the name: the covers stack up.
            guard await move(to: CGPoint(x: 128, y: 34)) else { return }
            press(true)
            guard await pause(0.15) else { return }
            press(false)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { stacked = true }
            guard await pause(0.6) else { return }
            // Swiped left, the next one comes up.
            guard await move(to: CGPoint(x: 100, y: 130)) else { return }
            press(true)
            stackTop = 1
            flung = 0.01
            withAnimation(.easeIn(duration: 0.4)) {
                finger = CGPoint(x: 30, y: 134)
                flung = -170
            }
            guard await pause(0.45) else { return }
            press(false)
            flung = 0
            guard await pause(0.3) else { return }
            // Tapped, it swings open.
            guard await move(to: CGPoint(x: 75, y: 130)) else { return }
            press(true)
            guard await pause(0.15) else { return }
            press(false)
            withAnimation(.spring(response: 0.68, dampingFraction: 0.74)) { swing = 1 }
            guard await pause(0.6) else { return }
            withAnimation { finger = nil }

        case .droplet:
            guard await move(to: CGPoint(x: 70, y: 265)) else { return }
            press(true)
            guard await pause(0.15) else { return }
            press(false)
            guard await floodTo(Self.covers[0][0], then: { screen = .nowPlaying }) else { return }
            withAnimation { finger = nil }
        }
    }
}
