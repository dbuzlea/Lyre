//
//  LiquidCardStack.swift
//  Lyre
//

import SwiftUI

// MARK: - Card Stack
//
// The other way to look through a list in Liquid: one cover at a time, in a stack, as the
// Gramophone's drawer holds its records. The cover on top fills most of the page, with
// the next few showing askew underneath it; its name is under it. Swiping it left brings
// the next one up, swiping right the one before, and on an alphabetical list an A–Z row
// under it jumps through the letters. Holding a cover queues it. One cover at a time is
// calmer than a page of them.
//
// Tapping the top cover turns it over (LiquidFoldView, over the whole library), as the
// Gramophone turns a record's sleeve: the cover comes forward and flips round, its back
// the album's name, Play and Shuffle and the track list, and the record slides partway
// up out of its top.
//
// The pages offer the stack beside their grid or list (LiquidLayoutSwitch); the choice is
// kept for every list.

/// A cover in a stack: an album (or playlist, or show), or one song of a list of songs.
enum LiquidStackItem: Identifiable {
    case album(AppAlbum)
    /// A song, with the list it's in and its place there.
    case song(AppTrack, list: [AppTrack], index: Int, listName: String)

    var id: String {
        switch self {
        case .album(let album): return "album:" + album.id
        case .song(let track, _, let index, _): return "song:\(index):" + track.id
        }
    }

    var title: String {
        switch self {
        case .album(let album): return album.tapeTitle
        case .song(let track, _, _, _): return track.title
        }
    }

    var subtitle: String {
        switch self {
        case .album(let album):
            return [album.caseByline, album.tapeDetail]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        case .song(let track, _, _, _):
            return track.albumTitle.isEmpty ? track.artistName
                : "\(track.artistName) · \(TapeFormat.displayTitle(track.albumTitle))"
        }
    }

    var cover: LiquidCover.Source {
        switch self {
        case .album(let album): return .album(album)
        case .song(let track, _, _, _): return .track(track)
        }
    }

    /// What it is, apart from where it is in the list: the cover the stack was left on
    /// is found again by this, wherever it's moved to since.
    var memoryID: String {
        switch self {
        case .album(let album): return album.id
        case .song(let track, _, _, _): return track.id
        }
    }

    var isPodcast: Bool {
        if case .album(let album) = self { return album.isPodcast }
        return false
    }
}

/// The switch beside a page's name between all at once and one at a time.
struct LiquidLayoutSwitch: View {
    @Binding var layout: LiquidLayout

    var body: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                layout = layout == .stack ? .grid : .stack
            }
        } label: {
            Image(systemName: layout == .stack ? "square.grid.2x2" : "rectangle.stack")
                .font(.system(size: 17, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.1), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: layout == .stack ? "liquid.layout.grid" : "liquid.layout.stack"))
        .accessibilityIdentifier("liquid.layout")
    }
}

/// A cover's hold menu in the stack: an album's as the grid has it (LiquidAlbumHoldMenu),
/// a song's as the lists have it (QueueMenu).
private struct LiquidStackHoldMenu: ViewModifier {
    let item: LiquidStackItem
    @Environment(\.liquidNavigator) private var navigator

    func body(content: Content) -> some View {
        switch item {
        case .album(let album):
            content.modifier(LiquidAlbumHoldMenu(album: album))
        case .song(let track, _, _, _):
            content.modifier(QueueMenu(isEnabled: true, track: track,
                                       onQueue: { navigator.queue($0, $1, track.title) }))
        }
    }
}

// MARK: - The Stack

struct LiquidCardStack: View {
    let items: [LiquidStackItem]
    /// Alphabetical, so it has the A–Z row.
    var isAlphabetical = true
    @ObservedObject var musicService: MusicService
    let bottomInset: CGFloat
    /// The covers' names, gathered once per list for the index rather than on every
    /// frame of a swipe (the stack redraws as it's dragged).
    private let titles: [String]
    @Environment(\.liquidNavigator) private var navigator

    init(items: [LiquidStackItem], isAlphabetical: Bool = true, musicService: MusicService, bottomInset: CGFloat) {
        self.items = items
        self.isAlphabetical = isAlphabetical
        self.musicService = musicService
        self.bottomInset = bottomInset
        titles = items.map(\.title)
    }

