//
//  DuoSafeAreaUITests.swift
//  LyreUITests
//

import XCTest

/// An iPhone Duo closed has its status bar and front camera down the right edge, a
/// column 84 points wide, where other iPhones have them across the top. Each player's
/// controls must keep out of it: the players draw edge to edge and place their own
/// controls, so nothing does it for them.
final class DuoSafeAreaUITests: XCTestCase {

    /// The closed Duo's window, and the column its status bar and camera take.
    private static let closedDuoWidth: CGFloat = 466
    private static let statusColumn: CGFloat = 84

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSpoolsControlsKeepOutOfTheStatusColumn() throws {
        try assertClear(style: "spool", ids: ["spool.settings", "spool.playerSwitch", "spool.airplay"])
    }

    @MainActor
    func testTheSlimSpoolsControlsKeepOutOfTheStatusColumn() throws {
        try assertClear(style: "spool", extra: ["-LyreSpoolModel", "slim"],
                        ids: ["spool.settings", "spool.playerSwitch", "spool.airplay"])
    }

    @MainActor
    func testGramophonesControlsKeepOutOfTheStatusColumn() throws {
        try assertClear(style: "gramophone", ids: ["gramophone.settings", "gramophone.playerSwitch", "gramophone.airplay"])
    }

    @MainActor
    func testDiscsControlsKeepOutOfTheStatusColumn() throws {
        try assertClear(style: "disc", ids: ["disc.settings", "disc.playerSwitch", "disc.airplay"])
    }

    /// The library's lava lamp, with nothing playing.
    @MainActor
    func testLiquidsLibraryKeepsOutOfTheStatusColumn() throws {
        try assertClear(style: "liquid", ids: ["liquid.settings", "liquid.playerSwitch", "liquid.menu.artists"])
    }

    /// Now Playing, with a song up.
    @MainActor
    func testLiquidsNowPlayingKeepsOutOfTheStatusColumn() throws {
        try assertClear(style: "liquid", extra: ["--spool-sample-queue", "-LiquidShot", "nowPlaying"],
                        ids: ["liquid.settings", "liquid.playerSwitch", "liquid.airplay"])
    }

    // MARK: - Helpers

    private func assertClear(style: String, extra: [String] = [], ids: [String]) throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest", "--uitest-complete-onboarding", "--uitest-hide-library-errors",
            "-LyrePlayerStyle", style, "-SpoolSampleTapes", "YES",
            "-LyreSpoolModel", "original", "-LyreGramophoneModel", "horn",
        ] + extra
        app.launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        guard window.frame.width == Self.closedDuoWidth else {
            throw XCTSkip("Only an iPhone Duo closed has its status bar down the side")
        }
        let edge = window.frame.maxX - Self.statusColumn
        for id in ids {
            let element = app.descendants(matching: .any)[id].firstMatch
            XCTAssertTrue(element.waitForExistence(timeout: 10), "\(id) is missing")
            XCTAssertLessThanOrEqual(element.frame.maxX, edge,
                                     "\(id) reaches under the status bar (\(element.frame), edge \(edge))")
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "duo-closed-\(style)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
