//
//  CassetteView.swift
//  Lyre
//

import SwiftUI

// MARK: - Cassette
//
// A smoked-plastic cassette seen through the deck's window. The reels are driven by
// `TapeTransport`, so their packs grow and shrink over the song and they spin at the
// speed a real tape would.
//
// The playback clock only ticks twice a second, which would make the reels stutter. While
// playing, a TimelineView extrapolates from the last tick at display rate; the next tick
// corrects any drift. Paused, the timeline stops and the reels rest on the clock's value.
//
// `axis` picks the orientation: `.horizontal` is a cassette lying flat, `.vertical` stands
// it on its end, as in the Spool's closed portrait layout.

struct CassetteView: View {
    @ObservedObject var clock: PlaybackClock
    let duration: TimeInterval
    let isPlaying: Bool
    /// Printed on the label. Nil shows a blank label.
    let title: String?
    /// Artwork printed across the label. Nil leaves it plain.
    var labelArt: TapeLabelArt?
    var format: TapeFormat = .album
    var trackCount: Int?
    /// A mixtape's blank, "C90", printed on its label.
    var blank: String?
    var axis: Axis = .horizontal

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The clock's last tick and when it arrived, for extrapolating between ticks.
    @State private var anchor: (time: TimeInterval, date: Date) = (0, .now)

    /// Width : height of a cassette shell lying flat (100 × 64 mm).
    static let aspectRatio: CGFloat = 100.0 / 64.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying || reduceMotion)) { context in
            let transport = TapeTransport(time: displayedTime(at: context.date), duration: duration)
            GeometryReader { geometry in
                let shellSize = axis == .horizontal
                    ? geometry.size
                    : CGSize(width: geometry.size.height, height: geometry.size.width)
                CassetteShell(transport: transport, title: title, size: shellSize, labelArt: labelArt,
                              format: format, trackCount: trackCount, blank: blank)
                    .frame(width: shellSize.width, height: shellSize.height)
                    .rotationEffect(axis == .horizontal ? .zero : .degrees(90))
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .aspectRatio(axis == .horizontal ? Self.aspectRatio : 1 / Self.aspectRatio, contentMode: .fit)
        .onAppear { anchor = (clock.time, .now) }
        .onReceive(clock.$time) { anchor = ($0, .now) }
        .onChange(of: isPlaying) { anchor = (clock.time, .now) }
        .accessibilityElement()
        .accessibilityLabel(String(format: String(localized: "spool.cassette.a11y"),
                                   title ?? String(localized: "spool.noTape")))
    }

    private func displayedTime(at date: Date) -> TimeInterval {
        guard isPlaying else { return anchor.time }
        // Capped so a stalled clock can't run the reels away from the real position.
        let elapsed = min(max(date.timeIntervalSince(anchor.date), 0), 1)
        let time = anchor.time + elapsed
        return duration > 0 ? min(time, duration) : time
    }
}

// MARK: - Shell

/// The cassette itself, lying flat, drawn at `size`. CassetteView animates one for the
/// deck; the tape carousel and the insert animation draw still ones directly.
struct CassetteShell: View {
    let transport: TapeTransport
    let title: String?
    let size: CGSize
    /// Artwork covering the label. Nil leaves a plain cream label.
    var labelArt: TapeLabelArt?
    /// A cassingle (single or EP) gets a coloured shell, a short pack of tape and its
    /// format stamped where an album's side letter goes.
    var format: TapeFormat = .album
    /// Printed at the end of an album's title strip, when known.
    var trackCount: Int?
    /// A mixtape's blank, "C90", printed where an album's song count goes.
    var blank: String?

    /// A tape sitting at the start of side A.
    static let resting = TapeTransport(time: 0, duration: 1)

