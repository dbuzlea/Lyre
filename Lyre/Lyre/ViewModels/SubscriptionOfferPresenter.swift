//
//  SubscriptionOfferPresenter.swift
//  Lyre
//

import SwiftUI
import MusicKit

// MARK: - Subscription Offer
//
// Apple Music's own trial offer, shown at the moment it's wanted: when someone without
// a subscription picks a song or album only Apple Music has, to play it or add it. The
// sheet is Apple's (`musicSubscriptionOffer`), told what was picked so it can show it,
// and only offered to someone Apple says can subscribe. Onboarding offers it too.

@MainActor
@Observable
final class SubscriptionOffer {
    static let shared = SubscriptionOffer()

    var isPresented = false
    private(set) var options = MusicSubscriptionOffer.Options.default

    /// Offers a trial for `itemID` (an Apple Music ID), to `play` it or to add it.
    func offer(itemID: String?, toPlay play: Bool = true) {
        Task {
            guard !AppEnvironment.isUITesting,
                  (try? await MusicSubscription.current)?.canBecomeSubscriber == true else { return }
            options = MusicSubscriptionOffer.Options(messageIdentifier: play ? .playMusic : .addMusic,
                                                    itemID: itemID.map { MusicItemID($0) })
            isPresented = true
        }
    }
}

/// Shows the offer whenever SubscriptionOffer asks, over whatever's on screen.
struct SubscriptionOfferPresenter: ViewModifier {
    func body(content: Content) -> some View {
        content.musicSubscriptionOffer(isPresented: Binding(get: { SubscriptionOffer.shared.isPresented },
                                                            set: { SubscriptionOffer.shared.isPresented = $0 }),
                                       options: SubscriptionOffer.shared.options)
    }
}
