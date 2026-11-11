//
//  RowSwipeActions.swift
//  Lyre
//

import SwiftUI

// MARK: - Row Swipe Actions
//
// Swiping a song right, in any of Lyre's lists, slides it aside onto Play Next and Add to
// Queue, as Apple Music's lists do: a purple pill and an orange one, each named under it.
// A long swipe plays it next straight away. An episode, which never joins the queue,
// offers its download there instead.
//
// Liquid's lists are system Lists and use `.swipeActions` with the same buttons and
// colours (RowSwipeAction.tint). The other players draw their lists in scroll views,
// where `.swipeActions` does nothing, so they use `rowSwipeActions` here, drawn to match.

/// One button a swiped row offers.
struct RowSwipeAction: Identifiable {
    let title: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var id: String { title }

    static let playNextTint = Color(red: 0.42, green: 0.32, blue: 0.86)
    static let addToQueueTint = Color(red: 0.93, green: 0.52, blue: 0.2)
    static let downloadTint = Color(red: 0.2, green: 0.5, blue: 0.95)
    static let libraryTint = Color(red: 0.04, green: 0.48, blue: 1.0)

    /// Add to Library: what a swiped-left song streamed from Apple Music offers, if the
    /// library hasn't it (LibraryAdder); nothing for one it has.
    @MainActor
    static func library(_ track: AppTrack) -> [RowSwipeAction] {
        guard LibraryAdder.shared.canAdd(track) else { return [] }
        return [RowSwipeAction(title: String(localized: "catalog.offer.add"), symbol: "plus.circle",
                               tint: libraryTint) { LibraryAdder.shared.add(track) }]
    }

    /// Play Next and Add to Queue: what a swiped song offers.
    static func queue(_ onQueue: @escaping (QueuePlacement) -> Void) -> [RowSwipeAction] {
        [RowSwipeAction(title: String(localized: "queue.action.playNext"), symbol: "text.insert",
                        tint: playNextTint) { UsageStats.shared.used(.swipeToQueue); onQueue(.next) },
         RowSwipeAction(title: String(localized: "queue.action.addToQueue"), symbol: "text.append",
                        tint: addToQueueTint) { UsageStats.shared.used(.swipeToQueue); onQueue(.last) }]
    }

    /// Download, Cancel or Remove Download: what a swiped episode offers.
    @MainActor
    static func download(_ episode: PodcastEpisode) -> [RowSwipeAction] {
        guard episode.streamURL != nil else { return [] }
        let downloads = PodcastDownloads.shared
        let action = downloads.actionTitle(for: episode.id)
        return [RowSwipeAction(title: action.title, symbol: action.symbol, tint: downloadTint) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            downloads.toggle(episode)
        }]
    }
}

/// Which row is slid open, so opening one closes any other; and whether a row is being
/// swiped, so a sideways drag of what holds the list (the Disc's case) leaves it be.
@Observable @MainActor
final class RowSwipeCoordinator {
    static let shared = RowSwipeCoordinator()
    var openRow: UUID?
    var isSwiping = false
}

extension View {
    /// Swiping the row right reveals `actions`, and left reveals `trailing`; a long swipe
    /// either way does that side's first. `captionColor` names the buttons legibly on the
    /// list's own ground.
    func rowSwipeActions(_ actions: [RowSwipeAction], trailing: [RowSwipeAction] = [],
                         captionColor: Color = .white.opacity(0.7)) -> some View {
        modifier(RowSwipeActions(actions: actions, trailing: trailing, captionColor: captionColor))
    }
}

private struct RowSwipeActions: ViewModifier {
    let actions: [RowSwipeAction]
    let trailing: [RowSwipeAction]
    let captionColor: Color

    @State private var id = UUID()
    /// How far the row is slid: right (positive) to show `actions`, left (negative) to
    /// show `trailing`.
    @State private var offset: CGFloat = 0
    /// Where it was slid to when the drag began.
    @State private var start: CGFloat = 0
    @State private var size: CGSize = .zero
    @State private var coordinator = RowSwipeCoordinator.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Off where a sideways swipe is something else's (a card among others in Liquid's
    /// deck turns to the next): the row's actions are in its menu there instead.
    @Environment(\.rowSwipesEnabled) private var swipesEnabled

