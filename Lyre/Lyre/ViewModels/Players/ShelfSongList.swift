//
//  ShelfSongList.swift
//  Lyre
//

import SwiftUI

// MARK: - Shelf Song List
//
// The Songs shelf of the Spool, the Disc and the Gramophone: every song in the library,
// A to Z, as each player would list them. The Spool's on a cassette's J-card, typed on
// its ruled lines; the Disc's in a CD's booklet; the Gramophone's printed on the back of
// a record sleeve. A letter heads each run of titles, and an A–Z index down the side
// jumps to one (LiquidLetterStrip).
//
// A song tapped plays, the rest of the list after it in Up Next, as the click wheel's
// Songs list plays; swiped right, it slides onto Play Next and Add to Queue
// (rowSwipeActions); held, it offers those and Add to Playlist (QueueMenu). Shuffle, at the top, plays the whole list in a random order. While
// searching, the list (and so what Shuffle plays) is the songs that match.

enum ShelfSongStyle {
    /// The Spool: a cassette's J-card.
    case jCard
    /// The Disc: a CD's booklet.
    case booklet
    /// The Gramophone: the back of a record sleeve.
    case sleeve
}

struct ShelfSongList: View {
    let tracks: [AppTrack]
    let style: ShelfSongStyle
    /// What to say when there are no songs (none in the library, or none matching).
    let emptyText: String
    /// The song playing, marked in the list.
    var playingID: String?
    /// Plays from song `index` of `tracks`.
    let onPlay: (Int) -> Void
    /// Plays the list shuffled.
    let onShuffle: () -> Void
    let onQueue: ([AppTrack], QueuePlacement) -> Void

    /// The first song under each letter, worked out when the list changes rather than
    /// on every redraw (a library can have thousands).
    @State private var headings: [Int: String] = [:]

    var body: some View {
        Group {
            if tracks.isEmpty {
                Text(emptyText)
                    .font(font(size: 15, weight: .medium))
                    .foregroundStyle(ink.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
        .background(paper)
        .clipShape(RoundedRectangle(cornerRadius: style == .sleeve ? 4 : 8, style: .continuous))
        .task(id: signature) { headings = Self.headings(for: tracks) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shelf.songs")
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .trailing) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        header
                        ForEach(tracks.indices, id: \.self) { index in
                            if let letter = headings[index] { heading(letter) }
                            row(tracks[index], index: index)
                                .id(index)
                        }
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, tracks.count >= 12 ? 34 : 14)
                    .padding(.vertical, 10)
                }
                .scrollIndicators(.hidden)
                if tracks.count >= 12 {
                    LiquidLetterStrip(titles: tracks.map(\.title), onJump: { index in
                        proxy.scrollTo(index, anchor: .top)
                    }, ink: ink)
                    .padding(.trailing, 4)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    // MARK: Rows

    private func row(_ track: AppTrack, index: Int) -> some View {
        let isPlaying = track.id == playingID
        return Button { onPlay(index) } label: {
            switch style {
            case .jCard: jCardRow(track, isPlaying: isPlaying)
            case .booklet: bookletRow(track, isPlaying: isPlaying)
            case .sleeve: sleeveRow(track, isPlaying: isPlaying)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isPlaying ? .isSelected : [])
        .accessibilityIdentifier("shelf.song.\(index)")
        // Swiped right onto Play Next and Add to Queue, as the albums' songs are. (The
        // row isn't one combined element, or the pills it reveals couldn't be reached.)
        .rowSwipeActions(RowSwipeAction.queue { placement in onQueue([track], placement) },
                         captionColor: ink.opacity(0.6))
        .modifier(QueueMenu(isEnabled: true, track: track, onQueue: onQueue))
    }

    /// Typed on a J-card's ruled line: the title, then who and what it's from, faint.
    private func jCardRow(_ track: AppTrack, isPlaying: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                // Typewriter letters are wide and the rack is narrow beside the door:
                // a long title runs onto a second line rather than being cut off.
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(track.title)
                        .font(font(size: 14, weight: isPlaying ? .bold : .regular))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if track.isExplicit { ExplicitTag() }
                }
                Text(byline(track))
                    .font(font(size: 10))
                    .foregroundStyle(ink.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            duration(track)
        }
        .foregroundStyle(isPlaying ? Self.jCardRed : ink)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // The card's blue ruled line under each song.
        .overlay(alignment: .bottom) { Rectangle().fill(Self.jCardBlue.opacity(0.35)).frame(height: 1) }
    }

    /// A line of the booklet's track listing.
    private func bookletRow(_ track: AppTrack, isPlaying: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: isPlaying ? "speaker.wave.2.fill" : "circle.fill")
                .font(.system(size: isPlaying ? 11 : 4))
                .foregroundStyle(ink.opacity(isPlaying ? 0.9 : 0.3))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(track.title)
                        .font(font(size: 15, weight: isPlaying ? .semibold : .regular))
                        .lineLimit(1)
                    if track.isExplicit { ExplicitTag() }
                }
                Text(byline(track))
                    .font(font(size: 12))
                    .foregroundStyle(ink.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            duration(track)
        }
        .foregroundStyle(ink)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rectangle().fill(ink.opacity(0.08)).frame(height: 0.5).padding(.leading, 24) }
    }

