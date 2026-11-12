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

    /// The classic player's Discover lists Apple Music's sections (placeholders here); a
    /// section lists what's in it, and an album opens on its songs.
    @MainActor
    func testClassicDiscoverOpensASectionAndAnAlbum() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-complete-onboarding", "-LyrePlayerStyle", "classic",
                               "-DiscoverSamples", "YES", "--uitest-open-discover", "--uitest-hide-library-errors"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Made for You"].waitForExistence(timeout: 5), "Discover didn't list its sections")
        XCTAssertTrue(app.staticTexts["Genres"].exists)
        app.buttons["Select"].tap()
        XCTAssertTrue(app.staticTexts["Discover Album"].waitForExistence(timeout: 3), "The section didn't open")
        XCTAssertTrue(app.staticTexts["Discover Mix"].exists)
        app.buttons["Select"].tap()
        XCTAssertTrue(app.staticTexts["Discover Song 1"].waitForExistence(timeout: 5), "The album didn't open on its songs")
        let shot = XCTAttachment(screenshot: app.lyreScreenshot())
        shot.name = "classic-discover-album"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The main menu lists Discover.
    @MainActor
    func testClassicMainMenuListsDiscover() throws {
        let app = launch(style: "classic")
        XCTAssertTrue(app.staticTexts["Discover"].waitForExistence(timeout: 5), "The main menu has no Discover")
    }

    // MARK: - The Other Players

    /// LYRE-15
    @MainActor
    func testSpoolChangePlayerButtonSwitchesToLiquid() throws {
        // LYRE-41: Liquid opens on the section the Spool was left on (its albums), not its menu.
        try assertSwitch(from: "spool", prefix: "spool", to: "Liquid", arrivesAt: "liquid.back")
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

    /// The switch's show isn't waited on: a touch while the old player bows out brings the
    /// new one straight in, ready to use.
    @MainActor
    func testATouchDuringTheSwitchBringsTheNewPlayerInAtOnce() throws {
        let app = launch(style: "liquid")
        openSwitchMenu(in: app, prefix: "liquid")
        XCTAssertTrue(app.buttons["Gramophone"].waitForExistence(timeout: 3))
        app.buttons["Gramophone"].tap()
        // Clear of anything the Gramophone has, near the top corner.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.02)).tap()
        let settings = app.buttons["gramophone.settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 3), "The Gramophone didn't come in")
        XCTAssertTrue(settings.isHittable, "The Gramophone came in but can't be touched")
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

    /// LYRE-41: switching players picks up where the last one's browsing was left: the
    /// tape brought to the front of the Spool's rack is at the front of the Disc's shelf.
    @MainActor
    func testSwitchingPlayersKeepsTheCoverAtTheFront() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest", "--uitest-complete-onboarding", "--uitest-hide-library-errors",
            "-LyrePlayerStyle", "spool", "-LyreSpoolModel", "original", "-LyreSpoolFinish", "blue",
            "-SpoolSampleTapes", "YES", "--spool-reset-rack",
        ]
        app.launch()
        let door = app.descendants(matching: .any)["spool.door"].firstMatch
        XCTAssertTrue(door.waitForExistence(timeout: 10))
        door.tap()
        // The single stands behind the cases; its label strip brings it to the front.
        let single = app.descendants(matching: .any)["spool.tape.sample-3"].firstMatch
        XCTAssertTrue(single.waitForExistence(timeout: 5), "No single in the rack")
        sleep(1)
        single.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        let header = app.descendants(matching: .any)["spool.carousel.nowShowing"].firstMatch
        expectation(for: NSPredicate(format: "label CONTAINS 'Sample Single 3'"), evaluatedWith: header)
        waitForExpectations(timeout: 4)
        // Shut the door, and switch to the Disc.
        door.tap()
        sleep(1)
        openSwitchMenu(in: app, prefix: "spool")
        app.buttons["Disc"].tap()
        let open = app.descendants(matching: .any)["disc.open"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 10), "Didn't switch to the Disc")
        open.tap()
        let discHeader = app.descendants(matching: .any)["spool.carousel.nowShowing"].firstMatch
        XCTAssertTrue(discHeader.waitForExistence(timeout: 5), "The Disc's shelf didn't open")
        expectation(for: NSPredicate(format: "label CONTAINS 'Sample Single 3'"), evaluatedWith: discHeader)
        waitForExpectations(timeout: 4)
        let shot = XCTAttachment(screenshot: app.lyreScreenshot())
        shot.name = "lyre-41-disc-picks-up"
        shot.lifetime = .keepAlways
        add(shot)
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

    /// Change Player: its own button, or in "…" where the rail is short (the Spool's,
    /// down an iPhone Duo's status column under the Dynamic Island).
    private func openSwitchMenu(in app: XCUIApplication, prefix: String) {
        let button = app.buttons["\(prefix).playerSwitch"].firstMatch
        let more = app.descendants(matching: .any)["\(prefix).more"].firstMatch
        if !button.waitForExistence(timeout: 10), more.exists {
            more.tap()
            let item = app.buttons["Change Player"].firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 3), "… has no Change Player")
            item.tap()
            return
        }
        XCTAssertTrue(button.exists, "The \(prefix) player should have a Change Player button")
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
