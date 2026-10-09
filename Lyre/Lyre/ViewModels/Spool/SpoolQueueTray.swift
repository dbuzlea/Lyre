//
//  SpoolQueueTray.swift
//  Lyre
//

import SwiftUI

// MARK: - Up Next Tray
//
// The queue, in a metal tray that pulls up from the bottom of the deck. Like the
// cassette case, it is driven by a progress the finger can scrub: SpoolPlayerView drags
// it up from the grip under the door, and dragging the tray's header back down puts it
// away. It follows the finger both ways and settles open or shut on release.
//
// Inside, the playing song sits at the top on its own label, and Up Next below it as a
// stack of song labels: tap one to play it now, hold one to move it, swipe one away to
// take it out of the queue.
//
// Tapping a song pulls its label out of the stack; SpoolPlayerView then lifts the
// cassette out of it and loads it into the deck (see `onPick`).
//
// While a podcast streams, the stack is the show's later episodes, in the order they
// play. They can be tapped to play but not moved or taken out: the show sets the order.

struct SpoolQueueTray: View {
    @ObservedObject var musicService: MusicService
    /// 0 put away, 1 all the way up.
    let progress: CGFloat
    /// The tray's height above the safe area.
    let height: CGFloat
    let bottomInset: CGFloat
    let onScrub: (CGFloat) -> Void
    /// Called on release; true puts the tray away.
    let onScrubEnd: (Bool) -> Void
    let onClose: () -> Void
    let onNotice: (String) -> Void
    /// A song tapped to play: its Up Next offset, the song, and where its label sits in
    /// SpoolPlayerView's coordinate space, for the cassette to come out of.
    let onPick: (Int, AppTrack, CGRect) -> Void

    @Environment(\.spoolTheme) private var theme
    @State private var dragStart: CGFloat?
    /// The label pulled out of the stack, and whether its cassette has left it.
    @State private var pulledID: String?
    @State private var isPulledEmpty = false
    @State private var rowFrames: [String: CGRect] = [:]

