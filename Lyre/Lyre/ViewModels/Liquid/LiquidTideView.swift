//
//  LiquidTideView.swift
//  Lyre
//

import SwiftUI

// MARK: - Tide
//
// Up Next, rising over Now Playing from the bulge on the bottom edge. Its top is a wave,
// and the songs stand in it as bands of their covers' colours, each a little taller the
// longer the song, so how long the queue runs can be seen at a glance.
//
// Every band shows what can be done with it: tap it to play it now (the rest of Up Next
// stays), the ✕ takes it out, and the grip drags it to another place; Clear empties the
// lot, after asking. A show's episodes play in the order they came out, so they list but
// can't be moved or taken out.
//
// It rises like a sheet: pulled up from the bulge on Now Playing it follows the finger,
// and dragged down by its top it follows the finger back; let go, and it settles open or
// falls away. Tapping the chevron or the dimmed cover above lets it fall. How far up it
// is (`progress`) belongs to LiquidPlayerView, which moves it.

struct LiquidTideView: View {
    @ObservedObject var musicService: MusicService
    /// How far up: 0 away below the screen, 1 open.
    let progress: CGFloat
    let onPick: (Int) -> Void
    let onClose: () -> Void
    let onNotice: (String) -> Void
    /// A finger dragging the top: how far down it has moved it.
    let onDrag: (CGFloat) -> Void
    /// The finger let go: how far it had moved, and how far it was heading.
    let onDragEnd: (CGFloat, CGFloat) -> Void

    @State private var isConfirmingClear = false
    @Environment(\.windowSafeArea) private var safeArea

    private var upNext: [AppTrack] { musicService.upcoming }
    private var canEdit: Bool { musicService.canEditUpcoming }

    var body: some View {
        GeometryReader { geometry in
            let height = Self.height(in: geometry.size.height)
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.35 * Double(progress))
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClose)
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    LiquidEdgeShape(amplitude: 0.5)
                        .fill(Color(red: 0.09, green: 0.09, blue: 0.1))
                        .frame(height: 36)
                        .overlay(alignment: .bottom) {
                            Capsule().fill(.white.opacity(0.35)).frame(width: 40, height: 5).offset(y: 2)
                        }
                    VStack(spacing: 0) {
                        header
                        content
                    }
                    .background(Color(red: 0.09, green: 0.09, blue: 0.1))
                }
                .frame(height: height)
                .offset(y: (1 - progress) * (height + 40))
                .gesture(
                    DragGesture(minimumDistance: 8, coordinateSpace: .global)
                        .onChanged { onDrag($0.translation.height) }
                        .onEnded { onDragEnd($0.translation.height, $0.predictedEndTranslation.height) }
                )
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("liquid.tide")
        .accessibilityAction(.escape, onClose)
    }

    /// How tall the tide stands when it's all the way up.
    static func height(in screen: CGFloat) -> CGFloat { screen * 0.8 }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(String(localized: "liquid.upNext").lowercased())
                .font(.system(size: 30, weight: .medium))
                .tracking(-1)
                .accessibilityAddTraits(.isHeader)
            if !upNext.isEmpty {
                Text(String(format: String(localized: "queue.upNextCount"), upNext.count))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 8)
            if !upNext.isEmpty, canEdit {
                Button(String(localized: "spool.queue.clear")) { isConfirmingClear = true }
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 1.5))
                    .accessibilityIdentifier("liquid.tide.clear")
                    .clearQueuePrompt(isPresented: $isConfirmingClear, count: upNext.count) {
                        musicService.clearQueue()
                        onNotice(String(localized: "queue.cleared"))
                    }
            }
            Button(action: onClose) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .accessibilityLabel(String(localized: "spool.queue.close"))
            .accessibilityIdentifier("liquid.tide.close")
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var content: some View {
        if upNext.isEmpty {
            VStack(spacing: 8) {
                Text(String(localized: "liquid.upNext.empty"))
                    .font(.system(size: 18, weight: .semibold))
                Text(String(localized: "liquid.upNext.empty.hint"))
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(entries) { entry in
                    LiquidBand(track: entry.track, canEdit: canEdit,
                               onPlay: { onPick(entry.offset) },
                               onRemove: { remove(IndexSet(integer: entry.offset)) })
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .accessibilityIdentifier("liquid.tide.band.\(entry.offset)")
                }
                .onMove(perform: moveAction)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 1)
            .padding(.bottom, safeArea.bottom)
        }
    }

    // MARK: Editing

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

    /// Moving, for a queue that can be edited; none for a show's episodes.
    private var moveAction: ((IndexSet, Int) -> Void)? { canEdit ? { move($0, $1) } : nil }

    private func move(_ source: IndexSet, _ destination: Int) {
        guard let origin = source.first else { return }
        let target = destination > origin ? destination - 1 : destination
        guard target != origin else { return }
        musicService.reorderUpNext(from: origin, to: target)
        musicService.commitQueueMove(to: target)
        onNotice(String(localized: "queue.reordered"))
    }

    private func remove(_ offsets: IndexSet) {
        let removed = offsets.sorted(by: >).compactMap { musicService.removeFromQueue(at: $0) }
        if removed.count == 1 {
            onNotice(String(format: String(localized: "queue.removed"), removed[0].title))
        }
    }
}

/// A song in the tide: a band of its cover's colour, taller the longer it runs.
private struct LiquidBand: View {
    let track: AppTrack
    let canEdit: Bool
    let onPlay: () -> Void
    let onRemove: () -> Void

    @State private var color: Color?

    var body: some View {
        let ground = color ?? LiquidColors.fallback(for: track.albumTitle)
        let isLight = ground.liquidIsLight
        let ink: Color = isLight ? Color(white: 0.1) : .white
        let minutes = min(8, max(1, track.duration / 60))
        HStack(spacing: 12) {
            Button(action: onPlay) {
                HStack(spacing: 12) {
                    LiquidCover(source: .track(track))
                        .frame(width: 46, height: 46)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 16, weight: .bold))
                            .lineLimit(1)
                        Text(track.duration > 0 ? "\(track.artistName) · \(AppHelpers.formatTime(track.duration))" : track.artistName)
                            .font(.system(size: 12))
                            .opacity(0.75)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(track.title)
            .accessibilityValue(track.artistName)
            .accessibilityHint(String(localized: "liquid.tide.playHint"))

            if canEdit {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(isLight ? 0.08 : 0.2), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(format: String(localized: "liquid.tide.remove"), track.title))
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 15, weight: .semibold))
                    .opacity(0.6)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(ink)
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .frame(height: 60 + CGFloat(minutes) * 7)
        .background(ground)
        .task(id: track.albumTitle + track.artistName) {
            let found = await LiquidColors.shared.color(for: track)
            withAnimation(.easeInOut(duration: 0.3)) { color = found }
        }
    }
}
