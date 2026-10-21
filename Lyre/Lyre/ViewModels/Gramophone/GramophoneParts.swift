//
//  GramophoneParts.swift
//  Lyre
//

import MusicKit
import SwiftUI

// MARK: - Gramophone Parts
//
// The machine's parts, drawn on their own so GramophonePlayerView only lays them out:
//
//   RecordDisc        a record: grooves cut in bands, one per song, and its label
//   TurntableView     the platter turning with the music and the tonearm over it,
//                     which a finger lifts, carries and drops (see TonearmGeometry)
//   GramophoneCrank   winds the spring; a full turn shuffles (drawn in 3D: see
//                     GramophoneStage)
//   BrakeLever        start and stop
//   SpeedRegulator    the podcast speed
//   UpNextPile        the records waiting their turn
//   Nameplate         the brass plate with the song playing
//   GramophoneSketch  a small drawing of a design, for settings and onboarding

// MARK: - Record

/// What a record is pressed as.
enum RecordKind: Equatable {
    /// A commercial pressing: black shellac with the cover printed on the label.
    case album
    /// A playlist, cut at home on an aluminum disc with a hand-written label.
    case homeRecording
    /// A podcast, as a radio station's transcription disc.
    case transcription

    init(_ album: AppAlbum?) {
        if album?.isMixtape == true { self = .homeRecording }
        else if album?.isPodcast == true { self = .transcription }
        else { self = .album }
    }
}

extension AppAlbum {
    /// A playlist with art of its own, to go on its record's label.
    var hasPlaylistArtwork: Bool {
        isMixtape && (mixtape?.musicKitPlaylist?.artwork != nil || mpArtwork != nil)
    }
}

/// What's printed on a record's label.
enum RecordLabel {
    case album(AppAlbum)
    case track(AppTrack)
    /// Paper only, with the title written or printed on it.
    case plain
}

struct RecordDisc: View {
    let kind: RecordKind
    let title: String
    let label: RecordLabel
    /// Where the songs' bands fall. Nil cuts one long groove.
    var grooves: GrooveMap?
    let diameter: CGFloat
    /// Painted once, for the 3D record, rather than drawn live: the label's picture as
    /// it was loaded, or the printed label when there's none.
    var still: StillLabel?

    struct StillLabel {
        let image: UIImage?
    }

