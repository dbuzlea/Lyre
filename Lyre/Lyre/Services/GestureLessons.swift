//
//  GestureLessons.swift
//  Lyre
//

import SwiftUI

// MARK: - Gesture Lessons
//
// Some of Lyre's players are worked by gestures a picture can't show: a tape swiped into
// the deck, a record flipped in the bin, the needle dragged across the grooves. Each says
// how, in a line on screen, until the person has done it a few times; then the line goes,
// and the object is left to itself. (Every gesture still has a button or a menu item, and
// VoiceOver's hints and actions, for anyone who'd rather not.)

@Observable
@MainActor
final class GestureLessons {
    static let shared = GestureLessons()

    enum Lesson: String, CaseIterable {
        /// Spool and Disc: a tape or case swiped left (or tapped at the front) into the deck.
        case insert
        /// Spool's Up Next tray: tap to play, hold to move, swipe to remove.
        case upNextList
        /// Gramophone's bin: flip, play, reorder, remove.
        case gramophoneRack
        /// Gramophone: the needle dragged to another band.
        case needle
        /// Classic's queue: swipe to play or remove, select to move.
        case classicQueue
    }

    /// How many times a gesture's done before its line goes.
    static let learnedAfter = 3
    private static let key = "LyreGestureLessons"

    private var counts: [String: Int]
    /// UI tests start each launch knowing nothing, and don't keep what they did.
    private let remembers: Bool

    private init() {
        let arguments = ProcessInfo.processInfo.arguments
        remembers = !arguments.contains("--uitest")
        if arguments.contains("--lyre-gestures-learned") {
            counts = Dictionary(uniqueKeysWithValues: Lesson.allCases.map { ($0.rawValue, Self.learnedAfter) })
        } else {
            counts = remembers ? (UserDefaults.standard.dictionary(forKey: Self.key) as? [String: Int] ?? [:]) : [:]
        }
    }

    /// Whether the person has done this enough to need no reminding.
    func learned(_ lesson: Lesson) -> Bool {
        counts[lesson.rawValue, default: 0] >= Self.learnedAfter
    }

    /// The gesture was done once more.
    func did(_ lesson: Lesson) {
        guard !learned(lesson) else { return }
        counts[lesson.rawValue, default: 0] += 1
        if remembers { UserDefaults.standard.set(counts, forKey: Self.key) }
    }

    /// Every line back, as for someone new (Settings).
    func forget() {
        counts = [:]
        if remembers { UserDefaults.standard.removeObject(forKey: Self.key) }
    }
}

/// Settings' Show Gesture Tips Again: every gesture's line back, as for someone new.
/// `card` is the outlined row of Spool, Disc and Gramophone; otherwise a list row (Liquid).
struct GestureTipsButton: View {
    var card = true
    @State private var isBack = false

    var body: some View {
        Button {
            GestureLessons.shared.forget()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(LyreMotion.light) { isBack = true }
        } label: {
            if card {
                HStack(spacing: 12) {
                    Image(systemName: "hand.draw")
                        .font(.system(size: 18, weight: .semibold))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "settings.gestureTips"))
                            .lyreFont(size: 15, weight: .semibold, maxScale: 2)
                        Text(String(localized: isBack ? "settings.gestureTips.back" : "settings.gestureTips.detail"))
                            .lyreFont(size: 12, maxScale: 2)
                            .lyreFaded(0.7)
                            .contentTransition(.opacity)
                    }
                    .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).strokeBorder(lineWidth: 1.5).opacity(0.5))
                .contentShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Label(String(localized: isBack ? "settings.gestureTips.back" : "settings.gestureTips"),
                      systemImage: "hand.draw")
            }
        }
        .buttonStyle(LyrePressStyle(isRow: true))
        .accessibilityIdentifier("settings.gestureTips")
    }
}
