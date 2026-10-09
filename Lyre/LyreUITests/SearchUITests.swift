//
//  SearchUITests.swift
//  LyreUITests
//

import XCTest

/// Library search in each player style: typing on the keyboard, the classic player's
/// click wheel going out of view while the keyboard is up and coming back after, and the
/// Spool's rack narrowing to the tapes that match.
final class SearchUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Classic

    @MainActor
    func testClassicSearchLowersTheWheelWhileTypingAndBringsItBack() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-complete-onboarding", "-LyrePlayerStyle", "classic",
                               "--uitest-open-search"]
        app.launch()

        let wheel = app.descendants(matching: .any)["Scroll wheel"].firstMatch

        let field = app.textFields["search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 3), "Search screen did not open")
        dismissLibraryAlert(in: app)
        if !app.keyboards.firstMatch.exists { field.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "Keyboard did not come up on Search")
        XCTAssertTrue(wait(for: wheel, hittable: false), "Wheel stayed in view with the keyboard up")
        attach(app, named: "classic-typing")

        field.typeText("zzzz")
        XCTAssertTrue(app.staticTexts["No Results"].waitForExistence(timeout: 3))

        // Return is the keyboard's Search key, with or without the on-screen keyboard.
        field.typeText("\n")
        XCTAssertTrue(waitForDisappearance(of: app.keyboards.firstMatch, timeout: 3), "Keyboard did not go away")
        dismissLibraryAlert(in: app)
        XCTAssertTrue(wait(for: wheel, hittable: true), "Wheel did not come back after the keyboard went")
        attach(app, named: "classic-done-typing")

        // Tapping the field types again, and the wheel goes again.
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(wait(for: wheel, hittable: false))
    }

    // MARK: - Spool

    @MainActor
    func testSpoolSearchNarrowsTheRack() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest", "--uitest-complete-onboarding",
            "-LyrePlayerStyle", "spool",
            "-SpoolSampleTapes", "YES",
            "-LyreSpoolModel", "original",
            "--spool-reset-rack",
        ]
        app.launch()

        let door = app.descendants(matching: .any)["spool.door"].firstMatch
        XCTAssertTrue(door.waitForExistence(timeout: 10), "Spool door never appeared")
        door.tap()

        let field = app.textFields["shelf.search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 3), "Rack opened without a search field")
        dismissLibraryAlert(in: app)
        field.tap()
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: field)
        XCTAssertEqual(XCTWaiter().wait(for: [focused], timeout: 3), .completed, "Tapping the search field didn't focus it")
        field.typeText("Sample EP")

        // Only the EP is left, so it's at the front, and the other tapes are gone.
        let front = app.descendants(matching: .any)["spool.carousel.nowShowing"].firstMatch
        let showsEP = NSPredicate(format: "label CONTAINS 'Sample EP 5'")
        expectation(for: showsEP, evaluatedWith: front)
        waitForExpectations(timeout: 3)
        XCTAssertFalse(app.descendants(matching: .any)["spool.tape.sample-1"].exists)
        attach(app, named: "spool-search")

        field.typeText("\n")
        dismissLibraryAlert(in: app)
        app.buttons["Clear Search"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["spool.tape.sample-1"].waitForExistence(timeout: 3),
                      "Clearing the search did not put the rack back")
    }

    // MARK: - Gramophone

    @MainActor
    func testGramophoneSearchFieldBringsUpTheKeyboard() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest", "--uitest-complete-onboarding",
            "-LyrePlayerStyle", "gramophone",
            "-SpoolSampleTapes", "YES",
            "--gramophone-reset-crate",
        ]
        app.launch()
        dismissLibraryAlert(in: app)

        let crate = app.descendants(matching: .any)["gramophone.crate"].firstMatch
        XCTAssertTrue(crate.waitForExistence(timeout: 10), "Drawer never appeared")
        crate.tap()

        let field = app.textFields["shelf.search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Crate opened without a search field")
        dismissLibraryAlert(in: app)
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "Tapping the search field brought up no keyboard")
        attach(app, named: "gramophone-typing")

        field.typeText("Sample EP")
        let front = app.descendants(matching: .any)["gramophone.stack.nowShowing"].firstMatch
        expectation(for: NSPredicate(format: "label CONTAINS 'Sample EP 5'"), evaluatedWith: front)
        waitForExpectations(timeout: 3)
    }

    // MARK: - Helpers

    /// The simulator has no music library, which the app reports in an alert that can
    /// arrive at any point and covers the wheel.
    private func dismissLibraryAlert(in app: XCUIApplication) {
        let alert = app.alerts.firstMatch
        if alert.waitForExistence(timeout: 4) { alert.buttons["Dismiss"].tap() }
    }

    /// Waits for the wheel to be out of reach (lowered away) or back within it.
    private func wait(for element: XCUIElement, hittable: Bool) -> Bool {
        let state = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == %@", NSNumber(value: hittable)),
                                              object: element)
        return XCTWaiter().wait(for: [state], timeout: 3) == .completed
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    private func attach(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
