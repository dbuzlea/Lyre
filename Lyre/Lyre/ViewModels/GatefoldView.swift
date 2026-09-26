//
//  GatefoldView.swift
//  Lyre
//

import SwiftUI
import UIKit

// MARK: - Gatefold
//
// The interior of an opened album sleeve, used by ArtworkCarouselView's fold interaction.
// Opening an album swings the cover left through 180° on its spine, producing a 2:1 spread
// of two square panels:
//
// • Left  — the record: a spinning disc with the artwork as its centre label, plus credits
//           and the Play / Shuffle actions.
// • Right — the liner: the tracklist, split into vinyl sides by runtime.
//
// Everything here is a pure function of the fold progress `p` supplied by the carousel, so
// the fold stays reversible mid-flight. See `AnimatableFold` for why that matters.
//
// The printed colours come from the artwork by way of `SleeveTheme` in the environment, so
// each album's interior is stocked in paper that suits its cover.

// MARK: - Palette

/// The default printed palette: warm card stock rather than the app's black chrome, so the
/// interior reads as paper the moment it is uncovered. Also the fallback for artwork we
/// cannot sample a colour from.
enum GatefoldPalette {
    static let card = Color(red: 0.914, green: 0.882, blue: 0.824)   // #E9E1D2
    static let ink = Color(red: 0.090, green: 0.075, blue: 0.059)    // #17130F
    static let disc = Color(red: 0.043, green: 0.043, blue: 0.047)   // #0B0B0C
    static let accent = Color(red: 0.780, green: 0.357, blue: 0.180) // #C75B2E
    static let kraft = Color(red: 0.812, green: 0.765, blue: 0.659)  // #CFC3A8
}

// MARK: - Sleeve Theme

/// The ink and paper an individual sleeve is printed in.
struct SleeveTheme: Equatable {
    /// The panel's base. On a photographic interior this is also the scrim colour laid over
    /// the artwork, which is why it goes dark there.
    var card: Color
    var ink: Color
    var accent: Color
    var disc: Color
    /// Light paper, whatever the interior is made of. The spindle hole and a white-label
    /// pressing need to stay pale even when `card` has gone dark.
    var stock: Color

    static let `default` = SleeveTheme(
        card: GatefoldPalette.card,
        ink: GatefoldPalette.ink,
        accent: GatefoldPalette.accent,
        disc: GatefoldPalette.disc,
        stock: GatefoldPalette.card
    )

    /// Splits a colour into hue and saturation, or nil if it has neither.
    private static func components(of source: Color?) -> (hue: CGFloat, saturation: CGFloat)? {
        guard let source else { return nil }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard UIColor(source).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return nil
        }
        return (hue, saturation)
    }

    /// Warm printed stock, tinted by the cover. Used when there is no artwork to print.
    ///
    /// Only the *hue* is taken from the cover. Brightness and saturation are clamped into
    /// fixed bands — paper stays light, ink stays dark — and that clamping is what keeps the
    /// liner legible whatever the cover looks like. Sampling the colour directly would print
    /// a black metal sleeve as black ink on black paper.
    static func paper(_ source: Color?) -> SleeveTheme {
        guard let (hue, saturation) = components(of: source) else { return .default }

        // A near-greyscale cover has no hue worth borrowing, so the accent keeps its default
        // terracotta and the current track still stands out against grey paper.
        let isNeutral = saturation < 0.12
        let card = Color(hue: hue, saturation: min(saturation, 0.16), brightness: 0.90)

        return SleeveTheme(
            card: card,
            ink: Color(hue: hue, saturation: min(saturation, 0.35), brightness: 0.10),
            accent: isNeutral
                ? GatefoldPalette.accent
                : Color(hue: hue, saturation: max(saturation, 0.55), brightness: 0.55),
            disc: Color(hue: hue, saturation: min(saturation, 0.20), brightness: 0.055),
            stock: card
        )
    }

    /// For interiors where the artwork itself is the surface.
    ///
    /// Type goes light because it prints over a photograph, and `card` becomes the dark
    /// scrim that guarantees it stays readable. The scrim opacities in `spreadBackdrop` are
    /// chosen against this brightness — at 0.10 an opacity of 0.92 keeps white type above
    /// 4.5:1 even where the artwork underneath is pure white.
    static func photographic(_ source: Color?) -> SleeveTheme {
        guard let (hue, saturation) = components(of: source) else {
            return SleeveTheme(
                card: Color(white: 0.08),
                ink: Color(white: 0.97),
                accent: GatefoldPalette.accent,
                disc: GatefoldPalette.disc,
                stock: Color(white: 0.90)
            )
        }

        let isNeutral = saturation < 0.12

        return SleeveTheme(
            card: Color(hue: hue, saturation: min(saturation, 0.30), brightness: 0.10),
            ink: Color(hue: hue, saturation: min(saturation, 0.08), brightness: 0.97),
            // Brighter than the paper accent: it has to carry on a dark ground.
            accent: isNeutral
                ? Color(hue: 0.06, saturation: 0.62, brightness: 0.82)
                : Color(hue: hue, saturation: max(saturation, 0.50), brightness: 0.82),
            disc: Color(hue: hue, saturation: min(saturation, 0.20), brightness: 0.045),
            stock: Color(hue: hue, saturation: min(saturation, 0.10), brightness: 0.90)
        )
    }
}