    var body: some View {
        let r = diameter / 2
        ZStack {
            Circle().fill(surface)
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                drawGrooves(in: context, center: center, radius: r)
            }
            labelView
                .frame(width: diameter * 0.34, height: diameter * 0.34)
                .clipShape(Circle())
            Circle()
                .fill(Color.black.opacity(0.85))
                .frame(width: diameter * 0.022, height: diameter * 0.022)
        }
        .frame(width: diameter, height: diameter)
    }

    private var surface: RadialGradient {
        switch kind {
        case .homeRecording:
            return RadialGradient(colors: [Color(white: 0.78), Color(white: 0.62), Color(white: 0.7)],
                                  center: .center, startRadius: 0, endRadius: diameter / 2)
        case .album, .transcription:
            return RadialGradient(colors: [Color(white: 0.11), Color(white: 0.05), Color(white: 0.09)],
                                  center: .center, startRadius: 0, endRadius: diameter / 2)
        }
    }

    private func drawGrooves(in context: GraphicsContext, center: CGPoint, radius r: CGFloat) {
        let outer = r * 0.94, inner = r * 0.36
        let light = kind == .homeRecording
        // The grooves: fine rings across the playing surface.
        var groove = outer
        var odd = false
        while groove > inner {
            let ring = Path(ellipseIn: CGRect(x: center.x - groove, y: center.y - groove,
                                              width: groove * 2, height: groove * 2))
            context.stroke(ring, with: .color(light ? .black.opacity(odd ? 0.08 : 0.14) : .white.opacity(odd ? 0.035 : 0.07)),
                           lineWidth: 0.6)
            odd.toggle()
            groove -= max(1.2, r * 0.012)
        }
        // The gaps between songs: smooth, so they catch the light.
        for start in (grooves?.bandStarts ?? []).dropFirst() {
            let gap = outer - (outer - inner) * CGFloat(start)
            let ring = Path(ellipseIn: CGRect(x: center.x - gap, y: center.y - gap, width: gap * 2, height: gap * 2))
            context.stroke(ring, with: .color(light ? .white.opacity(0.55) : .white.opacity(0.2)),
                           lineWidth: max(1.5, r * 0.018))
        }
        // The lead-in at the edge and the run-out around the label.
        context.stroke(Path(ellipseIn: CGRect(x: center.x - r * 0.985, y: center.y - r * 0.985,
                                              width: r * 1.97, height: r * 1.97)),
                       with: .color(.white.opacity(light ? 0.4 : 0.12)), lineWidth: 1)
    }

    @ViewBuilder
    private var labelView: some View {
        if let still, let image = still.image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if still != nil, kind == .album {
            printedLabel(color: Color(red: 0.55, green: 0.12, blue: 0.12))
        } else {
            liveLabel
        }
    }

    @ViewBuilder
    private var liveLabel: some View {
        switch kind {
        case .album:
            switch label {
            case .album(let album): TapeArtwork(album: album, size: (diameter * 0.34).rounded())
            case .track(let track): TrackArtwork(track: track, size: (diameter * 0.34).rounded())
            case .plain:            printedLabel(color: Color(red: 0.55, green: 0.12, blue: 0.12))
            }
        case .homeRecording:
            // The playlist's own art, stuck on, when it has some; otherwise plain card,
            // written on in pen. (A still with no picture loaded keeps the pen.)
            if still == nil, case .album(let album) = label, album.hasPlaylistArtwork {
                TapeArtwork(album: album, size: (diameter * 0.34).rounded())
            } else {
                handwrittenLabel
            }
        case .transcription:
            printedLabel(color: Color(red: 0.12, green: 0.24, blue: 0.42), stamp: String(localized: "gramophone.record.broadcast"))
        }
    }

    private var handwrittenLabel: some View {
        ZStack {
            Circle().fill(SpoolPalette.label)
            Text(title)
                .font(.custom(SpoolPalette.handwriting, size: diameter * 0.04))
                .foregroundStyle(SpoolPalette.pen)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .padding(diameter * 0.04)
        }
    }

    private func printedLabel(color: Color, stamp: String? = nil) -> some View {
        ZStack {
            Circle().fill(color)
            VStack(spacing: diameter * 0.006) {
                if let stamp {
                    Text(stamp.uppercased())
                        .font(.system(size: diameter * 0.018, weight: .black, design: .serif))
                        .tracking(diameter * 0.002)
                        .opacity(0.8)
                }
                Text(title)
                    .font(.system(size: diameter * 0.03, weight: .bold, design: .serif))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.5)
            }
            .foregroundStyle(Color(red: 0.96, green: 0.88, blue: 0.64))
            .padding(diameter * 0.04)
        }
    }
}

/// The light across a record's face. It stays put while the record turns, as a
/// reflection does.
private struct RecordSheen: View {
    var body: some View {
        Circle()
            .fill(AngularGradient(stops: [
                .init(color: .white.opacity(0), location: 0.0),
                .init(color: .white.opacity(0.16), location: 0.08),
                .init(color: .white.opacity(0), location: 0.18),
                .init(color: .white.opacity(0), location: 0.5),
                .init(color: .white.opacity(0.12), location: 0.58),
                .init(color: .white.opacity(0), location: 0.68),
            ], center: .center))
            .allowsHitTesting(false)
    }
}

// MARK: - Turntable

/// The record on the turntable, as the player knows it.
struct RecordOnPlatter: Equatable {
    let kind: RecordKind
    let title: String
    let label: RecordLabel
    let grooves: GrooveMap
    /// The song playing, as a band on the record.
    let currentIndex: Int
    /// Identity, so a new record animates on.
    let id: String

    static func == (lhs: RecordOnPlatter, rhs: RecordOnPlatter) -> Bool {
        lhs.id == rhs.id && lhs.currentIndex == rhs.currentIndex && lhs.grooves == rhs.grooves
    }
}

