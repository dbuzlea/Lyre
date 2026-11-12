//
//  DynamicTypeUITests.swift
//  LyreUITests
//

import XCTest

/// Every player read at a large accessibility text size (Dynamic Type): its type grows
/// (LyreType), and what it's played with stays on screen and in reach. The screenshots
/// are looked at by eye, for words cut off or run into each other.
final class DynamicTypeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    func testLiquidAtALargeTextSize() throws {
        let app = launch(style: "liquid", extra: ["-LiquidShot", "songs"])
        XCTAssertTrue(element(app, "liquid.songs.track.0").waitForExistence(timeout: 10), "No songs")
        assertInReach(app, ["liquid.songs.play", "liquid.songs.shuffle", "liquid.search.field"])
        shot(app, "type-liquid-songs")
        app.terminate()

        let album = launch(style: "liquid", extra: ["-LiquidShot", "album"])
        XCTAssertTrue(element(album, "liquid.album.play").waitForExistence(timeout: 10), "No album page")
        assertInReach(album, ["liquid.album.play", "liquid.album.shuffle"])
        shot(album, "type-liquid-album")
    }

    @MainActor
    func testSpoolAtALargeTextSize() throws {
        let app = launch(style: "spool")
        XCTAssertTrue(element(app, "spool.door").waitForExistence(timeout: 10))
        shot(app, "type-spool")
        let settings = element(app, "spool.settings")
        if settings.exists { settings.tap() } else {
            element(app, "spool.more").tap()
            app.buttons["Settings"].firstMatch.tap()
        }
        XCTAssertTrue(element(app, "spool.settings.done").waitForExistence(timeout: 5), "Settings didn't open")
        assertInReach(app, ["spool.settings.done"])
        shot(app, "type-spool-settings")
    }

    @MainActor
    func testDiscAtALargeTextSize() throws {
        let app = launch(style: "disc")
        let open = element(app, "disc.open")
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        shot(app, "type-disc")
        open.tap()
        XCTAssertTrue(element(app, "shelf.search.field").waitForExistence(timeout: 5), "The shelf didn't open")
        shot(app, "type-disc-shelf")
        app.terminate()

        let again = launch(style: "disc")
        let settings = element(again, "disc.settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(element(again, "disc.settings.done").waitForExistence(timeout: 5), "Settings didn't open")
        assertInReach(again, ["disc.settings.done"])
        shot(again, "type-disc-settings")
    }

    @MainActor
    func testGramophoneAtALargeTextSize() throws {
        let app = launch(style: "gramophone")
        let settings = element(app, "gramophone.settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        shot(app, "type-gramophone")
        settings.tap()
        XCTAssertTrue(element(app, "gramophone.settings.done").waitForExistence(timeout: 5), "Settings didn't open")
        assertInReach(app, ["gramophone.settings.done"])
        shot(app, "type-gramophone-settings")
    }

    @MainActor
    func testClassicAtALargeTextSize() throws {
        let app = launch(style: "classic")
        XCTAssertTrue(app.descendants(matching: .any)["Scroll wheel"].firstMatch.waitForExistence(timeout: 10))
        sleep(1)
        shot(app, "type-classic")
    }

    // MARK: - Helpers

    private func launch(style: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest", "--uitest-complete-onboarding", "--uitest-hide-library-errors",
            "-LyrePlayerStyle", style, "-SpoolSampleTapes", "YES", "--spool-sample-queue", "--spool-reset-rack",
            "-LyreSpoolModel", "original", "-LyreGramophoneModel", "horn",
            // Accessibility Large: the largest but one.
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL",
        ] + extra
        app.launch()
        let dismiss = app.alerts.buttons["Dismiss"]
        if dismiss.waitForExistence(timeout: 4) { dismiss.tap() }
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func assertInReach(_ app: XCUIApplication, _ ids: [String], file: StaticString = #filePath, line: UInt = #line) {
        let screen = app.windows.firstMatch.frame
        for id in ids {
            let found = element(app, id)
            XCTAssertTrue(found.exists, "\(id) is missing", file: file, line: line)
            XCTAssertTrue(screen.contains(CGPoint(x: found.frame.midX, y: found.frame.midY)),
                          "\(id) is off the screen (\(found.frame))", file: file, line: line)
        }
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        sleep(1)
        let attachment = XCTAttachment(screenshot: app.lyreScreenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
