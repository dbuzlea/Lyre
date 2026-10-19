//
//  SpoolUITests.swift
//  LyreUITests
//

import XCTest

/// Drives the Spool player's tape change with real touches: tap the door, swipe a tape
/// from the carousel into it, and back out without choosing one.
///
/// Launches with `-SpoolSampleTapes YES`, so the carousel has tapes on a simulator with
/// no music library. Those placeholders have no tracks, so a tape inserted here lands,
/// the door shuts, and playback is refused — the test checks the sequence, not the audio.
final class SpoolUITests: XCTestCase {

    private enum ID {
        static let door = "spool.door"
        static let firstTape = "spool.tape.sample-1"
        static let secondTape = "spool.tape.sample-2"
        /// A single: a bare cassette, not in a case.
        static let single = "spool.tape.sample-3"
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSwipingATapeLeftLoadsItAndClosesTheDeck() throws {
        let app = launchSpool()
        let door = element(app, ID.door)
        XCTAssertTrue(door.waitForExistence(timeout: 10), "Spool door never appeared")

        door.tap()
        let tape = element(app, ID.single)
        XCTAssertTrue(tape.waitForExistence(timeout: 3), "Carousel did not open from the door")
        attachScreenshot(app, named: "carousel-open")

        // A bare tape (albums come in cases, which open instead): bring it forward, swipe it.
        tape.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        sleep(1)
        tape.swipeLeft()

        // The tape flies into the door and the carousel slides away.
        XCTAssertTrue(waitForDisappearance(of: tape, timeout: 4), "Carousel stayed open after the swipe")
        XCTAssertTrue(door.exists)
        attachScreenshot(app, named: "after-insert")
    }

    /// An unfolded iPhone Duo: the deck on the left, the rack on the right. A tape swiped
    /// in waits in the open door; closing the phone (the debug posture, standing in for
    /// the hinge) shuts the door and plays it.
    @MainActor
    func testOnAnOpenDuoASwipedTapeWaitsInTheDeckUntilThePhoneCloses() throws {
        let app = launchSpool(extraArguments: ["-SpoolFoldPosture", "open"])
        let hint = element(app, "spool.open.hint")
        XCTAssertTrue(hint.waitForExistence(timeout: 10), "The open Duo layout didn't show")
        XCTAssertTrue(hint.label.contains("Swipe a tape"), "The open deck didn't ask for a tape: \(hint.label)")

        // The single is a bare tape, so a swipe left loads it rather than opening a case.
        let single = element(app, ID.single)
        XCTAssertTrue(single.waitForExistence(timeout: 5), "The rack isn't beside the deck")
        attachScreenshot(app, named: "duo-open")
        single.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        sleep(1)
        single.swipeLeft()

        // It goes in and waits: the hint says to close the phone, and nothing has played.
        expectation(for: NSPredicate(format: "label CONTAINS 'Close your iPhone'"), evaluatedWith: hint)
        waitForExpectations(timeout: 4)
        XCTAssertFalse(element(app, "spool.notice").exists, "The tape played before the phone was closed")
        attachScreenshot(app, named: "duo-tape-in-deck")

        // Close the phone: the door shuts on the tape and it goes to play. The sample tapes
        // have nothing behind them, so playing them is refused with a notice.
        element(app, "spool.settings").tap()
        let closed = app.buttons["Closed"]
        for _ in 0..<8 where !closed.isHittable { app.swipeUp() }
        closed.tap()
        // Closing goes to play the tape at once, under the sheet; its notice lasts a moment.
        let notice = element(app, "spool.notice")
        XCTAssertTrue(notice.waitForExistence(timeout: 6),
                      "Closing the phone didn't play the tape waiting in the deck")
        element(app, "spool.settings.done").tap()
        XCTAssertTrue(waitForDisappearance(of: hint, timeout: 4), "The open layout stayed after closing")
        attachScreenshot(app, named: "duo-closed")
    }

    /// On an unfolded Duo a case opens over the rack, not the whole screen, so the deck
    /// stays in view; a song picked from it goes into the open door and waits there.
    @MainActor
    func testOnAnOpenDuoACaseOpensOverTheRackAndItsSongGoesIntoTheDoor() throws {
        let app = launchSpool(extraArguments: ["-SpoolFoldPosture", "open"])
        let hint = element(app, "spool.open.hint")
        XCTAssertTrue(hint.waitForExistence(timeout: 10), "The open Duo layout didn't show")
        let door = element(app, ID.door)

        element(app, ID.firstTape).tap()
        let song = element(app, "spool.jcard.track.2")
        XCTAssertTrue(song.waitForExistence(timeout: 5), "The case didn't open")
        sleep(1)
        // The case keeps to the rack's side: the deck is still there, to its left.
        let tray = element(app, "spool.case.cassette")
        XCTAssertTrue(tray.exists)
        XCTAssertGreaterThan(tray.frame.minX, door.frame.maxX - 1, "The case covered the deck")
        attachScreenshot(app, named: "duo-case-over-rack")

        song.tap()
        expectation(for: NSPredicate(format: "label CONTAINS 'Close your iPhone'"), evaluatedWith: hint)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(song.exists, "The case stayed open after a song was picked")
        attachScreenshot(app, named: "duo-case-song-in-door")
    }