    /// Tall enough to name each button under it, as Apple Music does; on a shorter row
    /// the name goes inside, beside the symbol.
    private var showsCaption: Bool { size.height >= 50 }

    private func buttonWidth(_ count: Int) -> CGFloat {
        guard count > 0, size.width > 0 else { return 80 }
        return min(showsCaption ? 80 : 118, (size.width - 48) / CGFloat(count) - 8)
    }
    private func revealWidth(_ count: Int) -> CGFloat { CGFloat(count) * (buttonWidth(count) + 8) + 8 }
    private var leadingWidth: CGFloat { revealWidth(actions.count) }
    private var trailingWidth: CGFloat { revealWidth(trailing.count) }
    private var isOpen: Bool { offset != 0 }

    func body(content: Content) -> some View {
        if actions.isEmpty && trailing.isEmpty {
            content
        } else {
            content
                .offset(x: offset)
                // A tap on a slid-open row closes it, rather than playing the song.
                .overlay {
                    if isOpen {
                        Color.clear
                            .contentShape(Rectangle())
                            .offset(x: offset)
                            .onTapGesture { close() }
                    }
                }
                .background(alignment: .leading) {
                    if offset > 0 { buttons(actions, shown: offset / max(1, leadingWidth), edge: .leading) }
                }
                .background(alignment: .trailing) {
                    if offset < 0 { buttons(trailing, shown: -offset / max(1, trailingWidth), edge: .trailing) }
                }
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
                .modifier(RowSwipeGesture(isOpen: isOpen, allowsRight: swipesEnabled && !actions.isEmpty,
                                          allowsLeft: swipesEnabled && !trailing.isEmpty,
                                          onChange: slide, onEnd: settle))
                .onChange(of: coordinator.openRow) {
                    if coordinator.openRow != id, isOpen { close() }
                }
                .onDisappear { if coordinator.openRow == id { coordinator.openRow = nil } }
        }
    }

    // MARK: Buttons