/// The platter and the tonearm. Observes the playback clock on its own, so the
/// twice-a-second ticks redraw only the turntable: the record turns at 33⅓ and the
/// needle creeps inward across the bands.
struct TurntableView: View {
    @ObservedObject var clock: PlaybackClock
    let record: RecordOnPlatter?
    let isPlaying: Bool
    /// The arm on its rest rather than on the record.
    let isArmParked: Bool
    /// Lifted by a finger: the music pauses while it's carried.
    let onLift: () -> Void
    /// Put down on the record at a fraction across it, or back on its rest (nil).
    let onDrop: (Double?) -> Void
    /// Holding the record: show its sleeve.
    let onHoldRecord: () -> Void

    @Environment(\.gramophoneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The arm's angle while a finger carries it.
    @State private var carriedAngle: Double?
    @State private var dragBegan = false
    @State private var anchor: (time: TimeInterval, date: Date) = (0, .now)

    /// 33⅓ turns a minute.
    private static let degreesPerSecond = 200.0

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let (center, radius) = Self.platter(in: size)
            let arm = TonearmGeometry(center: center, radius: radius)

            ZStack(alignment: .topLeading) {
                platter(center: center, radius: radius)
                tonearm(arm, radius: radius)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            // Alongside the record's long press, so neither blocks the other.
            .simultaneousGesture(armDrag(arm, radius: radius))
            // Over the turntable rather than in it: a view with a gesture folds the
            // elements inside it into one, which would leave the arm as big as the
            // whole turntable to VoiceOver.
            .overlay(alignment: .topLeading) { armAccessibility(arm) }
        }
        .onAppear { anchor = (clock.time, .now) }
        .onReceive(clock.$time) { anchor = ($0, .now) }
        .onChange(of: isPlaying) { anchor = (clock.time, .now) }
    }

    /// Where the record lies in a turntable `size` big: its centre, left of the middle
    /// to leave the arm room on the right, and its radius. The 3D machine's camera comes
    /// down over its record to exactly here (see GramophoneStage).
    static func platter(in size: CGSize) -> (center: CGPoint, radius: CGFloat) {
        (CGPoint(x: size.width * 0.43, y: size.height * 0.54), min(size.width * 0.37, size.height * 0.42))
    }

    // MARK: Platter

