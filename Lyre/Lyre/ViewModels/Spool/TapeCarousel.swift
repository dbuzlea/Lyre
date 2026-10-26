//
//  TapeCarousel.swift
//  Lyre
//

import SwiftUI
import UIKit

// MARK: - Tape Carousel
//
// The library as a rack of cassettes running the full height of the screen. The front
// tape rests at the bottom, whole; the tapes still to come stand behind it, each tucked
// behind the next so only its label strip peeks out above, up to the top of the rack.
// Pulling down brings the next one forward, and tapes already passed slide away below.
// The rack reopens on whichever tape was last at the front.
// Swiping the front tape left (or tapping it) hands it to SpoolPlayerView, which flies it
// into the open door; tapping one in the rack brings it to the front first. Swiping the
// front tape right adds it to the end of the queue, the one-move shortcut. Holding a tape
// offers Play Next and Add to Queue, as holding an album or a song does on every player,
// and Show Songs, to start it at a particular song.
//
// Albums of more than one song stand in the rack in their clear plastic cases, the cover
// showing through the lid; tapping one, wherever it stands, or swiping it left opens the
// case rather than playing the whole album (see CassetteCaseView). Singles,
// EPs and one-song albums stand bare: singles and EPs as cassingles in a coloured shell
// (see TapeFormat).
//
// The rack is drawn rather than scrolled: `position` is the index of the front tape
// (fractional mid-pull), and every tape's place, size and shade follow from how many
// slots it stands behind the front. A lazy scroll stack only builds the tapes whose
// scroll slots are on screen, which left the rack a few tapes tall; drawing it directly
// fills the height, and only the tapes that can be seen are built.
//
// One drag drives both directions: it commits to an axis on its first few points of
// movement, so a sideways swipe on the front tape never scrolls the rack and a pull
// never swipes.
//
// Every tape carries a filing tab with the letter it files under, coloured for that
// letter (see SectionTab), so a run of tapes under one letter reads as one colour and
// the change of colour marks where the next letter starts. The header shows the front
// tape's letter too.
//
// The Gramophone's record crate is this rack too, drawing records in their sleeves
// instead of tapes (`card`, `cardAspectRatio`): flipping through a crate is the same
// gesture as pulling through a rack. Every sleeve opens to choose a song from
// (`opensToChoose`), as an album's case does here.
//
// Down the rack's side runs an A–Z index (ShelfIndexStrip): a finger run down it brings
// the first tape filed under each letter to the front, for a large library.
//
// The rack holds one shelf at a time, albums, mixtapes or podcasts, picked with the
// dividers above it (see ShelfDividers). A podcast always opens its case, to choose an
// episode, and can't be swiped right into the queue. SpoolPlayerView rebuilds the rack for each shelf, so each opens
// on its own front tape.
//
// Scrolling: the rack follows the finger point for point. Letting go hands the rack to
// one glide (see `glide`): a critically damped spring that leaves at the finger's speed
// and comes to rest, without bouncing, on the tape the flick would carry it to. There is
// no separate coast and settle to join, so nothing jolts as the rack slows. A tap that
// brings a tape forward glides the same way.
//
// The glide is stepped by the display (RackMotion, a CADisplayLink) and works out where
// the rack is for the moment each frame appears, so it stays in step with the screen,
// up to 120 Hz. Because `position` is set every frame rather than animated to a target,
// a finger can catch the rack mid-glide exactly where it is.
//
// Where the rack was left is saved once it comes to rest, not as each tape passes:
// `frontID` is stored by SpoolPlayerView, and writing it mid-scroll redrew the whole
// player on every tape. A selection tick marks each tape that passes the front.

