//
//  EnvironmentUITests.swift
//  LyreUITests
//
//  Lyre for every user and every situation they might be in: offline or with a
//  server down, with the largest text sizes, in a right-to-left language, holding the
//  phone sideways, using VoiceOver, and with music access taken away after onboarding.
//
//  The network states come from `-UITestNetwork` (see UITestNetwork in the app), which
//  answers the app's podcast requests itself; a simulator can't be taken offline from
//  inside a test.
//

import XCTest

final class EnvironmentUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: - Helpers

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    /// The classic player with the podcast search sheet open, on the given network.
    private func launchPodcastSearch(network: String) -> XCUIApplication {
        launch([
            "--uitest", "--uitest-complete-onboarding", "-LyrePlayerStyle", "classic",
            "--uitest-open-podcast-search", "--uitest-reset-subscriptions", "--uitest-hide-library-errors",
            "-UITestNetwork", network,
        ])
    }

    /// The simulator has no music library, which the app reports in an alert that can
    /// arrive at any point.
    private func dismissLibraryAlert(in app: XCUIApplication, timeout: TimeInterval = 3) {
        let alert = app.alerts.firstMatch
        if alert.waitForExistence(timeout: timeout), alert.buttons["Dismiss"].exists {
            alert.buttons["Dismiss"].tap()
        }
    }

    private func searchField(in app: XCUIApplication) -> XCUIElement {
        // The sheet waits for the library's load, and its error, to be out of the way;
        // on a simulator with no library the error can come up more than once.
        let field = app.searchFields.firstMatch
        let deadline = Date().addingTimeInterval(40)
        while !field.exists && Date() < deadline {
            let dismiss = app.alerts.firstMatch.buttons["Dismiss"]
            if dismiss.exists { dismiss.tap() }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTAssertTrue(field.exists, "The podcast search sheet didn't open")
        return field
    }

    private func type(_ text: String, into field: XCUIElement, in app: XCUIApplication) {
        field.tap()
        field.typeText(text)
    }

    private func text(containing fragment: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    private func tap(_ app: XCUIApplication, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "'\(label)' button should appear", file: file, line: line)
        if !button.isHittable { app.swipeUp() }
        button.tap()
    }

    /// Welcome → past the permissions page → Choose Your Player, whichever way the
    /// simulator has answered music access.
    private func advanceToChoosePlayer(_ app: XCUIApplication) {
        tap(app, "Get Started")
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 5) {
            notNow.tap()
        } else {
            tap(app, "Continue")
            let skip = app.buttons["Skip for now"], proceed = app.buttons["Continue"]
            let deadline = Date().addingTimeInterval(10)
            while Date() < deadline {
                if skip.exists { skip.tap(); break }
                if proceed.exists && proceed.isHittable { proceed.tap(); break }
                RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            }
        }
        XCTAssertTrue(app.staticTexts["Choose Your Player"].waitForExistence(timeout: 5))
    }

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

// MARK: - Connection States

extension EnvironmentUITests {

    @MainActor
    func testPodcastSearchOfflineSaysToCheckTheConnection() throws {
        let app = launchPodcastSearch(network: "offline")
        type("news", into: searchField(in: app), in: app)
        XCTAssertTrue(text(containing: "Check your connection", in: app).waitForExistence(timeout: 8),
                      "Searching offline should say why nothing came back")
        attachScreenshot(app, named: "podcast-search-offline")
    }

    @MainActor
    func testPodcastSearchWithTheDirectoryDownSaysToTryAgain() throws {
        let app = launchPodcastSearch(network: "serverError")
        type("news", into: searchField(in: app), in: app)
        XCTAssertTrue(text(containing: "Search isn't available right now", in: app).waitForExistence(timeout: 8),
                      "A directory that's down should read as unavailable, not as no results")
        XCTAssertFalse(app.staticTexts["No podcasts found"].exists)
    }

