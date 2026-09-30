//
//  OnboardingPracticeWheel.swift
//  Lyre
//

import SwiftUI
import AudioToolbox

// MARK: - Practice Wheel
//
// A working scroll wheel for onboarding, so a first-time user learns the wheel by using
// it rather than reading about it. It looks and feels like ScrollWheelView — same
// theme colors, same tap zones, same scroll threshold for the chosen sensitivity, the
// same haptic step and click — but drives nothing except its callbacks, so it can sit
// on a page with no library, player or navigation behind it.
//
// It keeps the real wheel's speed-based acceleration, because that is most of what the
// sensitivity setting changes — trying Low, Medium and High here should feel exactly
// like the app. It leaves out the center swipe, which the Shortcuts step describes.
//
// VoiceOver cannot spin a wheel, so the ring is an adjustable element (swipe up or down
// to scroll) with the four ring buttons as named actions, and the center is a button.

enum PracticeWheelButton: String {
    case menu, playPause, previous, next

    /// Same convention as ScrollWheelView: 0° = right, 90° = bottom.
    init(angle: Double) {
        switch angle {
        case 225..<315: self = .menu
        case 45..<135:  self = .playPause
        case 135..<225: self = .previous
        default:        self = .next
        }
    }
}

struct OnboardingPracticeWheel: View {
    let theme: LyreTheme
    var sensitivity: ScrollSensitivity = .medium
    var clickSound = true
    var size: CGFloat = 240
    /// Highlights a zone to draw the eye to it — the one the current lesson is about.
    var emphasized: PracticeWheelButton? = nil
    var emphasizeCenter = false
    /// +1 for one step clockwise (down the list), -1 anticlockwise.
    var onScroll: (Int) -> Void = { _ in }
    var onSelect: () -> Void = {}
    var onButton: (PracticeWheelButton) -> Void = { _ in }

    @State private var lastAngle: Double?
    @State private var startAngle: Double = 0
    @State private var travelled: Double = 0
    @State private var accumulated: Double = 0
    @State private var committed = false
    @State private var lastTime = Date()
    @State private var velocity: Double = 0
    @State private var pressed: PracticeWheelButton?
    @State private var centerPressed = false
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let step = UIImpactFeedbackGenerator(style: .medium)
    private let tap = UIImpactFeedbackGenerator(style: .rigid)

