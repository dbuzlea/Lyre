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

// MARK: - Onboarding: Navigation Helpers

extension LyreUITests {

    /// Taps a button once it appears.
    private func tap(_ app: XCUIApplication, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "'\(label)' button should appear", file: file, line: line)
        button.tap()
    }

    /// Welcome → past the permissions page → Choose Your Player. "Not Now" skips
    /// straight on; once access has been answered the page offers "Continue" instead,
    /// which leads to the music access result.
    private func advanceToChoosePlayer(_ app: XCUIApplication) {
        tap(app, "Get Started")
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 5) {
            notNow.tap()
        } else {
            tap(app, "Continue")
            passMusicAccess(app)
        }
        XCTAssertTrue(app.staticTexts["Choose Your Player"].waitForExistence(timeout: 5))
    }

    /// … → the classic player chosen → Meet the Scroll Wheel.
    private func advanceToMeetTheWheel(_ app: XCUIApplication) {
        advanceToChoosePlayer(app)
        choosePlayer(app, "classic")
        tap(app, "Continue")
    }

    private func waitFor(_ element: XCUIElement, labelContains text: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text),
                                                    object: element)
        return XCTWaiter().wait(for: [expectation], timeout: 3) == .completed
    }

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func choosePlayer(_ app: XCUIApplication, _ style: String) {
        let choice = app.buttons["onboarding.player.\(style)"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5), "No \(style) player to choose")
        choice.tap()
    }

    /// Any system alert currently on screen, such as a permission prompt.
    private var systemAlerts: XCUIElementQuery {
        XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts
    }

    /// The music access page offers "Skip for now" until access is granted and
    /// "Continue" once it has been — and a simulator can already have access.
    private func passMusicAccess(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let skip = app.buttons["Skip for now"]
        let proceed = app.buttons["Continue"]
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if skip.exists { skip.tap(); return }
            if proceed.exists && proceed.isHittable { proceed.tap(); return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTFail("Music access page offered no way forward", file: file, line: line)
    }

    /// … → skip practice → shortcuts → Make It Yours.
    private func advanceToMakeItYours(_ app: XCUIApplication) {
        advanceToMeetTheWheel(app)
        tap(app, "Try It Yourself")
        tap(app, "Skip Practice")
        tap(app, "Continue")
    }
}

// MARK: - Onboarding: Welcome

extension LyreUITests {

    @MainActor
    func testOnboardingWelcomePageIsShownOnFirstLaunch() throws {
        let app = launchFresh()
        XCTAssertTrue(app.staticTexts["Welcome to Lyre"].waitForExistence(timeout: 5),
                      "Welcome page should display its title")
        XCTAssertTrue(app.buttons["Get Started"].exists, "'Get Started' should be on the welcome page")
    }

    /// Regression: iOS used to ask for music access over the welcome page, before the
    /// app had explained anything.
    @MainActor
    func testFirstLaunchShowsNoPermissionPrompt() throws {
        let app = launchFresh()
        _ = app.staticTexts["Welcome to Lyre"].waitForExistence(timeout: 5)
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        XCTAssertEqual(systemAlerts.count, 0, "No system prompt should appear before the permissions page")
    }

    @MainActor
    func testOnboardingWelcomePageHasNoBackButton() throws {
        let app = launchFresh()
        _ = app.staticTexts["Welcome to Lyre"].waitForExistence(timeout: 5)
        XCTAssertFalse(app.buttons["Back"].exists, "There is nothing to go back to from the welcome page")
    }
}

// MARK: - Onboarding: Permissions

extension LyreUITests {

    @MainActor
    func testOnboardingExplainsPermissionsBeforeAsking() throws {
        let app = launchFresh()
        tap(app, "Get Started")
        XCTAssertTrue(app.staticTexts["Before We Ask"].waitForExistence(timeout: 5),
                      "The permissions page should come straight after the welcome")
        XCTAssertTrue(app.staticTexts["Media & Apple Music"].exists)
        XCTAssertTrue(app.buttons["Allow Access"].exists || app.buttons["Continue"].exists,
                      "The permissions page should offer a way forward")
        XCTAssertEqual(systemAlerts.count, 0, "Explaining must not prompt; only Allow Access does")
    }

    @MainActor
    func testOnboardingNotNowSkipsThePromptEntirely() throws {
        let app = launchFresh()
        tap(app, "Get Started")
        let notNow = app.buttons["Not Now"]
        guard notNow.waitForExistence(timeout: 5) else {
            throw XCTSkip("Access was already answered on this simulator, so there is nothing to decline")
        }
        notNow.tap()
        XCTAssertTrue(app.staticTexts["Meet the Scroll Wheel"].waitForExistence(timeout: 5))
        XCTAssertEqual(systemAlerts.count, 0, "Declining on the permissions page should never show the system prompt")
    }