    @MainActor
    func testSubscribingToAPastedFeedOfflineExplainsTheFailure() throws {
        let app = launchPodcastSearch(network: "offline")
        type("https://feeds.lyre.test/morning-somewhere.xml", into: searchField(in: app), in: app)
        let addFeed = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Subscribe to this feed'")).firstMatch
        XCTAssertTrue(addFeed.waitForExistence(timeout: 5), "Pasting a feed address should offer to subscribe to it")
        addFeed.tap()
        let alert = app.alerts["Couldn't Subscribe"]
        XCTAssertTrue(alert.waitForExistence(timeout: 8), "A failed subscribe should say so")
        attachScreenshot(app, named: "podcast-subscribe-offline")
        alert.buttons["OK"].tap()
        XCTAssertTrue(addFeed.waitForExistence(timeout: 3) && addFeed.isEnabled,
                      "It can be tried again once back online")
    }

    @MainActor
    func testPodcastSearchOnlineFindsAndSubscribesToAShow() throws {
        let app = launchPodcastSearch(network: "stub")
        let field = searchField(in: app)
        XCTAssertTrue(text(containing: "Search for any podcast", in: app).waitForExistence(timeout: 5),
                      "With no subscriptions, the sheet explains itself")

        type("morning", into: field, in: app)
        XCTAssertTrue(app.staticTexts["Morning Somewhere"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["No Public Feed"].exists, "A show with no public feed can't be streamed")

        let subscribe = app.buttons["Subscribe"].firstMatch
        XCTAssertTrue(subscribe.waitForExistence(timeout: 3))
        subscribe.tap()
        XCTAssertTrue(app.buttons["Subscribed"].firstMatch.waitForExistence(timeout: 8), "Subscribing didn't finish")

        // Clearing the search lists the subscription, with its episodes counted.
        field.buttons["Clear text"].tap()
        XCTAssertTrue(text(containing: "2 episodes", in: app).waitForExistence(timeout: 5))
        attachScreenshot(app, named: "podcast-subscribed")

        // Unsubscribe, leaving the simulator as it was.
        let row = app.cells.containing(.staticText, identifier: "Morning Somewhere").firstMatch
        row.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(text(containing: "Search for any podcast", in: app).waitForExistence(timeout: 5))
    }
}

// MARK: - Accessibility

extension EnvironmentUITests {

