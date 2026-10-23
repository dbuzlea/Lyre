//
//  LiquidNowPlayingView.swift
//  Lyre
//

import SwiftUI
import MediaPlayer

// MARK: - Liquid Now Playing
//
// The song playing, its cover filling the screen, and very little else: its name, a thin
// line for how far in it is, and play/pause. Songs change by the liquid wave (see
// LiquidWave): the bulge on the right edge carries the next song's cover, the one on the
// left the song before. Drag a bulge in and the wave follows the finger, showing where
// it's going; let go past a little way and it floods the screen and that song plays, or
// short of it and it springs back. Tapping a bulge does the same in one go.
//
// Left always goes back a song, never to the start of this one, since the wave shows the
// song before; the progress line is for moving within a song. A bulge with nothing behind
// it (the first song, the last) isn't shown.
//
// Up Next rises from the bulge on the bottom edge (see LiquidTideView), and the library
// is the button at the top left. Everything that can be done here has something on the
// screen to do it with.
//
// Left alone for a few seconds, the side waves slip away off the edges so the cover has
// the screen to itself (`isResting`). Tapping the cover puts them away at once, or
// brings them back. Dragging the cover down takes Now Playing away, back to the
// library page you came from. They
// stay while VoiceOver is on, which finds them by their place on the screen.
//
// While a song plays, the waves move to its beat like a wave: each bulge swells out on
// every beat and eases back in a smooth curve, and sways a little along the edge, up on
// one beat and down on the next (`pulse(at:)`). The music plays through the system's player, which
// lets no app hear it, so the beat is the song's tempo from its beats-per-minute tag,
// counted from the start of the song. A song with no tempo tagged breathes slowly
// instead.

struct LiquidNowPlayingView: View {
    @ObservedObject var musicService: MusicService
    let themeSettings: ThemeSettings
    let onOpenLibrary: () -> Void
    let onOpenQueue: () -> Void
    let onOpenSettings: () -> Void
    /// The bottom bulge pulled up: how far up the finger has moved, and on letting go,
    /// how far it moved and how far it was heading.
    var onQueueDrag: (CGFloat) -> Void = { _ in }
    var onQueueDragEnd: (CGFloat, CGFloat) -> Void = { _, _ in }
    /// The cover dragged down, to go back to the library: the same two.
    /// Opens the page of the album (or playlist, or show) playing.
    var onOpenPlayingAlbum: () -> Void = {}
    var onDismissDrag: (CGFloat) -> Void = { _ in }
    var onDismissDragEnd: (CGFloat, CGFloat) -> Void = { _, _ in }
    /// iPhone Duo, partly open: which way the fold is, and how far the waves lean
    /// toward it (each from -1 to 1). The hinge as gravity.
    var lean: CGVector = .zero

