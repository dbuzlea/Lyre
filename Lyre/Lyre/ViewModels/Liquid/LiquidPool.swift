//
//  LiquidPool.swift
//  Lyre
//

import SwiftUI

// MARK: - Pool
//
// iPhone Duo, opened and turned so the fold runs across the middle: Now Playing's waves
// above, and below, Up Next standing as a pool, its songs floating in it as drops in
// a row (sideways, so a flick up or down can't be taken for scrolling).
//
//   flick a drop up     it rises into the wave above: it plays next
//   flick it down       it drains away, out of Up Next
//   tap it              it plays now; the rest of Up Next stays
//   hold, then drag     it moves to another place in the row
//
// A show's episodes play in the order they came out, so they float but don't move or
// drain. The button at the pool's edge swaps it for the library, and back.

struct LiquidPool: View {
    @ObservedObject var musicService: MusicService
    /// The colour of what's playing, which the pool takes.
    let color: Color
    let onPick: (Int) -> Void
    let onNotice: (String) -> Void
    let onShowLibrary: () -> Void

    private var upNext: [AppTrack] { musicService.upcoming }
    private var canEdit: Bool { musicService.canEditUpcoming }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "liquid.pool.title"))
                    .font(.system(size: 22, weight: .bold))
                if !upNext.isEmpty {
                    Text("\(upNext.count)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.18), in: Capsule())
                }
                Spacer()
                Button(action: onShowLibrary) {
                    Label(String(localized: "liquid.pool.library"), systemImage: "square.grid.2x2")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background(.white.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("liquid.pool.library")
            }
            .padding(.horizontal, 20)

            if upNext.isEmpty {
                VStack(spacing: 6) {
                    Text(String(localized: "liquid.upNext.empty"))
                        .font(.system(size: 17, weight: .semibold))
                    Text(String(localized: "liquid.upNext.empty.hint"))
                        .font(.system(size: 13))
                        .opacity(0.65)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 18) {
                        ForEach(entries) { entry in
                            LiquidDrop(track: entry.track, offset: entry.offset, canEdit: canEdit,
                                       onPlay: { onPick(entry.offset) },
                                       onRise: { playNext(entry.offset) },
                                       onDrain: { drain(entry.offset) })
                                .draggable(String(entry.offset)) {
                                    LiquidCover(source: .track(entry.track))
                                        .frame(width: 70, height: 70)
                                        .clipShape(Circle())
                                }
                                .dropDestination(for: String.self) { dropped, _ in
                                    guard canEdit, let raw = dropped.first, let from = Int(raw) else { return false }
                                    move(from, to: entry.offset)
                                    return true
                                }
                                .accessibilityIdentifier("liquid.pool.drop.\(entry.offset)")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .scrollClipDisabled()
                Text(String(localized: canEdit ? "liquid.pool.hint" : "liquid.pool.hint.episodes"))
                    .font(.system(size: 12))
                    .opacity(0.55)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 6)
            }
        }
        .foregroundStyle(.white)
        .padding(.top, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            // The pool's surface, rippling just under the fold.
            ZStack(alignment: .top) {
                LinearGradient(colors: [color.liquidDeep, Color.liquidGround], startPoint: .top, endPoint: .bottom)
                LiquidEdgeShape(amplitude: 0.35)
                    .fill(color.opacity(0.35))
                    .frame(height: 26)
                    .rotationEffect(.degrees(180))
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("liquid.pool")
    }

    // MARK: Up Next

    /// Up Next with an identity per drop, since the same song can be queued twice.
    private var entries: [Entry] {
        var seen: [String: Int] = [:]
        return upNext.enumerated().map { offset, track in
            let copy = seen[track.id, default: 0]
            seen[track.id] = copy + 1
            return Entry(id: "\(track.id)#\(copy)", offset: offset, track: track)
        }
    }

    private struct Entry: Identifiable {
        let id: String
        let offset: Int
        let track: AppTrack
    }

    private func playNext(_ offset: Int) {
        guard canEdit, upNext.indices.contains(offset) else { return }
        let title = upNext[offset].title
        if offset != 0 {
            musicService.reorderUpNext(from: offset, to: 0)
            musicService.commitQueueMove(to: 0)
        }
        onNotice(String(format: String(localized: "liquid.pool.playsNext"), title))
    }

    private func drain(_ offset: Int) {
        guard canEdit, let removed = musicService.removeFromQueue(at: offset) else { return }
        onNotice(String(format: String(localized: "queue.removed"), removed.title))
    }

    private func move(_ origin: Int, to target: Int) {
        guard origin != target, upNext.indices.contains(origin), upNext.indices.contains(target) else { return }
        musicService.reorderUpNext(from: origin, to: target)
        musicService.commitQueueMove(to: target)
        onNotice(String(localized: "queue.reordered"))
    }
}

// MARK: - Drop

/// A song floating in the pool: its cover as a drop, its name under it. Flicked up it
/// rises out of the pool, down it sinks. Still otherwise: a bob on every drop would keep
/// the screen redrawing all the time it's open.
private struct LiquidDrop: View {
    let track: AppTrack
    let offset: Int
    let canEdit: Bool
    let onPlay: () -> Void
    let onRise: () -> Void
    let onDrain: () -> Void

    /// How far it's been pulled up (negative) or down.
    @State private var lift: CGFloat = 0
    /// On its way out: up into the wave, or down the drain.
    @State private var leaving: CGFloat = 0

    private static let side: CGFloat = 96

    var body: some View {
        VStack(spacing: 8) {
            LiquidCover(source: .track(track))
                .frame(width: Self.side, height: Self.side)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.35), radius: 8, y: 5)
            Text(track.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(track.artistName)
                .font(.system(size: 11))
                .opacity(0.65)
                .lineLimit(1)
        }
        .frame(width: Self.side + 14)
        .offset(y: lift + leaving)
        .opacity(Double(1 - min(1, abs(leaving) / 300)))
        .contentShape(Rectangle())
        .onTapGesture(perform: onPlay)
        .modifier(LiquidFlickPan(onChange: { lift = $0 * (canEdit ? 1 : 0.2) }, onEnd: settle))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(String(localized: "liquid.tide.playHint"))
        .accessibilityActions {
            if canEdit {
                Button(String(localized: "queue.action.playNext"), action: onRise)
                Button(String(localized: "liquid.pool.drain"), action: onDrain)
            }
        }
    }

    private func settle(_ dy: CGFloat, _ velocity: CGFloat) {
        let heading = dy + velocity * 0.2
        guard canEdit, abs(heading) > 110 else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { lift = 0 }
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let up = heading < 0
        withAnimation(.easeIn(duration: 0.28)) { leaving = up ? -420 : 300 } completion: {
            up ? onRise() : onDrain()
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                lift = 0
                leaving = 0
            }
        }
    }
}

