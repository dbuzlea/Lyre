//
//  ArtworkCarouselView.swift
//  Lyre
//
//  Created by Daniel Buzlea on 5/14/26.
//

import SwiftUI
import MusicKit
import MediaPlayer
import OSLog

private let logger = Logger(subsystem: "com.pinkhatcreations.lyreapp", category: "ArtworkCarousel")

// MARK: - Artwork Carousel
//
// Full-screen landscape browser showing cover art in a perspective carousel, activated
// when the device rotates to landscape orientation. Inspired by the Lyre classic's
// Artwork Carousel feature. Supports albums, playlists, and podcast shows.
//
// Architecture:
// • `position` is a continuous CGFloat (not an Int) so drag deltas accumulate into
//   smooth sub-item scrolling rather than discrete jumps.
// • A momentum physics loop (startMomentum) runs on @MainActor, decaying velocity by
//   a fixed friction coefficient each 60 fps tick until it drops below the stop
//   threshold, then snaps to the nearest index via a spring animation.
// • Cards beyond `visibleRadius` (±4 from center) are not rendered; the remaining
//   ones are sorted by distance so the center card always draws on top.
//
// Opening an album ("Gatefold"):
// • `foldProgress` is the single driven value: 0 is a closed sleeve, 1 is an open
//   2:1 spread. Every derived visual below is a pure function of it, so the fold
//   reverses cleanly mid-flight — a tap to open followed immediately by a swipe down
//   unwinds from wherever the hinge happens to be.
// • The cover swings left through 180° about its *leading* edge, so it reads as a
//   hinge rather than a coin spin. The back of the cover becomes the left interior
//   panel; the right interior was printed underneath the cover all along.
// • Derived values live inside an `AnimatableFold` so they are recomputed every frame
//   of the spring rather than interpolated between endpoints. See GatefoldView.swift.

// MARK: - Content Type

enum ArtworkCarouselContent {
    case albums([AppAlbum])
    case playlists([AppPlaylist])
    case podcasts([PodcastShow])

    /// Whether its records and their tracks can go in the queue. A show's episodes
    /// can't, in any player: they play from the show.
    var isQueueable: Bool {
        if case .podcasts = self { return false }
        return true
    }

    var itemCount: Int {
        switch self {
        case .albums(let items): return items.count
        case .playlists(let items): return items.count
        case .podcasts(let items): return items.count
        }
    }

    /// What the carousel says when there's nothing in it (LYRE-18).
    var emptyMessage: String {
        switch self {
        case .albums: return String(localized: "empty.albums")
        case .playlists: return String(localized: "empty.playlists")
        case .podcasts: return String(localized: "empty.podcasts")
        }
    }

    var backLabel: String {
        switch self {
        case .albums: return "Albums"
        case .playlists: return "Playlists"
        case .podcasts: return "Podcasts"
        }
    }

    /// Only albums are pressed to vinyl. Playlists fan their covers; podcasts open as books.
    var usesVinyl: Bool {
        if case .albums = self { return true }
        return false
    }

    func title(at index: Int) -> String {
        switch self {
        case .albums(let items): return index < items.count ? items[index].title : ""
        case .playlists(let items): return index < items.count ? items[index].name : ""
        case .podcasts(let items): return index < items.count ? items[index].title : ""
        }
    }

    func subtitle(at index: Int) -> String? {
        switch self {
        case .albums(let items):
            return index < items.count ? items[index].artistName : nil
        case .playlists:
            return nil
        case .podcasts(let items):
            guard index < items.count else { return nil }
            let count = items[index].episodes.count
            return "\(count) episode\(count == 1 ? "" : "s")"
        }
    }

    /// True when the item has no artwork of its own and should fall back to a kraft sleeve.
    func lacksArtwork(at index: Int) -> Bool {
        switch self {
        case .albums(let items):
            guard index < items.count else { return true }
            return items[index].musicKitAlbum?.artwork == nil && items[index].mpArtwork == nil
        case .playlists(let items):
            guard index < items.count else { return true }
            return items[index].musicKitPlaylist?.artwork == nil && items[index].mpArtwork == nil
        case .podcasts(let items):
            guard index < items.count else { return true }
            return !items[index].hasArtwork
        }
    }
}

// MARK: - View

struct ArtworkCarouselView: View {
    let content: ArtworkCarouselContent
    @ObservedObject var musicService: MusicService
    @Binding var selectedIndex: Int
    let onDismiss: () -> Void
    /// Whether Back can leave the carousel. Off on an unfolded iPhone Duo (LYRE-12): its
    /// inner display is wide however it's held, so the carousel is the open phone's own
    /// view and closing the phone is the way back. An open album's own back button stays.
    var showsBackButton = true

    @State private var position: CGFloat = 0
    /// A play waiting to be confirmed, as it would clear songs queued by hand.
    @State private var pendingPlay: PendingPlay?
    @State private var lastTranslation: CGFloat = 0

    // Gatefold state. `foldProgress` is the only value the visuals read.
    @State private var foldProgress: CGFloat = 0
    @State private var isArmed = false
    /// True while a finger is down on the centred cover. A `@GestureState` resets when
    /// its gesture is *cancelled* as well as when it ends, and cancellation is what the
    /// long-press menu does to the cover's open gesture — `onEnded` never runs. Watching
    /// this is the only way to learn the menu took the touch.
    @GestureState private var isPressingCover = false
    @State private var recordSide = 0
    @State private var isRecordFlipping = false
    @State private var recordFlipAngle: Double = 0

    // Fold gesture bookkeeping.
    @State private var foldDragStart: CGFloat?
    /// True once an opening animation has *finished*, false from the moment anything
    /// starts moving the hinge again. See `isSettledOpen` for why this cannot be derived
    /// from `foldProgress`.
    @State private var spreadSettled = false
    @State private var foldDragIsVertical = false
    @State private var lastHalfwayHaptic: Date?
    @State private var wasPastHalfway = false

    @State private var backFaceTracks: [AppTrack] = []
    @State private var backFaceEpisodes: [PodcastEpisode] = []
    @ObservedObject private var downloads = PodcastDownloads.shared
    @State private var backFacePlaylistID: String? = nil
    @State private var backFacePodcastShowTitle: String? = nil
    @State private var isLoadingBackFace = false
    @State private var prefetchedIndex: Int? = nil
    @State private var momentumTask: Task<Void, Never>? = nil

    /// The ink and paper this sleeve is printed in, derived from its cover at arm time.
    @State private var sleeveTheme: SleeveTheme = .default
    @State private var screenSize: CGSize = .zero

    /// Confirmation for queue actions. This view is a fullScreenCover, so the screen
    /// banner the wheel uses is not on top of it and it needs its own.
    @State private var toast: String?
    /// UI-test only: every gatefold action step, in order. See `trace(_:)`.
    @State private var gatefoldTrace: [String] = []
    @State private var toastTask: Task<Void, Never>?

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var coverSize: CGFloat { verticalSizeClass == .compact ? 210 : 260 }
    private var reflectionRatio: CGFloat { 0.75 }
    private var baseSpacing: CGFloat { verticalSizeClass == .compact ? 42 : 52 }
    private let sideAngle: Double = 70
    private let minVisibleRadius = 3
    private let maxVisibleRadius = 9

    /// Height of the band the cards live in.
    ///
    /// The ideal band is the cover plus its full reflection, but that alone overruns a
    /// landscape phone once the top bar is accounted for — 36 + 369.5 against a 390 pt
    /// screen — which pushes the title and artist off the bottom. So the band gives way to
    /// the fixed chrome and crops the tail of the reflection instead, which is where the
    /// reflection has already faded to nothing.
    private var carouselHeight: CGFloat {
        let ideal = coverSize * (1 + reflectionRatio) + 2
        guard screenSize.height > 0 else { return ideal }
        let chrome = topBarHeight + infoGap + infoBlockHeight + bottomInset
        return min(ideal, max(coverSize + 20, screenSize.height - chrome))
    }

    /// Cover plus hairline plus reflection — the intrinsic height of a card. Usually taller
    /// than the band, in which case the band centres it.
    private var artStackHeight: CGFloat { coverSize * (1 + reflectionRatio) + 1 }