    /// A line printed on the back of a record sleeve: the title in the Gramophone's
    /// serif, who and what it's from in italics under it, on a fine brown rule.
    private func sleeveRow(_ track: AppTrack, isPlaying: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: isPlaying ? "speaker.wave.2.fill" : "smallcircle.filled.circle")
                .font(.system(size: isPlaying ? 11 : 7))
                .foregroundStyle(isPlaying ? Self.sleeveRed : ink.opacity(0.35))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(track.title)
                        .font(font(size: 16, weight: isPlaying ? .bold : .medium))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if track.isExplicit { ExplicitTag() }
                }
                Text(byline(track))
                    .font(font(size: 12))
                    .italic()
                    .foregroundStyle(ink.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            duration(track)
        }
        .foregroundStyle(isPlaying ? Self.sleeveRed : ink)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rectangle().fill(ink.opacity(0.18)).frame(height: 0.5).padding(.leading, 22) }
    }

    // MARK: Headings

    private func heading(_ letter: String) -> some View {
        Group {
            switch style {
            case .jCard:
                Text(letter)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Self.jCardRed)
                    .padding(.top, 12)
                    .padding(.bottom, 2)
            case .booklet:
                Text(letter)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(ink.opacity(0.45))
                    .padding(.top, 14)
                    .padding(.bottom, 2)
            case .sleeve:
                Text(letter)
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .italic()
                    .foregroundStyle(Self.sleeveRed)
                    .padding(.top, 12)
                    .padding(.bottom, 2)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }

    /// Above the songs: Shuffle, in the player's own hand. On the J-card it's written
    /// across the top beside the card's title; in the booklet, a printed button; on the
    /// sleeve, printed in red under the sleeve's heading.
    @ViewBuilder private var header: some View {
        switch style {
        case .jCard:
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "spool.shelf.songs").uppercased())
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(ink.opacity(0.75))
                    .accessibilityHidden(true)
                Spacer(minLength: 6)
                shuffleButton {
                    Label(String(localized: "detail.shuffle").uppercased(), systemImage: "shuffle")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Self.jCardRed)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .overlay(Capsule().strokeBorder(Self.jCardRed.opacity(0.7), lineWidth: 1.2))
                }
            }
            .padding(.bottom, 4)
            .overlay(alignment: .bottom) { Rectangle().fill(Self.jCardRed.opacity(0.7)).frame(height: 1.5) }
        case .booklet:
            shuffleButton {
                Label(String(localized: "detail.shuffle"), systemImage: "shuffle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(white: 0.98))
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(Color(white: 0.15), in: Capsule())
            }
            .padding(.bottom, 4)
        case .sleeve:
            shuffleButton {
                Label(String(localized: "detail.shuffle"), systemImage: "shuffle")
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(Self.sleevePaper)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(Self.sleeveRed, in: Capsule())
            }
            .padding(.bottom, 4)
        }
    }

    private func shuffleButton<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        Button(action: onShuffle, label: label)
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "detail.shuffle"))
            .accessibilityIdentifier("shelf.songs.shuffle")
    }

    // MARK: Parts

    private func duration(_ track: AppTrack) -> some View {
        Text(track.duration > 0 ? AppHelpers.formatTime(track.duration) : "")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(ink.opacity(0.5))
    }

    private func byline(_ track: AppTrack) -> String {
        track.albumTitle.isEmpty ? track.artistName : "\(track.artistName) · \(TapeFormat.displayTitle(track.albumTitle))"
    }

    private func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch style {
        case .jCard: .system(size: size, weight: weight, design: .monospaced)
        case .booklet: .system(size: size, weight: weight)
        case .sleeve: .system(size: size, weight: weight, design: .serif)
        }
    }

    private var ink: Color {
        style == .sleeve ? Color(red: 0.24, green: 0.14, blue: 0.08) : Color(white: 0.12)
    }

    @ViewBuilder private var paper: some View {
        switch style {
        case .jCard: Self.jCardPaper
        case .booklet: LinearGradient(colors: [Color(white: 0.99), Color(white: 0.93)], startPoint: .top, endPoint: .bottom)
        // Aged card, a little darker towards the foot, as an old sleeve's back is.
        case .sleeve: LinearGradient(colors: [Self.sleevePaper, Color(red: 0.88, green: 0.82, blue: 0.7)],
                                     startPoint: .top, endPoint: .bottom)
        }
    }

    private static let jCardPaper = Color(red: 0.96, green: 0.93, blue: 0.85)
    private static let jCardBlue = Color(red: 0.25, green: 0.45, blue: 0.8)
    private static let jCardRed = Color(red: 0.78, green: 0.16, blue: 0.14)
    private static let sleevePaper = Color(red: 0.95, green: 0.91, blue: 0.82)
    private static let sleeveRed = Color(red: 0.55, green: 0.13, blue: 0.1)

    /// Changes when the list does: its length and its ends.
    private var signature: String {
        "\(tracks.count):\(tracks.first?.id ?? ""):\(tracks.last?.id ?? "")"
    }

    /// The index of the first song under each letter.
    static func headings(for tracks: [AppTrack]) -> [Int: String] {
        var headings: [Int: String] = [:]
        var last: String?
        for (index, track) in tracks.enumerated() {
            let letter = letter(of: track.title)
            if letter != last { headings[index] = letter; last = letter }
        }
        return headings
    }

    /// The letter a title files under: the A–Z index's own (LiquidLetterEntry), so a
    /// heading is always where the index jumps to.
    static func letter(of title: String) -> String {
        LiquidLetterEntry.filingLetter(of: title)
    }
}
