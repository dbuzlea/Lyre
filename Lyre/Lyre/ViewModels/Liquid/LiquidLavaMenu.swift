//
//  LiquidLavaMenu.swift
//  Lyre
//

import SwiftUI
import UIKit
import CoreMotion

// MARK: - Lava Menu
//
// The library's first page, as a lava lamp. Each way into the music — albums, artists,
// playlists, podcasts, search — is a blob of wax with its name on it, in the colour of
// what's playing (a warm orange with nothing playing). The blobs drift as wax does in a
// lamp, rising and sinking slowly, and where two come close they run together and pull
// apart again. Tilt the phone and they slide towards the low side.
//
// Pressing a blob swells it until its colour fills the screen, and the page it names is
// there when the colour clears: the Liquid player's flood, starting from the blob.
//
// How it's drawn: the blobs are circles, blurred and then cut at half their opacity
// (`alphaThreshold`), which joins circles that come near each other the way metaballs
// do. That shape masks a gradient of the lava's colour, with a glow behind it.
//
// How it moves (`LavaLamp`): each blob is pulled towards a home spot that itself drifts
// slowly up and down, pushed off the others when they crowd it, kept inside the lamp, and
// pushed by the tilt of the phone, measured from how it was held when the page opened.
// The motion is stepped by the display, and stops while the page is away, under Reduce
// Motion (where the blobs rest at home) and in UI tests.

struct LiquidLavaMenu: View {
    @ObservedObject var musicService: MusicService
    let items: [(id: String, title: String, route: LiquidRoute)]
    /// A blob chosen: where it is on screen, and the lava's colour, to flood from.
    let onChoose: (LiquidRoute, CGPoint, Color) -> Void
    let onOpenSettings: () -> Void
    let bottomInset: CGFloat

    @State private var lamp = LavaLamp()
    @State private var source: Color?
    @Environment(\.windowSafeArea) private var safeArea
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var lava: LavaColors { LavaColors(source: source) }

    var body: some View {
        GeometryReader { geometry in
            let frame = geometry.frame(in: .global)
            ZStack {
                glass
                blobs
                labels(in: frame)
                header
            }
            .onAppear {
                lamp.configure(items: items, size: geometry.size,
                               top: safeArea.top + 76, bottom: geometry.size.height - bottomInset - 8)
                isStill ? lamp.settle() : lamp.start()
            }
            .onDisappear { lamp.stop() }
            // Nothing to see while Lyre's in the background (a podcast can keep it
            // running there), so the lamp and the tilt sensor stop until it's back.
            .onChange(of: scenePhase) { _, phase in
                guard !isStill else { return }
                phase == .active ? lamp.start() : lamp.stop()
            }
            .onChange(of: geometry.size) { _, size in
                lamp.configure(items: items, size: size,
                               top: safeArea.top + 76, bottom: size.height - bottomInset - 8)
            }
        }
        .ignoresSafeArea()
        .task(id: musicService.nowPlayingTrack?.id) {
            guard let track = musicService.nowPlayingTrack else { return }
            let found = await LiquidColors.shared.color(for: track)
            withAnimation(.easeInOut(duration: 1)) { source = found }
        }
    }

    private var isStill: Bool {
        reduceMotion || ProcessInfo.processInfo.arguments.contains("--uitest")
    }

    // MARK: Drawing

    /// The lamp's glass: dark, warmed from below by the lava's light.
    private var glass: some View {
        ZStack {
            Color.liquidGround
            RadialGradient(colors: [lava.deep.opacity(0.55), .clear],
                           center: .bottom, startRadius: 0, endRadius: 520)
            RadialGradient(colors: [lava.main.opacity(0.12), .clear],
                           center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: 360)
        }
        .accessibilityHidden(true)
    }