    // MARK: - Fold Timing
    //
    // One knob. `openResponse` sets how long the sleeve takes to swing; the two delays
    // below are fractions of it, because the 90° and landing haptics are *scheduled* rather
    // than observed and would drift out of step with the hinge if tuned separately.
    // The multipliers are what reproduced the original 0.52 spring's real timings.

    /// Raise to open more slowly, lower to snap.
    private let openResponse: Double = 0.68
    private let openDamping: Double = 0.74

    private var openSpring: Animation {
        .spring(response: openResponse, dampingFraction: openDamping)
    }

    /// When the spring reaches roughly p = 0.5.
    private var openHalfwayDelay: TimeInterval { openResponse * 0.8 }
    /// When it has effectively settled flat.
    private var openSettleDelay: TimeInterval { openResponse * 1.23 }

    private var topBarHeight: CGFloat { verticalSizeClass == .compact ? 36 : 50 }
    private var infoGap: CGFloat { verticalSizeClass == .compact ? 10 : 18 }
    private var infoBlockHeight: CGFloat { verticalSizeClass == .compact ? 40 : 48 }
    private var bottomInset: CGFloat { verticalSizeClass == .compact ? 10 : 22 }

    private var pixelsPerItem: CGFloat { coverSize * 0.5 + baseSpacing }

    private var centeredIndex: Int {
        max(0, min(content.itemCount - 1, Int(position.rounded())))
    }

    /// Any fold at all, including mid-flight. Gates carousel scrolling and the back button.
    private var isOpen: Bool { foldProgress > 0.001 }

    /// Whether a track is the one loaded in the player.
    ///
    /// `updateNowPlayingItem` rebuilds `currentTrack` by looking the now-playing item up in
    /// the global song list, so its `id` is not necessarily the one an album or playlist
    /// request handed back. Hence the fallback chain rather than a plain `id` comparison.
    private func isCurrentTrack(_ track: AppTrack) -> Bool {
        guard let current = musicService.currentTrack else { return false }
        if track.id == current.id { return true }
        if let lhs = track.mpPersistentID, let rhs = current.mpPersistentID {
            return lhs == rhs
        }
        return track.title == current.title && track.albumTitle == current.albumTitle
    }

    /// Whether the open sleeve is the one the player is working through.
    ///
    /// Without this the disc spins for *any* playback, so opening a second album while the
    /// first is still playing shows a record turning that nobody put on.
    private var isCurrentItem: Bool {
        switch content {
        case .podcasts:
            return backFaceEpisodes.contains { musicService.isCurrentEpisode($0) }
        case .albums, .playlists:
            return backFaceTracks.contains { isCurrentTrack($0) }
        }
    }

    private var isPlayingThisItem: Bool {
        isCurrentItem && musicService.isPlaying
    }

    /// The disc only turns for this sleeve's own playback, and never in Low Power Mode
    /// or under a UI test — a perpetual animation stops the app ever going idle, which
    /// is what XCUITest waits for before each query.
    private var discIsSpinning: Bool {
        isPlayingThisItem
            && !ProcessInfo.processInfo.isLowPowerModeEnabled
            && !AppEnvironment.isUITesting
    }

