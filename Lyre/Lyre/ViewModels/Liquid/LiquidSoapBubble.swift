//
//  LiquidSoapBubble.swift
//  Lyre
//

import SwiftUI

// MARK: - Liquid Soap Bubble
//
// Liquid's artists, and the songs on an artist's page, are shown in soap bubbles rather
// than square frames: the picture fills most of a ball of clear film that isn't quite
// round, with what makes a bubble look like one drawn over it. Its rim is bright where
// the light catches it and faint where it doesn't; a band of colour (thin-film
// interference, the oil-on-water rainbow) runs round the top; a blue reflection curves
// along the bottom; a highlight sits up on the left; it glows a little on the page and
// throws a soft shadow.
//
// A big one (an artist's page) wobbles slowly, as a bubble does drifting; small ones
// in a list keep still, so a list scrolls as smoothly as ever, and drop the blurred
// layers, which cost too much row after row. With Reduce Motion on, none wobble.

struct LiquidSoapBubble<Content: View>: View {
    let diameter: CGFloat
    /// The slow drift of a bubble's outline; for a big one shown alone.
    var wobbles = false
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Double = 0

    /// Under this, a bubble is in a list or a row: no blur, no glow, no wobble.
    private var isSmall: Bool { diameter < 120 }
    private var shape: SoapBubbleShape { SoapBubbleShape(phase: phase, wobble: isSmall ? 0.025 : 0.04) }

    var body: some View {
        let rim = max(0.75, diameter / 120)
        ZStack {
            // The picture, filling the bubble, seen through the film: darker towards the
            // rim, where the film curves away.
            content()
                .frame(width: diameter, height: diameter)
                .clipShape(shape.scale(0.985))
                .overlay {
                    shape.fill(RadialGradient(colors: [.clear, .black.opacity(0.32)], center: .center,
                                              startRadius: diameter * 0.3, endRadius: diameter * 0.5))
                }
            // The film over it: clear in the middle, catching more light towards the edge,
            // as glass does seen at a slant.
            shape.fill(RadialGradient(stops: [.init(color: .clear, location: 0),
                                              .init(color: .clear, location: 0.62),
                                              .init(color: .white.opacity(0.16), location: 0.92),
                                              .init(color: .white.opacity(0.3), location: 1)],
                                      center: .center, startRadius: 0, endRadius: diameter * 0.5))
                .blendMode(.screen)
            // The rim: bright down the lower left and across the top, where the light
            // catches the curve, faint on the right.
            shape.stroke(LinearGradient(stops: [.init(color: .white.opacity(0.75), location: 0),
                                                .init(color: .white.opacity(0.12), location: 0.45),
                                                .init(color: .white.opacity(0.08), location: 0.6),
                                                .init(color: .white.opacity(0.55), location: 1)],
                                        startPoint: .topTrailing, endPoint: .bottomLeading),
                         lineWidth: rim)
            // Thin-film colour round the top.
            iridescence(rim: rim)
            // A reflection curving along the bottom, just inside the rim, cool blue.
            shape.trim(from: 0.14, to: 0.34)
                .stroke(LinearGradient(colors: [.clear, Color(red: 0.45, green: 0.75, blue: 1).opacity(0.75), .clear],
                                       startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: rim * 1.6, lineCap: .round))
                .scaleEffect(0.93)
            // A small second highlight, low on the right, where the light comes through.
            Ellipse()
                .fill(RadialGradient(colors: [.white.opacity(0.35), .white.opacity(0)], center: .center,
                                     startRadius: 0, endRadius: diameter * 0.05))
                .frame(width: diameter * 0.1, height: diameter * 0.06)
                .rotationEffect(.degrees(-35))
                .offset(x: diameter * 0.27, y: diameter * 0.25)
                .blendMode(.screen)
            // The highlight up on the left.
            Ellipse()
                .fill(RadialGradient(colors: [.white.opacity(0.55), .white.opacity(0)], center: .center,
                                     startRadius: 0, endRadius: diameter * 0.12))
                .frame(width: diameter * 0.26, height: diameter * 0.15)
                .rotationEffect(.degrees(-30))
                .offset(x: -diameter * 0.22, y: -diameter * 0.26)
                .blendMode(.screen)
        }
        .frame(width: diameter, height: diameter)
        .compositingGroup()
        // A faint glow on the page round it, and its shadow.
        .background {
            if !isSmall {
                Circle()
                    .fill(.white.opacity(0.07))
                    .blur(radius: diameter * 0.12)
                    .scaleEffect(1.1)
            }
        }
        .shadow(color: .black.opacity(0.45), radius: diameter / 14, y: diameter / 28)
        .onAppear {
            guard wobbles, !isSmall, !reduceMotion else { return }
            withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) { phase = 2 * .pi }
        }
    }

    /// A band of rainbow colour on the film round the top, fading out down the sides.
    @ViewBuilder private func iridescence(rim: CGFloat) -> some View {
        let band = shape
            .stroke(AngularGradient(colors: [.pink, .orange, .yellow, .green, .cyan, .blue, .purple, .pink],
                                    center: .center, angle: .degrees(200)),
                    lineWidth: rim * (isSmall ? 1.6 : 2.2))
            .mask(LinearGradient(stops: [.init(color: .white, location: 0),
                                         .init(color: .white.opacity(0.5), location: 0.18),
                                         .init(color: .clear, location: 0.38)],
                                 startPoint: .top, endPoint: .bottom))
            .opacity(0.55)
            .blendMode(.screen)
        if isSmall {
            band
        } else {
            band.blur(radius: rim * 0.8)
        }
    }
}

/// A bubble's outline: round, give or take a few per cent, the give moving round as
/// `phase` turns (a smooth closed curve through points at a radius that varies).
struct SoapBubbleShape: Shape {
    var phase: Double
    /// How far from round, as a fraction of the radius.
    var wobble: Double

    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 / (1 + wobble * 1.6)
        let count = 36
        let points: [CGPoint] = (0..<count).map { index in
            let angle = Double(index) / Double(count) * 2 * .pi
            let give = wobble * (sin(2 * angle + phase) + 0.6 * sin(3 * angle - phase * 0.7 + 1.3))
            let r = radius * (1 + give)
            return CGPoint(x: centre.x + r * cos(angle), y: centre.y + r * sin(angle))
        }
        // Catmull-Rom through the points, as cubic curves: a smooth, closed outline.
        var path = Path()
        path.move(to: points[0])
        for index in 0..<count {
            let p0 = points[(index - 1 + count) % count], p1 = points[index]
            let p2 = points[(index + 1) % count], p3 = points[(index + 2) % count]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        path.closeSubpath()
        return path
    }
}
