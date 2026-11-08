//
//  LibraryAdder.swift
//  Lyre
//

import Foundation
internal import Combine
import MusicKit
import UIKit

// MARK: - Adding Songs to the Library
//
// A song Lyre streams from Apple Music that the library hasn't (a catalogue album's,
// Discover's, a search's) can be added to it from wherever it's listed, the same in every
// player: holding the song offers Add to Library (QueueMenu, Liquid's lists), and swiping
// it left reveals it (RowSwipeAction.library). Adding needs an Apple Music subscription;
// without one, Apple's trial is offered (AppleMusicCatalog.add). What happened is said in
// the player's own notice (each observes `notice`), and the library is reloaded a moment
// after, once Apple Music has it.

@MainActor
final class LibraryAdder: ObservableObject {
    static let shared = LibraryAdder()

    struct Notice: Equatable {
        let id = UUID()
        let text: String
    }

    /// The last thing to say about an add, for the player showing to put up.
    @Published private(set) var notice: Notice?
    /// The songs added this session, by store ID, so they stop offering to be.
    @Published private(set) var added: Set<String> = []

    /// For the subscription and the reload afterwards (ContentView sets it).
    weak var musicService: MusicService?

    /// Whether `track` can be added: streamed from Apple Music, not the library's, and not
    /// already added.
    func canAdd(_ track: AppTrack) -> Bool {
        guard track.isStreamOnly, let storeID = track.storeID else { return false }
        return !added.contains(storeID)
    }

    func add(_ track: AppTrack) {
        guard let storeID = track.storeID, canAdd(track) else { return }
        Task {
            do {
                let song: Song
                if let known = track.musicKitSong {
                    song = known
                } else {
                    let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(storeID))
                    guard let found = try await request.response().items.first else {
                        throw URLError(.resourceUnavailable)
                    }
                    song = found
                }
                try await AppleMusicCatalog.shared.add(song, subscribed: musicService?.subscriptionState.isSubscribed ?? false)
                added.insert(storeID)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                notice = Notice(text: String(format: String(localized: "catalog.added"), track.title))
                // The library has it once Apple Music has synced it.
                try? await Task.sleep(for: .seconds(4))
                await musicService?.refreshOnForeground()
            } catch AppleMusicCatalog.AddError.needsSubscription {
                // Apple's trial is being offered instead.
            } catch {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.4)
                notice = Notice(text: String(format: String(localized: "catalog.add.failed"), track.title))
            }
        }
    }
}
