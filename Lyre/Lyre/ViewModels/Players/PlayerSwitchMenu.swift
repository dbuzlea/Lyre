//
//  PlayerSwitchMenu.swift
//  Lyre
//

import SwiftUI

// MARK: - Player Switch Menu
//
// The button beside each player's Settings button that changes the player without going
// into Settings: a menu of the five, the one on screen ticked. Choosing one sets
// `ThemeSettings.playerStyle`, so `PlayerSwitchStage` plays the same switch it does when
// the style is changed from Settings.
//
// Each player dresses the button like the Settings button next to it, so the menu takes
// its label from the player, given the symbol to draw. The Classic player has no button
// for it; its main menu has a Change Player item instead (see `MainMenuView`).

struct PlayerSwitchMenu<Label: View>: View {
    let themeSettings: ThemeSettings
    /// The player's own prefix, as on its other buttons: `spool.playerSwitch` and so on.
    let identifier: String
    @ViewBuilder let label: (_ symbol: String) -> Label

    /// Two cards trading places.
    static var symbol: String { "rectangle.2.swap" }

    var body: some View {
        Menu {
            Picker(String(localized: "playerSwitch.title"), selection: style) {
                ForEach(PlayerStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
        } label: {
            label(Self.symbol)
        }
        .accessibilityLabel(String(localized: "playerSwitch.title"))
        .accessibilityValue(themeSettings.playerStyle.displayName)
        .accessibilityIdentifier(identifier)
    }

    private var style: Binding<PlayerStyle> {
        Binding(get: { themeSettings.playerStyle },
                set: { themeSettings.playerStyle = $0 })
    }
}
