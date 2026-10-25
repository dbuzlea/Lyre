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
}