extension EnvironmentValues {
    @Entry var sleeveTheme: SleeveTheme = .default
}

/// The average colour of an image, by way of a one-pixel downsample.
///
/// Used for local-library artwork, which carries no palette of its own. Apple Music artwork
/// has `Artwork.backgroundColor` already extracted and should use that instead.
func sleeveColor(from image: UIImage) -> Color? {
    guard let cgImage = image.cgImage else { return nil }

    var pixel: [UInt8] = [0, 0, 0, 0]
    guard let context = CGContext(
        data: &pixel,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    guard pixel[3] > 0 else { return nil }

    return Color(
        red: Double(pixel[0]) / 255,
        green: Double(pixel[1]) / 255,
        blue: Double(pixel[2]) / 255
    )
}

// MARK: - Animatable Fold

/// Re-evaluates its content on every frame of an animation on `progress`.
///
/// Without this, SwiftUI would interpolate each derived modifier between its start and end
/// value instead of tracing the real curve. Non-linear derivations break badly under that:
/// the gutter shadow's `sin(πp)` is 0 at both ends, so it would never appear at all. Making
/// `progress` the `animatableData` forces `body` to run per frame, and every derived value
/// follows its actual shape.
struct AnimatableFold<Content: View>: View, Animatable {
    var progress: CGFloat
    @ViewBuilder var content: (CGFloat) -> Content

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        content(progress)
    }
}

// MARK: - Vinyl Sides

/// Splits an album's tracks into vinyl sides by **runtime**, not track count.
///
/// A side holds at most 22 minutes, which is roughly where a 12" LP at 33⅓ rpm starts losing
/// bass to reduce groove width. Records are pressed in pairs of sides, so the count goes
/// 1 → 2 → 4 → 6 rather than incrementing one at a time.
///
/// Cuts land on track boundaries chosen to leave the sides as close in length as possible.
/// Returns an empty array for an empty track list: no tracks, no sides.
func vinylSides(_ tracks: [AppTrack]) -> [[AppTrack]] {
    guard !tracks.isEmpty else { return [] }

    let maxSideLength: TimeInterval = 22 * 60
    let total = tracks.reduce(0) { $0 + $1.duration }

    // One side up to 22:00, then even side counts: 2 up to 44:00, 4 up to 88:00, and so on.
    let sideCount: Int
    if total <= maxSideLength {
        sideCount = 1
    } else {
        sideCount = 2 * Int((total / (maxSideLength * 2)).rounded(.up))
    }

    // Never ask for more sides than there are tracks to fill them.
    let count = min(max(1, sideCount), tracks.count)
    guard count > 1 else { return [tracks] }

    // Running total at each track boundary, so cut points can be chosen by time.
    var cumulative: [TimeInterval] = []
    var running: TimeInterval = 0
    for track in tracks {
        running += track.duration
        cumulative.append(running)
    }

    // For each cut, take the boundary whose elapsed time is closest to an even division of
    // the album, keeping cuts strictly increasing so no side comes out empty.
    var cuts: [Int] = []
    for side in 1..<count {
        let target = total * Double(side) / Double(count)
        let lowerBound = (cuts.last ?? 0) + 1
        let upperBound = tracks.count - (count - side)
        guard lowerBound <= upperBound else { break }

        var best = lowerBound
        var bestDelta = abs(cumulative[best - 1] - target)
        for boundary in lowerBound...upperBound {
            let delta = abs(cumulative[boundary - 1] - target)
            if delta < bestDelta {
                best = boundary
                bestDelta = delta
            }
        }
        cuts.append(best)
    }

    var sides: [[AppTrack]] = []
    var start = 0
    for cut in cuts {
        sides.append(Array(tracks[start..<cut]))
        start = cut
    }
    sides.append(Array(tracks[start...]))
    return sides
}

