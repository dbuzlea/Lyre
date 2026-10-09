//
//  SpoolTour.swift
//  Lyre
//

import SwiftUI

// MARK: - Spool Tour
//
// How to use the Spool, acted out. Each lesson plays on a miniature deck: a ghost
// fingertip, like the one that demonstrates the wheel in onboarding, taps, drags and
// holds where a real finger would, and the deck answers as the real one does — the
// door swings open on the rack, a tape flies into the door, the reels turn.
//
// Onboarding shows the tour when the Spool is chosen, and the owner's manual keeps it
// in its Tutorial section, so it can be watched again later. Both use SpoolTourPager,
// the shared TourPager with the Spool's lessons: one lesson at a time, with Previous,
// Next and Play Again.
//
// The miniature is drawn on a fixed 300 × 240 canvas and scaled to fit, so a lesson's
// script can place the finger in plain points. It is a sketch of the original design
// in the chosen finish; the gestures are the same on the slim.
//
// As in onboarding, each lesson plays once and stops — an endless animation keeps the
// app from going idle, which UI tests wait for — and Reduce Motion skips the
// demonstration and leaves the words to teach it.

enum SpoolLesson: Int, CaseIterable, Identifiable, TourLesson {
    case openRack
    case browse
    case loadTape
    case openCase
    case shelves
    case keys
    case wind
    case holdDoor
    case upNext
    case podcasts
    case manual

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .openRack: return String(localized: "spool.tour.openRack.title")
        case .browse:   return String(localized: "spool.tour.browse.title")
        case .loadTape: return String(localized: "spool.tour.loadTape.title")
        case .openCase: return String(localized: "spool.tour.openCase.title")
        case .shelves:  return String(localized: "spool.tour.shelves.title")
        case .keys:     return String(localized: "spool.tour.keys.title")
        case .wind:     return String(localized: "spool.tour.wind.title")
        case .holdDoor: return String(localized: "spool.tour.holdDoor.title")
        case .upNext:   return String(localized: "spool.tour.upNext.title")
        case .podcasts: return String(localized: "spool.tour.podcasts.title")
        case .manual:   return String(localized: "spool.tour.manual.title")
        }
    }

    var detail: String {
        switch self {
        case .openRack: return String(localized: "spool.tour.openRack.detail")
        case .browse:   return String(localized: "spool.tour.browse.detail")
        case .loadTape: return String(localized: "spool.tour.loadTape.detail")
        case .openCase: return String(localized: "spool.tour.openCase.detail")
        case .shelves:  return String(localized: "spool.tour.shelves.detail")
        case .keys:     return String(localized: "spool.tour.keys.detail")
        case .wind:     return String(localized: "spool.tour.wind.detail")
        case .holdDoor: return String(localized: "spool.tour.holdDoor.detail")
        case .upNext:   return String(localized: "spool.tour.upNext.detail")
        case .podcasts: return String(localized: "spool.tour.podcasts.detail")
        case .manual:   return String(localized: "spool.tour.manual.detail")
        }
    }
}

// MARK: - Pager

/// The Spool's lessons in the shared tour pager (see TourPager).
struct SpoolTourPager: View {
    enum Appearance {
        /// White on onboarding's dark background.
        case onboarding
        /// Ink on the owner's manual's paper.
        case manual
    }

    let theme: SpoolTheme
    var appearance: Appearance = .onboarding
    var lessons: [SpoolLesson] = SpoolLesson.allCases

    var body: some View {
        TourPager(lessons: lessons, ink: appearance == .onboarding ? .white : SpoolPalette.labelInk) { lesson, run in
            SpoolTourScene(lesson: lesson, theme: theme, run: run)
        }
    }
}

// MARK: - Scene

/// One lesson on the miniature deck. Starts from the lesson's opening state and plays
/// its script once; `run` changing plays it again from the start.
struct SpoolTourScene: View {
    let lesson: SpoolLesson
    let theme: SpoolTheme
    var run = 0

    @State private var deck = TourDeck()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let canvas = CGSize(width: 300, height: 240)

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / Self.canvas.width
            TourDeckView(deck: deck, theme: theme)
                .frame(width: Self.canvas.width, height: Self.canvas.height)
                .scaleEffect(scale, anchor: .topLeading)
        }
        .aspectRatio(Self.canvas.width / Self.canvas.height, contentMode: .fit)
        .frame(maxWidth: 360)
        .task(id: run) {
            withTransaction(Transaction(animation: nil)) { deck = TourDeck(opening: lesson) }
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .milliseconds(500))
            await TourScript(deck: $deck).play(lesson)
        }
    }
}