/// A flick up or down: a UIKit pan that begins only for a mostly vertical drag, so the
/// row scrolls sideways under the finger as before. A SwiftUI drag alongside before iOS 18.
private struct LiquidFlickPan: ViewModifier {
    let onChange: (CGFloat) -> Void
    let onEnd: (CGFloat, CGFloat) -> Void

    private var drag: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                guard abs(value.translation.height) > abs(value.translation.width) * 1.3 else { return }
                onChange(value.translation.height)
            }
            .onEnded { value in
                guard abs(value.translation.height) > abs(value.translation.width) * 1.3 else {
                    onEnd(0, 0)
                    return
                }
                onEnd(value.translation.height, value.velocity.height)
            }
    }

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.gesture(VerticalPan(onChange: onChange, onEnd: onEnd))
        } else {
            content.simultaneousGesture(drag)
        }
    }
}

@available(iOS 18.0, *)
private struct VerticalPan: UIGestureRecognizerRepresentable {
    let onChange: (CGFloat) -> Void
    let onEnd: (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let dy = recognizer.translation(in: recognizer.view).y
        switch recognizer.state {
        case .began, .changed: onChange(dy)
        case .ended: onEnd(dy, recognizer.velocity(in: recognizer.view).y)
        case .cancelled, .failed: onEnd(0, 0)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.y) > abs(velocity.x) * 1.3
        }
    }
}
