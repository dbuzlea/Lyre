//
//  QueueView.swift
//  Lyre
//

import SwiftUI

// MARK: - Queue Screen
//
// Shows what is playing now followed by the Up Next list, and doubles as the reorder
// surface. Like every other screen it is display-only: the scroll wheel owns the
// cursor (`selection`, an offset into Up Next) and the carry state.
//
// Reordering is a two-step "pick up, drop" interaction, the only shape that fits a
// wheel and one button: pressing the center button picks up the highlighted row
// (`movingOffset`), the wheel then carries it through the list, and a second press
// drops it. The carried row is drawn with an up/down arrow glyph and a dashed edge so
// it is obvious the wheel is moving the song rather than the cursor. A swipe left on the
// center button plays the highlighted song now, and a swipe right takes it out.
//
// The footer hint changes with the mode because there is nothing else on the device to
// discover these gestures from.
//
// The list is the same one every player shows (`MusicService.upcoming`): Up Next, or
// while a podcast plays, the show's later episodes. Those play in the show's order, so
// they can't be moved, removed or cleared; pressing the center button on one plays it.
struct QueueView: View {
    /// The Clear Queue row sits one step *above* the first song rather than taking
    /// index 0, so every other offset still maps straight onto Up Next. It also means
    /// the cursor never lands on a destructive action when the screen opens — the
    /// user has to scroll up to it deliberately.
    static let clearRowOffset = -1

    /// The highest the cursor goes: the Clear Queue row, or the first row when the list
    /// can't be edited and so has no Clear row.
    static func topOffset(canEdit: Bool) -> Int { canEdit ? clearRowOffset : 0 }

    @ObservedObject var musicService: MusicService
    let themeSettings: ThemeSettings
    @Binding var selection: Int
    /// Up Next offset of the row the user is carrying, or nil when simply browsing.
    let movingOffset: Int?

    private var upNext: [AppTrack] { musicService.upcoming }
    private var canEdit: Bool { musicService.canEditUpcoming }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            Divider().background(themeSettings.currentTheme.dividerColor)

