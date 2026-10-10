//
//  GramophoneTour.swift
//  Lyre
//

import SwiftUI

// MARK: - Gramophone Tour
//
// How to use the Gramophone, acted out, as the Spool's tour does for the cassette deck
// (see SpoolTour): each lesson plays on a miniature of the machine seen from above, the
// turntable and tonearm in the middle, the brake, speed knob and crank beside them, and
// along the front the play switch, the drawer and the bin of Up Next's records. A ghost
// fingertip taps, drags and holds where a real finger would, and the miniature answers
// as the real machine does.
//
// The owner's booklet keeps it in its first section, in the shared TourPager. The
// miniature is drawn on a fixed 300 × 240 canvas and scaled to fit, so a lesson's script
// can place the finger in plain points; it is drawn in the chosen finish.
//
// Each lesson plays once and stops, and Reduce Motion skips the demonstration and leaves
// the words to teach it, as in the Spool's tour.

enum GramophoneLesson: Int, CaseIterable, Identifiable, TourLesson {
    case playSwitch
    case findRecord
    case putOn
    case queue
    case tonearm
    case brake
    case holdRecord
    case upNext
    case crank
    case broadcasts
    case booklet

    var id: Int { rawValue }

    // Spelled out case by case: a key put together at run time isn't looked up.
    var title: String {
        switch self {
        case .playSwitch: return String(localized: "gramophone.tour.playSwitch.title")
        case .findRecord: return String(localized: "gramophone.tour.findRecord.title")
        case .putOn: return String(localized: "gramophone.tour.putOn.title")
        case .queue: return String(localized: "gramophone.tour.queue.title")
        case .tonearm: return String(localized: "gramophone.tour.tonearm.title")
        case .brake: return String(localized: "gramophone.tour.brake.title")
        case .holdRecord: return String(localized: "gramophone.tour.holdRecord.title")
        case .upNext: return String(localized: "gramophone.tour.upNext.title")
        case .crank: return String(localized: "gramophone.tour.crank.title")
        case .broadcasts: return String(localized: "gramophone.tour.broadcasts.title")
        case .booklet: return String(localized: "gramophone.tour.booklet.title")
        }
    }

    var detail: String {
        switch self {
        case .playSwitch: return String(localized: "gramophone.tour.playSwitch.detail")
        case .findRecord: return String(localized: "gramophone.tour.findRecord.detail")
        case .putOn: return String(localized: "gramophone.tour.putOn.detail")
        case .queue: return String(localized: "gramophone.tour.queue.detail")
        case .tonearm: return String(localized: "gramophone.tour.tonearm.detail")
        case .brake: return String(localized: "gramophone.tour.brake.detail")
        case .holdRecord: return String(localized: "gramophone.tour.holdRecord.detail")
        case .upNext: return String(localized: "gramophone.tour.upNext.detail")
        case .crank: return String(localized: "gramophone.tour.crank.detail")
        case .broadcasts: return String(localized: "gramophone.tour.broadcasts.detail")
        case .booklet: return String(localized: "gramophone.tour.booklet.detail")
        }
    }
}

// MARK: - Pager

/// The Gramophone's lessons in the shared tour pager, in ink on the booklet's paper.
struct GramophoneTourPager: View {
    let theme: GramophoneTheme

    var body: some View {
        TourPager(lessons: GramophoneLesson.allCases, ink: SpoolPalette.labelInk, idPrefix: "gramophone.tour") { lesson, run in
            GramophoneTourScene(lesson: lesson, theme: theme, run: run)
        }
    }
}

// MARK: - Scene

/// One lesson on the miniature machine. Starts from the lesson's opening state and plays
/// its script once; `run` changing plays it again from the start.
struct GramophoneTourScene: View {
    let lesson: GramophoneLesson
    let theme: GramophoneTheme
    var run = 0

    @State private var machine = TourMachine()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let canvas = CGSize(width: 300, height: 240)

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / Self.canvas.width
            TourMachineView(machine: machine, theme: theme)
                .frame(width: Self.canvas.width, height: Self.canvas.height)
                .scaleEffect(scale, anchor: .topLeading)
        }
        .aspectRatio(Self.canvas.width / Self.canvas.height, contentMode: .fit)
        .frame(maxWidth: 360)
        .task(id: run) {
            withTransaction(Transaction(animation: nil)) { machine = TourMachine(opening: lesson) }
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .milliseconds(500))
            await TourMachineScript(machine: $machine).play(lesson)
        }
    }
}

