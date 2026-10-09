//
//  CassetteDoor.swift
//  Lyre
//

import SwiftUI

// MARK: - Cassette Door
//
// The compartment the tape sits in: a dark recess behind a door. Each Spool design has
// its own door:
//
// • Original — a solid door in the body colour with a small window over the reels and an
//   arrow showing which way the tape runs. It is hinged down its left edge, so opening
//   swings its right side out towards the viewer, and the tape slides out of its seat
//   towards the opening.
// • Slim — a solid front panel with a pill-shaped window over a tape lying flat. It is
//   hinged along its bottom edge, so opening tips its top out, and the tape lifts up.
//
// The door only draws state; SpoolPlayerView owns the sequence (open → browse → insert →
// close) and decides when each part happens.

struct CassetteDoor<Tape: View>: View {
    enum Hinge {
        case leading
        case bottom
    }

    enum Window {
        /// The whole door is glass.
        case glass
        /// A solid door with a rounded window over `rect`, in unit coordinates.
        case inset(CGRect)
        /// A solid door with a pill-shaped window over `rect`.
        case pill(CGRect)
    }

    let isOpen: Bool
    /// False while the old tape is ejected and the bay stands empty.
    let showsTape: Bool
    var hinge: Hinge = .leading
    var window: Window = .glass
    /// Printing on the door, which swings with it.
    var markings: AnyView?
    /// Reports where a seated tape sits, in SpoolPlayerView's coordinate space, so a tape
    /// flying in knows where to land.
    var onSeatFrame: (CGRect) -> Void = { _ in }
    @ViewBuilder let tape: Tape

    @Environment(\.spoolTheme) private var theme

    static var cornerRadius: CGFloat { 22 }
    /// Gap between the tape and the compartment walls.
    static var inset: CGFloat { 14 }
    /// How far the door swings on its hinge. The sign brings the free edge towards the
    /// viewer rather than into the deck.
    static var openAngle: Double { -42 }

    var body: some View {
        ZStack {
            // Recess
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .fill(theme.bay)
                .overlay(
                    RoundedRectangle(cornerRadius: Self.cornerRadius)
                        .strokeBorder(.black.opacity(0.35), lineWidth: 3)
                        .blur(radius: 2)
                        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
                )

            Color.clear
                .padding(Self.inset)
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(SpoolPlayerView.coordinateSpace))
                } action: { onSeatFrame($0) }

            tape
                .padding(Self.inset)
                .offset(x: showsTape || hinge == .bottom ? 0 : 28,
                        y: showsTape || hinge == .leading ? 0 : -28)
                .opacity(showsTape ? 1 : 0)

            door
                .rotation3DEffect(.degrees(isOpen ? Self.openAngle : 0),
                                  axis: hinge == .leading ? (x: 0, y: 1, z: 0) : (x: 1, y: 0, z: 0),
                                  anchor: hinge == .leading ? .leading : .bottom,
                                  perspective: 0.45)
                .shadow(color: .black.opacity(isOpen ? 0.35 : 0), radius: 10,
                        x: hinge == .leading ? 8 : 0, y: hinge == .leading ? 0 : 8)
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
    }

    @ViewBuilder
    private var door: some View {
        switch window {
        case .glass:
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .fill(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.03)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    RoundedRectangle(cornerRadius: Self.cornerRadius)
                        .strokeBorder(SpoolPalette.doorRim, lineWidth: 3)
                )
                .overlay(alignment: latchAlignment) { latch }
        case .inset(let rect):
            solidDoor(window: rect, isPill: false)
        case .pill(let rect):
            solidDoor(window: rect, isPill: true)
        }
    }

    /// A door in the body colour with a window cut through it.
    private func solidDoor(window rect: CGRect, isPill: Bool) -> some View {
        let panel = DoorPanel(cornerRadius: Self.cornerRadius, window: rect, isPill: isPill)
        return ZStack {
            panel
                .fill(theme.bodyGradient, style: FillStyle(eoFill: true))
                // A pressed edge: light along the top, shade along the bottom.
                .overlay(
                    panel.stroke(LinearGradient(colors: [.white.opacity(0.35), .black.opacity(0.25)],
                                                startPoint: .top, endPoint: .bottom),
                                 lineWidth: 1.5)
                )
            // Smoked glass in the window, placed as its own view over the hole. (A shape
            // whose path covers only part of its frame drew misplaced on device.)
            GeometryReader { geometry in
                let frame = panel.windowFrame(in: CGRect(origin: .zero, size: geometry.size))
                RoundedRectangle(cornerRadius: panel.windowRadius(for: frame))
                    .fill(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04), .white.opacity(0.1)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        RoundedRectangle(cornerRadius: panel.windowRadius(for: frame))
                            .stroke(.black.opacity(0.45), lineWidth: 2)
                    )
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
            }
            markings
        }
        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
    }

    private var latchAlignment: Alignment { hinge == .leading ? .trailing : .top }

    /// The catch on the edge that opens.
    private var latch: some View {
        Capsule()
            .fill(SpoolPalette.doorRim)
            .frame(width: hinge == .leading ? 6 : 56, height: hinge == .leading ? 56 : 6)
            .padding(hinge == .leading ? .trailing : .top, 6)
    }
}

/// A door panel with a window cut through it. Filled even-odd, the window is a hole.
private struct DoorPanel: Shape {
    let cornerRadius: CGFloat
    /// The window, in unit coordinates of the panel.
    let window: CGRect
    let isPill: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: cornerRadius)
        path.addPath(windowPath(in: rect))
        return path
    }

    func windowFrame(in rect: CGRect) -> CGRect {
        CGRect(x: rect.minX + window.minX * rect.width,
               y: rect.minY + window.minY * rect.height,
               width: window.width * rect.width,
               height: window.height * rect.height)
    }

    func windowRadius(for frame: CGRect) -> CGFloat {
        isPill ? min(frame.width, frame.height) / 2 : min(frame.width, frame.height) * 0.12
    }

    private func windowPath(in rect: CGRect) -> Path {
        let frame = windowFrame(in: rect)
        return Path(roundedRect: frame, cornerRadius: windowRadius(for: frame))
    }
}
