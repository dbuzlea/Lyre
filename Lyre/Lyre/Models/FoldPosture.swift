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

    /// How far open the hinge is, in degrees: 0 shut, 180 flat. Nil without a hinge.
    /// For effects that follow the hinge (the Disc's lid, Liquid's lava), never layout.
    private(set) var systemAngle: Double?
    /// Stands in for the hinge's angle (debug builds).
    var debugAngle: Double?

    init() {
        #if DEBUG
        // `-SpoolFoldPosture open` (or tent) at launch, for screenshots and UI tests;
        // `-LyreHingeAngle 100` for the angle.
        if let raw = UserDefaults.standard.string(forKey: "SpoolFoldPosture") {
            debugOverride = FoldPosture(rawValue: raw)
        }
        if UserDefaults.standard.object(forKey: "LyreHingeAngle") != nil {
            debugAngle = UserDefaults.standard.double(forKey: "LyreHingeAngle")
        }
        #endif
    }

    var posture: FoldPosture { debugOverride ?? systemPosture }

    /// The hinge's angle, when there's a hinge (or one's stood in for): what's open
    /// with no angle reported counts as flat.
    var angle: Double? {
        if let debugAngle { return debugAngle }
        if let systemAngle { return systemAngle }
        return posture == .open ? 180 : nil
    }

    /// Partly open, between shut and flat: propped up, as a laptop or on a table.
    var isPartlyOpen: Bool {
        guard posture == .open, let angle else { return false }
        return angle < 160
    }

    func update(_ reading: HingeReading, angle: Double? = nil) {
        let posture = FoldPosture(reading)
        // Angle updates arrive continuously while the hinge moves; only a change of
        // posture should invalidate the views that read it. The angle is kept apart,
        // in whole degrees, so only what follows it redraws.
        if posture != systemPosture { systemPosture = posture }
        let rounded = angle.map { $0.rounded() }
        if rounded != systemAngle { systemAngle = rounded }
    }
}

// MARK: - Hinge Observer

/// Feeds the hinge into a `FoldPostureMonitor`. Attach once, near the root.
///
/// Status chooses a layout; the angle (in whole degrees) is only for effects that follow
// the hinge, read by the few views that draw them.
/// Layout itself still comes from the size the views are given, which is what keeps every
/// other iPhone working the same way.
struct HingeObserver: ViewModifier {
    let monitor: FoldPostureMonitor

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, context in
                monitor.update(HingeReading(context.hinge), angle: context.hinge?.angle.degrees)
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