// MARK: - Machine State

/// Everything the miniature can show, in canvas points where it's a position.
struct TourMachine {
    var switchOn = false
    var recordTitle = TourCrate.titles[1]
    /// Which colour the record's label is (see TourCrate.labels).
    var recordLabel = 1
    /// How far the record has turned, in degrees.
    var recordAngle: Double = 0
    var recordShown = true
    var armAngle = TourMachine.restAngle
    var armLifted = false
    /// Turning under the needle. The brake and lifting the arm stop it.
    var isPlaying = false
    var crankAngle: Double = 0
    /// 0 shut, 1 pulled out with the crate showing.
    var drawer: CGFloat = 0
    var stackIndex = 0
    var stackSwipe: CGFloat = 0
    /// The letter a finger is on along the drawer's index.
    var indexLetter: String?
    var sleeveShown = false
    var sleeveHighlight: Int?
    var menuShown = false
    var menuHighlight: Int?
    var binShown = false
    var binIndex = 0
    var binFlip: CGFloat = 0
    var podcastMode = false
    var speed = "1×"
    var bookletShown = false
    var holdRing: CGFloat = 0
    var notice: String?
    var finger: CGPoint?
    var fingerPressed = false

    /// The tonearm on its rest, and over the record's first and last bands.
    static let restAngle: Double = 97
    static let firstBand: Double = 120
    static let lastBand: Double = 127
    static func band(_ index: Int) -> Double { firstBand + Double(index) * 1.6 }

    init() {}

    /// Where each lesson starts.
    init(opening lesson: GramophoneLesson) {
        switch lesson {
        case .playSwitch, .booklet:
            break
        case .findRecord, .queue:
            playing()
        case .putOn:
            playing()
            drawer = 1
        case .tonearm, .brake, .holdRecord, .upNext, .crank:
            playing()
        case .broadcasts:
            playing()
            podcastMode = true
            recordTitle = TourCrate.broadcast
            recordLabel = 4
        }
    }

    private mutating func playing() {
        switchOn = true
        isPlaying = true
        armAngle = Self.band(1)
    }

    var isTurning: Bool { isPlaying && !armLifted && armAngle > Self.restAngle + 5 && recordShown }
}

/// The records in the miniature's crate and bin.
enum TourCrate {
    static let titles = ["Abbey Road", "Blonde", "Currents", "Dawn FM", "Echoes", "Fearless"]
    static let broadcast = "The Daily Spin"
    static let labels: [Color] = [
        Color(red: 0.80, green: 0.34, blue: 0.20), Color(red: 0.93, green: 0.78, blue: 0.30),
        Color(red: 0.24, green: 0.45, blue: 0.70), Color(red: 0.55, green: 0.30, blue: 0.62),
        Color(red: 0.12, green: 0.18, blue: 0.30), Color(red: 0.30, green: 0.58, blue: 0.40),
    ]
    static let songs = ["Overture", "Morning Light", "Side Street", "Long Way Home", "Last Dance"]
}

// MARK: - Script

/// The lessons, acted out: moves the finger and changes the machine as the real one would.
@MainActor
struct TourMachineScript {
    @Binding var machine: TourMachine