    private func platter(center: CGPoint, radius: CGFloat) -> some View {
        ZStack {
            // The platter's rim, and the felt.
            Circle()
                .fill(theme.metalGradient)
                .frame(width: radius * 2.12, height: radius * 2.12)
                .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
            Circle()
                .fill(theme.felt)
                .frame(width: radius * 2.04, height: radius * 2.04)
            if let record {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying || reduceMotion)) { context in
                    RecordDisc(kind: record.kind, title: record.title, label: record.label,
                               grooves: record.grooves, diameter: radius * 2)
                        .rotationEffect(.degrees(spin(at: context.date)))
                }
                .overlay(RecordSheen())
                .frame(width: radius * 2, height: radius * 2)
                .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
                .transition(.scale(scale: 1.12).combined(with: .opacity))
                .id(record.id)
                .onLongPressGesture(minimumDuration: 0.5) { onHoldRecord() }
                .accessibilityElement()
                .accessibilityLabel(String(format: String(localized: "gramophone.record.a11y"), record.title))
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(String(localized: "gramophone.record.hint"))
                .accessibilityIdentifier("gramophone.record")
                .accessibilityAction { onHoldRecord() }
            }
            // The spindle.
            Circle()
                .fill(theme.metalGradient)
                .frame(width: radius * 0.05, height: radius * 0.05)
        }
        .position(center)
    }

    private func spin(at date: Date) -> Double {
        let elapsed = isPlaying ? min(max(date.timeIntervalSince(anchor.date), 0), 1) : 0
        return (anchor.time + elapsed) * Self.degreesPerSecond
    }

    // MARK: Tonearm

    /// Where the needle sits now: carried, resting, or riding the groove.
    private func currentAngle(_ arm: TonearmGeometry) -> Double {
        if let carriedAngle { return carriedAngle }
        guard let record, !isArmParked else { return arm.restAngle }
        return arm.angle(forFraction: record.grooves.fraction(track: record.currentIndex, time: clock.time))
    }

    private func tonearm(_ arm: TonearmGeometry, radius: CGFloat) -> some View {
        let angle = currentAngle(arm)
        let isLifted = carriedAngle != nil
        return ZStack(alignment: .topLeading) {
            // The arm itself: a tapered tube from the pivot to the soundbox, turned
            // about the pivot.
            ArmShape()
                .fill(theme.metalGradient)
                .overlay(ArmShape().stroke(theme.metalDark.opacity(0.6), lineWidth: 0.8))
                .frame(width: arm.armLength, height: radius * 0.16)
                .overlay(alignment: .trailing) {
                    soundbox(radius: radius)
                }
                .rotationEffect(.radians(angle), anchor: .leading)
                .offset(x: arm.pivot.x, y: arm.pivot.y - radius * 0.08)
                // Lifted, it rises off the record: bigger, with a longer shadow.
                .shadow(color: .black.opacity(0.45), radius: isLifted ? 9 : 3, x: 0, y: isLifted ? 8 : 2)
                .animation(carriedAngle == nil ? .spring(response: 0.5, dampingFraction: 0.85) : nil, value: angle)

            // The pivot's base.
            Circle()
                .fill(theme.metalGradient)
                .overlay(Circle().strokeBorder(theme.metalDark, lineWidth: 1.5))
                .overlay(Circle().fill(theme.metalDark).frame(width: radius * 0.08, height: radius * 0.08))
                .frame(width: radius * 0.3, height: radius * 0.3)
                .position(arm.pivot)
                .shadow(color: .black.opacity(0.4), radius: 3, y: 2)

        }
    }

    /// The arm, for VoiceOver: the song under the needle, and moving it a song. A square
    /// at the needle, placed by padding so its frame is where it's drawn.
    private func armAccessibility(_ arm: TonearmGeometry) -> some View {
        let needle = arm.needle(at: currentAngle(arm))
        return Color.white.opacity(0.001)
            .frame(width: 44, height: 44)
            .accessibilityElement()
            .accessibilityLabel(String(localized: "gramophone.tonearm"))
            .accessibilityValue(armValue)
            .accessibilityIdentifier("gramophone.tonearm")
            .accessibilityAdjustableAction { direction in
                guard let record else { return }
                let target = direction == .increment ? record.currentIndex + 1 : record.currentIndex - 1
                let starts = record.grooves.bandStarts
                guard starts.indices.contains(target) else { return }
                onDrop(starts[target] + 0.0001)
            }
            .accessibilityAction(named: String(localized: isArmParked ? "gramophone.tonearm.lower" : "gramophone.tonearm.lift")) {
                if isArmParked {
                    onDrop(record.map { $0.grooves.fraction(track: $0.currentIndex, time: clock.time) })
                } else {
                    onLift()
                    onDrop(nil)
                }
            }
            .allowsHitTesting(false)
            .padding(.leading, max(0, needle.x - 22))
            .padding(.top, max(0, needle.y - 22))
    }

    private var armValue: String {
        guard let record else { return String(localized: "gramophone.tonearm.noRecord") }
        if isArmParked { return String(localized: "gramophone.tonearm.resting") }
        return String(format: String(localized: "gramophone.tonearm.value"),
                      record.currentIndex + 1, record.grooves.durations.count)
    }

    /// The soundbox at the arm's end, with the needle under it.
    private func soundbox(radius: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(theme.metalGradient)
                .overlay(Circle().strokeBorder(theme.metalDark, lineWidth: 1.5))
                .overlay(
                    Circle()
                        .fill(RadialGradient(colors: [theme.metalLight, theme.metalDark], center: .center,
                                             startRadius: 0, endRadius: radius * 0.1))
                        .padding(radius * 0.04)
                )
            Circle()
                .fill(Color.black)
                .frame(width: radius * 0.035, height: radius * 0.035)
        }
        .frame(width: radius * 0.26, height: radius * 0.26)
        // Centred on the arm's end, where the needle is.
        .offset(x: radius * 0.13)
    }

    // MARK: Moving the Arm

    /// A finger on the arm lifts it and carries it; letting go drops it where it is —
    /// on the record to play from there, or off the record onto its rest to stop.
    private func armDrag(_ arm: TonearmGeometry, radius: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if !dragBegan {
                    dragBegan = true
                    // Only a touch on the arm takes hold of it.
                    let angle = currentAngle(arm)
                    let needle = arm.needle(at: angle)
                    let nearHead = hypot(value.startLocation.x - needle.x, value.startLocation.y - needle.y) < radius * 0.3
                    let nearArm = distance(from: value.startLocation, toSegment: arm.pivot, needle) < radius * 0.12
                    guard nearHead || nearArm else { return }
                    carriedAngle = angle
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if !isArmParked { onLift() }
                }
                guard carriedAngle != nil else { return }
                carriedAngle = arm.angle(toward: value.location)
            }
            .onEnded { _ in
                defer { dragBegan = false }
                guard let angle = carriedAngle else { return }
                let fraction = record == nil ? nil : arm.fraction(at: angle)
                // Settle where it was let go, then hand over: the arm then follows the
                // groove, or goes to its rest.
                carriedAngle = nil
                onDrop(fraction)
            }
    }

    private func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = dx * dx + dy * dy
        guard length > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / length))
        return hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
    }
}

