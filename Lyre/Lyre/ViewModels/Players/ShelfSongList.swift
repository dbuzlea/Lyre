//
//  ShelfSongList.swift
//  Lyre
//

import SwiftUI

// MARK: - Shelf Song List
//
// The Songs shelf of the Spool, the Disc and the Gramophone: every song in the library,
// A to Z, as each player would list them. The Spool's on a cassette's J-card, typed on
// its ruled lines; the Disc's in a CD's booklet; the Gramophone's on a jukebox's title
// strips, two-tone cards in a row. A letter heads each run of titles, and an A–Z index
// down the side jumps to one (LiquidLetterStrip).
//
// A song tapped plays, the rest of the list after it in Up Next, as the click wheel's
// Songs list plays; held, it offers Play Next, Add to Queue and Add to Playlist
// (QueueMenu). Shuffle, at the top, plays the whole list in a random order. While
// searching, the list (and so what Shuffle plays) is the songs that match.

enum ShelfSongStyle {
    /// The Spool: a cassette's J-card.
    case jCard
    /// The Disc: a CD's booklet.
    case booklet
    /// The Gramophone: a jukebox's title strips.
    case jukebox
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
        .clipShape(RoundedRectangle(cornerRadius: style == .jukebox ? 14 : 8, style: .continuous))
        .task(id: signature) { headings = Self.headings(for: tracks) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shelf.songs")
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .trailing) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: style == .jukebox ? 6 : 0) {
                        header
                        ForEach(tracks.indices, id: \.self) { index in
                            if let letter = headings[index] { heading(letter) }
                            row(tracks[index], index: index)
                                .id(index)
                        }
                    }
                    .padding(.leading, style == .jukebox ? 10 : 14)
                    .padding(.trailing, tracks.count >= 12 ? 34 : (style == .jukebox ? 10 : 14))
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
            case .jukebox: jukeboxStrip(track, index: index, isPlaying: isPlaying)
            }
        }
        .buttonStyle(.plain)
        .modifier(QueueMenu(isEnabled: true, track: track, onQueue: onQueue))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isPlaying ? .isSelected : [])
        .accessibilityIdentifier("shelf.song.\(index)")
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

    /// A jukebox title strip: a card with a coloured band across top and bottom, the
    /// title in capitals over the artist, centred. The bands take turns, red and blue,
    /// as a jukebox's do.
    private func jukeboxStrip(_ track: AppTrack, index: Int, isPlaying: Bool) -> some View {
        let band = index.isMultiple(of: 2) ? Self.jukeboxRed : Self.jukeboxBlue
        return VStack(spacing: 3) {
            HStack(spacing: 5) {
                Text(track.title.uppercased())
                    .font(.system(size: 13, weight: .heavy, design: .serif))
                    .tracking(0.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if track.isExplicit { ExplicitTag() }
            }
            Rectangle().fill(band.opacity(0.7)).frame(width: 60, height: 1)
            Text(track.artistName)
                .font(.system(size: 11, weight: .medium, design: .serif))
                .italic()
                .lineLimit(1)
        }
        .foregroundStyle(Color(white: 0.12))
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .background(
            Self.stripCard
                .overlay(alignment: .top) { band.frame(height: 5) }
                .overlay(alignment: .bottom) { band.frame(height: 5) }
        )
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay {
            // The one playing is lit.
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(Color(red: 1, green: 0.78, blue: 0.3), lineWidth: isPlaying ? 2.5 : 0)
        }
        .shadow(color: isPlaying ? Color(red: 1, green: 0.7, blue: 0.2).opacity(0.6) : .black.opacity(0.3),
                radius: isPlaying ? 6 : 1.5, y: 1)
        .contentShape(Rectangle())
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
            case .jukebox:
                // A chrome plate over the run of strips.
                Text(letter)
                    .font(.system(size: 13, weight: .black, design: .serif))
                    .foregroundStyle(Color(white: 0.15))
                    .frame(width: 30, height: 22)
                    .background(
                        LinearGradient(colors: [Color(white: 0.95), Color(white: 0.6), Color(white: 0.9)],
                                       startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }

    /// Above the songs: Shuffle, in the player's own hand. On the J-card it's written
    /// across the top beside the card's title; in the booklet, a printed button; on the
    /// jukebox, a chrome push button.
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
        case .jukebox:
            shuffleButton {
                Label(String(localized: "detail.shuffle").uppercased(), systemImage: "shuffle")
                    .font(.system(size: 13, weight: .black, design: .serif))
                    .tracking(1)
                    .foregroundStyle(Color(white: 0.12))
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(
                        LinearGradient(colors: [Color(white: 0.97), Color(white: 0.62), Color(white: 0.9)],
                                       startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
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
        case .jukebox: .system(size: size, weight: weight, design: .serif)
        }
    }

    private var ink: Color {
        style == .jukebox ? Color(red: 0.98, green: 0.93, blue: 0.82) : Color(white: 0.12)
    }

    @ViewBuilder private var paper: some View {
        switch style {
        case .jCard: Self.jCardPaper
        case .booklet: LinearGradient(colors: [Color(white: 0.99), Color(white: 0.93)], startPoint: .top, endPoint: .bottom)
        // The jukebox's selector, dark behind its strips.
        case .jukebox: LinearGradient(colors: [Color(red: 0.2, green: 0.1, blue: 0.06), Color(red: 0.08, green: 0.04, blue: 0.03)],
                                      startPoint: .top, endPoint: .bottom)
        }
    }

    private static let jCardPaper = Color(red: 0.96, green: 0.93, blue: 0.85)
    private static let jCardBlue = Color(red: 0.25, green: 0.45, blue: 0.8)
    private static let jCardRed = Color(red: 0.78, green: 0.16, blue: 0.14)
    private static let jukeboxRed = Color(red: 0.75, green: 0.12, blue: 0.12)
    private static let jukeboxBlue = Color(red: 0.12, green: 0.3, blue: 0.65)
    private static let stripCard = Color(red: 0.97, green: 0.94, blue: 0.86)

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
