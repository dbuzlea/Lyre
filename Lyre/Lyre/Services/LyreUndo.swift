//
//  LyreUndo.swift
//  Lyre
//

import SwiftUI
import UIKit

// MARK: - Undo
//
// Things taken away in Lyre (a song swiped out of Up Next, Up Next cleared, a song out of
// a playlist, a show unsubscribed from, a download removed) can be put back: for a few
// seconds a small banner says what went, with Undo beside it; and shaking the phone, as
// anywhere in iOS, offers the same undo. Apple's guidelines: people explore more freely
// when they know a step can be taken back, and recovering shouldn't cost them their work.
//
// One undo at a time, the latest: a new one replaces the last. The banner goes after a
// few seconds (or swiped away); shaking still offers the last thing until another comes.

@Observable
@MainActor
final class LyreUndo {
    static let shared = LyreUndo()

    struct Offer: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let action: () async -> Void

        static func == (lhs: Offer, rhs: Offer) -> Bool { lhs.id == rhs.id }
    }

    /// What the banner shows now, if anything.
    private(set) var banner: Offer?
    /// Where the banner is on screen: the only place its window takes touches.
    @ObservationIgnored var bannerFrame: CGRect = .zero
    @ObservationIgnored private var window: UIWindow?
    /// The last thing that can be undone, by the banner or by a shake.
    private var latest: Offer?
    private var expiry: Task<Void, Never>?

    /// How long the banner stays.
    static let life: Duration = .seconds(6)

    /// Something's been taken away: `message` says what, and `undo` puts it back.
    func offer(_ message: String, undo: @escaping () async -> Void) {
        let offer = Offer(message: message, action: undo)
        latest = offer
        showWindow()
        withAnimation(LyreMotion.light) { banner = offer }
        if let manager = Self.undoManager {
            manager.removeAllActions(withTarget: self)
            manager.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated { target.perform(offer.id) }
            }
            manager.setActionName(message)
        }
        UIAccessibility.post(notification: .announcement,
                             argument: "\(message). \(String(localized: "undo.available"))")
        expiry?.cancel()
        expiry = Task { [weak self] in
            try? await Task.sleep(for: Self.life)
            guard !Task.isCancelled else { return }
            self?.hideBanner(offer.id)
        }
    }

    /// Puts back the latest thing taken away (or the one `id` names, if it's still the latest).
    func perform(_ id: UUID? = nil) {
        guard let offer = latest, id == nil || id == offer.id else { return }
        latest = nil
        hideBanner(offer.id)
        Self.undoManager?.removeAllActions(withTarget: self)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        Task { await offer.action() }
    }

    /// The banner put away (it stays undoable by a shake).
    func hideBanner(_ id: UUID? = nil) {
        guard let banner, id == nil || id == banner.id else { return }
        withAnimation(LyreMotion.light) { self.banner = nil }
    }

    /// The banner's own window, over the app's (sheets and covers included), passing
    /// every touch but those on the banner through to the app beneath.
    private func showWindow() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first else { return }
        if let window, window.windowScene === scene { return }
        let window = UndoWindow(windowScene: scene)
        window.windowLevel = .normal + 1
        let host = UIHostingController(rootView: UndoBanner())
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false
        self.window = window
    }

    /// The key window's undo manager, which a shake asks.
    private static var undoManager: UndoManager? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first { !($0 is UndoWindow) }?.undoManager
    }
}

/// The banner's window: touches land on it only where the banner is.
private final class UndoWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let frame = MainActor.assumeIsolated { LyreUndo.shared.banner == nil ? .zero : LyreUndo.shared.bannerFrame }
        guard frame.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }

    override var canBecomeKey: Bool { false }
}

/// The undo banner, over every player at the bottom of the screen: what went, and Undo.
/// Swiped down (or flicked), it goes; it goes by itself after a few seconds.
struct UndoBanner: View {
    @State private var undo = LyreUndo.shared
    @State private var drag: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            if let offer = undo.banner {
                HStack(spacing: 14) {
                    Text(offer.message)
                        .lyreFont(size: 15, weight: .medium, maxScale: 1.5)
                        .lineLimit(2)
                        .foregroundStyle(.white)
                    Button(String(localized: "undo.action")) { undo.perform(offer.id) }
                        .lyreFont(size: 15, weight: .bold, maxScale: 1.5)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(.white, in: Capsule())
                        .frame(minHeight: 44)
                        .buttonStyle(LyrePressStyle())
                        .accessibilityIdentifier("lyre.undo.button")
                }
                .padding(.leading, 18)
                .padding(.trailing, 8)
                .padding(.vertical, 6)
                .lyreMaterial(.ultraThinMaterial, in: Capsule(), solid: Color(white: 0.14))
                .background(Color.black.opacity(0.55), in: Capsule())
                .environment(\.colorScheme, .dark)
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { undo.bannerFrame = $0 }
                .padding(.horizontal, 20)
                .padding(.bottom, 96)
                .offset(y: max(0, drag))
                .gesture(DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        // Down follows the finger; up gives a little, rubber-banded.
                        drag = value.translation.height > 0
                            ? value.translation.height
                            : -LyreMotion.rubberBand(-value.translation.height, limit: 12)
                    }
                    .onEnded { value in
                        let flung = value.translation.height + LyreMotion.project(value.velocity.height)
                        if max(value.translation.height, flung) > 40 {
                            undo.hideBanner(offer.id)
                            drag = 0
                        } else {
                            withAnimation(LyreMotion.release(velocity: -value.velocity.height, distance: drag)) { drag = 0 }
                        }
                    })
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("lyre.undo")
                .id(offer.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

// MARK: - Up Next, Undoably

extension MusicService {
    /// Takes song `offset` out of Up Next, offering to put it back.
    @discardableResult
    func removeFromQueueOfferingUndo(at offset: Int) -> AppTrack? {
        guard upNext.indices.contains(offset) else { return nil }
        let wasQueued = isListenerQueued(upNext[offset])
        guard let removed = removeFromQueue(at: offset) else { return nil }
        LyreUndo.shared.offer(String(format: String(localized: "queue.removed"), removed.title)) { [weak self] in
            await self?.restoreToQueue(removed, at: offset, wasListenerQueued: wasQueued)
        }
        return removed
    }

    /// Empties Up Next, offering to put it all back. Returns how many songs went.
    @discardableResult
    func clearQueueOfferingUndo() -> Int {
        let before = snapshotUpNext()
        let removed = clearQueue()
        guard removed > 0 else { return 0 }
        LyreUndo.shared.offer(String(format: String(localized: "queue.cleared.count"), removed)) { [weak self] in
            await self?.restoreUpNext(before)
        }
        return removed
    }
}