    @MainActor
    func testTappingATapeInTheRackBringsItForwardToBeSwiped() throws {
        let app = launchSpool()
        let door = element(app, ID.door)
        XCTAssertTrue(door.waitForExistence(timeout: 10))

        door.tap()
        let first = element(app, ID.firstTape)
        let single = element(app, ID.single)
        XCTAssertTrue(single.waitForExistence(timeout: 3), "Single not in the rack")

        // The single stands behind the cases; only its label strip shows. Tap that.
        single.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        sleep(1)
        attachScreenshot(app, named: "single-brought-forward")
        XCTAssertFalse(element(app, "spool.jcard.track.0").exists, "A bare tape opened a case")

        // Now in front, it swipes into the deck.
        single.swipeLeft()
        XCTAssertTrue(waitForDisappearance(of: first, timeout: 4), "Swiping the single did not insert it")
    }

    @MainActor
    func testClosingTheCarouselBacksOutWithoutChangingTapes() throws {
        let app = launchSpool()
        let door = element(app, ID.door)
        XCTAssertTrue(door.waitForExistence(timeout: 10))

        door.tap()
        let tape = element(app, ID.firstTape)
        XCTAssertTrue(tape.waitForExistence(timeout: 3))

        app.buttons["Close"].tap()
        XCTAssertTrue(waitForDisappearance(of: tape, timeout: 3), "Close did not dismiss the carousel")

        // And the door opens again afterwards.
        door.tap()
        XCTAssertTrue(tape.waitForExistence(timeout: 3), "Door would not reopen after backing out")
    }

    @MainActor
    func testSwipingInFromTheRightEdgeOpensTheCarousel() throws {
        let app = launchSpool()
        XCTAssertTrue(element(app, ID.door).waitForExistence(timeout: 10))

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)

        XCTAssertTrue(element(app, ID.firstTape).waitForExistence(timeout: 3),
                      "Edge swipe did not open the carousel")
    }

    @MainActor
    func testHeaderNamesTheTapeAtTheFront() throws {
        let app = launchSpool()
        let door = element(app, ID.door)
        XCTAssertTrue(door.waitForExistence(timeout: 10))
        door.tap()

        let header = element(app, "spool.carousel.nowShowing")
        XCTAssertTrue(header.waitForExistence(timeout: 3))
        XCTAssertTrue(header.label.contains("Sample Tape 1"), "Header shows \(header.label)")

        let single = element(app, ID.single)
        single.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        let follows = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS 'Sample Single 3'"), object: header)
        XCTAssertEqual(XCTWaiter().wait(for: [follows], timeout: 3), .completed,
                       "Header did not follow the front tape: \(header.label)")
    }

    @MainActor
    func testHoldingATapeOffersQueueingAndItsSongsAndAPickedSongInsertsIt() throws {
        let app = launchSpool()
        let door = element(app, ID.door)
        XCTAssertTrue(door.waitForExistence(timeout: 10))
        door.tap()

        let tape = element(app, ID.firstTape)
        XCTAssertTrue(tape.waitForExistence(timeout: 3))
        sleep(1)
        tape.press(forDuration: 1.0)

        // Holding a tape queues it, as holding an album does on every player.
        let showSongs = app.buttons["Show Songs"]
        XCTAssertTrue(showSongs.waitForExistence(timeout: 3), "Holding a tape offered no menu")
        XCTAssertTrue(app.buttons["Play Next"].exists, "Holding a tape didn't offer Play Next")
        XCTAssertTrue(app.buttons["Add to Queue"].exists, "Holding a tape didn't offer Add to Queue")
        attachScreenshot(app, named: "tape-menu")
        showSongs.tap()

        let song = element(app, "spool.jcard.track.2")
        XCTAssertTrue(song.waitForExistence(timeout: 3), "Cassette case did not open on long press")
        sleep(1)
        attachScreenshot(app, named: "jcard")
        song.tap()

        XCTAssertTrue(waitForDisappearance(of: song, timeout: 3), "J-card stayed open")
        XCTAssertTrue(waitForDisappearance(of: tape, timeout: 5), "Picked song did not insert the tape")
    }