// MARK: - Deck State

/// Everything the miniature can show, in canvas points where it's a position.
struct TourDeck {
    var doorOpen = false
    var rackShown = false
    /// The rack's position: the index of the front tape, fractional mid-pull.
    var rackPosition: CGFloat = 0
    /// 0 albums, 1 mixtapes, 2 podcasts.
    var shelf = 0
    /// A tape flying from the rack's front into the door: 0 in the rack, 1 seated.
    var flight: CGFloat?
    var tapeSeated = true
    var tapeTitle = "Blonde"
    var tapeShelf = 0
    /// Drives the reels: seconds into the side.
    var tapeTime: TimeInterval = 42
    var playLatched = false
    /// The key held down: 0 play, 1 fast-forward, 2 rewind, 3 eject.
    var pressedKey: Int?
    var podcastMode = false
    var speed = "1×"
    var caseOpen: CGFloat = 0
    /// Where the case comes from: the rack's front tape, or the door.
    var caseFromDoor = false
    var caseHighlight: Int?
    var trayProgress: CGFloat = 0
    var pulledLabel: Int?
    var sheetShown = false
    var holdRing: CGFloat = 0
    var finger: CGPoint?
    var fingerPressed = false

    init() {}

    /// Where each lesson starts.
    init(opening lesson: SpoolLesson) {
        switch lesson {
        case .openRack, .keys, .manual:
            break
        case .browse, .shelves, .openCase:
            doorOpen = true
            rackShown = true
            tapeSeated = false
        case .loadTape:
            doorOpen = true
            rackShown = true
            tapeSeated = false
        case .wind, .holdDoor, .upNext:
            playLatched = true
        case .podcasts:
            podcastMode = true
            playLatched = true
            tapeTitle = "Cassette Culture"
            tapeShelf = 2
            tapeTime = 754
        }
    }

    /// The counter: elapsed, or for a podcast what's left of a 32-minute episode.
    var counterText: String {
        let shown = podcastMode ? max(0, 1920 - tapeTime) : tapeTime
        let text = String(format: "%d:%02d", Int(shown) / 60, Int(shown) % 60)
        return podcastMode ? "-" + text : text
    }
}

// MARK: - Script

/// The lessons, acted out: moves the finger and changes the deck as the real one would.
@MainActor
struct TourScript {
    @Binding var deck: TourDeck

    // Places on the canvas.
    private static let door = CGPoint(x: 98, y: 108)
    private static let grip = CGPoint(x: 98, y: 224)
    private static let hotline = CGPoint(x: 258, y: 26)
    private static let speedKnob = CGPoint(x: 258, y: 66)
    private static func key(_ index: Int) -> CGPoint { CGPoint(x: 240, y: 92 + CGFloat(index) * 34) }
    private static let rackFront = CGPoint(x: 203, y: 172)
    private static func divider(_ index: Int) -> CGPoint { CGPoint(x: 146 + CGFloat(index) * 58, y: 16) }
    private static func caseLine(_ index: Int) -> CGPoint { CGPoint(x: 170, y: 74 + CGFloat(index) * 17) }
    private static func trayLabel(_ index: Int) -> CGPoint { CGPoint(x: 150, y: 168 + CGFloat(index) * 24) }