    /// The largest accessibility text size still leaves every onboarding choice and
    /// the way on within reach.
    @MainActor
    func testOnboardingWorksAtTheLargestTextSize() throws {
        let app = launch(["--uitest-reset-onboarding",
                          "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.buttons["Get Started"].waitForExistence(timeout: 5))
        advanceToChoosePlayer(app)
        attachScreenshot(app, named: "onboarding-choose-player-xxxl")

        for style in ["classic", "spool", "gramophone", "disc", "liquid"] {
            let choice = app.buttons["onboarding.player.\(style)"]
            var swipes = 0
            while !choice.isHittable && swipes < 8 { app.swipeUp(); swipes += 1 }
            XCTAssertTrue(choice.isHittable, "The \(style) choice can't be reached at the largest text size")
        }
        app.buttons["onboarding.player.liquid"].tap()
        let next = app.buttons["Continue"]
        XCTAssertTrue(next.isHittable, "Continue is out of reach at the largest text size")
        next.tap()
        XCTAssertTrue(app.staticTexts["Meet Liquid"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTheMainMenuWorksAtTheLargestTextSize() throws {
        let app = launch(["--uitest", "--uitest-complete-onboarding", "-LyrePlayerStyle", "classic",
                          "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let wheel = app.descendants(matching: .any)["Scroll wheel"].firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 5))
        dismissLibraryAlert(in: app)
        XCTAssertTrue(wheel.isHittable)
        XCTAssertTrue(app.buttons["Select"].isHittable)
        attachScreenshot(app, named: "main-menu-xxxl")
    }

    /// Everything on the first screens has a name VoiceOver can read, and nothing is
    /// too small to tap.
    @MainActor
    func testTheWelcomePagePassesAnAccessibilityAudit() throws {
        let app = launch(["--uitest-reset-onboarding"])
        XCTAssertTrue(app.buttons["Get Started"].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion, .trait])
    }

    @MainActor
    func testChoosingAPlayerPassesAnAccessibilityAudit() throws {
        let app = launch(["--uitest-reset-onboarding"])
        advanceToChoosePlayer(app)
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion, .trait])
    }

    @MainActor
    func testPodcastSearchPassesAnAccessibilityAudit() throws {
        let app = launchPodcastSearch(network: "stub")
        // Return puts the keyboard away: it's the system's, and not what's audited.
        type("morning\n", into: searchField(in: app), in: app)
        XCTAssertTrue(app.staticTexts["Morning Somewhere"].waitForExistence(timeout: 8))
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion]) { issue in
            // The search bar's own clear button is the system's, not Lyre's to size.
            issue.element?.label == "Clear text"
        }
    }
}

// MARK: - Languages and Orientation

extension EnvironmentUITests {

    /// A right-to-left language mirrors the layout; onboarding must still lead
    /// through to a player.
    @MainActor
    func testOnboardingWorksRightToLeft() throws {
        let app = launch(["--uitest-reset-onboarding",
                          "-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES"])
        advanceToChoosePlayer(app)
        attachScreenshot(app, named: "onboarding-rtl")
        app.buttons["onboarding.player.liquid"].tap()
        tap(app, "Continue")
        XCTAssertTrue(app.staticTexts["Meet Liquid"].waitForExistence(timeout: 5))
        tap(app, "Continue")
        XCTAssertTrue(app.staticTexts["You're All Set!"].waitForExistence(timeout: 5))
        tap(app, "Start Listening")
        XCTAssertTrue(app.descendants(matching: .any)["liquid.menu.albums"].firstMatch.waitForExistence(timeout: 8))
    }

    @MainActor
    func testTheMainMenuWorksRightToLeft() throws {
        let app = launch(["--uitest", "--uitest-complete-onboarding", "-LyrePlayerStyle", "classic",
                          "-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES"])
        XCTAssertTrue(app.descendants(matching: .any)["Scroll wheel"].firstMatch.waitForExistence(timeout: 5))
        dismissLibraryAlert(in: app)
        for item in ["Now Playing", "Songs", "Albums", "Podcasts", "Settings"] {
            XCTAssertTrue(app.staticTexts[item].exists, "'\(item)' is missing right-to-left")
        }
        app.buttons["Select"].tap()
        XCTAssertTrue(app.staticTexts["Nothing playing"].waitForExistence(timeout: 3))
    }

    /// Onboarding started with the phone on its side can still be finished.
    @MainActor
    func testOnboardingCanBeFinishedInLandscape() throws {
        let app = launch(["--uitest-reset-onboarding"])
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["Get Started"].waitForExistence(timeout: 5))
        advanceToChoosePlayer(app)
        let liquid = app.buttons["onboarding.player.liquid"]
        var swipes = 0
        while !liquid.isHittable && swipes < 6 { app.swipeUp(); swipes += 1 }
        liquid.tap()
        tap(app, "Continue")
        XCTAssertTrue(app.staticTexts["Meet Liquid"].waitForExistence(timeout: 5))
        attachScreenshot(app, named: "onboarding-landscape")
    }

    /// Turning the phone mid-onboarding keeps the step reached.
    @MainActor
    func testRotatingDuringOnboardingKeepsTheStep() throws {
        let app = launch(["--uitest-reset-onboarding"])
        advanceToChoosePlayer(app)
        XCUIDevice.shared.orientation = .landscapeRight
        XCTAssertTrue(app.staticTexts["Choose Your Player"].waitForExistence(timeout: 3))
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.staticTexts["Choose Your Player"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Continue"].exists)
    }
}

// MARK: - Life Cycle

extension EnvironmentUITests {

    /// Sent to the background and brought back, the player is where it was left.
    @MainActor
    func testComingBackFromTheBackgroundKeepsThePlayer() throws {
        let app = launch(["--uitest", "--uitest-complete-onboarding", "-LyrePlayerStyle", "classic"])
        let wheel = app.descendants(matching: .any)["Scroll wheel"].firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 5))
        dismissLibraryAlert(in: app)
        app.buttons["Select"].tap()
        XCTAssertTrue(app.staticTexts["Nothing playing"].waitForExistence(timeout: 3))

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(XCUIApplication(bundleIdentifier: "com.apple.springboard").wait(for: .runningForeground, timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        dismissLibraryAlert(in: app, timeout: 2)
        XCTAssertTrue(app.staticTexts["Nothing playing"].waitForExistence(timeout: 3),
                      "Coming back should land on the screen that was left")
    }

    /// A player chosen in onboarding is still the player after the app is quit.
    @MainActor
    func testTheChosenPlayerSurvivesARelaunch() throws {
        let app = launch(["--uitest-reset-onboarding"])
        advanceToChoosePlayer(app)
        app.buttons["onboarding.player.liquid"].tap()
        tap(app, "Continue")
        tap(app, "Continue")
        tap(app, "Start Listening")
        XCTAssertTrue(app.descendants(matching: .any)["liquid.menu.albums"].firstMatch.waitForExistence(timeout: 8))

        app.terminate()
        let relaunched = launch(["--uitest"])
        XCTAssertTrue(relaunched.descendants(matching: .any)["liquid.menu.albums"].firstMatch.waitForExistence(timeout: 8),
                      "A returning user should come back to the player they chose")
        XCTAssertFalse(relaunched.staticTexts["Welcome to Lyre"].exists, "Onboarding shouldn't run twice")
    }
}

// MARK: - Music Access

extension EnvironmentUITests {

    /// A returning user whose music access was turned off is told so, can go on without
    /// it, and — once access is allowed again — gets their library back.
    ///
    /// Resets the simulator's music access, then allows it again through onboarding, so
    /// the simulator ends up as it started.
    @MainActor
    func testARevokedLibraryAccessIsExplainedAndCanBeRestored() throws {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .mediaLibrary)

        // A returning user with access gone.
        app.launchArguments = ["--uitest", "--uitest-complete-onboarding", "-LyrePlayerStyle", "classic",
                               "-accessRecoverySkipped", "NO"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Media & Apple Music Access Needed"].waitForExistence(timeout: 8),
                      "Losing access should be explained, not shown as an empty library")
        XCTAssertTrue(app.buttons["Open Settings"].exists)
        attachScreenshot(app, named: "access-revoked")
        tap(app, "Not Now")
        XCTAssertTrue(app.descendants(matching: .any)["Scroll wheel"].firstMatch.waitForExistence(timeout: 5),
                      "Not Now should let the user in without access")
        app.terminate()

        // Allowing access again, from onboarding's permission page.
        app.launchArguments = ["--uitest-reset-onboarding"]
        app.launch()
        tap(app, "Get Started")
        tap(app, "Allow Access")
        let prompt = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 8), "Allow Access should bring up the system prompt")
        let allow = ["Allow", "OK"].map { prompt.buttons[$0] }.first { $0.exists }
        XCTAssertNotNil(allow, "The system prompt had no Allow button: \(prompt.buttons.allElementsBoundByIndex.map(\.label))")
        allow?.tap()
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 8),
                      "With access allowed, onboarding should go on")
        app.terminate()

        // Back as a returning user, the recovery screen settles and the player is reachable.
        app.launchArguments = ["--uitest", "--uitest-complete-onboarding", "-LyrePlayerStyle", "classic"]
        app.launch()
        // "Access restored" stays up until the library has reloaded. The simulator has
        // access but no library, so that takes every retry, and the load's error may
        // come up too. Waiting it out also leaves nothing pending for the next test.
        let wheel = app.descendants(matching: .any)["Scroll wheel"].firstMatch
        let deadline = Date().addingTimeInterval(60)
        while !(wheel.exists && wheel.isHittable) && Date() < deadline {
            if app.alerts.firstMatch.buttons["Dismiss"].exists { app.alerts.firstMatch.buttons["Dismiss"].tap() }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTAssertTrue(wheel.isHittable, "With access restored, the player should come back")
        XCTAssertFalse(app.staticTexts["Media & Apple Music Access Needed"].exists)
        XCTAssertFalse(app.staticTexts["Access Restored"].exists)
    }
}
