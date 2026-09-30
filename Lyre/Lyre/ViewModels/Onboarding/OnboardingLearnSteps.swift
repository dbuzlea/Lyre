//
//  OnboardingLearnSteps.swift
//  Lyre
//

import SwiftUI

// MARK: - Learn the Wheel
//
// Three steps that take someone who has never used a click wheel to using one:
//
//   MeetTheWheelStep  what each part of the wheel does, shown by a ghost finger: it
//                     traces the ring as the list above it moves, and tapping a part
//                     in the list has the finger press that spot, so the words, the
//                     place and the effect connect.
//   PracticeStep      a guided lesson on a working wheel — scroll, open, go back —
//                     with one instruction at a time, a burst and a tick as each is
//                     done, and the ghost finger demonstrating once if the user stalls.
//   ShortcutsStep     the extras, framed as "for later" so nobody feels they have to
//                     memorise them now.

// MARK: - Meet the Wheel

struct MeetTheWheelStep: View {
    let theme: LyreTheme
    let onNext: () -> Void

    private enum Part: CaseIterable {
        case spin, center, menu, playPause, skip
    }

    @State private var focused: Part = .spin
    @State private var ghost = GhostFinger()
    @State private var demo: Task<Void, Never>?
    /// The demonstration list's highlighted row, moved by the ghost finger.
    @State private var demoSelection = 0
    /// Title of the demonstration screen: the menu, or the row the center "opened".
    @State private var demoOpened: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let wheelSize: CGFloat = 190
    private let rows = [
        String(localized: "menu.nowPlaying"),
        String(localized: "menu.songs"),
        String(localized: "menu.albums"),
        String(localized: "menu.artists"),
        String(localized: "menu.playlists"),
        String(localized: "menu.podcasts"),
        String(localized: "menu.settings"),
    ]

    var body: some View {
        OnboardingPage(title: String(localized: "onboarding.wheel.title"),
                       message: String(localized: "onboarding.wheel.message")) {
            VStack(spacing: 16) {
                OnboardingMiniScreen(theme: theme,
                                     title: demoOpened.map { rows[$0] } ?? String(localized: "app.name"),
                                     rows: demoOpened == nil ? rows : [String(localized: "onboarding.practice.sample1"),
                                                                       String(localized: "onboarding.practice.sample2")],
                                     selection: demoOpened == nil ? demoSelection : 0,
                                     showsBack: demoOpened != nil)
                    .frame(width: 210, height: 100)
                    .accessibilityHidden(true)

                ZStack {
                    OnboardingPracticeWheel(
                        theme: theme,
                        size: Self.wheelSize,
                        emphasized: emphasizedButton,
                        emphasizeCenter: focused == .center
                    )
                    GhostFingerOverlay(ghost: ghost, size: Self.wheelSize)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .task {
                    try? await Task.sleep(for: .milliseconds(700))
                    guard !Task.isCancelled else { return }
                    demonstrate(.spin)
                }
                .onDisappear { demo?.cancel() }

                VStack(spacing: 6) {
                    partRow(.spin, symbol: "arrow.clockwise",
                            title: "onboarding.wheel.spin.title", detail: "onboarding.wheel.spin.detail")
                    partRow(.center, symbol: "circle.fill",
                            title: "onboarding.wheel.center.title", detail: "onboarding.wheel.center.detail")
                    partRow(.menu, symbol: "line.horizontal.3",
                            title: "onboarding.wheel.menu.title", detail: "onboarding.wheel.menu.detail")
                    partRow(.playPause, symbol: "playpause.fill",
                            title: "onboarding.wheel.play.title", detail: "onboarding.wheel.play.detail")
                    partRow(.skip, symbol: "forward.fill",
                            title: "onboarding.wheel.skip.title", detail: "onboarding.wheel.skip.detail")
                }
            }
        } footer: {
            OnboardingPrimaryButton(title: String(localized: "onboarding.wheel.tryIt"), action: onNext)
        }
    }

    private var emphasizedButton: PracticeWheelButton? {
        switch focused {
        case .menu:      return .menu
        case .playPause: return .playPause
        case .skip:      return .next
        case .spin, .center: return nil
        }
    }

    /// Has the ghost finger act the part out on the wheel, and the screen respond.
    private func demonstrate(_ part: Part) {
        guard !reduceMotion else { return }
        demo?.cancel()
        ghost.hide()
        demo = Task {
            switch part {
            case .spin:
                demoOpened = nil
                await ghost.spin {
                    withAnimation(.easeOut(duration: 0.1)) {
                        demoSelection = (demoSelection + 1) % rows.count
                    }
                }
            case .center:
                await ghost.tap(nil) { withAnimation { demoOpened = demoSelection } }
            case .menu:
                if demoOpened == nil { demoOpened = demoSelection }
                await ghost.tap(.menu) { withAnimation { demoOpened = nil } }
            case .playPause:
                await ghost.tap(.playPause)
            case .skip:
                await ghost.tap(.next)
            }
        }
    }

    private func partRow(_ part: Part, symbol: String, title: String.LocalizationValue, detail: String.LocalizationValue) -> some View {
        Button {
            focused = part
            demonstrate(part)
        } label: {
            OnboardingInfoRow(symbol: symbol, title: String(localized: title), detail: String(localized: detail))
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.white.opacity(focused == part ? 0.12 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "onboarding.wheel.showOnWheel"))
        .accessibilityAddTraits(focused == part ? .isSelected : [])
    }
}

// MARK: - Practice

struct PracticeStep: View {
    let themeSettings: ThemeSettings
    let onNext: () -> Void

