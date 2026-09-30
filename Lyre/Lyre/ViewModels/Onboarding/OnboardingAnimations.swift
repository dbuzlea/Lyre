//
//  OnboardingAnimations.swift
//  Lyre
//

import SwiftUI
import AudioToolbox
import MusicKit

// MARK: - Onboarding Animations
//
// The moving parts of onboarding, kept together so every step animates the same way:
//
//   onboardingEntrance(_:)   page content fades and rises in, one piece after another
//   GhostFinger              a translucent fingertip that demonstrates the wheel
//   CompletionBurst          a ring of dots thrown out when a practice lesson is done
//   DrawnCheckmark           a checkmark that draws itself
//   ShortcutDemoIcon         each shortcut's gesture, played once
//   LibraryMosaic            the user's own covers flipping in as the library loads
//   OnboardingClick          the wheel's click and tap, for moments that "land"
//
// Two rules hold throughout. Everything plays once and stops — an animation that never
// ends keeps the app from going idle, which UI tests wait for, and wastes battery.
// And Reduce Motion replaces movement with a plain fade, or skips the demonstration:
// the words on each page teach the same thing.

// MARK: - Entrance

private struct OnboardingEntrance: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                let animation: Animation = reduceMotion
                    ? .easeOut(duration: 0.2)
                    : .spring(response: 0.5, dampingFraction: 0.85).delay(Double(index) * 0.06)
                withAnimation(animation) { shown = true }
            }
    }
}

extension View {
    /// Fades and lifts the view in, `index` steps after the first thing on the page.
    func onboardingEntrance(_ index: Int) -> some View {
        modifier(OnboardingEntrance(index: index))
    }
}

// MARK: - Click

enum OnboardingClick {
    /// The wheel's click, when click sound is on, with a light tap either way.
    @MainActor
    static func play(sound: Bool) {
        if sound { AudioServicesPlaySystemSound(1104) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Ghost Finger

/// Drives the demonstration fingertip. Positions are fractions of the wheel's size,
/// measured from its center, so one finger fits any wheel.
@Observable
@MainActor
final class GhostFinger {
    /// Where the fingertip is, or nil while it's hidden.
    var position: CGPoint?
    var pressed = false
    /// Bumped on every press, to start a ripple where the finger pressed.
    var rippleCount = 0
    var ripplePosition: CGPoint = .zero

    /// Halfway across the ring — where the wheel's button labels sit.
    static let ringRadius: CGFloat = 0.3575

    static func point(for button: PracticeWheelButton?) -> CGPoint {
        switch button {
        case .menu?:      return CGPoint(x: 0, y: -ringRadius)
        case .playPause?: return CGPoint(x: 0, y: ringRadius)
        case .previous?:  return CGPoint(x: -ringRadius, y: 0)
        case .next?:      return CGPoint(x: ringRadius, y: 0)
        case nil:         return .zero          // the center button
        }
    }

    private static func point(atDegrees degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: cos(radians) * ringRadius, y: sin(radians) * ringRadius)
    }

    /// Traces the ring clockwise from the top, calling `onStep` every `stepDegrees`, the
    /// way a list moves under a real spin.
    func spin(degrees: Double = 270, duration: Double = 1.8, stepDegrees: Double = 45,
              onStep: () -> Void = {}) async {
        let start = -90.0
        withAnimation(.easeOut(duration: 0.25)) { position = Self.point(atDegrees: start) }
        try? await Task.sleep(for: .milliseconds(350))

        let frames = max(1, Int(duration * 60))
        var steps = 0
        for frame in 1...frames {
            guard !Task.isCancelled else { break }
            let angle = start + degrees * Double(frame) / Double(frames)
            position = Self.point(atDegrees: angle)
            let reached = Int((angle - start) / stepDegrees)
            if reached > steps {
                steps = reached
                onStep()
            }
            try? await Task.sleep(for: .milliseconds(16))
        }
        hide()
    }

    /// Moves to a button, presses it with a ripple, and lifts away.
    func tap(_ button: PracticeWheelButton?, onPress: () -> Void = {}) async {
        let target = Self.point(for: button)
        withAnimation(.easeOut(duration: 0.25)) { position = target }
        try? await Task.sleep(for: .milliseconds(380))
        guard !Task.isCancelled else { return hide() }

        ripplePosition = target
        withAnimation(.easeIn(duration: 0.1)) { pressed = true }
        rippleCount += 1
        onPress()
        try? await Task.sleep(for: .milliseconds(180))
        withAnimation(.easeOut(duration: 0.15)) { pressed = false }
        try? await Task.sleep(for: .milliseconds(350))
        hide()
    }

    func hide() {
        withAnimation(.easeIn(duration: 0.25)) {
            position = nil
            pressed = false
        }
    }
}

/// Draws a GhostFinger over a wheel of the given size. Never takes touches.
struct GhostFingerOverlay: View {
    let ghost: GhostFinger
    let size: CGFloat

    @State private var rippleProgress: CGFloat = 1

    var body: some View {
        ZStack {
            // The ripple, where the finger last pressed.
            Circle()
                .stroke(.white, lineWidth: 2)
                .frame(width: size * 0.2, height: size * 0.2)
                .scaleEffect(0.6 + rippleProgress * 1.4)
                .opacity(Double(1 - rippleProgress) * 0.8)
                .offset(x: ghost.ripplePosition.x * size, y: ghost.ripplePosition.y * size)

            if let position = ghost.position {
                Circle()
                    .fill(.white.opacity(0.4))
                    .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                    .frame(width: size * 0.17, height: size * 0.17)
                    .scaleEffect(ghost.pressed ? 0.82 : 1)
                    .offset(x: position.x * size, y: position.y * size)
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: ghost.rippleCount) {
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { rippleProgress = 0 }
            withAnimation(.easeOut(duration: 0.55)) { rippleProgress = 1 }
        }
    }
}

// MARK: - Completion Burst

/// A ring of dots thrown outward each time `trigger` changes.
struct CompletionBurst: View {
    let trigger: Int
    let size: CGFloat
    var color: Color = .green

    @State private var progress: CGFloat = 1
    private let dots = 12

    var body: some View {
        ZStack {
            ForEach(0..<dots, id: \.self) { index in
                let angle = Double(index) / Double(dots) * 2 * .pi
                let radius = size * (0.44 + 0.2 * progress)
                Circle()
                    .fill(index.isMultiple(of: 2) ? color : .white)
                    .frame(width: 7, height: 7)
                    .scaleEffect(1 - progress * 0.6)
                    .offset(x: cos(angle) * radius, y: sin(angle) * radius)
            }
        }
        .opacity(Double(1 - progress))
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) {
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { progress = 0 }
            withAnimation(.easeOut(duration: 0.65)) { progress = 1 }
        }
    }
}

// MARK: - Drawn Checkmark

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.27, y: rect.minY + rect.height * 0.53))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.69))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.75, y: rect.minY + rect.height * 0.35))
        return path
    }
}

