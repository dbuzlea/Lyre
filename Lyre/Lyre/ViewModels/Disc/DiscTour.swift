//
//  DiscTour.swift
//  Lyre
//

import SwiftUI

// MARK: - Disc Tour
//
// The Disc's tutorial, acted out on a miniature of the player: the lid, the shelf of
// cases, the keys, the modes, Up Next, and the case of what's playing. The settings sheet
// shows it as its first section, in the shared TourPager.

enum DiscLesson: CaseIterable, TourLesson {
    case openLid
    case chooseDisc
    case keys
    case modes
    case upNext
    case holdLid
    case shelves

    // Each key is written out so the strings are found and localized.
    var title: String {
        switch self {
        case .openLid:    return String(localized: "disc.tour.openLid.title")
        case .chooseDisc: return String(localized: "disc.tour.chooseDisc.title")
        case .keys:       return String(localized: "disc.tour.keys.title")
        case .modes:      return String(localized: "disc.tour.modes.title")
        case .upNext:     return String(localized: "disc.tour.upNext.title")
        case .holdLid:    return String(localized: "disc.tour.holdLid.title")
        case .shelves:    return String(localized: "disc.tour.shelves.title")
        }
    }

    var detail: String {
        switch self {
        case .openLid:    return String(localized: "disc.tour.openLid.detail")
        case .chooseDisc: return String(localized: "disc.tour.chooseDisc.detail")
        case .keys:       return String(localized: "disc.tour.keys.detail")
        case .modes:      return String(localized: "disc.tour.modes.detail")
        case .upNext:     return String(localized: "disc.tour.upNext.detail")
        case .holdLid:    return String(localized: "disc.tour.holdLid.detail")
        case .shelves:    return String(localized: "disc.tour.shelves.detail")
        }
    }
}

struct DiscTourPager: View {
    let theme: DiscTheme
    var ink: Color = SpoolPalette.labelInk

    var body: some View {
        TourPager(lessons: DiscLesson.allCases, ink: ink, idPrefix: "disc.tour") { lesson, replay in
            DiscTourScene(lesson: lesson, replay: replay, theme: theme)
        }
    }
}

/// The miniature: the round deck on the left, the display and keys on the right, a
/// fingertip working them, and the shelf, the case and the tray when a lesson calls for
/// them.
struct DiscTourScene: View {
    let lesson: DiscLesson
    let replay: Int
    let theme: DiscTheme

    @State private var finger: CGPoint?
    @State private var isPressed = false
    @State private var isLidOpen = false
    @State private var showsShelf = false
    @State private var isSpinning = true
    @State private var flyingDisc: CGPoint?
    @State private var isCaseOpen = false
    @State private var trayUp = false
    @State private var lcdTrack = 1
    @State private var lcdTime = "1:24"
    @State private var lit: Set<String> = []
    @State private var shelfLabel = 0

    private static let size = CGSize(width: 280, height: 210)
    private static let deck = CGPoint(x: 78, y: 100)
    private static let deckSide: CGFloat = 128