    var body: some View {
        let w = size.width
        let h = size.height
        let reelSpacing = w * 0.36
        let reelDiameter = h * 0.44

        ZStack {
            // Plastic body: smoked for an album, coloured for a cassingle, white for a
            // blank taped at home
            RoundedRectangle(cornerRadius: w * 0.04)
                .fill(LinearGradient(colors: [shellColours.top, shellColours.bottom],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: w * 0.04)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )

            // Label
            label
                .position(x: w / 2, y: h * 0.42)

            // Window with the reels
            RoundedRectangle(cornerRadius: h * 0.06)
                .fill(SpoolPalette.window)
                .frame(width: w * 0.68, height: h * 0.52)
                .position(x: w / 2, y: h * 0.47)

            Reel(packRadius: pack(transport.supplyRadius), angle: transport.supplyAngle)
                .frame(width: reelDiameter, height: reelDiameter)
                .position(x: w / 2 - reelSpacing / 2, y: h * 0.47)
            Reel(packRadius: pack(transport.takeUpRadius), angle: transport.takeUpAngle)
                .frame(width: reelDiameter, height: reelDiameter)
                .position(x: w / 2 + reelSpacing / 2, y: h * 0.47)

            // Lower bridge where the tape meets the head
            BridgeShape()
                .fill(shellColours.bottom.opacity(0.9))
                .overlay(BridgeShape().stroke(.white.opacity(0.06), lineWidth: 1))
                .frame(width: w * 0.64, height: h * 0.18)
                .position(x: w / 2, y: h * 0.90)

            // Screws
            ForEach(Array(screwPositions(w: w, h: h).enumerated()), id: \.offset) { _, point in
                Circle()
                    .fill(SpoolPalette.screw)
                    .frame(width: w * 0.03, height: w * 0.03)
                    .position(point)
            }
        }
    }

    private var shellColours: (top: Color, bottom: Color) {
        switch format {
        case .single, .ep: return (SpoolPalette.singleShellTop, SpoolPalette.singleShellBottom)
        case .mixtape:     return (SpoolPalette.mixtapeShellTop, SpoolPalette.mixtapeShellBottom)
        case .spokenWord:  return (SpoolPalette.spokenWordShellTop, SpoolPalette.spokenWordShellBottom)
        case .album:       return (SpoolPalette.shellTop, SpoolPalette.shellBottom)
        }
    }

    @ViewBuilder
    private var label: some View {
        if format == .mixtape {
            handwrittenLabel
        } else {
            printedLabel
        }
    }

    /// A blank's label, written on in pen: the printed side letter and length, a few
    /// ruled lines, and the tape's name in handwriting.
    private var handwrittenLabel: some View {
        let labelSize = CGSize(width: size.width * 0.86, height: size.height * 0.70)
        let shape = RoundedRectangle(cornerRadius: size.width * 0.02)
        return ZStack(alignment: .topLeading) {
            shape.fill(SpoolPalette.label)
            // Ruled lines across the strip above the window.
            VStack(spacing: size.height * 0.055) {
                ForEach(0..<2, id: \.self) { _ in
                    Rectangle()
                        .fill(SpoolPalette.mixtapeRule)
                        .frame(height: max(0.5, size.height * 0.006))
                }
            }
            .padding(.horizontal, size.width * 0.04)
            .padding(.top, size.height * 0.115)
            HStack(alignment: .firstTextBaseline, spacing: size.width * 0.03) {
                Text(String(localized: "spool.sideA"))
                    .font(.system(size: size.height * 0.11, weight: .heavy, design: .rounded))
                    .foregroundStyle(SpoolPalette.labelInk)
                Text(title ?? "")
                    .font(.custom(SpoolPalette.handwriting, size: size.height * 0.08))
                    .foregroundStyle(SpoolPalette.pen)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .rotationEffect(.degrees(-1.5))
                Spacer(minLength: 0)
                if let blank {
                    Text(blank)
                        .font(.system(size: size.height * 0.06, weight: .black, design: .rounded))
                        .foregroundStyle(SpoolPalette.label)
                        .padding(.horizontal, size.height * 0.025)
                        .padding(.vertical, size.height * 0.006)
                        .background(SpoolPalette.labelInk, in: RoundedRectangle(cornerRadius: size.height * 0.015))
                        .fixedSize()
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, size.width * 0.04)
            .padding(.top, size.height * 0.035)
        }
        .frame(width: labelSize.width, height: labelSize.height)
        .clipShape(shape)
    }

    /// A word printed in a coloured box on the label: "SINGLE", "SPOKEN WORD".
    private func chip(_ text: String, colour: Color, scale: CGFloat = 1) -> some View {
        Text(text.uppercased())
            .font(.system(size: size.height * 0.07 * scale, weight: .black, design: .rounded))
            .tracking(size.height * 0.008)
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, size.height * 0.03)
            .padding(.vertical, size.height * 0.008)
            .background(colour, in: RoundedRectangle(cornerRadius: size.height * 0.02))
    }

