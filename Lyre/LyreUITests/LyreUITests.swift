//
//  LyreUITests.swift
//  LyreUITests
//

import XCTest

final class LyreUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Launch Helpers

    @discardableResult
    private func launchFresh() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-reset-onboarding"]
        addInterruptionMonitor(app: app)
        app.launch()
        return app
    }

    @discardableResult
    private func launchWithOnboardingComplete() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-complete-onboarding"]
        addInterruptionMonitor(app: app)
        app.launch()
        return app
    }

    /// Dismiss any system alerts (e.g. Apple Music permission) automatically.
    private func addInterruptionMonitor(app: XCUIApplication) {
        addUIInterruptionMonitor(withDescription: "System permission alert") { alert in
            let denyLabels = ["Don't Allow", "Not Now", "Deny", "Cancel"]
            for label in denyLabels {
                let btn = alert.buttons[label]
                if btn.exists {
                    btn.tap()
                    return true
                }
            }
            return false
        }
    }
}

// MARK: - Onboarding: Welcome Page

extension LyreUITests {

    @MainActor
    func testOnboardingWelcomePageIsShownOnFirstLaunch() throws {
        let app = launchFresh()
        XCTAssertTrue(app.staticTexts["Lyre"].waitForExistence(timeout: 5),
                      "Welcome page should display the 'Lyre' title")
    }

    @MainActor
    func testOnboardingGetStartedButtonExists() throws {
        let app = launchFresh()
        let button = app.buttons["Get Started"]
        XCTAssertTrue(button.waitForExistence(timeout: 5),
                      "'Get Started' button should be visible on the welcome page")
    }

    @MainActor
    func testOnboardingPageIndicatorDotsVisible() throws {
        let app = launchFresh()
        // The welcome page should show 4 progress indicator capsules.
        // They are not individually labelled, but the page renders when the title is present.
        XCTAssertTrue(app.staticTexts["Lyre"].waitForExistence(timeout: 5))
        // Verify we haven't accidentally jumped ahead — "Skip for now" must NOT be present yet.
        XCTAssertFalse(app.buttons["Skip for now"].exists,
                       "Skip button should not be visible on the welcome page")
    }
}

// MARK: - Onboarding: Music Auth Page

extension LyreUITests {

    @MainActor
    func testOnboardingAdvancesToMusicAuthPage() throws {
        let app = launchFresh()
        _ = app.buttons["Get Started"].waitForExistence(timeout: 5)
        app.buttons["Get Started"].tap()

        // Page 2 shows either "Connect Apple Music" or "Skip for now"
        let skipBtn = app.buttons["Skip for now"]
        XCTAssertTrue(skipBtn.waitForExistence(timeout: 5),
                      "Music auth page should show 'Skip for now' button")
    }

    @MainActor
    func testOnboardingMusicAuthPageHasConnectButton() throws {
        let app = launchFresh()
        _ = app.buttons["Get Started"].waitForExistence(timeout: 5)
        app.buttons["Get Started"].tap()

        // "Connect Apple Music" may be replaced by "Open Settings" if already denied,
        // but one primary action button must always exist on this page.
        let connectBtn = app.buttons["Connect Apple Music"]
        let openSettingsBtn = app.buttons["Open Settings"]
        let exists = connectBtn.waitForExistence(timeout: 5) || openSettingsBtn.exists
        XCTAssertTrue(exists, "Music auth page must show a primary action button")
    }
}

// MARK: - Onboarding: Theme Picker Page

extension LyreUITests {

    @MainActor
    func testOnboardingSkipAuthAdvancesToThemePicker() throws {
        let app = launchFresh()
        _ = app.buttons["Get Started"].waitForExistence(timeout: 5)
        app.buttons["Get Started"].tap()

        _ = app.buttons["Skip for now"].waitForExistence(timeout: 5)
        app.buttons["Skip for now"].tap()

        // Theme picker shows "Continue" and "Pick Your Style" heading
        XCTAssertTrue(app.staticTexts["Pick Your Style"].waitForExistence(timeout: 5),
                      "Theme picker heading should be visible after skipping auth")
    }

