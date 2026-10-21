//
//  GramophoneCrateBin.swift
//  Lyre
//

import SwiftUI

// MARK: - Crate Bin
//
// iPhone Duo only. Opened, and turned so the fold runs across the middle, the inner
// screen is two halves: the gramophone above, and here below, a record shop's bin to
// flip through, as Up Next's rack is flipped through. Albums, songs, home recordings
// (playlists) and broadcasts (podcasts) each have a divider of their own.
//
// The records stand in the bin facing out, the next few showing over the top of the
// one in front. Swiping down tips the front record forward, as a hand flips through a
// bin, and the next is in front; swiping up stands the last one back up. A hard flick
// goes through several at once. Tapping the front record opens its sleeve (a song puts
// its album on at that song); holding it offers Play Next and Add to Queue. Each
// divider keeps its place.
//
// On any other iPhone, and on the Duo closed or held as a book, there is no bin: the
// drawer in the machine is where the records are, as before.

struct GramophoneCrateBin: View {
    enum Divider: String, CaseIterable, Identifiable {
        case albums, songs, recordings, broadcasts
        var id: String { rawValue }

        var title: String {
            switch self {
            case .albums:     return String(localized: "spool.shelf.albums")
            case .songs:      return String(localized: "gramophone.shelf.songs")
            case .recordings: return String(localized: "gramophone.shelf.recordings")
            case .broadcasts: return String(localized: "gramophone.shelf.broadcasts")
            }
        }
    }

    /// A record in the bin: an album (or playlist, or show), or one song.
    enum Record {
        case album(AppAlbum)
        case song(AppTrack)

        var title: String {
            switch self {
            case .album(let album): return album.tapeTitle
            case .song(let track): return track.title
            }
        }

        var subtitle: String {
            switch self {
            case .album(let album): return album.caseByline ?? album.artistName
            case .song(let track): return track.artistName
            }
        }

        /// What it is, apart from where it is: the bin finds its place again by this.
        var memoryID: String {
            switch self {
            case .album(let album): return album.id
            case .song(let track): return track.id
            }
        }

        var isPodcast: Bool {
            if case .album(let album) = self { return album.isPodcast }
            return false
        }
    }

    let library: ShelfLibrary
    @ObservedObject var musicService: MusicService
    let onOpen: (AppAlbum) -> Void
    let onPlaySong: (AppTrack) -> Void
    let onQueueAlbum: (AppAlbum, QueuePlacement) -> Void
    let onQueueSong: (AppTrack, QueuePlacement) -> Void

