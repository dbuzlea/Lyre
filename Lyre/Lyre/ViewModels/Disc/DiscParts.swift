//
//  DiscParts.swift
//  Lyre
//

import SwiftUI

// MARK: - Disc Parts
//
// The pieces the Disc player is drawn from:
//
//   CompactDisc     a disc, label side up: an album's pressed with its cover, a
//                   playlist's a burned CD-R with its name in marker, a show's an
//                   enhanced CD with the show's art and a printed band
//   DiscSpinner     turns a disc while it plays, carrying on from wherever it stopped,
//                   with the light catching its rim standing still
//   JewelCaseCard   a disc in its case on the shelf
//   DiscLCD         the display: track, time, a scrolling title, and the modes
//   DiscKey         a rubber key, which can also be held

/// What kind of disc something is pressed as.
enum DiscKind: Equatable {
    /// A pressed album, its cover printed across the label.
    case pressed
    /// A CD-R a playlist was burned onto, its name written on in marker.
    case burned
    /// A show's episodes, on an enhanced CD.
    case enhanced

    init(_ album: AppAlbum?) {
        if album?.isPodcast == true {
            self = .enhanced
        } else if album == nil || album?.isMixtape == true {
            self = .burned
        } else {
            self = .pressed
        }
    }
}

/// What's printed on a disc's label.
enum DiscArt {
    case album(AppAlbum)
    /// A song's cover: a disc taken from Up Next.
    case track(AppTrack)
    case none
}

// MARK: - Compact Disc

struct CompactDisc: View {
    let kind: DiscKind
    let art: DiscArt
    /// Written on a burned disc, and printed small on the others.
    let title: String
    let diameter: CGFloat

    /// The centre hole, the clear hub around it, and where the printing starts.
    static let holeRatio: CGFloat = 0.15
    static let hubRatio: CGFloat = 0.34

    var body: some View {
        let d = diameter
        ZStack {
            // The disc's metal, seen past the printing at the rim and the hub.
            Circle()
                .fill(AngularGradient(colors: [Color(white: 0.92), Color(white: 0.72), Color(white: 0.95),
                                               Color(white: 0.68), Color(white: 0.9), Color(white: 0.75),
                                               Color(white: 0.92)],
                                      center: .center))

            label
                .frame(width: d * 0.96, height: d * 0.96)
                .clipShape(Circle())

            // The clear hub: plastic with nothing on it, and the stacking ring.
            Circle()
                .fill(Color(white: 0.86).opacity(0.85))
                .frame(width: d * Self.hubRatio, height: d * Self.hubRatio)
            Circle()
                .strokeBorder(Color(white: 0.6).opacity(0.7), lineWidth: max(0.5, d * 0.006))
                .frame(width: d * Self.hubRatio * 0.62, height: d * Self.hubRatio * 0.62)

            // The clear rim, where the light splits into colours.
            Circle()
                .strokeBorder(AngularGradient(colors: [.cyan, .purple, .pink, .yellow, .green, .cyan],
                                              center: .center).opacity(0.35),
                              lineWidth: max(1, d * 0.02))

            // The hole, punched through.
            Circle()
                .frame(width: d * Self.holeRatio, height: d * Self.holeRatio)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .frame(width: d, height: d)
        .accessibilityHidden(true)
    }

    /// The printed (or written-on) side, inside the rim, with the hub left clear.
    @ViewBuilder
    private var label: some View {
        let d = diameter * 0.96
        switch kind {
        case .pressed:
            artwork(size: d)
                .overlay(alignment: .bottom) { smallPrint.padding(.bottom, d * 0.06) }
        case .burned:
            // The CD-R's gold top, and its name written across it in marker.
            ZStack {
                AngularGradient(colors: [Color(red: 0.93, green: 0.82, blue: 0.5), Color(red: 0.78, green: 0.62, blue: 0.3),
                                         Color(red: 0.96, green: 0.88, blue: 0.6), Color(red: 0.74, green: 0.58, blue: 0.28),
                                         Color(red: 0.93, green: 0.82, blue: 0.5)],
                                center: .center)
                Text(title)
                    .font(.custom(SpoolPalette.handwriting, size: max(8, d * 0.1)))
                    .foregroundStyle(Color(red: 0.08, green: 0.1, blue: 0.22))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .rotationEffect(.degrees(-8))
                    .frame(width: d * 0.62)
                    .offset(y: -d * 0.28)
                Text(String(localized: "disc.print.cdr80"))
                    .font(.system(size: max(4, d * 0.035), weight: .heavy))
                    .tracking(d * 0.004)
                    .foregroundStyle(.black.opacity(0.45))
                    .offset(y: d * 0.36)
            }
        case .enhanced:
            artwork(size: d)
                .overlay(alignment: .bottom) {
                    Text(String(localized: "disc.enhanced").uppercased())
                        .font(.system(size: max(4, d * 0.04), weight: .black))
                        .tracking(d * 0.006)
                        .foregroundStyle(.white)
                        .frame(width: d, height: d * 0.13)
                        .background(.black.opacity(0.8))
                        .padding(.bottom, d * 0.1)
                }
        }
    }

    @ViewBuilder
    private func artwork(size: CGFloat) -> some View {
        let side = size.rounded()
        switch art {
        case .album(let album):
            TapeArtwork(album: album, size: side)
                .frame(width: size, height: size)
        case .track(let track):
            TrackArtwork(track: track, size: side)
                .frame(width: size, height: size)
        case .none:
            LinearGradient(colors: [Color(white: 0.3), Color(white: 0.15)], startPoint: .top, endPoint: .bottom)
        }
    }

    /// The tiny print round a pressed disc's edge.
    private var smallPrint: some View {
        Text(String(localized: "disc.print.digitalAudio"))
            .font(.system(size: max(3, diameter * 0.03), weight: .heavy))
            .tracking(diameter * 0.004)
            .foregroundStyle(.white.opacity(0.85))
            .shadow(color: .black.opacity(0.6), radius: 1)
    }
}

// MARK: - Spinner

/// Turns its content while `isSpinning`, stopping where it was and carrying on from
/// there, the way a disc coasts to a stop under the lid. The angle is worked out from
/// the time on each frame rather than animated, so it never builds up a backlog.
struct DiscSpinner<Content: View>: View {
    let isSpinning: Bool
    /// Turns a second.
    var speed: Double = 0.55
    /// The most it's redrawn a second: 60 for a disc in view, less for a small one.
    var frameRate: Double = 60
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var base: Double = 0
    @State private var startedAt: Date?