    func play(_ lesson: SpoolLesson) async {
        switch lesson {
        case .openRack:
            await tap(Self.door) {
                withAnimation(.spring(duration: 0.35, bounce: 0.3)) { deck.doorOpen = true }
            }
            await pause(250)
            withAnimation(.spring(duration: 0.5, bounce: 0.12)) { deck.rackShown = true }
            await pause(700)
            hideFinger()

        case .browse:
            // A pull down brings the tapes behind forward; a little back up, and it settles.
            await move(to: CGPoint(x: 203, y: 110))
            await press()
            withAnimation(.easeInOut(duration: 0.9)) {
                deck.finger = CGPoint(x: 203, y: 200)
                deck.rackPosition = 2
            }
            await pause(950)
            withAnimation(.easeInOut(duration: 0.5)) {
                deck.finger = CGPoint(x: 203, y: 160)
                deck.rackPosition = 1
            }
            await pause(550)
            await lift()
            hideFinger()

        case .loadTape:
            await move(to: Self.rackFront)
            await press()
            // The front tape follows the finger left, then flies into the door.
            deck.tapeTitle = TourShelf.titles[0][0]
            deck.tapeShelf = 0
            withAnimation(.easeIn(duration: 0.3)) { deck.finger = CGPoint(x: 150, y: 172) }
            await pause(250)
            await lift()
            hideFinger()
            deck.flight = 0
            await pause(30)
            withAnimation(.easeIn(duration: 0.45)) { deck.flight = 1 }
            await pause(480)
            await seatTapeAndPlay()

        case .openCase:
            await tap(Self.rackFront) {
                withAnimation(.spring(duration: 0.55, bounce: 0.1)) { deck.caseOpen = 1 }
            }
            await pause(500)
            await tap(Self.caseLine(2)) {
                withAnimation(.easeOut(duration: 0.15)) { deck.caseHighlight = 2 }
            }
            hideFinger()
            deck.tapeTitle = TourShelf.titles[0][0]
            deck.tapeShelf = 0
            withAnimation(.easeIn(duration: 0.3)) { deck.caseOpen = 0 }
            deck.flight = 0
            await pause(200)
            withAnimation(.easeIn(duration: 0.45)) { deck.flight = 1 }
            await pause(480)
            deck.caseHighlight = nil
            await seatTapeAndPlay()

        case .shelves:
            await tap(Self.divider(1)) {
                withAnimation(.easeInOut(duration: 0.25)) { deck.shelf = 1; deck.rackPosition = 0 }
            }
            await pause(700)
            await tap(Self.divider(2)) {
                withAnimation(.easeInOut(duration: 0.25)) { deck.shelf = 2 }
            }
            await pause(500)
            hideFinger()

        case .keys:
            await tap(Self.key(0), key: 0) {
                withAnimation(.easeOut(duration: 0.15)) { deck.playLatched = true }
            }
            hideFinger()
            await turnReels(seconds: 1.2, speed: 1)
            await tap(Self.key(1), key: 1) {
                deck.tapeTime = 0
            }
            hideFinger()
            await turnReels(seconds: 1, speed: 1)

        case .wind:
            await move(to: Self.key(2))
            await press()
            deck.pressedKey = 2
            await pause(400)
            // Held: the tape winds back, quicker the longer it's held.
            await turnReels(seconds: 1.6, speed: -24)
            deck.pressedKey = nil
            await lift()
            hideFinger()
            await turnReels(seconds: 0.8, speed: 1)

        case .holdDoor:
            await move(to: Self.door)
            await press()
            withAnimation(.linear(duration: 0.5)) { deck.holdRing = 1 }
            await pause(550)
            deck.holdRing = 0
            deck.caseFromDoor = true
            withAnimation(.spring(duration: 0.55, bounce: 0.1)) { deck.caseOpen = 1 }
            await lift()
            hideFinger()
            await pause(900)
            await tap(Self.caseLine(4)) {
                withAnimation(.easeOut(duration: 0.15)) { deck.caseHighlight = 4 }
            }
            hideFinger()
            withAnimation(.easeIn(duration: 0.35)) { deck.caseOpen = 0 }
            await pause(400)
            deck.caseHighlight = nil
            deck.tapeTime = 0
            await turnReels(seconds: 0.8, speed: 1)

        case .upNext:
            await move(to: Self.grip)
            await press()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                deck.finger = CGPoint(x: 98, y: 130)
                deck.trayProgress = 1
            }
            await pause(500)
            await lift()
            await tap(Self.trayLabel(1)) {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.7)) { deck.pulledLabel = 1 }
            }
            hideFinger()
            await pause(400)
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { deck.trayProgress = 0 }
            await pause(450)
            deck.pulledLabel = nil
            deck.tapeTime = 0
            deck.tapeTitle = "Nights"
            await turnReels(seconds: 0.8, speed: 1)

        case .podcasts:
            await turnReels(seconds: 0.6, speed: 1)
            await tap(Self.key(1), key: 1) { deck.tapeTime += 30 }
            await tap(Self.key(2), key: 2) { deck.tapeTime -= 15 }
            await tap(Self.speedKnob) {
                withAnimation(.easeOut(duration: 0.15)) { deck.speed = "1.5×" }
            }
            hideFinger()
            await turnReels(seconds: 1, speed: 1.5)

        case .manual:
            await tap(Self.hotline) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) { deck.sheetShown = true }
            }
            hideFinger()
        }
    }

    // MARK: Moves

    /// The tape lands, the rack goes, the door shuts, and the play key goes down.
    private func seatTapeAndPlay() async {
        deck.flight = nil
        deck.tapeSeated = true
        deck.tapeTime = 0
        withAnimation(.spring(duration: 0.45, bounce: 0.1)) { deck.rackShown = false }
        await pause(450)
        withAnimation(.spring(duration: 0.3, bounce: 0.25)) { deck.doorOpen = false }
        await pause(350)
        withAnimation(.easeOut(duration: 0.15)) { deck.playLatched = true }
        await turnReels(seconds: 1.2, speed: 1)
    }

    /// Plays the tape for `seconds` at `speed` times normal, turning the reels.
    private func turnReels(seconds: Double, speed: Double) async {
        let frames = Int(seconds * 30)
        for _ in 0..<frames {
            guard !Task.isCancelled else { return }
            deck.tapeTime = max(0, deck.tapeTime + speed / 30)
            try? await Task.sleep(for: .milliseconds(33))
        }
    }

    /// Glides the finger to `point`, or puts it down there if it isn't showing.
    private func move(to point: CGPoint) async {
        let wasHidden = deck.finger == nil
        if wasHidden {
            withTransaction(Transaction(animation: nil)) { deck.finger = point }
            await pause(250)
        } else {
            withAnimation(.easeInOut(duration: 0.35)) { deck.finger = point }
            await pause(380)
        }
    }

    private func press() async {
        withAnimation(.easeIn(duration: 0.1)) { deck.fingerPressed = true }
        await pause(120)
    }

    private func lift() async {
        withAnimation(.easeOut(duration: 0.15)) { deck.fingerPressed = false }
        await pause(160)
    }

    /// Moves to `point`, presses (holding `key` down while pressed) and lifts away.
    private func tap(_ point: CGPoint, key: Int? = nil, then action: () -> Void = {}) async {
        await move(to: point)
        await press()
        deck.pressedKey = key
        action()
        await pause(180)
        deck.pressedKey = nil
        await lift()
        await pause(200)
    }

    private func hideFinger() {
        withAnimation(.easeIn(duration: 0.2)) {
            deck.finger = nil
            deck.fingerPressed = false
        }
    }

    private func pause(_ milliseconds: Int) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }
}