/// "A", "B", "C" … for a side index.
func vinylSideLabel(_ index: Int) -> String {
    guard index >= 0, index < 26 else { return "\(index + 1)" }
    return String(UnicodeScalar(UInt8(65 + index)))
}

// MARK: - Duration Formatting

/// `m:ss`, or `h:mm:ss` past an hour. Matches the carousel's own formatting.
func gatefoldDuration(_ duration: TimeInterval) -> String {
    let total = Int(duration)
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
    return String(format: "%d:%02d", m, s)
}

/// "N min", for the credits line.
func gatefoldMinutes(_ duration: TimeInterval) -> String {
    "\(max(1, Int((duration / 60).rounded()))) min"
}

// MARK: - Rotating Disc

/// Turns its content at 33⅓ rpm (one revolution per 1.8s) while `isSpinning`.
///
/// Uses a paused `TimelineView` rather than `repeatForever`, because a repeating animation
/// cannot be stopped cleanly — the disc needs to hold its angle when playback pauses or Low
/// Power Mode kicks in, not snap back to zero.
private struct RotatingDisc<Content: View>: View {
    let isSpinning: Bool
    @ViewBuilder var content: () -> Content

    @State private var angle: Double = 0
    @State private var lastTick: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isSpinning)) { timeline in
            content()
                .rotationEffect(.degrees(angle))
                .onChange(of: timeline.date) { _, now in
                    guard isSpinning else {
                        lastTick = nil
                        return
                    }
                    if let last = lastTick {
                        angle += now.timeIntervalSince(last) / 1.8 * 360
                    }
                    lastTick = now
                }
        }
    }
}

// MARK: - Vinyl Disc

/// The record itself: near-black platter tinted toward the cover, groove hairlines, artwork
/// centre label, spindle hole, and a static diagonal sheen that deliberately does *not*
/// rotate with the disc.
struct VinylDisc<Label: View>: View {
    let diameter: CGFloat
    let isSpinning: Bool
    let showsWhiteLabel: Bool
    @ViewBuilder var label: () -> Label

    @Environment(\.sleeveTheme) private var theme

    private var labelDiameter: CGFloat { diameter * 0.36 }