    @State private var left = WaveState(side: .left)
    @State private var right = WaveState(side: .right)
    @State private var topSide: LiquidSide = .right
    /// The song a wave just flooded in, shown until the player has moved to it.
    @State private var arriving: AppTrack?
    @State private var arrivingTask: Task<Void, Never>?
    /// Brings the bulges back in after a change, from just off the edges.
    @State private var bulgeInset: CGFloat = 0
    /// No touch for a while: the side waves are away, leaving the cover.
    @State private var isResting = false
    /// Gone altogether once they've slipped away, so nothing finds them there.
    @State private var areWavesAway = false
    /// When the song playing started, as the beat counts from it.
    @State private var beatAnchor = Date()
    @State private var restTask: Task<Void, Never>?
    @State private var bottomLift: CGFloat = 0
    @Environment(\.windowSafeArea) private var safeArea
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var library: ShelfLibrary { ShelfLibrary(musicService: musicService) }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                cover(for: current)
                    .ignoresSafeArea()
                    // A tap on the cover puts the waves away, or brings them back; a drag
                    // down takes Now Playing away, back to where you were.
                    .contentShape(Rectangle())
                    .onTapGesture { isResting ? wake() : rest() }
                    // Held, the cover opens its album, as holding what's playing does on
                    // every player.
                    .onLongPressGesture(minimumDuration: 0.5) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onOpenPlayingAlbum()
                    }
                    .gesture(dismissDrag)
                scrim
                    .ignoresSafeArea()

                if current == nil {
                    emptyState
                }

                if arriving == nil, !areWavesAway {
                    // 60 a second at most: the pulse is a slow swell, and on a 120Hz
                    // screen redrawing the two covered waves twice as often buys nothing.
                    TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !isBeating)) { context in
                        let pulse = isBeating ? pulse(at: context.date) : .still
                        ZStack {
                            if let previous {
                                wave(left, covering: previous, size: size, pulse: pulse)
                                    .zIndex(topSide == .left ? 2 : 1)
                            }
                            if let next {
                                wave(right, covering: next, size: size, pulse: pulse)
                                    .zIndex(topSide == .right ? 2 : 1)
                            }
                        }
                    }
                }

                chrome(size: size)
                    .zIndex(3)
                    .allowsHitTesting(left.progress == 0 && right.progress == 0)
            }
            // Any touch, wherever it lands, brings the waves back and restarts the wait.
            // Simultaneous, so it never takes a touch away from what's under it.
            // Any touch while the waves are out keeps them out a while longer.
            // Simultaneous, so it never takes a touch away from what's under it.
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in
                if !isResting { wake() }
            })
            .onAppear {
                wake()
                left.centerY = size.height * 0.42
                right.centerY = size.height * 0.42
                #if DEBUG
                // `-LiquidWaveDemo 0.3` leaves the right wave pulled that far in, for screenshots.
                let demo = UserDefaults.standard.double(forKey: "LiquidWaveDemo")
                if demo > 0 { right.progress = demo }
                #endif
            }
        }
        .onChange(of: musicService.currentTrack?.id ?? musicService.currentEpisode?.id) {
            guard arriving != nil else { return }
            settleArrival()
        }
        .onChange(of: musicService.nowPlayingTrack?.id, initial: true) { syncBeat() }
        .onChange(of: musicService.isPlaying) { syncBeat() }
        .onDisappear { restTask?.cancel() }
    }

    // MARK: Beat

    /// The waves move only while a song plays and nobody's touching them.
    private var isBeating: Bool {
        musicService.isPlaying && !isResting && !reduceMotion && arriving == nil
            && left.progress == 0 && right.progress == 0
    }

    /// The song's tempo, if it's tagged with one that's believable.
    private var beatsPerMinute: Double? {
        guard let bpm = current?.mpItem?.beatsPerMinute, (40...220).contains(bpm) else { return nil }
        return Double(bpm)
    }

    /// Counts the beat from the start of the song, wherever it is now.
    private func syncBeat() {
        beatAnchor = Date().addingTimeInterval(-musicService.clock.time)
    }

    /// The beat's hold on the bulges at a moment: how far they swell out on top of
    /// resting, and how far they sway along the edge.
    struct Pulse {
        var swell: CGFloat
        var sway: CGFloat
        static let still = Pulse(swell: 0, sway: 0)
    }

    /// How far the bulges swell out on top of resting: a smooth wave that crests on each
    /// beat and falls away before the next, with a sway along the edge that takes two
    /// beats to go up and back. A song with no tempo swells slowly instead, as if
    /// breathing.
    private func pulse(at date: Date) -> Pulse {
        let elapsed = date.timeIntervalSince(beatAnchor)
        let beats: Double
        let swellSize: Double
        if let bpm = beatsPerMinute {
            beats = elapsed * bpm / 60
            swellSize = Self.beatSwell
        } else {
            beats = elapsed / 1.6
            swellSize = Self.breathSwell
        }
        // Cresting on the beat: 1 on it, 0 halfway to the next, a little sharper going out
        // than coming back.
        let phase = beats.truncatingRemainder(dividingBy: 1)
        let wave = pow((1 + cos(2 * .pi * phase)) / 2, 1.6)
        let sway = sin(.pi * beats) * Self.sway
        return Pulse(swell: CGFloat(wave * swellSize), sway: CGFloat(sway))
    }

    /// How far a beat swells the bulges, as wave progress, and how far they sway, in points.
    private static let beatSwell = 0.055
    private static let breathSwell = 0.03
    private static let sway = 22.0

    // MARK: Resting

    /// How long without a touch before the waves slip away.
    private static let restDelay: Duration = .seconds(4)

    /// Puts the waves away now, as a tap on the cover asks.
    private func rest() {
        restTask?.cancel()
        guard !UIAccessibility.isVoiceOverRunning, left.progress == 0, right.progress == 0, arriving == nil else { return }
        withAnimation(.easeInOut(duration: 0.45)) {
            isResting = true
        } completion: {
            if isResting { areWavesAway = true }
        }
    }

    /// Down, mostly straight down, from the cover.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .global)
            .onChanged { value in
                guard value.translation.height > 0,
                      value.translation.height > abs(value.translation.width) else { return }
                onDismissDrag(value.translation.height)
            }
            .onEnded { value in
                onDismissDragEnd(max(0, value.translation.height), value.predictedEndTranslation.height)
            }
    }

    /// Brings the waves back, if they're away, and starts the wait again.
    private func wake() {
        if isResting {
            // Back in place off the edges first, then in.
            areWavesAway = false
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { isResting = false }
            }
        }
        restTask?.cancel()
        restTask = Task {
            try? await Task.sleep(for: Self.restDelay)
            guard !Task.isCancelled, !UIAccessibility.isVoiceOverRunning,
                  left.progress == 0, right.progress == 0, arriving == nil else { return }
            withAnimation(.easeInOut(duration: 0.7)) {
                isResting = true
            } completion: {
                if isResting { areWavesAway = true }
            }
        }
    }

    // MARK: Songs

    /// The song shown: one a wave just brought in, or what's playing.
    private var current: AppTrack? { arriving ?? musicService.nowPlayingTrack }

    private var next: AppTrack? { musicService.upcoming.first }

    /// The song before, from the queue's history. A stream's episodes only go forward.
    private var previous: AppTrack? {
        guard musicService.currentEpisode == nil else { return nil }
        let queue = musicService.playbackQueue
        guard !queue.isEmpty, queue.currentIndex > 0 else { return nil }
        return queue.tracks[queue.currentIndex - 1]
    }

    /// A song's cover, or for an episode streaming, its show's.
    @ViewBuilder
    private func cover(for track: AppTrack?) -> some View {
        if let track {
            if musicService.currentEpisode?.id == track.id,
               let show = library.podcasts.first(where: { $0.title == musicService.currentPodcastShowTitle }) {
                LiquidCover(source: .album(show))
            } else {
                LiquidCover(source: .track(track))
            }
        } else {
            LinearGradient(colors: [Color(white: 0.16), Color(white: 0.06)], startPoint: .top, endPoint: .bottom)
        }
    }

    /// Dark at the top and the bottom, so the controls and the name read over any cover.
    private var scrim: some View {
        LinearGradient(stops: [.init(color: .black.opacity(0.45), location: 0),
                               .init(color: .black.opacity(0), location: 0.2),
                               .init(color: .black.opacity(0), location: 0.5),
                               .init(color: .black.opacity(0.75), location: 1)],
                       startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)
    }

    // MARK: Waves

    private func wave(_ state: WaveState, covering track: AppTrack, size: CGSize, pulse: Pulse = .still) -> some View {
        // At rest, the beat moves the bulge; once a finger has it, the finger does. The two
        // sides sway opposite ways, so the screen rocks between them.
        let atRest = state.progress == 0
        // Leaning toward the fold: the bulges slide along their edges toward it, and the
        // one on the fold's side swells, as water runs downhill.
        let toward = max(0, lean.dx * (state.side == .right ? 1 : -1))
        let progress = atRest ? pulse.swell + toward * 0.05 : state.progress
        let centerY = state.centerY + (atRest ? pulse.sway * (state.side == .left ? 1 : -1) + lean.dy * size.height * 0.2 : 0)
        let shape = LiquidWaveShape(side: state.side, centerY: centerY, progress: progress)
        let geometry = LiquidWaveGeometry(side: state.side, centerY: centerY, progress: progress, size: size)
        let isNext = state.side == .right
        return ZStack {
            cover(for: track)
                .frame(width: size.width, height: size.height)
                .mask(shape)
            // The arrow on the bulge.
            ZStack {
                Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1.5)
                Image(systemName: isNext ? "chevron.left" : "chevron.right")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .frame(width: LiquidWaveGeometry.buttonRadius * 2, height: LiquidWaveGeometry.buttonRadius * 2)
            .position(geometry.buttonCenter)
            // Fades as a finger pulls the wave in, not as the beat moves it.
            .opacity(Double(max(1 - state.progress * 5, 0)))
            .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
        .offset(x: (state.side == .left ? -1 : 1) * (bulgeInset + (isResting ? 90 : 0)))
        .opacity(isResting ? 0 : 1)
        .allowsHitTesting(!isResting)
        .shadow(color: .black.opacity(0.35), radius: 12)
        .contentShape(shape)
        .gesture(drag(state.side, size: size))
        .simultaneousGesture(TapGesture().onEnded { commit(state.side, size: size) })
        .accessibilityElement()
        .accessibilityLabel(String(localized: isNext ? "liquid.next" : "liquid.previous"))
        .accessibilityValue(track.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(isNext ? "liquid.wave.next" : "liquid.wave.previous")
        .accessibilityAction { commit(state.side, size: size) }
    }

    private func drag(_ side: LiquidSide, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                topSide = side
                let dx = (side == .left ? 1 : -1) * value.translation.width
                let progress = min(1, max(0, dx * LiquidWaveGeometry.dragGain / size.width))
                let wasPast = state(side).progress >= LiquidWaveGeometry.cancelThreshold
                update(side) { $0.progress = progress; $0.centerY = value.location.y }
                if wasPast != (progress >= LiquidWaveGeometry.cancelThreshold) {
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
            .onEnded { _ in
                if state(side).progress < LiquidWaveGeometry.cancelThreshold {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) { update(side) { $0.progress = 0 } }
                } else {
                    commit(side, size: size)
                }
            }
    }

    /// Floods the screen with the wave's song, and plays it.
    private func commit(_ side: LiquidSide, size: CGSize) {
        guard arriving == nil, let target = side == .right ? next : previous else { return }
        topSide = side
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        let flood: Animation = reduceMotion ? .easeInOut(duration: 0.25) : .easeOut(duration: 0.42)
        withAnimation(flood) {
            update(side) { $0.progress = 1 }
        } completion: {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.6)
            var swap = Transaction()
            swap.disablesAnimations = true
            withTransaction(swap) {
                arriving = target
                left.progress = 0
                right.progress = 0
                bulgeInset = 80
            }
            Task {
                if side == .right {
                    await musicService.skipToNext()
                } else {
                    await musicService.skipToPrevious()
                }
            }
            // If the player never gets there, show what it's playing after all.
            arrivingTask?.cancel()
            arrivingTask = Task {
                try? await Task.sleep(for: .seconds(2.5))
                guard !Task.isCancelled else { return }
                settleArrival()
            }
        }
    }

    /// The player has moved to the song the wave brought in: the bulges come back.
    private func settleArrival() {
        arrivingTask?.cancel()
        arriving = nil
        withAnimation(.spring(response: 0.55, dampingFraction: 0.55)) { bulgeInset = 0 }
    }

    private func state(_ side: LiquidSide) -> WaveState { side == .left ? left : right }

    private func update(_ side: LiquidSide, _ change: (inout WaveState) -> Void) {
        if side == .left { change(&left) } else { change(&right) }
    }

    // MARK: Chrome

    private func chrome(size: CGSize) -> some View {
        VStack(spacing: 0) {
            HStack {
                roundButton("line.3.horizontal", label: "liquid.library", id: "liquid.library", action: onOpenLibrary)
                Spacer()
                AirPlayRouteButton(identifier: "liquid.airplay") { isActive in
                    Image(systemName: "airplayaudio")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isActive ? Color.accentColor : .white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.28), in: Circle())
                }
                PlayerSwitchMenu(themeSettings: themeSettings, identifier: "liquid.playerSwitch") { symbol in
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.28), in: Circle())
                }
                roundButton("ellipsis", label: "settings.title", id: "liquid.settings", action: onOpenSettings)
            }
            .padding(.horizontal, 16)
            .padding(.top, safeArea.top + 6)

            Spacer(minLength: 0)

            if let track = current {
                nowPlaying(track)
                    .padding(.horizontal, 24)
            }

            upNextHandle
                .padding(.top, 18)
                .padding(.bottom, safeArea.bottom)
        }
        .frame(width: size.width, height: size.height)
        .ignoresSafeArea()
    }

    private func nowPlaying(_ track: AppTrack) -> some View {
        let isPodcast = musicService.isPlayingPodcast
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                // The name opens its album.
                Button(action: onOpenPlayingAlbum) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title)
                            .font(.system(size: 28, weight: .bold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                        Text(subtitle(for: track))
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint(String(localized: "liquid.openAlbum.hint"))
                .accessibilityIdentifier("liquid.nowPlaying")
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    Task { await musicService.togglePlayPause() }
                } label: {
                    Image(systemName: musicService.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(.black)
                        .frame(width: 60, height: 60)
                        .background(.white.opacity(0.94), in: Circle())
                }
                .accessibilityLabel(String(localized: musicService.isPlaying ? "spool.pause" : "spool.play"))
                .accessibilityIdentifier("liquid.playPause")
            }
            LiquidProgress(musicService: musicService, clock: musicService.clock)
            if isPodcast {
                HStack {
                    smallButton("gobackward.15", label: "spool.skipBack") {
                        Task { await musicService.jump(by: -PodcastStreamPlayer.skipBackwardInterval) }
                    }
                    Spacer()
                    speedMenu
                    Spacer()
                    smallButton("goforward.30", label: "spool.skipForward") {
                        Task { await musicService.jump(by: PodcastStreamPlayer.skipForwardInterval) }
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.35), radius: 6, y: 1)
    }

    /// A show's playing speed, 0.75× to 2×, as every player offers while a show plays.
    private var speedMenu: some View {
        Menu {
            ForEach(MusicService.podcastRates, id: \.self) { rate in
                Button {
                    musicService.setPodcastRate(rate)
                } label: {
                    if rate == musicService.podcastRate {
                        Label(SpoolPlayerView.speedText(rate), systemImage: "checkmark")
                    } else {
                        Text(SpoolPlayerView.speedText(rate))
                    }
                }
            }
        } label: {
            Text(SpoolPlayerView.speedText(musicService.podcastRate))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(minWidth: 56, minHeight: 36)
                .background(.white.opacity(0.16), in: Capsule())
                .frame(minHeight: 44)
        }
        .accessibilityLabel(String(localized: "spool.speed"))
        .accessibilityValue(SpoolPlayerView.speedText(musicService.podcastRate))
        .accessibilityIdentifier("liquid.speed")
    }

    private func subtitle(for track: AppTrack) -> String {
        if let episode = musicService.currentEpisode, episode.id == track.id { return episode.showTitle }
        return track.albumTitle.isEmpty ? track.artistName : "\(track.artistName) — \(TapeFormat.displayTitle(track.albumTitle))"
    }

    /// The bulge on the bottom edge: tapped, or pulled up, it raises Up Next.
    private var upNextHandle: some View {
        let count = musicService.upcoming.count
        return VStack(spacing: 2) {
            Text(count > 0 ? String(format: String(localized: "liquid.upNext.count"), count)
                           : String(localized: "liquid.upNext"))
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.8))
            LiquidBottomBulge(lift: bottomLift)
                .fill(.white.opacity(0.22))
                .frame(height: 34)
                .overlay(alignment: .bottom) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.bottom, 6)
                }
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenQueue)
        // Pulled up, Up Next rises after the finger like a sheet.
        .gesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .global)
                .onChanged { value in
                    bottomLift = min(1, max(0, -value.translation.height / 120))
                    onQueueDrag(max(0, -value.translation.height))
                }
                .onEnded { value in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { bottomLift = 0 }
                    onQueueDragEnd(max(0, -value.translation.height), -value.predictedEndTranslation.height)
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(String(localized: "spool.queue.open"))
        .accessibilityIdentifier("liquid.upNext")
        .accessibilityAction(.default, onOpenQueue)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text(String(localized: "liquid.nothingPlaying"))
                .font(.system(size: 26, weight: .bold))
            Button(String(localized: "liquid.openLibrary"), action: onOpenLibrary)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 22)
                .frame(height: 48)
                .background(.white, in: Capsule())
                .accessibilityIdentifier("liquid.empty.library")
        }
        .foregroundStyle(.white)
    }

    private func roundButton(_ symbol: String, label: String.LocalizationValue, id: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.28), in: Circle())
        }
        .accessibilityLabel(String(localized: label))
        .accessibilityIdentifier(id)
    }

    private func smallButton(_ symbol: String, label: String.LocalizationValue, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(String(localized: label))
    }
}