    /// The cover on top.
    @State private var index = 0
    /// Whether the stack has gone back to the cover it was left on.
    @State private var hasRestored = false
    @Environment(\.liquidListKey) private var listKey
    /// How far the top cover is pulled sideways.
    @State private var dragX: CGFloat = 0
    /// A cover swiped off, on its way out: which, and which way.
    @State private var leaving: (item: LiquidStackItem, direction: CGFloat)?
    @State private var leavingX: CGFloat = 0
    /// The top cover's place on screen, where it swings open from.
    @State private var topFrame: CGRect = .zero

    private static let commitDistance: CGFloat = 80
    private static let commitVelocityDistance: CGFloat = 220
    /// How the covers underneath lie: across, down, and turned.
    private static let lie: [(x: CGFloat, y: CGFloat, degrees: Double)] = [(-12, 10, -5), (14, 16, 4), (-8, 22, -2.5)]

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width - 64, geometry.size.height * 0.58)
            VStack(spacing: 18) {
                ZStack {
                    ForEach((1...3).reversed(), id: \.self) { depth in
                        if let item = item(atDepth: depth) {
                            card(item, side: side)
                                .scaleEffect(1 - 0.03 * CGFloat(depth))
                                .rotationEffect(.degrees(Self.lie[depth - 1].degrees))
                                .offset(x: Self.lie[depth - 1].x, y: Self.lie[depth - 1].y)
                                .brightness(-0.1 * Double(depth))
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    if items.indices.contains(index) {
                        topCard(items[index], side: side)
                    }
                    if let leaving {
                        card(leaving.item, side: side)
                            .rotationEffect(.degrees(Double(leavingX / side) * 14))
                            .offset(x: leavingX)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: side + 40, height: side + 40)

                if items.indices.contains(index) {
                    let item = items[index]
                    VStack(spacing: 4) {
                        Text(item.title)
                            .font(.system(size: 22, weight: .bold))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        Text(item.subtitle)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                        Text(String(format: String(localized: "liquid.stack.position"), index + 1, items.count))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.top, 2)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.15), value: item.id)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("liquid.stack.nowShowing")
                }

                if isAlphabetical, items.count >= 12 {
                    LiquidLetterRow(titles: titles) { jump(to: $0) }
                        .padding(.horizontal, 16)
                }
                Spacer(minLength: 0)
            }
            .frame(width: geometry.size.width)
            .padding(.top, 8)
        }
        .padding(.bottom, bottomInset)
        // Back on the cover it was left on, when that's in the list (which may still
        // be loading when the page opens).
        .onAppear(perform: restore)
        .onChange(of: items.count) {
            restore()
            // Back to the first cover if a search leaves the one on top out of range.
            if !items.indices.contains(index) { index = 0 }
        }
        .onChange(of: index) {
            guard hasRestored, items.indices.contains(index), !listKey.isEmpty else { return }
            UserDefaults.standard.set(items[index].memoryID, forKey: placeKey)
        }
    }

    // MARK: Covers

    /// The cover `depth` down: whichever comes next the way the top one is pulled (on,
    /// unless it's pulled right).
    private func item(atDepth depth: Int) -> LiquidStackItem? {
        let step = dragX > 0 ? -depth : depth
        return items.indices.contains(index + step) ? items[index + step] : nil
    }

    private func card(_ item: LiquidStackItem, side: CGFloat) -> some View {
        LiquidCover(source: item.cover)
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.55), radius: 18, y: 10)
    }

    private func topCard(_ item: LiquidStackItem, side: CGFloat) -> some View {
        let playing = isPlaying(item)
        return card(item, side: side)
            // Playing, it's marked as in the lists.
            .overlay(alignment: .bottomTrailing) {
                if playing {
                    Image(systemName: "waveform")
                        .font(.system(size: 15, weight: .bold))
                        .symbolEffect(.variableColor.iterative, isActive: musicService.isPlaying)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.55), in: Circle())
                        .padding(12)
                        .accessibilityHidden(true)
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { topFrame = $0 }
            .rotationEffect(.degrees(Double(dragX / side) * 12))
            .offset(x: dragX)
            .contentShape(Rectangle())
            .onTapGesture { open(item) }
            .simultaneousGesture(swipe(side: side))
            // Held, the same menu as the grid's covers and the lists' songs.
            .modifier(LiquidStackHoldMenu(item: item))
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(item.title)
            .accessibilityAction(named: String(localized: "queue.action.playNext")) { queue(item, .next) }
            .accessibilityAction(named: String(localized: "queue.action.addToQueue")) { queue(item, .last) }
            .accessibilityValue(String(format: String(localized: "liquid.stack.position"), index + 1, items.count))
            .accessibilityHint(String(localized: "liquid.stack.hint"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: move(by: 1)
                case .decrement: move(by: -1)
                @unknown default: break
                }
            }
            .accessibilityIdentifier("liquid.stack.top")
    }

    private func open(_ item: LiquidStackItem) {
        let fold = LiquidFoldState.shared
        guard fold.item == nil, topFrame.width > 0 else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        fold.frame = topFrame
        fold.item = item
    }

    /// Whether it's what's playing: the song, or the album, playlist or show it's from.
    private func isPlaying(_ item: LiquidStackItem) -> Bool {
        switch item {
        case .song(let track, _, _, _):
            return musicService.currentTrack?.id == track.id
        // Worked out as Liquid finds the album playing to open it from Now Playing.
        case .album(let album):
            if let show = musicService.currentPodcastShowTitle { return album.isPodcast && album.title == show }
            if let playlist = musicService.currentPlaylistID { return album.mixtape?.id == playlist }
            guard !album.isPodcast, !album.isMixtape, let track = musicService.nowPlayingTrack else { return false }
            return TapeFormat.displayTitle(track.albumTitle) == album.tapeTitle && track.artistName == album.artistName
        }
    }

    private func queue(_ item: LiquidStackItem, _ placement: QueuePlacement) {
        guard !item.isPodcast else { return }
        switch item {
        case .album(let album): navigator.queueAlbum(album, placement)
        case .song(let track, _, _, _): navigator.queue([track], placement, track.title)
        }
    }

    // MARK: Moving

    private func swipe(side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let x = value.translation.width
                // Nothing further that way: it gives a little, and no more.
                let step = x < 0 ? 1 : -1
                dragX = items.indices.contains(index + step) ? x : x * 0.25
            }
            .onEnded { value in
                let x = value.translation.width
                let heading = value.predictedEndTranslation.width
                let committed = (abs(x) > Self.commitDistance || abs(heading) > Self.commitVelocityDistance)
                    && (heading < 0) == (x < 0)
                let step = x < 0 ? 1 : -1
                guard committed, items.indices.contains(index + step) else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { dragX = 0 }
                    return
                }
                fling(step, from: dragX, side: side)
            }
    }

    /// The top cover goes off the way it was swiped, and the next one that way is on top.
    private func fling(_ step: Int, from x: CGFloat, side: CGFloat) {
        let item = items[index]
        UISelectionFeedbackGenerator().selectionChanged()
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            leaving = (item, step > 0 ? -1 : 1)
            leavingX = x
            dragX = 0
            index += step
        }
        withAnimation(.easeIn(duration: 0.26)) { leavingX = (step > 0 ? -1 : 1) * (side * 1.6 + 80) }
        Task {
            try? await Task.sleep(for: .milliseconds(280))
            if leaving?.item.id == item.id { leaving = nil }
        }
    }

    private func move(by step: Int) {
        guard items.indices.contains(index + step) else { return }
        fling(step, from: 0, side: topFrame.width)
    }

    private var placeKey: String { "LiquidStackPlace." + listKey }

    private func restore() {
        guard !hasRestored, !items.isEmpty else { return }
        hasRestored = true
        guard !listKey.isEmpty, let saved = UserDefaults.standard.string(forKey: placeKey),
              let found = items.firstIndex(where: { $0.memoryID == saved }) else { return }
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { index = found }
    }

    private func jump(to target: Int) {
        guard items.indices.contains(target), target != index else { return }
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { index = target }
    }
}