struct TapeCarousel: View {
    let albums: [AppAlbum]
    /// Said when the shelf has no tapes.
    var emptyText = String(localized: "spool.shelf.empty")
    /// A button offered under the empty text: its title and action.
    var emptyAction: (title: String, action: () -> Void)?
    /// Draws an item. Nil draws the Spool's tapes and cases.
    var card: ((AppAlbum, CGSize) -> AnyView)?
    /// Width : height of an item.
    var cardAspectRatio: CGFloat = CassetteView.aspectRatio
    /// Whether tapping an item, or swiping it left, opens it to choose a song from
    /// rather than loading the whole of it.
    var opensToChoose: (AppAlbum) -> Bool = { $0.comesInCase }
    /// Swiping an item left always loads the whole of it, even one that opens to choose
    /// from when tapped — as the Gramophone's records do.
    var swipeLeftLoads = false
    /// The line under the item's name in the header. Nil uses the Spool's.
    var byline: ((AppAlbum) -> String)?
    /// The tape currently flying into the door, hidden here so it isn't drawn twice.
    let hiddenID: String?
    /// The chosen album and the card's frame in SpoolPlayerView's coordinate space.
    let onInsert: (AppAlbum, CGRect) -> Void
    /// Opens the album's track list. The frame is where the front tape sits, for the
    /// flight if a song is chosen.
    let onShowSongs: (AppAlbum, CGRect) -> Void
    /// Queues the whole album: next, or at the end.
    let onQueue: (AppAlbum, QueuePlacement) -> Void
    let onClose: () -> Void
    /// Whether the header has a button to put the rack away. Not on an open iPhone Duo,
    /// where the rack stands beside the deck for as long as the phone is open.
    var showsClose = true
    /// The tape at the front. The rack opens on it and keeps it current, so coming back
    /// finds the rack where it was left.
    @Binding var frontID: String?

    /// Index of the tape at the front, fractional mid-pull.
    @State private var position: CGFloat = 0
    /// The vertical translation already applied to `position` during this pull.
    @State private var lastPull: CGFloat = 0
    @State private var dragAxis: Axis?
    /// The glide after a release, stopped when a finger lands on the rack.
    @State private var motion = RackMotion()
    /// How far the front tape has been swiped sideways.
    @State private var swipeX: CGFloat = 0
    /// The rack's frame in SpoolPlayerView's coordinate space.
    @State private var rackFrame: CGRect = .zero
    @Environment(\.spoolTheme) private var theme

    /// Movement it takes to tell a swipe from a pull.
    private static let axisSlop: CGFloat = 8
    /// Fraction of a flick's speed kept per 60 fps frame: the Artwork Carousel's friction.
    /// Decides how far a flick carries the rack.
    private static let friction: CGFloat = 0.965
    /// How quickly a glide settles, as a spring's angular frequency: from a long flick's
    /// gentle run-out (`slowest`) to a short snap onto the nearest tape (`fastest`).
    private static let slowestGlide: CGFloat = 4
    private static let fastestGlide: CGFloat = 19

    /// Fewer tapes than this are quick enough to pull through, and get no index.
    private static let indexMinimumItems = 12

