//
//  NowPlayingCreditsUITests.swift
//  LyreUITests
//

import XCTest

/// Every player's Now Playing: the artist's name goes to what the player has of theirs,
/// the album's to its songs (NowPlayingCredits). Liquid's is in LiquidUITests; Spool's
/// links are inside its door, one element to VoiceOver (with Go to Artist / Go to Album).
final class NowPlayingCreditsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testClassicsArtistAndAlbumOpenTheirScreens() throws {
        let app = launch(style: "classic", extra: ["--uitest-open-now-playing"])
        let artist = element(app, "classic.nowPlaying.artist")
        XCTAssertTrue(artist.waitForExistence(timeout: 10), "Classic's Now Playing has no artist link")
        XCTAssertTrue(element(app, "classic.nowPlaying.album").exists, "Classic's Now Playing has no album link")
        shot(app, "classic-credits")
        artist.tap()
        XCTAssertTrue(app.staticTexts["Sample Tape 2"].waitForExistence(timeout: 5), "The artist's screen didn't open")
        app.terminate()

        let again = launch(style: "classic", extra: ["--uitest-open-now-playing"])
        let album = element(again, "classic.nowPlaying.album")
        XCTAssertTrue(album.waitForExistence(timeout: 10))
        album.tap()
        XCTAssertTrue(again.staticTexts["Sample Song 2"].waitForExistence(timeout: 5), "The album's songs didn't open")
    }

    @MainActor
    func testDiscsDisplayOffersTheArtistAndAlbum() throws {
        let app = launch(style: "disc")
        let credits = element(app, "disc.nowPlaying.credits")
        XCTAssertTrue(credits.waitForExistence(timeout: 10), "The display's title offers nothing")
        credits.tap()
        let artist = app.buttons["Lyre"].firstMatch
        XCTAssertTrue(artist.waitForExistence(timeout: 3), "No artist in the display's menu")
        XCTAssertTrue(app.buttons["Sample Tape 1"].firstMatch.exists, "No album in the display's menu")
        shot(app, "disc-credits")
        artist.tap()
        let field = element(app, "shelf.search.field")
        XCTAssertTrue(field.waitForExistence(timeout: 5), "The shelf didn't open")
        XCTAssertEqual(field.value as? String, "Lyre", "The shelf wasn't searched for the artist")
    }

    @MainActor
    func testGramophonesPlateOffersTheArtistAndAlbum() throws {
        let app = launch(style: "gramophone")
        let credits = element(app, "gramophone.nowPlaying.credits")
        XCTAssertTrue(credits.waitForExistence(timeout: 10), "The plate offers nothing")
        credits.tap()
        let album = app.buttons["Sample Tape 1"].firstMatch
        XCTAssertTrue(album.waitForExistence(timeout: 3), "No album in the plate's menu")
        XCTAssertTrue(app.buttons["Lyre"].firstMatch.exists, "No artist in the plate's menu")
        shot(app, "gramophone-credits")
        album.tap()
        XCTAssertTrue(element(app, "gramophone.sleeve.track.0").waitForExistence(timeout: 5),
                      "The album didn't open its sleeve")
    }

    // MARK: - Helpers

    private func launch(style: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest", "--uitest-complete-onboarding", "--uitest-hide-library-errors",
            "-LyrePlayerStyle", style, "-SpoolSampleTapes", "YES", "--spool-sample-queue", "--uitest-now-playing", "--spool-reset-rack",
            "-LyreSpoolModel", "original", "-LyreGramophoneModel", "horn",
        ] + extra
        app.launch()
        let dismiss = app.alerts.buttons["Dismiss"]
        if dismiss.waitForExistence(timeout: 4) { dismiss.tap() }
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        sleep(1)
        let attachment = XCTAttachment(screenshot: app.lyreScreenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