/// An A–Z row: a finger along it jumps to the first title under each letter.
struct LiquidLetterRow: View {
    let titles: [String]
    let onJump: (Int) -> Void

    @State private var lastLetter: String?
    /// Where along the row the finger is, for the letter's bubble.
    @State private var fingerAt: CGFloat = 0

    /// The first title under each letter: worked out when the titles change, not on
    /// every redraw (a finger along the index redraws it at every letter it crosses).
    @State private var letters: [LiquidLetterEntry] = []

    var body: some View {
        // Fewer than three letters isn't worth an index.
        if letters.count >= 3 { row } else {
            Color.clear.frame(height: 0)
                .onChange(of: titles, initial: true) { letters = LiquidLetterEntry.index(titles) }
        }
    }

    private var row: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(letters, id: \.letter) { entry in
                    Text(entry.letter)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(lastLetter == entry.letter ? Color.black : .white.opacity(0.65))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(lastLetter == entry.letter ? Color.white : .clear, in: Capsule())
                }
            }
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !letters.isEmpty else { return }
                        let width = max(1, (geometry.size.width - 16) / CGFloat(letters.count))
                        let column = Int((value.location.x - 8) / width)
                        let entry = letters[min(letters.count - 1, max(0, column))]
                        fingerAt = min(max(value.location.x, 26), geometry.size.width - 26)
                        guard entry.letter != lastLetter else { return }
                        withAnimation(lastLetter == nil ? .spring(response: 0.25, dampingFraction: 0.7) : nil) {
                            lastLetter = entry.letter
                        }
                        UISelectionFeedbackGenerator().selectionChanged()
                        onJump(entry.index)
                    }
                    .onEnded { _ in withAnimation(.easeOut(duration: 0.15)) { lastLetter = nil } }
            )
            .overlay(alignment: .topLeading) {
                // Above the finger, where the finger doesn't cover it.
                if let lastLetter {
                    LiquidLetterBubble(letter: lastLetter)
                        .position(x: fingerAt, y: -34)
                }
            }
        }
        .frame(height: 30)
        .background(.white.opacity(0.07), in: Capsule())
        .onChange(of: titles) { letters = LiquidLetterEntry.index(titles) }
        .accessibilityElement()
        .accessibilityLabel(String(localized: "liquid.index"))
        .accessibilityIdentifier("liquid.stack.index")
    }
}