    /// How far left a release must be, or be heading, to count as a swipe.
    private static let commitDistance: CGFloat = 90
    private static let commitVelocityDistance: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if albums.isEmpty {
                VStack(spacing: 14) {
                    Text(emptyText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .font(.system(size: 15))
                        .foregroundStyle(theme.ink.opacity(0.7))
                    if let emptyAction {
                        Button(emptyAction.title, action: emptyAction.action)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.keySymbol)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(theme.keyLight.opacity(0.9), in: Capsule())
                            .accessibilityIdentifier("spool.shelf.emptyAction")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 8) {
                    GeometryReader { geometry in
                        rack(Rack(size: geometry.size, count: albums.count, aspectRatio: cardAspectRatio))
                    }
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named(SpoolPlayerView.coordinateSpace))
                    } action: { rackFrame = $0 }

                    // The A–Z index down the rack's side, in the filing tabs' colours.
                    if albums.count >= Self.indexMinimumItems {
                        ShelfIndexStrip(titles: albums.map(\.title), currentIndex: frontIndex,
                                        axis: .vertical, style: .spool(theme),
                                        // The rack ticks as each tape reaches the front.
                                        ticks: false, accessibilityID: "spool.index") { index in
                            jump(to: index)
                        }
                        .frame(width: 20)
                        .transition(.opacity)
                    }
                }
            }
        }
    }

    private func rack(_ rack: Rack) -> some View {
        let front = frontIndex
        return ZStack(alignment: .top) {
            ForEach(rack.visibleIndices(around: position), id: \.self) { index in
                let album = albums[index]
                let slots = CGFloat(index) - position
                let isFront = index == front
                cardView(album, rack.cardSize)
                    // Holding a tape queues it, as holding an album does on every player.
                    .contextMenu { holdMenu(album, index, rack) }
                    // Stuck on over the top corner, sticking out a little past the edge;
                    // short enough to show above the tape in front.
                    .overlay(alignment: .topLeading) {
                        SectionTab(letter: AppHelpers.firstLetter(of: album.title),
                                   height: rack.cardSize.height * 0.19)
                            .offset(x: -rack.cardSize.width * 0.035, y: rack.cardSize.height * 0.022)
                    }
                    // A translucent black shape darkens far tapes for the cost of one
                    // fill; a brightness filter would re-render the whole tape each frame.
                    .overlay(
                        RoundedRectangle(cornerRadius: rack.cardSize.width * 0.04)
                            .fill(.black.opacity(rack.shade(slots)))
                            .allowsHitTesting(false)
                    )
                    .offset(x: isFront ? swipeX : 0)
                    .rotationEffect(.degrees(isFront ? Double(swipeX) / 60 : 0), anchor: .trailing)
                    .scaleEffect(rack.scale(slots), anchor: .top)
                    .offset(y: rack.y(slots))
                    .opacity(rack.opacity(slots))
                    .opacity(album.id == hiddenID ? 0 : 1)
                    .zIndex(Double(-slots))
                    .onTapGesture {
                        // A tap on a coasting rack just stops it, as on any scroll view.
                        if stopCoasting() { return }
                        if opensToChoose(album) {
                            // A cased album opens, to show its songs and its tape.
                            showSongs(index, rack)
                        } else if !isFront {
                            bringForward(index)
                        } else {
                            insert(album, rack)
                        }
                    }
                    .accessibilityElement()
                    .accessibilityLabel([album.tapeTitle, album.caseByline, album.tapeDetail]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(String(localized: "spool.carousel.insert"))
                    .accessibilityIdentifier("spool.tape.\(album.id)")
                    // VoiceOver can insert any tape directly; it doesn't see the stacking.
                    .accessibilityAction { insert(album, rack) }
                    .accessibilityAction(named: String(localized: "spool.carousel.showSongs")) {
                        showSongs(index, rack)
                    }
                    .accessibilityActions {
                        if !album.isPodcast {
                            Button(String(localized: "queue.action.playNext")) { onQueue(album, .next) }
                            Button(String(localized: "queue.action.addToQueue")) { onQueue(album, .last) }
                        }
                    }
            }

            // Shows from under the front tape as it is swiped right.
            if swipeX > 0, !albums[front].isPodcast {
                Label(String(localized: "queue.action.addToQueue"), systemImage: "text.append")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(theme.ink.opacity(0.15), in: Capsule())
                    .scaleEffect(swipeX >= Self.commitDistance ? 1.06 : 1)
                    .opacity(min(1, swipeX / Self.commitDistance))
                    .frame(width: rack.size.width, height: rack.cardSize.height, alignment: .leading)
                    .offset(y: rack.frontY)
                    .zIndex(-1000)
                    .allowsHitTesting(false)
                    .animation(.spring(response: 0.2, dampingFraction: 0.7), value: swipeX >= Self.commitDistance)
            }
        }
        .frame(width: rack.size.width, height: rack.size.height, alignment: .top)
        .contentShape(Rectangle())
        .gesture(drag(rack))
        .sensoryFeedback(.selection, trigger: frontIndex)
        .onAppear {
            // Open on the tape last at the front, if it's still in the library.
            // Without animation: it opens there, rather than scrolling there while it
            // slides in.
            if let frontID, let index = albums.firstIndex(where: { $0.id == frontID }) {
                withTransaction(Transaction(animation: nil)) { position = CGFloat(index) }
            }
        }
        .onDisappear {
            // Closed mid-glide: remember the tape it was heading for.
            if motion.isRunning { motion.stop(); position = clamped(position.rounded()) }
            rememberFront()
        }
        .accessibilityScrollAction { edge in
            let step: CGFloat = edge == .top ? 1 : edge == .bottom ? -1 : 0
            withAnimation { position = clamped((position + step * 5).rounded()) }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            if let frontAlbum {
                SectionTab(letter: AppHelpers.firstLetter(of: frontAlbum.title), height: 34)
                    .padding(.top, 2)
                    .animation(.easeInOut(duration: 0.15), value: frontAlbum.id)
                    .accessibilityHidden(true)
            }
            // Names the tape at the front, changing as the rack moves. An empty rack
            // has nothing to name, so it says what the rack is instead.
            VStack(alignment: .leading, spacing: 2) {
                Text(frontAlbum?.tapeTitle ?? String(localized: "spool.shelf.title"))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(frontAlbum.map(headerByline) ?? String(localized: "spool.carousel.hint"))
                    .font(.system(size: 15))
                    .foregroundStyle(theme.ink.opacity(0.75))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.15), value: frontAlbum?.id)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("spool.carousel.nowShowing")
            Spacer(minLength: 8)
            if showsClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.keySymbol)
                        .frame(width: 34, height: 34)
                        .background(theme.keyLight.opacity(0.75), in: Circle())
                }
                .accessibilityLabel(String(localized: "spool.carousel.close"))
            }
        }
    }

    // MARK: - Actions

    private var frontIndex: Int { Int(clamped(position).rounded()) }

    private var frontAlbum: AppAlbum? { albums.isEmpty ? nil : albums[frontIndex] }

    private func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), CGFloat(albums.count - 1))
    }

    /// The front tape's frame in SpoolPlayerView's space, where a flight sets off from.
    private func frontFrame(_ rack: Rack) -> CGRect {
        CGRect(x: rackFrame.minX + swipeX, y: rackFrame.minY + rack.frontY,
               width: rack.cardSize.width, height: rack.cardSize.height)
    }

    private func insert(_ album: AppAlbum, _ rack: Rack) {
        onInsert(album, frontFrame(rack))
    }

    @ViewBuilder
    private func cardView(_ album: AppAlbum, _ size: CGSize) -> some View {
        if let card {
            card(album, size)
        } else {
            TapeCard(album: album, size: size)
                .equatable()
        }
    }

    private func headerByline(_ album: AppAlbum) -> String {
        byline?(album) ?? tapeByline(album)
    }

    /// "Artist · Single", "Artist · 12 songs", "Made by Sam · C90 · 23 songs".
    private func tapeByline(_ album: AppAlbum) -> String {
        [album.caseByline, album.tapeDetail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func showSongs(_ index: Int, _ rack: Rack) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        bringForward(index)
        onShowSongs(albums[index], frontFrame(rack))
    }

    /// What holding a tape offers.
    @ViewBuilder
    private func holdMenu(_ album: AppAlbum, _ index: Int, _ rack: Rack) -> some View {
        if !album.isPodcast {
            Button { onQueue(album, .next) } label: {
                Label(String(localized: "queue.action.playNext"), systemImage: "text.insert")
            }
            Button { onQueue(album, .last) } label: {
                Label(String(localized: "queue.action.addToQueue"), systemImage: "text.append")
            }
        }
        Button { showSongs(index, rack) } label: {
            Label(String(localized: "spool.carousel.showSongs"), systemImage: "music.note.list")
        }
    }

    /// Puts the tape at `index` at the front at once, from the index down the side.
    private func jump(to index: Int) {
        stopCoasting(settle: false)
        withTransaction(Transaction(animation: nil)) { position = CGFloat(index) }
        rememberFront()
    }

    private func bringForward(_ index: Int) {
        glide(velocity: 0, to: CGFloat(index))
    }

    /// Saves the tape at the front, so the rack reopens on it.
    private func rememberFront() {
        guard albums.indices.contains(frontIndex), frontID != albums[frontIndex].id else { return }
        frontID = albums[frontIndex].id
    }

    private func drag(_ rack: Rack) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                if dragAxis == nil {
                    // A finger on the rack catches it wherever it has coasted to.
                    stopCoasting(settle: false)
                    guard max(abs(dx), abs(dy)) >= Self.axisSlop else { return }
                    if abs(dx) > abs(dy) * 1.3, rack.frontRect.contains(value.startLocation),
                       position == position.rounded() {
                        dragAxis = .horizontal
                    } else {
                        dragAxis = .vertical
                        // Start from here, so the slop doesn't land as a jump.
                        lastPull = dy
                    }
                }
                switch dragAxis {
                case .horizontal:
                    // Left towards the door, right to queue. Right runs off the screen's
                    // edge, so it gives less ground past the point that counts.
                    // A podcast can't be queued: right only gives a little, then holds.
                    if dx > 0, albums[frontIndex].isPodcast {
                        swipeX = min(dx, 60) * 0.3
                    } else {
                        swipeX = dx < 0 || dx < Self.commitDistance
                            ? dx : Self.commitDistance + (dx - Self.commitDistance) * 0.3
                    }
                case .vertical:
                    let delta = (dy - lastPull) / rack.pullDistance
                    lastPull = dy
                    // Past either end the rack gives a little, then resists.
                    let isPastEnd = clamped(position) != position || clamped(position + delta) != position + delta
                    withTransaction(Transaction(animation: nil)) {
                        position += isPastEnd ? delta * 0.3 : delta
                    }
                case nil:
                    break
                }
            }
            .onEnded { value in
                defer { dragAxis = nil; lastPull = 0 }
                switch dragAxis {
                case .horizontal:
                    let width = value.translation.width
                    let predicted = value.predictedEndTranslation.width
                    let album = albums[frontIndex]
                    if !album.isPodcast,
                       width > Self.commitDistance || (width > 0 && predicted > Self.commitVelocityDistance) {
                        // Queued: the tape goes back in the rack.
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onQueue(album, .last)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { swipeX = 0 }
                    } else if width < -Self.commitDistance || predicted < -Self.commitVelocityDistance,
                              opensToChoose(album), !swipeLeftLoads {
                        // A case opens to be chosen from; it never plays the whole album unopened.
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { swipeX = 0 }
                        showSongs(frontIndex, rack)
                    } else if width < -Self.commitDistance || predicted < -Self.commitVelocityDistance {
                        // Hand over where the card is now; the flying copy takes it from here.
                        insert(album, rack)
                        var reset = Transaction()
                        reset.disablesAnimations = true
                        withTransaction(reset) { swipeX = 0 }
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { swipeX = 0 }
                    }
                case .vertical:
                    glide(velocity: value.velocity.height / rack.pullDistance)
                case nil:
                    // Lifted before choosing an axis: a caught rack settles where it is.
                    if position != position.rounded() { glide(velocity: 0) }
                }
            }
    }

    // MARK: - Momentum

    /// Glides the rack from where it is, leaving at `velocity` tapes a second, to rest on
    /// `target`, or else on the tape a flick at that speed would carry it to.
    ///
    /// A critically damped spring: it starts at exactly the finger's speed, so letting go
    /// doesn't jolt, and comes to rest without overshooting. For a flick its stiffness is
    /// matched to the speed and the distance (`2 · speed / distance`), which makes the
    /// rack slow from the first frame rather than speed up or stall; a nudge, or a tape
    /// brought forward, gets a quick snap. Past either end it springs back to the end.
    private func glide(velocity: CGFloat, to target: CGFloat? = nil) {
        motion.stop()
        let start = position
        // How far a flick would carry the rack with the Artwork Carousel's friction.
        let reach = velocity / (-log(Self.friction) * 60)
        let end = target ?? clamped((start + reach).rounded())
        let distance = end - start
        guard abs(distance) > 0.001 || abs(velocity) > 0.01 else {
            position = end
            rememberFront()
            return
        }

        let headingThere = distance * velocity > 0
        let stiffness = headingThere && abs(distance) > 0.001
            ? min(max(2 * abs(velocity) / abs(distance), Self.slowestGlide), Self.fastestGlide)
            : Self.fastestGlide
        let spring = Spring(response: 2 * .pi / stiffness, dampingRatio: 1)
        let duration = spring.settlingDuration(target: distance, initialVelocity: velocity, epsilon: 0.002)

        motion.run { elapsed in
            guard elapsed < duration else {
                withTransaction(Transaction(animation: nil)) { position = end }
                rememberFront()
                return false
            }
            let travelled = spring.value(target: distance, initialVelocity: velocity, time: elapsed)
            withTransaction(Transaction(animation: nil)) { position = start + travelled }
            return true
        }
    }

    /// Stops a glide in progress, settling the nearest tape at the front unless a finger
    /// is taking over. Returns whether there was one.
    @discardableResult
    private func stopCoasting(settle shouldSettle: Bool = true) -> Bool {
        guard motion.isRunning else { return false }
        motion.stop()
        if shouldSettle { glide(velocity: 0) }
        return true
    }
}