    private func buttons(_ actions: [RowSwipeAction], shown: CGFloat, edge: HorizontalEdge) -> some View {
        let pill = showsCaption ? min(36, size.height - 26) : max(18, min(32, size.height - 6))
        let width = buttonWidth(actions.count)
        let shown = min(1, shown)
        return HStack(spacing: 8) {
            ForEach(actions) { action in
                Button {
                    close()
                    action.action()
                } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: 5) {
                            Image(systemName: action.symbol)
                                .font(.system(size: min(17, pill * 0.5), weight: .semibold))
                            // Named inside only where the name fits whole.
                            if !showsCaption, width >= 112 {
                                Text(action.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .frame(width: width, height: pill)
                        .background(action.tint, in: Capsule())
                        if showsCaption {
                            Text(action.title)
                                .font(.system(size: 12))
                                .foregroundStyle(captionColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(width: width + 8)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(LyrePressStyle(isRow: true))
                .accessibilityLabel(action.title)
                .accessibilityIdentifier("swipe." + action.symbol)
            }
        }
        .padding(edge == .leading ? .leading : .trailing, 8)
        .scaleEffect(0.85 + 0.15 * shown, anchor: edge == .leading ? .leading : .trailing)
        .opacity(Double(shown))
    }

    // MARK: Sliding

    private func slide(_ dx: CGFloat) {
        if !coordinator.isSwiping {
            coordinator.isSwiping = true
            start = offset
        }
        let target = start + dx
        // Past the buttons it gives, then gives way to the long swipe; only towards a
        // side that has buttons.
        if target >= 0 {
            guard !actions.isEmpty else { offset = 0; return }
            offset = target <= leadingWidth ? target : leadingWidth + (target - leadingWidth) * 0.85
        } else {
            guard !trailing.isEmpty else { offset = 0; return }
            offset = -target <= trailingWidth ? target : -(trailingWidth + (-target - trailingWidth) * 0.85)
        }
    }

    private func settle(_ dx: CGFloat, velocity: CGFloat) {
        coordinator.isSwiping = false
        let heading = offset + velocity * 0.15
        if offset > 0 {
            if offset > max(leadingWidth + 60, size.width * 0.62) {
                // The long swipe: the first action, at once.
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                close()
                actions[0].action()
            } else if offset > leadingWidth * 0.45 && heading > leadingWidth * 0.3 {
                open(leadingWidth, velocity: velocity)
            } else {
                close(velocity: velocity)
            }
        } else if offset < 0 {
            if -offset > max(trailingWidth + 60, size.width * 0.62) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                close()
                trailing[0].action()
            } else if -offset > trailingWidth * 0.45 && -heading > trailingWidth * 0.3 {
                open(-trailingWidth, velocity: velocity)
            } else {
                close(velocity: velocity)
            }
        } else {
            close()
        }
    }

    /// The row let go towards `to`, the finger's `velocity` (points a second, rightward
    /// positive) carried on into the spring so it doesn't stop and start again.
    private func open(_ to: CGFloat, velocity: CGFloat = 0) {
        coordinator.openRow = id
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : slide(to: to, velocity: velocity)) {
            offset = to
        }
    }

    private func close(velocity: CGFloat = 0) {
        if coordinator.openRow == id { coordinator.openRow = nil }
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : slide(to: 0, velocity: velocity)) {
            offset = 0
        }
    }

    private func slide(to: CGFloat, velocity: CGFloat) -> Animation {
        let distance = to - offset
        guard velocity != 0, abs(distance) > 0.5 else { return LyreMotion.light }
        return LyreMotion.release(velocity: distance > 0 ? velocity : -velocity, distance: abs(distance))
    }
}

/// The row's swipe, as a UIKit pan: it only begins for a sideways drag (rightward, or
/// either way once the row is open), so the list still scrolls, and once it has begun it
/// cancels the row's own touch, so a swipe never also plays the song.
@available(iOS 18.0, *)
private struct RowSwipePan: UIGestureRecognizerRepresentable {
    let isOpen: Bool
    let allowsRight: Bool
    let allowsLeft: Bool
    let onChange: (CGFloat) -> Void
    let onEnd: (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        context.coordinator.isOpen = isOpen
        context.coordinator.allowsRight = allowsRight
        context.coordinator.allowsLeft = allowsLeft
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.isOpen = isOpen
        context.coordinator.allowsRight = allowsRight
        context.coordinator.allowsLeft = allowsLeft
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let dx = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .began, .changed: onChange(dx)
        case .ended: onEnd(dx, recognizer.velocity(in: recognizer.view).x)
        case .cancelled, .failed: onEnd(0, 0)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isOpen = false
        var allowsRight = true
        var allowsLeft = false

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.2
                && ((velocity.x > 0 && allowsRight) || (velocity.x < 0 && allowsLeft) || isOpen)
        }
    }
}

/// The UIKit pan where there is one (iOS 18); before that, a SwiftUI drag alongside the
/// row's own touch.
private struct RowSwipeGesture: ViewModifier {
    let isOpen: Bool
    let allowsRight: Bool
    let allowsLeft: Bool
    let onChange: (CGFloat) -> Void
    let onEnd: (CGFloat, CGFloat) -> Void
    @State private var isSideways: Bool?

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.gesture(RowSwipePan(isOpen: isOpen, allowsRight: allowsRight, allowsLeft: allowsLeft,
                                        onChange: onChange, onEnd: onEnd))
        } else {
            content.simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        let dx = value.translation.width
                        if isSideways == nil {
                            isSideways = abs(dx) > abs(value.translation.height) * 1.2
                                && ((dx > 0 && allowsRight) || (dx < 0 && allowsLeft) || isOpen)
                        }
                        if isSideways == true { onChange(dx) }
                    }
                    .onEnded { value in
                        if isSideways == true {
                            onEnd(value.translation.width, value.velocity.width)
                        }
                        isSideways = nil
                    }
            )
        }
    }
}

extension EnvironmentValues {
    /// Whether rows slide aside onto their swipe actions; off where a sideways swipe
    /// belongs to something else (RowSwipeActions).
    @Entry var rowSwipesEnabled = true
}
