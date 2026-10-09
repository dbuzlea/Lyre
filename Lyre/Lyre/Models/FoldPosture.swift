//
//  FoldPosture.swift
//  Lyre
//

import SwiftUI

// MARK: - Fold Posture
//
// How a foldable phone is being held, as far as the Spool player cares:
//
// • closed — folded shut, one portrait screen. The only posture any shipping iPhone has,
//            and what every device reports today.
// • open   — opened like a book. Spool shows the tape shelf beside the deck; a tape picked
//            there is loaded, and closing the phone plays it.
// • tent   — propped up in landscape on its fold. Spool lays the deck out sideways with
//            the transport keys along the bottom edge.
//
// `FoldPostureMonitor` is the single place the hinge is read. On iOS 27.1 and later
// `HingeObserver` feeds it from SwiftUI's `onHingeChange`; every iPhone without a hinge
// reports no hinge at all, which reads as `.closed`, so nothing changes there. A debug
// build can still override the posture from the Spool options menu.
//
// The hinge reports closed, partially open, or fully open — not how the phone is
// standing — so it cannot tell a phone opened like a book from one propped up as a tent.
// Both read as `.open`; `.tent` is reachable only through the debug override until it can
// be told apart on hardware.

enum FoldPosture: String, CaseIterable, Identifiable {
    case closed
    case open
    case tent

    var id: String { rawValue }

    var debugName: String {
        switch self {
        case .closed: return "Closed"
        case .open:   return "Open"
        case .tent:   return "Tent"
        }
    }
}

/// What the hinge reported, reduced to what posture needs. Kept apart from the SDK's
/// `DeviceHinge` so the mapping can be tested: that type has no public initializer.
enum HingeReading: Equatable {
    /// No hinge in this hierarchy — every iPhone that does not fold.
    case absent
    case closed
    /// Partially or fully open.
    case open
}

extension FoldPosture {
    init(_ reading: HingeReading) {
        switch reading {
        case .absent, .closed: self = .closed
        case .open:            self = .open
        }
    }
}

@Observable
final class FoldPostureMonitor {
    /// What the hardware reports. `.closed` on any iPhone without a hinge.
    private(set) var systemPosture: FoldPosture = .closed

    /// Set from the debug menu to stand in for the hardware. Not persisted, so a release
    /// build can never get stuck in a posture the device isn't in.
    var debugOverride: FoldPosture?

    init() {
        #if DEBUG
        // `-SpoolFoldPosture open` (or tent) at launch, for screenshots and UI tests.
        if let raw = UserDefaults.standard.string(forKey: "SpoolFoldPosture") {
            debugOverride = FoldPosture(rawValue: raw)
        }
        #endif
    }

    var posture: FoldPosture { debugOverride ?? systemPosture }

    func update(_ reading: HingeReading) {
        let posture = FoldPosture(reading)
        // Angle updates arrive continuously while the hinge moves; only a change of
        // posture should invalidate the views that read it.
        if posture != systemPosture { systemPosture = posture }
    }
}

// MARK: - Hinge Observer

/// Feeds the hinge into a `FoldPostureMonitor`. Attach once, near the root.
///
/// Status only, never the angle: posture chooses a layout, and the angle is for effects.
/// Layout itself still comes from the size the views are given, which is what keeps every
/// other iPhone working the same way.
struct HingeObserver: ViewModifier {
    let monitor: FoldPostureMonitor

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, context in
                monitor.update(HingeReading(context.hinge))
            }
        } else {
            content
        }
    }
}

@available(iOS 27.1, *)
extension HingeReading {
    init(_ hinge: DeviceHinge?) {
        guard let hinge else { self = .absent; return }
        self = hinge.status == .closed ? .closed : .open
    }
}