    // Places on the canvas.
    private static let playSwitch = CGPoint(x: 42, y: 222)
    private static let drawerFront = CGPoint(x: 150, y: 222)
    private static let bin = CGPoint(x: 258, y: 222)
    private static let stackTop = CGPoint(x: 150, y: 128)
    private static let record = CGPoint(x: 118, y: 100)
    private static let brake = CGPoint(x: 230, y: 150)
    private static let speedKnob = CGPoint(x: 230, y: 182)
    private static let crankHub = CGPoint(x: 284, y: 96)
    private static let booklet = CGPoint(x: 276, y: 20)
    private static func sleeveRow(_ index: Int) -> CGPoint { CGPoint(x: 150, y: 116 + CGFloat(index) * 17) }
    private static func menuRow(_ index: Int) -> CGPoint { CGPoint(x: 150, y: 112 + CGFloat(index) * 24) }
    private static func indexPoint(_ letter: Int) -> CGPoint {
        CGPoint(x: TourMachineView.indexFrame.minX + (CGFloat(letter) + 0.5) * TourMachineView.indexStep,
                y: TourMachineView.indexFrame.midY)
    }
    /// The tip of the tonearm at `angle`, where a finger takes hold of it.
    private static func armTip(_ angle: Double) -> CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(x: TourMachineView.armPivot.x + cos(radians) * TourMachineView.armLength * 0.92,
                       y: TourMachineView.armPivot.y + sin(radians) * TourMachineView.armLength * 0.92)
    }

    func play(_ lesson: GramophoneLesson) async {
        switch lesson {
        case .playSwitch:
            await tap(Self.playSwitch) {
                withAnimation(.spring(duration: 0.3, bounce: 0.3)) { machine.switchOn = true }
            }
            hideFinger()
            await dropNeedle(on: 0)
            await turn(seconds: 1.4)

        case .findRecord:
            await turn(seconds: 0.4)
            await tap(Self.drawerFront) {
                withAnimation(.spring(duration: 0.5, bounce: 0.1)) { machine.drawer = 1 }
            }
            await pause(300)
            // A swipe right goes up the stack.
            await move(to: Self.stackTop)
            await press()
            withAnimation(.easeIn(duration: 0.3)) {
                machine.finger = CGPoint(x: 236, y: 128)
                machine.stackSwipe = 1
            }
            await pause(320)
            withTransaction(Transaction(animation: nil)) {
                machine.stackIndex = 1
                machine.stackSwipe = 0
            }
            await lift()
            await pause(300)
            // Along the index, the stack jumps to each letter the finger reaches.
            await move(to: Self.indexPoint(1))
            await press()
            for letter in [1, 2, 3, 4] {
                withAnimation(.easeInOut(duration: 0.22)) {
                    machine.finger = Self.indexPoint(letter)
                    machine.indexLetter = TourMachineView.letters[letter]
                }
                // The strip starts with "#", so letter 1 (A) is the first record.
                machine.stackIndex = min(letter - 1, TourCrate.titles.count - 1)
                await pause(260)
            }
            await lift()
            withAnimation(.easeOut(duration: 0.2)) { machine.indexLetter = nil }
            hideFinger()

        case .putOn:
            await tap(Self.stackTop) {
                withAnimation(.spring(duration: 0.45, bounce: 0.1)) { machine.sleeveShown = true }
            }
            await pause(400)
            await tap(Self.sleeveRow(2)) {
                withAnimation(.easeOut(duration: 0.15)) { machine.sleeveHighlight = 2 }
            }
            hideFinger()
            withAnimation(.easeIn(duration: 0.3)) {
                machine.sleeveShown = false
                machine.drawer = 0
            }
            await pause(300)
            machine.sleeveHighlight = nil
            await changeRecord(to: machine.stackIndex)
            await dropNeedle(on: 2)
            await turn(seconds: 1.2)

        case .queue:
            await turn(seconds: 0.3)
            await tap(Self.drawerFront) {
                withAnimation(.spring(duration: 0.5, bounce: 0.1)) { machine.drawer = 1 }
            }
            await pause(300)
            await hold(Self.stackTop)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { machine.menuShown = true }
            await lift()
            await pause(500)
            await tap(Self.menuRow(0)) {
                withAnimation(.easeOut(duration: 0.12)) { machine.menuHighlight = 0 }
            }
            hideFinger()
            withAnimation(.easeIn(duration: 0.2)) { machine.menuShown = false }
            machine.menuHighlight = nil
            await showNotice(String(localized: "gramophone.tour.queued"))

        case .tonearm:
            await turn(seconds: 0.6)
            // Lifted, the record stops; set down on another band, it plays that song.
            await move(to: Self.armTip(machine.armAngle))
            await press()
            withAnimation(.easeOut(duration: 0.15)) { machine.armLifted = true }
            await pause(250)
            withAnimation(.easeInOut(duration: 0.6)) {
                machine.armAngle = TourMachine.band(3)
                machine.finger = Self.armTip(TourMachine.band(3))
            }
            await pause(650)
            withAnimation(.easeIn(duration: 0.15)) { machine.armLifted = false }
            await lift()
            hideFinger()
            await turn(seconds: 1.2)

        case .brake:
            await turn(seconds: 0.6)
            await tap(Self.brake) {
                withAnimation(.spring(duration: 0.25, bounce: 0.3)) { machine.isPlaying = false }
            }
            await pause(500)
            await tap(Self.brake) {
                withAnimation(.spring(duration: 0.25, bounce: 0.3)) { machine.isPlaying = true }
            }
            hideFinger()
            await turn(seconds: 1)

        case .holdRecord:
            await turn(seconds: 0.4)
            await hold(Self.record)
            withAnimation(.spring(duration: 0.45, bounce: 0.1)) { machine.sleeveShown = true }
            await lift()
            await pause(500)
            await tap(Self.sleeveRow(3)) {
                withAnimation(.easeOut(duration: 0.15)) { machine.sleeveHighlight = 3 }
            }
            hideFinger()
            withAnimation(.easeIn(duration: 0.3)) { machine.sleeveShown = false }
            await pause(300)
            machine.sleeveHighlight = nil
            await moveNeedle(to: 3)
            await turn(seconds: 1)

        case .upNext:
            await turn(seconds: 0.4)
            await tap(Self.bin) {
                withAnimation(.spring(duration: 0.45, bounce: 0.1)) { machine.binShown = true }
            }
            await pause(300)
            // A swipe down flips the front record forward to the next.
            await move(to: CGPoint(x: 150, y: 90))
            await press()
            withAnimation(.easeIn(duration: 0.3)) {
                machine.finger = CGPoint(x: 150, y: 170)
                machine.binFlip = 1
            }
            await pause(320)
            withTransaction(Transaction(animation: nil)) {
                machine.binIndex = 1
                machine.binFlip = 0
            }
            await lift()
            await pause(250)
            await tap(CGPoint(x: 150, y: 110))
            hideFinger()
            withAnimation(.easeIn(duration: 0.3)) { machine.binShown = false }
            await pause(300)
            await changeRecord(to: 3 + machine.binIndex)
            await dropNeedle(on: 0)
            await turn(seconds: 1)

        case .crank:
            await turn(seconds: 0.4)
            // A full turn of the handle, the finger going round with it.
            await move(to: TourMachineView.crankHandle(0))
            await press()
            let steps = 24
            for step in 1...steps {
                let angle = Double(step) / Double(steps) * 360
                withAnimation(.linear(duration: 0.04)) {
                    machine.crankAngle = angle
                    machine.finger = TourMachineView.crankHandle(angle)
                }
                await pause(40)
            }
            await lift()
            hideFinger()
            await showNotice(String(localized: "gramophone.shuffle.done"), keep: false)
            await changeRecord(to: 5, title: String(localized: "gramophone.shuffle.title"))
            await dropNeedle(on: 0)
            await turn(seconds: 1)
            withAnimation(.easeOut(duration: 0.2)) { machine.notice = nil }

        case .broadcasts:
            await turn(seconds: 0.6)
            await tap(Self.speedKnob) {
                withAnimation(.easeOut(duration: 0.15)) { machine.speed = "1.5×" }
            }
            hideFinger()
            await turn(seconds: 1, speed: 1.5)

        case .booklet:
            await tap(Self.booklet) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) { machine.bookletShown = true }
            }
            hideFinger()
        }
    }

    // MARK: Moves

    /// The tonearm swings over from its rest and lowers the needle onto `band`.
    private func dropNeedle(on band: Int) async {
        withAnimation(.easeOut(duration: 0.15)) { machine.armLifted = true }
        await pause(150)
        withAnimation(.easeInOut(duration: 0.6)) { machine.armAngle = TourMachine.band(band) }
        await pause(620)
        withAnimation(.easeIn(duration: 0.15)) {
            machine.armLifted = false
            machine.isPlaying = true
        }
        await pause(150)
    }

    /// The needle lifted and set down again on `band` of the same record.
    private func moveNeedle(to band: Int) async {
        withAnimation(.easeOut(duration: 0.15)) { machine.armLifted = true }
        await pause(150)
        withAnimation(.easeInOut(duration: 0.4)) { machine.armAngle = TourMachine.band(band) }
        await pause(420)
        withAnimation(.easeIn(duration: 0.15)) { machine.armLifted = false }
        await pause(150)
    }

    /// The record on the turntable lifted off and another put on in its place.
    private func changeRecord(to index: Int, title: String? = nil) async {
        withAnimation(.easeOut(duration: 0.15)) { machine.armLifted = true }
        withAnimation(.easeInOut(duration: 0.4)) { machine.armAngle = TourMachine.restAngle }
        await pause(420)
        withAnimation(.easeIn(duration: 0.2)) { machine.recordShown = false }
        await pause(220)
        machine.recordTitle = title ?? TourCrate.titles[index % TourCrate.titles.count]
        machine.recordLabel = index % TourCrate.labels.count
        withAnimation(.easeOut(duration: 0.25)) { machine.recordShown = true }
        await pause(280)
    }

    /// The record turning for `seconds`, while the needle's down and the brake is off.
    private func turn(seconds: Double, speed: Double = 1) async {
        let frames = Int(seconds * 30)
        for _ in 0..<frames {
            guard !Task.isCancelled else { return }
            if machine.isTurning { machine.recordAngle += 200 * speed / 30 }
            try? await Task.sleep(for: .milliseconds(33))
        }
    }

    private func showNotice(_ text: String, keep: Bool = true) async {
        withAnimation(.easeOut(duration: 0.2)) { machine.notice = text }
        guard keep else { return }
        await pause(1400)
        withAnimation(.easeIn(duration: 0.2)) { machine.notice = nil }
    }

    /// Glides the finger to `point`, or puts it down there if it isn't showing.
    private func move(to point: CGPoint) async {
        if machine.finger == nil {
            withTransaction(Transaction(animation: nil)) { machine.finger = point }
            await pause(250)
        } else {
            withAnimation(.easeInOut(duration: 0.35)) { machine.finger = point }
            await pause(380)
        }
    }

    private func press() async {
        withAnimation(.easeIn(duration: 0.1)) { machine.fingerPressed = true }
        await pause(120)
    }

    private func lift() async {
        withAnimation(.easeOut(duration: 0.15)) { machine.fingerPressed = false }
        await pause(160)
    }

    /// Moves to `point`, presses and holds until the hold takes; the finger stays down.
    private func hold(_ point: CGPoint) async {
        await move(to: point)
        await press()
        withAnimation(.linear(duration: 0.5)) { machine.holdRing = 1 }
        await pause(550)
        machine.holdRing = 0
    }

    /// Moves to `point`, presses and lifts away.
    private func tap(_ point: CGPoint, then action: () -> Void = {}) async {
        await move(to: point)
        await press()
        action()
        await pause(180)
        await lift()
        await pause(200)
    }

    private func hideFinger() {
        withAnimation(.easeIn(duration: 0.2)) {
            machine.finger = nil
            machine.fingerPressed = false
        }
    }

    private func pause(_ milliseconds: Int) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }
}

