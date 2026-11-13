//
//  GestureIntentTouch.swift
//  Lyre
//

import SwiftUI
import UIKit

// MARK: - A Touch, Read for What It Means
//
// One UIKit recognizer for a thing that can be tapped, held, lifted and carried among
// things that scroll (Liquid's bubbles). It hands each sample of the finger, and the
// passing time, to GestureIntent and acts on what it names: a swipe is let go to the
// scroll; a pause lifts the thing; lifted and moved, it's carried; lifted and rested on,
// it's held; quick and still, a tap. It runs alongside the scroll until it's sure.

@available(iOS 18.0, *)
final class GestureIntentRecognizer: UIGestureRecognizer {
    enum Event { case none, lifted, moved, held, released, tapped }

    var intent = GestureIntent()
    /// Whether the field under it is moving: a touch landing then only stops it.
    var isFieldMoving: () -> Bool = { false }
    /// What last happened, for the action handler.
    private(set) var event: Event = .none
    private(set) var isHolding = false
    private var link: CADisplayLink?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touches.count == 1, numberOfTouches <= 1, let touch = touches.first, !isFieldMoving() else {
            state = .failed
            return
        }
        intent.began(at: touch.location(in: nil), time: touch.timestamp)
        GestureHUD.shared.show(intent)
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        let before = intent.intent
        intent.moved(to: touch.location(in: nil), time: touch.timestamp)
        react(from: before, moving: true)
    }

    @objc private func step() {
        let before = intent.intent
        intent.tick(at: CACurrentMediaTime())
        react(from: before, moving: false)
        // Named for good: no more need of the clock.
        switch intent.intent {
        case .undecided, .lift: break
        default: stopClock()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        stopClock()
        let time = touches.first?.timestamp ?? CACurrentMediaTime()
        let named = intent.ended(at: time)
        GestureHUD.shared.show(intent)
        if named == .tap {
            self.event = .tapped
            state = .ended
        } else if state == .possible {
            state = .failed
        } else {
            self.event = .released
            state = .ended
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        stopClock()
        if state == .possible {
            state = .failed
        } else {
            self.event = .released
            state = .cancelled
        }
    }

    override func reset() {
        super.reset()
        stopClock()
        event = .none
        isHolding = false
        intent.began(at: .zero, time: 0)
    }

    private func react(from before: GestureIntent.Intent, moving: Bool) {
        let now = intent.intent
        if now != before || moving { GestureHUD.shared.show(intent) }
        switch now {
        case .scroll:
            stopClock()
            if state == .possible { state = .failed }
        case .lift, .pull:
            if state == .possible {
                event = .lifted
                state = .began
            } else if moving, now == .pull {
                event = .moved
                state = .changed
            }
        case .carry:
            // Always after .lift, so already begun.
            event = .moved
            state = .changed
        case .spread:
            if state == .possible { state = .began }
            if !isHolding {
                isHolding = true
                event = .held
                state = .changed
            } else if moving {
                event = .moved
                state = .changed
            }
        default:
            break
        }
    }

    private func stopClock() {
        link?.invalidate()
        link = nil
    }
}

/// GestureIntentRecognizer for SwiftUI, reporting in screen points: lifted (where the
/// thing's centre is, and the finger), moved, held, released (where a flick would carry
/// it, and how fast), tapped.
@available(iOS 18.0, *)
struct GestureIntentTouch: UIGestureRecognizerRepresentable {
    enum Phase { case lifted, moved, held, released, tapped }

    let diameter: CGFloat
    let pullDirection: CGVector?
    let canCarry: Bool
    let isFieldMoving: () -> Bool
    /// What happened: the thing's centre (where it started, for lifted; where the finger
    /// has it since), the finger, and for released, the speed.
    let onPhase: (Phase, _ center: CGPoint, _ origin: CGPoint, _ finger: CGPoint, _ velocity: CGPoint) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// Where the thing's centre was as the touch began.
        var origin: CGPoint = .zero

        // Alongside the scroll, until it's sure; once it's lifted the thing, no pan (the
        // scroll, a row's swipe) takes the touch from it. Holds (a menu) still may.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            recognizer.state == .possible || !(other is UIPanGestureRecognizer)
        }
    }

    func makeUIGestureRecognizer(context: Context) -> GestureIntentRecognizer {
        let recognizer = GestureIntentRecognizer()
        recognizer.delegate = context.coordinator
        configure(recognizer)
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: GestureIntentRecognizer, context: Context) {
        configure(recognizer)
    }

    private func configure(_ recognizer: GestureIntentRecognizer) {
        recognizer.intent.pullDirection = pullDirection
        recognizer.intent.canCarry = canCarry
        recognizer.isFieldMoving = isFieldMoving
    }

    func handleUIGestureRecognizerAction(_ recognizer: GestureIntentRecognizer, context: Context) {
        let finger = context.converter.location(in: .global)
        let intent = recognizer.intent
        // The finger's way from where it touched, carried over to the thing's centre.
        let carried = CGPoint(x: context.coordinator.origin.x + intent.location.x - intent.start.x,
                              y: context.coordinator.origin.y + intent.location.y - intent.start.y)
        switch recognizer.event {
        case .lifted:
            // Where the thing's centre was as the touch began: where it is under the finger,
            // less how far the finger's come.
            let inThing = context.converter.location(in: .local)
            let now = CGPoint(x: finger.x - inThing.x + diameter / 2, y: finger.y - inThing.y + diameter / 2)
            context.coordinator.origin = CGPoint(x: now.x - (intent.location.x - intent.start.x),
                                                 y: now.y - (intent.location.y - intent.start.y))
            let origin = context.coordinator.origin
            onPhase(.lifted, origin, origin, finger, .zero)
            if intent.intent == .pull || intent.intent == .carry {
                onPhase(.moved, CGPoint(x: origin.x + intent.location.x - intent.start.x,
                                        y: origin.y + intent.location.y - intent.start.y),
                        origin, finger, .zero)
            }
        case .moved:
            onPhase(.moved, carried, context.coordinator.origin, finger, .zero)
        case .held:
            if context.coordinator.origin == .zero {
                let inThing = context.converter.location(in: .local)
                context.coordinator.origin = CGPoint(x: finger.x - inThing.x + diameter / 2,
                                                     y: finger.y - inThing.y + diameter / 2)
            }
            onPhase(.held, context.coordinator.origin, context.coordinator.origin, finger, .zero)
        case .released:
            let v = recognizer.state == .ended ? intent.velocity : .zero
            // Where a flick would carry it: a quarter of a second on at its speed.
            onPhase(.released, CGPoint(x: carried.x + v.dx * 0.25, y: carried.y + v.dy * 0.25),
                    context.coordinator.origin, finger, CGPoint(x: v.dx, y: v.dy))
            context.coordinator.origin = .zero
        case .tapped:
            let inThing = context.converter.location(in: .local)
            let center = CGPoint(x: finger.x - inThing.x + diameter / 2, y: finger.y - inThing.y + diameter / 2)
            onPhase(.tapped, center, center, finger, .zero)
            context.coordinator.origin = .zero
        case .none:
            break
        }
    }
}

// MARK: - Tuning Overlay

/// `-LyreGestureHUD YES` (debug builds): the finger's smoothed speed and the rule that
/// named the touch, live, at the top of the screen, for tuning GestureIntent on a phone.
@Observable
@MainActor
final class GestureHUD {
    static let shared = GestureHUD()
    let isOn: Bool = {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "LyreGestureHUD")
        #else
        false
        #endif
    }()
    private(set) var speed: CGFloat = 0
    private(set) var rule = "—"
    private(set) var moved: CGFloat = 0

    func show(_ intent: GestureIntent) {
        guard isOn else { return }
        speed = intent.speed
        rule = intent.intent.rule
        moved = intent.moved
    }
}

struct GestureHUDView: View {
    @State private var hud = GestureHUD.shared

    var body: some View {
        if hud.isOn {
            HStack(spacing: 10) {
                Text("\(Int(hud.speed)) pt/s").monospacedDigit()
                Text("\(Int(hud.moved)) pt").monospacedDigit()
                Text(hud.rule).bold()
            }
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.75), in: Capsule())
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