// MARK: - Motion

/// Steps a glide once per frame, in time with the display. Each step is handed the time
/// since the glide began, as of when that frame will appear, and says whether to go on.
@MainActor
private final class RackMotion: NSObject {
    private var link: CADisplayLink?
    private var step: ((TimeInterval) -> Bool)?
    private var startTime: CFTimeInterval?

    var isRunning: Bool { link != nil }

    func run(_ step: @escaping (TimeInterval) -> Bool) {
        stop()
        self.step = step
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        step = nil
        startTime = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        // Timed from the frame before the first one drawn, so the first step already moves.
        let start = startTime ?? link.timestamp
        startTime = start
        if step?(link.targetTimestamp - start) == false { stop() }
    }
}

// MARK: - Rack Geometry

/// Where each tape stands, given how many slots it is behind the front tape: 0 is the
/// front, positive is further back up the rack, negative is already passed.
private struct Rack {
    /// The area the rack fills.
    let size: CGSize
    let count: Int
    /// Width : height of an item.
    var aspectRatio: CGFloat = CassetteView.aspectRatio

    /// Room under the front tape.
    static let bottomInset: CGFloat = 4

    var cardSize: CGSize { CGSize(width: size.width, height: size.width / aspectRatio) }
    /// The front tape's top edge.
    var frontY: CGFloat { max(0, size.height - cardSize.height - Self.bottomInset) }
    var frontRect: CGRect { CGRect(origin: CGPoint(x: 0, y: frontY), size: cardSize) }