// MARK: - Drawing

/// The miniature machine, drawn from a TourMachine on the 300 × 240 canvas, from above.
private struct TourMachineView: View {
    let machine: TourMachine
    let theme: GramophoneTheme

    static let platterCenter = CGPoint(x: 118, y: 100)
    static let platterRadius: CGFloat = 74
    static let recordRadius: CGFloat = 68
    static let armPivot = CGPoint(x: 222, y: 36)
    static let armLength: CGFloat = 118
    static let crankCenter = CGPoint(x: 284, y: 96)
    static let letters = ["#", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M"]
    static let indexFrame = CGRect(x: 40, y: 200, width: 220, height: 16)
    static var indexStep: CGFloat { indexFrame.width / CGFloat(letters.count) }

    /// The crank's handle at `angle` degrees round from the top.
    static func crankHandle(_ angle: Double) -> CGPoint {
        let radians = (angle - 90) * .pi / 180
        return CGPoint(x: crankCenter.x + cos(radians) * 14, y: crankCenter.y + sin(radians) * 14)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22)
                .fill(theme.woodGradient)

            plinthEdge
            turntable
            tonearm
            brake
            speedKnob
            crank
            bookletButton
            frontPanel

            if machine.drawer > 0 { crate }
            if machine.sleeveShown { sleeve }
            if machine.menuShown { holdMenu }
            if machine.binShown { bin }
            if let notice = machine.notice { noticeView(notice) }
            if machine.bookletShown { bookletSheet }
            TourFingertip(point: machine.finger, isPressed: machine.fingerPressed)
        }
        .frame(width: GramophoneTourScene.canvas.width, height: GramophoneTourScene.canvas.height)
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    // MARK: The Machine