    var body: some View {
        let spins = isSpinning && !reduceMotion
        TimelineView(.animation(minimumInterval: 1 / frameRate, paused: !spins)) { context in
            content()
                .rotationEffect(.degrees(angle(at: context.date)))
        }
        .onChange(of: spins, initial: true) { _, spinning in
            if spinning {
                startedAt = .now
            } else {
                base = angle(at: .now)
                startedAt = nil
            }
        }
    }

    private func angle(at date: Date) -> Double {
        guard let startedAt else { return base }
        return (base + date.timeIntervalSince(startedAt) * speed * 360).truncatingRemainder(dividingBy: 360)
    }
}

/// The light on a disc: bands of colour that stay put while the disc turns under them.
struct DiscSheen: View {
    let diameter: CGFloat

    var body: some View {
        ZStack {
            AngularGradient(stops: [.init(color: .clear, location: 0),
                                    .init(color: .white.opacity(0.35), location: 0.08),
                                    .init(color: .clear, location: 0.16),
                                    .init(color: .clear, location: 0.5),
                                    .init(color: .white.opacity(0.28), location: 0.58),
                                    .init(color: .clear, location: 0.66)],
                            center: .center, angle: .degrees(-30))
            AngularGradient(colors: [.clear, .cyan.opacity(0.18), .purple.opacity(0.14), .clear, .clear,
                                     .yellow.opacity(0.14), .pink.opacity(0.16), .clear],
                            center: .center, angle: .degrees(20))
        }
        .frame(width: diameter, height: diameter)
        .mask {
            ZStack {
                Circle()
                Circle()
                    .frame(width: diameter * CompactDisc.holeRatio, height: diameter * CompactDisc.holeRatio)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Jewel Case

/// A disc on the shelf in its case: the booklet's cover behind the lid, the black
/// hinge down the left. A burned disc's case holds a paper insert written on by hand;
/// an enhanced CD has a printed band across its cover.
struct JewelCaseCard: View, Equatable {
    let album: AppAlbum
    let size: CGSize
    /// The side the hinge runs down: the left seen from the front, the right from inside
    /// the open lid.
    var hingeEdge: HorizontalEdge = .leading

    /// Width : height of a jewel case.
    static let aspectRatio: CGFloat = 142.0 / 125.0

    static func == (lhs: JewelCaseCard, rhs: JewelCaseCard) -> Bool {
        lhs.album.id == rhs.album.id && lhs.size == rhs.size && lhs.hingeEdge == rhs.hingeEdge
    }

    var body: some View {
        let w = size.width, h = size.height
        let hinge = w * 0.075
        let corner = w * 0.02
        HStack(spacing: 0) {
            if hingeEdge == .trailing {
                insert
                    .frame(width: w - hinge, height: h)
                    .clipped()
            }
            // The hinge: black plastic with its ridges.
            ZStack {
                Color(white: 0.08)
                VStack(spacing: h * 0.06) {
                    ForEach(0..<8, id: \.self) { _ in
                        Rectangle().fill(.white.opacity(0.12)).frame(height: max(0.5, h * 0.008))
                    }
                }
                .padding(.horizontal, hinge * 0.25)
            }
            .frame(width: hinge)

            if hingeEdge == .leading {
                insert
                    .frame(width: w - hinge, height: h)
                    .clipped()
            }
        }
        .frame(width: w, height: h)
        // The lid: clear plastic over the insert, its edge and a glare across it.
        .overlay(
            LinearGradient(stops: [.init(color: .white.opacity(0.28), location: 0),
                                   .init(color: .white.opacity(0.04), location: 0.35),
                                   .init(color: .clear, location: 0.55),
                                   .init(color: .white.opacity(0.1), location: 1)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .allowsHitTesting(false)
        )
        .overlay(RoundedRectangle(cornerRadius: corner).strokeBorder(.white.opacity(0.45), lineWidth: max(1, w * 0.006)))
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .overlay(alignment: .topTrailing) {
            if let stamp = album.tapeFormat.stamp {
                Text(stamp.uppercased())
                    .font(.system(size: max(7, w * 0.045), weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, w * 0.025)
                    .padding(.vertical, w * 0.01)
                    .background(Color(red: 0.85, green: 0.2, blue: 0.2), in: Capsule())
                    .padding(w * 0.04)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: corner)
                .fill(.black)
                .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)
        )
    }

    @ViewBuilder
    private var insert: some View {
        let w = size.width, h = size.height
        switch DiscKind(album) {
        case .pressed:
            TapeArtwork(album: album, size: max(w, h).rounded())
                .frame(width: w, height: h)
        case .enhanced:
            TapeArtwork(album: album, size: max(w, h).rounded())
                .frame(width: w, height: h)
                .overlay(alignment: .bottom) {
                    Text(String(localized: "disc.enhanced").uppercased())
                        .font(.system(size: max(7, w * 0.05), weight: .black))
                        .tracking(w * 0.006)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, h * 0.035)
                        .background(.black.opacity(0.82))
                }
        case .burned:
            // Lined paper, the name in marker, and who made it.
            ZStack(alignment: .topLeading) {
                Color(red: 0.98, green: 0.97, blue: 0.93)
                VStack(spacing: h * 0.09) {
                    ForEach(0..<9, id: \.self) { _ in
                        Rectangle().fill(Color(red: 0.55, green: 0.7, blue: 0.9).opacity(0.5)).frame(height: 1)
                    }
                }
                .padding(.top, h * 0.18)
                Rectangle()
                    .fill(Color(red: 0.9, green: 0.4, blue: 0.4).opacity(0.5))
                    .frame(width: 1)
                    .padding(.leading, w * 0.12)
                VStack(alignment: .leading, spacing: h * 0.03) {
                    Text(album.tapeTitle)
                        .font(.custom(SpoolPalette.handwriting, size: max(10, h * 0.15)))
                        .foregroundStyle(SpoolPalette.pen)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                    if let byline = album.caseByline {
                        Text(byline)
                            .font(.custom(SpoolPalette.handwriting, size: max(8, h * 0.08)))
                            .foregroundStyle(SpoolPalette.pen.opacity(0.8))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text("CD-R")
                        .font(.system(size: max(7, h * 0.07), weight: .black, design: .rounded))
                        .foregroundStyle(.black.opacity(0.35))
                }
                .padding(.leading, w * 0.16)
                .padding(.trailing, w * 0.06)
                .padding(.vertical, h * 0.08)
            }
            .frame(width: w, height: h)
        }
    }
}

// MARK: - Display

/// The LCD: the track and the time on top, the title scrolling under them, and the
/// modes lit along the bottom. Tapping the time switches it between elapsed and left.
struct DiscLCD: View {
    @ObservedObject var clock: PlaybackClock
    let duration: TimeInterval
    /// The song's place on the disc, and how many there are; nil with no disc in.
    let track: (number: Int, count: Int)?
    let title: String
    let isPlaying: Bool
    let shuffle: Bool
    let repeatMode: RepeatMode
    /// The podcast speed, shown while a show plays.
    let rate: Float?
    /// Said where the time goes while a disc spins up or the lid is open.
    var status: String?
    @Binding var showsRemaining: Bool
    @Environment(\.discTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                segments(track.map { String(format: "%02d", $0.number) } ?? "--", ghost: "88", size: 26)
                    .accessibilityHidden(true)
                Text(String(localized: "disc.lcd.track").uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .opacity(0.7)
                Spacer(minLength: 4)
                Group {
                    if let status {
                        segments(status, ghost: nil, size: 22)
                    } else {
                        segments(timeText, ghost: "-88:88", size: 26)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    UISelectionFeedbackGenerator().selectionChanged()
                    showsRemaining.toggle()
                }
                .accessibilityElement()
                .accessibilityLabel(String(localized: showsRemaining ? "disc.lcd.remaining" : "disc.lcd.elapsed"))
                .accessibilityValue(timeText)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("disc.lcd.time")
            }

            DiscMarquee(text: title.uppercased(), isRunning: isPlaying)
                // Takes the display's width, however long the title is.
                .frame(minWidth: 0, maxWidth: .infinity)
                .frame(height: 18)
                .accessibilityLabel(title)
                .accessibilityIdentifier("disc.lcd.title")

            HStack(spacing: 8) {
                indicator(isPlaying ? "▶" : "❚❚", lit: true)
                indicator("RND", lit: shuffle)
                    .accessibilityIdentifier("disc.lcd.random")
                indicator(repeatMode == .one ? "REP 1" : "REP", lit: repeatMode != .off)
                    .accessibilityIdentifier("disc.lcd.repeat")
                Spacer(minLength: 4)
                if let rate {
                    indicator(SpoolPlayerView.speedText(rate), lit: true)
                }
                indicator("ESP", lit: true)
                track.map { indicator("\($0.count) TR", lit: true) }
            }
            .font(.system(size: 10, weight: .heavy, design: .monospaced))
        }
        .foregroundStyle(theme.lcdInk)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: [theme.lcd.opacity(0.92), theme.lcd], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.black.opacity(0.35), lineWidth: 2))
                .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)
        )
        // The display's own shadow under its segments.
        .shadow(color: theme.lcdInk.opacity(0.12), radius: 0, x: 1, y: 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("disc.lcd")
    }

    private var timeText: String {
        guard duration > 0 else { return AppHelpers.formatTime(clock.time) }
        if showsRemaining {
            return "-" + AppHelpers.formatTime(max(0, duration - clock.time))
        }
        return AppHelpers.formatTime(clock.time)
    }

    /// Digits, with the unlit segments faintly behind them.
    private func segments(_ text: String, ghost: String?, size: CGFloat) -> some View {
        ZStack(alignment: .trailing) {
            if let ghost {
                Text(ghost).opacity(0.08)
            }
            Text(text)
        }
        .font(.system(size: size, weight: .bold, design: .monospaced))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.4)
    }

    private func indicator(_ text: String, lit: Bool) -> some View {
        Text(text)
            .opacity(lit ? 1 : 0.1)
            .accessibilityHidden(!lit)
    }
}

/// A line of the display too long to fit, scrolling through it and pausing at the
/// start each time round. Short lines stand still.
struct DiscMarquee: View {
    let text: String
    var isRunning = true

    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let speed: CGFloat = 32
    private static let gap: CGFloat = 40
    private static let pause: Double = 1.6

    var body: some View {
        let overflows = textWidth > boxWidth && boxWidth > 0
        let runs = overflows && isRunning && !reduceMotion
        // Laid over the box from its leading edge, so a line longer than the box starts
        // at the left and runs off the right rather than spilling both ways.
        Color.clear
            .overlay(alignment: .leading) {
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !runs)) { context in
                    let offset = runs ? self.offset(at: context.date) : 0
                    HStack(spacing: Self.gap) {
                        label
                        if overflows { label }
                    }
                    .fixedSize()
                    .offset(x: -offset)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { boxWidth = $0 }
            .clipped()
        .background(
            label.hidden()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
        )
    }

    private var label: some View {
        Text(text)
            .font(.system(size: 14, weight: .bold, design: .monospaced))
            .lineLimit(1)
            .fixedSize()
    }

    private func offset(at date: Date) -> CGFloat {
        let cycle = Double((textWidth + Self.gap) / Self.speed)
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle + Self.pause)
        return t < Self.pause ? 0 : CGFloat(t - Self.pause) * Self.speed
    }
}

// MARK: - Keys

/// A rubber key. It gives under the finger and softly clicks; a key given `onHoldStart`
/// also does something for as long as it's held, past `holdDelay`, and letting go ends
/// it without the tap's action.
struct DiscKey: View {
    let symbol: String?
    var caption: String?
    let label: String
    var isAccent = false
    var size = CGSize(width: 72, height: 52)
    var onHoldStart: (() -> Void)?
    var onHoldEnd: (() -> Void)?
    let action: () -> Void