    @MainActor
    func testTheRackHasAnIndexDownItsSide() throws {
        let app = launchSpool()
        let door = element(app, ID.door)
        XCTAssertTrue(door.waitForExistence(timeout: 10))
        door.tap()

        let index = element(app, "spool.index")
        XCTAssertTrue(index.waitForExistence(timeout: 5), "No A–Z index down the rack")
        sleep(1)
        attachScreenshot(app, named: "rack-index")

        // A finger down the index, held near the end to see its letter.
        let top = index.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
        let low = index.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        top.press(forDuration: 0.1, thenDragTo: low, withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertTrue(element(app, "spool.carousel.nowShowing").exists)
        attachScreenshot(app, named: "rack-index-after")
    }

    @MainActor
    func testSinglesAreLabelledAsSingles() throws {
        let app = launchSpool()
        let door = element(app, ID.door)
        XCTAssertTrue(door.waitForExistence(timeout: 10))
        door.tap()

        let single = element(app, "spool.tape.sample-3")
        XCTAssertTrue(single.waitForExistence(timeout: 3))
        XCTAssertTrue(single.label.contains("Single"), "Single reads as \(single.label)")
        XCTAssertFalse(single.label.contains(" - Single"), "Store suffix left in \(single.label)")
        single.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        sleep(1)
        attachScreenshot(app, named: "single-at-front")
    }

    @MainActor
    func testFlickingTheRackCoastsPastSeveralTapes() throws {
        let app = launchSpool()
        let door = element(app, ID.door)
        XCTAssertTrue(door.waitForExistence(timeout: 10))
        door.tap()

        let header = element(app, "spool.carousel.nowShowing")
        XCTAssertTrue(header.waitForExistence(timeout: 3))
        element(app, ID.firstTape).swipeDown(velocity: .fast)
        sleep(2)

        // A flick should carry on past the next tape, not stop one tape along.
        let label = header.label
        XCTAssertFalse(label.hasPrefix("Sample Tape 1,"), "Rack did not move: \(label)")
        XCTAssertFalse(label.hasPrefix("Sample Tape 2,"), "Rack stopped after one tape: \(label)")
        attachScreenshot(app, named: "after-flick")
    }

    @MainActor
    func testTheSlimDesignChangesTapesTheSameWay() throws {
        let app = launchSpool(model: "slim", finish: "silver")
        let door = element(app, ID.door)
        XCTAssertTrue(door.waitForExistence(timeout: 10))
        attachScreenshot(app, named: "slim-closed")

        door.tap()
        let tape = element(app, ID.firstTape)
        XCTAssertTrue(tape.waitForExistence(timeout: 3), "Slim door did not open the carousel")
        attachScreenshot(app, named: "slim-open")

        // Swiped left, a case opens; its Play sends the whole tape in.
        tape.swipeLeft()
        let play = element(app, "spool.case.play")
        XCTAssertTrue(play.waitForExistence(timeout: 3), "Swiping a case did not open it")
        sleep(1)
        play.tap()
        XCTAssertTrue(waitForDisappearance(of: tape, timeout: 5), "Slim deck did not take the tape")
    }

    /// Not a check: screenshots of each design in a spread of finishes, for review.
    @MainActor
    func testDesignGallery() throws {
        let looks = [("original", "blue"), ("original", "sport"), ("original", "black"),
                     ("slim", "red"), ("slim", "gold"), ("slim", "black")]
        for (model, finish) in looks {
            let app = launchSpool(model: model, finish: finish)
            XCTAssertTrue(element(app, ID.door).waitForExistence(timeout: 10))
            sleep(2)
            attachScreenshot(app, named: "\(model)-\(finish)")
            app.terminate()
        }
    }

    @MainActor
    func testTheRackReopensOnTheTapeLastAtTheFront() throws {
        let app = launchSpool()
        let door = element(app, ID.door)
        XCTAssertTrue(door.waitForExistence(timeout: 10))
        door.tap()

        let second = element(app, ID.secondTape)
        XCTAssertTrue(second.waitForExistence(timeout: 3))
        // Tapping the case behind the front opens it; play the whole tape from there.
        second.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        let play = element(app, "spool.case.play")
        XCTAssertTrue(play.waitForExistence(timeout: 3), "Tapping the second case did not open it")
        sleep(1)
        play.tap()
        XCTAssertTrue(waitForDisappearance(of: second, timeout: 5), "Tape was not inserted")

        // Back to the rack: it should open on the tape just played, not the first.
        sleep(2)
        door.tap()
        let header = element(app, "spool.carousel.nowShowing")
        XCTAssertTrue(header.waitForExistence(timeout: 3))
        XCTAssertTrue(header.label.hasPrefix("Sample Tape 2,"), "Rack reopened on \(header.label)")
    }

    @MainActor
    func testTheMixtapeShelfHoldsPlaylistsWithTheirSongsSplitIntoSides() throws {
        let app = launchSpool()
        let door = element(app, ID.door)
        XCTAssertTrue(door.waitForExistence(timeout: 10))
        door.tap()

        let mixtapes = element(app, "spool.shelf.mixtapes")
        XCTAssertTrue(mixtapes.waitForExistence(timeout: 3))
        mixtapes.tap()

        // The sample mixtapes, filed by name: Late Night, Road Trip, Summer '89.
        let header = element(app, "spool.carousel.nowShowing")
        let lateNight = NSPredicate(format: "label BEGINSWITH 'Late Night,'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: lateNight, object: header)],
                                        timeout: 3), .completed, "Header shows \(header.label)")
        XCTAssertFalse(element(app, ID.firstTape).exists, "The album shelf is still showing")
        sleep(1)
        attachScreenshot(app, named: "mixtape-shelf")

        // Road Trip is long enough for two sides, and made by someone.
        let roadTrip = element(app, "spool.tape.mixtape:sample-mix-0")
        XCTAssertTrue(roadTrip.waitForExistence(timeout: 3))
        XCTAssertTrue(roadTrip.label.contains("Made by Sam"), "Label was \(roadTrip.label)")
        roadTrip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        XCTAssertTrue(element(app, "spool.jcard.track.0").waitForExistence(timeout: 3), "The mixtape's case did not open")
        XCTAssertTrue(app.staticTexts["SIDE A"].exists, "No side A heading")
        sleep(1)
        attachScreenshot(app, named: "mixtape-case")
        app.buttons["Close Case"].tap()
        sleep(1)

        // Back to albums: the album rack, on its first tape.
        element(app, "spool.shelf.albums").tap()
        XCTAssertTrue(element(app, ID.firstTape).waitForExistence(timeout: 3), "The album shelf did not come back")
    }