    /// The line where the cabinet's top meets its front panel.
    private var plinthEdge: some View {
        Rectangle()
            .fill(theme.woodDark.opacity(0.6))
            .frame(width: 300, height: 34)
            .overlay(alignment: .top) { Rectangle().fill(.black.opacity(0.3)).frame(height: 1.5) }
            .position(x: 150, y: 223)
    }

    private var turntable: some View {
        ZStack {
            Circle()
                .fill(theme.felt)
                .overlay(Circle().strokeBorder(theme.metalGradient, lineWidth: 2.5))
                .frame(width: Self.platterRadius * 2, height: Self.platterRadius * 2)
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
            if machine.recordShown {
                record
                    .rotationEffect(.degrees(machine.recordAngle))
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
            // Holding the record: a ring fills as the hold takes.
            Circle()
                .trim(from: 0, to: holdingAt(TourMachineView.platterCenter) ? machine.holdRing : 0)
                .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 44, height: 44)
        }
        .position(Self.platterCenter)
    }

    private var record: some View {
        ZStack {
            Circle().fill(Color(white: 0.08))
            ForEach(0..<6, id: \.self) { ring in
                Circle()
                    .stroke(.white.opacity(ring.isMultiple(of: 2) ? 0.07 : 0.03), lineWidth: 1)
                    .frame(width: 128 - CGFloat(ring) * 15, height: 128 - CGFloat(ring) * 15)
            }
            Circle()
                .fill(TourCrate.labels[machine.recordLabel])
                .frame(width: 44, height: 44)
                .overlay {
                    Text(machine.recordTitle)
                        .font(.system(size: 5.5, weight: .bold, design: .serif))
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .frame(width: 34)
                        .offset(y: -8)
                }
                .overlay(Circle().fill(Color(white: 0.85)).frame(width: 4, height: 4))
        }
        .frame(width: Self.recordRadius * 2, height: Self.recordRadius * 2)
    }

