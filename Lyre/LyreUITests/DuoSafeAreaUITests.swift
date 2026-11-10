//
//  DuoSafeAreaUITests.swift
//  LyreUITests
//

import XCTest

/// An iPhone Duo closed (or held open as a book) has its status bar and front camera
/// down the right edge, where other iPhones have them across the top. There, each
/// player's header buttons stand in that column, under the status bar, where a thumb
/// reaches them (SideRail); everything else keeps out of it.
///
/// The column is measured from the window's safe area as Lyre sees it, so the tests
/// hold on a simulator's Duo and a real one alike, whatever their sizes.
final class DuoSafeAreaUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSpoolsKeysStandInTheStatusColumn() throws {
        try assertSides(style: "spool", inColumn: ["spool.settings", "spool.playerSwitch", "spool.airplay"])
    }

    @MainActor
    func testTheSlimSpoolsOptionsStandInTheStatusColumn() throws {
        try assertSides(style: "spool", extra: ["-LyreSpoolModel", "slim"],
                        inColumn: ["spool.settings", "spool.playerSwitch", "spool.airplay"])
    }

    @MainActor
    func testGramophonesButtonsStandInTheStatusColumn() throws {
        try assertSides(style: "gramophone", inColumn: ["gramophone.settings", "gramophone.playerSwitch", "gramophone.airplay"])
    }

    @MainActor
    func testDiscsButtonsStandInTheStatusColumn() throws {
        try assertSides(style: "disc", inColumn: ["disc.settings", "disc.playerSwitch", "disc.airplay"])
    }

    /// The library's lava lamp, with nothing playing: its buttons in the column, its
    /// blobs clear of it.
    @MainActor
    func testLiquidsLibraryButtonsStandInTheStatusColumn() throws {
        try assertSides(style: "liquid", inColumn: ["liquid.settings", "liquid.playerSwitch"],
                        clear: ["liquid.menu.artists"])
    }

    /// Now Playing, with a song up.
    @MainActor
    func testLiquidsNowPlayingButtonsStandInTheStatusColumn() throws {
        try assertSides(style: "liquid", extra: ["--spool-sample-queue", "-LiquidShot", "nowPlaying"],
                        inColumn: ["liquid.settings", "liquid.playerSwitch", "liquid.airplay", "liquid.library"])
    }

    // MARK: - Helpers

    private func assertSides(style: String, extra: [String] = [], inColumn: [String], clear: [String] = []) throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest", "--uitest-complete-onboarding", "--uitest-hide-library-errors",
            "-LyrePlayerStyle", style, "-SpoolSampleTapes", "YES",
            "-LyreSpoolModel", "original", "-LyreGramophoneModel", "horn",
        ] + extra
        app.launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        guard let column = app.lyreSideStatusColumn else {
            throw XCTSkip("This phone keeps its status bar across the top, not down the side")
        }
        let edge = window.frame.maxX - column
        for id in inColumn {
            let element = app.descendants(matching: .any)[id].firstMatch
            XCTAssertTrue(element.waitForExistence(timeout: 10), "\(id) is missing")
            // In the column, and below the clock and battery at its top.
            XCTAssertGreaterThanOrEqual(element.frame.minX, edge - 20,
                                        "\(id) isn't in the status column (\(element.frame), column from \(edge))")
            XCTAssertLessThanOrEqual(element.frame.maxX, window.frame.maxX + 1, "\(id) runs off the screen")
            XCTAssertGreaterThanOrEqual(element.frame.minY, window.frame.minY + 140,
                                        "\(id) is under the status bar (\(element.frame))")
        }
        for id in clear {
            let element = app.descendants(matching: .any)[id].firstMatch
            XCTAssertTrue(element.waitForExistence(timeout: 10), "\(id) is missing")
            XCTAssertLessThanOrEqual(element.frame.maxX, edge,
                                     "\(id) reaches under the status bar (\(element.frame), edge \(edge))")
        }
        let attachment = XCTAttachment(screenshot: app.lyreScreenshot())
        attachment.name = "duo-closed-\(style)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