/// The arm's tube, tapering from the pivot to the soundbox, laid along +x.
private struct ArmShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let mid = rect.midY
        path.move(to: CGPoint(x: rect.minX, y: mid - rect.height * 0.3))
        path.addLine(to: CGPoint(x: rect.maxX, y: mid - rect.height * 0.14))
        path.addLine(to: CGPoint(x: rect.maxX, y: mid + rect.height * 0.14))
        path.addLine(to: CGPoint(x: rect.minX, y: mid + rect.height * 0.3))
        path.closeSubpath()
        return path
    }
}

// MARK: - Crank

/// The winding crank, as a finger works it. The crank is drawn in 3D on the machine's
/// right-hand side, seen almost edge-on from the front, so its handle goes down and up
/// as it turns: running a finger down or up over it turns it on, and the ratchet ticks;
/// a full turn winds the spring and shuffles. It only ever turns forward, as a ratchet
/// does.
struct GramophoneCrank: View {
    /// The handle's angle in degrees, for the drawing.
    @Binding var angle: Double
    /// Each tooth of the ratchet passing.
    let onTooth: () -> Void
    /// A full turn.
    let onWound: () -> Void

    @State private var wound: Double = 0
    @State private var lastLocation: CGPoint?

    private static let toothDegrees = 30.0
    /// How far the handle turns for a finger moving the control's height.
    private static let degreesPerHeight = 200.0

