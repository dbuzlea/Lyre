//
//  StreamingDeviceUITests.swift
//  LyreUITests
//

import XCTest

/// Streaming a song from Apple Music that isn't in the library, end to end. Only a
/// device can: it needs the listener's own library, Apple Music access and a
/// subscription, none of which a simulator has, so it's skipped there. It plays out
/// loud for a few seconds.
final class StreamingDeviceUITests: XCTestCase {

    override func setUpWithError() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Streaming from Apple Music needs a device with a subscription.")
        #endif
        continueAfterFailure = false
    }

    /// Liquid's search finds a song in Apple Music the library hasn't; tapped, it streams
    /// and Now Playing shows it.
    @MainActor
    func testASongNotInTheLibraryStreamsFromSearch() throws {
        let app = XCUIApplication()
        // The listener's own library and settings: no sample tapes, not `--uitest`
        // (which keeps Apple Music out of the way).
        app.launchArguments += ["-LyrePlayerStyle", "liquid"]
        app.launch()

        // Lyre comes back where it was left: Now Playing, or the library.
        let library = app.descendants(matching: .any)["liquid.library"].firstMatch
        let search = app.descendants(matching: .any)["liquid.menu.search"].firstMatch
        if !search.waitForExistence(timeout: 10) {
            XCTAssertTrue(library.waitForExistence(timeout: 10), "Liquid didn't open")
            library.tap()
            XCTAssertTrue(search.waitForExistence(timeout: 10), "The library has no search")
        }
        search.tap()
        let field = app.descendants(matching: .any)["liquid.search.field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        app.typeText("billboard hot 100")

        // The first Apple Music song the library hasn't.
        let notInLibrary = app.buttons.matching(identifier: "liquid.catalog.song")
            .matching(NSPredicate(format: "label CONTAINS %@", "Not in your library")).firstMatch
        XCTAssertTrue(notInLibrary.waitForExistence(timeout: 20), "Search found nothing in Apple Music that isn't in the library")
        let title = notInLibrary.label.components(separatedBy: ",").first ?? ""
        notInLibrary.tap()

        let nowPlaying = app.descendants(matching: .any)["liquid.nowPlaying"].firstMatch
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 15), "Now Playing didn't come back")
        let showsIt = NSPredicate(format: "label CONTAINS %@", title)
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: showsIt, object: nowPlaying)], timeout: 20),
                       .completed, "Now Playing doesn't show '\(title)': \(nowPlaying.label)")
        sleep(4)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "streaming-now-playing"
        shot.lifetime = .keepAlways
        add(shot)
        app.descendants(matching: .any)["liquid.playPause"].firstMatch.tap()
    }

    /// A typical few minutes in Liquid with the listener's own library, for profiling
    /// (Instruments attaches to Lyre while it runs): the albums, an album, the artists,
    /// an artist, search with Apple Music's results, and back to Now Playing.
    @MainActor
    func testATypicalLiquidSession() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-LyrePlayerStyle", "liquid"]
        app.launch()
        func any(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
        func toMenu() {
            for _ in 0..<4 where !any("liquid.menu.albums").exists {
                if any("liquid.back").exists { any("liquid.back").tap() }
                else if any("liquid.library").exists { any("liquid.library").tap() }
                sleep(1)
            }
        }
        sleep(3)
        toMenu()
        XCTAssertTrue(any("liquid.menu.albums").waitForExistence(timeout: 10))

        any("liquid.menu.albums").tap()
        let cover = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'liquid.cover.'")).firstMatch
        XCTAssertTrue(cover.waitForExistence(timeout: 10))
        for _ in 0..<6 { app.swipeUp(velocity: .fast) }
        for _ in 0..<3 { app.swipeDown(velocity: .fast) }
        cover.tap()
        sleep(2)
        app.swipeUp(); app.swipeDown()
        // Playing changes the song, which is when Liquid looks tempos up.
        if any("liquid.album.play").waitForExistence(timeout: 5) {
            any("liquid.album.play").tap()
            sleep(6)
        }
        toMenu()

        any("liquid.menu.artists").tap()
        let artist = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'liquid.artist.'")).firstMatch
        XCTAssertTrue(artist.waitForExistence(timeout: 10))
        for _ in 0..<5 { app.swipeUp(velocity: .fast) }
        for _ in 0..<6 { app.swipeDown(velocity: .fast) }
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'liquid.artist.'")).element(boundBy: 2).tap()
        sleep(3)
        app.swipeUp(); app.swipeUp(); app.swipeDown()
        toMenu()

        any("liquid.menu.search").tap()
        sleep(3)
        app.swipeUp(); app.swipeDown()
        let field = any("liquid.search.field")
        if field.waitForExistence(timeout: 5) {
            field.tap()
            app.typeText("the beatles")
            // Apple Music's results, each row checked against the library.
            XCTAssertTrue(any("liquid.search.catalog").waitForExistence(timeout: 15), "No Apple Music results")
            sleep(2)
            app.swipeUp(); app.swipeUp(); app.swipeDown()
        }
        toMenu()
        sleep(2)
    }
}