    var body: some View {
        ZStack {
            RotatingDisc(isSpinning: isSpinning) {
                ZStack {
                    Circle()
                        .fill(theme.disc)

                    // Groove hairlines.
                    ForEach([0.92, 0.78, 0.64], id: \.self) { scale in
                        Circle()
                            .stroke(Color.white.opacity(scale > 0.8 ? 0.055 : 0.04), lineWidth: 0.5)
                            .frame(width: diameter * scale, height: diameter * scale)
                    }

                    Group {
                        if showsWhiteLabel {
                            Circle().fill(theme.stock)
                        } else {
                            label()
                        }
                    }
                    .frame(width: labelDiameter, height: labelDiameter)
                    .clipShape(Circle())

                    Circle()
                        .fill(theme.stock)
                        .frame(width: diameter * 0.035, height: diameter * 0.035)
                }
            }

            // Sheen sits above the spin so the highlight stays fixed to the room, not the disc.
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.10),
                            Color.white.opacity(0.02),
                            Color.clear,
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .allowsHitTesting(false)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Accessibility Identifiers

/// Handles for the gatefold's controls, shared with the UI tests. These are deliberately
/// not labels: the disc and the Play pill both read "Play"/"Pause" to VoiceOver, so a
/// test querying by label cannot tell which one it tapped.
enum GatefoldID {
    public static let cover = "gatefold.cover"
    public static let disc = "gatefold.disc"
    public static let play = "gatefold.play"
    public static let shuffle = "gatefold.shuffle"
}

// MARK: - Pills

/// Play / Shuffle. Visually 30 pt tall, with the hit area padded out to 44 pt.
private struct GatefoldPill: View {
    let title: String
    let icon: String
    let filled: Bool
    /// Stable handle for UI tests. The Play pill and the disc both label themselves
    /// "Play"/"Pause", so a label is not enough to tell them apart.
    let identifier: String
    let action: () -> Void

    @Environment(\.sleeveTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(filled ? theme.card : theme.ink)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background {
                if filled {
                    Capsule().fill(theme.ink)
                } else {
                    Capsule().stroke(theme.ink.opacity(0.45), lineWidth: 1)
                }
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Record Panel (Left Interior, Albums)

/// Left interior for albums: the disc, the credits, and the two actions.
struct RecordPanel<Label: View>: View {
    let panel: CGFloat
    let title: String
    let subtitle: String
    let reveal: CGFloat
    let isSpinning: Bool
    /// Whether *this* record is the one the player is working through. Distinct from
    /// `isSpinning`, which Low Power Mode can switch off while playback continues.
    let isPlayingThisItem: Bool
    let isFlipping: Bool
    let flipAngle: Double
    let showsWhiteLabel: Bool
    @ViewBuilder var label: () -> Label
    let onDiscTap: () -> Void
    let onPlay: () -> Void
    let onShuffle: () -> Void

    @Environment(\.sleeveTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// At accessibility sizes the disc tucks down so the credits keep their room.
    private var diameter: CGFloat {
        panel * (dynamicTypeSize.isAccessibilitySize ? 0.44 : 0.57)
    }

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            Button(action: onDiscTap) {
                VinylDisc(
                    diameter: diameter,
                    isSpinning: isSpinning,
                    showsWhiteLabel: showsWhiteLabel,
                    label: label
                )
            }
            .buttonStyle(.plain)
            .offset(y: isFlipping ? -20 : 0)
            .rotation3DEffect(.degrees(flipAngle), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
            // Slides in from the gutter side as the cover clears it.
            .offset(x: -14 * (1 - reveal))
            .opacity(Double(reveal))
            .accessibilityLabel(isPlayingThisItem ? "Pause" : "Play")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(GatefoldID.disc)

            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(theme.ink)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(theme.ink.opacity(0.6))
                    .lineLimit(1)
            }
            // Credits rise into place just behind the disc.
            .offset(y: 8 * (1 - creditsReveal))
            .opacity(Double(creditsReveal))

            HStack(spacing: 8) {
                GatefoldPill(
                    title: isPlayingThisItem ? "Pause" : "Play",
                    icon: isPlayingThisItem ? "pause.fill" : "play.fill",
                    filled: true,
                    identifier: GatefoldID.play,
                    action: onPlay
                )
                GatefoldPill(
                    title: "Shuffle",
                    icon: "shuffle",
                    filled: false,
                    identifier: GatefoldID.shuffle,
                    action: onShuffle
                )
            }
            .opacity(Double(creditsReveal))

            Spacer(minLength: 0)
        }
        // Padding inside the frame, not outside it. The other way round the panel ends
        // up 34 pt wider than the square it is meant to fill, so it overflows its slot
        // in the spread and its controls sit outside the bounds being hit-tested.
        .padding(.horizontal, 17)
        .frame(width: panel, height: panel)
    }

    /// Credits trail the disc by roughly 40 ms worth of progress.
    private var creditsReveal: CGFloat {
        max(0, min(1, (reveal - 0.12) / 0.88))
    }
}

// MARK: - Liner Panel (Right Interior)

struct LinerRow: Identifiable {
    let id: Int
    let number: Int
    let title: String
    let duration: TimeInterval
    let isCurrent: Bool
}

/// Right interior: the printed liner. One vinyl side at a time, with the side's runtime in
/// the header and an A·B control at the foot when the album has more than one side.
///
/// Rows are selectable two ways: a tap plays the track, and a rightward swipe queues it —
/// the same swipe that queues a song everywhere else in the app. The swipe is a plain
/// `.gesture`, deliberately not a high-priority one: a vertical drag has to keep reaching
/// the enclosing ScrollView so a long tracklist still scrolls, and SwiftUI only hands this
/// gesture the drags the scroll view does not claim. The cost is that a horizontal drag
/// started on a row no longer scrubs the gatefold hinge; drags anywhere else still do.
struct LinerPanel: View {
    let width: CGFloat
    let height: CGFloat
    let header: String
    let rows: [LinerRow]
    let sideCount: Int
    let currentSide: Int
    let showsSideControl: Bool
    let onSelect: (Int) -> Void
    let onQueue: (Int, QueuePlacement) -> Void
    let onSideChange: (Int) -> Void

    @Environment(\.sleeveTheme) private var theme
    @Environment(\.colorSchemeContrast) private var contrast

    /// The row that was just queued — the liner is printed matter with no system control
    /// styling, so it has to show the confirmation itself.
    @State private var queuedRow: Int?
    @State private var queuedFlashTask: Task<Void, Never>?

    private var separatorOpacity: Double { contrast == .increased ? 0.24 : 0.08 }

    /// Sideways travel before a drag counts as "queue this row".
    private let queueSwipeDistance: CGFloat = 44

    private var sideDuration: TimeInterval {
        rows.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(header)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2.8)
                    .foregroundColor(theme.ink)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text(gatefoldDuration(sideDuration))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(theme.ink.opacity(0.5))
            }
            .padding(.bottom, 5)

            Rectangle()
                .fill(theme.ink.opacity(0.22))
                .frame(height: 1)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        linerRow(row)

                        if row.id != rows.last?.id {
                            Rectangle()
                                .fill(theme.ink.opacity(separatorOpacity))
                                .frame(height: 0.5)
                        }
                    }
                }
            }

