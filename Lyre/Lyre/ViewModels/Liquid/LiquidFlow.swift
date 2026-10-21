//
//  LiquidFlow.swift
//  Lyre
//

import SwiftUI
import UIKit

// MARK: - Liquid Flow
//
// Every change of view in the Liquid player is the same movement: the colour of where
// you're going floods out from where you touched until it covers the screen, the new
// view is put under it, and the colour clears. Now Playing and the library, a word in the
// menu and its list, a cover and its album, Back, Up Next rising and falling: all of them.
//
// LiquidPlayerView owns the flood and hands it down as `liquidFlood`; the library turns
// its pushes and pops into floods through `liquidNavigator`. Where the touch was comes
// from `LiquidTouchTracker`, which watches the window without taking any touch from
// what's under it, so a button, a list row or a cover needs nothing of its own.

/// Floods the screen with `color` from `origin` (a point on the screen, or else the last
/// touch), makes `change` under it, then lets it clear.
struct LiquidFloodAction {
    var run: (Color, CGPoint?, @escaping () -> Void) -> Void = { _, _, change in change() }

    func callAsFunction(_ color: Color, from origin: CGPoint? = nil, then change: @escaping () -> Void) {
        run(color, origin, change)
    }
}

/// Moves through the library's pages, each move a flood, and the few things any page
/// can ask of the library: queueing a whole album, and finding shows.
struct LiquidNavigator {
    var push: (LiquidRoute) -> Void = { _ in }
    var back: () -> Void = {}
    var queueAlbum: (AppAlbum, QueuePlacement) -> Void = { _, _ in }
    var findShows: () -> Void = {}
    /// Plays `tracks` of an album from `index`; true when the whole of it was asked for.
    var play: (AppAlbum, [AppTrack], Int, Bool) -> Void = { _, _, _, _ in }
    /// Plays a list of songs from `index`, named for what queueing it instead says.
    var playSongs: ([AppTrack], Int, Bool, String) -> Void = { _, _, _, _ in }
    var queue: ([AppTrack], QueuePlacement, String) -> Void = { _, _, _ in }
    /// An album's songs, as its page lists them.
    var loadTracks: (AppAlbum) async -> [AppTrack] = { _ in [] }
    /// The album a song is on, when the library has it.
    var album: (AppTrack) -> AppAlbum? = { _ in nil }
}

/// How Liquid's lists are laid out: everything at once (a grid of covers, or a list of
/// songs), or one cover at a time in a stack to flip through. Kept, for every list.
enum LiquidLayout: String {
    case grid
    case stack
}

/// Whether a card is swung open over the library, which the droplet stays out of the way
/// of.
@Observable @MainActor
final class LiquidFoldState {
    static let shared = LiquidFoldState()
    /// Open, or opening: the droplet steps aside.
    var isOpen = false
    /// The cover swung open, and where on screen it was before (global): drawn over the
    /// whole library, not just the page it came from.
    var item: LiquidStackItem?
    var frame: CGRect = .zero
}

extension EnvironmentValues {
    @Entry var liquidFlood = LiquidFloodAction()
    @Entry var liquidNavigator = LiquidNavigator()
    /// The list a page shows (albums, songs, one artist's…), which its layout and the
    /// cover its stack was left on are kept under.
    @Entry var liquidListKey = ""

}

/// The colour of the library's ground: what a flood into a plain page fills with.
extension Color {
    static let liquidGround = Color(red: 0.063, green: 0.063, blue: 0.071)
}

// MARK: - Touch Tracker

/// Remembers where the last touch on the window landed, in window coordinates, without
/// taking part in any gesture.
@MainActor
final class LiquidTouchTracker {
    static let shared = LiquidTouchTracker()
    var lastTouch: CGPoint?
    /// When the screen was last touched, for what waits for it to be left alone.
    var lastTouchTime = Date()
}

/// Installs the tracker's recogniser on the window it's placed in.
struct LiquidTouchTrackerView: UIViewRepresentable {
    func makeUIView(context: Context) -> TrackerHostView { TrackerHostView() }
    func updateUIView(_ uiView: TrackerHostView, context: Context) {}

    final class TrackerHostView: UIView {
        private var recognizer: TouchRecorder?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, recognizer == nil else { return }
            let recognizer = TouchRecorder()
            window.addGestureRecognizer(recognizer)
            self.recognizer = recognizer
        }

        override func removeFromSuperview() {
            if let recognizer { recognizer.view?.removeGestureRecognizer(recognizer) }
            recognizer = nil
            super.removeFromSuperview()
        }

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    }

    /// Notes each touch as it begins and then fails at once, so it never recognises,
    /// delays or cancels anything.
    final class TouchRecorder: UIGestureRecognizer, UIGestureRecognizerDelegate {
        init() {
            super.init(target: nil, action: nil)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
            delegate = self
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            if let touch = touches.first, let view {
                let point = touch.location(in: view)
                MainActor.assumeIsolated {
                    LiquidTouchTracker.shared.lastTouch = point
                    LiquidTouchTracker.shared.lastTouchTime = Date()
                }
            }
            state = .failed
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

// MARK: - Where Liquid Is

/// Which part of the library Liquid is showing, for the Artwork Carousel to open on when
/// the phone turns sideways, as the Classic player's does from its own lists. Kept up to
/// date by LiquidPlayerView; read by LyreView.
@MainActor
final class LiquidLocation {
    static let shared = LiquidLocation()

    enum Shelf { case albums, playlists, podcasts }

    /// The shelf of the page showing; nil on Now Playing, the menu and search, where the
    /// carousel opens on what's playing instead.
    private(set) var shelf: Shelf?
    /// The album, playlist or show open, for the carousel to turn to.
    private(set) var album: AppAlbum?

    func update(screenIsLibrary: Bool, path: [LiquidRoute]) {
        guard screenIsLibrary, let top = path.last else {
            shelf = nil
            album = nil
            return
        }
        switch top {
        case .albums, .artist, .songs, .recentlyAdded, .recentlyPlayed, .artists:
            shelf = .albums
            album = nil
        case .playlists:
            shelf = .playlists
            album = nil
        case .podcasts:
            shelf = .podcasts
            album = nil
        case .album(let opened):
            shelf = opened.isPodcast ? .podcasts : opened.isMixtape ? .playlists : .albums
            album = opened
        case .search:
            shelf = nil
            album = nil
        }
    }
}