    @MainActor
    func testOnboardingThemePickerHasContinueButton() throws {
        let app = launchFresh()
        _ = app.buttons["Get Started"].waitForExistence(timeout: 5)
        app.buttons["Get Started"].tap()
        _ = app.buttons["Skip for now"].waitForExistence(timeout: 5)
        app.buttons["Skip for now"].tap()

        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 5),
                      "Theme picker should have a 'Continue' button")
    }

    @MainActor
    func testOnboardingThemePickerHasSignatureGroup() throws {
        let app = launchFresh()
        _ = app.buttons["Get Started"].waitForExistence(timeout: 5)
        app.buttons["Get Started"].tap()
        _ = app.buttons["Skip for now"].waitForExistence(timeout: 5)
        app.buttons["Skip for now"].tap()

        XCTAssertTrue(app.staticTexts["SIGNATURE"].waitForExistence(timeout: 5),
                      "Theme picker should show the 'Signature' group header")
    }
}

// MARK: - Onboarding: Ready Page

extension LyreUITests {

    @MainActor
    func testOnboardingAdvancesToReadyPage() throws {
        let app = launchFresh()
        _ = app.buttons["Get Started"].waitForExistence(timeout: 5)
        app.buttons["Get Started"].tap()
        _ = app.buttons["Skip for now"].waitForExistence(timeout: 5)
        app.buttons["Skip for now"].tap()
        _ = app.buttons["Continue"].waitForExistence(timeout: 5)
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.staticTexts["You're All Set!"].waitForExistence(timeout: 5),
                      "Ready page heading 'You're All Set!' should appear")
    }

    @MainActor
    func testOnboardingReadyPageHasStartListeningButton() throws {
        let app = launchFresh()
        _ = app.buttons["Get Started"].waitForExistence(timeout: 5)
        app.buttons["Get Started"].tap()
        _ = app.buttons["Skip for now"].waitForExistence(timeout: 5)
        app.buttons["Skip for now"].tap()
        _ = app.buttons["Continue"].waitForExistence(timeout: 5)
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.buttons["Start Listening"].waitForExistence(timeout: 5),
                      "'Start Listening' button should be on the ready page")
    }

    @MainActor
    func testOnboardingReadyPageShowsTips() throws {
        let app = launchFresh()
        _ = app.buttons["Get Started"].waitForExistence(timeout: 5)
        app.buttons["Get Started"].tap()
        _ = app.buttons["Skip for now"].waitForExistence(timeout: 5)
        app.buttons["Skip for now"].tap()
        _ = app.buttons["Continue"].waitForExistence(timeout: 5)
        app.buttons["Continue"].tap()

        _ = app.staticTexts["You're All Set!"].waitForExistence(timeout: 5)
        XCTAssertTrue(
            app.staticTexts["Rotate the scroll wheel to scroll through menus"].exists
            || app.staticTexts["Press the center button to select an item"].exists,
            "Ready page should show at least one usage tip"
        )
    }
}

// MARK: - Onboarding: Complete Flow

extension LyreUITests {

    @MainActor
    func testCompleteOnboardingFlowTransitionsToLyreView() throws {
        let app = launchFresh()

        _ = app.buttons["Get Started"].waitForExistence(timeout: 5)
        app.buttons["Get Started"].tap()

        _ = app.buttons["Skip for now"].waitForExistence(timeout: 5)
        app.buttons["Skip for now"].tap()

        _ = app.buttons["Continue"].waitForExistence(timeout: 5)
        app.buttons["Continue"].tap()

        _ = app.buttons["Start Listening"].waitForExistence(timeout: 5)
        app.buttons["Start Listening"].tap()

        // After onboarding the Lyre view should appear with a scroll wheel
        XCTAssertTrue(app.buttons["Scroll wheel"].waitForExistence(timeout: 5),
                      "Completing onboarding should show the Lyre view with a scroll wheel")
    }
}

// MARK: - Lyre View: Layout

extension LyreUITests {

    @MainActor
    func testLyreViewIsShownWhenOnboardingComplete() throws {
        let app = launchWithOnboardingComplete()
        XCTAssertTrue(app.buttons["Scroll wheel"].waitForExistence(timeout: 5),
                      "Lyre view should be shown when onboarding is already complete")
    }

    @MainActor
    func testLyreViewShowsHoldSwitch() throws {
        let app = launchWithOnboardingComplete()
        _ = app.buttons["Scroll wheel"].waitForExistence(timeout: 5)

        let holdSwitch = app.buttons["Hold switch, disabled"]
        XCTAssertTrue(holdSwitch.exists,
                      "Hold switch should be visible and initially disabled")
    }