            if showsSideControl {
                // Every side count gets the same control. A segmented `Picker` used to
                // take over past four sides, and being UIKit-backed it never received a
                // touch out here: the panel is drawn well outside its ancestor's frame,
                // which SwiftUI's hit testing tolerates and UIKit's does not. One
                // control also means the slider looks the same on every album.
                ABControl(
                    sideCount: sideCount,
                    currentSide: currentSide,
                    maxWidth: width,
                    onSideChange: onSideChange
                )
                .padding(.top, 6)
            }
        }
        .frame(width: width, height: height)
        .onDisappear { queuedFlashTask?.cancel() }
    }

    @ViewBuilder
    private func linerRow(_ row: LinerRow) -> some View {
        let isQueued = queuedRow == row.id

        Button {
            onSelect(row.id)
        } label: {
            HStack(spacing: 7) {
                // The number becomes a tick for a moment after the row is queued, which
                // is the only confirmation that fits inside printed liner notes.
                Group {
                    if isQueued {
                        Image(systemName: "text.append")
                            .font(.system(size: 9, weight: .semibold))
                    } else {
                        Text("\(row.number)")
                            .font(.system(size: 10, design: .monospaced))
                    }
                }
                .foregroundColor(isQueued ? theme.accent : theme.ink.opacity(row.isCurrent ? 0.9 : 0.45))
                .frame(width: 16, alignment: .trailing)

                Text(row.title)
                    .font(.system(size: 12, weight: row.isCurrent ? .semibold : .regular))
                    .foregroundColor(row.isCurrent ? theme.accent : theme.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(gatefoldDuration(row.duration))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(theme.ink.opacity(0.45))
            }
        }
        // The press tint comes from the style rather than a `DragGesture(minimumDistance: 0)`
        // watching for touches. That gesture competed with the Button and the enclosing
        // ScrollView for every tap, which is exactly the kind of fight a tap loses.
        .buttonStyle(LinerRowButtonStyle(ink: theme.ink))
        // Simultaneous so the swipe cannot claim the touch from the row's own Button —
        // attached exclusively, a drag on a Button stops its action from firing.
        .simultaneousGesture(queueSwipe(for: row))
        // Touch and hold offers both placements; swipe right stays the one-move
        // shortcut for the bottom of the queue. Holding still cannot be mistaken for
        // the list's scroll, the swipe, or a tap.
        .contextMenu {
            Button {
                queue(row, placement: .next)
            } label: {
                Label(String(localized: "queue.action.playNext"), systemImage: "text.insert")
            }
            Button {
                queue(row, placement: .last)
            } label: {
                Label(String(localized: "queue.action.addToQueue"), systemImage: "text.append")
            }
        }
        .animation(.easeOut(duration: 0.18), value: isQueued)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.number). \(row.title)")
        .accessibilityAddTraits(row.isCurrent ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: Text(String(localized: "queue.action.playNext"))) {
            queue(row, placement: .next)
        }
        .accessibilityAction(named: Text(String(localized: "queue.action.addToQueue"))) {
            queue(row, placement: .last)
        }
    }

    /// Recognises only the rightward drags the enclosing ScrollView leaves alone.
    private func queueSwipe(for row: LinerRow) -> some Gesture {
        DragGesture(minimumDistance: 16)
            .onEnded { value in
                guard value.translation.width >= queueSwipeDistance,
                      abs(value.translation.width) > abs(value.translation.height) else { return }
                queue(row, placement: .last)
            }
    }

    private func queue(_ row: LinerRow, placement: QueuePlacement) {
        onQueue(row.id, placement)
        queuedFlashTask?.cancel()
        queuedRow = row.id
        queuedFlashTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            queuedRow = nil
        }
    }
}