            if upNext.isEmpty {
                emptyState
            } else {
                nowPlayingRow
                // Shuffle makes the player choose its own next track, so the order
                // below is the queue's, not the order it will be heard in. Saying so
                // beats looking broken when a queued song is passed over.
                if musicService.shuffleMode != .off, canEdit {
                    Label(String(localized: "queue.shuffleOn"), systemImage: "shuffle")
                        .font(.system(size: 8))
                        .foregroundStyle(themeSettings.currentTheme.screenSecondaryTextColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 6)
                }
                trackList
                hint
            }
        }
        // The cursor is an offset into a list that shrinks as songs play, so it is
        // clamped both on arrival and whenever the queue changes underneath it.
        .onAppear { clampSelection() }
        .onChange(of: upNext.count) { _, _ in clampSelection() }
        .onChange(of: canEdit) { _, _ in clampSelection() }
    }

    private func clampSelection() {
        selection = upNext.isEmpty ? 0 : min(max(Self.topOffset(canEdit: canEdit), selection), upNext.count - 1)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "chevron.left")
                .font(.system(size: 10))
                .foregroundStyle(themeSettings.currentTheme.screenTextColor)
            Text(String(localized: "queue.title"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(themeSettings.currentTheme.screenTextColor)
            Spacer()
            if !upNext.isEmpty {
                Text(String(format: String(localized: "queue.upNextCount"), upNext.count))
                    .font(.system(size: 10))
                    .foregroundStyle(themeSettings.currentTheme.screenSecondaryTextColor)
            }
        }
    }

    // MARK: - Now Playing

    @ViewBuilder
    private var nowPlayingRow: some View {
        if let current = musicService.nowPlayingTrack {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    Image(systemName: musicService.isPlaying ? "play.fill" : "pause.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(themeSettings.currentTheme.highlightColor)
                    Text(String(localized: "queue.nowPlaying"))
                        .font(.system(size: 8, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(themeSettings.currentTheme.highlightColor)
                }
                Text(current.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(String(localized: "queue.nowPlaying")): \(current.title)")
        }
    }

    // MARK: - Up Next

    private var trackList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if canEdit {
                        clearRow
                            .id(rowID(Self.clearRowOffset))
                    }
                    ForEach(Array(upNext.enumerated()), id: \.offset) { offset, track in
                        row(offset: offset, track: track)
                            .id(rowID(offset))
                    }
                }
            }
            .onAppear { proxy.scrollTo(rowID(selection), anchor: .center) }
            .onChange(of: selection) { _, newValue in
                withAnimation { proxy.scrollTo(rowID(newValue), anchor: .center) }
            }
        }
    }

    private func rowID(_ offset: Int) -> String {
        offset == Self.clearRowOffset ? "queue-clear" : "queue-\(offset)"
    }

    private var clearRow: some View {
        let isSelected = selection == Self.clearRowOffset

        return HStack(spacing: 4) {
            Image(systemName: "trash")
                .font(.system(size: 9))
                .foregroundStyle(isSelected
                    ? themeSettings.currentTheme.highlightTextColor
                    : themeSettings.currentTheme.screenSecondaryTextColor)
                .frame(width: 16, alignment: .center)
            Text(String(localized: "queue.clear"))
                .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected
                    ? themeSettings.currentTheme.highlightTextColor
                    : themeSettings.currentTheme.screenSecondaryTextColor)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? themeSettings.currentTheme.highlightColor : Color.clear)
        .selectionBarRefraction(when: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "queue.clear"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func row(offset: Int, track: AppTrack) -> some View {
        let isSelected = selection == offset
        let isMoving = movingOffset == offset

        return HStack(spacing: 4) {
            if isMoving {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(themeSettings.currentTheme.highlightTextColor)
                    .frame(width: 16, alignment: .center)
            } else {
                Text("\(offset + 1)")
                    .font(.system(size: 9))
                    .foregroundStyle(isSelected
                        ? themeSettings.currentTheme.highlightTextColor.opacity(0.7)
                        : themeSettings.currentTheme.screenTextColor.opacity(0.5))
                    .frame(width: 16, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.system(size: 11, weight: isMoving ? .semibold : .regular))
                    .foregroundStyle(isSelected
                        ? themeSettings.currentTheme.highlightTextColor
                        : themeSettings.currentTheme.screenTextColor)
                    .lineLimit(1)
                Text(track.artistName)
                    .font(.system(size: 9))
                    .foregroundStyle(isSelected
                        ? themeSettings.currentTheme.highlightTextColor.opacity(0.8)
                        : themeSettings.currentTheme.screenSecondaryTextColor)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? themeSettings.currentTheme.highlightColor : Color.clear)
        .overlay {
            if isMoving {
                Rectangle()
                    .strokeBorder(
                        themeSettings.currentTheme.highlightTextColor.opacity(0.8),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                    )
            }
        }
        .selectionBarRefraction(when: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(offset + 1). \(track.title), \(track.artistName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Footer / Empty

    private var hint: some View {
        // Whichever gesture the highlighted row responds to, spelled out — there is
        // nowhere else on the device to discover it.
        let key: String.LocalizationValue
        if !canEdit {
            key = "queue.hint.episodes"
        } else if movingOffset != nil {
            key = "queue.hint.moving"
        } else if selection == Self.clearRowOffset {
            key = "queue.hint.clear"
        } else {
            key = "queue.hint.browse"
        }

        return Text(String(localized: key))
            .font(.system(size: 8))
            .foregroundStyle(movingOffset == nil
                ? themeSettings.currentTheme.screenSecondaryTextColor
                : themeSettings.currentTheme.highlightColor)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Spacer()
            Image(systemName: "list.bullet.indent")
                .font(.system(size: 28))
                .foregroundStyle(themeSettings.currentTheme.screenTextColor.opacity(0.3))
            Text(String(localized: "queue.empty"))
                .font(.system(size: 12))
                .foregroundStyle(themeSettings.currentTheme.screenTextColor.opacity(0.5))
            Text(String(localized: "queue.empty.hint"))
                .font(.system(size: 9))
                .multilineTextAlignment(.center)
                .foregroundStyle(themeSettings.currentTheme.screenSecondaryTextColor)
                .padding(.horizontal, 12)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
