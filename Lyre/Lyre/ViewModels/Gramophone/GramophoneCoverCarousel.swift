//
//  GramophoneCoverCarousel.swift
//  Lyre
//

import SwiftUI

// MARK: - Cover Carousel
//
// iPhone Duo only (LYRE-13). Opened partway or flat, with the fold across the middle,
// the inner screen is two halves: the gramophone above, and here below, the covers in a
// row to swipe through, as the Artwork Carousel lays them out: the one in the middle
// faces out, its neighbours turned away on either side, each standing on its reflection
// on the shop's counter. A search field and the dividers sit just above: albums, songs
// (each as its album's cover), home recordings (playlists) and broadcasts (podcasts).
//
// Swiping runs along the row, a flick coasting on; tapping a cover to the side brings it
// to the middle. Tapping the middle cover opens its sleeve with the record sliding out
// (a song puts its album on at that song); holding it offers Play Next and Add to Queue.
// Each divider keeps its place.
//
// On any other iPhone, on the Duo closed, and on the Duo open on its side, there is no
// carousel: the drawer in the machine is where the records are, as before.

struct GramophoneCoverCarousel: View {
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

    /// A cover in the row: an album (or playlist, or show), or one song.
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

        /// What it is, apart from where it is: the row finds its place again by this.
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
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool
    /// Where the row is, in covers: whole numbers at rest, between them while it moves.
    @State private var position: CGFloat = 0
    @State private var dragStart: CGFloat?
    @State private var hasRestored = false
    @Environment(\.gramophoneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let sideAngle: Double = 70
    private static let visibleRadius = 4

    // MARK: The Records

    /// The divider's records, narrowed to what the search field asks for.
    private var records: [Record] {
        let terms = LibrarySearch.terms(query)
        switch divider {
        case .albums:
            return LibrarySearch.filter(library.albums, matching: query, songs: library.songs).map(Record.album)
        case .songs:
            let songs = library.songs
            let found = terms.isEmpty ? songs
                : songs.filter { LibrarySearch.matches(terms, $0.title, $0.artistName, $0.albumTitle) }
            return found.map(Record.song)
        case .recordings:
            return LibrarySearch.filter(library.mixtapes, matching: query, songs: library.songs).map(Record.album)
        case .broadcasts:
            return LibrarySearch.filter(library.podcasts, matching: query, songs: library.songs).map(Record.album)
        }
    }

    private var emptyText: String {
        if !query.isEmpty { return String(localized: "search.noResults") }
        switch divider {
        case .albums:     return String(localized: "spool.shelf.empty")
        case .songs:      return String(localized: "liquid.songs.empty")
        case .recordings: return String(localized: "gramophone.shelf.recordings.empty")
        case .broadcasts: return String(localized: "spool.shelf.podcasts.empty")
        }
    }

    private var centered: Int { Int(position.rounded()) }

    // MARK: Body

    var body: some View {
        let records = records
        VStack(spacing: 8) {
            ShelfSearchField(query: $query, prompt: String(localized: "gramophone.search.prompt"),
                             isFocused: $isSearchFocused)
            dividers
            GeometryReader { geometry in
                carousel(records, in: geometry.size)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .background(alignment: .top) {
            // The shop's counter the covers stand on, in the machine's own wood.
            LinearGradient(colors: [theme.woodDark, Color(red: 0.06, green: 0.04, blue: 0.03)],
                           startPoint: .top, endPoint: .bottom)
                .overlay(alignment: .top) { Rectangle().fill(.black.opacity(0.5)).frame(height: 2) }
                .ignoresSafeArea(edges: .bottom)
        }
        .onAppear { restore(records) }
        .onChange(of: divider) {
            hasRestored = false
            restore(self.records)
        }
        .onChange(of: query) {
            withAnimation(.easeOut(duration: 0.2)) { position = 0 }
        }
        .onChange(of: records.count) {
            restore(self.records)
            if centered >= records.count { position = CGFloat(max(0, records.count - 1)) }
        }
        .onChange(of: centered) {
            guard hasRestored, query.isEmpty, records.indices.contains(centered) else { return }
            UserDefaults.standard.set(records[centered].memoryID, forKey: placeKey)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gramophone.carousel")
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
                .accessibilityIdentifier("gramophone.carousel.\(tab.rawValue)")
            }
        }
    }

    // MARK: The Row

    private func carousel(_ records: [Record], in size: CGSize) -> some View {
        let plateHeight: CGFloat = 50
        // The cover and its reflection, three quarters as tall, fill the room above the plate.
        let side = max(80, min(size.width * 0.5, (size.height - plateHeight - 12) / 1.6))
        let spacing = side * 0.2
        let step = side * 0.5 + spacing
        return VStack(spacing: 0) {
            if records.isEmpty {
                Text(emptyText)
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(theme.ink.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack {
                    ForEach(visibleIndices(count: records.count), id: \.self) { index in
                        cover(records[index], index: index, side: side, step: step, spacing: spacing,
                              count: records.count)
                    }
                }
                .frame(width: size.width, height: size.height - plateHeight)
                .contentShape(Rectangle())
                // Alongside the covers' own tap and hold, which would otherwise keep a
                // swipe that starts on a cover from moving the row.
                .simultaneousGesture(swipe(step: step, count: records.count))
                .clipped()
                plate(records, height: plateHeight)
            }
        }
    }

    /// The covers near the middle, farthest first so the middle one is drawn on top.
    private func visibleIndices(count: Int) -> [Int] {
        let low = max(0, centered - Self.visibleRadius)
        let high = min(count - 1, centered + Self.visibleRadius)
        guard low <= high else { return [] }
        return (low...high).sorted { abs(CGFloat($0) - position) > abs(CGFloat($1) - position) }
    }

    private func cover(_ record: Record, index: Int, side: CGFloat, step: CGFloat, spacing: CGFloat,
                       count: Int) -> some View {
        let raw = CGFloat(index) - position
        let isMiddle = index == centered
        return art(record, side: side)
            .scaleEffect(Self.scale(raw))
            .rotation3DEffect(.degrees(-Double(max(-1, min(1, raw))) * Self.sideAngle),
                              axis: (x: 0, y: 1, z: 0), perspective: 0.35)
            .offset(x: Self.offset(raw, step: step, spacing: spacing))
            .zIndex(Double(100 - abs(raw) * 10))
            .onTapGesture {
                if isMiddle { open(record) } else { move(to: index, count: count) }
            }
            .contextMenu {
                if isMiddle, !record.isPodcast {
                    Button { queue(record, .next) } label: {
                        Label(String(localized: "queue.action.playNext"), systemImage: "text.insert")
                    }
                    Button { queue(record, .last) } label: {
                        Label(String(localized: "queue.action.addToQueue"), systemImage: "text.append")
                    }
                }
            }
            .modifier(MiddleCoverAccessibility(isMiddle: isMiddle, record: record, index: index, count: count,
                                               onStep: { move(to: centered + $0, count: count) },
                                               onQueue: { queue(record, $0) }))
    }

    /// A cover standing on its reflection.
    private func art(_ record: Record, side: CGFloat) -> some View {
        VStack(spacing: 0) {
            artwork(record, side: side)
                .shadow(color: .black.opacity(0.7), radius: 10, y: 6)
            artwork(record, side: side)
                .scaleEffect(x: 1, y: -1)
                .mask(LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom))
                .frame(height: side * 0.6, alignment: .top)
                .clipped()
                .allowsHitTesting(false)
        }
        // The cover's middle, not the reflection's, is where the row runs.
        .offset(y: side * 0.3)
    }

    private func artwork(_ record: Record, side: CGFloat) -> some View {
        Group {
            switch record {
            case .album(let album):
                RecordCard(album: album, size: CGSize(width: side, height: side))
            case .song(let track):
                TrackArtwork(track: track, size: side.rounded())
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: side * 0.012))
            }
        }
        .frame(width: side, height: side)
    }