/// Draws a liner row's press tint. A `ButtonStyle` reads the press state the Button
/// already tracks, so nothing has to add a gesture to observe it.
private struct LinerRowButtonStyle: ButtonStyle {
    let ink: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(ink.opacity(configuration.isPressed ? 0.10 : 0))
            )
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - A·B Control

/// The side selector: a glass track with one segment per side and a knob that can be
/// dragged along it or tapped straight to a side. Exposed to VoiceOver as a single
/// adjustable element so the sides can be stepped without the gesture.
///
/// The track and knob are drawn in the system Liquid Glass material rather than from
/// `sleeveTheme`, so the control reads identically on every album. The previous
/// ink-derived stroke took its colour from the cover, which left it close to invisible
/// on dark and photographic interiors. Only the labels still follow the sleeve, because
/// a fixed label colour would be illegible on one end or the other of that range.
struct ABControl: View {
    let sideCount: Int
    let currentSide: Int
    /// The room the liner can spare. Segments shrink to fit rather than running off the
    /// edge of the panel, which a double album with eight sides otherwise would.
    let maxWidth: CGFloat
    let onSideChange: (Int) -> Void

    @Environment(\.sleeveTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Where the knob sits while a drag is in flight, measured in segments. `nil` at
    /// rest, when the knob follows `currentSide` instead.
    @State private var dragSegment: CGFloat?

    private let trackHeight: CGFloat = 28

    private var segmentWidth: CGFloat {
        guard sideCount > 0 else { return 34 }
        return min(34, max(20, maxWidth / CGFloat(sideCount)))
    }

    private var trackWidth: CGFloat { segmentWidth * CGFloat(sideCount) }
    private var knobSegment: CGFloat { dragSegment ?? CGFloat(currentSide) }

    var body: some View {
        VStack(spacing: 3) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.black.opacity(0.12))
                    .overlay {
                        Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                    }

                GlassKnob()
                    .frame(width: segmentWidth - 4, height: trackHeight - 6)
                    .offset(x: knobSegment * segmentWidth + 2)

                HStack(spacing: 0) {
                    ForEach(0..<sideCount, id: \.self) { index in
                        Text(vinylSideLabel(index))
                            .font(.system(size: 11, weight: index == currentSide ? .semibold : .regular))
                            .foregroundColor(theme.ink.opacity(index == currentSide ? 0.95 : 0.5))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(width: segmentWidth)
                    }
                }
            }
            .frame(width: trackWidth, height: trackHeight)
            // Only the settled position animates. Drag updates move the knob straight
            // to the finger, which is the whole point of dragging it.
            .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.86),
                       value: currentSide)

            Text("Drag the slider, or swipe up on the record")
                .font(.system(size: 9))
                .foregroundColor(theme.ink.opacity(0.4))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(height: 44)
        .contentShape(Rectangle())
        // One gesture covers both jobs: a touch that never moves commits the segment it
        // landed on, and a drag carries the knob and commits wherever it is let go.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    dragSegment = segment(at: value.location.x)
                }
                .onEnded { value in
                    let target = Int(segment(at: value.location.x).rounded())
                    dragSegment = nil
                    guard target != currentSide else { return }
                    onSideChange(target)
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Record side")
        .accessibilityValue("Side \(vinylSideLabel(currentSide))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSideChange(min(sideCount - 1, currentSide + 1))
            case .decrement: onSideChange(max(0, currentSide - 1))
            @unknown default: break
            }
        }
    }

    /// Converts a touch position along the track into a segment, clamped to the ends.
    private func segment(at x: CGFloat) -> CGFloat {
        let raw = (x - segmentWidth / 2) / segmentWidth
        return min(max(0, raw), CGFloat(sideCount - 1))
    }
}