    private var printedLabel: some View {
        let labelSize = CGSize(width: size.width * 0.86, height: size.height * 0.70)
        let shape = RoundedRectangle(cornerRadius: size.width * 0.02)
        return ZStack(alignment: .topLeading) {
            if let labelArt {
                // The art is square; centred and cropped to the wide label, with a fade
                // along the top so the printing stays legible over any cover.
                LabelArtwork(art: labelArt, size: labelSize.width)
                    .frame(width: labelSize.width, height: labelSize.height)
                    .clipped()
                LinearGradient(colors: [.black.opacity(0.6), .black.opacity(0)],
                               startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.32))
            } else {
                shape.fill(SpoolPalette.label)
            }
            HStack(alignment: .firstTextBaseline, spacing: size.width * 0.03) {
                if let stamp = format.stamp {
                    chip(stamp, colour: SpoolPalette.singleShellTop)
                } else if format == .spokenWord {
                    // Spoken-word tapes are one long programme, not side A of an album.
                    chip(String(localized: "spool.tape.spokenWord"), colour: SpoolPalette.spokenWordBand,
                         scale: 0.75)
                } else {
                    Text(String(localized: "spool.sideA"))
                        .font(.system(size: size.height * 0.11, weight: .heavy, design: .rounded))
                }
                Text(title ?? "")
                    .font(.system(size: size.height * 0.075, weight: .medium, design: .serif))
                    .italic()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                // A show's name needs the room more than its episode count does.
                if !format.isShort, format != .spokenWord, let trackCount {
                    Text(format.count(trackCount))
                        .font(.system(size: size.height * 0.055, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize()
                        .opacity(0.85)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(labelArt == nil ? SpoolPalette.labelInk : .white)
            .shadow(color: .black.opacity(labelArt == nil ? 0 : 0.5), radius: 2, x: 0, y: 1)
            .padding(.horizontal, size.width * 0.04)
            .padding(.top, size.height * 0.035)
        }
        .frame(width: labelSize.width, height: labelSize.height)
        .clipShape(shape)
    }

    /// A cassingle carries a few minutes of tape, so its packs stay close to the hub.
    private func pack(_ radius: Double) -> Double {
        guard format.isShort else { return radius }
        return TapeTransport.hubRadius + (radius - TapeTransport.hubRadius) * 0.45
    }

    private func screwPositions(w: CGFloat, h: CGFloat) -> [CGPoint] {
        [CGPoint(x: w * 0.04, y: h * 0.06), CGPoint(x: w * 0.96, y: h * 0.06),
         CGPoint(x: w * 0.04, y: h * 0.94), CGPoint(x: w * 0.96, y: h * 0.94),
         CGPoint(x: w * 0.50, y: h * 0.94)]
    }
}

// MARK: - Label Art

/// What covers a cassette's label: the album a tape was made from, or, for a tape
/// already playing, the current track's cover.
enum TapeLabelArt {
    case album(AppAlbum)
    case track(AppTrack)
}

private struct LabelArtwork: View {
    let art: TapeLabelArt
    let size: CGFloat

    var body: some View {
        // Rounded so a size that wobbles by a fraction of a point reuses the cached image.
        switch art {
        case .album(let album): TapeArtwork(album: album, size: size.rounded())
        case .track(let track): TrackArtwork(track: track, size: size.rounded())
        }
    }
}

// MARK: - Reel

/// One reel: a tape pack around a toothed hub. `packRadius` is relative to the frame
/// (1 fills it), and `angle` turns the hub so the spin is visible.
private struct Reel: View {
    let packRadius: Double
    let angle: Double

    var body: some View {
        GeometryReader { geometry in
            let d = min(geometry.size.width, geometry.size.height)
            let hubDiameter = d * TapeTransport.hubRadius
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [SpoolPalette.tapeInner, SpoolPalette.tapeOuter],
                                         center: .center,
                                         startRadius: hubDiameter / 2,
                                         endRadius: d * packRadius / 2))
                    .frame(width: d * packRadius, height: d * packRadius)

                Hub()
                    .frame(width: hubDiameter, height: hubDiameter)
                    .rotationEffect(.radians(angle))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

private struct Hub: View {
    var body: some View {
        GeometryReader { geometry in
            let d = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle().fill(SpoolPalette.hub)
                Circle().fill(SpoolPalette.window).frame(width: d * 0.62, height: d * 0.62)
                ForEach(0..<6, id: \.self) { tooth in
                    RoundedRectangle(cornerRadius: d * 0.03)
                        .fill(SpoolPalette.hub)
                        .frame(width: d * 0.12, height: d * 0.16)
                        .offset(y: -d * 0.24)
                        .rotationEffect(.degrees(Double(tooth) * 60))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

/// The trapezoid at the bottom of the shell.
private struct BridgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.width * 0.08
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    CassetteView(clock: PlaybackClock(), duration: 200, isPlaying: false, title: "Side One")
        .padding()
        .background(SpoolPalette.body)
}