    private var upNext: [AppTrack] { musicService.upcoming }
    private var nowPlaying: AppTrack? { musicService.nowPlayingTrack }
    private var canEdit: Bool { musicService.canEditUpcoming }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.4 * progress)
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
                .accessibilityHidden(true)

            panel
                .frame(height: height + bottomInset)
                .offset(y: (1 - progress) * (height + bottomInset + 24))
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            header
            window
                .padding(.horizontal, 12)
        }
        .padding(.bottom, bottomInset + 8)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                .fill(LinearGradient(colors: [theme.railLight, theme.rail], startPoint: .top, endPoint: .bottom))
                // Brushed grain, as on the rail.
                .overlay(
                    LinearGradient(colors: [.white.opacity(0.12), .clear, .white.opacity(0.08), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
                )
                .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: -4)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spool.queue")
        .accessibilityAction(.escape, onClose)
    }

    // MARK: - Header

    /// The grip and title. Dragging anywhere on it pulls the tray back down.
    private var header: some View {
        VStack(spacing: 10) {
            Capsule()
                .fill(theme.keySymbol.opacity(0.35))
                .frame(width: 40, height: 5)
                .padding(.top, 8)
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "spool.queue.title").uppercased())
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .tracking(2)
                        .accessibilityAddTraits(.isHeader)
                    if !upNext.isEmpty {
                        Text(String(format: String(localized: "queue.upNextCount"), upNext.count))
                            .font(.system(size: 12, weight: .medium))
                            .opacity(0.7)
                    }
                }
                Spacer(minLength: 8)
                if !upNext.isEmpty, canEdit {
                    Button(String(localized: "spool.queue.clear")) {
                        musicService.clearQueue()
                        onNotice(String(localized: "queue.cleared"))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(theme.keyLight, in: Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                    .accessibilityIdentifier("spool.queue.clear")
                }
                Button(action: onClose) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(theme.keyLight, in: Circle())
                        .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                }
                .accessibilityLabel(String(localized: "spool.queue.close"))
                .accessibilityIdentifier("spool.queue.close")
            }
            .padding(.horizontal, 20)
        }
        .foregroundStyle(theme.keySymbol)
        .padding(.bottom, 12)
        .contentShape(Rectangle())
        .gesture(closeDrag)
    }

    private var closeDrag: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(SpoolPlayerView.coordinateSpace))
            .onChanged { value in
                let start = dragStart ?? progress
                if dragStart == nil { dragStart = progress }
                onScrub(min(1, max(0, start - value.translation.height / height)))
            }
            .onEnded { value in
                dragStart = nil
                let speed = value.velocity.height
                onScrubEnd(speed > 300 || (speed > -300 && value.translation.height > height * 0.25))
            }
    }

    // MARK: - Window

    /// The dark recess the labels sit in.
    private var window: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let nowPlaying {
                Text(String(localized: "queue.nowPlaying"))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.55))
                label(for: nowPlaying, number: nil, isPlaying: true)
                    .accessibilityIdentifier("spool.queue.nowPlaying")
            }

            if musicService.shuffleMode != .off, !upNext.isEmpty, canEdit {
                Label(String(localized: "queue.shuffleOn"), systemImage: "shuffle")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }

            if upNext.isEmpty {
                emptyState
            } else {
                list
                Text(String(localized: canEdit ? "spool.queue.hint" : "spool.queue.hint.episodes"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(theme.bay)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(.black.opacity(0.35), lineWidth: 3)
                        .blur(radius: 2)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                )
        )
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.bullet")
                .font(.system(size: 28, weight: .light))
            Text(String(localized: "spool.queue.empty"))
                .font(.system(size: 16, weight: .semibold))
            Text(String(localized: "spool.queue.empty.hint"))
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .opacity(0.7)
        }
        .foregroundStyle(.white.opacity(0.8))
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("spool.queue.empty")
    }

    /// Up Next. A List, for its drag-to-move and swipe-to-remove.
    private var list: some View {
        List {
            ForEach(entries) { entry in
                Button {
                    pick(entry)
                } label: {
                    label(for: entry.track, number: entry.offset + 1, isPlaying: false)
                        // Once its cassette is out, the label is an empty sleeve.
                        .opacity(pulledID == entry.id && isPulledEmpty ? 0.45 : 1)
                }
                .buttonStyle(.plain)
                // Pulled out of the stack, sideways and up towards the finger.
                .offset(x: pulledID == entry.id ? 34 : 0)
                .scaleEffect(pulledID == entry.id ? 1.03 : 1)
                .shadow(color: .black.opacity(pulledID == entry.id ? 0.5 : 0), radius: 8, x: 0, y: 4)
                .zIndex(pulledID == entry.id ? 1 : 0)
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(SpoolPlayerView.coordinateSpace))
                } action: { rowFrames[entry.id] = $0 }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                .accessibilityIdentifier("spool.queue.row.\(entry.offset)")
            }
            .onMove(perform: moveAction)
            .onDelete(perform: removeAction)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
    }

    /// A song's label: cream card stock, like the label on the cassette.
    private func label(for track: AppTrack, number: Int?, isPlaying: Bool) -> some View {
        HStack(spacing: 10) {
            if let number {
                Text("\(number)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .opacity(0.5)
                    .frame(minWidth: 18, alignment: .trailing)
            }
            TrackArtwork(track: track, size: 36)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.system(size: 14, weight: .semibold))
                Text(track.artistName)
                    .font(.system(size: 12))
                    .opacity(0.65)
            }
            .lineLimit(1)
            Spacer(minLength: 6)
            if isPlaying {
                Image(systemName: musicService.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.isLight ? theme.logo : theme.accent)
            } else if track.duration > 0 {
                Text(AppHelpers.formatTime(track.duration))
                    .font(.system(size: 12, design: .monospaced))
                    .opacity(0.55)
            }
        }
        .foregroundStyle(SpoolPalette.labelInk)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(SpoolPalette.label)
                // The coloured band along the top of a cassette label.
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill((theme.isLight ? theme.logo : theme.accent).opacity(isPlaying ? 0.9 : 0.35))
                        .frame(height: 3)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6))
                }
        )
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Editing

    /// Up Next with an identity per row, since the same song can be queued twice.
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

    /// Pulls the song's label out of the stack, then hands it over to be loaded.
    private func pick(_ entry: Entry) {
        guard pulledID == nil else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.26, dampingFraction: 0.7)) {
            pulledID = entry.id
        } completion: {
            isPulledEmpty = true
            onPick(entry.offset, entry.track, rowFrames[entry.id] ?? .zero)
        }
    }

    /// Moving and removing, for a queue that can be edited; none for a show's episodes.
    private var moveAction: ((IndexSet, Int) -> Void)? { canEdit ? { move($0, $1) } : nil }
    private var removeAction: ((IndexSet) -> Void)? { canEdit ? { remove($0) } : nil }

    private func move(_ source: IndexSet, _ destination: Int) {
        guard let origin = source.first else { return }
        // The destination counts the row being moved; the queue's offsets don't.
        let target = destination > origin ? destination - 1 : destination
        guard target != origin else { return }
        musicService.reorderUpNext(from: origin, to: target)
        musicService.commitQueueMove(to: target)
        onNotice(String(localized: "queue.reordered"))
    }

    private func remove(_ offsets: IndexSet) {
        // From the bottom up, so the offsets still to go stay valid.
        let removed = offsets.sorted(by: >).compactMap { musicService.removeFromQueue(at: $0) }
        if removed.count == 1 {
            onNotice(String(format: String(localized: "queue.removed"), removed[0].title))
        }
    }
}
