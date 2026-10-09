//
//  ShelfIndexStrip.swift
//  Lyre
//

import SwiftUI

// MARK: - Shelf Index Strip
//
// The A–Z index beside a shelf of records or tapes, for getting to a part of a large
// library without going through every item on the way: along the front of the
// Gramophone's drawer (RecordIndexStrip), and down the side of the Spool's rack.
//
// Running a finger along it brings the first item filed under the letter beneath the
// finger to the front, with a tick as each letter is reached; a disc beside the finger
// shows the letter while it's down. A letter with nothing under it goes to the next
// letter that has something. The letter of the item at the front stands out on a tab,
// so the strip also says where in the shelf it is.
//
// Items file by `AppHelpers.firstLetter`, as the shelves are sorted ("The Weeknd" under
// W), and anything not starting with a letter under "#", which leads the strip.

struct ShelfIndexStrip: View {
    /// The items' names, in shelf order.
    let titles: [String]
    /// The item at the front.
    let currentIndex: Int?
    var axis: Axis = .horizontal
    let style: Style
    /// Whether the strip ticks as each letter is reached. Off where the shelf ticks as
    /// each item reaches the front, so a jump isn't felt twice.
    var ticks = true
    var accessibilityID = "shelf.index"
    /// Brings the item at this index to the front.
    let onJump: (Int) -> Void

    /// How the strip is drawn, in each player's materials.
    struct Style {
        var design: Font.Design
        var ink: Color
        var rail: Color
        var railEdge: Color
        /// The current letter's tab, and the disc beside a finger: fill and lettering.
        var tab: (String) -> (fill: AnyShapeStyle, ink: Color)
    }

    /// Where each letter's items start. Worked out when the items change rather than on
    /// every redraw, which a finger on the strip makes many of.
    @State private var starts: [String: Int] = [:]
    /// The letter under a finger on the strip, and where along the strip it is.
    @State private var touched: (letter: String, at: CGFloat)?

    static let letters = ["#"] + (UnicodeScalar("A").value...UnicodeScalar("Z").value)
        .compactMap { UnicodeScalar($0).map { String(Character($0)) } }

    private var frontLetter: String? {
        guard let currentIndex, titles.indices.contains(currentIndex) else {
            return titles.first.map(AppHelpers.firstLetter(of:))
        }
        return AppHelpers.firstLetter(of: titles[currentIndex])
    }

    private var isVertical: Bool { axis == .vertical }

    var body: some View {
        GeometryReader { geometry in
            let length = isVertical ? geometry.size.height : geometry.size.width
            let thickness = isVertical ? geometry.size.width : geometry.size.height
            let step = length / CGFloat(Self.letters.count)
            let layout = isVertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
            layout {
                ForEach(Self.letters, id: \.self) { letter in
                    letterMark(letter, step: step, thickness: thickness)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        point(at: isVertical ? value.location.y : value.location.x, step: step)
                    }
                    .onEnded { _ in withAnimation(.easeOut(duration: 0.15)) { touched = nil } }
            )
            .overlay(alignment: .topLeading) {
                if let touched {
                    let at = min(max(touched.at, 26), length - 26)
                    bubble(touched.letter)
                        .position(x: isVertical ? -34 : at, y: isVertical ? at : -34)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
        }
        // Clear of the rail's rounded ends.
        .padding(isVertical ? .vertical : .horizontal, 10)
        .background(
            Capsule()
                .fill(style.rail)
                .overlay(Capsule().strokeBorder(style.railEdge, lineWidth: 1))
        )
        .task(id: "\(titles.count):\(titles.first ?? ""):\(titles.last ?? "")") {
            var found: [String: Int] = [:]
            for (index, title) in titles.enumerated() {
                let letter = AppHelpers.firstLetter(of: title)
                if found[letter] == nil { found[letter] = index }
            }
            starts = found
        }
        .accessibilityElement()
        .accessibilityLabel(String(localized: "gramophone.index"))
        .accessibilityValue(frontLetter ?? "")
        .accessibilityAdjustableAction { direction in
            let filled = Self.letters.filter { starts[$0] != nil }
            guard let current = frontLetter, let at = filled.firstIndex(of: current) else { return }
            let next = direction == .increment ? at + 1 : at - 1
            if filled.indices.contains(next) { jump(to: filled[next]) }
        }
        .accessibilityIdentifier(accessibilityID)
    }

    private func letterMark(_ letter: String, step: CGFloat, thickness: CGFloat) -> some View {
        let isFront = letter == frontLetter
        let isFilled = starts[letter] != nil
        let tab = style.tab(letter)
        let size = min(12, (isVertical ? min(step, thickness) : step) * 0.85)
        return Text(letter)
            .font(.system(size: size, weight: isFront ? .heavy : .semibold, design: style.design))
            .foregroundStyle(isFront ? tab.ink : style.ink.opacity(isFilled ? 0.85 : 0.28))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .frame(width: isVertical ? thickness : step, height: isVertical ? step : thickness)
            .background {
                if isFront {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(tab.fill)
                        .padding(isVertical ? .horizontal : .vertical, thickness * 0.14)
                        .padding(isVertical ? .vertical : .horizontal, -1)
                        .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
                }
            }
            .animation(.easeInOut(duration: 0.12), value: isFront)
    }

    /// The letter, large, on a disc beside the finger.
    private func bubble(_ letter: String) -> some View {
        let tab = style.tab(letter)
        return Text(letter)
            .font(.system(size: 26, weight: .bold, design: style.design))
            .foregroundStyle(tab.ink)
            .frame(width: 50, height: 50)
            .background(Circle().fill(tab.fill))
            .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
    }

    // MARK: - Jumping

    private func point(at position: CGFloat, step: CGFloat) {
        let slot = min(max(Int(position / max(step, 1)), 0), Self.letters.count - 1)
        let letter = Self.letters[slot]
        let isNew = touched?.letter != letter
        withAnimation(touched == nil ? .spring(response: 0.25, dampingFraction: 0.7) : nil) {
            touched = (letter, position)
        }
        guard isNew else { return }
        if ticks { UISelectionFeedbackGenerator().selectionChanged() }
        jump(to: letter)
    }

    /// Brings the first item filed under `letter` to the front, or under the next letter
    /// that has any; past the last, the last letter that has any.
    private func jump(to letter: String) {
        guard let at = Self.letters.firstIndex(of: letter) else { return }
        let target = Self.letters[at...].lazy.compactMap { starts[$0] }.first
            ?? Self.letters[..<at].reversed().lazy.compactMap { starts[$0] }.first
        guard let target, titles.indices.contains(target), target != currentIndex else { return }
        onJump(target)
    }
}

extension ShelfIndexStrip.Style {
    /// Brass and cream serif, for the Gramophone's drawer.
    static func gramophone(_ theme: GramophoneTheme) -> Self {
        Self(design: .serif, ink: theme.ink, rail: .black.opacity(0.28), railEdge: theme.metal.opacity(0.35),
             tab: { _ in (AnyShapeStyle(theme.metalGradient), theme.plateInk) })
    }

    /// The Spool's filing tabs: each letter in its own colour, as on the tapes.
    static func spool(_ theme: SpoolTheme) -> Self {
        Self(design: .rounded, ink: theme.ink, rail: .black.opacity(0.18), railEdge: theme.ink.opacity(0.2),
             tab: { letter in
                 let colour = SectionTab.colour(for: letter)
                 return (AnyShapeStyle(colour.fill), colour.ink)
             })
    }
}