    static let holdDelay: Duration = .milliseconds(450)

    @State private var holdTask: Task<Void, Never>?
    @State private var isHolding = false
    @State private var pressWasHeld = false

    var body: some View {
        Button {
            guard !pressWasHeld else { return }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            action()
        } label: {
            VStack(spacing: 2) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                }
                if let caption {
                    Text(caption.uppercased())
                        .font(.system(size: symbol == nil ? 12 : 8, weight: .heavy))
                        .tracking(0.8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
        }
        .buttonStyle(DiscKeyStyle(isAccent: isAccent, size: size, onPressChange: pressChanged))
        .accessibilityLabel(label)
        .onDisappear { endHold() }
    }

    private func pressChanged(_ isDown: Bool) {
        if isDown { DiscSound.button.play() }
        guard onHoldStart != nil else { return }
        if isDown {
            pressWasHeld = false
            holdTask?.cancel()
            holdTask = Task {
                try? await Task.sleep(for: Self.holdDelay)
                guard !Task.isCancelled else { return }
                pressWasHeld = true
                isHolding = true
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                onHoldStart?()
            }
        } else {
            endHold()
        }
    }

    private func endHold() {
        holdTask?.cancel()
        holdTask = nil
        guard isHolding else { return }
        isHolding = false
        onHoldEnd?()
    }
}

private struct DiscKeyStyle: ButtonStyle {
    let isAccent: Bool
    let size: CGSize
    var onPressChange: (Bool) -> Void = { _ in }
    @Environment(\.discTheme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        let isDown = configuration.isPressed
        let colors = isAccent ? [theme.accentLight, theme.accent] : [theme.buttonLight, theme.button]
        return configuration.label
            .foregroundStyle(isAccent ? Color.white : theme.buttonSymbol)
            .frame(width: size.width, height: size.height)
            .background(
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().strokeBorder(.white.opacity(isDown ? 0.05 : 0.35), lineWidth: 1))
                    .overlay(Capsule().fill(.black.opacity(isDown ? 0.12 : 0)))
                    // The well the key sits in.
                    .shadow(color: .black.opacity(isDown ? 0.15 : 0.35), radius: isDown ? 1 : 3, x: 0, y: isDown ? 0 : 2)
            )
            .scaleEffect(isDown ? 0.95 : 1)
            .contentShape(Capsule())
            .animation(.easeOut(duration: 0.08), value: isDown)
            .onChange(of: configuration.isPressed) { _, pressed in onPressChange(pressed) }
    }
}

// MARK: - Arc Text

/// A line of print set round the bottom of a circle, reading left to right with each
/// letter's top towards the centre, as the lettering round a lid's window is. Centred on
/// the bottom of the circle; `radius` is where the letters' middles sit.
struct ArcText: View {
    let text: String
    let radius: CGFloat
    let fontSize: CGFloat
    var tracking: CGFloat = 0
    var weight: UIFont.Weight = .bold

    var body: some View {
        let font = UIFont.systemFont(ofSize: fontSize, weight: weight)
        let letters = Array(text)
        // Each letter's advance along the arc, measured in the font it's drawn in.
        let widths = letters.map { (String($0) as NSString).size(withAttributes: [.font: font]).width + tracking }
        let total = widths.reduce(0, +)
        ZStack {
            ForEach(letters.indices, id: \.self) { index in
                let along = widths[..<index].reduce(0, +) + widths[index] / 2 - total / 2
                // Left of centre is further round the circle; the bottom is 90° down.
                let angle = Double.pi / 2 - Double(along / radius)
                Text(String(letters[index]))
                    .font(Font(font))
                    .rotationEffect(.radians(angle - .pi / 2))
                    .offset(x: radius * CGFloat(cos(angle)), y: radius * CGFloat(sin(angle)))
            }
        }
        .frame(width: radius * 2, height: radius * 2)
        .accessibilityElement()
        .accessibilityLabel(text)
    }
}