// MARK: - Sample Tapes

/// The tapes in the miniature's rack, one list per shelf.
enum TourShelf {
    static let titles: [[String]] = [
        ["Abbey Road", "Blonde", "Currents", "Dawn FM", "Echoes", "Fearless"],
        ["Late Night", "Road Trip", "Summer '89", "Sunday Drive", "Workout", "Zen"],
        ["Cassette Culture", "Deep Cuts", "Mixtape Radio", "The Daily Spin", "Vinyl Talk", "Wavelengths"],
    ]
}

// MARK: - Drawing

/// The miniature deck, drawn from a TourDeck on the 300 × 240 canvas.
private struct TourDeckView: View {
    let deck: TourDeck
    let theme: SpoolTheme

    private static let doorFrame = CGRect(x: 20, y: 18, width: 156, height: 186)
    /// How far the deck slides left for the rack, leaving the door's edge in view.
    static let rackShift: CGFloat = 70

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22)
                .fill(theme.bodyGradient)

            // The deck slides left as the rack comes in, as the real page does.
            ZStack(alignment: .topLeading) {
                bay
                doorPanel
                // The rack covers the rail and the grip while it's out.
                grip.opacity(deck.rackShown ? 0 : 1)
                rail.opacity(deck.rackShown ? 0 : 1)
            }
            .frame(width: SpoolTourScene.canvas.width, height: SpoolTourScene.canvas.height, alignment: .topLeading)
            .offset(x: deck.rackShown ? -Self.rackShift : 0)

            rack
                .offset(x: deck.rackShown ? 0 : 200)
                .opacity(deck.rackShown ? 1 : 0)

            if let flight = deck.flight { flyingTape(flight) }

            if deck.caseOpen > 0 { openCase }
            tray
            if deck.sheetShown { manualSheet }
            finger
        }
        .frame(width: SpoolTourScene.canvas.width, height: SpoolTourScene.canvas.height)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .environment(\.spoolTheme, theme)
    }

    // MARK: Door

    private var bay: some View {
        let frame = Self.doorFrame
        return RoundedRectangle(cornerRadius: 14)
            .fill(theme.bay)
            .overlay {
                if deck.tapeSeated {
                    cassette(width: 128)
                        .rotationEffect(.degrees(90))
                }
            }
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
    }

    private var doorPanel: some View {
        let frame = Self.doorFrame
        return RoundedRectangle(cornerRadius: 14)
            .fill(theme.windowTint.opacity(0.35))
            .overlay(alignment: .top) {
                Text(String(localized: "spool.brand"))
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 6)
            }
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(SpoolPalette.doorRim.opacity(0.8), lineWidth: 3))
            .overlay {
                // Holding the door: a ring fills as the hold takes.
                Circle()
                    .trim(from: 0, to: deck.holdRing)
                    .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 40, height: 40)
                    .opacity(deck.holdRing > 0 ? 1 : 0)
            }
            .rotation3DEffect(.degrees(deck.doorOpen ? -68 : 0), axis: (x: 0, y: 1, z: 0),
                              anchor: .leading, perspective: 0.5)
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
    }

    private var grip: some View {
        VStack(spacing: 2) {
            Capsule().fill(theme.ink.opacity(0.4)).frame(width: 24, height: 3)
            Text(String(localized: "spool.queue.title").uppercased())
                .font(.system(size: 6.5, weight: .bold))
                .tracking(1)
                .foregroundStyle(theme.ink.opacity(0.8))
        }
        .frame(width: 80)
        .position(x: 98, y: 222)
    }

    private func cassette(width: CGFloat) -> some View {
        let format: TapeFormat = deck.tapeShelf == 1 ? .mixtape : deck.tapeShelf == 2 ? .spokenWord : .album
        return CassetteShell(transport: TapeTransport(time: deck.tapeTime, duration: 1800),
                             title: deck.tapeTitle,
                             size: CGSize(width: width, height: width / CassetteView.aspectRatio),
                             format: format)
            .frame(width: width, height: width / CassetteView.aspectRatio)
    }

    // MARK: Rail

    private var rail: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.railGradient)
                .frame(width: 64, height: 224)
                .position(x: 258, y: 120)

            Circle()
                .fill(theme.isLight ? theme.logo : theme.accent)
                .frame(width: 22, height: 22)
                .overlay(Image(systemName: "ellipsis").font(.system(size: 9, weight: .bold)).foregroundStyle(.white))
                .position(x: 258, y: 26)

            Text(deck.counterText)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.keySymbol.opacity(0.85))
                .position(x: 258, y: 48)

            if deck.podcastMode {
                Text(deck.speed)
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.keySymbol)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.keyLight.opacity(0.85), in: Capsule())
                    .position(x: 258, y: 66)
            }

            ForEach(0..<4, id: \.self) { index in
                key(index)
                    .position(x: 240 + (isDown(index) ? 4 : 0), y: 92 + CGFloat(index) * 34)
            }
        }
        .frame(width: SpoolTourScene.canvas.width, height: SpoolTourScene.canvas.height, alignment: .topLeading)
    }

    private func isDown(_ index: Int) -> Bool {
        deck.pressedKey == index || (index == 0 && deck.playLatched)
    }

    private func key(_ index: Int) -> some View {
        let symbol: String
        switch index {
        case 0:  symbol = deck.playLatched ? "pause.fill" : "play.fill"
        case 1:  symbol = deck.podcastMode ? "goforward.30" : "forward.fill"
        case 2:  symbol = deck.podcastMode ? "gobackward.15" : "backward.fill"
        default: symbol = "eject.fill"
        }
        let colors = index == 0 ? [theme.accentLight, theme.accent] : [theme.keyLight, theme.key]
        return RoundedRectangle(cornerRadius: 4)
            .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 4).fill(.black.opacity(isDown(index) ? 0.12 : 0)))
            .overlay(Image(systemName: symbol).font(.system(size: 11, weight: .heavy)).foregroundStyle(theme.keySymbol))
            .frame(width: 44, height: 30)
            .shadow(color: .black.opacity(0.3), radius: isDown(index) ? 0 : 2, x: -1, y: 1)
    }

    // MARK: Rack

    private var rack: some View {
        ZStack(alignment: .topLeading) {
            dividers
            ForEach(Array(TourShelf.titles[deck.shelf].enumerated()), id: \.offset) { index, title in
                let slots = CGFloat(index) - deck.rackPosition
                let isFront = index == Int(deck.rackPosition.rounded())
                TourTape(title: title, shelf: deck.shelf, index: index)
                    .frame(width: 170, height: 109)
                    .scaleEffect(1 - min(max(slots, 0), 4) * 0.035, anchor: .top)
                    .brightness(-min(max(slots, 0), 4) * 0.06)
                    .offset(x: 118, y: slots >= 0 ? 118 - slots * 22 : 118 - slots * 120)
                    .opacity(slots < -0.9 ? 0 : (deck.flight != nil && isFront ? 0 : 1))
                    .zIndex(Double(-slots))
            }
        }
        .frame(width: SpoolTourScene.canvas.width, height: SpoolTourScene.canvas.height, alignment: .topLeading)
        .clipped()
    }

    private var dividers: some View {
        HStack(spacing: 2) {
            ForEach(Array(SpoolShelf.allCases.enumerated()), id: \.offset) { index, shelf in
                Text(shelf.title.uppercased())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .font(.system(size: 6.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.keySymbol.opacity(index == deck.shelf ? 1 : 0.55))
                    .frame(width: 56, height: 14)
                    .background(
                        UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4)
                            .fill(theme.keyLight.opacity(index == deck.shelf ? 0.95 : 0.45))
                    )
            }
        }
        .offset(x: 117, y: 9)
    }

    private func flyingTape(_ progress: CGFloat) -> some View {
        // From the rack's front tape to the door's seat, turning upright on the way.
        let start = CGPoint(x: 203, y: 172)
        let end = CGPoint(x: 98 - Self.rackShift * (deck.rackShown ? 1 : 0), y: 111)
        let point = CGPoint(x: start.x + (end.x - start.x) * progress, y: start.y + (end.y - start.y) * progress)
        return cassette(width: 170 - 42 * progress)
            .rotationEffect(.degrees(90 * progress))
            .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
            .position(point)
    }

    // MARK: Case

    private var openCase: some View {
        let source = deck.caseFromDoor ? CGPoint(x: 98, y: 108) : CGPoint(x: 203, y: 172)
        let center = CGPoint(x: 150, y: 120)
        let p = deck.caseOpen
        return VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [Color(hue: 0.08, saturation: 0.6, brightness: 0.9),
                                                  Color(hue: 0.95, saturation: 0.55, brightness: 0.6)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 0) {
                    Text(deck.caseFromDoor ? deck.tapeTitle : TourShelf.titles[0][0])
                        .font(.system(size: 11, weight: .bold, design: .serif))
                    ForEach(0..<6, id: \.self) { line in
                        HStack(spacing: 4) {
                            Text("\(line + 1)").font(.system(size: 7, design: .monospaced)).opacity(0.5)
                            Capsule().fill(SpoolPalette.labelInk.opacity(0.35))
                                .frame(width: CGFloat(60 + (line * 23) % 40), height: 3)
                            Spacer(minLength: 0)
                        }
                        .frame(height: 17)
                        .background(deck.caseHighlight == line ? SpoolPalette.labelInk.opacity(0.15) : .clear)
                    }
                }
            }
            .foregroundStyle(SpoolPalette.labelInk)
            .padding(8)
            .frame(width: 210, height: 150, alignment: .topLeading)
            .background(SpoolPalette.label, in: RoundedRectangle(cornerRadius: 6))
            .padding(6)
            .background(.white.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
        }
        .scaleEffect(0.35 + 0.65 * p)
        .position(x: source.x + (center.x - source.x) * p, y: source.y + (center.y - source.y) * p)
        .opacity(min(1, p * 2))
    }

    // MARK: Up Next

    private var tray: some View {
        VStack(alignment: .leading, spacing: 6) {
            Capsule().fill(theme.keySymbol.opacity(0.35)).frame(width: 30, height: 4)
                .frame(maxWidth: .infinity)
            Text(String(localized: "spool.queue.title").uppercased())
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(theme.keySymbol)
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 6) {
                    Text("\(row + 1)").font(.system(size: 7, design: .monospaced)).opacity(0.5)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hue: Double(row) * 0.21 + 0.5, saturation: 0.5, brightness: 0.75))
                        .frame(width: 14, height: 14)
                    Capsule().fill(SpoolPalette.labelInk.opacity(0.4)).frame(width: CGFloat(80 + row * 20), height: 3)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .frame(height: 20)
                .background(SpoolPalette.label, in: RoundedRectangle(cornerRadius: 3))
                .offset(x: deck.pulledLabel == row ? 14 : 0)
                .shadow(color: .black.opacity(deck.pulledLabel == row ? 0.4 : 0), radius: 4, y: 2)
                .foregroundStyle(SpoolPalette.labelInk)
            }
        }
        .padding(10)
        .frame(width: 280, height: 130, alignment: .top)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
                .fill(theme.railGradient)
                .shadow(color: .black.opacity(0.3), radius: 6, y: -2)
        )
        .position(x: 150, y: 240 - 65 + (1 - deck.trayProgress) * 150)
    }

    // MARK: Manual

    private var manualSheet: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "spool.brand"))
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .tracking(3)
            Text(String(localized: "spool.settings.manual"))
                .font(.system(size: 7, weight: .semibold))
                .tracking(1.5)
                .opacity(0.6)
            Rectangle().frame(height: 1.5)
            ForEach(1..<5, id: \.self) { number in
                HStack(spacing: 6) {
                    Text("\(number)")
                        .font(.system(size: 7, weight: .bold, design: .rounded))
                        .foregroundStyle(SpoolPalette.label)
                        .frame(width: 13, height: 13)
                        .background(SpoolPalette.labelInk, in: Circle())
                    Capsule().fill(SpoolPalette.labelInk.opacity(0.5)).frame(width: CGFloat(50 + number * 17), height: 3)
                }
            }
        }
        .foregroundStyle(SpoolPalette.labelInk)
        .padding(14)
        .frame(width: 300, height: 200, alignment: .topLeading)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
                .fill(Color(red: 0.957, green: 0.929, blue: 0.871))
                .shadow(color: .black.opacity(0.35), radius: 8, y: -2)
        )
        .position(x: 150, y: 140)
        .transition(.move(edge: .bottom))
    }

    // MARK: Finger

    @ViewBuilder
    private var finger: some View {
        TourFingertip(point: deck.finger, isPressed: deck.fingerPressed)
    }
}

