//
//  GramophoneUITests.swift
//  LyreUITests
//

import XCTest

/// Drives the Gramophone with real touches: its front (the play switch, the crank, the
/// drawer), looking in at the turntable, the crate, a record's sleeve, the tonearm and
/// the instruction booklet.
///
/// Launches with `-SpoolSampleTapes YES`, so the crate has records on a simulator with no
/// music library. Their songs have nothing behind them, so a record goes on the
/// turntable but nothing plays — the tests check the machine, not the audio.
final class GramophoneUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTheHornGramophoneShowsItsFront() throws {
        let app = launchGramophone(model: "horn")
        XCTAssertTrue(element(app, "gramophone.crate").waitForExistence(timeout: 10))
        // In front: the controls on the machine's parts, and no turntable yet.
        for id in ["gramophone.switch", "gramophone.crank", "gramophone.nameplate", "gramophone.upNext",
                   "gramophone.speed", "gramophone.lookInside", "gramophone.settings"] {
            XCTAssertTrue(element(app, id).exists, "\(id) is missing")
        }
        XCTAssertFalse(element(app, "gramophone.tonearm").exists, "The overhead turntable shows in front")
        sleep(1)
        attachScreenshot(app, named: "gramophone-horn-front")

        // Looking in: the camera goes over the top, and the turntable takes over.
        element(app, "gramophone.lookInside").tap()
        let arm = element(app, "gramophone.tonearm")
        XCTAssertTrue(arm.waitForExistence(timeout: 5), "Looking in didn't reach the turntable")
        XCTAssertEqual(arm.value as? String, "No record")
        // VoiceOver finds the arm at its soundbox, not across the whole turntable.
        XCTAssertLessThan(arm.frame.width, 120, "The tonearm's element is \(arm.frame)")
        sleep(1)
        attachScreenshot(app, named: "gramophone-horn-overhead")