    var body: some View {
        GeometryReader { geometry in
            Color.white.opacity(0.001)
                .contentShape(Rectangle())
                .gesture(turn(height: geometry.size.height))
        }
        .accessibilityElement()
        .accessibilityLabel(String(localized: "gramophone.crank"))
        .accessibilityHint(String(localized: "gramophone.crank.hint"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("gramophone.crank")
        .accessibilityAction { onWound() }
    }

    private func turn(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                defer { lastLocation = value.location }
                guard let last = lastLocation else { return }
                // Down and up both carry the handle on round; across, less so.
                let moved = abs(value.location.y - last.y) + abs(value.location.x - last.x) * 0.5
                let delta = Double(moved / max(height, 1)) * Self.degreesPerHeight
                guard delta > 0 else { return }
                let before = Int(wound / Self.toothDegrees)
                angle += delta
                wound += delta
                if Int(wound / Self.toothDegrees) > before { onTooth() }
                if wound >= 360 {
                    wound = 0
                    onWound()
                }
            }
            .onEnded { _ in lastLocation = nil }
    }
}

// MARK: - Levers

/// The start/stop brake: tipped to Start while the record plays, to Stop when it doesn't.
struct BrakeLever: View {
    let isPlaying: Bool
    let action: () -> Void
    @Environment(\.gramophoneTheme) private var theme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack(alignment: .bottom) {
                    // The slot the lever swings in, with its marks.
                    HStack {
                        Text(String(localized: "gramophone.brake.stop")).opacity(isPlaying ? 0.45 : 1)
                        Spacer(minLength: 0)
                        Text(String(localized: "gramophone.brake.start")).opacity(isPlaying ? 1 : 0.45)
                    }
                    .font(.system(size: 7, weight: .heavy, design: .serif))
                    .foregroundStyle(theme.ink)
                    .frame(width: 58)
                    .offset(y: -22)
                    Capsule()
                        .fill(theme.metalGradient)
                        .frame(width: 5, height: 26)
                        .overlay(alignment: .top) {
                            Circle().fill(theme.metalGradient).frame(width: 11, height: 11).offset(y: -4)
                        }
                        .rotationEffect(.degrees(isPlaying ? 32 : -32), anchor: .bottom)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPlaying)
                    Capsule().fill(theme.metalDark).frame(width: 18, height: 5)
                }
                .frame(width: 64, height: 40)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: isPlaying ? "gramophone.brake.a11y.stop" : "gramophone.brake.a11y.start"))
        .accessibilityIdentifier("gramophone.brake")
    }
}

/// The speed regulator. It sets a podcast's speed; music always plays at its own, so for
/// music it rests at its mark and can't be moved.
struct SpeedRegulator: View {
    let isEnabled: Bool
    let rate: Float
    /// False over the 3D machine's knob, which draws itself.
    var isDrawn = true
    let onSet: (Float) -> Void
    @Environment(\.gramophoneTheme) private var theme

    var body: some View {
        Menu {
            ForEach(MusicService.podcastRates, id: \.self) { option in
                Button {
                    onSet(option)
                } label: {
                    if option == rate {
                        Label(SpoolPlayerView.speedText(option), systemImage: "checkmark")
                    } else {
                        Text(SpoolPlayerView.speedText(option))
                    }
                }
            }
        } label: {
            if isDrawn { face } else { Color.clear.contentShape(Rectangle()) }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled || !isDrawn ? 1 : 0.65)
        .accessibilityLabel(String(localized: "spool.speed"))
        .accessibilityValue(isEnabled ? SpoolPlayerView.speedText(rate) : "33⅓")
        .accessibilityIdentifier("gramophone.speed")
    }

    private var face: some View {
            VStack(spacing: 2) {
                Text(String(localized: "gramophone.speed").uppercased())
                    .font(.system(size: 7, weight: .heavy, design: .serif))
                    .tracking(1)
                    .foregroundStyle(theme.ink.opacity(0.8))
                Text(isEnabled ? SpoolPlayerView.speedText(rate) : "33⅓")
                    .font(.system(size: 12, weight: .bold, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(theme.plateInk)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(theme.metalGradient, in: RoundedRectangle(cornerRadius: 4))
            }
            .frame(minWidth: 52, minHeight: 44)
            .contentShape(Rectangle())
    }
}

// MARK: - Up Next Pile

/// The records waiting their turn, stacked on the corner of the machine. Tapping the
/// pile brings up Up Next.
struct UpNextPile: View {
    let count: Int
    let action: () -> Void
    @Environment(\.gramophoneTheme) private var theme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    ForEach(0..<min(3, max(1, count)), id: \.self) { layer in
                        Ellipse()
                            .fill(RadialGradient(colors: [Color(white: 0.15), Color(white: 0.04)],
                                                 center: .center, startRadius: 0, endRadius: 22))
                            .overlay(Ellipse().fill(theme.paper.opacity(0.9)).frame(width: 14, height: 5))
                            .frame(width: 46, height: 15)
                            .offset(y: CGFloat(-layer) * 5)
                    }
                }
                .opacity(count > 0 ? 1 : 0.35)
                .frame(height: 28)
                HStack(spacing: 4) {
                    Text(String(localized: "spool.queue.title").uppercased())
                        .tracking(1)
                    if count > 0 {
                        Text("\(count)")
                            .monospacedDigit()
                            .padding(.horizontal, 5)
                            .background(theme.ink.opacity(0.18), in: Capsule())
                    }
                }
                .font(.system(size: 9, weight: .heavy, design: .serif))
                .foregroundStyle(theme.ink.opacity(0.9))
            }
            .frame(minWidth: 64, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "spool.queue.open"))
        .accessibilityValue(count > 0 ? String(format: String(localized: "queue.upNextCount"), count) : "")
        .accessibilityIdentifier("gramophone.upNext")
    }
}