    /// The wax: the blobs run together where they meet, lit from above and glowing.
    private var blobs: some View {
        let shapes = lamp.blobs
        return LinearGradient(colors: [lava.light, lava.main, lava.deep], startPoint: .top, endPoint: .bottom)
            .mask {
                Canvas { context, _ in
                    context.addFilter(.alphaThreshold(min: 0.5, color: .white))
                    context.addFilter(.blur(radius: 22))
                    context.drawLayer { layer in
                        for blob in shapes {
                            let r = blob.drawnRadius
                            layer.fill(Path(ellipseIn: CGRect(x: blob.position.x - r, y: blob.position.y - r,
                                                              width: r * 2, height: r * 2)),
                                       with: .color(.white))
                            let bead = blob.bead
                            layer.fill(Path(ellipseIn: CGRect(x: bead.centre.x - bead.radius, y: bead.centre.y - bead.radius,
                                                              width: bead.radius * 2, height: bead.radius * 2)),
                                       with: .color(.white))
                        }
                    }
                }
            }
            // A sheen near the top of each blob, where the lamp's light catches the wax.
            .overlay {
                Canvas { context, _ in
                    context.addFilter(.blur(radius: 14))
                    for blob in shapes {
                        let r = blob.drawnRadius * 0.42
                        let centre = CGPoint(x: blob.position.x - blob.drawnRadius * 0.28,
                                             y: blob.position.y - blob.drawnRadius * 0.36)
                        context.fill(Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r * 0.7,
                                                            width: r * 2, height: r * 1.4)),
                                     with: .color(.white.opacity(0.28)))
                    }
                }
                .allowsHitTesting(false)
            }
            .shadow(color: lava.main.opacity(0.55), radius: 28)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Each blob's name, which is also what's pressed.
    private func labels(in frame: CGRect) -> some View {
        ForEach(Array(lamp.blobs.enumerated()), id: \.element.id) { index, blob in
            Button {
                choose(index, in: frame)
            } label: {
                Text(blob.title)
                    .font(.system(size: blob.radius * 0.32, weight: .bold))
                    .tracking(-0.5)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(lava.ink)
                    .padding(blob.radius * 0.2)
                    .frame(width: blob.radius * 1.7, height: blob.radius * 1.7)
                    .contentShape(Circle())
            }
            .buttonStyle(LavaPressStyle())
            .opacity(lamp.chosen == nil || lamp.chosen == index ? 1 : 0)
            .position(labelPosition(for: blob, in: frame.size))
            .accessibilityLabel(blob.title)
            .accessibilityIdentifier("liquid.menu.\(blob.id)")
        }
    }

    /// Where a blob's name sits: on the blob, but never past the edge of the screen. A
    /// blob leaning out past an edge keeps its name in view, nudged in along it.
    private func labelPosition(for blob: LavaLamp.Blob, in size: CGSize) -> CGPoint {
        let half = blob.radius * 0.85
        let margin: CGFloat = 6
        return CGPoint(x: min(max(blob.position.x, half + margin), size.width - half - margin),
                       y: min(max(blob.position.y, half * 0.5 + safeArea.top + 60),
                              size.height - bottomInset - half * 0.5))
    }

    private var header: some View {
        VStack {
            HStack {
                Text("LYRE")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .tracking(4)
                    .foregroundStyle(.white.opacity(0.55))
                    .accessibilityHidden(true)
                Spacer()
                Button(action: onOpenSettings) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.1), in: Circle())
                }
                .foregroundStyle(.white)
                .accessibilityLabel(String(localized: "settings.title"))
                .accessibilityIdentifier("liquid.settings")
            }
            .padding(.horizontal, 24)
            .padding(.top, safeArea.top + 12)
            Spacer()
        }
    }

    // MARK: Choosing

    /// The blob swells, and its colour floods the screen from its middle.
    private func choose(_ index: Int, in frame: CGRect) {
        guard lamp.chosen == nil, lamp.blobs.indices.contains(index) else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        let blob = lamp.blobs[index]
        lamp.swell(index)
        onChoose(blob.route, CGPoint(x: frame.minX + blob.position.x, y: frame.minY + blob.position.y), lava.main)
    }
}

/// A blob's name gives a little under the finger.
private struct LavaPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// The lava's colours, from the colour of what's playing: bright and warm enough to read
/// as wax under a lamp, whatever the cover.
struct LavaColors {
    let main: Color
    let light: Color
    let deep: Color
    let ink: Color

    init(source: Color?) {
        var h: CGFloat = 0.05, s: CGFloat = 0.8, b: CGFloat = 0.95, a: CGFloat = 1
        if let source { UIColor(source).getHue(&h, saturation: &s, brightness: &b, alpha: &a) }
        // A greyish cover has no hue worth lighting: the classic orange instead.
        if s < 0.15 { h = 0.05; s = 0.8 }
        main = Color(hue: Double(h), saturation: Double(max(s, 0.65)), brightness: 0.95)
        light = Color(hue: Double(h), saturation: Double(max(s, 0.65) * 0.55), brightness: 1)
        deep = Color(hue: Double(h), saturation: Double(min(1, max(s, 0.65) + 0.15)), brightness: 0.55)
        ink = Color(white: 0.08).opacity(0.88)
    }
}

// MARK: - Lamp