    /// How many tapes stand behind the front one: as many as reach the top of the rack
    /// with their label strips showing, or the whole library if it is smaller.
    var depth: Int {
        let fit = Int(frontY / (cardSize.height * 0.22))
        return max(1, min(fit, count - 1))
    }
    /// How much of each tape shows above the one in front. Spread out so the rack always
    /// reaches the top, which shows more of each tape in a small library.
    var peek: CGFloat { min(cardSize.height * 0.5, frontY / CGFloat(depth)) }
    /// Finger travel that moves the rack by one tape: the front tape tracks the finger.
    var pullDistance: CGFloat { cardSize.height * 0.9 }

    func y(_ slots: CGFloat) -> CGFloat {
        slots >= 0 ? frontY - slots * peek : frontY - slots * pullDistance
    }

    /// Tapes further back are a little smaller and darker.
    func scale(_ slots: CGFloat) -> CGFloat { 1 - recess(slots) * 0.14 }
    /// Opacity of the black laid over a tape.
    func shade(_ slots: CGFloat) -> CGFloat { recess(slots) * 0.3 }

    func opacity(_ slots: CGFloat) -> CGFloat {
        if slots < 0 { return max(0, 1 + slots * 1.5) }
        let back = CGFloat(depth)
        return slots > back ? max(0, 1 - (slots - back)) : 1
    }

