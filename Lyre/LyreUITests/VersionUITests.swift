//
//  VersionUITests.swift
//  LyreUITests
//

import XCTest

/// Every player's settings say which version and build this is, as "Version 2.5.2 (8)",
/// read from the app's own Info.plist, so a TestFlight tester can say what they're on.
final class VersionUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testEveryPlayersSettingsShowTheVersionAndBuild() throws {
        for (style, settings) in [("spool", "spool.settings"), ("disc", "disc.settings"),
                                  ("gramophone", "gramophone.settings"), ("liquid", "liquid.settings")] {
            let app = XCUIApplication()
            app.launchArguments = ["--uitest", "--uitest-complete-onboarding", "--uitest-hide-library-errors",
                                   "-LyrePlayerStyle", style, "-LyreGramophoneModel", "horn"]
            app.launch()
            let button = app.descendants(matching: .any)[settings].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 10), "\(style) has no settings button")
            button.tap()

            let version = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Version '")).firstMatch
            for _ in 0..<12 where !(version.exists && version.isHittable) { app.swipeUp() }
            XCTAssertTrue(version.exists, "\(style)'s settings don't say the version")
            let label = version.label
            XCTAssertNotNil(label.range(of: #"^Version \d+\.\d+(\.\d+)? \(\d+\)$"#, options: .regularExpression),
                            "\(style)'s version line reads \"\(label)\"")
            print("VERSION-LINE \(style): \(label)")
            app.terminate()
        }
    }
}
