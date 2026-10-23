//
//  PlayerSwitchUITests.swift
//  LyreUITests
//

import XCTest

/// LYRE-15: every player can be changed from its main screen, without going into
/// Settings. Spool, Gramophone, Disc and Liquid have a Change Player button beside their
/// Settings button, a menu of the five; the Classic player has a Change Player item in
/// its main menu.
final class PlayerSwitchUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Classic

    /// LYRE-15: the main menu lists Change Player, just above Settings. (Where pressing it
    /// leads is checked in `PlayerSwitchTests`: XCUITest can't step the wheel one row at a
    /// time on iOS.)
    @MainActor
    func testClassicMainMenuListsChangePlayerAboveSettings() throws {
        let app = launch(style: "classic")
        XCTAssertTrue(app.descendants(matching: .any)["Scroll wheel"].firstMatch.waitForExistence(timeout: 5))
        let changePlayer = app.staticTexts["Change Player"]
        let settings = app.staticTexts["Settings"]
        XCTAssertTrue(changePlayer.waitForExistence(timeout: 3), "The main menu should list Change Player")
        XCTAssertTrue(settings.exists)
        XCTAssertLessThan(changePlayer.frame.minY, settings.frame.minY,
                          "Change Player should come just above Settings")
    }

    // MARK: - The Other Players

    /// LYRE-15
    @MainActor
    func testSpoolChangePlayerButtonSwitchesToLiquid() throws {
        try assertSwitch(from: "spool", prefix: "spool", to: "Liquid", arrivesAt: "liquid.settings")
    }

    /// LYRE-15
    @MainActor
    func testGramophoneChangePlayerButtonSwitchesToDisc() throws {
        try assertSwitch(from: "gramophone", prefix: "gramophone", to: "Disc", arrivesAt: "disc.settings")
    }

    /// LYRE-15
    @MainActor
    func testDiscChangePlayerButtonSwitchesToSpool() throws {
        try assertSwitch(from: "disc", prefix: "disc", to: "Spool", arrivesAt: "spool.settings")
    }

    /// LYRE-15
    @MainActor
    func testLiquidChangePlayerButtonSwitchesToGramophone() throws {
        try assertSwitch(from: "liquid", prefix: "liquid", to: "Gramophone", arrivesAt: "gramophone.settings")
    }

    /// LYRE-15: switching back to the Classic player from a button.
    @MainActor
    func testDiscChangePlayerButtonSwitchesToClassic() throws {
        let app = launch(style: "disc")
        openSwitchMenu(in: app, prefix: "disc")
        app.buttons["Classic"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["Scroll wheel"].firstMatch.waitForExistence(timeout: 10),
                      "Choosing Classic should bring back the click wheel")
    }

    // MARK: - Helpers

    /// Opens `prefix`'s Change Player menu, checks it lists all five players, chooses
    /// `target`, and waits for the button the new player is known by.
    private func assertSwitch(from style: String, prefix: String, to target: String,
                              arrivesAt identifier: String) throws {
        let app = launch(style: style)
        openSwitchMenu(in: app, prefix: prefix)
        for name in ["Classic", "Spool", "Gramophone", "Disc", "Liquid"] {
            XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 3),
                          "The \(style) player's Change Player menu should list \(name)")
        }
        app.buttons[target].tap()
        XCTAssertTrue(app.buttons[identifier].firstMatch.waitForExistence(timeout: 10),
                      "Choosing \(target) from the \(style) player should switch to it")
    }

    private func openSwitchMenu(in app: XCUIApplication, prefix: String) {
        let button = app.buttons["\(prefix).playerSwitch"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10),
                      "The \(prefix) player should have a Change Player button")
        button.tap()
    }

    private func launch(style: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest", "--uitest-complete-onboarding",
            "-LyrePlayerStyle", style,
            // The default designs and finishes, whatever an earlier test chose.
            "-LyreSpoolModel", "original", "-LyreSpoolFinish", "blue",
            "-LyreGramophoneModel", "horn", "-LyreGramophoneFinish", "mahogany",
            "--uitest-hide-library-errors",
        ]
        app.launch()
        return app
    }
}