/// The slider's knob: real Liquid Glass where the OS has it, a material capsule on the
/// versions below. The app still deploys to iOS 17.6, so the effect cannot simply be
/// used — but both branches are independent of the sleeve, which is what keeps the
/// control looking the same from one album to the next.
private struct GlassKnob: View {
    var body: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay { Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        }
    }
}

// MARK: - Playlist Fan (Left Interior, Playlists)

/// Left interior for playlists. No disc — a playlist was never pressed to vinyl — so the
/// panel fans the first few covers instead.
struct PlaylistFanPanel<Artwork: View>: View {
    let panel: CGFloat
    let title: String
    let subtitle: String
    let reveal: CGFloat
    let artworkCount: Int
    let isPlayingThisItem: Bool
    @ViewBuilder var artwork: (Int) -> Artwork
    let onPlay: () -> Void
    let onShuffle: () -> Void

    @Environment(\.sleeveTheme) private var theme

    private var cardSize: CGFloat { panel * 0.46 }
    private let angles: [Double] = [-9, -3, 4, 9]

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)

            ZStack {
                ForEach(0..<min(artworkCount, 4), id: \.self) { index in
                    artwork(index)
                        .frame(width: cardSize, height: cardSize)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .shadow(color: .black.opacity(0.25), radius: 5, x: 0, y: 3)
                        .rotationEffect(.degrees(angles[index]))
                        .offset(x: CGFloat(index) * 6 - 9, y: CGFloat(index) * -3)
                }
            }
            .frame(width: panel * 0.72, height: cardSize * 1.15)
            .offset(x: -14 * (1 - reveal))
            .opacity(Double(reveal))

            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(theme.ink.opacity(0.6))
                    .lineLimit(1)
            }
            .offset(y: 8 * (1 - reveal))
            .opacity(Double(reveal))

            HStack(spacing: 8) {
                GatefoldPill(
                    title: isPlayingThisItem ? "Pause" : "Play",
                    icon: isPlayingThisItem ? "pause.fill" : "play.fill",
                    filled: true,
                    identifier: GatefoldID.play,
                    action: onPlay
                )
                GatefoldPill(
                    title: "Shuffle",
                    icon: "shuffle",
                    filled: false,
                    identifier: GatefoldID.shuffle,
                    action: onShuffle
                )
            }
            .opacity(Double(reveal))

            Spacer(minLength: 0)
        }
        // Padding inside the frame — see RecordPanel.
        .padding(.horizontal, 17)
        .frame(width: panel, height: panel)
    }
}

// MARK: - Show Panel (Left Interior, Podcasts)

/// Left interior for podcasts. A podcast opens like a book, not a gatefold: show art and
/// description, no disc, no sides, no spin.
struct ShowPanel<Artwork: View>: View {
    let panel: CGFloat
    let title: String
    let subtitle: String
    let reveal: CGFloat
    @ViewBuilder var artwork: () -> Artwork

    @Environment(\.sleeveTheme) private var theme

    private var artSize: CGFloat { panel * 0.52 }

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)

            artwork()
                .frame(width: artSize, height: artSize)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .shadow(color: .black.opacity(0.28), radius: 8, x: 0, y: 4)
                .offset(x: -14 * (1 - reveal))
                .opacity(Double(reveal))

            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(theme.ink)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(theme.ink.opacity(0.6))
                    .lineLimit(1)
            }
            .offset(y: 8 * (1 - reveal))
            .opacity(Double(reveal))

            Spacer(minLength: 0)
        }
        // Padding inside the frame — see RecordPanel.
        .padding(.horizontal, 17)
        .frame(width: panel, height: panel)
    }
}

// MARK: - Kraft Sleeve

/// Stand-in for missing artwork. A plain kraft sleeve with the title in letter-spaced caps
/// reads as an unbranded record jacket; a grey square just reads as a bug. Stays on the
/// default palette, since an item with no artwork has no colour to borrow.
struct KraftSleeve: View {
    let title: String
    let size: CGFloat

    var body: some View {
        ZStack {
            GatefoldPalette.kraft

            Text(title.uppercased())
                .font(.system(size: max(9, size * 0.055), weight: .medium))
                .tracking(max(1.5, size * 0.012))
                .foregroundColor(GatefoldPalette.ink.opacity(0.62))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, size * 0.12)
        }
        .frame(width: size, height: size)
    }
}