    /// The tapes worth building: the rack's depth behind the front, plus one at each end
    /// so tapes fade in rather than appear.
    func visibleIndices(around position: CGFloat) -> [Int] {
        let low = max(0, Int(position.rounded(.down)) - 1)
        let high = min(count - 1, Int(position.rounded(.up)) + depth + 1)
        return low <= high ? Array(low...high) : []
    }

    /// 0 at the front, 1 at the back of the rack.
    private func recess(_ slots: CGFloat) -> CGFloat {
        min(max(slots, 0), CGFloat(depth)) / CGFloat(depth)
    }
}

// MARK: - Card

/// Equatable so the rack's per-frame updates, which only move and shade cards from
/// outside, never rebuild a tape.
private struct TapeCard: View, Equatable {
    let album: AppAlbum
    let size: CGSize

    var body: some View {
        Group {
            if album.comesInCase {
                ClosedCaseFront(album: album)
            } else {
                CassetteShell(
                    transport: CassetteShell.resting,
                    title: album.tapeTitle,
                    size: size,
                    labelArt: .album(album),
                    format: album.tapeFormat,
                    trackCount: album.tapeTrackCount,
                    blank: album.tapeBlank
                )
            }
        }
        .frame(width: size.width, height: size.height)
        // Cast by a plain shape behind the tape: far cheaper to draw than a shadow of
        // the whole tape, and the same outline.
        .background(
            RoundedRectangle(cornerRadius: size.width * 0.04)
                .fill(.black)
                .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: -2)
        )
    }
}