    @MainActor
    func testOnboardingBackReturnsToWelcome() throws {
        let app = launchFresh()
        tap(app, "Get Started")
        tap(app, "Back")
        XCTAssertTrue(app.staticTexts["Welcome to Lyre"].waitForExistence(timeout: 5),
                      "Back from the permissions page should return to the welcome page")
    }
}

// MARK: - Onboarding: Learning the Wheel

extension LyreUITests {

    @MainActor
    func testOnboardingShowsWheelTourAfterMusicAccess() throws {
        let app = launchFresh()
        advanceToMeetTheWheel(app)
        XCTAssertTrue(app.staticTexts["Meet the Scroll Wheel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Try It Yourself"].exists)
    }

    @MainActor
    func testOnboardingPracticeCanBeSkipped() throws {
        let app = launchFresh()
        advanceToMeetTheWheel(app)
        tap(app, "Try It Yourself")

        XCTAssertTrue(app.staticTexts["Give It a Try"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Continue"].isEnabled, "Continue waits until the lesson is done")
        tap(app, "Skip Practice")
        XCTAssertTrue(app.staticTexts["Handy Shortcuts"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testOnboardingResumesAtTheStepReached() throws {
        let app = launchFresh()
        advanceToMeetTheWheel(app)
        _ = app.staticTexts["Meet the Scroll Wheel"].waitForExistence(timeout: 5)

        // Relaunch without resetting: the journey picks up where it was left.
        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launch()
        XCTAssertTrue(relaunched.staticTexts["Meet the Scroll Wheel"].waitForExistence(timeout: 5),
                      "An interrupted onboarding should resume at the step reached")
    }
}

// MARK: - Onboarding: The Spool

extension LyreUITests {

    @MainActor
    func testOnboardingOffersAChoiceOfPlayer() throws {
        let app = launchFresh()
        advanceToChoosePlayer(app)
        XCTAssertTrue(app.buttons["onboarding.player.classic"].exists)
        XCTAssertTrue(app.buttons["onboarding.player.spool"].exists)
    }

    @MainActor
    func testOnboardingTeachesTheSpoolAndEndsOnIt() throws {
        let app = launchFresh()
        advanceToChoosePlayer(app)
        choosePlayer(app, "spool")
        tap(app, "Continue")

        // The acted-out tour, one lesson at a time.
        XCTAssertTrue(app.staticTexts["Meet the Spool"].waitForExistence(timeout: 5))
        let lesson = app.descendants(matching: .any)["spool.tour.lesson"].firstMatch
        XCTAssertTrue(lesson.waitForExistence(timeout: 5))
        XCTAssertTrue(lesson.label.contains("Open the Deck"), "First lesson was \(lesson.label)")
        sleep(3)
        attachScreenshot(app, named: "onboarding-spool-tour")
        tap(app, "Next Lesson")
        XCTAssertTrue(waitFor(lesson, labelContains: "Find a Tape"), "Next went to \(lesson.label)")
        tap(app, "Previous Lesson")
        XCTAssertTrue(waitFor(lesson, labelContains: "Open the Deck"), "Previous went to \(lesson.label)")
        tap(app, "Continue")

        // Design and finish.
        XCTAssertTrue(app.staticTexts["Make It Yours"].waitForExistence(timeout: 5))
        let slim = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Slim'")).firstMatch
        XCTAssertTrue(slim.exists, "The Spool's designs should be offered")
        slim.tap()
        attachScreenshot(app, named: "onboarding-spool-style")
        tap(app, "Continue")

        XCTAssertTrue(app.staticTexts["You're All Set!"].waitForExistence(timeout: 5))
        let player = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Spool'")).firstMatch
        XCTAssertTrue(player.exists, "The summary should name the Spool")
        tap(app, "Start Listening")
        XCTAssertTrue(app.descendants(matching: .any)["spool.door"].firstMatch.waitForExistence(timeout: 8),
                      "Finishing should open the Spool")
    }

    @MainActor
    func testOnboardingCanEndOnTheGramophone() throws {
        let app = launchFresh()
        advanceToChoosePlayer(app)
        choosePlayer(app, "gramophone")
        tap(app, "Continue")

        XCTAssertTrue(app.staticTexts["Make It Yours"].waitForExistence(timeout: 5))
        let cabinet = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Cabinet'")).firstMatch
        XCTAssertTrue(cabinet.exists, "The Gramophone's designs should be offered")
        cabinet.tap()
        attachScreenshot(app, named: "onboarding-gramophone-style")
        tap(app, "Continue")

        XCTAssertTrue(app.staticTexts["You're All Set!"].waitForExistence(timeout: 5))
        tap(app, "Start Listening")
        XCTAssertTrue(app.descendants(matching: .any)["gramophone.crate"].firstMatch.waitForExistence(timeout: 8),
                      "Finishing should open the Gramophone")
    }

    @MainActor
    func testOnboardingTeachesTheDiscAndEndsOnIt() throws {
        let app = launchFresh()
        advanceToChoosePlayer(app)
        choosePlayer(app, "disc")
        tap(app, "Continue")

        XCTAssertTrue(app.staticTexts["Meet the Disc"].waitForExistence(timeout: 5))
        let lesson = app.descendants(matching: .any)["disc.tour.lesson"].firstMatch
        XCTAssertTrue(lesson.waitForExistence(timeout: 5))
        XCTAssertTrue(lesson.label.contains("Open the Lid"), "First lesson was \(lesson.label)")
        sleep(2)
        attachScreenshot(app, named: "onboarding-disc-tour")
        tap(app, "Continue")

        XCTAssertTrue(app.staticTexts["Make It Yours"].waitForExistence(timeout: 5))
        let graphite = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Graphite'")).firstMatch
        XCTAssertTrue(graphite.exists, "The Disc's finishes should be offered")
        graphite.tap()
        attachScreenshot(app, named: "onboarding-disc-style")
        tap(app, "Continue")

        XCTAssertTrue(app.staticTexts["You're All Set!"].waitForExistence(timeout: 5))
        tap(app, "Start Listening")
        XCTAssertTrue(app.descendants(matching: .any)["disc.lid"].firstMatch.waitForExistence(timeout: 8),
                      "Finishing should open the Disc")
    }

    @MainActor
    func testOnboardingCanEndOnLiquid() throws {
        let app = launchFresh()
        advanceToChoosePlayer(app)
        choosePlayer(app, "liquid")
        tap(app, "Continue")

        // The tutorial, one lesson at a time.
        XCTAssertTrue(app.staticTexts["Meet Liquid"].waitForExistence(timeout: 5))
        let lesson = app.descendants(matching: .any)["liquid.tour.lesson"].firstMatch
        XCTAssertTrue(lesson.waitForExistence(timeout: 5))
        XCTAssertTrue(lesson.label.contains("Change Songs"), "First lesson was \(lesson.label)")
        tap(app, "Continue")

        XCTAssertTrue(app.staticTexts["You're All Set!"].waitForExistence(timeout: 5))
        tap(app, "Start Listening")
        XCTAssertTrue(app.descendants(matching: .any)["liquid.menu.albums"].firstMatch.waitForExistence(timeout: 8),
                      "Finishing should open Liquid")
    }

    @MainActor
    func testTheClassicShortcutsIncludePlayNext() throws {
        let app = launchFresh()
        advanceToMeetTheWheel(app)
        tap(app, "Try It Yourself")
        tap(app, "Skip Practice")
        XCTAssertTrue(app.staticTexts["Handy Shortcuts"].waitForExistence(timeout: 5))
        let playNext = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Swipe left on the center'")).firstMatch
        XCTAssertTrue(playNext.exists, "The shortcuts should teach swipe left")
    }
}

// MARK: - Onboarding: Customizing

extension LyreUITests {

    @MainActor
    func testOnboardingOffersToSkipCustomization() throws {
        let app = launchFresh()
        advanceToMakeItYours(app)
        XCTAssertTrue(app.staticTexts["Make It Yours"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Customize"].exists)
        XCTAssertTrue(app.buttons["Keep the Classic Look"].exists)
    }

    @MainActor
    func testOnboardingSkippingCustomizationGoesToSummary() throws {
        let app = launchFresh()
        advanceToMakeItYours(app)
        tap(app, "Keep the Classic Look")
        XCTAssertTrue(app.staticTexts["You're All Set!"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start Listening"].exists)
    }

    @MainActor
    func testOnboardingCustomizationIsOneChoicePerStep() throws {
        let app = launchFresh()
        advanceToMakeItYours(app)
        tap(app, "Customize")

        XCTAssertTrue(app.staticTexts["Choose a Body"].waitForExistence(timeout: 5))
        let slim = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Slim'")).firstMatch
        XCTAssertTrue(slim.exists, "Body step should list the Slim family")
        slim.tap()
        tap(app, "Continue")

        XCTAssertTrue(app.staticTexts["Pick a Color"].waitForExistence(timeout: 5))
        tap(app, "Continue")
        XCTAssertTrue(app.staticTexts["Highlight Color"].waitForExistence(timeout: 5))
        tap(app, "Continue")
        XCTAssertTrue(app.staticTexts["Screen Size"].waitForExistence(timeout: 5))
        tap(app, "Continue")
        XCTAssertTrue(app.staticTexts["How the Wheel Feels"].waitForExistence(timeout: 5))
        tap(app, "Continue")
        XCTAssertTrue(app.staticTexts["Screen Timeout"].waitForExistence(timeout: 5))
        tap(app, "Continue")
        XCTAssertTrue(app.staticTexts["You're All Set!"].waitForExistence(timeout: 5))
    }
}

// MARK: - Onboarding: Complete Flow

extension LyreUITests {

    @MainActor
    func testCompleteOnboardingFlowTransitionsToLyreView() throws {
        let app = launchFresh()
        advanceToMakeItYours(app)
        tap(app, "Keep the Classic Look")
        tap(app, "Start Listening")

        // After onboarding the Lyre view should appear with a scroll wheel
        XCTAssertTrue(app.descendants(matching: .any)["Scroll wheel"].firstMatch.waitForExistence(timeout: 5),
                      "Completing onboarding should show the Lyre view with a scroll wheel")
    }
}

// MARK: - Lyre View: Layout

extension LyreUITests {

    @MainActor
    func testLyreViewIsShownWhenOnboardingComplete() throws {
        let app = launchWithOnboardingComplete()
        XCTAssertTrue(app.descendants(matching: .any)["Scroll wheel"].firstMatch.waitForExistence(timeout: 5),
                      "Lyre view should be shown when onboarding is already complete")
    }

    @MainActor
    func testLyreViewShowsHoldSwitch() throws {
        let app = launchWithOnboardingComplete()
        _ = app.descendants(matching: .any)["Scroll wheel"].firstMatch.waitForExistence(timeout: 5)

        let holdSwitch = app.buttons["Hold switch, disabled"]
        XCTAssertTrue(holdSwitch.exists,
                      "Hold switch should be visible and initially disabled")
    }

    @MainActor
    func testLyreViewShowsScrollWheel() throws {
        let app = launchWithOnboardingComplete()
        XCTAssertTrue(app.descendants(matching: .any)["Scroll wheel"].firstMatch.waitForExistence(timeout: 5),
                      "Scroll wheel should be present on the Lyre view")
    }

    /// VoiceOver can't spin the ring, so the wheel is adjustable and its value reads out
    /// the highlighted item.
    @MainActor
    func testScrollWheelReportsHighlightedItemToVoiceOver() throws {
        let app = launchWithOnboardingComplete()
        let wheel = app.descendants(matching: .any)["Scroll wheel"].firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 5))
        XCTAssertEqual(wheel.value as? String, "Now Playing",
                       "On the main menu the wheel should report the highlighted menu item")
    }

    @MainActor
    func testLyreViewShowsSelectButton() throws {
        let app = launchWithOnboardingComplete()
        _ = app.descendants(matching: .any)["Scroll wheel"].firstMatch.waitForExistence(timeout: 5)

        XCTAssertTrue(app.buttons["Select"].exists,
                      "Center Select button should be present on the Lyre view")
    }

    @MainActor
    func testMainMenuShowsAppTitle() throws {
        let app = launchWithOnboardingComplete()
        _ = app.descendants(matching: .any)["Scroll wheel"].firstMatch.waitForExistence(timeout: 5)

        XCTAssertTrue(app.staticTexts["Lyre"].waitForExistence(timeout: 3),
                      "Main menu should show 'Lyre' as its title")
    }

    @MainActor
    func testLyreMainMenuShowsAllMenuItems() throws {
        let app = launchWithOnboardingComplete()
        _ = app.descendants(matching: .any)["Scroll wheel"].firstMatch.waitForExistence(timeout: 5)

        let expectedItems = ["Now Playing", "Songs", "Albums", "Artists",
                             "Playlists", "Podcasts", "Search", "Change Player", "Settings"]
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
        _ = app.descendants(matching: .any)["Scroll wheel"].firstMatch.waitForExistence(timeout: 5)

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
        _ = app.descendants(matching: .any)["Scroll wheel"].firstMatch.waitForExistence(timeout: 5)

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
        _ = app.descendants(matching: .any)["Scroll wheel"].firstMatch.waitForExistence(timeout: 5)

        // Tap Select to enter the first menu item (Now Playing)
        app.buttons["Select"].tap()

        XCTAssertTrue(app.staticTexts["Nothing playing"].waitForExistence(timeout: 3),
                      "Now Playing screen should show 'Nothing playing' when no music has started")
    }

    @MainActor
    func testNowPlayingScreenHasTitle() throws {
        let app = launchWithOnboardingComplete()
        _ = app.descendants(matching: .any)["Scroll wheel"].firstMatch.waitForExistence(timeout: 5)

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