/// The blobs and how they move. Stepped by the display while the menu shows.
@Observable @MainActor
final class LavaLamp {
    struct Blob: Identifiable {
        let id: String
        let title: String
        let route: LiquidRoute
        /// Where it rests, as a share of the lamp's width and height.
        let home: CGPoint
        let radius: CGFloat
        /// Its own rhythm of rising and sinking.
        let phase: Double
        var position: CGPoint
        var velocity: CGVector = .zero
        /// How much it has swelled, once chosen.
        var swell: CGFloat = 1
        /// Where the bead of wax clinging to its edge has got to, going round.
        var wobble: Double = 0

        var drawnRadius: CGFloat { radius * swell }

        /// The bead of wax that creeps round the blob's edge, running into it, so the
        /// blob is never quite round.
        var bead: (centre: CGPoint, radius: CGFloat) {
            let angle = wobble + phase * 2.1
            let reach = drawnRadius * 0.86
            return (CGPoint(x: position.x + CGFloat(cos(angle)) * reach,
                            y: position.y + CGFloat(sin(angle)) * reach * 0.9),
                    drawnRadius * 0.4)
        }
    }

    private(set) var blobs: [Blob] = []
    private(set) var chosen: Int?

    @ObservationIgnored private var size: CGSize = .zero
    @ObservationIgnored private var top: CGFloat = 0
    @ObservationIgnored private var bottom: CGFloat = 0
    @ObservationIgnored private var time: Double = 0
    @ObservationIgnored private var driver: LavaDriver?
    @ObservationIgnored private let motion = CMMotionManager()
    /// How the phone was held, which tilting is measured from; it follows a held tilt
    /// slowly, so the blobs come back once the phone's been held a new way a while.
    @ObservationIgnored private var level: CGVector?
    @ObservationIgnored private var tilt: CGVector = .zero

    /// Where each blob rests, zigzagging down the lamp, and how big it is (a share of
    /// the lamp's width).
    private static let homes: [CGPoint] = [
        CGPoint(x: 0.3, y: 0.04), CGPoint(x: 0.72, y: 0.17), CGPoint(x: 0.28, y: 0.31),
        CGPoint(x: 0.72, y: 0.44), CGPoint(x: 0.28, y: 0.57), CGPoint(x: 0.72, y: 0.7),
        CGPoint(x: 0.3, y: 0.83), CGPoint(x: 0.72, y: 0.96)
    ]
    private static let radii: [CGFloat] = [0.165, 0.145, 0.15, 0.15, 0.15, 0.15, 0.14, 0.13]

    func configure(items: [(id: String, title: String, route: LiquidRoute)], size: CGSize, top: CGFloat, bottom: CGFloat) {
        guard size.width > 0, size.height > 0 else { return }
        let resized = size != self.size
        self.size = size
        self.top = top
        self.bottom = max(top + 200, bottom)
        // Made again for a new size, since the blobs are sized from the lamp's width.
        if blobs.count != items.count || resized {
            blobs = items.enumerated().map { index, item in
                let home = Self.homes[index % Self.homes.count]
                let radius = size.width * Self.radii[index % Self.radii.count]
                return Blob(id: item.id, title: item.title, route: item.route, home: home, radius: radius,
                            phase: Double(index) * 1.3, position: point(for: home))
            }
        }
        chosen = nil
        for index in blobs.indices { blobs[index].swell = 1 }
    }

    /// Where a share of the lamp is on screen.
    private func point(for unit: CGPoint) -> CGPoint {
        CGPoint(x: size.width * unit.x, y: top + (bottom - top) * unit.y)
    }

    /// Still: every blob at home.
    func settle() {
        for index in blobs.indices {
            blobs[index].position = point(for: blobs[index].home)
            blobs[index].velocity = .zero
        }
    }

    func start() {
        guard driver == nil else { return }
        level = nil
        if motion.isDeviceMotionAvailable {
            // The tilt is smoothed heavily before it moves anything; 30 readings a
            // second is plenty, at half the sensor's power.
            motion.deviceMotionUpdateInterval = 1 / 30
            motion.startDeviceMotionUpdates()
        }
        driver = LavaDriver { [weak self] dt in self?.step(dt) }
    }

    func stop() {
        driver?.invalidate()
        driver = nil
        motion.stopDeviceMotionUpdates()
    }

    /// The chosen blob swells while its colour floods out.
    func swell(_ index: Int) {
        chosen = index
    }