    /// The paper label on the counter: the middle cover, and how far along the row.
    private func plate(_ records: [Record], height: CGFloat) -> some View {
        let record = records.indices.contains(centered) ? records[centered] : nil
        return VStack(spacing: 2) {
            Text(record?.title ?? "")
                .font(.system(size: 15, weight: .bold, design: .serif))
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(record?.subtitle ?? "")
                    .lineLimit(1)
                Text("·")
                Text(String(format: String(localized: "liquid.stack.position"), centered + 1, records.count))
                    .monospacedDigit()
            }
            .font(.system(size: 12, design: .serif))
            .opacity(0.75)
        }
        .foregroundStyle(theme.ink)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .contentTransition(.opacity)
        .animation(.easeInOut(duration: 0.15), value: centered)
        .accessibilityHidden(true)
    }

    // MARK: Layout

    /// How far from the middle a cover sits: a full step for the first either side, then
    /// closer together, as the Artwork Carousel stacks them.
    static func offset(_ raw: CGFloat, step: CGFloat, spacing: CGFloat) -> CGFloat {
        let magnitude = abs(raw)
        let sign: CGFloat = raw < 0 ? -1 : 1
        return magnitude <= 1 ? raw * step : sign * (step + (magnitude - 1) * spacing)
    }

    static func scale(_ raw: CGFloat) -> CGFloat {
        let m = abs(raw)
        if m < 1 { return 1 - m * 0.13 }
        if m < 2 { return 0.87 - (m - 1) * 0.1 }
        return max(0.68, 0.77 - (m - 2) * 0.09)
    }

    // MARK: Moving

    private func swipe(step: CGFloat, count: Int) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if dragStart == nil { dragStart = position }
                let raw = (dragStart ?? 0) - value.translation.width / step
                // Past either end it gives a little, no more.
                let last = CGFloat(max(0, count - 1))
                position = raw < 0 ? raw * 0.25 : raw > last ? last + (raw - last) * 0.25 : raw
            }
            .onEnded { value in
                let start = dragStart ?? position
                dragStart = nil
                let coast = start - value.predictedEndTranslation.width / step
                move(to: Int(coast.rounded()), count: count)
            }
    }

    private func move(to target: Int, count: Int) {
        let target = min(max(target, 0), max(0, count - 1))
        if target != centered { UISelectionFeedbackGenerator().selectionChanged() }
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.86)) {
            position = CGFloat(target)
        }
    }

    // MARK: Choosing

    private func open(_ record: Record) {
        isSearchFocused = false
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

    /// Back on the cover each divider was left on, once its records are in.
    private func restore(_ records: [Record]) {
        guard !hasRestored, !records.isEmpty else { return }
        hasRestored = true
        let saved = UserDefaults.standard.string(forKey: placeKey)
        position = CGFloat(records.firstIndex { $0.memoryID == saved } ?? 0)
    }
}

/// VoiceOver for the middle cover: what it is, where in the row, swipe up or down to
/// move along, and the queue actions. The covers to the side are left out.
private struct MiddleCoverAccessibility: ViewModifier {
    let isMiddle: Bool
    let record: GramophoneCoverCarousel.Record
    let index: Int
    let count: Int
    let onStep: (Int) -> Void
    let onQueue: (QueuePlacement) -> Void

    func body(content: Content) -> some View {
        if isMiddle {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(record.title + ", " + record.subtitle)
                .accessibilityValue(String(format: String(localized: "liquid.stack.position"), index + 1, count))
                .accessibilityHint(String(localized: "gramophone.carousel.hint"))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: onStep(1)
                    case .decrement: onStep(-1)
                    @unknown default: break
                    }
                }
                .accessibilityAction(named: String(localized: "queue.action.playNext")) { onQueue(.next) }
                .accessibilityAction(named: String(localized: "queue.action.addToQueue")) { onQueue(.last) }
                .accessibilityIdentifier("gramophone.carousel.front")
        } else {
            content.accessibilityHidden(true)
        }
    }
}