    @MainActor
    func testThePodcastShelfOpensAShowOnItsEpisodesNewestFirst() throws {
        let app = launchSpool()
        let door = element(app, ID.door)
        XCTAssertTrue(door.waitForExistence(timeout: 10))
        door.tap()

        let podcasts = element(app, "spool.shelf.podcasts")
        XCTAssertTrue(podcasts.waitForExistence(timeout: 3))
        podcasts.tap()
        XCTAssertTrue(element(app, "spool.shelf.findShows").waitForExistence(timeout: 3), "No way to find shows")

        // The sample shows, filed by name: Cassette Culture, then The Daily Spin (under D).
        let header = element(app, "spool.carousel.nowShowing")
        let first = NSPredicate(format: "label BEGINSWITH 'Cassette Culture,'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: first, object: header)],
                                        timeout: 3), .completed, "Header shows \(header.label)")
        sleep(1)
        attachScreenshot(app, named: "podcast-shelf")

        // Swiping a show right doesn't queue it: it springs back and nothing is said.
        let show = element(app, "spool.tape.podcast:feed:https://example.invalid/feed-1.xml")
        XCTAssertTrue(show.waitForExistence(timeout: 3))
        show.swipeRight()
        sleep(1)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Added'")).firstMatch.exists,
                       "A podcast was queued")

        // Tapping opens its case on the newest episode, to play the latest.
        show.tap()
        let newest = element(app, "spool.jcard.track.0")
        XCTAssertTrue(newest.waitForExistence(timeout: 3), "The show's case did not open")
        XCTAssertTrue(newest.label.contains("Episode 12"), "First episode was \(newest.label)")
        XCTAssertTrue(element(app, "spool.case.play").exists)
        XCTAssertFalse(element(app, "spool.case.shuffle").exists, "Episodes offered to shuffle")
        sleep(1)
        attachScreenshot(app, named: "podcast-case")
        app.buttons["Close Case"].tap()
    }

    @MainActor
    func testWithAnEpisodeInTheKeysJumpTheSpeedKnobShowsAndUpNextListsTheRest() throws {
        let app = launchSpool()
        let door = element(app, ID.door)
        XCTAssertTrue(door.waitForExistence(timeout: 10))
        // Music keys to start with.
        XCTAssertTrue(app.buttons["Fast Forward"].exists, "No music wind key to start with")
        XCTAssertFalse(app.buttons["Skip Forward 30 Seconds"].exists)
        XCTAssertFalse(element(app, "spool.speed").exists, "Speed knob shown with no podcast")
        door.tap()

        let podcasts = element(app, "spool.shelf.podcasts")
        XCTAssertTrue(podcasts.waitForExistence(timeout: 3))
        podcasts.tap()
        let show = element(app, "spool.tape.podcast:feed:https://example.invalid/feed-1.xml")
        XCTAssertTrue(show.waitForExistence(timeout: 3))
        sleep(1)
        show.tap()

        // The second newest, so ten older episodes follow it.
        let episode = element(app, "spool.jcard.track.1")
        XCTAssertTrue(episode.waitForExistence(timeout: 3), "The show's case did not open")
        sleep(1)
        episode.tap()

        // The sample can't stream, but the episode is loaded: the deck is in podcast mode.
        let forward = app.buttons["Skip Forward 30 Seconds"]
        XCTAssertTrue(forward.waitForExistence(timeout: 8), "The wind keys did not turn into jumps")
        XCTAssertTrue(app.buttons["Skip Back 15 Seconds"].exists)
        let knob = element(app, "spool.speed")
        XCTAssertTrue(knob.waitForExistence(timeout: 3), "No speed knob")
        sleep(1)
        attachScreenshot(app, named: "podcast-deck")

        knob.tap()
        let fast = app.buttons["1.5×"]
        XCTAssertTrue(fast.waitForExistence(timeout: 3), "The speed menu did not open")
        XCTAssertEqual(app.keyboards.count, 0, "A keyboard came up with the speed menu")
        fast.tap()
        XCTAssertEqual(knob.value as? String, "1.5×")

        // Up Next is the show's later episodes, which can't be cleared or moved.
        element(app, "spool.queue.grip").tap()
        let count = app.staticTexts["10 up next"]
        XCTAssertTrue(count.waitForExistence(timeout: 3), "Up Next didn't list the ten older episodes")
        XCTAssertFalse(element(app, "spool.queue.clear").exists, "A show's episodes offered to be cleared")
        XCTAssertTrue(element(app, "spool.queue.nowPlaying").label.contains("Episode 11"),
                      "Now playing was \(element(app, "spool.queue.nowPlaying").label)")
        sleep(1)
        attachScreenshot(app, named: "podcast-up-next")
        element(app, "spool.queue.close").tap()
        // Let the tray finish going down; its backdrop takes touches until then.
        sleep(1)

        // Songs can't join a podcast's Up Next: queueing one says so, in the Spool as
        // in the classic player.
        door.tap()
        let albums = element(app, "spool.shelf.albums")
        XCTAssertTrue(albums.waitForExistence(timeout: 3))
        albums.tap()
        let tape = element(app, ID.firstTape)
        XCTAssertTrue(tape.waitForExistence(timeout: 3))
        sleep(1)
        tape.swipeRight()
        let notice = element(app, "spool.notice")
        XCTAssertTrue(notice.waitForExistence(timeout: 3), "Queueing during a podcast said nothing")
        XCTAssertTrue(notice.label.contains("while a podcast plays"), "Notice was \(notice.label)")
        app.buttons["Close"].tap()
        sleep(1)

        // Put the speed back for later runs.
        sleep(1)
        knob.tap()
        let normal = app.buttons["1×"]
        XCTAssertTrue(normal.waitForExistence(timeout: 3))
        normal.tap()
    }

    @MainActor
    func testTheOwnersManualHasATutorialToStepThrough() throws {
        let app = launchSpool()
        let settings = element(app, "spool.settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()

        let lesson = element(app, "spool.tour.lesson")
        XCTAssertTrue(lesson.waitForExistence(timeout: 5), "The manual has no tutorial")
        XCTAssertTrue(lesson.label.contains("Open the Deck"), "First lesson was \(lesson.label)")
        // Let the first lesson play through.
        sleep(4)
        attachScreenshot(app, named: "manual-tutorial")

        let next = element(app, "spool.tour.next")
        for title in ["Find a Tape", "Load It"] {
            next.tap()
            let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", title), object: lesson)
            XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 3), .completed, "Next showed \(lesson.label)")
        }
        sleep(4)
        attachScreenshot(app, named: "manual-tutorial-load")
        element(app, "spool.tour.replay").tap()
        XCTAssertTrue(lesson.label.contains("Load It"), "Play Again changed the lesson")
    }

    @MainActor
    func testTurningThePhoneDoesNotOpenTheArtworkCarousel() throws {
        let app = launchSpool()
        let door = element(app, ID.door)
        XCTAssertTrue(door.waitForExistence(timeout: 10))

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        attachScreenshot(app, named: "spool-turned")
        XCUIDevice.shared.orientation = .portrait

        // Still the Spool, still upright.
        XCTAssertTrue(door.isHittable, "Something covered the Spool after turning the phone")
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(window.height, window.width, "The interface turned to landscape")
    }

    @MainActor
    func testTappingACasedAlbumOpensItsCaseAndClosingPutsItBack() throws {
        let app = launchSpool()
        let door = element(app, ID.door)
        XCTAssertTrue(door.waitForExistence(timeout: 10))
        door.tap()

        // Sample Tape 1 is an album of several songs, so it stands in its case.
        let tape = element(app, ID.firstTape)
        XCTAssertTrue(tape.waitForExistence(timeout: 3))
        sleep(1)
        tape.tap()

        let song = element(app, "spool.jcard.track.0")
        XCTAssertTrue(song.waitForExistence(timeout: 3), "Tapping the case did not open it")
        sleep(1)
        attachScreenshot(app, named: "case-open")

        app.buttons["Close Case"].tap()
        XCTAssertTrue(waitForDisappearance(of: song, timeout: 3), "Case did not close")
        sleep(1)
        attachScreenshot(app, named: "case-back-in-rack")
        XCTAssertTrue(tape.exists, "Case did not go back into the rack")
    }

    @MainActor
    func testSwipingACaseLeftOpensItInsteadOfPlayingIt() throws {
        let app = launchSpool()
        let door = element(app, ID.door)
        XCTAssertTrue(door.waitForExistence(timeout: 10))
        door.tap()

        let tape = element(app, ID.firstTape)
        XCTAssertTrue(tape.waitForExistence(timeout: 3))
        sleep(1)
        tape.swipeLeft()

        XCTAssertTrue(element(app, "spool.case.play").waitForExistence(timeout: 3), "Case did not open")
        XCTAssertTrue(element(app, "spool.case.shuffle").exists, "No Shuffle in the case")
        sleep(1)
        attachScreenshot(app, named: "case-play-shuffle")
    }

    @MainActor
    func testDraggingTheLidDownFoldsTheCaseShut() throws {
        let app = launchSpool()
        let door = element(app, ID.door)
        XCTAssertTrue(door.waitForExistence(timeout: 10))
        door.tap()

        let tape = element(app, ID.firstTape)
        XCTAssertTrue(tape.waitForExistence(timeout: 3))
        sleep(1)
        tape.tap()
        let song = element(app, "spool.jcard.track.0")
        XCTAssertTrue(song.waitForExistence(timeout: 3))
        sleep(1)

        // The lid's top edge, level with its close button.
        let close = app.buttons["Close Case"]
        let y = close.frame.midY
        let top = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 120, dy: y))

        // A short drag let go springs the lid back open.
        top.press(forDuration: 0.3, thenDragTo: top.withOffset(CGVector(dx: 0, dy: 40)),
                  withVelocity: .slow, thenHoldForDuration: 0.2)
        sleep(1)
        XCTAssertTrue(song.exists, "A short drag closed the case")

        // A long one folds it shut.
        top.press(forDuration: 0.3, thenDragTo: top.withOffset(CGVector(dx: 0, dy: 360)),
                  withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertTrue(waitForDisappearance(of: song, timeout: 3), "Dragging the lid down did not close the case")
        XCTAssertTrue(tape.exists, "Case did not go back into the rack")
    }

    @MainActor
    func testSwipingATapeRightQueuesIt() throws {
        let app = launchSpool()
        let door = element(app, ID.door)
        XCTAssertTrue(door.waitForExistence(timeout: 10))
        door.tap()

        let tape = element(app, ID.firstTape)
        XCTAssertTrue(tape.waitForExistence(timeout: 3))
        sleep(1)
        tape.swipeRight()

        // The sample tapes have nothing playable behind them, so the queue turns them
        // down — but it was asked, and says so, and the rack stays open.
        let notice = element(app, "spool.notice")
        XCTAssertTrue(notice.waitForExistence(timeout: 3), "Swiping right did not queue the tape")
        attachScreenshot(app, named: "queued")
        XCTAssertTrue(tape.exists, "Queueing took the tape out of the rack")
        XCTAssertFalse(element(app, "spool.jcard.track.0").exists, "Swiping right opened the case")
    }

    @MainActor
    func testHoldingASongInTheCaseOffersToQueueIt() throws {
        let app = launchSpool()
        let door = element(app, ID.door)
        XCTAssertTrue(door.waitForExistence(timeout: 10))
        door.tap()

        let tape = element(app, ID.firstTape)
        XCTAssertTrue(tape.waitForExistence(timeout: 3))
        sleep(1)
        tape.tap()
        let song = element(app, "spool.jcard.track.1")
        XCTAssertTrue(song.waitForExistence(timeout: 3))
        sleep(1)

        song.press(forDuration: 1.0)
        let add = app.buttons["Add to Queue"]
        XCTAssertTrue(add.waitForExistence(timeout: 3), "Holding a song offered no queue menu")
        XCTAssertTrue(app.buttons["Play Next"].exists)
        attachScreenshot(app, named: "song-menu")
        add.tap()

        // The menu takes a moment to fold away before the queue answers.
        XCTAssertTrue(element(app, "spool.notice").waitForExistence(timeout: 8), "Queueing the song said nothing")
        XCTAssertTrue(song.exists, "Queueing a song closed the case")
    }

    @MainActor
    func testHoldingTheDoorBringsUpThePlayingAlbumsCase() throws {
        let app = launchSpool()
        let door = element(app, ID.door)
        XCTAssertTrue(door.waitForExistence(timeout: 10))

        // Put a cased album in the deck.
        door.tap()
        let tape = element(app, ID.firstTape)
        XCTAssertTrue(tape.waitForExistence(timeout: 3))
        sleep(1)
        tape.tap()
        let play = element(app, "spool.case.play")
        XCTAssertTrue(play.waitForExistence(timeout: 3))
        sleep(1)
        play.tap()
        XCTAssertTrue(waitForDisappearance(of: tape, timeout: 5), "Tape was not inserted")
        sleep(3)

        // Holding the shut door opens that album's case over it.
        door.press(forDuration: 0.9)
        let song = element(app, "spool.jcard.track.0")
        XCTAssertTrue(song.waitForExistence(timeout: 3), "Holding the door did not bring up the case")
        XCTAssertFalse(tape.exists, "Holding the door opened the carousel too")
        sleep(1)
        attachScreenshot(app, named: "case-from-deck")

        app.buttons["Close Case"].tap()
        XCTAssertTrue(waitForDisappearance(of: song, timeout: 3), "Case did not close")

        // A tap still works the door.
        sleep(1)
        door.tap()
        XCTAssertTrue(tape.waitForExistence(timeout: 3), "Tapping the door no longer opens it")
    }

    @MainActor
    func testHoldingTheDoorWithASingleInTheDeckDoesNothing() throws {
        let app = launchSpool()
        let door = element(app, ID.door)
        XCTAssertTrue(door.waitForExistence(timeout: 10))

        door.tap()
        let single = element(app, ID.single)
        XCTAssertTrue(single.waitForExistence(timeout: 3))
        single.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        sleep(1)
        single.swipeLeft()
        XCTAssertTrue(waitForDisappearance(of: single, timeout: 5), "Single was not inserted")
        sleep(3)

        door.press(forDuration: 0.9)
        sleep(1)
        XCTAssertFalse(element(app, "spool.jcard.track.0").exists, "A single came up in a case")
        XCTAssertFalse(single.exists, "Holding the door opened it")
    }

    // MARK: - Up Next

    /// With songs queued by hand, putting a new tape in asks first, as it would clear them:
    /// the ✕ leaves the deck and the queue alone; Add to Queue queues the tape instead;
    /// Clear and Play goes ahead.
    @MainActor
    func testPlayingATapeOverAQueueBuiltByHandAsksFirst() throws {
        let app = launchSpool(extraArguments: ["--spool-sample-queue", "--queued-by-hand"])
        let door = element(app, ID.door)
        XCTAssertTrue(door.waitForExistence(timeout: 10))
        door.tap()
        let single = element(app, ID.single)
        XCTAssertTrue(single.waitForExistence(timeout: 3))
        single.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        sleep(1)
        single.swipeLeft()

        let prompt = element(app, "queue.replace")
        XCTAssertTrue(prompt.waitForExistence(timeout: 3), "Playing a tape over a queue built by hand didn't ask")
        XCTAssertTrue(app.staticTexts["Playing this clears the 8 songs you've queued."].exists,
                      "The prompt didn't say how many queued songs would go")
        XCTAssertTrue(element(app, "queue.replace.queue").exists, "No Add to Queue in the prompt")
        attachScreenshot(app, named: "replace-queue-prompt")

        // The ✕ in the corner cancels.
        element(app, "queue.replace.cancel").tap()
        XCTAssertTrue(waitForDisappearance(of: prompt, timeout: 2))
        XCTAssertTrue(single.exists, "Cancelling still put the tape in")

        // Add to Queue queues the tape and leaves it in the rack.
        single.swipeLeft()
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
        element(app, "queue.replace.queue").tap()
        XCTAssertTrue(element(app, "spool.notice").waitForExistence(timeout: 5), "Add to Queue said nothing")
        XCTAssertTrue(single.exists, "Add to Queue put the tape in")

        // Clear and Play goes ahead.
        single.swipeLeft()
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
        element(app, "queue.replace.play").tap()
        XCTAssertTrue(waitForDisappearance(of: single, timeout: 5), "Clear and Play didn't put the tape in")
    }

    /// Clearing Up Next asks first: Cancel keeps the songs, Clear Queue empties it.
    @MainActor
    func testClearingUpNextAsksFirst() throws {
        let app = launchSpool(extraArguments: ["--spool-sample-queue"])
        let grip = element(app, "spool.queue.grip")
        XCTAssertTrue(grip.waitForExistence(timeout: 10), "No Up Next grip under the door")
        grip.tap()
        XCTAssertTrue(element(app, "spool.queue.row.0").waitForExistence(timeout: 3))

        let clear = element(app, "spool.queue.clear")
        clear.tap()
        let prompt = app.alerts["Clear the Queue?"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 3), "Clear didn't ask first")
        XCTAssertTrue(prompt.staticTexts["This removes 8 songs from Up Next. What's playing now keeps playing."].exists,
                      "The prompt didn't say how many songs would go")
        attachScreenshot(app, named: "clear-queue-prompt")
        prompt.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["8 up next"].waitForExistence(timeout: 2), "Cancel still cleared the queue")

        clear.tap()
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
        prompt.buttons["Clear Queue"].tap()
        XCTAssertTrue(waitForDisappearance(of: element(app, "spool.queue.row.0"), timeout: 3),
                      "Clear Queue didn't empty Up Next")
    }

    @MainActor
    func testTappingTheGripBringsUpUpNextAndASwipeRemovesASong() throws {
        let app = launchSpool(finish: "gold", extraArguments: ["--spool-sample-queue"])
        let grip = element(app, "spool.queue.grip")
        XCTAssertTrue(grip.waitForExistence(timeout: 10), "No Up Next grip under the door")

        grip.tap()
        // A List only builds the rows on screen, so the count is read from the header.
        XCTAssertTrue(element(app, "spool.queue.row.0").waitForExistence(timeout: 3),
                      "Up Next did not come up with the queued songs")
        XCTAssertTrue(app.staticTexts["8 up next"].exists, "Up Next does not count the queued songs")
        XCTAssertTrue(element(app, "spool.queue.nowPlaying").exists, "No now-playing label")
        sleep(1)
        attachScreenshot(app, named: "queue-tray")

        // Swipe the first song away.
        let first = element(app, "spool.queue.row.0")
        first.swipeLeft()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3), "Swiping a song offered no Delete")
        delete.tap()
        XCTAssertTrue(app.staticTexts["7 up next"].waitForExistence(timeout: 3), "The song was not removed")

        element(app, "spool.queue.close").tap()
        XCTAssertTrue(waitForDisappearance(of: element(app, "spool.queue.row.0"), timeout: 3),
                      "Up Next did not go away")
    }

    @MainActor
    func testPickingASongFromUpNextLoadsItsCassetteIntoTheDeck() throws {
        let app = launchSpool(extraArguments: ["--spool-sample-queue"])
        let grip = element(app, "spool.queue.grip")
        XCTAssertTrue(grip.waitForExistence(timeout: 10))
        grip.tap()
        let row = element(app, "spool.queue.row.1")
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        sleep(1)

        row.tap()
        // Pulled out, then lifted out of its label as the tray goes and the door opens.
        usleep(450_000)
        attachScreenshot(app, named: "queue-pick-lifted")
        XCTAssertTrue(waitForDisappearance(of: row, timeout: 3), "The tray stayed up")

        // Once it's in, the door carries the picked song. (The sample song can't play,
        // so the door goes back to "No tape" a little later; watch for the change.)
        let door = element(app, ID.door)
        let loaded = expectation(for: NSPredicate(format: "label CONTAINS %@", "Sample Song 3"),
                                 evaluatedWith: door)
        wait(for: [loaded], timeout: 5)
        attachScreenshot(app, named: "queue-pick-loaded")
        XCTAssertTrue(grip.isHittable, "The deck did not settle back")
    }

    @MainActor
    func testDraggingTheGripUpPullsTheTrayAndDraggingItsHeaderDownPutsItAway() throws {
        let app = launchSpool(extraArguments: ["--spool-sample-queue"])
        let grip = element(app, "spool.queue.grip")
        XCTAssertTrue(grip.waitForExistence(timeout: 10))

        let start = grip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -400)))
        let close = element(app, "spool.queue.close")
        XCTAssertTrue(close.waitForExistence(timeout: 3), "Dragging the grip up did not bring the tray")
        sleep(1)

        // Down from the header, beside the buttons.
        let header = close.coordinate(withNormalizedOffset: CGVector(dx: -4, dy: 0.5))
        header.press(forDuration: 0.05, thenDragTo: header.withOffset(CGVector(dx: 0, dy: 450)))
        XCTAssertTrue(waitForDisappearance(of: close, timeout: 3), "Dragging the header down left the tray up")
    }

    @MainActor
    func testUpNextSaysSoWhenTheQueueIsEmpty() throws {
        let app = launchSpool()
        let grip = element(app, "spool.queue.grip")
        XCTAssertTrue(grip.waitForExistence(timeout: 10))
        grip.tap()
        XCTAssertTrue(element(app, "spool.queue.empty").waitForExistence(timeout: 3), "No empty state")
    }

    // MARK: - Settings

    @MainActor
    func testTheHotlineButtonOpensSettingsAndAFinishAppliesStraightAway() throws {
        let app = launchSpool(finish: "blue")
        let settings = element(app, "spool.settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "No settings button on the rail")
        // The simulator's missing library is reported in an alert that can cover the button.
        let dismiss = app.alerts.buttons["Dismiss"]
        if dismiss.waitForExistence(timeout: 3) {
            dismiss.tap()
            // A sheet asked for while the alert is still going away doesn't appear.
            sleep(1)
        }

        settings.tap()
        XCTAssertTrue(element(app, "spool.settings.done").waitForExistence(timeout: 3), "Settings did not open")
        // The tutorial and the designs come first; the finishes are under them, and
        // aren't made until they're scrolled to.
        let gold = element(app, "spool.settings.finish.gold")
        for _ in 0..<8 where !(gold.exists && gold.isHittable) { app.swipeUp() }
        gold.tap()
        XCTAssertTrue(gold.isSelected, "The finish picked is not shown as chosen")
        attachScreenshot(app, named: "settings")

        element(app, "spool.settings.done").tap()
        XCTAssertTrue(waitForDisappearance(of: gold, timeout: 3), "Done did not close Settings")
        attachScreenshot(app, named: "settings-gold-applied")
    }

    @MainActor
    func testPickingTheSlimDesignInSettingsChangesTheDeck() throws {
        let app = launchSpool(model: "original")
        XCTAssertTrue(element(app, "spool.settings").waitForExistence(timeout: 10))
        element(app, "spool.settings").tap()

        let slim = element(app, "spool.settings.design.slim")
        XCTAssertTrue(slim.waitForExistence(timeout: 3))
        slim.tap()
        element(app, "spool.settings.done").tap()
        XCTAssertTrue(waitForDisappearance(of: slim, timeout: 3))

        // The slim's keys run along the top, above the door.
        let door = element(app, ID.door)
        let play = app.buttons["Play"]
        XCTAssertTrue(door.waitForExistence(timeout: 3) && play.exists)
        XCTAssertLessThan(play.frame.maxY, door.frame.minY, "Still the original's layout")
    }

    /// Swiped right, a song in a case slides aside onto Play Next and Add to Queue, as
    /// in every list in Lyre, without loading the tape.
    @MainActor
    func testSwipingASongInACaseOffersPlayNextAndAddToQueue() throws {
        let app = launchSpool()
        let door = element(app, ID.door)
        XCTAssertTrue(door.waitForExistence(timeout: 10))
        door.tap()
        let tape = element(app, ID.firstTape)
        XCTAssertTrue(tape.waitForExistence(timeout: 3))
        sleep(1)
        tape.tap()
        let song = element(app, "spool.jcard.track.2")
        XCTAssertTrue(song.waitForExistence(timeout: 5), "The case didn't open")
        sleep(1)
        let from = song.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 150, dy: 0)))
        let playNext = app.buttons["Play Next"].firstMatch
        XCTAssertTrue(playNext.waitForExistence(timeout: 3), "Swiping the song offered nothing")
        XCTAssertTrue(app.buttons["Add to Queue"].firstMatch.exists, "No Add to Queue")
        XCTAssertTrue(song.exists, "The swipe played the song")
        attachScreenshot(app, named: "spool-case-swiped")
        playNext.tap()
        XCTAssertTrue(waitForDisappearance(of: playNext, timeout: 5), "The row stayed open")
        XCTAssertTrue(song.exists, "Play Next played the song")
    }

    // MARK: - Helpers

    private func launchSpool(model: String = "original", finish: String = "blue",
                             extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += extraArguments
        app.launchArguments += [
            "--uitest", "--uitest-complete-onboarding",
            "-LyrePlayerStyle", "spool",
            "-SpoolSampleTapes", "YES",
            "-LyreSpoolModel", model,
            "-LyreSpoolFinish", finish,
            // Start every run at the front of the rack.
            "--spool-reset-rack",
        ]
        app.launch()
        dismissLibraryAlert(in: app)
        return app
    }

    /// A simulator with no music library reports it as an alert a moment after launch,
    /// which would swallow the touches below.
    private func dismissLibraryAlert(in app: XCUIApplication) {
        let dismiss = app.alerts.buttons["Dismiss"]
        if dismiss.waitForExistence(timeout: 8) { dismiss.tap() }
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
