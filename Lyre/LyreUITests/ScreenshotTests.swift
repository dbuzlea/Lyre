//
//  ScreenshotTests.swift
//  LyreUITests
//

import XCTest

/// The README's screenshots: each player style, and the Spool on an unfolded iPhone Duo.
///
/// Off unless asked for, so ordinary runs aren't slowed by them:
///
///     TEST_RUNNER_LYRE_SCREENSHOTS=1 xcodebuild test -only-testing:LyreUITests/ScreenshotTests …
///
/// Each screenshot is attached under the file name it goes by in `screenshots/`. They use
/// the sample tapes and records, as a simulator has no music library; the Duo one only
/// makes sense on the iPhone Duo simulator.
final class ScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LYRE_SCREENSHOTS"] == "1",
                          "Screenshots are only taken when LYRE_SCREENSHOTS=1")
    }

    // MARK: - Classic

    @MainActor
    func testClassicSearch() throws {
        let app = launch(style: "classic", extra: ["--uitest-open-search"])
        XCTAssertTrue(app.textFields["search.field"].waitForExistence(timeout: 10))
        dismissLibraryAlert(in: app)
        if !app.keyboards.firstMatch.exists { app.textFields["search.field"].tap() }
        sleep(2)
        save(app, "classic-search")
    }

    // MARK: - Spool

    @MainActor
    func testSpool() throws {
        let app = launch(style: "spool", extra: ["--spool-reset-rack"])
        let door = element(app, "spool.door")
        XCTAssertTrue(door.waitForExistence(timeout: 10))
        dismissLibraryAlert(in: app)
        sleep(1)
        save(app, "spool-deck")

        door.tap()
        XCTAssertTrue(element(app, "spool.index").waitForExistence(timeout: 5))
        sleep(2)
        save(app, "spool-rack")

        // An album's case, open on its J-card.
        element(app, "spool.tape.sample-1").tap()
        XCTAssertTrue(element(app, "spool.jcard.track.0").waitForExistence(timeout: 5))
        sleep(2)
        save(app, "spool-case")
    }

    @MainActor
    func testSpoolManual() throws {
        let app = launch(style: "spool")
        let settings = element(app, "spool.settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        dismissLibraryAlert(in: app)
        settings.tap()
        XCTAssertTrue(element(app, "spool.tour.lesson").waitForExistence(timeout: 5))
        sleep(3)
        save(app, "spool-manual")
    }

    // MARK: - Gramophone

    @MainActor
    func testGramophone() throws {
        let app = launch(style: "gramophone", extra: ["--gramophone-reset-crate"])
        let crate = element(app, "gramophone.crate")
        XCTAssertTrue(crate.waitForExistence(timeout: 10))
        dismissLibraryAlert(in: app)
        sleep(2)
        save(app, "gramophone-front")

        crate.tap()
        XCTAssertTrue(element(app, "gramophone.index").waitForExistence(timeout: 8))
        sleep(2)
        save(app, "gramophone-crate")

        // A record's sleeve, turned over on its songs.
        element(app, "gramophone.stack.sample-1").tap()
        sleep(2)
        save(app, "gramophone-sleeve")
    }

    @MainActor
    func testGramophoneTurntable() throws {
        // A shuffle of the sample records put on the turntable a moment after launch.
        let app = launch(style: "gramophone", extra: ["-GramophoneShot", "put"])
        XCTAssertTrue(element(app, "gramophone.crate").waitForExistence(timeout: 10))
        sleep(8)
        save(app, "gramophone-turntable")
    }

    @MainActor
    func testGramophoneBooklet() throws {
        let app = launch(style: "gramophone")
        let booklet = element(app, "gramophone.settings")
        XCTAssertTrue(booklet.waitForExistence(timeout: 10))
        dismissLibraryAlert(in: app)
        booklet.tap()
        XCTAssertTrue(element(app, "gramophone.tour.lesson").waitForExistence(timeout: 5))
        // Two lessons on, where the drawer is out and the index in use.
        element(app, "gramophone.tour.next").tap()
        sleep(4)
        save(app, "gramophone-booklet")
    }

    // MARK: - iPhone Duo

    /// The Spool on an unfolded iPhone Duo, with a tape waiting in the open deck. The
    /// posture is set at launch, standing in for the hinge.
    @MainActor
    func testSpoolOnAnOpenDuo() throws {
        let app = launch(style: "spool", extra: ["--spool-reset-rack", "-SpoolFoldPosture", "open"])
        XCTAssertTrue(element(app, "spool.open.hint").waitForExistence(timeout: 10))
        dismissLibraryAlert(in: app)
        sleep(1)
        save(app, "duo-spool-open")

        let single = element(app, "spool.tape.sample-3")
        XCTAssertTrue(single.waitForExistence(timeout: 5))
        single.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        sleep(1)
        single.swipeLeft()
        sleep(2)
        save(app, "duo-spool-loaded")
    }

    // MARK: - Helpers

    private func launch(style: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest", "--uitest-complete-onboarding",
            "-LyrePlayerStyle", style,
            "-SpoolSampleTapes", "YES",
            // The default designs and finishes, whatever an earlier test chose.
            "-LyreSpoolModel", "original", "-LyreSpoolFinish", "blue",
            "-LyreGramophoneModel", "horn", "-LyreGramophoneFinish", "mahogany",
        ] + extra
        app.launch()
        // The simulator's missing library is reported a few seconds after launch; wait
        // for it here, so it neither blocks a tap nor ends up in a screenshot.
        dismissLibraryAlert(in: app, waiting: 10)
        return app
    }

    /// The simulator's missing library is reported in an alert a moment after launch.
    private func dismissLibraryAlert(in app: XCUIApplication, waiting timeout: TimeInterval = 1) {
        let dismiss = app.alerts.buttons["Dismiss"]
        if dismiss.waitForExistence(timeout: timeout) {
            dismiss.tap()
            sleep(1)
        }
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func save(_ app: XCUIApplication, _ name: String) {
        dismissLibraryAlert(in: app)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