    private enum Lesson: Int, CaseIterable {
        case scroll, open, back
    }

    @State private var lesson: Lesson = .scroll
    @State private var finished = false
    @State private var scrolledSteps = 0
    @State private var selection = 0
    @State private var openedRow: Int?
    @State private var detailSelection = 0
    /// A one-line reaction to a press that isn't part of the current lesson.
    @State private var hint: String?
    @State private var ghost = GhostFinger()
    /// Bumped on each lesson completed, to throw the burst.
    @State private var bursts = 0
    /// When the wheel was last used, so a stalled user gets one demonstration.
    @State private var lastInteraction = Date()
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let wheelSize: CGFloat = 210

    private let menuRows = [
        String(localized: "menu.nowPlaying"),
        String(localized: "menu.songs"),
        String(localized: "menu.albums"),
        String(localized: "menu.artists"),
        String(localized: "menu.playlists"),
        String(localized: "menu.podcasts"),
        String(localized: "menu.settings"),
    ]

    private let sampleRows = [
        String(localized: "onboarding.practice.sample1"),
        String(localized: "onboarding.practice.sample2"),
        String(localized: "onboarding.practice.sample3"),
        String(localized: "onboarding.practice.sample4"),
    ]

    var body: some View {
        OnboardingPage(title: String(localized: "onboarding.practice.title"), compact: true) {
            VStack(spacing: 12) {
                instructionCard

                screen
                    .frame(width: 220, height: 112)

                ZStack {
                    OnboardingPracticeWheel(
                        theme: themeSettings.currentTheme,
                        sensitivity: themeSettings.scrollSensitivity,
                        clickSound: themeSettings.clickSoundEnabled,
                        size: Self.wheelSize,
                        emphasized: !finished && lesson == .back ? .menu : nil,
                        emphasizeCenter: !finished && lesson == .open,
                        onScroll: scrolled,
                        onSelect: selected,
                        onButton: pressed
                    )
                    GhostFingerOverlay(ghost: ghost, size: Self.wheelSize)
                    CompletionBurst(trigger: bursts, size: Self.wheelSize)
                }
                .task(id: lesson) { await nudgeIfStalled() }

                if let hint {
                    Text(hint)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }
            }
        } footer: {
            OnboardingPrimaryButton(title: String(localized: "onboarding.continue"), isEnabled: finished, action: onNext)
            if !finished {
                OnboardingSecondaryButton(title: String(localized: "onboarding.practice.skip"), action: onNext)
            }
        }
    }

    // MARK: Pieces

    private var screen: some View {
        Group {
            if let openedRow {
                OnboardingMiniScreen(theme: themeSettings.currentTheme, title: menuRows[openedRow],
                                     rows: sampleRows, selection: detailSelection, showsBack: true)
            } else {
                OnboardingMiniScreen(theme: themeSettings.currentTheme, title: String(localized: "app.name"),
                                     rows: menuRows, selection: selection)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: openedRow)
    }

    private var instructionCard: some View {
        VStack(spacing: 6) {
            if finished {
                HStack(spacing: 10) {
                    DrawnCheckmark(size: 26)
                    Text(String(localized: "onboarding.practice.done"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.green)
                }
                Text(String(localized: "onboarding.practice.doneDetail"))
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.85))
            } else {
                progressDots
                Text(instruction(for: lesson))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.08)))
        .accessibilityElement(children: .combine)
    }