/// One side's wave: how far it's been pulled, and where along the edge.
private struct WaveState {
    let side: LiquidSide
    var centerY: CGFloat = 340
    var progress: CGFloat = 0
}

/// How far into the song: a thin line you can drag along, with the times under it.
/// Observes the clock on its own, so its ticks redraw only this.
struct LiquidProgress: View {
    @ObservedObject var musicService: MusicService
    @ObservedObject var clock: PlaybackClock
    @State private var scrub: Double?

    var body: some View {
        let duration = max(musicService.duration, 1)
        let fraction = min(1, max(0, (scrub ?? clock.time) / duration))
        VStack(spacing: 6) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.28))
                    Capsule().fill(.white).frame(width: geometry.size.width * fraction)
                }
                .frame(height: scrub == nil ? 4 : 7)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if scrub == nil { musicService.startScrubbing() }
                            scrub = min(1, max(0, value.location.x / geometry.size.width)) * duration
                        }
                        .onEnded { _ in
                            let time = scrub ?? clock.time
                            scrub = nil
                            Task {
                                await musicService.seek(to: time)
                                musicService.stopScrubbing()
                            }
                        }
                )
                .animation(.easeOut(duration: 0.15), value: scrub == nil)
            }
            .frame(height: 24)
            HStack {
                Text(AppHelpers.formatTime(scrub ?? clock.time))
                Spacer()
                Text("-" + AppHelpers.formatTime(max(0, duration - (scrub ?? clock.time))))
            }
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.75))
        }
        .accessibilityElement()
        .accessibilityLabel(String(localized: "liquid.position"))
        .accessibilityValue(AppHelpers.formatTime(clock.time))
        .accessibilityAdjustableAction { direction in
            Task { await musicService.jump(by: direction == .increment ? 15 : -15) }
        }
    }
}