// MARK: - Shelves

/// What the rack is showing.
enum SpoolShelf: String, CaseIterable, Identifiable {
    case albums
    case mixtapes
    case podcasts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .albums:   return String(localized: "spool.shelf.albums")
        case .mixtapes: return String(localized: "spool.shelf.mixtapes")
        case .podcasts: return String(localized: "spool.shelf.podcasts")
        }
    }
}

/// The dividers along the top of the tape drawer, one per shelf. The shelf in use stands
/// up in front, lit; the others sit back behind it.
struct ShelfDividers: View {
    @Binding var shelf: SpoolShelf
    /// What each divider says; the Spool's names by default.
    var title: (SpoolShelf) -> String = { $0.title }
    /// Opens podcast search; offered beside the dividers on the podcast shelf.
    var onFindShows: () -> Void = {}
    @Environment(\.spoolTheme) private var theme

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(SpoolShelf.allCases) { option in
                let isSelected = option == shelf
                Button {
                    guard !isSelected else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.easeInOut(duration: 0.22)) { shelf = option }
                } label: {
                    Text(title(option).uppercased())
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(0.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(theme.keySymbol.opacity(isSelected ? 1 : 0.6))
                        // The dividers share the drawer's width.
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 3)
                        .padding(.top, isSelected ? 9 : 6)
                        .padding(.bottom, 6)
                        .background(
                            UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8)
                                .fill(theme.keyLight.opacity(isSelected ? 0.95 : 0.45))
                                .shadow(color: .black.opacity(isSelected ? 0.25 : 0), radius: 2, x: 0, y: -1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("spool.shelf.\(option.rawValue)")
            }
            if shelf == .podcasts {
                Button(action: onFindShows) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(theme.keySymbol)
                        .frame(width: 30, height: 26)
                        .background(theme.keyLight.opacity(0.75), in: Capsule())
                        .padding(.bottom, 4)
                }
                .accessibilityLabel(String(localized: "podcasts.search"))
                .accessibilityIdentifier("spool.shelf.findShows")
                .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            // The drawer's front edge, which the dividers stand in.
            Rectangle()
                .fill(theme.keyLight.opacity(0.95))
                .frame(height: 2)
        }
    }
}