    @AppStorage("GramophoneBinDivider") private var divider: Divider = .albums
    /// The record in front.
    @State private var index = 0
    /// How far the front record's pulled, down (forward) or up.
    @State private var drag: CGFloat = 0
    /// A record tipping forward out of the way, and how far it's gone (0 standing, 1 down).
    @State private var falling: (record: Record, tip: CGFloat)?
    /// The front record standing back up, from tipped forward (1) to upright (0).
    @State private var rising: CGFloat = 0
    @State private var hasRestored = false
    @Environment(\.gramophoneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let commitDistance: CGFloat = 60
    private static let flickDistance: CGFloat = 700
    private static let flickStep = 5

    // MARK: The Records

    /// Read by place rather than mapped to records, so a library of thousands costs
    /// nothing per redraw.
    private var count: Int {
        switch divider {
        case .albums:     return library.albums.count
        case .songs:      return library.songs.count
        case .recordings: return library.mixtapes.count
        case .broadcasts: return library.podcasts.count
        }
    }

    private func record(at index: Int) -> Record? {
        guard index >= 0 else { return nil }
        switch divider {
        case .albums:
            let albums = library.albums
            return albums.indices.contains(index) ? .album(albums[index]) : nil
        case .songs:
            let songs = library.songs
            return songs.indices.contains(index) ? .song(songs[index]) : nil
        case .recordings:
            let mixtapes = library.mixtapes
            return mixtapes.indices.contains(index) ? .album(mixtapes[index]) : nil
        case .broadcasts:
            let podcasts = library.podcasts
            return podcasts.indices.contains(index) ? .album(podcasts[index]) : nil
        }
    }

    private var emptyText: String {
        switch divider {
        case .albums:     return String(localized: "spool.shelf.empty")
        case .songs:      return String(localized: "liquid.songs.empty")
        case .recordings: return String(localized: "gramophone.shelf.recordings.empty")
        case .broadcasts: return String(localized: "spool.shelf.podcasts.empty")
        }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 10) {
            dividers
            GeometryReader { geometry in
                bin(in: geometry.size)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .background(alignment: .top) {
            // The shop's counter the bin sits on.
            LinearGradient(colors: [theme.woodDark, Color(red: 0.06, green: 0.04, blue: 0.03)],
                           startPoint: .top, endPoint: .bottom)
                .overlay(alignment: .top) { Rectangle().fill(.black.opacity(0.5)).frame(height: 2) }
                .ignoresSafeArea(edges: .bottom)
        }
        .onAppear(perform: restore)
        .onChange(of: divider) {
            hasRestored = false
            falling = nil
            restore()
        }
        .onChange(of: count) {
            restore()
            if index >= count { index = max(0, count - 1) }
        }
        .onChange(of: index) {
            guard hasRestored, let record = record(at: index) else { return }
            UserDefaults.standard.set(record.memoryID, forKey: placeKey)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gramophone.bin")
    }

    private var dividers: some View {
        HStack(spacing: 6) {
            ForEach(Divider.allCases) { tab in
                Button {
                    guard tab != divider else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.easeInOut(duration: 0.2)) { divider = tab }
                } label: {
                    Text(tab.title)
                        .font(.system(size: 12, weight: .bold, design: .serif))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(tab == divider ? theme.plateInk : theme.ink.opacity(0.75))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(
                            UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8)
                                .fill(tab == divider ? theme.paper : theme.wood.opacity(0.6))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == divider ? .isSelected : [])
                .accessibilityIdentifier("gramophone.bin.\(tab.rawValue)")
            }
        }
    }

    // MARK: The Bin

    private func bin(in size: CGSize) -> some View {
        let plateHeight: CGFloat = 54
        let side = max(80, min(size.width * 0.56, size.height - plateHeight - 34))
        let wallHeight = side * 0.2
        return VStack(spacing: 0) {
            if count == 0 {
                Text(emptyText)
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(theme.ink.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack(alignment: .bottom) {
                    // The records behind, their tops showing over the one in front.
                    ForEach((1...3).reversed(), id: \.self) { depth in
                        if let record = record(at: index + depth) {
                            card(record, side: side)
                                .scaleEffect(1 - 0.035 * CGFloat(depth), anchor: .bottom)
                                .offset(y: -CGFloat(depth) * side * 0.075)
                                .brightness(-0.12 * Double(depth))
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    if let record = record(at: index) {
                        frontRecord(record, side: side)
                    }
                    // One tipping forward out of the way.
                    if let falling {
                        card(falling.record, side: side)
                            .rotation3DEffect(.degrees(-Double(falling.tip) * 88), axis: (x: 1, y: 0, z: 0),
                                              anchor: .bottom, perspective: 0.55)
                            .opacity(Double(1 - falling.tip * 0.6))
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    // The bin's front wall, which the records stand behind.
                    binWall(width: side + 40, height: wallHeight)
                        .allowsHitTesting(false)
                }
                .frame(width: size.width, height: size.height - plateHeight, alignment: .bottom)
                .clipped()
                plate(height: plateHeight)
            }
        }
    }

    private func card(_ record: Record, side: CGFloat) -> some View {
        Group {
            switch record {
            case .album(let album):
                RecordCard(album: album, size: CGSize(width: side, height: side))
            case .song(let track):
                TrackArtwork(track: track, size: side.rounded())
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: side * 0.012))
                    .shadow(color: .black.opacity(0.45), radius: 8, y: -2)
            }
        }
        .frame(width: side, height: side)
    }

    private func frontRecord(_ record: Record, side: CGFloat) -> some View {
        // Pulled down, it starts to tip forward; pulled up, it lifts a little.
        let tip = max(0, min(1, drag / (side * 1.1)))
        return card(record, side: side)
            .rotation3DEffect(.degrees(-Double(max(tip, rising)) * 88), axis: (x: 1, y: 0, z: 0),
                              anchor: .bottom, perspective: 0.55)
            .offset(y: drag < 0 ? max(drag * 0.25, -24) : 0)
            .contentShape(Rectangle())
            .onTapGesture { open(record) }
            .gesture(flip(side: side))
            .contextMenu {
                if !record.isPodcast {
                    Button { queue(record, .next) } label: {
                        Label(String(localized: "queue.action.playNext"), systemImage: "text.insert")
                    }
                    Button { queue(record, .last) } label: {
                        Label(String(localized: "queue.action.addToQueue"), systemImage: "text.append")
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(record.title + ", " + record.subtitle)
            .accessibilityValue(String(format: String(localized: "liquid.stack.position"), index + 1, count))
            .accessibilityHint(String(localized: "gramophone.bin.hint"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: step(1)
                case .decrement: step(-1)
                @unknown default: break
                }
            }
            .accessibilityAction(named: String(localized: "queue.action.playNext")) { queue(record, .next) }
            .accessibilityAction(named: String(localized: "queue.action.addToQueue")) { queue(record, .last) }
            .accessibilityIdentifier("gramophone.bin.front")
    }

    /// The bin's front: a wooden wall, its top edge catching the light.
    private func binWall(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(theme.woodGradient)
            .overlay(alignment: .top) {
                Rectangle().fill(theme.woodLight.opacity(0.7)).frame(height: 2)
            }
            .shadow(color: .black.opacity(0.5), radius: 6, y: -3)
            .frame(width: width, height: height)
    }

    /// The paper label on the counter: what's in front, and how far through the bin.
    private func plate(height: CGFloat) -> some View {
        let record = record(at: index)
        return VStack(spacing: 2) {
            Text(record?.title ?? "")
                .font(.system(size: 15, weight: .bold, design: .serif))
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(record?.subtitle ?? "")
                    .lineLimit(1)
                Text("·")
                Text(String(format: String(localized: "liquid.stack.position"), index + 1, count))
                    .monospacedDigit()
            }
            .font(.system(size: 12, design: .serif))
            .opacity(0.75)
        }
        .foregroundStyle(theme.ink)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .contentTransition(.opacity)
        .animation(.easeInOut(duration: 0.15), value: index)
        .accessibilityHidden(true)
    }

    // MARK: Flipping

    private func flip(side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard abs(value.translation.height) > abs(value.translation.width) || drag != 0 else { return }
                let dy = value.translation.height
                // Nothing further that way: it gives a little, no more.
                if dy > 0, index + 1 >= count { drag = dy * 0.2 } else if dy < 0, index == 0 { drag = dy * 0.2 } else { drag = dy }
            }
            .onEnded { value in
                let dy = value.translation.height
                let heading = value.predictedEndTranslation.height
                let committed = (abs(dy) > Self.commitDistance || abs(heading) > Self.commitDistance * 2.5)
                    && (dy > 0) == (heading > 0)
                guard committed else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { drag = 0 }
                    return
                }
                let steps = abs(heading) > Self.flickDistance ? Self.flickStep : 1
                step(dy > 0 ? steps : -steps)
            }
    }

    /// Forward `by` records (back, if negative): the front one tips over forward, or one
    /// tipped over stands back up.
    private func step(_ by: Int) {
        let target = min(max(index + by, 0), max(0, count - 1))
        guard target != index else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { drag = 0 }
            return
        }
        UISelectionFeedbackGenerator().selectionChanged()
        let tipped = max(0, min(1, drag / 200))
        var instant = Transaction()
        instant.disablesAnimations = true
        if target > index, let leaving = record(at: index) {
            withTransaction(instant) {
                falling = (leaving, tipped)
                drag = 0
                index = target
            }
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .easeIn(duration: 0.24)) { falling?.tip = 1 }
            Task {
                try? await Task.sleep(for: .milliseconds(260))
                if falling?.record.memoryID == leaving.memoryID { falling = nil }
            }
        } else {
            withTransaction(instant) {
                drag = 0
                index = target
                rising = 1
            }
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.78)) { rising = 0 }
        }
    }

    // MARK: Choosing

    private func open(_ record: Record) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        switch record {
        case .album(let album): onOpen(album)
        case .song(let track): onPlaySong(track)
        }
    }

    private func queue(_ record: Record, _ placement: QueuePlacement) {
        switch record {
        case .album(let album):
            guard !album.isPodcast else { return }
            onQueueAlbum(album, placement)
        case .song(let track):
            onQueueSong(track, placement)
        }
    }

    // MARK: Its Place

    private var placeKey: String { "GramophoneBinPlace." + divider.rawValue }

    /// Back on the record each divider was left on, once its records are in.
    private func restore() {
        guard !hasRestored, count > 0 else { return }
        hasRestored = true
        guard let saved = UserDefaults.standard.string(forKey: placeKey) else {
            index = 0
            return
        }
        let found: Int? = switch divider {
        case .albums:     library.albums.firstIndex { $0.id == saved }
        case .songs:      library.songs.firstIndex { $0.id == saved }
        case .recordings: library.mixtapes.firstIndex { $0.id == saved }
        case .broadcasts: library.podcasts.firstIndex { $0.id == saved }
        }
        index = found ?? 0
    }
}