/// A green disc whose checkmark draws itself in when it appears.
struct DrawnCheckmark: View {
    var size: CGFloat = 28
    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(.green)
            CheckmarkShape()
                .trim(from: 0, to: progress)
                .stroke(.white, style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { progress = 1; return }
            withAnimation(.easeOut(duration: 0.45).delay(0.1)) { progress = 1 }
        }
    }
}

// MARK: - Shortcut Demos

/// The icon for one shortcut, which acts out its gesture once, `delay` after appearing.
struct ShortcutDemoIcon: View {
    enum Demo { case swipe, rotate, shake, hold, resize }

    let demo: Demo
    var delay: Double = 0

    @State private var offsetX: CGFloat = 0
    @State private var angle: Double = 0
    @State private var scale: CGFloat = 1
    @State private var holdOn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        icon
            .offset(x: offsetX)
            .rotationEffect(.degrees(angle))
            .scaleEffect(scale)
            .frame(width: 36, height: 30)
            .accessibilityHidden(true)
            .task {
                guard !reduceMotion else { return }
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                await play()
            }
    }

    @ViewBuilder
    private var icon: some View {
        switch demo {
        case .swipe:
            Image(systemName: "hand.point.right").font(.title2).foregroundStyle(.white)
        case .rotate:
            Image(systemName: "iphone").font(.title2).foregroundStyle(.white)
        case .shake:
            Image(systemName: "iphone.gen3").font(.title2).foregroundStyle(.white)
        case .hold:
            Capsule()
                .fill(.white.opacity(0.25))
                .frame(width: 30, height: 16)
                .overlay(alignment: holdOn ? .trailing : .leading) {
                    Capsule()
                        .fill(holdOn ? Color.orange : .white)
                        .frame(width: 14, height: 12)
                        .padding(.horizontal, 2)
                }
        case .resize:
            Image(systemName: "arrow.up.left.and.arrow.down.right").font(.title2).foregroundStyle(.white)
        }
    }

    private func play() async {
        switch demo {
        case .swipe:
            withAnimation(.easeOut(duration: 0.35)) { offsetX = 12 }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.easeInOut(duration: 0.3)) { offsetX = 0 }
        case .rotate:
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { angle = 90 }
            try? await Task.sleep(for: .milliseconds(800))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { angle = 0 }
        case .shake:
            for tilt in [14.0, -14, 12, -12, 8, -8] {
                withAnimation(.easeInOut(duration: 0.07)) { angle = tilt }
                try? await Task.sleep(for: .milliseconds(70))
            }
            withAnimation(.easeOut(duration: 0.1)) { angle = 0 }
        case .hold:
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { holdOn = true }
            try? await Task.sleep(for: .milliseconds(1000))
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { holdOn = false }
        case .resize:
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { scale = 1.3 }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { scale = 1 }
        }
    }
}

// MARK: - Library Mosaic

/// Up to nine of the user's own covers, flipping in one after another once the
/// library has loaded — so the wait ends on something that is recognisably theirs.
struct LibraryMosaic: View {
    let albums: [AppAlbum]
    var tile: CGFloat = 60

    @State private var shown = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var covers: [AppAlbum] {
        Array(albums.lazy.filter { $0.musicKitAlbum?.artwork != nil || $0.mpArtwork != nil }.prefix(9))
    }

    var body: some View {
        let covers = covers
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(tile), spacing: 8), count: 3), spacing: 8) {
            ForEach(Array(covers.enumerated()), id: \.element.id) { index, album in
                cover(album)
                    .rotation3DEffect(.degrees(index < shown || reduceMotion ? 0 : 90), axis: (x: 0, y: 1, z: 0))
                    .opacity(index < shown ? 1 : 0)
            }
        }
        .accessibilityHidden(true)
        .task(id: covers.map(\.id)) {
            shown = 0
            for index in covers.indices {
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 90))
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? .easeOut(duration: 0.3) : .spring(response: 0.45, dampingFraction: 0.75)) {
                    shown = index + 1
                }
            }
        }
    }

    @ViewBuilder
    private func cover(_ album: AppAlbum) -> some View {
        Group {
            if let artwork = album.musicKitAlbum?.artwork {
                ArtworkImage(artwork, width: tile)
            } else {
                LocalArtworkImage(cacheKey: "album.\(album.id)", size: tile, artwork: album.mpArtwork) { image in
                    image.resizable()
                } placeholder: {
                    Color.white.opacity(0.1)
                }
            }
        }
        .frame(width: tile, height: tile)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
    }
}