// MARK: - Section Tab

/// A colour-coded filing label: the letter a tape files under, in that letter's colour.
/// The colours follow the filing-label convention of thirteen colours, used once for
/// A–M and again for N–Z, so neighbouring letters always differ and the colour changes
/// at every new letter. Anything that doesn't start with a letter files under "#".
struct SectionTab: View {
    let letter: String
    let height: CGFloat

    var body: some View {
        let colour = Self.colour(for: letter)
        Text(letter)
            .font(.system(size: height * 0.6, weight: .heavy, design: .rounded))
            .foregroundStyle(colour.ink)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .frame(width: height * 0.9, height: height)
            .background(
                RoundedRectangle(cornerRadius: height * 0.2)
                    .fill(colour.fill)
                    // A glossy sticker: light along the top.
                    .overlay(
                        RoundedRectangle(cornerRadius: height * 0.2)
                            .fill(LinearGradient(colors: [.white.opacity(0.3), .clear],
                                                 startPoint: .top, endPoint: .center))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: height * 0.2)
                            .strokeBorder(.black.opacity(0.2), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
            .accessibilityHidden(true)
    }

    /// The thirteen label colours, with the ink that reads on each. Warm and cool take
    /// turns, so each letter's colour stands well apart from the letters beside it.
    private static let palette: [(fill: Color, ink: Color)] = [
        (Color(red: 0.84, green: 0.17, blue: 0.16), .white),               // A red
        (Color(red: 0.13, green: 0.32, blue: 0.75), .white),               // B blue
        (Color(red: 0.98, green: 0.82, blue: 0.16), Color(white: 0.15)),   // C yellow
        (Color(red: 0.49, green: 0.27, blue: 0.72), .white),               // D purple
        (Color(red: 0.12, green: 0.55, blue: 0.27), .white),               // E green
        (Color(red: 0.95, green: 0.50, blue: 0.10), .white),               // F orange
        (Color(red: 0.36, green: 0.70, blue: 0.93), Color(white: 0.12)),   // G sky
        (Color(red: 0.93, green: 0.42, blue: 0.66), .white),               // H pink
        (Color(red: 0.08, green: 0.62, blue: 0.62), .white),               // I teal
        (Color(red: 0.52, green: 0.33, blue: 0.20), .white),               // J brown
        (Color(red: 0.55, green: 0.78, blue: 0.24), Color(white: 0.12)),   // K lime
        (Color(red: 0.16, green: 0.16, blue: 0.18), .white),               // L black
        (Color(red: 0.62, green: 0.63, blue: 0.65), Color(white: 0.12)),   // M grey
    ]

    static func colour(for letter: String) -> (fill: Color, ink: Color) {
        // Accented letters take their base letter's colour: É files with E.
        let base = letter.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        guard let scalar = base.unicodeScalars.first, letter != "#" else {
            return (Color(white: 0.92), Color(white: 0.2))
        }
        let value = Int(scalar.value)
        let index = (97...122).contains(value) ? value - 97 : value
        return palette[index % palette.count]
    }
}