    private func step(_ dt: Double) {
        let dt = min(dt, 1 / 30)
        time += dt
        readTilt()

        let height = bottom - top
        var next = blobs
        for i in next.indices {
            var blob = next[i]
            // The home spot drifts: up as the wax warms, down as it cools.
            let home = point(for: blob.home)
            let target = CGPoint(x: home.x + CGFloat(sin(time * 0.21 + blob.phase * 1.7)) * size.width * 0.06,
                                 y: home.y + CGFloat(sin(time * 0.33 + blob.phase)) * height * 0.07)
            var ax = (target.x - blob.position.x) * 1.4
            var ay = (target.y - blob.position.y) * 1.4
            // The tilt of the phone.
            ax += tilt.dx * 950
            ay += tilt.dy * 950
            // Crowding: blobs shoulder each other aside, but may touch and run together.
            for j in next.indices where j != i {
                let dx = blob.position.x - next[j].position.x
                let dy = blob.position.y - next[j].position.y
                let distance = max(1, (dx * dx + dy * dy).squareRoot())
                let room = (blob.radius + next[j].radius) * 0.9
                if distance < room {
                    let push = (room - distance) * 26
                    ax += dx / distance * push
                    ay += dy / distance * push
                }
            }
            blob.velocity.dx = (blob.velocity.dx + ax * dt) * pow(0.25, dt)
            blob.velocity.dy = (blob.velocity.dy + ay * dt) * pow(0.25, dt)
            blob.position.x += blob.velocity.dx * dt
            blob.position.y += blob.velocity.dy * dt
            // The lamp's walls; a blob may lean out past them a little (its name stays in).
            let lean = blob.radius * 0.75
            blob.position.x = min(max(blob.position.x, lean), size.width - lean)
            blob.position.y = min(max(blob.position.y, top + lean * 0.4), bottom - lean * 0.4)
            blob.wobble += dt * (0.35 + blob.phase * 0.05)
            // The chosen blob swells as its colour floods out.
            if chosen == i { blob.swell = min(1.6, blob.swell + CGFloat(dt) * 3) }
            next[i] = blob
        }
        blobs = next
        // Drifting, the lava looks the same at 30 frames a second as at 60, for half
        // the work; it goes up to 60 while anything moves briskly.
        let fastest = next.lazy.map { ($0.velocity.dx * $0.velocity.dx + $0.velocity.dy * $0.velocity.dy).squareRoot() }.max() ?? 0
        driver?.isBrisk = fastest > 45 || chosen != nil
    }

    private func readTilt() {
        guard let gravity = motion.deviceMotion?.gravity else { return }
        let now = CGVector(dx: gravity.x, dy: -gravity.y)
        guard let current = level else {
            level = now
            return
        }
        // The level creeps after a held tilt, so it's the change that moves the blobs.
        let creep = 0.004
        let settled = CGVector(dx: current.dx + (now.dx - current.dx) * creep,
                               dy: current.dy + (now.dy - current.dy) * creep)
        level = settled
        let raw = CGVector(dx: now.dx - settled.dx, dy: now.dy - settled.dy)
        tilt = CGVector(dx: tilt.dx + (raw.dx - tilt.dx) * 0.2, dy: tilt.dy + (raw.dy - tilt.dy) * 0.2)
    }
}

/// Calls back once per screen refresh with the time since the last.
private final class LavaDriver: NSObject {
    private var link: CADisplayLink?
    private var last: CFTimeInterval?
    private let tick: @MainActor (Double) -> Void

    init(tick: @escaping @MainActor (Double) -> Void) {
        self.tick = tick
        super.init()
        let link = CADisplayLink(target: self, selector: #selector(fire(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        applyRate()
        lowPower = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyRate() }
        }
    }

    /// Whether the lava's moving fast enough to want 60 frames a second.
    var isBrisk = false {
        didSet { if isBrisk != oldValue { applyRate() } }
    }
    private var lowPower: NSObjectProtocol?

    /// 30 frames a second drifting, 60 while brisk; never more than 30 in Low Power Mode.
    private func applyRate() {
        let fast = isBrisk && !ProcessInfo.processInfo.isLowPowerModeEnabled
        link?.preferredFrameRateRange = fast ? CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
                                             : CAFrameRateRange(minimum: 24, maximum: 30, preferred: 30)
    }

    @objc private func fire(_ link: CADisplayLink) {
        let dt = last.map { link.timestamp - $0 } ?? 1 / 60
        last = link.timestamp
        MainActor.assumeIsolated { tick(dt) }
    }

    func invalidate() {
        link?.invalidate()
        link = nil
        if let lowPower { NotificationCenter.default.removeObserver(lowPower) }
        lowPower = nil
    }
}