    var body: some View {
        ZStack {
            if isOpen {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
            }

            VStack(spacing: 0) {
                topBar
                if content.itemCount == 0 {
                    emptyState
                        .frame(maxHeight: .infinity)
                } else {
                    carouselSection(panel: panelSize)
                    Spacer(minLength: 0)
                        .frame(height: isOpen ? 4 : infoGap)
                    infoSection
                        .frame(height: infoBlockHeight)
                }
                Spacer(minLength: bottomInset)
            }

            if let toast {
                toastView(toast)
            }

            if AppEnvironment.isUITesting {
                // Near-invisible but present in the accessibility tree, which is all the
                // UI test needs. Never built outside `--uitest`.
                Text(gatefoldTrace.isEmpty ? "none" : gatefoldTrace.joined(separator: " | "))
                    .font(.system(size: 1))
                    .opacity(0.01)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("gatefold.trace")
            }
        }
        // Black bleeds to the physical edges, but as a *background* rather than a ZStack
        // child. As a child its `ignoresSafeArea` would grow the ZStack to the full screen,
        // and the chrome laid out inside it would sit under the camera housing — in
        // landscape that is a ~59 pt leading inset, enough to swallow the back button.
        .background(Color.black.ignoresSafeArea())
        // Measured in the background so reading the size cannot disturb the layout. Wrapping
        // the body in a GeometryReader instead pushes the VStack down by the bottom safe-area
        // inset — the reader pins its child top-leading rather than centring it — which clips
        // the info section off the bottom of the screen.
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { screenSize = proxy.size }
                    .onChange(of: proxy.size) { _, newValue in screenSize = newValue }
            }
        }
        .onAppear {
            position = CGFloat(selectedIndex)
        }
        .onChange(of: selectedIndex) { _, newValue in
            if abs(position - CGFloat(newValue)) > 0.5 {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                    position = CGFloat(newValue)
                }
            }
        }
        .replaceQueuePrompt($pendingPlay, count: musicService.listenerQueuedCount)
    }

    // MARK: - Geometry

    /// One square panel of the open spread. Two of them plus the gutter fill the screen.
    /// Falls back to the closed cover size until the background reader reports in.
    ///
    /// Bounded by the carousel band rather than the raw screen height: the spread is centred
    /// in that band and nothing clips it, so a panel taller than the band would ride up over
    /// the back button.
    private var panelSize: CGFloat {
        guard screenSize.width > 0, screenSize.height > 0 else { return coverSize }
        let byHeight = carouselHeight - 8
        let byWidth = (screenSize.width - 64) / 2
        return max(120, min(byHeight, byWidth))
    }

    /// Floats over the spread rather than sitting in the layout: the chrome here is
    /// already tight enough that a reserved row would cost the reflection more height.
    private func toastView(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color(white: 0.16).opacity(0.94)))
                .padding(.bottom, bottomInset + 6)
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .transition(.opacity)
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            if isOpen || showsBackButton {
                Button(action: {
                    if isOpen { close() } else { onDismiss() }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text(isOpen ? content.backLabel : "Back")
                            .font(.system(size: 14))
                    }
                    .foregroundColor(.white)
                }
                .accessibilityIdentifier("carousel.back")
            } else {
                // Where Back would be, how to get back instead.
                Label(String(localized: "carousel.closeToGoBack"), systemImage: "iphone.gen3")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.5))
                    .accessibilityIdentifier("carousel.closeHint")
            }
            Spacer()
        }
        .padding(.leading, 20)
        .padding(.top, verticalSizeClass == .compact ? 8 : 14)
        .frame(height: topBarHeight)
    }

    // MARK: - Empty

    /// Said in place of the covers when there are none, rather than leaving a black
    /// screen that reads as something gone wrong (LYRE-18). Without access to the music
    /// library that's the likelier reason, so it says how to give it.
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.stack")
                .font(.system(size: 34, weight: .light))
                .foregroundColor(Color(white: 0.45))
                .accessibilityHidden(true)
            Text(content.emptyMessage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
            if content.isQueueable, !musicService.isAuthorized {
                Text(String(localized: "empty.enableAccess"))
                    .font(.system(size: 14))
                    .foregroundColor(Color(white: 0.62))
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("carousel.empty")
    }

    // MARK: - Info Section

    private var infoSection: some View {
        Group {
            if content.itemCount > 0, centeredIndex < content.itemCount {
                VStack(alignment: .leading, spacing: 3) {
                    Text(content.title(at: centeredIndex))
                        .font(.system(size: verticalSizeClass == .compact ? 16 : 20, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if let subtitle = content.subtitle(at: centeredIndex) {
                        Text(subtitle)
                            .font(.system(size: verticalSizeClass == .compact ? 12 : 14))
                            .foregroundColor(Color(white: 0.62))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .id(centeredIndex)
                // Rest info clears early, well before the spread lands.
                .opacity(Double(1 - min(1, 3 * foldProgress)))
                .animation(.easeInOut(duration: 0.18), value: centeredIndex)
            }
        }
    }

    // MARK: - Carousel

    private func carouselSection(panel: CGFloat) -> some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(visibleIndices(in: geometry.size.width), id: \.self) { index in
                    // The settled spread *replaces* the centre card rather than
                    // covering it. Leaving both in place built the interior panels
                    // twice, so every control existed in duplicate — one copy in the
                    // rotated flap and one in the spread — and a touch could land on
                    // whichever the system happened to prefer.
                    if !(isSettledOpen && index == centeredIndex) {
                        coverCard(for: index, panel: panel)
                            .zIndex(index == centeredIndex ? 200 : zIndex(for: index))
                    }
                }
                // The neighbouring cards are mid-animation scenery; they have no
                // business taking touches while the sleeve is open.
                .allowsHitTesting(!isSettledOpen)

                // Kept in the hierarchy for the whole time the sleeve is open or being
                // dragged, and only *shown* once settled. The scrub gesture lives on
                // this view, and removing a view cancels any gesture running on it —
                // so if the spread vanished as soon as a drag nudged the hinge off 1,
                // the drag that was closing the sleeve would die one pixel in.
                if isOpen || foldDragStart != nil {
                    openSpread(for: centeredIndex, panel: panel)
                        .opacity(isSettledOpen ? 1 : 0)
                        .zIndex(300)
                }
            }
            .frame(width: geometry.size.width, height: carouselHeight)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .frame(height: carouselHeight)
        // Suppressed over the open spread; the spread runs it as a simultaneous
        // gesture instead, so the controls inside it get first refusal on every touch.
        .gesture(carouselDrag(panel: panel), including: isOpen ? .subviews : .all)
    }

    /// The open spread, laid out plainly: two square panels side by side, no rotation,
    /// no offset, nothing drawn outside its own bounds.
    ///
    /// The hinge cannot carry the controls. SwiftUI hit-tests against a view's
    /// *untransformed* geometry, so anything inside the flap answers in a mirrored
    /// position, and a faded-out layer keeps taking touches because `opacity(0)` is
    /// still hit-testable. Chasing those one at a time just moved the dead zone around.
    /// So the fold is decoration and this is the real thing: once `foldProgress` lands,
    /// this spread is laid over the top, pixel-identical to where the animation
    /// finished, and it owns every touch.
    ///
    /// The geometry lines up because the animated spread ends up centred here too: the
    /// centre card is pushed right by half a panel, its left flap swings a full panel
    /// left, and the two cancel.
    private func openSpread(for index: Int, panel: CGFloat) -> some View {
        HStack(spacing: 0) {
            interiorLeft(for: index, size: panel)
                .frame(width: panel, height: panel)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                // The hinge scrub belongs to the left panel only. Across the whole
                // spread it also ran under the liner's track list, so scrolling a long
                // playlist or podcast moved the hinge too, and a downward scroll could
                // close the sleeve. The right panel's drags are the list's own.
                //
                // Simultaneous so it cannot cancel a tap: a plain drag that recognises
                // after 1 pt beats a Button, and almost every real tap moves more than
                // 1 pt. The content shape lets the whole panel start a scrub, not just
                // the parts that happen to be drawn.
                .contentShape(Rectangle())
                .simultaneousGesture(carouselDrag(panel: panel))

            interiorRight(for: index, size: panel)
                .overlay { castShadow(p: 1, size: panel) }
                .frame(width: panel, height: panel)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .frame(width: panel * 2, height: panel)
        .overlay {
            // Sized to one panel so the gradient's dark band lands on the gutter,
            // matching where the animated assembly puts it.
            gutterShadow(p: 1, size: panel)
                .frame(width: panel, height: panel)
                .allowsHitTesting(false)
        }
    }

    /// True once the hinge has finished opening and nothing is moving it.
    ///
    /// This cannot be read off `foldProgress`. `withAnimation` sets the stored value to
    /// its target immediately and only the *rendered* value travels, so `foldProgress`
    /// is already 1 on the first frame of the opening. Testing it made the flat spread
    /// replace the animated sleeve before the hinge had moved, and the album appeared
    /// with no animation at all.
    private var isSettledOpen: Bool { spreadSettled && foldProgress > 0.999 }

    /// Animates the hinge fully open and marks the spread settled only when it lands.
    private func animateOpen(_ animation: Animation, alongside changes: () -> Void = {}) {
        spreadSettled = false
        withAnimation(animation, completionCriteria: .logicallyComplete) {
            foldProgress = 1
            changes()
        } completion: {
            // A drag or close that began mid-flight owns the hinge now.
            guard foldDragStart == nil, foldProgress > 0.999 else { return }
            spreadSettled = true
        }
    }

    /// One gesture serves both jobs: scrolling the carousel when closed, and scrubbing or
    /// dismissing the hinge when open.
    private func carouselDrag(panel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                momentumTask?.cancel()
                momentumTask = nil

                if isOpen || foldDragStart != nil {
                    scrubFold(value: value, panel: panel)
                    return
                }

                let delta = value.translation.width - lastTranslation
                lastTranslation = value.translation.width
                let maxIdx = CGFloat(max(0, content.itemCount - 1))
                position = max(0, min(maxIdx, position - delta / pixelsPerItem))
            }
            .onEnded { value in
                if foldDragStart != nil {
                    endFoldScrub(value: value, panel: panel)
                    return
                }
                guard !isOpen else { return }
                lastTranslation = 0
                let initialVelocity = value.velocity.width / pixelsPerItem
                startMomentum(initialVelocity: initialVelocity)
            }
    }

    // MARK: - Card Dispatch

    @ViewBuilder
    private func coverCard(for index: Int, panel: CGFloat) -> some View {
        let isCentered = index == centeredIndex
        let rawPosition = CGFloat(index) - position

        if isCentered {
            AnimatableFold(progress: foldProgress) { p in
                centerCard(for: index, panel: panel, p: p)
                    .rotation3DEffect(
                        .degrees(centerCardRotation(rawPosition: rawPosition, p: p)),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.42
                    )
                    .offset(x: xOffset(for: index) * (1 - p) + 0.5 * panel * p)
                    .scaleEffect(isArmed && p < 0.02 ? 1.03 : 1.0)
                    .offset(y: isArmed && p < 0.02 ? -6 : 0)
            }
            .animation(.spring(response: 0.22, dampingFraction: 0.90), value: isArmed)
        } else {
            AnimatableFold(progress: foldProgress) { p in
                sideCard(for: index)
                    .scaleEffect(coverScale(rawPosition: rawPosition))
                    .rotation3DEffect(
                        .degrees(rotationAngle(rawPosition: rawPosition)),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.35
                    )
                    // Neighbours part outward and blur away as the sleeve opens.
                    .offset(x: xOffset(for: index) + (rawPosition < 0 ? -240 : 240) * p)
                    .opacity(Double(1 - p))
                    .blur(radius: 5 * p)
            }
            .offset(x: isArmed && foldProgress < 0.02 ? (rawPosition < 0 ? -18 : 18) : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.90), value: isArmed)
        }
    }

    // MARK: - Center Card

    /// The hinged sleeve. At p = 0 this is exactly the closed cover with its reflection,
    /// sitting where the side cards sit; at p = 1 it is the centred 2:1 spread.
    @ViewBuilder
    private func centerCard(for index: Int, panel: CGFloat, p: CGFloat) -> some View {
        let sleeve = coverSize + (panel - coverSize) * p
        // Closed, the cover sits where a side card's cover sits — which is not the top of
        // the band, because the art-plus-reflection stack is taller than the band and gets
        // centred in it. Matching that offset is what keeps the centre card level with its
        // neighbours. Open, the spread is centred, so the offset interpolates to zero.
        let restY = coverSize / 2 - artStackHeight / 2
        let assemblyY = restY * (1 - p)

        ZStack {
            foldAssembly(for: index, sleeve: sleeve, p: p)
                .offset(y: assemblyY)
        }
        .frame(width: coverSize, height: carouselHeight)
    }

    /// The mirrored cover below the sleeve, hinging on the same spine.
    ///
    /// A floor mirror flips vertically but not horizontally, so the reflected cover swings
    /// the same way the real one does. Handing it the same rotation and the same leading
    /// anchor gets that for free, and the foreshortening thins it to a sliver exactly as the
    /// cover reaches edge-on — which is why the fade can be gentler than a plain dissolve.
    @ViewBuilder
    private func reflectedFlap(for index: Int, size: CGFloat, p: CGFloat) -> some View {
        let alpha = Double(1 - min(1, 2 * p))

        if alpha > 0.001 {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.clear, Color(white: 0.65).opacity(0.75), Color.clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: size, height: 1)

                artworkImage(for: index, size: size)
                    .frame(width: size, height: size)
                    .cornerRadius(5)
                    .scaleEffect(x: 1, y: -1)
                    .mask(
                        LinearGradient(
                            colors: [Color.black.opacity(0.52), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: size * reflectionRatio)
                        .frame(maxHeight: .infinity, alignment: .top)
                    )
                    .frame(height: size * reflectionRatio)
                    .clipped()
            }
            .frame(width: size)
            .opacity(alpha)
            .rotation3DEffect(
                .degrees(-Double(p) * 180),
                axis: (x: 0, y: 1, z: 0),
                anchor: .leading,
                perspective: 0.5
            )
            // Hangs off the bottom edge of the sleeve.
            .offset(y: size / 2 + (size * reflectionRatio + 1) / 2)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Fold Assembly

    @ViewBuilder
    private func foldAssembly(for index: Int, sleeve: CGFloat, p: CGFloat) -> some View {
        ZStack {
            // Behind everything, on the "floor".
            reflectedFlap(for: index, size: sleeve, p: p)

            // The right interior was printed under the cover all along; the cover's shadow
            // retreats off it as the flap swings away.
            interiorRight(for: index, size: sleeve)
                .overlay { castShadow(p: p, size: sleeve) }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .opacity(p > 0.001 ? 1 : 0)
                // The animated sleeve's interiors are pictures. Transparent is not the
                // same as hidden to accessibility, so a *closed* sleeve used to expose
                // its Play, Shuffle and disc to VoiceOver. The settled spread carries the
                // accessible copies.
                .accessibilityHidden(true)

            if reduceMotion {
                // No hinge: the spread cross-dissolves into place.
                interiorLeft(for: index, size: sleeve)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .offset(x: -sleeve)
                    .opacity(Double(p))
                    .accessibilityHidden(true)

                coverFace(for: index, size: sleeve, p: p, showsSweep: false)
                    .opacity(Double(1 - p))
            } else {
                flap(for: index, size: sleeve, p: p)
            }

            gutterShadow(p: p, size: sleeve)
                .offset(x: -sleeve / 2)
                .allowsHitTesting(false)
        }
        .frame(width: sleeve, height: sleeve)
    }

    /// The cover, hinged on its leading edge. SwiftUI has no backface culling, so the two
    /// faces swap at 90° and the back one is pre-rotated to read the right way round.
    @ViewBuilder
    private func flap(for index: Int, size: CGFloat, p: CGFloat) -> some View {
        ZStack {
            coverFace(for: index, size: size, p: p, showsSweep: true)
                .opacity(p < 0.5 ? 1 : 0)
                .allowsHitTesting(p < 0.5)

            // Never hit-testable. A 3D rotation moves this panel visually left of the
            // spine but hit-testing still uses the pre-rotation frame, which lands
            // squarely on top of the liner — so taking touches here made the track
            // rows on the right unreachable. Nothing on this panel is interactive.
            interiorLeft(for: index, size: size)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(p >= 0.5 ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            // The card's own thickness, only visible edge-on. Uses `stock` rather than
            // `card`: this is cut board, and it stays pale even when the interior is dark.
            HStack(spacing: 0) {
                Rectangle()
                    .fill(sleeveTheme.stock)
                    .frame(width: 3)
                Spacer(minLength: 0)
            }
            .opacity(Double(max(0, 1 - abs(p - 0.5) * 8)))
            .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
        .rotation3DEffect(
            .degrees(-Double(p) * 180),
            axis: (x: 0, y: 1, z: 0),
            anchor: .leading,
            perspective: 0.5
        )
    }

    // MARK: - Cover Face

    @ViewBuilder
    private func coverFace(for index: Int, size: CGFloat, p: CGFloat, showsSweep: Bool) -> some View {
        artworkImage(for: index, size: size)
            .frame(width: size, height: size)
            .overlay {
                if showsSweep {
                    specularSweep(size: size, p: p)
                }
            }
            .overlay(alignment: .leading) {
                // A little light catching the spine.
                LinearGradient(
                    colors: [Color.white.opacity(0.18), Color.clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: size * 0.06)
                .blendMode(.screen)
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .shadow(color: .black.opacity(0.85), radius: 14, x: 0, y: 7)
            .contentShape(Rectangle())
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 5))
            .gesture(openGesture(index: index))
            // Touch and hold queues the whole record without opening it. Holding still
            // is the one thing no other gatefold gesture asks for — every drag here is
            // told apart by its direction — so this cannot be set off by a scroll, a
            // scrub or a flip. Empty (and so switched off) unless this is the closed,
            // centred cover.
            .contextMenu {
                // Shows have no queue menu: their episodes are never queued.
                if index == centeredIndex, !isOpen, content.isQueueable {
                    collectionQueueMenu(for: index)
                }
            }
            .onChange(of: isPressingCover) { _, isPressing in
                // The menu cancels the open gesture, so its `onEnded` never runs and the
                // cover would stay lifted underneath the menu. Put it back down. A
                // cancelled gesture cannot open the sleeve, so nothing else is needed —
                // an earlier hold-time limit kept its own state in `onEnded`, never got
                // to reset it, and so broke the next ordinary tap.
                guard !isPressing, isArmed, !isOpen else { return }
                withAnimation(.spring(response: 0.22, dampingFraction: 0.90)) {
                    isArmed = false
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(coverAccessibilityLabel(index: index))
            .accessibilityHint("Opens the sleeve")
            .accessibilityAddTraits(.isButton)
            .accessibilityActions {
                if content.isQueueable {
                    Button(String(localized: "queue.action.playNext")) { queueCollection(at: index, placement: .next) }
                    Button(String(localized: "queue.action.addToQueue")) { queueCollection(at: index, placement: .last) }
                }
            }
            // Only the centred cover carries this, so a test can open the sleeve
            // without knowing which album happens to be in the middle.
            .accessibilityIdentifier(index == centeredIndex ? GatefoldID.cover : "")
    }

    /// A band of light that travels across the cover as it swings. Its position is tied to
    /// the fold rather than to time, so dragging the hinge back un-sweeps the light.
    private func specularSweep(size: CGFloat, p: CGFloat) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0), location: 0.38),
                        .init(color: .white.opacity(0.62), location: 0.50),
                        .init(color: .white.opacity(0), location: 0.62)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: size * 2.2, height: size * 2.2)
            .rotationEffect(.degrees(14))
            .offset(x: (-1.2 + 2.5 * p) * size)
            .blendMode(.screen)
            .opacity(Double((1 - abs(2 * p - 1)) * 0.9))
            .allowsHitTesting(false)
    }

    // MARK: - Shadows

    /// The crease. Peaks at 90° and settles low but never to zero — a real gatefold keeps a
    /// shadow in the fold.
    @ViewBuilder
    private func gutterShadow(p: CGFloat, size: CGFloat) -> some View {
        let opacity = sin(Double.pi * Double(p)) * 0.42 + 0.09 * Double(p)

        if contrast == .increased {
            // Drawn in ink rather than a fixed dark, so the rule still contrasts once the
            // interior itself has gone dark behind a photograph.
            Rectangle()
                .fill(sleeveTheme.ink.opacity(0.8))
                .frame(width: 1, height: size)
                .opacity(p > 0.5 ? 1 : 0)
        } else {
            Rectangle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0), location: 0.0),
                            .init(color: .black.opacity(0.85), location: 0.48),
                            .init(color: .black, location: 0.50),
                            .init(color: .black.opacity(0.85), location: 0.52),
                            .init(color: .black.opacity(0), location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 52, height: size)
                .opacity(opacity)
        }
    }

    /// The cover's shadow lying across the liner, retreating off it as the flap lifts.
    private func castShadow(p: CGFloat, size: CGFloat) -> some View {
        let ink = max(0, min(1, (p - 0.30) / 0.45))
        let edge = max(0.0, min(1.0, Double(1 - p)))

        return Rectangle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.88), location: 0.0),
                        .init(color: .black.opacity(0.88), location: edge),
                        .init(color: .black.opacity(0.10), location: min(1.0, edge + 0.22)),
                        .init(color: .black.opacity(0.04), location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .opacity(Double(1 - 0.92 * ink))
            .allowsHitTesting(false)
    }

    // MARK: - Side Card

    @ViewBuilder
    private func sideCard(for index: Int) -> some View {
        artWithReflection(for: index)
            .onTapGesture {
                guard !isOpen else { return }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                    position = CGFloat(index)
                    selectedIndex = index
                }
            }
    }

    // MARK: - Art + Reflection

    @ViewBuilder
    private func artWithReflection(for index: Int) -> some View {
        VStack(spacing: 0) {
            artworkImage(for: index, size: coverSize)
                .frame(width: coverSize, height: coverSize)
                .cornerRadius(5)
                .shadow(color: .black.opacity(0.85), radius: 14, x: 0, y: 7)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.clear, Color(white: 0.65).opacity(0.75), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: coverSize, height: 1)

            artworkImage(for: index, size: coverSize)
                .frame(width: coverSize, height: coverSize)
                .cornerRadius(5)
                .scaleEffect(x: 1, y: -1)
                .mask(
                    LinearGradient(
                        colors: [Color.black.opacity(0.52), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: coverSize * reflectionRatio)
                    .frame(maxHeight: .infinity, alignment: .top)
                )
                .frame(height: coverSize * reflectionRatio)
                .clipped()
        }
        .frame(width: coverSize, height: carouselHeight)
    }

    // MARK: - Artwork Image

    @ViewBuilder
    private func artworkImage(for index: Int, size: CGFloat) -> some View {
        switch content {
        case .albums(let items):
            if index < items.count {
                let album = items[index]
                if let artwork = album.musicKitAlbum?.artwork {
                    ArtworkImage(artwork, width: size)
                } else if album.mpArtwork != nil {
                    // Decoded once in the background, not on every redraw of a drag.
                    LocalArtworkImage(cacheKey: album.id, size: size, artwork: album.mpArtwork) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        placeholderArt(icon: "music.note", size: size)
                    }
                } else {
                    KraftSleeve(title: album.title, size: size)
                }
            } else {
                placeholderArt(icon: "music.note", size: size)
            }
        case .playlists(let items):
            if index < items.count {
                let playlist = items[index]
                if let artwork = playlist.musicKitPlaylist?.artwork {
                    ArtworkImage(artwork, width: size)
                } else if playlist.mpArtwork != nil {
                    LocalArtworkImage(cacheKey: playlist.id, size: size, artwork: playlist.mpArtwork) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        placeholderArt(icon: "music.note.list", size: size)
                    }
                } else {
                    KraftSleeve(title: playlist.name, size: size)
                }
            } else {
                placeholderArt(icon: "music.note.list", size: size)
            }
        case .podcasts(let items):
            if index < items.count {
                let show = items[index]
                LocalArtworkImage(cacheKey: show.artworkCacheKey, size: size, artwork: show.artwork, remoteURL: show.artworkURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    KraftSleeve(title: show.title, size: size)
                }
            } else {
                placeholderArt(icon: "mic.fill", size: size)
            }
        }
    }

    @ViewBuilder
    private func placeholderArt(icon: String, size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Color(white: 0.18))
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: size * 0.28))
                    .foregroundColor(Color(white: 0.44))
            }
    }

    // MARK: - Spread Backdrop

    /// One continuous image printed across both inner panels, the way a real gatefold's
    /// spread usually is.
    ///
    /// The cover is blown up to twice the panel width and cropped to a horizontal band; the
    /// left panel shows that band's left half and the right panel its right half, so the two
    /// line up across the gutter. The left panel is the back of the flap and gets mirrored
    /// twice on its way there — once pre-rotated, once by the hinge — so both halves can be
    /// positioned in the same un-mirrored coordinate space.
    ///
    /// The scrim dissolves left to right: the artwork reads behind the disc, and by the time
    /// it reaches the tracklist it has gone near-solid. That is the same move as the
    /// reference screenshot, turned on its side to suit a spread rather than a scroll.
    @ViewBuilder
    private func spreadBackdrop(for index: Int, size: CGFloat, isLeftPanel: Bool) -> some View {
        if content.lacksArtwork(at: index) {
            // Nothing to print; fall back to plain stock.
            sleeveTheme.card
        } else {
            Color.clear
                .frame(width: size, height: size)
                .overlay {
                    artworkImage(for: index, size: size * 2)
                        .blur(radius: 12)
                        .frame(width: size * 2, height: size)
                        .clipped()
                        .offset(x: isLeftPanel ? size / 2 : -size / 2)
                }
                .clipped()
                .overlay {
                    LinearGradient(
                        colors: isLeftPanel
                            ? [sleeveTheme.card.opacity(0.28), sleeveTheme.card.opacity(0.58)]
                            : [sleeveTheme.card.opacity(0.88), sleeveTheme.card.opacity(0.96)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
                .overlay {
                    // The credits and pills sit low on the left panel, where the horizontal
                    // scrim alone is far too light to carry white type.
                    if isLeftPanel {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.40),
                                .init(color: sleeveTheme.card.opacity(0.92), location: 0.78)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
        }
    }

    // MARK: - Interiors

    /// The record, the fanned covers, or the show art, depending on content type.
    @ViewBuilder
    private func interiorLeft(for index: Int, size: CGFloat) -> some View {
        let reveal = max(0, min(1, (foldProgress - 0.58) / 0.32))

        ZStack {
            spreadBackdrop(for: index, size: size, isLeftPanel: true)
                // Decoration only. The artwork inside is drawn at twice the panel's width
                // and shifted sideways; `.clipped()` hides the overflow but does not limit
                // hit-testing, so without this the right panel's invisible overflow lay on
                // top of the entire left panel and swallowed every touch meant for the
                // disc and pills. Accessibility looked straight through it (an image is
                // not an element), which is why the controls tested as hittable.
                .allowsHitTesting(false)

            switch content {
            case .albums:
                RecordPanel(
                    panel: size,
                    title: content.title(at: index),
                    subtitle: creditsLine(for: index),
                    reveal: reveal,
                    isSpinning: discIsSpinning,
                    isPlayingThisItem: isPlayingThisItem,
                    isFlipping: isRecordFlipping,
                    flipAngle: recordFlipAngle,
                    showsWhiteLabel: content.lacksArtwork(at: index),
                    label: { artworkImage(for: index, size: size * 0.57 * 0.36) },
                    onDiscTap: { primaryAction() },
                    onPlay: { primaryAction() },
                    onShuffle: { playAll(shuffled: true) }
                )
                // Simultaneous, not exclusive. As a plain `.gesture` on the panel this
                // drag claimed every touch that began inside it, so the disc and both
                // pills were hit-tested and touched but their actions never ran — the
                // UI test proved it by recording nothing at all for four taps. The
                // right-hand panel has no parent gesture, which is why it always worked.
                .simultaneousGesture(recordSwipe)

            case .playlists:
                PlaylistFanPanel(
                    panel: size,
                    title: content.title(at: index),
                    subtitle: creditsLine(for: index),
                    reveal: reveal,
                    artworkCount: max(1, min(4, backFaceTracks.count)),
                    isPlayingThisItem: isPlayingThisItem,
                    artwork: { _ in artworkImage(for: index, size: size * 0.46) },
                    onPlay: { primaryAction() },
                    onShuffle: { playAll(shuffled: true) }
                )

            case .podcasts:
                ShowPanel(
                    panel: size,
                    title: content.title(at: index),
                    subtitle: content.subtitle(at: index) ?? "",
                    reveal: reveal,
                    artwork: { artworkImage(for: index, size: size * 0.52) }
                )
            }
        }
        .frame(width: size, height: size)
        .environment(\.sleeveTheme, sleeveTheme)
    }

    /// The printed liner.
    @ViewBuilder
    private func interiorRight(for index: Int, size: CGFloat) -> some View {
        ZStack {
            spreadBackdrop(for: index, size: size, isLeftPanel: false)
                .allowsHitTesting(false)

            if isLoadingBackFace {
                ProgressView()
                    .tint(sleeveTheme.ink.opacity(0.5))
                    .scaleEffect(0.85)
            } else {
                LinerPanel(
                    width: size - 34,
                    height: size - 34,
                    header: linerHeader(for: index),
                    rows: linerRows,
                    sideCount: max(1, sides.count),
                    currentSide: recordSide,
                    showsSideControl: sides.count > 1,
                    onSelect: { globalIndex in playTrack(at: globalIndex) },
                    onQueue: { globalIndex, placement in queueTrack(at: globalIndex, placement: placement) },
                    canQueue: content.isQueueable,
                    onSideChange: { flipRecord(to: $0) },
                    onDownload: { globalIndex in toggleDownload(at: globalIndex) }
                )
            }
        }
        .frame(width: size, height: size)
        .environment(\.sleeveTheme, sleeveTheme)
    }

    // MARK: - Liner Data

    /// Podcasts and short albums have no sides; anything longer is cut by runtime.
    private var sides: [[AppTrack]] {
        guard content.usesVinyl else { return backFaceTracks.isEmpty ? [] : [backFaceTracks] }
        return vinylSides(backFaceTracks)
    }

    /// Index of the first track of the current side within the full tracklist.
    private var currentSideOffset: Int {
        guard recordSide > 0, recordSide < sides.count else { return 0 }
        return sides[0..<recordSide].reduce(0) { $0 + $1.count }
    }

    private var linerRows: [LinerRow] {
        switch content {
        case .podcasts:
            return backFaceEpisodes.enumerated().map { offset, episode in
                LinerRow(
                    id: offset,
                    number: offset + 1,
                    title: episode.title,
                    duration: episode.duration,
                    // Marks the loaded episode, not whether audio is flowing — pausing
                    // should not un-highlight the row you just picked. The disc already
                    // says whether it is turning.
                    isCurrent: musicService.isCurrentEpisode(episode),
                    download: downloadMark(for: episode),
                    episode: episode
                )
            }

        case .albums, .playlists:
            guard recordSide < sides.count else { return [] }
            let offset = currentSideOffset
            return sides[recordSide].enumerated().map { local, track in
                LinerRow(
                    id: offset + local,
                    number: offset + local + 1,
                    title: track.title,
                    duration: track.duration,
                    // Matching on identity, not bare title: two albums can share a song name.
                    isCurrent: isCurrentTrack(track)
                )
            }
        }
    }

    private func linerHeader(for index: Int) -> String {
        // A single-sided record has no side to name, so the title does the work instead.
        guard sides.count > 1 else { return content.title(at: index) }
        return "SIDE \(vinylSideLabel(recordSide))"
    }

    private func creditsLine(for index: Int) -> String {
        let artist = content.subtitle(at: index) ?? ""
        let count = backFaceTracks.count
        let total = backFaceTracks.reduce(0) { $0 + $1.duration }
        guard count > 0 else { return artist }
        let tracks = "\(count) track\(count == 1 ? "" : "s")"
        return artist.isEmpty
            ? "\(tracks) · \(gatefoldMinutes(total))"
            : "\(artist) · \(tracks) · \(gatefoldMinutes(total))"
    }

    /// The dominant colour of an item's cover, used to stock its sleeve.
    ///
    /// Apple Music artwork already carries Apple's own extracted `backgroundColor`, which is
    /// both better and free. Local-library artwork has no palette, so it gets downsampled to
    /// a single pixel instead.
    private func artworkColor(at index: Int) -> Color? {
        let thumb = CGSize(width: 32, height: 32)

        switch content {
        case .albums(let items):
            guard index < items.count else { return nil }
            if let background = items[index].musicKitAlbum?.artwork?.backgroundColor {
                return Color(cgColor: background)
            }
            guard let image = items[index].mpArtwork?.image(at: thumb) else { return nil }
            return sleeveColor(from: image)

        case .playlists(let items):
            guard index < items.count else { return nil }
            if let background = items[index].musicKitPlaylist?.artwork?.backgroundColor {
                return Color(cgColor: background)
            }
            guard let image = items[index].mpArtwork?.image(at: thumb) else { return nil }
            return sleeveColor(from: image)

        case .podcasts(let items):
            guard index < items.count,
                  let image = items[index].artwork?.image(at: thumb) else { return nil }
            return sleeveColor(from: image)
        }
    }

    private func coverAccessibilityLabel(index: Int) -> String {
        let title = content.title(at: index)
        if let subtitle = content.subtitle(at: index), !subtitle.isEmpty {
            return "\(title), \(subtitle)"
        }
        return title
    }

    // MARK: - Playback

    private func playTrack(at globalIndex: Int) {
        // Starting something new replaces Up Next: ask first if it holds songs queued by hand.
        let queueable: Bool = if case .podcasts = content { false } else { true }
        musicService.play(asking: { pendingPlay = $0 },
                          addToQueue: queueable ? { queueTrack(at: globalIndex, placement: .last) } : nil) {
            startTrack(at: globalIndex)
        }
    }

    private func startTrack(at globalIndex: Int) {
        switch content {
        case .podcasts:
            Task {
                await musicService.playPodcastEpisodes(
                    backFaceEpisodes,
                    startingAt: globalIndex,
                    podcastShowTitle: backFacePodcastShowTitle
                )
            }
        case .albums, .playlists:
            Task {
                let outcome = await musicService.play(
                    tracks: backFaceTracks,
                    startingAt: globalIndex,
                    playlistID: backFacePlaylistID
                )
                await MainActor.run { report(outcome) }
            }
        }
    }

    /// Says so when a tap could not start anything. Without this a track the player has
    /// nothing to play — catalogue content, or a cloud item that was never downloaded —
    /// is a silent dead tap, indistinguishable from a missed touch.
    private func report(_ outcome: PlaybackStartOutcome) {
        switch outcome {
        case .started:
            break
        case .trackUnavailable:
            impact(.rigid, 0.4)
            showToast(String(localized: "playback.trackUnavailable"))
        case .nothingPlayable:
            impact(.rigid, 0.4)
            showToast(String(localized: "playback.nothingPlayable"))
        }
    }

    private func downloadMark(for episode: PodcastEpisode) -> LinerDownloadMark? {
        guard episode.streamURL != nil else { return nil }
        switch downloads.state(for: episode.id) {
        case .downloading(let progress): return .downloading(progress: progress)
        case .downloaded:                return .downloaded
        case nil:                        return .available
        }
    }

    /// Downloads a streamed episode for offline listening, or undoes that.
    private func toggleDownload(at globalIndex: Int) {
        guard backFaceEpisodes.indices.contains(globalIndex) else { return }
        let episode = backFaceEpisodes[globalIndex]
        switch downloads.state(for: episode.id) {
        case nil:
            downloads.download(episode)
            impact(.light, 0.7)
            showToast(String(format: String(localized: "download.started"), episode.title))
        case .downloading:
            downloads.remove(episode.id)
            impact(.rigid, 0.4)
            showToast(String(localized: "download.cancelled"))
        case .downloaded:
            downloads.remove(episode.id)
            impact(.rigid, 0.4)
            showToast(String(format: String(localized: "download.removed"), episode.title))
        }
    }

    /// Queues the track behind a liner row, leaving playback alone.
    ///
    /// The row index is into the whole tracklist, not the visible side, so it addresses
    /// `backFaceTracks` directly — `LinerRow.id` is already offset by `currentSideOffset`.
    private func queueTrack(at globalIndex: Int, placement: QueuePlacement) {
        let track: AppTrack
        switch content {
        case .podcasts:
            // Episodes play from their show; they don't go in the queue, in any player.
            impact(.rigid, 0.4)
            showToast(String(localized: "queue.episodes"))
            return
        case .albums, .playlists:
            guard backFaceTracks.indices.contains(globalIndex) else { return }
            track = backFaceTracks[globalIndex]
        }

        Task {
            let outcome = await musicService.addToQueue(track, placement: placement)
            await MainActor.run {
                reportQueued(outcome, name: track.title, requested: 1, placement: placement,
                             isCollection: false)
            }
        }
    }

    /// The long-press menu on a closed cover.
    @ViewBuilder
    private func collectionQueueMenu(for index: Int) -> some View {
        Button {
            queueCollection(at: index, placement: .next)
        } label: {
            Label(String(localized: "queue.action.playNext"), systemImage: "text.insert")
        }
        Button {
            queueCollection(at: index, placement: .last)
        } label: {
            Label(String(localized: "queue.action.addToQueue"), systemImage: "text.append")
        }
    }

    /// Queues a whole album, playlist or podcast show from its cover, without opening
    /// the sleeve. Loads the tracks itself rather than reusing the sleeve's, which are
    /// only ever loaded for the record that is open.
    private func queueCollection(at index: Int, placement: QueuePlacement) {
        guard index < content.itemCount else { return }
        let name = content.title(at: index)
        let content = self.content
        if case .podcasts = content {
            impact(.rigid, 0.4)
            showToast(String(localized: "queue.episodes"))
            return
        }

        Task {
            let tracks: [AppTrack]
            switch content {
            case .albums(let items):
                tracks = await musicService.loadTracks(for: items[index])
            case .playlists(let items):
                tracks = await musicService.loadTracks(for: items[index])
            case .podcasts:
                tracks = []
            }
            let outcome = await musicService.addToQueue(tracks: tracks, placement: placement)
            await MainActor.run {
                reportQueued(outcome, name: name, requested: tracks.count, placement: placement,
                             isCollection: true)
            }
        }
    }

    /// Tells the user what a queue add did, in the words every player uses.
    private func reportQueued(_ outcome: QueueAddOutcome, name: String, requested: Int,
                              placement: QueuePlacement, isCollection: Bool) {
        trace("queue \(placement == .next ? "next" : "last"): \(outcome)")
        if outcome.succeeded { impact(.light, 0.7) } else { impact(.rigid, 0.4) }
        showToast(outcome.message(name: name, requested: requested, placement: placement,
                                  isCollection: isCollection))
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) { toast = message }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.25)) { toast = nil }
        }
    }

    /// The disc and the Play pill share this. If the player is already loaded with this
    /// sleeve it toggles, so a paused album resumes where it left off rather than starting
    /// over; otherwise it puts this record on.
    private func primaryAction() {
        trace("primary: isCurrentItem=\(isCurrentItem) tracks=\(backFaceTracks.count)")
        if isCurrentItem {
            Task {
                await musicService.togglePlayPause()
                await MainActor.run { trace("toggled: isPlaying=\(musicService.isPlaying)") }
            }
        } else {
            playAll(shuffled: false)
        }
    }

    private func playAll(shuffled: Bool) {
        trace("playAll: shuffled=\(shuffled) tracks=\(backFaceTracks.count) loading=\(isLoadingBackFace)")
        guard !backFaceTracks.isEmpty else {
            // Used to return silently, which made an unloaded sleeve look like a dead
            // button. Say so instead.
            trace("playAll: no tracks loaded")
            impact(.rigid, 0.4)
            showToast(String(localized: "playback.nothingPlayable"))
            return
        }
        let queue = shuffled ? backFaceTracks.shuffled() : backFaceTracks
        let name = content.title(at: selectedIndex)
        musicService.play(asking: { pendingPlay = $0 }, addToQueue: { queueAll(queue, name: name) }) {
            startAll(queue)
        }
    }

    /// The open record's songs onto the end of Up Next, in the order Play or Shuffle chose.
    private func queueAll(_ tracks: [AppTrack], name: String) {
        Task {
            let outcome = await musicService.addToQueue(tracks: tracks, placement: .last)
            await MainActor.run {
                reportQueued(outcome, name: name, requested: tracks.count, placement: .last, isCollection: true)
            }
        }
    }

    private func startAll(_ queue: [AppTrack]) {
        Task {
            let outcome = await musicService.play(tracks: queue, startingAt: 0, playlistID: backFacePlaylistID)
            await MainActor.run {
                trace("play: \(outcome)")
                report(outcome)
            }
        }
    }

    /// Records what the gatefold's actions actually did, for the UI tests.
    ///
    /// A toast lasts 1.6 s and playback outcomes arrive asynchronously, so from outside
    /// the app "nothing happened" could mean the action never fired, it bailed early, or
    /// playback was refused. This keeps the last step on screen, readable through
    /// accessibility, for as long as the test needs. It is only drawn under `--uitest`.
    private func trace(_ event: String) {
        logger.info("Gatefold: \(event)")
        guard AppEnvironment.isUITesting else { return }
        gatefoldTrace.append(event)
    }

    // MARK: - Open / Close

    /// Touch-down. Lifts the sleeve slightly and, crucially, starts the fetch here: the fold
    /// takes well over half a second, which is almost always longer than loading the tracks,
    /// so the liner is filled before anyone can read it.
    private func arm(index: Int) {
        guard !isArmed else { return }
        isArmed = true
        impact(.soft, 0.4)
        prefetch(index: index)
    }

    private func open(index: Int) {
        guard content.itemCount > 0 else { return }
        trace("open")
        momentumTask?.cancel()
        momentumTask = nil
        recordSide = 0
        prefetch(index: index)
        wasPastHalfway = false

        if reduceMotion {
            animateOpen(.easeInOut(duration: 0.2)) { isArmed = false }
            announceOpen(index: index)
            return
        }

        // Scheduled rather than observed, so the tick lands as the hinge passes 90°.
        scheduleHalfwayHaptic(after: openHalfwayDelay)

        animateOpen(openSpring) { isArmed = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + openSettleDelay) {
            guard foldProgress > 0.9 else { return }
            impact(.medium, 0.7)
            announceOpen(index: index)
        }
    }

    /// Closing is always faster than opening.
    private func close() {
        guard isOpen else { return }
        isArmed = false
        wasPastHalfway = false
        spreadSettled = false

        let animation: Animation = reduceMotion
            ? .easeInOut(duration: 0.2)
            : .spring(response: 0.34, dampingFraction: 0.86)

        // Clearing in the completion, not on a timer: a fast reopen must not show an empty
        // sleeve.
        withAnimation(animation, completionCriteria: .logicallyComplete) {
            foldProgress = 0
        } completion: {
            backFaceTracks = []
            backFaceEpisodes = []
            backFacePlaylistID = nil
            backFacePodcastShowTitle = nil
            prefetchedIndex = nil
            recordSide = 0
            impact(.soft, 0.35)
        }
    }

    private func announceOpen(index: Int) {
        let title = content.title(at: index)
        let artist = content.subtitle(at: index) ?? ""
        let count = linerRows.count
        var message = artist.isEmpty ? "\(title), open." : "\(title), by \(artist), open."
        if sides.count > 1 {
            message += " Side \(vinylSideLabel(recordSide)), \(count) tracks."
        } else if count > 0 {
            message += " \(count) tracks."
        }
        AccessibilityNotification.Announcement(message).post()
    }

    /// Fetches the tracklist without touching the animation.
    private func prefetch(index: Int) {
        guard prefetchedIndex != index else { return }
        prefetchedIndex = index
        // With artwork the interior is the photograph itself, so the type inverts to light
        // on a dark scrim. Without it there is nothing to print and we fall back to stock.
        let dominant = artworkColor(at: index)
        sleeveTheme = content.lacksArtwork(at: index)
            ? SleeveTheme.paper(dominant)
            : SleeveTheme.photographic(dominant)

        // Drop the previous sleeve's tracks up front. They decide whether this record is the
        // one playing, so leaving them in place during the fetch would spin the new disc on
        // the strength of the old album's playback.
        backFaceTracks = []
        backFaceEpisodes = []

        switch content {
        case .podcasts(let items):
            guard index < items.count else { return }
            backFaceEpisodes = items[index].episodes
            backFacePodcastShowTitle = items[index].title

        case .albums(let items):
            guard index < items.count else { return }
            isLoadingBackFace = true
            Task {
                let loaded = await musicService.loadTracks(for: items[index])
                await MainActor.run {
                    backFaceTracks = loaded
                    isLoadingBackFace = false
                }
            }

        case .playlists(let items):
            guard index < items.count else { return }
            isLoadingBackFace = true
            Task {
                let loaded = await musicService.loadTracks(for: items[index])
                await MainActor.run {
                    backFaceTracks = loaded
                    backFacePlaylistID = items[index].id
                    isLoadingBackFace = false
                }
            }
        }
    }

    // MARK: - Open Gesture

    /// Touch-down arms, release within the tap slop opens. A minimumDistance of 0 is what
    /// lets the arm animation start before the finger lifts.
    private func openGesture(index: Int) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isPressingCover) { _, isPressing, _ in isPressing = true }
            .onChanged { _ in
                guard !isOpen else { return }
                arm(index: index)
            }
            .onEnded { value in
                guard !isOpen else { return }
                let moved = hypot(value.translation.width, value.translation.height)
                if moved < 4 {
                    open(index: index)
                } else {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.90)) {
                        isArmed = false
                    }
                }
            }
    }

    // MARK: - Fold Scrubbing

    /// Drag sideways on an open panel to scrub the hinge 1:1 — one panel width is 1.0 of
    /// progress. Dragging left opens, matching the direction the cover actually swings.
    private func scrubFold(value: DragGesture.Value, panel: CGFloat) {
        if foldDragStart == nil {
            foldDragStart = foldProgress
            // Hand the picture back to the animated sleeve so the hinge can be seen
            // following the finger. The spread stays alive underneath for the gesture.
            spreadSettled = false
            foldDragIsVertical = abs(value.translation.height) > abs(value.translation.width)
        }
        guard let start = foldDragStart else { return }

        if foldDragIsVertical {
            // Swipe down closes from wherever the hinge is.
            let drop = max(0, value.translation.height)
            setFold(max(0, start - drop / panel))
            return
        }

        var next = start - value.translation.width / panel
        if next > 1 {
            // Rubber-band up to 8 pt past fully open.
            let overshoot = (next - 1) * panel
            next = 1 + min(8, overshoot * 0.55) / panel
        }
        setFold(max(0, next))
    }

    private func endFoldScrub(value: DragGesture.Value, panel: CGFloat) {
        let start = foldDragStart ?? foldProgress
        foldDragStart = nil

        if foldDragIsVertical {
            if value.translation.height > 40 || value.velocity.height > 320 {
                close()
            } else {
                reopen()
            }
            foldDragIsVertical = false
            return
        }

        // Progress per second, positive means opening.
        let velocity = -value.velocity.width / panel
        let shouldOpen: Bool

        if abs(value.velocity.width) > 320 {
            // A fast release overrides the thresholds in its own direction.
            shouldOpen = velocity > 0
        } else if foldProgress >= 0.55 {
            shouldOpen = true
        } else if foldProgress < 0.45 {
            shouldOpen = false
        } else {
            // Dead band: decide by direction of travel. A single 0.50 threshold makes a
            // hinge held near halfway chatter.
            shouldOpen = foldProgress > start
        }

        if shouldOpen {
            animateOpen(openSpring)
        } else {
            close()
        }
    }

    private func reopen() {
        animateOpen(openSpring)
    }

    /// Sets progress with no animation, firing the 90° tick on threshold *crossings* only.
    private func setFold(_ value: CGFloat) {
        withTransaction(Transaction(animation: nil)) {
            foldProgress = value
        }

        let isPast = value >= 0.5
        if isPast != wasPastHalfway {
            wasPastHalfway = isPast
            let now = Date()
            // A 120 ms floor keeps scrubbing from machine-gunning the Taptic Engine.
            if let last = lastHalfwayHaptic, now.timeIntervalSince(last) < 0.12 { return }
            lastHalfwayHaptic = now
            impact(.rigid, 0.3)
        }
    }

    private func scheduleHalfwayHaptic(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard foldProgress > 0.3, foldProgress < 0.95 || isOpen else { return }
            impact(.rigid, 0.3)
            wasPastHalfway = true
        }
    }

    // MARK: - Record Flip

    /// Swipe up on the record to turn it over.
    private var recordSwipe: some Gesture {
        DragGesture(minimumDistance: 28)
            .onEnded { value in
                guard sides.count > 1 else { return }
                guard value.translation.height < -28, value.velocity.height < -200 else { return }
                flipRecord(to: (recordSide + 1) % sides.count)
            }
    }

    /// The disc lifts, turns end over end on the X axis — the way you would actually flip a
    /// record — and drops back. The liner's rows change as it passes vertical.
    private func flipRecord(to side: Int) {
        guard !isRecordFlipping, side != recordSide, side < sides.count else { return }
        isRecordFlipping = true
        impact(.light, 0.5)

        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) { recordSide = side }
            isRecordFlipping = false
            return
        }

        withAnimation(.easeIn(duration: 0.19)) {
            recordFlipAngle = 90
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.19) {
            recordSide = side
            recordFlipAngle = -90
            withAnimation(.easeOut(duration: 0.19)) {
                recordFlipAngle = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.19) {
                isRecordFlipping = false
                impact(.soft, 0.4)
            }
        }
    }

    // MARK: - Haptics

    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, _ intensity: CGFloat) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred(intensity: intensity)
    }

    // MARK: - Momentum

    private func startMomentum(initialVelocity: CGFloat) {
        let maxIdx = CGFloat(max(0, content.itemCount - 1))
        momentumTask?.cancel()
        momentumTask = Task { @MainActor in
            var vel = initialVelocity    // items/sec; negative = swipe left = move forward
            let decay: CGFloat = 0.965  // fraction retained per frame at 60 fps
            let stopThreshold: CGFloat = 0.03
            let dt: CGFloat = 1.0 / 60.0

            while !Task.isCancelled && abs(vel) > stopThreshold {
                withTransaction(Transaction(animation: nil)) {
                    position = max(0, min(maxIdx, position - vel * dt))
                }
                vel *= decay
                try? await Task.sleep(nanoseconds: 16_666_667)
            }

            guard !Task.isCancelled else { return }

            let target = max(0, min(maxIdx, position.rounded()))
            withAnimation(.spring(response: 0.14, dampingFraction: 0.88)) {
                position = target
            }
            selectedIndex = Int(target)
        }
    }

    // MARK: - Layout Helpers

    private func visibleIndices(in containerWidth: CGFloat) -> [Int] {
        guard content.itemCount > 0 else { return [] }
        let center = centeredIndex
        let halfWidth = containerWidth / 2
        let radius: Int
        if pixelsPerItem < halfWidth {
            let extra = Int((halfWidth - pixelsPerItem) / baseSpacing + 0.5)
            radius = max(minVisibleRadius, min(maxVisibleRadius, 1 + extra))
        } else {
            radius = minVisibleRadius
        }
        let start = max(0, center - radius)
        let end = min(content.itemCount - 1, center + radius)
        return (start...end).sorted { abs(CGFloat($0) - position) > abs(CGFloat($1) - position) }
    }

    private func xOffset(for index: Int) -> CGFloat {
        let raw = CGFloat(index) - position
        guard abs(raw) > 0.0001 else { return 0 }
        let sign: CGFloat = raw < 0 ? -1 : 1
        let magnitude = abs(raw)
        if magnitude <= 1 {
            return sign * magnitude * pixelsPerItem
        } else {
            return sign * (pixelsPerItem + (magnitude - 1) * baseSpacing)
        }
    }

    private func rotationAngle(rawPosition: CGFloat) -> Double {
        let clamped = max(-1.0, min(1.0, Double(rawPosition)))
        return -clamped * sideAngle
    }

    /// Blends the carousel's own tilt away as the fold takes over, so an album opened
    /// slightly off-centre still hinges from where it actually sits.
    private func centerCardRotation(rawPosition: CGFloat, p: CGFloat) -> Double {
        Double(-rawPosition) * sideAngle * Double(1 - p)
    }

    private func coverScale(rawPosition: CGFloat) -> CGFloat {
        let m = abs(rawPosition)
        if m < 1 { return 1.0 - m * 0.13 }
        if m < 2 { return 0.87 - (m - 1) * 0.10 }
        return max(0.68, 0.77 - (m - 2) * 0.09)
    }

    private func zIndex(for index: Int) -> Double {
        Double(100 - abs(CGFloat(index) - position) * 10)
    }
}