// MARK: - The Fold

/// A cover from the stack, turned over as the Gramophone turns a sleeve: the cover comes
/// forward to the middle of the page and flips round on its upright centre, with
/// perspective and a band of light crossing it; its back grows down into a card holding
/// the name, Play and Shuffle (for a song, Play, Play Next and Add to Queue) and the
/// track list; and the record, the cover on its label, slides partway up out of the
/// top. One driven value, `progress`, through AnimatableFold, so it can close from
/// wherever it's got to, each step running backwards.
struct LiquidFoldView: View {
    let item: LiquidStackItem
    /// The cover's place on screen (global) before it opened.
    let closedFrame: CGRect
    @ObservedObject var musicService: MusicService
    let onClose: () -> Void

    @Environment(\.liquidNavigator) private var navigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    /// The album's songs (for a song, its album's), as they load.
    @State private var tracks: [AppTrack]?
    /// The album a song is on.
    @State private var songAlbum: AppAlbum?
    @State private var color: Color = Color(white: 0.14)

    var body: some View {
        GeometryReader { geometry in
            let origin = geometry.frame(in: .global).origin
            let closed = closedFrame.offsetBy(dx: -origin.x, dy: -origin.y)
            AnimatableFold(progress: progress) { p in
                scene(p: p, closed: closed, layout: Layout(size: geometry.size))
            }
        }
        .ignoresSafeArea()
        .task {
            LiquidFoldState.shared.isOpen = true
            withAnimation(reduceMotion ? .easeOut(duration: 0.25)
                          : .spring(response: 0.9, dampingFraction: 0.86)) { progress = 1 }
            await load()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("liquid.fold")
        .accessibilityAction(.escape, close)
    }

    private func close() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        LiquidFoldState.shared.isOpen = false
        withAnimation(reduceMotion ? .easeIn(duration: 0.2) : .spring(response: 0.55, dampingFraction: 0.9)) {
            progress = 0
        } completion: {
            onClose()
        }
    }

    private func load() async {
        switch item {
        case .album(let album):
            if !album.preloadedTracks.isEmpty { tracks = album.tapeSongs(album.preloadedTracks) }
            async let found = LiquidColors.shared.color(for: album)
            let loaded = await navigator.loadTracks(album)
            if !loaded.isEmpty || tracks == nil { tracks = album.tapeSongs(loaded) }
            let tint = await found
            withAnimation(.easeInOut(duration: 0.3)) { color = tint }
        case .song(let track, _, _, _):
            async let found = LiquidColors.shared.color(for: track)
            if let album = navigator.album(track) {
                songAlbum = album
                tracks = await navigator.loadTracks(album)
            } else {
                tracks = [track]
            }
            let tint = await found
            withAnimation(.easeInOut(duration: 0.3)) { color = tint }
        }
    }