    /// "Step n of 3" with a tick for each lesson done — the lesson names are read out
    /// for VoiceOver.
    private var progressDots: some View {
        HStack(spacing: 10) {
            Text(String(format: String(localized: "onboarding.practice.stepOf"), lesson.rawValue + 1, Lesson.allCases.count))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))
            ForEach(Lesson.allCases, id: \.self) { item in
                let done = item.rawValue < lesson.rawValue
                Image(systemName: done ? "checkmark.circle.fill" : (item == lesson ? "circle.inset.filled" : "circle"))
                    .font(.subheadline)
                    .foregroundStyle(done ? .green : .white.opacity(0.7))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: done)
                    .accessibilityLabel(checklistTitle(for: item))
                    .accessibilityValue(done ? String(localized: "onboarding.practice.completed") : "")
            }
        }
    }

    private func instruction(for lesson: Lesson) -> String {
        switch lesson {
        case .scroll:
            return String(localized: voiceOver ? "onboarding.practice.scroll.voiceOver" : "onboarding.practice.scroll")
        case .open:
            return String(format: String(localized: "onboarding.practice.open"), menuRows[selection])
        case .back:
            return String(localized: "onboarding.practice.back")
        }
    }

    private func checklistTitle(for lesson: Lesson) -> String {
        switch lesson {
        case .scroll: return String(localized: "onboarding.practice.check.scroll")
        case .open:   return String(localized: "onboarding.practice.check.open")
        case .back:   return String(localized: "onboarding.practice.check.back")
        }
    }

    // MARK: Nudge

    /// If the wheel sits untouched for six seconds during a lesson, the ghost finger
    /// shows that lesson's move once. It never repeats, and never interrupts use.
    private func nudgeIfStalled() async {
        guard !reduceMotion else { return }
        lastInteraction = Date()
        while !Task.isCancelled, !finished {
            try? await Task.sleep(for: .seconds(1))
            guard Date().timeIntervalSince(lastInteraction) >= 6 else { continue }
            switch lesson {
            case .scroll: await ghost.spin(degrees: 180, duration: 1.2)
            case .open:   await ghost.tap(nil)
            case .back:   await ghost.tap(.menu)
            }
            return
        }
    }

    private func interacted() {
        lastInteraction = Date()
        if ghost.position != nil { ghost.hide() }
    }

    // MARK: Wheel Events

    private func scrolled(_ direction: Int) {
        interacted()
        if openedRow != nil {
            detailSelection = min(max(detailSelection + direction, 0), sampleRows.count - 1)
        } else {
            selection = min(max(selection + direction, 0), menuRows.count - 1)
        }
        hint = nil
        guard lesson == .scroll, !finished else { return }
        scrolledSteps += 1
        if scrolledSteps >= 3 { complete(.scroll) }
    }

    private func selected() {
        interacted()
        guard openedRow == nil else {
            hint = String(localized: "onboarding.practice.hint.inside")
            return
        }
        withAnimation { openedRow = selection }
        detailSelection = 0
        hint = nil
        if lesson == .open { complete(.open) }
        else if lesson == .scroll { hint = String(localized: "onboarding.practice.hint.opened") }
    }

    private func pressed(_ button: PracticeWheelButton) {
        interacted()
        switch button {
        case .menu:
            guard openedRow != nil else {
                hint = String(localized: "onboarding.practice.hint.topLevel")
                return
            }
            withAnimation { openedRow = nil }
            hint = nil
            if lesson == .back { complete(.back) }
        case .playPause:
            hint = String(localized: "onboarding.practice.hint.play")
        case .previous, .next:
            hint = String(localized: "onboarding.practice.hint.skip")
        }
    }

    private func complete(_ done: Lesson) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if !reduceMotion { bursts += 1 }
        if let next = Lesson(rawValue: done.rawValue + 1) {
            withAnimation { lesson = next }
            AccessibilityNotification.Announcement(
                String(localized: "onboarding.practice.nice") + " " + instruction(for: next)
            ).post()
        } else {
            withAnimation { finished = true }
            AccessibilityNotification.Announcement(String(localized: "onboarding.practice.done")).post()
        }
    }
}

// MARK: - Shortcuts

struct ShortcutsStep: View {
    let onNext: () -> Void

    var body: some View {
        OnboardingPage(symbol: "sparkles",
                       title: String(localized: "onboarding.shortcuts.title"),
                       message: String(localized: "onboarding.shortcuts.message")) {
            // Each row acts out its gesture once, in turn, as the page settles.
            VStack(alignment: .leading, spacing: 22) {
                shortcut(.swipe, 0, "onboarding.shortcuts.swipe.title", "onboarding.shortcuts.swipe.detail")
                shortcut(.rotate, 1, "onboarding.shortcuts.rotate.title", "onboarding.shortcuts.rotate.detail")
                shortcut(.shake, 2, "onboarding.shortcuts.shake.title", "onboarding.shortcuts.shake.detail")
                shortcut(.hold, 3, "onboarding.shortcuts.hold.title", "onboarding.shortcuts.hold.detail")
                shortcut(.resize, 4, "onboarding.shortcuts.resize.title", "onboarding.shortcuts.resize.detail")
            }
        } footer: {
            OnboardingPrimaryButton(title: String(localized: "onboarding.continue"), action: onNext)
        }
    }

    private func shortcut(_ demo: ShortcutDemoIcon.Demo, _ order: Int,
                          _ title: String.LocalizationValue, _ detail: String.LocalizationValue) -> some View {
        OnboardingInfoRow(title: String(localized: title), detail: String(localized: detail)) {
            ShortcutDemoIcon(demo: demo, delay: 0.6 + Double(order) * 0.9)
        }
        .onboardingEntrance(4 + order)
    }
}