    private var tonearm: some View {
        ZStack(alignment: .topLeading) {
            // The arm and its head, drawn pointing right from the pivot on the full canvas
            // and swung about the pivot; lifted, it casts a longer shadow.
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(theme.metalGradient)
                    .frame(width: Self.armLength, height: 6)
                    .overlay(alignment: .trailing) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.metalDark)
                            .frame(width: 14, height: 10)
                    }
                    .position(x: Self.armPivot.x + Self.armLength / 2, y: Self.armPivot.y)
            }
            .frame(width: 300, height: 240, alignment: .topLeading)
            .rotationEffect(.degrees(machine.armAngle),
                            anchor: UnitPoint(x: Self.armPivot.x / 300, y: Self.armPivot.y / 240))
            .shadow(color: .black.opacity(0.45), radius: machine.armLifted ? 5 : 1.5,
                    x: machine.armLifted ? 4 : 1, y: machine.armLifted ? 6 : 1.5)
            Circle()
                .fill(theme.metalGradient)
                .frame(width: 20, height: 20)
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                .position(Self.armPivot)
        }
        .frame(width: 300, height: 240, alignment: .topLeading)
    }

    private var brake: some View {
        Text(String(localized: machine.isPlaying ? "gramophone.brake.stop" : "gramophone.brake.start"))
            .font(.system(size: 7, weight: .heavy, design: .serif))
            .tracking(1)
            .foregroundStyle(theme.plateInk)
            .frame(width: 42, height: 16)
            .background(theme.metalGradient, in: Capsule())
            .offset(x: machine.isPlaying ? 4 : -4)
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
            .position(x: 230, y: 150)
    }

    private var speedKnob: some View {
        Text(machine.speed)
            .font(.system(size: 7.5, weight: .heavy, design: .rounded))
            .foregroundStyle(theme.plateInk)
            .frame(width: 26, height: 26)
            .background(theme.metalGradient, in: Circle())
            .opacity(machine.podcastMode ? 1 : 0.45)
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
            .position(x: 230, y: 182)
    }

    private var crank: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: Self.crankCenter)
                path.addLine(to: Self.crankHandle(machine.crankAngle))
            }
            .stroke(theme.metalGradient, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            Circle().fill(theme.metalDark).frame(width: 10, height: 10).position(Self.crankCenter)
            Circle().fill(theme.woodDark).overlay(Circle().strokeBorder(theme.metal, lineWidth: 1.5))
                .frame(width: 10, height: 10).position(Self.crankHandle(machine.crankAngle))
        }
        .frame(width: 300, height: 240, alignment: .topLeading)
    }

    private var bookletButton: some View {
        Image(systemName: "book.closed.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(theme.plateInk)
            .frame(width: 22, height: 22)
            .background(theme.metalGradient, in: Circle())
            .position(x: 276, y: 20)
    }

    /// The play switch, the drawer and the bin of Up Next's records, along the front.
    private var frontPanel: some View {
        ZStack(alignment: .topLeading) {
            // The play switch: a lever that tips right when on.
            Capsule()
                .fill(.black.opacity(0.35))
                .frame(width: 30, height: 14)
                .overlay(alignment: machine.switchOn ? .trailing : .leading) {
                    Circle().fill(theme.metalGradient).frame(width: 12, height: 12).padding(1)
                }
                .position(x: 42, y: 222)
            // The drawer's front and its knob.
            RoundedRectangle(cornerRadius: 3)
                .fill(theme.woodGradient)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.black.opacity(0.35), lineWidth: 1))
                .overlay(Circle().fill(theme.metalGradient).frame(width: 7, height: 7))
                .frame(width: 112, height: 24)
                .position(x: 150, y: 222)
            // Up Next: the records waiting, in a bin.
            ZStack {
                ForEach(0..<3, id: \.self) { record in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(TourCrate.labels[(record + 3) % TourCrate.labels.count])
                        .frame(width: 22, height: 22)
                        .offset(x: CGFloat(record) * 3, y: CGFloat(record) * -2)
                }
            }
            .position(x: 255, y: 223)
        }
        .frame(width: 300, height: 240, alignment: .topLeading)
    }

    // MARK: The Crate

    private var crate: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.woodDark)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black.opacity(0.4), lineWidth: 2))
                .frame(width: 280, height: 176)
                .position(x: 150, y: 140)
            ForEach((0..<3).reversed(), id: \.self) { depth in
                let index = machine.stackIndex + depth
                if index < TourCrate.titles.count {
                    sleeveCard(index, size: 86)
                        .rotationEffect(.degrees(depth == 0 ? Double(machine.stackSwipe) * 14 : Double(depth) * 3))
                        .offset(x: depth == 0 ? machine.stackSwipe * 120 : CGFloat(depth) * 3,
                                y: CGFloat(depth) * -2)
                        .opacity(depth == 0 ? Double(1 - machine.stackSwipe * 0.6) : 1)
                        .brightness(-0.06 * Double(depth))
                        .position(x: 150, y: 128)
                }
            }
            // Holding the top record: a ring fills as the hold takes.
            Circle()
                .trim(from: 0, to: holdingAt(CGPoint(x: 150, y: 128)) ? machine.holdRing : 0)
                .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 44, height: 44)
                .position(x: 150, y: 128)
            indexStrip
        }
        .frame(width: 300, height: 240, alignment: .topLeading)
        .offset(y: (1 - machine.drawer) * 200)
        .transition(.opacity)
    }

    private func sleeveCard(_ index: Int, size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(TourCrate.labels[index % TourCrate.labels.count])
            .overlay(alignment: .bottomLeading) {
                Text(TourCrate.titles[index % TourCrate.titles.count])
                    .font(.system(size: 8, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .padding(5)
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
    }

    private var indexStrip: some View {
        let front = String(TourCrate.titles[min(machine.stackIndex, TourCrate.titles.count - 1)].prefix(1))
        return ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                ForEach(Self.letters, id: \.self) { letter in
                    let isFront = letter == front
                    Text(letter)
                        .font(.system(size: 7, weight: .bold, design: .serif))
                        .foregroundStyle(isFront ? theme.plateInk : theme.ink.opacity(0.8))
                        .frame(width: Self.indexStep, height: Self.indexFrame.height)
                        .background {
                            if isFront { RoundedRectangle(cornerRadius: 2).fill(theme.metalGradient).padding(.vertical, 2) }
                        }
                }
            }
            .background(Capsule().fill(.black.opacity(0.3)))
            .position(x: Self.indexFrame.midX, y: Self.indexFrame.midY)

            if let letter = machine.indexLetter, let at = Self.letters.firstIndex(of: letter) {
                Text(letter)
                    .font(.system(size: 14, weight: .bold, design: .serif))
                    .foregroundStyle(theme.plateInk)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(theme.metalGradient))
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
                    .position(x: Self.indexFrame.minX + (CGFloat(at) + 0.5) * Self.indexStep, y: Self.indexFrame.minY - 18)
            }
        }
        .frame(width: 300, height: 240, alignment: .topLeading)
    }

    // MARK: The Sleeve and the Menu

    /// A record's sleeve turned over: the record slid partway out of the top, and the
    /// songs on the back.
    private var sleeve: some View {
        ZStack(alignment: .top) {
            Circle()
                .fill(Color(white: 0.08))
                .frame(width: 120, height: 120)
                .offset(y: -44)
            RoundedRectangle(cornerRadius: 4)
                .fill(theme.paper)
                .frame(width: 180, height: 150)
                .shadow(color: .black.opacity(0.45), radius: 8, y: 3)
            VStack(alignment: .leading, spacing: 0) {
                Text(machine.drawer > 0 ? TourCrate.titles[machine.stackIndex % TourCrate.titles.count] : machine.recordTitle)
                    .font(.system(size: 11, weight: .bold, design: .serif))
                    .padding(.bottom, 6)
                ForEach(TourCrate.songs.indices, id: \.self) { row in
                    HStack(spacing: 6) {
                        Text("\(row + 1)").font(.system(size: 7, weight: .semibold, design: .serif)).opacity(0.5)
                        Text(TourCrate.songs[row]).font(.system(size: 8, design: .serif))
                        Spacer(minLength: 0)
                    }
                    .frame(height: 17)
                    .padding(.horizontal, 4)
                    .background(machine.sleeveHighlight == row ? theme.metal.opacity(0.35) : .clear)
                }
            }
            .foregroundStyle(theme.plateInk)
            .padding(12)
            .frame(width: 180, alignment: .leading)
        }
        .position(x: 150, y: 118)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    /// The menu a held record offers.
    private var holdMenu: some View {
        VStack(spacing: 0) {
            ForEach(0..<2, id: \.self) { row in
                HStack {
                    Text(String(localized: row == 0 ? "queue.action.playNext" : "queue.action.addToQueue"))
                        .font(.system(size: 9, weight: .medium))
                    Spacer()
                    Image(systemName: row == 0 ? "text.insert" : "text.append").font(.system(size: 8))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(machine.menuHighlight == row ? Color.black.opacity(0.1) : .clear)
                if row == 0 { Divider() }
            }
        }
        .frame(width: 130)
        .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 9))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        .position(x: 150, y: 124)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    // MARK: Up Next

    /// Round at the front of the bin: Up Next's front record, which a swipe down flips.
    private var bin: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.55))
            ForEach((0..<2).reversed(), id: \.self) { depth in
                sleeveCard(3 + machine.binIndex + depth, size: 104)
                    .rotation3DEffect(.degrees(depth == 0 ? Double(machine.binFlip) * 70 : 0),
                                      axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.5)
                    .brightness(-0.08 * Double(depth))
                    .offset(y: CGFloat(depth) * -6)
            }
            .offset(y: -10)
            Text(String(localized: "gramophone.rack.instructions"))
                .font(.system(size: 6.5, design: .serif))
                .italic()
                .foregroundStyle(.white.opacity(0.75))
                .offset(y: 92)
        }
        .frame(width: 300, height: 240)
        .transition(.opacity)
    }

    // MARK: Words

    private func noticeView(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.black.opacity(0.75), in: Capsule())
            .position(x: 150, y: 186)
            .transition(.opacity)
    }

    private var bookletSheet: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "gramophone.brand"))
                .font(.system(size: 18, weight: .bold, design: .serif))
            Text(String(localized: "gramophone.settings.booklet").uppercased())
                .font(.system(size: 7, weight: .semibold, design: .serif))
                .tracking(1.5)
                .opacity(0.6)
            VStack(spacing: 2) {
                Rectangle().frame(height: 1.5)
                Rectangle().frame(height: 0.5)
            }
            ForEach(["I.", "II.", "III.", "IV."], id: \.self) { numeral in
                HStack(spacing: 6) {
                    Text(numeral).font(.system(size: 8, weight: .bold, design: .serif)).frame(width: 18, alignment: .leading)
                    Capsule().fill(theme.plateInk.opacity(0.45))
                        .frame(width: CGFloat(60 + numeral.count * 22), height: 3)
                }
            }
        }
        .foregroundStyle(theme.plateInk)
        .padding(14)
        .frame(width: 300, height: 200, alignment: .topLeading)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
                .fill(theme.paper)
                .shadow(color: .black.opacity(0.35), radius: 8, y: -2)
        )
        .position(x: 150, y: 140)
        .transition(.move(edge: .bottom))
    }

    /// Whether the finger is holding near `point`, for the hold ring.
    private func holdingAt(_ point: CGPoint) -> Bool {
        guard let finger = machine.finger else { return false }
        return hypot(finger.x - point.x, finger.y - point.y) < 30
    }
}