/// A tape in the miniature's rack: an album in its case, a hand-labelled mixtape, or a
/// spoken-word tape, with its filing tab.
private struct TourTape: View {
    let title: String
    let shelf: Int
    let index: Int

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch shelf {
            case 1:
                RoundedRectangle(cornerRadius: 6)
                    .fill(SpoolPalette.label)
                    .overlay(alignment: .topLeading) {
                        HStack(alignment: .top, spacing: 8) {
                            cover.rotationEffect(.degrees(-3))
                            Text(title)
                                .font(.custom(SpoolPalette.handwriting, size: 13))
                                .foregroundStyle(SpoolPalette.pen)
                        }
                        .padding(10)
                    }
            case 2:
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(colors: [SpoolPalette.spokenWordShellTop, SpoolPalette.spokenWordShellBottom],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(alignment: .topLeading) {
                        HStack(alignment: .top, spacing: 8) {
                            cover
                            VStack(alignment: .leading, spacing: 3) {
                                Text(title)
                                    .font(.system(size: 11, weight: .bold, design: .serif))
                                Text(String(localized: "spool.tape.spokenWord").uppercased())
                                    .font(.system(size: 6, weight: .black, design: .rounded))
                                    .padding(.horizontal, 3)
                                    .background(SpoolPalette.spokenWordBand, in: RoundedRectangle(cornerRadius: 2))
                            }
                            .foregroundStyle(.white)
                        }
                        .padding(10)
                    }
            default:
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.08)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(alignment: .topLeading) {
                        HStack(alignment: .top, spacing: 8) {
                            cover
                            Text(title)
                                .font(.system(size: 11, weight: .bold, design: .serif))
                                .foregroundStyle(.white)
                        }
                        .padding(10)
                    }
            }
            RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.55), lineWidth: 1)
            SectionTab(letter: AppHelpers.firstLetter(of: title), height: 18)
                .offset(x: -4, y: 3)
        }
        .shadow(color: .black.opacity(0.35), radius: 3, y: -1)
    }

    private var cover: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(LinearGradient(colors: [Color(hue: Double(index) * 0.17 + Double(shelf) * 0.3, saturation: 0.55, brightness: 0.85),
                                          Color(hue: Double(index) * 0.17 + 0.4, saturation: 0.5, brightness: 0.55)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 58, height: 58)
            .padding(.top, 12)
    }
}