        // And back out.
        element(app, "gramophone.stepBack").tap()
        XCTAssertTrue(element(app, "gramophone.switch").waitForExistence(timeout: 5), "Stepping back didn't return to the front")
    }

    @MainActor
    func testThePlaySwitchSpringsBackWithNoRecord() throws {
        let app = launchGramophone()
        let toggle = element(app, "gramophone.switch")
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.tap()
        let notice = element(app, "gramophone.notice")
        XCTAssertTrue(notice.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? String, "Off")
        XCTAssertTrue(toggle.exists, "The camera went in with nothing to play")
    }

    @MainActor
    func testTheCabinetGramophoneHasItsParts() throws {
        let app = launchGramophone(model: "cabinet", finish: "oak")
        XCTAssertTrue(element(app, "gramophone.crate").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "gramophone.switch").exists)
        sleep(1)
        attachScreenshot(app, named: "gramophone-cabinet-front")
    }

    @MainActor
    func testChoosingASongFromASleevePutsTheRecordOnTheTurntable() throws {
        let app = launchGramophone()
        openCrate(app)

        // Sample Tape 1 is on top of the stack; tapping it opens its sleeve.
        let record = element(app, "gramophone.stack.sample-1")
        XCTAssertTrue(record.waitForExistence(timeout: 8), "The drawer didn't open onto the crate")
        sleep(1)
        attachScreenshot(app, named: "gramophone-crate")
        record.tap()
        let song = element(app, "gramophone.sleeve.track.2")
        XCTAssertTrue(song.waitForExistence(timeout: 3), "Tapping the record did not open its sleeve")
        sleep(1)
        attachScreenshot(app, named: "gramophone-sleeve")
        song.tap()

        // The crate goes, and the record is on the turntable with the needle down.
        let onPlatter = element(app, "gramophone.record")
        XCTAssertTrue(onPlatter.waitForExistence(timeout: 15), "No record on the turntable")
        XCTAssertTrue(onPlatter.label.contains("Sample Tape 1"), "Record was \(onPlatter.label)")
        let arm = element(app, "gramophone.tonearm")
        let lowered = NSPredicate(format: "value BEGINSWITH 'On band'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: lowered, object: arm)], timeout: 6),
                       .completed, "The needle didn't go down: \(arm.value ?? "")")
        sleep(1)
        attachScreenshot(app, named: "gramophone-playing")
    }

    @MainActor
    func testSwipingTheStackGoesUpAndDownItAndHoldingQueues() throws {
        let app = launchGramophone()
        openCrate(app)
        let first = element(app, "gramophone.stack.sample-1")
        XCTAssertTrue(first.waitForExistence(timeout: 8), "The drawer didn't open onto the stack")
        sleep(1)

        // Right goes up the stack, to the next record.
        first.swipeRight()
        let second = element(app, "gramophone.stack.sample-2")
        XCTAssertTrue(second.waitForExistence(timeout: 3), "Swiping right didn't go up the stack")
        attachScreenshot(app, named: "gramophone-stack-up")

        // Left comes back down it.
        second.swipeLeft()
        XCTAssertTrue(first.waitForExistence(timeout: 3), "Swiping left didn't go back down the stack")

        // Holding the top record offers to queue it, next or at the end.
        first.press(forDuration: 1.0)
        let playNext = app.buttons["Play Next"]
        XCTAssertTrue(playNext.waitForExistence(timeout: 3), "Holding the record offered no queue menu")
        XCTAssertTrue(app.buttons["Add to Queue"].exists)
        playNext.tap()
        XCTAssertTrue(element(app, "gramophone.notice").waitForExistence(timeout: 8), "Play Next didn't queue the record")
        attachScreenshot(app, named: "gramophone-stack-queued")
    }

    @MainActor
    func testTappingASingleInTheStackOpensItsSleeve() throws {
        let app = launchGramophone()
        openCrate(app)
        let first = element(app, "gramophone.stack.sample-1")
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        sleep(1)
        first.swipeRight()
        let second = element(app, "gramophone.stack.sample-2")
        XCTAssertTrue(second.waitForExistence(timeout: 3))
        second.swipeRight()

        // Sample Tape 3 has one song: its sleeve opens on it, to play or queue.
        let single = element(app, "gramophone.stack.sample-3")
        XCTAssertTrue(single.waitForExistence(timeout: 3))
        single.tap()
        let song = element(app, "gramophone.sleeve.track.0")
        XCTAssertTrue(song.waitForExistence(timeout: 3), "The single's sleeve didn't open")
        XCTAssertFalse(element(app, "gramophone.sleeve.track.1").exists)
        song.tap()
        let arm = element(app, "gramophone.tonearm")
        let lowered = NSPredicate(format: "value BEGINSWITH 'On band'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: lowered, object: arm)], timeout: 16),
                       .completed, "The single didn't go on: \(arm.value ?? "")")
    }

    @MainActor
    func testTheUpNextBinFlipsRemovesReordersAndPlays() throws {
        let app = launchGramophone(extraArguments: ["--spool-sample-queue"])
        // Round to the bin.
        let bin = element(app, "gramophone.upNext")
        XCTAssertTrue(bin.waitForExistence(timeout: 8))
        sleep(1)
        bin.tap()
        let front = element(app, "gramophone.rack.record")
        XCTAssertTrue(front.waitForExistence(timeout: 6), "The camera didn't go round to the bin")
        sleep(1)
        let first = front.value as? String ?? ""
        XCTAssertTrue(first.hasPrefix("1 of "), "The bin opened on \(first)")
        let count = first.replacingOccurrences(of: "1 of ", with: "")
        attachScreenshot(app, named: "gramophone-rack")

        // Down flips to the next record; up flips back.
        front.swipeDown()
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "2 of \(count)"), object: front)], timeout: 3), .completed,
            "Swiping down didn't flip forward: \(front.value ?? "")")
        sleep(1)
        attachScreenshot(app, named: "gramophone-rack-flipped")
        front.swipeUp()
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "1 of \(count)"), object: front)], timeout: 3), .completed,
            "Swiping up didn't flip back: \(front.value ?? "")")

        // Left offers to take it out.
        front.swipeLeft()
        let remove = element(app, "gramophone.rack.remove")
        XCTAssertTrue(remove.waitForExistence(timeout: 3), "Swiping left didn't offer to remove it")
        attachScreenshot(app, named: "gramophone-rack-remove")
        remove.tap()
        let fewer = "1 of \((Int(count) ?? 0) - 1)"
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", fewer), object: front)], timeout: 4), .completed,
            "Removing didn't take it out: \(front.value ?? "")")

        // Holding opens Up Next to reorder.
        front.press(forDuration: 1.0)
        XCTAssertTrue(element(app, "spool.queue.row.0").waitForExistence(timeout: 4), "Holding didn't open Up Next")
        element(app, "spool.queue.close").tap()
        sleep(1)

        // Tapping plays it, on the turntable.
        front.tap()
        XCTAssertTrue(element(app, "gramophone.stepBack").waitForExistence(timeout: 10), "Tapping didn't play it")
        // Put on as a record from the drawer is: there's a record under the arm.
        let arm = element(app, "gramophone.tonearm")
        XCTAssertTrue(arm.waitForExistence(timeout: 10))
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", "No record"), object: arm)], timeout: 10), .completed,
            "No record went on the turntable")
        attachScreenshot(app, named: "gramophone-rack-played")
    }

    @MainActor
    func testTappingTheEmptySpaceBacksOutOfEachView() throws {
        let app = launchGramophone(extraArguments: ["--spool-sample-queue"])

        // The drawer: below the records.
        openCrate(app)
        let stack = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'gramophone.stack.sample'")).firstMatch
        XCTAssertTrue(stack.waitForExistence(timeout: 6), "The drawer didn't open")
        sleep(1)
        tap(app, at: CGPoint(x: stack.frame.midX, y: stack.frame.maxY + 70))
        XCTAssertTrue(waitForDisappearance(element(app, "gramophone.crate.close")), "Tapping below the drawer didn't close it")

        // The turntable: between the record and the deck.
        let lookInside = element(app, "gramophone.lookInside")
        XCTAssertTrue(lookInside.waitForExistence(timeout: 6))
        sleep(1)
        lookInside.tap()
        let stepBack = element(app, "gramophone.stepBack")
        XCTAssertTrue(stepBack.waitForExistence(timeout: 6), "Looking in didn't reach the turntable")
        sleep(1)
        // Just above the deck, whose top row the speed regulator is in.
        let deck = element(app, "gramophone.speed").frame
        tap(app, at: CGPoint(x: app.windows.firstMatch.frame.midX, y: deck.minY - 50))
        XCTAssertTrue(waitForDisappearance(stepBack), "Tapping under the record didn't step back")

        // The bin: in front of it.
        let upNext = element(app, "gramophone.upNext")
        XCTAssertTrue(upNext.waitForExistence(timeout: 6))
        sleep(1)
        upNext.tap()
        let record = element(app, "gramophone.rack.record")
        XCTAssertTrue(record.waitForExistence(timeout: 6), "The camera didn't go round to the bin")
        sleep(1)
        tap(app, at: CGPoint(x: record.frame.midX, y: record.frame.maxY + 60))
        XCTAssertTrue(waitForDisappearance(record), "Tapping in front of the bin didn't close it")
    }

    @MainActor
    func testLiftingTheTonearmOffTheRecordPutsItOnItsRest() throws {
        let app = launchGramophone()
        openCrate(app)
        let record = element(app, "gramophone.stack.sample-1")
        XCTAssertTrue(record.waitForExistence(timeout: 8))
        sleep(1)
        record.tap()
        let song = element(app, "gramophone.sleeve.track.2")
        XCTAssertTrue(song.waitForExistence(timeout: 3))
        song.tap()

        let arm = element(app, "gramophone.tonearm")
        let lowered = NSPredicate(format: "value BEGINSWITH 'On band'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: lowered, object: arm)], timeout: 16),
                       .completed, "Swiping the record left didn't put it on: \(arm.value ?? "")")
        sleep(1)

        // Take hold of the needle and carry it off the record, out to the right.
        let needle = arm.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let offRecord = needle.withOffset(CGVector(dx: 110, dy: -10))
        needle.press(forDuration: 0.3, thenDragTo: offRecord)
        let resting = NSPredicate(format: "value == 'On its rest'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: resting, object: arm)], timeout: 4),
                       .completed, "The arm didn't go to its rest: \(arm.value ?? "")")
        attachScreenshot(app, named: "gramophone-arm-rest")
    }

    @MainActor
    func testWindingTheCrankAFullTurnShufflesAllTheSongs() throws {
        let app = launchGramophone()
        let crank = element(app, "gramophone.crank")
        XCTAssertTrue(crank.waitForExistence(timeout: 10))

        // Seen from the front the handle goes down and up as it turns: a finger running
        // down and up over it twice turns it round.
        let top = crank.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        let bottom = crank.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        top.press(forDuration: 0.05, thenDragTo: bottom)
        bottom.press(forDuration: 0.05, thenDragTo: top)
        top.press(forDuration: 0.05, thenDragTo: bottom)

        // A shuffle record goes on. (The sample songs can't play here, so what's said
        // after is that nothing could be played; on a real library, it plays.)
        let record = element(app, "gramophone.record")
        XCTAssertTrue(record.waitForExistence(timeout: 15), "A full turn did nothing")
        XCTAssertTrue(record.label.contains("Shuffle"), "Record was \(record.label)")
        attachScreenshot(app, named: "gramophone-shuffle")
    }

    @MainActor
    func testTheBookletSwitchesTheDesign() throws {
        let app = launchGramophone(model: "horn")
        let booklet = element(app, "gramophone.settings")
        XCTAssertTrue(booklet.waitForExistence(timeout: 10))
        booklet.tap()
        let cabinet = element(app, "gramophone.settings.design.cabinet")
        XCTAssertTrue(cabinet.waitForExistence(timeout: 5))
        sleep(1)
        attachScreenshot(app, named: "gramophone-booklet")
        // The tutorial comes first; the designs are under it.
        scrollUntilHittable(cabinet, in: app)
        cabinet.tap()
        XCTAssertTrue(cabinet.isSelected, "The cabinet wasn't chosen")
        element(app, "gramophone.settings.done").tap()
    }

    @MainActor
    func testTheBookletOpensWithATutorial() throws {
        let app = launchGramophone()
        let booklet = element(app, "gramophone.settings")
        XCTAssertTrue(booklet.waitForExistence(timeout: 10))
        // The simulator's missing library is reported in an alert that can cover the button.
        let dismiss = app.alerts.buttons["Dismiss"]
        if dismiss.waitForExistence(timeout: 3) {
            dismiss.tap()
            // A sheet asked for while the alert is still going away doesn't appear.
            sleep(1)
        }
        booklet.tap()

        let lesson = element(app, "gramophone.tour.lesson")
        XCTAssertTrue(lesson.waitForExistence(timeout: 5), "The booklet has no tutorial")
        expectation(for: NSPredicate(format: "label CONTAINS 'The Play Switch'"), evaluatedWith: lesson)
        waitForExpectations(timeout: 3)
        sleep(3)
        attachScreenshot(app, named: "tour-play-switch")

        // On to the tonearm, four lessons in.
        let next = element(app, "gramophone.tour.next")
        for _ in 0..<4 { next.tap() }
        expectation(for: NSPredicate(format: "label CONTAINS 'The Tonearm'"), evaluatedWith: lesson)
        waitForExpectations(timeout: 3)
        sleep(2)
        attachScreenshot(app, named: "tour-tonearm")
    }

    /// Swiped right, a song in a sleeve slides aside onto Play Next and Add to Queue, as
    /// in every list in Lyre, without lowering the arm.
    @MainActor
    func testSwipingASongInASleeveOffersPlayNextAndAddToQueue() throws {
        let app = launchGramophone()
        openCrate(app)
        let first = element(app, "gramophone.stack.sample-1")
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        sleep(1)
        first.swipeRight()
        let second = element(app, "gramophone.stack.sample-2")
        XCTAssertTrue(second.waitForExistence(timeout: 3))
        second.swipeRight()
        let single = element(app, "gramophone.stack.sample-3")
        XCTAssertTrue(single.waitForExistence(timeout: 3))
        single.tap()
        let song = element(app, "gramophone.sleeve.track.0")
        XCTAssertTrue(song.waitForExistence(timeout: 3), "The sleeve didn't open")
        sleep(1)
        let from = song.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 150, dy: 0)))
        let playNext = app.buttons["Play Next"].firstMatch
        XCTAssertTrue(playNext.waitForExistence(timeout: 3), "Swiping the song offered nothing")
        XCTAssertTrue(app.buttons["Add to Queue"].firstMatch.exists, "No Add to Queue")
        XCTAssertTrue(song.exists, "The swipe played the song")
        attachScreenshot(app, named: "gramophone-sleeve-swiped")
        playNext.tap()
        XCTAssertTrue(waitForDisappearance(playNext), "The row stayed open")
        XCTAssertTrue(song.exists, "Play Next played the song")
    }

    /// The booklet ends with the app's version, as every player's settings do.
    @MainActor
    func testTheBookletShowsTheVersion() throws {
        let app = launchGramophone()
        let booklet = element(app, "gramophone.settings")
        XCTAssertTrue(booklet.waitForExistence(timeout: 10))
        booklet.tap()
        let version = element(app, "gramophone.settings.version")
        for _ in 0..<10 where !(version.exists && version.isHittable) { app.swipeUp() }
        XCTAssertTrue(version.exists, "The booklet doesn't say its version")
        let expected = Bundle(for: Self.self).object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        XCTAssertTrue(version.label.hasPrefix("Version "), "Version line reads \(version.label)")
        attachScreenshot(app, named: "gramophone-version \(expected)")
    }

    // MARK: - Helpers

    /// Scrolls the booklet up until `element` can be tapped.
    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.isHittable {
            app.swipeUp()
        }
    }

    @MainActor
    func testTheDrawerHasAnIndexThatTakesAFinger() throws {
        let app = launchGramophone()
        openCrate(app)
        let index = element(app, "gramophone.index")
        XCTAssertTrue(index.waitForExistence(timeout: 5), "No A–Z index along the drawer's front")
        attachScreenshot(app, named: "index")

        // Run a finger from A to the end, holding at the end to see the letter bubble.
        let start = index.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5))
        let end = index.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.6)
        XCTAssertTrue(element(app, "gramophone.stack.nowShowing").exists)
        attachScreenshot(app, named: "index-after-scrub")
    }

    private func launchGramophone(model: String = "horn", finish: String = "mahogany",
                                  extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "--uitest", "--uitest-complete-onboarding",
            "-LyrePlayerStyle", "gramophone",
            "-SpoolSampleTapes", "YES",
            "-LyreGramophoneModel", model,
            "-LyreGramophoneFinish", finish,
            "--gramophone-reset-crate",
        ] + extraArguments
        app.launch()
        let dismiss = app.alerts.buttons["Dismiss"]
        if dismiss.waitForExistence(timeout: 8) { dismiss.tap() }
        return app
    }

    private func openCrate(_ app: XCUIApplication) {
        let crate = element(app, "gramophone.crate")
        XCTAssertTrue(crate.waitForExistence(timeout: 10))
        crate.tap()
    }

    /// Taps a point on screen, in points.
    private func tap(_ app: XCUIApplication, at point: CGPoint) {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y)).tap()
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
