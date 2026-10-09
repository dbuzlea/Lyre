//
//  TourPager.swift
//  Lyre
//

import SwiftUI

// MARK: - Tour Pager
//
// The tutorial as every player's manual shows it: one lesson at a time, acted out on a
// miniature of the player above its name and what to do, with Previous, Next and Play
// Again under it. Tapping the miniature plays the lesson again.
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

    private var lesson: Lesson { lessons[index] }

    var body: some View {
        VStack(spacing: 14) {
            scene(lesson, replays)
                .id(lesson)
                .transition(.opacity)
                .contentShape(Rectangle())
                .onTapGesture { replays += 1 }
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(String(format: String(localized: "spool.tour.lessonOf"), index + 1, lessons.count))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .tracking(1)
                    .opacity(0.6)
                Text(lesson.title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(lesson.detail)
                    .font(.subheadline)
                    .opacity(0.8)
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
        withAnimation(.easeInOut(duration: 0.2)) { index += step }
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
