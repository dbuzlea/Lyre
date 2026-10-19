//
//  DiscUITests.swift
//  LyreUITests
//

import XCTest

/// Drives the Disc with real touches: the lid and the shelf, a jewel case and its songs,
/// the MODE and RANDOM keys, the replace-queue prompt, and the operating instructions.
///
/// Launches with `-SpoolSampleTapes YES`, so the shelf has cases on a simulator with no
/// music library. Their songs have nothing behind them, so a disc goes on the spindle but
/// nothing plays — the tests check the player, not the audio.
final class DiscUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testThePlayerShowsItsDeckDisplayAndKeys() throws {
        let app = launchDisc()
        XCTAssertTrue(element(app, "disc.lid").waitForExistence(timeout: 10))
        for id in ["disc.lcd", "disc.previous", "disc.playPause", "disc.next", "disc.mode", "disc.random",
                   "disc.open", "disc.queue.grip", "disc.settings", "disc.airplay"] {
            XCTAssertTrue(element(app, id).exists, "\(id) is missing")
        }
        attachScreenshot(app, named: "disc-player")
    }

    @MainActor
    func testChoosingASongFromACasePutsTheDiscOnAndShutsTheLid() throws {
        let app = launchDisc()
        let open = element(app, "disc.open")
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()

        let disc = element(app, "spool.tape.sample-1")
        XCTAssertTrue(disc.waitForExistence(timeout: 5), "Open didn't bring the shelf up")
        XCTAssertTrue(element(app, "shelf.search.field").exists, "The shelf has no search field")
        XCTAssertTrue(element(app, "spool.shelf.mixtapes").exists, "The shelf has no dividers")
        sleep(1)
        attachScreenshot(app, named: "disc-shelf")

        disc.tap()
        let jewelCase = element(app, "disc.case")
        XCTAssertTrue(jewelCase.waitForExistence(timeout: 5), "Tapping a case didn't open it")
        let song = element(app, "disc.case.track.2")
        XCTAssertTrue(song.waitForExistence(timeout: 5), "The case has no track list")
        sleep(1)
        attachScreenshot(app, named: "disc-case")

        song.tap()
        XCTAssertTrue(waitForDisappearance(jewelCase), "The case stayed open")
        XCTAssertTrue(waitForDisappearance(element(app, "shelf.search.field")), "The shelf stayed up after a disc went on")
        XCTAssertTrue(element(app, "disc.mode").waitForExistence(timeout: 5), "The keys didn't come back")
    }

    @MainActor
    func testTappingTheLidAgainBacksOut() throws {
        let app = launchDisc()
        let lid = element(app, "disc.lid")
        XCTAssertTrue(lid.waitForExistence(timeout: 10))
        lid.tap()
        let search = element(app, "shelf.search.field")
        XCTAssertTrue(search.waitForExistence(timeout: 5), "Tapping the lid didn't open it")
        lid.tap()
        XCTAssertTrue(waitForDisappearance(search), "Tapping the open lid didn't shut it")
    }

    @MainActor
    func testModeStepsThroughRepeat() throws {
        let app = launchDisc()
        let mode = element(app, "disc.mode")
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        mode.tap()
        let notice = element(app, "disc.notice")
        XCTAssertTrue(notice.waitForExistence(timeout: 3), "MODE said nothing")
        XCTAssertEqual(notice.label, "Repeat All")
        mode.tap()
        expectation(for: NSPredicate(format: "label == 'Repeat One'"), evaluatedWith: notice)
        waitForExpectations(timeout: 3)
        mode.tap()
    }

    @MainActor
    func testPuttingADiscOnOverAQueueBuiltByHandAsksFirst() throws {
        let app = launchDisc(extraArguments: ["--spool-sample-queue", "--queued-by-hand"])
        let open = element(app, "disc.open")
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        let disc = element(app, "spool.tape.sample-1")
        XCTAssertTrue(disc.waitForExistence(timeout: 5))
        sleep(1)
        disc.swipeLeft()

        let prompt = element(app, "queue.replace")
        XCTAssertTrue(prompt.waitForExistence(timeout: 3), "Putting a disc on over a queue built by hand didn't ask")
        XCTAssertTrue(element(app, "queue.replace.queue").exists, "No Add to Queue in the prompt")
        element(app, "queue.replace.cancel").tap()
        XCTAssertTrue(waitForDisappearance(prompt, timeout: 2))
        XCTAssertTrue(disc.exists, "Cancelling still put the disc on")
    }

    @MainActor
    func testTheInstructionsHaveATutorialAndAFinishAppliesStraightAway() throws {
        let app = launchDisc()
        let settings = element(app, "disc.settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        // The simulator's library alert can come late, and swallows a sheet asked for
        // while it's up.
        let dismiss = app.alerts.buttons["Dismiss"]
        if dismiss.waitForExistence(timeout: 3) {
            dismiss.tap()
            sleep(1)
        }
        settings.tap()
        let lesson = element(app, "disc.tour.lesson")
        if !lesson.waitForExistence(timeout: 3) {
            if dismiss.exists { dismiss.tap(); sleep(1) }
            settings.tap()
        }
        XCTAssertTrue(lesson.waitForExistence(timeout: 5), "The instructions have no tutorial")
        expectation(for: NSPredicate(format: "label CONTAINS 'Open the Lid'"), evaluatedWith: lesson)
        waitForExpectations(timeout: 3)
        element(app, "disc.tour.next").tap()
        expectation(for: NSPredicate(format: "label CONTAINS 'Choose a Disc'"), evaluatedWith: lesson)
        waitForExpectations(timeout: 3)
        sleep(2)
        attachScreenshot(app, named: "disc-instructions")

        let graphite = element(app, "disc.settings.finish.graphite")
        graphite.tap()
        XCTAssertTrue(graphite.isSelected, "The finish wasn't picked")
        element(app, "disc.settings.done").tap()
        XCTAssertTrue(waitForDisappearance(lesson), "Done didn't close the instructions")
        attachScreenshot(app, named: "disc-graphite")
    }

    /// Swiped right, a song in a case slides aside onto Play Next and Add to Queue, as
    /// in every list in Lyre, without putting the disc on.
    @MainActor
    func testSwipingASongInACaseOffersPlayNextAndAddToQueue() throws {
        let app = launchDisc()
        let open = element(app, "disc.open")
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        let disc = element(app, "spool.tape.sample-1")
        XCTAssertTrue(disc.waitForExistence(timeout: 5))
        disc.tap()
        let song = element(app, "disc.case.track.2")
        XCTAssertTrue(song.waitForExistence(timeout: 5), "The case has no track list")
        sleep(1)
        let from = song.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 150, dy: 0)))
        let playNext = app.buttons["Play Next"].firstMatch
        XCTAssertTrue(playNext.waitForExistence(timeout: 3), "Swiping the song offered nothing")
        XCTAssertTrue(app.buttons["Add to Queue"].firstMatch.exists, "No Add to Queue")
        XCTAssertTrue(element(app, "disc.case").exists, "The swipe put the disc on")
        attachScreenshot(app, named: "disc-case-swiped")
        playNext.tap()
        XCTAssertTrue(waitForDisappearance(playNext), "The row stayed open")
        XCTAssertTrue(element(app, "disc.case").exists, "Play Next put the disc on")
    }

    // MARK: - Helpers

    private func launchDisc(finish: String = "silver", extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "--uitest", "--uitest-complete-onboarding",
            "-LyrePlayerStyle", "disc",
            "-LyreDiscFinish", finish,
            "-SpoolSampleTapes", "YES",
            "--spool-reset-rack",
        ] + extraArguments
        app.launch()
        let dismiss = app.alerts.buttons["Dismiss"]
        if dismiss.waitForExistence(timeout: 4) {
            dismiss.tap()
            sleep(1)
        }
        return app
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                         object: element)], timeout: timeout) == .completed
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
