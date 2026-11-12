//
//  TourPager.swift
//  Lyre
//

import SwiftUI

// MARK: - Tour Pager
//
// The tutorial as every player's manual shows it: one lesson at a time, acted out on a
// miniature of the player above its name and what to do, with Previous, Next and Play
// Again under it. Tapping the miniature plays the lesson again. Swiping across the pager
// turns the lessons too — left for the next, right for the one before — and each lesson
// slides in from the side it's coming from.
//
// Each player brings its own lessons and its own miniature (SpoolTourScene,
// GramophoneTourScene); the pager is shared so the tutorials work the same way.

/// A lesson in a player's tutorial.
protocol TourLesson: Hashable {
    var title: String { get }
    var detail: String { get }
}

struct TourPager<Lesson: TourLesson, Scene: View>: View {
    let lessons: [Lesson]
    /// The words' and buttons' colour: white on onboarding, ink on a manual's paper.
    let ink: Color
    /// Prefixes the accessibility identifiers, so UI tests can tell the tours apart.
    var idPrefix = "spool.tour"
    /// The miniature acting a lesson out; the second value changes to play it again.
    @ViewBuilder let scene: (Lesson, Int) -> Scene

    @State private var index = 0
    /// Bumped to play the lesson on screen again.
    @State private var replays = 0
    /// Which way the last turn went, so the next lesson slides in from that side.
    @State private var forward = true

    private var lesson: Lesson { lessons[index] }

    var body: some View {
        VStack(spacing: 14) {
            scene(lesson, replays)
                .id(lesson)
                .transition(.asymmetric(
                    insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                .contentShape(Rectangle())
                .onTapGesture { replays += 1 }
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(String(format: String(localized: "spool.tour.lessonOf"), index + 1, lessons.count))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .tracking(1)
                    .lyreFaded(0.6)
                Text(lesson.title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(lesson.detail)
                    .font(.subheadline)
                    .lyreFaded(0.8)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 60, alignment: .top)
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("\(idPrefix).lesson")

            HStack(spacing: 12) {
                stepButton("chevron.left", label: "spool.tour.previous", id: "\(idPrefix).previous",
                           enabled: index > 0) { go(by: -1) }
                Spacer(minLength: 0)
                dots
                Spacer(minLength: 0)
                stepButton("arrow.counterclockwise", label: "spool.tour.replay", id: "\(idPrefix).replay",
                           enabled: true) { replays += 1 }
                stepButton("chevron.right", label: "spool.tour.next", id: "\(idPrefix).next",
                           enabled: index < lessons.count - 1) { go(by: 1) }
            }
            .foregroundStyle(ink)
        }
        .clipped()
        .contentShape(Rectangle())
        // A swipe across turns the lessons, as the arrows do. A UIKit pan that only begins
        // for a sideways swipe: an up or down one never reaches it, so the manual around
        // the pager scrolls from anywhere on it (a SwiftUI drag here held the scroll back).
        .modifier(TourSwipe { dx, flung in
            guard abs(dx) > 50 || abs(flung) > 160 else { return }
            if dx < 0, index < lessons.count - 1 {
                go(by: 1)
            } else if dx > 0, index > 0 {
                go(by: -1)
            }
        })
        .accessibilityAction(named: String(localized: "spool.tour.next")) {
            if index < lessons.count - 1 { go(by: 1) }
        }
        .accessibilityAction(named: String(localized: "spool.tour.previous")) {
            if index > 0 { go(by: -1) }
        }
    }

    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(lessons.indices, id: \.self) { dot in
                Circle()
                    .fill(ink.opacity(dot == index ? 0.9 : 0.25))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    private func stepButton(_ symbol: String, label: String.LocalizationValue, id: String,
                            enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 40, height: 40)
                .background(ink.opacity(0.1), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(String(localized: label))
        .accessibilityIdentifier(id)
    }

    private func go(by step: Int) {
        UISelectionFeedbackGenerator().selectionChanged()
        forward = step > 0
        withAnimation(.easeInOut(duration: 0.28)) { index += step }
    }
}

/// The pager's swipe: begins only when the finger moves clearly sideways, and runs
/// alongside the page's scroll rather than in its way. Reports the distance across and
/// where a fling would have carried it.
private struct TourSwipe: ViewModifier {
    let onEnd: (CGFloat, CGFloat) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.gesture(TourSwipePan(onEnd: onEnd))
        } else {
            content
        }
    }
}

@available(iOS 18.0, *)
private struct TourSwipePan: UIGestureRecognizerRepresentable {
    let onEnd: (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        guard recognizer.state == .ended else { return }
        let dx = recognizer.translation(in: recognizer.view).x
        onEnd(dx, dx + LyreMotion.project(recognizer.velocity(in: recognizer.view).x))
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.4
        }
    }
}

// MARK: - Fingertip

/// The ghost fingertip that acts a lesson out on a miniature, as onboarding's does on
/// the wheel: a soft white disc that shrinks a little while pressed.
struct TourFingertip: View {
    let point: CGPoint?
    var isPressed = false

    var body: some View {
        if let point {
            Circle()
                .fill(.white.opacity(0.45))
                .overlay(Circle().stroke(.white.opacity(0.95), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
                .frame(width: 28, height: 28)
                .scaleEffect(isPressed ? 0.8 : 1)
                .position(point)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }
}
