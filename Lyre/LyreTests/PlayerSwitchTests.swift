//
//  PlayerSwitchTests.swift
//  LyreTests
//
//  Changing the player from its main screen (LYRE-15): the Classic player's main menu
//  item, and the menu the other players share.
//

import Testing
import SwiftUI
@testable import Lyre

@Suite("Changing the player")
@MainActor
struct PlayerSwitchTests {

    /// LYRE-15: the Classic player's main menu has a Change Player item, and pressing it
    /// opens the list of players.
    @Test func classicMainMenuChangePlayerOpensThePlayerList() throws {
        let index = try #require(MainMenuView.items.firstIndex(of: String(localized: "menu.changePlayer")))
        #expect(ScrollWheelView.mainMenuDestination(at: index) == .playerStyleSelection)
    }

    /// LYRE-15: Change Player sits just above Settings, which is still the last item.
    @Test func settingsStaysLastJustBelowChangePlayer() {
        let items = MainMenuView.items
        #expect(items.last == String(localized: "menu.settings"))
        #expect(items[items.count - 2] == String(localized: "menu.changePlayer"))
        #expect(ScrollWheelView.mainMenuDestination(at: items.count - 1) == .settings)
    }

    /// Every main menu row leads somewhere, and nothing past the last one does: the menu's
    /// list and the wheel's routing change together.
    @Test func everyMainMenuRowHasADestination() {
        for index in MainMenuView.items.indices {
            #expect(ScrollWheelView.mainMenuDestination(at: index) != nil, "Row \(index) leads nowhere")
        }
        #expect(ScrollWheelView.mainMenuDestination(at: MainMenuView.items.count) == nil)
        #expect(ScrollWheelView.mainMenuDestination(at: -1) == nil)
    }

    /// The menu beside the other players' Settings button offers every player.
    @Test func switchMenuOffersEveryPlayer() {
        #expect(PlayerStyle.allCases == [.classic, .spool, .gramophone, .disc, .liquid])
        #expect(PlayerSwitchMenu<EmptyView>.symbol == "rectangle.2.swap")
    }
}