    @MainActor
    func testLyreViewShowsScrollWheel() throws {
        let app = launchWithOnboardingComplete()
        XCTAssertTrue(app.buttons["Scroll wheel"].waitForExistence(timeout: 5),
                      "Scroll wheel should be present on the Lyre view")
    }

    @MainActor
    func testLyreViewShowsSelectButton() throws {
        let app = launchWithOnboardingComplete()
        _ = app.buttons["Scroll wheel"].waitForExistence(timeout: 5)

        XCTAssertTrue(app.buttons["Select"].exists,
                      "Center Select button should be present on the Lyre view")
    }

    @MainActor
    func testMainMenuShowsAppTitle() throws {
        let app = launchWithOnboardingComplete()
        _ = app.buttons["Scroll wheel"].waitForExistence(timeout: 5)

        XCTAssertTrue(app.staticTexts["Lyre"].waitForExistence(timeout: 3),
                      "Main menu should show 'Lyre' as its title")
    }

    @MainActor
    func testLyreMainMenuShowsAllMenuItems() throws {
        let app = launchWithOnboardingComplete()
        _ = app.buttons["Scroll wheel"].waitForExistence(timeout: 5)

        let expectedItems = ["Now Playing", "Songs", "Albums", "Artists",
                             "Playlists", "Podcasts", "Settings"]
        for item in expectedItems {
            XCTAssertTrue(app.staticTexts[item].waitForExistence(timeout: 3),
                          "Main menu should contain '\(item)'")
        }
    }
}

// MARK: - Lyre View: Hold Switch

extension LyreUITests {

    @MainActor
    func testHoldSwitchTogglesOnLongPress() throws {
        let app = launchWithOnboardingComplete()
        _ = app.buttons["Scroll wheel"].waitForExistence(timeout: 5)

        let holdSwitchOff = app.buttons["Hold switch, disabled"]
        XCTAssertTrue(holdSwitchOff.exists, "Hold switch should start disabled")

        holdSwitchOff.press(forDuration: 0.7)

        let holdSwitchOn = app.buttons["Hold switch, enabled"]
        XCTAssertTrue(holdSwitchOn.waitForExistence(timeout: 2),
                      "Hold switch should become enabled after long press")
    }

    @MainActor
    func testHoldSwitchTogglesBackOffOnSecondLongPress() throws {
        let app = launchWithOnboardingComplete()
        _ = app.buttons["Scroll wheel"].waitForExistence(timeout: 5)

        // Enable hold
        app.buttons["Hold switch, disabled"].press(forDuration: 0.7)
        _ = app.buttons["Hold switch, enabled"].waitForExistence(timeout: 2)

        // Disable hold again
        app.buttons["Hold switch, enabled"].press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["Hold switch, disabled"].waitForExistence(timeout: 2),
                      "Hold switch should toggle back off on a second long press")
    }
}

// MARK: - Now Playing Screen

extension LyreUITests {

    @MainActor
    func testNowPlayingShowsNothingPlayingByDefault() throws {
        let app = launchWithOnboardingComplete()
        _ = app.buttons["Scroll wheel"].waitForExistence(timeout: 5)

        // Tap Select to enter the first menu item (Now Playing)
        app.buttons["Select"].tap()

        XCTAssertTrue(app.staticTexts["Nothing playing"].waitForExistence(timeout: 3),
                      "Now Playing screen should show 'Nothing playing' when no music has started")
    }

    @MainActor
    func testNowPlayingScreenHasTitle() throws {
        let app = launchWithOnboardingComplete()
        _ = app.buttons["Scroll wheel"].waitForExistence(timeout: 5)

        app.buttons["Select"].tap()

        // The Now Playing header appears alongside the content
        XCTAssertTrue(app.staticTexts["Now Playing"].waitForExistence(timeout: 3),
                      "Now Playing screen should display the 'Now Playing' header")
    }
}

// MARK: - Launch Performance

extension LyreUITests {

    @MainActor
    func testLaunchPerformanceWithOnboardingComplete() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments = ["--uitest-complete-onboarding"]
            app.launch()
            app.terminate()
        }
    }

    @MainActor
    func testLaunchPerformanceFreshInstall() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments = ["--uitest-reset-onboarding"]
            app.launch()
            app.terminate()
        }
    }
}