    private static func key(_ index: Int) -> CGPoint { CGPoint(x: 160 + CGFloat(index) * 38, y: 98) }
    private static func mode(_ index: Int) -> CGPoint { CGPoint(x: 160 + CGFloat(index) * 38, y: 132) }
    private static let grip = CGPoint(x: 198, y: 176)
    private static let frontCase = CGPoint(x: 210, y: 158)

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22)
                .fill(theme.bodyGradient)

            deck
                .position(Self.deck)

            if showsShelf {
                shelf.transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                controls.transition(.opacity)
            }

            if let flyingDisc {
                miniDisc(Self.deckSide * 0.5)
                    .position(flyingDisc)
            }

            if isCaseOpen { openCase.transition(.scale(scale: 0.6).combined(with: .opacity)) }
            if trayUp { tray.transition(.move(edge: .bottom)) }

            TourFingertip(point: finger, isPressed: isPressed)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .frame(maxWidth: .infinity)
        .task(id: "\(lesson)-\(replay)") { await act() }
    }

    // MARK: Drawing

    private var deck: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [theme.bodyDark, theme.bodyLight], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(Color(white: 0.08)).padding(5)
            if !isLidOpen || !showsShelf {
                DiscSpinner(isSpinning: isSpinning, frameRate: 30) { miniDisc(Self.deckSide * 0.84) }
            }
            Circle()
                .fill(theme.lid.opacity(theme.isClear ? 0.42 : 0.6))
                .overlay(Circle().strokeBorder(theme.body, lineWidth: 5))
                .rotation3DEffect(.degrees(isLidOpen ? -70 : 0), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.55)
        }
        .frame(width: Self.deckSide, height: Self.deckSide)
    }

    private func miniDisc(_ diameter: CGFloat) -> some View {
        ZStack {
            Circle().fill(AngularGradient(colors: [Color(red: 0.95, green: 0.55, blue: 0.3), Color(red: 0.4, green: 0.3, blue: 0.7),
                                                   Color(red: 0.2, green: 0.6, blue: 0.7), Color(red: 0.95, green: 0.55, blue: 0.3)],
                                          center: .center))
            Circle().fill(Color(white: 0.85)).frame(width: diameter * 0.32, height: diameter * 0.32)
            Circle().fill(Color(white: 0.1)).frame(width: diameter * 0.12, height: diameter * 0.12)
        }
        .frame(width: diameter, height: diameter)
        .overlay(DiscSheen(diameter: diameter))
    }

    private var controls: some View {
        ZStack(alignment: .topLeading) {
            // The display.
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(String(format: "%02d", lcdTrack))
                    Spacer()
                    Text(lcdTime)
                }
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                HStack(spacing: 5) {
                    Text("RND").opacity(lit.contains("rnd") ? 1 : 0.12)
                    Text("REP").opacity(lit.contains("rep") ? 1 : 0.12)
                }
                .font(.system(size: 7, weight: .heavy, design: .monospaced))
            }
            .foregroundStyle(theme.lcdInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(width: 112)
            .background(theme.lcd, in: RoundedRectangle(cornerRadius: 4))
            .position(x: 198, y: 46)

            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index == 1 ? theme.accent : theme.buttonLight)
                    .overlay(Image(systemName: ["backward.end.alt.fill", "playpause.fill", "forward.end.alt.fill"][index])
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(index == 1 ? .white : theme.buttonSymbol))
                    .frame(width: 32, height: 22)
                    .position(Self.key(index))
            }
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(theme.buttonLight)
                    .overlay(Text(["MODE", "RND", "OPEN"][index])
                        .font(.system(size: 6, weight: .heavy))
                        .foregroundStyle(theme.buttonSymbol))
                    .frame(width: 32, height: 14)
                    .position(Self.mode(index))
            }
            Capsule()
                .fill(theme.ink.opacity(0.4))
                .frame(width: 26, height: 4)
                .position(Self.grip)
        }
    }

    private var shelf: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    Text([String(localized: "spool.shelf.albums"), String(localized: "disc.shelf.burned"),
                          String(localized: "spool.shelf.podcasts")][index].uppercased())
                        .font(.system(size: 6, weight: .heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(theme.buttonSymbol.opacity(shelfLabel == index ? 1 : 0.5))
                        .frame(width: 34, height: 12)
                        .background(theme.buttonLight.opacity(shelfLabel == index ? 0.95 : 0.4),
                                    in: UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3))
                }
            }
            .position(x: 210, y: 30)
            ForEach(0..<4, id: \.self) { index in
                let depth = CGFloat(3 - index)
                RoundedRectangle(cornerRadius: 2)
                    .fill(shelfLabel == 1
                          ? Color(red: 0.98, green: 0.97, blue: 0.93)
                          : [Color(red: 0.8, green: 0.35, blue: 0.3), Color(red: 0.3, green: 0.45, blue: 0.7),
                             Color(red: 0.85, green: 0.7, blue: 0.3), Color(red: 0.25, green: 0.55, blue: 0.45)][index])
                    .overlay(alignment: .leading) { Rectangle().fill(.black).frame(width: 4) }
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(.white.opacity(0.5), lineWidth: 0.5))
                    .frame(width: 80 - depth * 6, height: 70 - depth * 5)
                    .brightness(-Double(depth) * 0.1)
                    .position(x: Self.frontCase.x, y: Self.frontCase.y - depth * 24)
                    .opacity(index == 3 && flyingDisc != nil ? 0.6 : 1)
            }
        }
    }

    private var openCase: some View {
        ZStack {
            Color.black.opacity(0.5)
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.8, green: 0.35, blue: 0.3))
                    .frame(width: 76, height: 76)
                ZStack {
                    RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.1))
                    miniDisc(66)
                }
                .frame(width: 76, height: 76)
            }
            .offset(y: -36)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule().fill(SpoolPalette.labelInk.opacity(0.25)).frame(width: index == 1 ? 90 : 120, height: 5)
                }
            }
            .padding(10)
            .frame(width: 152, alignment: .leading)
            .background(Color(white: 0.97), in: RoundedRectangle(cornerRadius: 3))
            .offset(y: 46)
        }
    }

    private var tray: some View {
        VStack(spacing: 6) {
            Capsule().fill(SpoolPalette.labelInk.opacity(0.3)).frame(width: 26, height: 4)
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(theme.accent.opacity(0.6)).frame(width: 16, height: 16)
                    Capsule().fill(SpoolPalette.labelInk.opacity(0.25)).frame(height: 5)
                }
            }
        }
        .padding(12)
        .frame(width: Self.size.width, height: 130, alignment: .top)
        .background(theme.buttonLight, in: UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14))
        .position(x: Self.size.width / 2, y: Self.size.height - 65)
    }

    // MARK: Acting

    private func reset() {
        finger = nil
        isPressed = false
        isLidOpen = false
        showsShelf = false
        isSpinning = true
        flyingDisc = nil
        isCaseOpen = false
        trayUp = false
        lcdTrack = 1
        lcdTime = "1:24"
        lit = []
        shelfLabel = 0
    }

    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }

    private func move(to point: CGPoint) async -> Bool {
        withAnimation(.easeInOut(duration: 0.45)) { finger = point }
        return await pause(0.5)
    }

    private func tap() async -> Bool {
        withAnimation(.easeOut(duration: 0.1)) { isPressed = true }
        guard await pause(0.18) else { return false }
        withAnimation(.easeOut(duration: 0.1)) { isPressed = false }
        return await pause(0.2)
    }

    private func act() async {
        reset()
        guard await pause(0.4) else { return }
        withAnimation(.easeOut(duration: 0.3)) { finger = CGPoint(x: Self.size.width / 2, y: Self.size.height + 20) }
        switch lesson {
        case .openLid:
            guard await move(to: Self.deck), await tap() else { return }
            withAnimation(.spring(duration: 0.35, bounce: 0.35)) { isLidOpen = true }
            guard await pause(0.35) else { return }
            withAnimation(.spring(duration: 0.5)) { showsShelf = true }
            guard await pause(0.6) else { return }
            withAnimation { finger = nil }

        case .chooseDisc:
            withAnimation { isLidOpen = true; showsShelf = true; isSpinning = false }
            guard await move(to: Self.frontCase) else { return }
            withAnimation(.easeOut(duration: 0.1)) { isPressed = true }
            withAnimation(.easeInOut(duration: 0.45)) { finger = CGPoint(x: Self.frontCase.x - 60, y: Self.frontCase.y) }
            guard await pause(0.45) else { return }
            withAnimation(.easeOut(duration: 0.1)) { isPressed = false; finger = nil }
            flyingDisc = Self.frontCase
            withAnimation(.easeInOut(duration: 0.55)) { flyingDisc = Self.deck }
            guard await pause(0.6) else { return }
            flyingDisc = nil
            withAnimation(.spring(duration: 0.4)) { showsShelf = false }
            guard await pause(0.3) else { return }
            withAnimation(.spring(duration: 0.28)) { isLidOpen = false }
            lcdTime = "0:00"
            guard await pause(0.5) else { return }
            isSpinning = true

        case .keys:
            guard await move(to: Self.key(2)), await tap() else { return }
            lcdTrack = 2
            lcdTime = "0:00"
            guard await pause(0.4), await move(to: Self.key(0)) else { return }
            withAnimation(.easeOut(duration: 0.1)) { isPressed = true }
            for time in ["0:00", "0:06", "0:21", "0:48"].reversed() {
                lcdTime = time
                guard await pause(0.3) else { return }
            }
            withAnimation(.easeOut(duration: 0.1)) { isPressed = false }
            guard await pause(0.4) else { return }
            withAnimation { finger = nil }

        case .modes:
            guard await move(to: Self.mode(0)), await tap() else { return }
            lit.insert("rep")
            guard await pause(0.3), await move(to: Self.mode(1)), await tap() else { return }
            lit.insert("rnd")
            guard await pause(0.5) else { return }
            withAnimation(.easeOut(duration: 0.1)) { isPressed = true }
            guard await pause(0.7) else { return }
            withAnimation(.easeOut(duration: 0.1)) { isPressed = false }
            isSpinning = false
            guard await pause(0.2) else { return }
            lcdTrack = 1
            lcdTime = "0:00"
            isSpinning = true
            withAnimation { finger = nil }

        case .upNext:
            guard await move(to: Self.grip) else { return }
            withAnimation(.easeOut(duration: 0.1)) { isPressed = true }
            withAnimation(.easeInOut(duration: 0.4)) { finger = CGPoint(x: Self.grip.x, y: 90) }
            withAnimation(.spring(duration: 0.45)) { trayUp = true }
            guard await pause(0.5) else { return }
            withAnimation(.easeOut(duration: 0.1)) { isPressed = false }
            guard await pause(0.4) else { return }
            withAnimation { finger = nil }

        case .holdLid:
            guard await move(to: Self.deck) else { return }
            withAnimation(.easeOut(duration: 0.1)) { isPressed = true }
            guard await pause(0.7) else { return }
            withAnimation(.easeOut(duration: 0.1)) { isPressed = false; finger = nil }
            withAnimation(.spring(duration: 0.45)) { isCaseOpen = true }

        case .shelves:
            withAnimation { isLidOpen = true; showsShelf = true; isSpinning = false }
            for index in [1, 2] {
                guard await move(to: CGPoint(x: 172 + CGFloat(index) * 37, y: 30)), await tap() else { return }
                withAnimation(.easeInOut(duration: 0.2)) { shelfLabel = index }
                guard await pause(0.5) else { return }
            }
            withAnimation { finger = nil }
        }
    }
}