    private var centerSize: CGFloat { size * 0.43 }
    private var labelOffset: CGFloat { size * 0.357 }
    private var ringWidth: CGFloat { (size - centerSize) / 2 }

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: theme.wheelOuterGradientColors, center: .center,
                                     startRadius: size * 0.25, endRadius: size * 0.5))
                .overlay { Circle().stroke(theme.wheelStrokeColor, lineWidth: 2) }

            ringGestureLayer

            ForEach([PracticeWheelButton.menu, .playPause, .previous, .next], id: \.self) { button in
                label(for: button)
                    .offset(offset(for: button))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            centerButton
        }
        .frame(width: size, height: size)
        // Pulses only while something is highlighted: an animation that never stops
        // keeps the app from going idle, which UI tests wait for.
        .task(id: emphasized != nil || emphasizeCenter) {
            withAnimation(.easeOut(duration: 0.2)) { pulse = false }
            guard emphasized != nil || emphasizeCenter, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    // MARK: Ring

    private var ringGestureLayer: some View {
        Circle()
            .stroke(Color.clear, lineWidth: ringWidth)
            .frame(width: size - ringWidth, height: size - ringWidth)
            .contentShape(Circle().stroke(lineWidth: ringWidth))
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let inset = (size - (size - ringWidth)) / 2
                        let local = CGPoint(x: value.location.x + inset, y: value.location.y + inset)
                        rotate(to: local)
                    }
                    .onEnded { _ in endRotation() }
            )
            .accessibilityElement()
            .accessibilityLabel(String(localized: "wheel.a11y.label"))
            .accessibilityHint(String(localized: "wheel.a11y.hint"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: scrolled(+1)
                case .decrement: scrolled(-1)
                @unknown default: break
                }
            }
            .accessibilityAction(named: Text(String(localized: "wheel.menu"))) { fire(.menu) }
            .accessibilityAction(named: Text(String(localized: "wheel.playPause"))) { fire(.playPause) }
            .accessibilityAction(named: Text(String(localized: "wheel.previous"))) { fire(.previous) }
            .accessibilityAction(named: Text(String(localized: "wheel.next"))) { fire(.next) }
    }

    private func rotate(to point: CGPoint) {
        var angle = atan2(point.y - size / 2, point.x - size / 2) * 180 / .pi
        if angle < 0 { angle += 360 }

        guard let last = lastAngle else {
            lastAngle = angle
            startAngle = angle
            lastTime = Date()
            velocity = 0
            travelled = 0
            accumulated = 0
            committed = false
            pressed = PracticeWheelButton(angle: angle)
            step.prepare()
            return
        }

        var delta = angle - last
        if delta > 180 { delta -= 360 } else if delta < -180 { delta += 360 }
        lastAngle = angle
        travelled += abs(delta)

        let now = Date()
        let elapsed = now.timeIntervalSince(lastTime)
        lastTime = now
        velocity = elapsed > 0 && elapsed < 0.15 ? velocity * 0.6 + abs(delta) / elapsed * 0.4 : 0

        // A few degrees of travel make it a spin rather than a press, as on the real wheel.
        if !committed {
            guard travelled >= 5 else { return }
            committed = true
            pressed = nil
            accumulated = 0
        }

        accumulated += delta
        if abs(accumulated) >= sensitivity.scrollThreshold {
            // Same steps-per-notch table as ScrollWheelView.scrollSteps(for:).
            let t = sensitivity.velocityStepThresholds
            let steps = velocity < t.t1 ? 1 : velocity < t.t2 ? 2 : velocity < t.t3 ? 3 : 5
            for _ in 0..<steps { scrolled(accumulated > 0 ? 1 : -1) }
            accumulated = 0
        }
    }

    private func endRotation() {
        if lastAngle != nil, !committed {
            fire(PracticeWheelButton(angle: startAngle))
        }
        lastAngle = nil
        committed = false
        pressed = nil
    }

    private func scrolled(_ direction: Int) {
        if clickSound { AudioServicesPlaySystemSound(1104) }
        step.impactOccurred()
        onScroll(direction)
    }

    private func fire(_ button: PracticeWheelButton) {
        tap.impactOccurred(intensity: 0.7)
        onButton(button)
    }

    // MARK: Labels

    @ViewBuilder
    private func label(for button: PracticeWheelButton) -> some View {
        let isEmphasized = emphasized == button
        VStack(spacing: 2) {
            switch button {
            case .menu:
                Image(systemName: "line.horizontal.3").font(.system(size: size * 0.058, weight: .semibold))
                Text("MENU").font(.system(size: size * 0.033, weight: .semibold)).tracking(0.5)
            case .playPause:
                Image(systemName: "playpause.fill").font(.system(size: size * 0.058, weight: .semibold))
            case .previous:
                Image(systemName: "backward.fill").font(.system(size: size * 0.054, weight: .semibold))
            case .next:
                Image(systemName: "forward.fill").font(.system(size: size * 0.054, weight: .semibold))
            }
        }
        .foregroundStyle(theme.wheelButtonTextColor.opacity(pressed == button ? 1 : 0.9))
        .padding(8)
        .background {
            if isEmphasized {
                Circle()
                    .stroke(Color.accentColor, lineWidth: 3)
                    .frame(width: size * 0.2, height: size * 0.2)
                    .scaleEffect(pulse ? 1.12 : 0.95)
            }
        }
    }

    private func offset(for button: PracticeWheelButton) -> CGSize {
        switch button {
        case .menu:      return CGSize(width: 0, height: -labelOffset)
        case .playPause: return CGSize(width: 0, height: labelOffset)
        case .previous:  return CGSize(width: -labelOffset, height: 0)
        case .next:      return CGSize(width: labelOffset, height: 0)
        }
    }

    // MARK: Center

    private var centerButton: some View {
        Circle()
            .fill(RadialGradient(colors: theme.wheelCenterGradientColors.map { centerPressed ? $0.opacity(0.8) : $0 },
                                 center: .center, startRadius: 0, endRadius: centerSize / 2))
            .overlay { Circle().stroke(theme.wheelCenterStrokeColor, lineWidth: 1) }
            .overlay {
                if emphasizeCenter {
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 3)
                        .scaleEffect(pulse ? 1.08 : 0.96)
                }
            }
            .frame(width: centerSize, height: centerSize)
            .shadow(color: .black.opacity(centerPressed ? 0.1 : 0.3), radius: 4, y: 2)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in centerPressed = true }
                    .onEnded { value in
                        centerPressed = false
                        guard abs(value.translation.width) < 26, abs(value.translation.height) < 26 else { return }
                        tap.impactOccurred()
                        onSelect()
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(String(localized: "wheel.select"))
            .accessibilityHint(String(localized: "wheel.select.hint"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { tap.impactOccurred(); onSelect() }
    }
}

// MARK: - Practice Screen

/// A small stand-in for Lyre's screen, drawn in the theme's LCD colors: a titled list
/// with one highlighted row. Used by the practice and wheel-feel steps and by the
/// device preview.
struct OnboardingMiniScreen: View {
    let theme: LyreTheme
    let title: String
    let rows: [String]
    let selection: Int
    var showsBack = false
    var fontScale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * fontScale) {
            HStack(spacing: 4) {
                if showsBack {
                    Image(systemName: "chevron.left").font(.system(size: 10 * fontScale, weight: .semibold))
                }
                Text(title).font(.system(size: 13 * fontScale, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(theme.screenTextColor)
            Rectangle().fill(theme.dividerColor.opacity(0.6)).frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 2 * fontScale) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            HStack {
                                Text(row).font(.system(size: 13 * fontScale, weight: index == selection ? .semibold : .regular))
                                Spacer()
                                if index == selection {
                                    Image(systemName: "chevron.right").font(.system(size: 10 * fontScale, weight: .bold))
                                }
                            }
                            .foregroundStyle(index == selection ? theme.highlightTextColor : theme.screenTextColor)
                            .padding(.horizontal, 6 * fontScale)
                            .padding(.vertical, 4 * fontScale)
                            .background(index == selection ? theme.highlightColor : .clear)
                            .id(index)
                        }
                    }
                }
                .scrollDisabled(true)
                .onChange(of: selection) { _, new in proxy.scrollTo(new, anchor: .center) }
            }
        }
        .padding(8 * fontScale)
        .background(LinearGradient(colors: theme.screenBackgroundLight, startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: 8 * fontScale))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(rows.indices.contains(selection) ? "\(rows[selection]) selected" : "")
    }
}
