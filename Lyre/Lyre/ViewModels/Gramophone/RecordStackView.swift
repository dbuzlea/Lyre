//
//  RecordStackView.swift
//  Lyre
//

import SwiftUI

// MARK: - Record Stack
//
// The records in the open drawer, in a stack, laid exactly over the 3D records the
// camera is looking down on (`frame` is where the top one is on screen), so the stack
// takes over from them without a seam.
//
//   swipe left    the top record goes off to the left, and the next one in the list
//                 is on top: on down the list
//   swipe right   it goes off to the right, and the one before is back on top: back
//                 up the list (LYRE-19 turned these round)
//   tap           opens its sleeve to choose a song
//   hold          Play Next or Add to Queue, as holding an album does on every player
//
// Whichever way a finger is pulling, the record under the top one is the one that
// comes next that way.

struct RecordStackView: View {
    let albums: [AppAlbum]
    /// Where the top record lies on screen, in global coordinates.
    let frame: CGRect
    /// The record on top. The stack opens on it and keeps it current, so coming back
    /// finds the stack where it was left.
    @Binding var frontID: String?
    let onOpen: (AppAlbum) -> Void
    let onQueue: (AppAlbum, QueuePlacement) -> Void

    /// How far the top record is pulled sideways.
    @State private var dragX: CGFloat = 0
    /// A record swiped off, on its way out: which, and which way.
    @State private var leaving: (album: AppAlbum, direction: CGFloat)?
    @State private var leavingX: CGFloat = 0

    /// How far a release must be, or be heading, to count as a swipe.
    private static let commitDistance: CGFloat = 90
    private static let commitVelocityDistance: CGFloat = 220

    /// Which way through the list a pull goes (LYRE-19): pulled left, on to the next
    /// record; pulled right, back to the one before. The record still goes off the way
    /// it's pulled.
    static func listStep(forPull x: CGFloat) -> Int { x < 0 ? 1 : -1 }

    private var index: Int {
        guard let frontID, let index = albums.firstIndex(where: { $0.id == frontID }) else { return 0 }
        return index
    }

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let center = CGPoint(x: frame.midX - origin.x, y: frame.midY - origin.y)
            ZStack {
                // From the bottom up: the records under the top one, then it.
                ForEach((1...3).reversed(), id: \.self) { depth in
                    if let album = album(atDepth: depth) {
                        sleeve(album, depth: depth)
                            .position(center)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                if let album = album(atDepth: 0) {
                    topRecord(album)
                        .position(center)
                }
                if let leaving {
                    RecordCard(album: leaving.album, size: frame.size)
                        .rotationEffect(.degrees(Double(leavingX / frame.width) * 14))
                        .position(x: center.x + leavingX, y: center.y)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - The Records

    /// The record `depth` down: the top one, then whichever comes next the way the
    /// top one's being pulled (on down the list unless it's pulled right).
    private func album(atDepth depth: Int) -> AppAlbum? {
        guard depth > 0 else { return albums.indices.contains(index) ? albums[index] : nil }
        let step = dragX > 0 ? -depth : depth
        let other = index + step
        return albums.indices.contains(other) ? albums[other] : nil
    }

    private func sleeve(_ album: AppAlbum, depth: Int) -> some View {
        let lie = GramophoneStage.stackLie(depth)
        let scale = frame.width / CGFloat(GramophoneStage.stackSleeveSide)
        return RecordCard(album: album, size: frame.size)
            .equatable()
            // Anticlockwise from above is anticlockwise on screen, looking down.
            .rotationEffect(.radians(-Double(lie.angle)))
            .offset(x: CGFloat(lie.x) * scale, y: CGFloat(lie.z) * scale)
            .brightness(-0.06 * Double(depth))
    }

    private func topRecord(_ album: AppAlbum) -> some View {
        RecordCard(album: album, size: frame.size)
            .equatable()
            // Holding the record queues it. A show's episodes don't go in the queue.
            .contextMenu {
                if !album.isPodcast {
                    Button { onQueue(album, .next) } label: {
                        Label(String(localized: "queue.action.playNext"), systemImage: "text.insert")
                    }
                    Button { onQueue(album, .last) } label: {
                        Label(String(localized: "queue.action.addToQueue"), systemImage: "text.append")
                    }
                }
            }
            .rotationEffect(.degrees(Double(dragX / max(frame.width, 1)) * 14))
            .offset(x: dragX)
            .contentShape(Rectangle())
            .onTapGesture { onOpen(album) }
            .simultaneousGesture(swipe)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(album.tapeTitle)
            .accessibilityValue(String(format: String(localized: "gramophone.stack.position"), index + 1, albums.count))
            .accessibilityHint(String(localized: "gramophone.stack.hint"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: move(by: 1)
                case .decrement: move(by: -1)
                @unknown default: break
                }
            }
            .accessibilityActions {
                if !album.isPodcast {
                    Button(String(localized: "queue.action.playNext")) { onQueue(album, .next) }
                    Button(String(localized: "queue.action.addToQueue")) { onQueue(album, .last) }
                }
            }
            .accessibilityIdentifier("gramophone.stack.\(album.id)")
    }

    // MARK: - Swiping

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let x = value.translation.width
                // Nothing further that way: it gives a little, and no more.
                dragX = albums.indices.contains(index + Self.listStep(forPull: x)) ? x : x * 0.25
            }
            .onEnded { value in
                let direction: CGFloat = value.translation.width < 0 ? -1 : 1
                let step = Self.listStep(forPull: value.translation.width)
                let travelled = abs(value.translation.width)
                let heading = abs(value.predictedEndTranslation.width)
                let committed = (travelled > Self.commitDistance || heading > Self.commitVelocityDistance)
                    && (value.predictedEndTranslation.width < 0) == (direction < 0)
                guard committed, albums.indices.contains(index + step) else {
                    if committed { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.5) }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { dragX = 0 }
                    return
                }
                fling(direction, step: step, from: dragX)
            }
    }

    /// The top record goes off `direction` (1 right, -1 left), and the one `step` along
    /// the list is on top.
    private func fling(_ direction: CGFloat, step: Int, from x: CGFloat) {
        let album = albums[index]
        GramophoneSound.flip.play()
        UISelectionFeedbackGenerator().selectionChanged()
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            leaving = (album, direction)
            leavingX = x
            dragX = 0
            frontID = albums[index + step].id
        }
        withAnimation(.easeIn(duration: 0.28)) { leavingX = direction * (frame.width * 1.6 + 80) }
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            if leaving?.album.id == album.id { leaving = nil }
        }
    }

    /// For VoiceOver: along the list by one, the record going off the way a finger
    /// would have pulled it.
    private func move(by step: Int) {
        guard albums.indices.contains(index + step) else { return }
        fling(step > 0 ? -1 : 1, step: step, from: 0)
    }
}