// MARK: - Nameplate

/// The brass plate on the front, engraved with the maker's name, and the song playing
/// printed on a card slipped into its frame.
struct Nameplate: View {
    let title: String
    let subtitle: String
    @Environment(\.gramophoneTheme) private var theme

    var body: some View {
        VStack(spacing: 3) {
            Text(String(localized: "gramophone.brand").uppercased())
                .font(.system(size: 11, weight: .heavy, design: .serif))
                .tracking(4)
                .foregroundStyle(theme.plateInk)
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                Text(subtitle)
                    .font(.system(size: 11, design: .serif))
                    .italic()
                    .opacity(0.75)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(SpoolPalette.labelInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(theme.paper, in: RoundedRectangle(cornerRadius: 3))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.metalGradient)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.metalDark, lineWidth: 1.5))
                .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("gramophone.nameplate")
    }
}

// MARK: - Sketch

/// A small drawing of a design in a finish, as the instruction booklet and onboarding
/// show it. Drawn 88 points tall.
struct GramophoneSketch: View {
    let model: GramophoneModel
    let theme: GramophoneTheme

    var body: some View {
        Group {
            switch model {
            case .horn:    horn
            case .cabinet: cabinet
            }
        }
        .frame(height: 88)
        .accessibilityHidden(true)
    }

    /// A box with the turntable on top and the horn's bell over it.
    private var horn: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 4)
                .fill(theme.woodGradient)
                .frame(width: 70, height: 30)
            Ellipse()
                .fill(theme.felt)
                .overlay(Ellipse().fill(Color(white: 0.08)).padding(4))
                .frame(width: 50, height: 12)
                .offset(x: -6, y: -26)
            Capsule()
                .fill(theme.metalGradient)
                .frame(width: 4, height: 36)
                .rotationEffect(.degrees(-20))
                .offset(x: 18, y: -38)
            Ellipse()
                .fill(theme.metalGradient)
                .overlay(Ellipse().fill(RadialGradient(colors: [.black, theme.metalDark], center: .center,
                                                       startRadius: 0, endRadius: 20)).padding(4))
                .frame(width: 46, height: 40)
                .offset(x: 2, y: -48)
        }
        .frame(width: 80, height: 88, alignment: .bottom)
    }

    /// An upright console with its lid up and louvered doors.
    private var cabinet: some View {
        VStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 3)
                .fill(theme.woodGradient)
                .frame(width: 54, height: 10)
                .rotation3DEffect(.degrees(50), axis: (x: 1, y: 0, z: 0), anchor: .bottom)
            VStack(spacing: 4) {
                Ellipse()
                    .fill(theme.felt)
                    .overlay(Ellipse().fill(Color(white: 0.08)).padding(3))
                    .frame(width: 34, height: 8)
                HStack(spacing: 2) {
                    ForEach(0..<2, id: \.self) { _ in
                        VStack(spacing: 2) {
                            ForEach(0..<5, id: \.self) { _ in
                                Capsule().fill(theme.woodDark).frame(height: 2)
                            }
                        }
                        .padding(3)
                        .frame(width: 22, height: 30)
                        .background(theme.woodLight.opacity(0.6), in: RoundedRectangle(cornerRadius: 2))
                    }
                }
                Capsule().fill(theme.metalGradient).frame(width: 14, height: 3)
            }
            .padding(5)
            .frame(width: 58)
            .background(theme.woodGradient, in: RoundedRectangle(cornerRadius: 4))
        }
        .frame(width: 80, height: 88)
    }
}
