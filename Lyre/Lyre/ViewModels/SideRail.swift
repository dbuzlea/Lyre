//
//  SideRail.swift
//  Lyre
//

import SwiftUI

// MARK: - Side Rail
//
// An iPhone Duo keeps its status bar in a column down the right edge, closed, or held
// open as a book, where other iPhones keep it across the top. Every player's header
// buttons (back, close, ★, AirPlay, the player switch, settings) leave the top there and
// stand in that column instead, one under the other below the status bar: the top of a
// tall, narrow phone held in one hand is the hardest place to reach, and the column was
// otherwise empty. Held as a book, the left page's buttons stand down the left edge,
// where the other thumb is.
//
// Everywhere else (any other iPhone, a Duo opened upright with its status bar on top)
// nothing changes: `SideRail.isOn` is false and the buttons stay in their rows.

enum SideRail {
    /// How wide the status column down the right edge is; 0 on a phone without one.
    static func column(_ safeArea: EdgeInsets) -> CGFloat {
        safeArea.trailing >= 40 ? safeArea.trailing : 0
    }

    /// Whether the header buttons stand down the side.
    static func isOn(_ safeArea: EdgeInsets) -> Bool { column(safeArea) > 0 }

    /// Clear of the status bar at the column's top, a Live Activity's pill included.
    static let statusReserve: CGFloat = 262
    /// Where a rail that runs the column's height (the Spool's keys) starts: under the
    /// clock and battery, if not a Live Activity's pill.
    static let stripTop: CGFloat = 150
    /// Down the left edge (held as a book): where the row used to be, and a little lower.
    static let leadingTop: CGFloat = 96
    /// How wide the left edge's rail is.
    static let leadingWidth: CGFloat = 72
    /// How tall one button in a rail is, with the gap below it.
    static let step: CGFloat = 58

    /// How many buttons fit down the column of a window `height` tall, under the status
    /// bar and above the home indicator (`bottom`): past that, the rest go in a "…" menu.
    static func capacity(height: CGFloat, bottom: CGFloat) -> Int {
        max(1, Int((height - statusReserve - bottom - 8 + 14) / step))
    }
}

extension EnvironmentValues {
    /// How much of the column's top another rail already takes (held as a book, Now
    /// Playing's buttons over the right-hand page's): a rail here starts below it.
    @Entry var sideRailStart: CGFloat = 0
    /// The column already has the player switch and Settings (Now Playing's, held as a
    /// book), so a page beside it doesn't stand its own there too.
    @Entry var sideRailHasPlayerButtons = false
}

/// Header buttons stood one under the other in the status column down the right edge
/// (or down the left edge, for a book's left page), drawn only where there's a column.
/// Placed over a view that runs to that edge of the window.
struct SideRailButtons<Content: View>: View {
    var edge: HorizontalEdge = .trailing
    var spacing: CGFloat = 14
    @ViewBuilder let content: () -> Content

    @Environment(\.windowSafeArea) private var safeArea
    @Environment(\.sideRailStart) private var start

    var body: some View {
        if SideRail.isOn(safeArea) {
            VStack(spacing: spacing) { content() }
                .frame(width: edge == .trailing ? SideRail.column(safeArea) : SideRail.leadingWidth)
                .padding(.top, edge == .trailing ? SideRail.statusReserve + start : SideRail.leadingTop)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: edge == .trailing ? .topTrailing : .topLeading)
                // Into the column, which a view laid out in the safe area (a sheet) keeps clear of.
                .ignoresSafeArea()
                .transition(.opacity)
        }
    }
}

/// A sheet's Done, for the side rail: the same word, on a capsule that fits the column.
struct SideRailDone: View {
    let identifier: String
    var font: Font = .system(size: 15, weight: .semibold)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(String(localized: "spool.settings.done"))
                .font(font)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 10)
                .frame(minWidth: 44, minHeight: 44)
                .background(.primary.opacity(0.08), in: Capsule())
        }
        .buttonStyle(LyrePressStyle())
        .accessibilityIdentifier(identifier)
    }
}