    // MARK: Scene

    /// Where everything ends up: the card across the middle of the page, with room above
    /// it for the record standing out of its top.
    private struct Layout {
        let size: CGSize
        let width: CGFloat
        let recordDiameter: CGFloat
        /// How much of the record stands out of the card.
        let recordOut: CGFloat
        /// The card turned over: square at first, as the cover was, then grown down.
        let square: CGRect
        let card: CGRect

        init(size: CGSize) {
            self.size = size
            width = min(size.width - 40, 420)
            recordDiameter = width * 0.7
            recordOut = recordDiameter * 0.44
            let top = max(size.height * 0.1, 54) + recordOut
            let height = min(size.height - top - max(size.height * 0.06, 34), width * 1.7)
            square = CGRect(x: (size.width - width) / 2, y: top, width: width, height: width)
            card = CGRect(x: square.minX, y: top, width: width, height: max(width, height))
        }
    }

    private func scene(p: CGFloat, closed: CGRect, layout: Layout) -> some View {
        let p = min(max(p, 0), 1)
        // Forward to the middle; over, half a turn; the back grows down; the record out.
        let travel = Self.smooth(Self.phase(p, 0, 0.45))
        let turn = Self.phase(p, 0.2, 0.7)
        let grow = Self.smooth(Self.phase(p, 0.45, 0.8))
        let slide = Self.smooth(Self.phase(p, 0.7, 1))
        let isOpen = p > 0.999
        let square = Self.lerp(closed, layout.square, travel)
        let rect = CGRect(x: square.minX, y: square.minY, width: square.width,
                          height: square.height + (layout.card.height - layout.square.height) * grow)
        let corner = 20 - 4 * travel
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let recordTop = rect.minY - layout.recordOut * (reduceMotion ? (isOpen ? 1 : Double(p)) : slide)
        return ZStack(alignment: .topLeading) {
            Color.black.opacity(0.78 * Double(p))
                .contentShape(Rectangle())
                .onTapGesture { if isOpen { close() } }
                .accessibilityHidden(true)

            // The record, behind the card, rising out of its top once it's turned over.
            LiquidFoldRecord(cover: item.cover, diameter: layout.recordDiameter)
                .position(x: rect.midX, y: recordTop + layout.recordDiameter / 2)
                .opacity(reduceMotion ? Double(p) : (turn >= 1 ? 1 : 0))
                .accessibilityHidden(true)

            if isOpen {
                // Settled: the back, flat, where it can be touched.
                backPanel(isInteractive: true)
                    .frame(width: rect.width, height: rect.height)
                    .clipShape(shape)
                    .position(x: rect.midX, y: rect.midY)
            } else if reduceMotion {
                backPanel(isInteractive: false)
                    .frame(width: layout.card.width, height: layout.card.height)
                    .clipShape(shape)
                    .opacity(Double(p))
                    .position(x: layout.card.midX, y: layout.card.midY)
                cover(p: p, corner: corner)
                    .frame(width: closed.width, height: closed.height)
                    .opacity(Double(1 - p))
                    .position(x: closed.midX, y: closed.midY)
            } else {
                // The cover turning over: its two faces swap edge-on, the back turned
                // round beforehand to read the right way. Never touched while it turns.
                ZStack {
                    cover(p: p, corner: corner)
                        .opacity(turn < 0.5 ? 1 : 0)
                    backPanel(isInteractive: false)
                        .clipShape(shape)
                        .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                        .opacity(turn >= 0.5 ? 1 : 0)
                }
                .frame(width: rect.width, height: rect.height)
                .rotation3DEffect(.degrees(Double(turn) * 180), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
                // Lifted off the page mid-turn, as a hand turning it over would.
                .scaleEffect(1 + 0.06 * sin(Double.pi * Double(turn)))
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .shadow(color: .black.opacity(0.45 * Double(p)), radius: 20, y: 10)
    }

    /// The cover's front, with a band of light that crosses it as it turns.
    private func cover(p: CGFloat, corner: CGFloat) -> some View {
        LiquidCover(source: item.cover)
            .overlay {
                Rectangle()
                    .fill(LinearGradient(stops: [.init(color: .white.opacity(0), location: 0.38),
                                                 .init(color: .white.opacity(0.6), location: 0.5),
                                                 .init(color: .white.opacity(0), location: 0.62)],
                                         startPoint: .leading, endPoint: .trailing))
                    .rotationEffect(.degrees(14))
                    .scaleEffect(2.2)
                    .offset(x: (-1.2 + 2.5 * p) * 200)
                    .blendMode(.screen)
                    .opacity(Double((1 - abs(2 * p - 1)) * 0.9))
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    // MARK: Panels

    /// The back of the cover: the name, what can be done, and the songs.
    private func backPanel(isInteractive: Bool) -> some View {
        let ground = color.liquidDeep
        return ZStack {
            // Solid underneath, so the record behind the card never shows through.
            ground
            LiquidCover(source: item.cover)
                .blur(radius: 30)
                .opacity(0.45)
            LinearGradient(colors: [ground.opacity(0.7), ground.opacity(0.97)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.system(size: 22, weight: .bold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        Text(item.subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 30, height: 30)
                            .background(.white.opacity(0.15), in: Circle())
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "liquid.fold.close"))
                    .accessibilityIdentifier("liquid.fold.close")
                }
                actions
                trackList
                    .padding(.horizontal, -12)
            }
            .padding(.top, 14)
            .padding(.horizontal, 16)
            .foregroundStyle(.white)
        }
        .allowsHitTesting(isInteractive)
        .accessibilityHidden(!isInteractive)
    }

    @ViewBuilder
    private var actions: some View {
        switch item {
        case .album(let album):
            if let tracks, !tracks.isEmpty {
                HStack(spacing: 10) {
                    actionButton(String(localized: album.isPodcast ? "spool.podcast.playLatest" : "detail.play"),
                                 symbol: "play.fill", isPrimary: true, id: "liquid.fold.play") {
                        navigator.play(album, tracks, 0, true)
                    }
                    if !album.isPodcast {
                        actionButton(String(localized: "detail.shuffle"), symbol: "shuffle", id: "liquid.fold.shuffle") {
                            navigator.play(album, tracks.shuffled(), 0, true)
                        }
                    }
                }
            } else if tracks == nil {
                ProgressView().tint(.white)
            }
        case .song(let track, let list, let index, let listName):
            HStack(spacing: 8) {
                actionButton(String(localized: "detail.play"), symbol: "play.fill", isPrimary: true, id: "liquid.fold.play") {
                    navigator.playSongs(list, index, false, listName)
                }
                actionButton(String(localized: "queue.action.playNext"), symbol: "text.insert", id: "liquid.fold.playNext") {
                    navigator.queue([track], .next, track.title)
                }
                actionButton(String(localized: "queue.action.addToQueue"), symbol: "text.append", id: "liquid.fold.addToQueue") {
                    navigator.queue([track], .last, track.title)
                }
            }
        }
    }

    private func actionButton(_ title: String, symbol: String, isPrimary: Bool = false, id: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(isPrimary ? Color.black : .white)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background {
                    if isPrimary {
                        Capsule().fill(.white)
                    } else {
                        Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1.3)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    /// The songs: the album's, or for a song, its album's with that song marked. Row for
    /// row as on the album's page: tapped, a song plays from there; swiped right or held,
    /// it offers Play Next and Add to Queue; what's playing has a waveform; a playlist's
    /// songs say who they're by; a show's episodes can't be queued, but are marked when
    /// downloaded, and held, offer to download or remove the download.
    private var trackList: some View {
        let album: AppAlbum? = {
            switch item {
            case .album(let album): return album
            case .song: return songAlbum
            }
        }()
        let marked: String? = {
            if case .song(let track, _, _, _) = item { return track.id }
            return nil
        }()
        let isPodcast = album?.isPodcast == true
        let playingID = musicService.currentEpisode?.id ?? musicService.currentTrack?.id
        let episodes = album?.podcast?.episodesNewestFirst
        return ZStack {
            if let tracks, !tracks.isEmpty {
                List {
                    ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                        Button {
                            if let album {
                                navigator.play(album, tracks, index, false)
                            } else {
                                navigator.playSongs(tracks, index, false, track.title)
                            }
                        } label: {
                            trackRow(track, index: index, isPlaying: track.id == playingID,
                                     isMarked: track.id == marked, showsArtist: album?.isMixtape == true,
                                     isPodcast: isPodcast,
                                     episode: episodes.flatMap { $0.indices.contains(index) ? $0[index] : nil })
                        }
                        .buttonStyle(.plain)
                        .modifier(QueueMenu(isEnabled: !isPodcast, track: track,
                                            episode: episodes.flatMap { $0.indices.contains(index) ? $0[index] : nil },
                                            onQueue: { navigator.queue($0, $1, $0.count == 1 ? $0[0].title : album?.tapeTitle ?? item.title) }))
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if !isPodcast {
                                Button { navigator.queue([track], .next, track.title) } label: {
                                    Label(String(localized: "queue.action.playNext"), systemImage: "text.insert")
                                }
                                .tint(RowSwipeAction.playNextTint)
                                Button { navigator.queue([track], .last, track.title) } label: {
                                    Label(String(localized: "queue.action.addToQueue"), systemImage: "text.append")
                                }
                                .tint(RowSwipeAction.addToQueueTint)
                            } else if let episode = episodes.flatMap({ $0.indices.contains(index) ? $0[index] : nil }) {
                                // An episode offers its download, as in every player.
                                ForEach(RowSwipeAction.download(episode)) { action in
                                    Button(action: action.action) { Label(action.title, systemImage: action.symbol) }
                                        .tint(action.tint)
                                }
                            }
                        }
                        .listRowBackground(track.id == marked ? Color.white.opacity(0.12) : Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 10))
                        .listRowSeparatorTint(.white.opacity(0.1))
                        .accessibilityIdentifier("liquid.fold.track.\(index)")
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 1)
            } else if tracks != nil {
                Text(String(localized: "spool.jcard.empty"))
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func trackRow(_ track: AppTrack, index: Int, isPlaying: Bool, isMarked: Bool,
                          showsArtist: Bool, isPodcast: Bool, episode: PodcastEpisode?) -> some View {
        HStack(spacing: 8) {
            Group {
                if isPlaying {
                    Image(systemName: "waveform").font(.system(size: 11, weight: .bold))
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .frame(width: 20, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                // An episode's marked if played before, or part way through.
                EpisodeTitle(track.title, episode: episode)
                    .font(.system(size: 14, weight: isPlaying || isMarked ? .bold : .regular))
                    .lineLimit(2)
                    .foregroundStyle(.white)
                if showsArtist {
                    Text(track.artistName)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if isPodcast {
                // Whether the episode is downloaded, as on every player.
                EpisodeDownloadMark(episodeID: track.id)
            }
            if track.duration > 0 {
                Text(AppHelpers.formatTime(track.duration))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(minHeight: 40)
        .contentShape(Rectangle())
    }

    // MARK: Geometry

    private static func smooth(_ t: CGFloat) -> CGFloat { t * t * (3 - 2 * t) }

    /// How far through the stretch from `start` to `end` the fold is, 0 to 1.
    private static func phase(_ p: CGFloat, _ start: CGFloat, _ end: CGFloat) -> CGFloat {
        min(1, max(0, (p - start) / (end - start)))
    }

    private static func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
               width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
    }
}

/// The record that slides out of a turned-over cover: near-black vinyl with its grooves
/// catching the light, and the cover for a label.
private struct LiquidFoldRecord: View {
    let cover: LiquidCover.Source
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.06))
            ForEach([0.96, 0.88, 0.8, 0.72, 0.64, 0.56, 0.48], id: \.self) { scale in
                Circle()
                    .stroke(.white.opacity(0.06), lineWidth: 0.6)
                    .frame(width: diameter * scale, height: diameter * scale)
            }
            Circle()
                .fill(AngularGradient(colors: [.white.opacity(0), .white.opacity(0.14), .white.opacity(0),
                                               .white.opacity(0), .white.opacity(0.1), .white.opacity(0)],
                                      center: .center, angle: .degrees(-30)))
            LiquidCover(source: cover)
                .frame(width: diameter * 0.36, height: diameter * 0.36)
                .clipShape(Circle())
            Circle()
                .fill(Color(white: 0.06))
                .frame(width: diameter * 0.03, height: diameter * 0.03)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
    }
}
