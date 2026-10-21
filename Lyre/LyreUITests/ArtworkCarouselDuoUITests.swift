//
//  ArtworkCarouselDuoUITests.swift
//  LyreUITests
//

import XCTest

/// The Artwork Carousel's way back, on a phone turned sideways and on an unfolded iPhone
/// Duo. Turned sideways, Back turns the interface upright again. Unfolded, the display
/// stays wide however it's held, so there's no Back: closing the phone is the way back
/// (LYRE-12).
final class ArtworkCarouselDuoUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    /// The classic player, turned sideways into the carousel, with the hinge as given.
    private func launchIntoCarousel(foldedOpen: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-complete-onboarding", "-LyrePlayerStyle", "classic",
                               "--uitest-hide-library-errors"]
            + (foldedOpen ? ["-SpoolFoldPosture", "open"] : [])
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["Scroll wheel"].firstMatch.waitForExistence(timeout: 15))
        // The window going wide is what opens the carousel, as unfolding does.
        XCUIDevice.shared.orientation = .landscapeLeft
        return app
    }

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// LYRE-12: Back showed on an unfolded Duo and led to the wheel in a wide window.
    @MainActor
    func testAnUnfoldedDuosCarouselSaysToCloseThePhoneInsteadOfBack() throws {
        let app = launchIntoCarousel(foldedOpen: true)
        let hint = app.descendants(matching: .any)["carousel.closeHint"].firstMatch
        XCTAssertTrue(hint.waitForExistence(timeout: 10), "The carousel didn't open, or didn't say how to go back")
        XCTAssertFalse(app.buttons["carousel.back"].exists, "An unfolded Duo shouldn't offer Back")
        attachScreenshot(app, named: "carousel-duo-open")

        // An album opened in the carousel still has its own way back to the covers.
        let cover = app.buttons["gatefold.cover"]
        guard cover.waitForExistence(timeout: 5) else { return }  // no albums on this device
        cover.tap()
        let albumBack = app.buttons["carousel.back"]
        XCTAssertTrue(albumBack.waitForExistence(timeout: 5), "An open album lost its back button")
        attachScreenshot(app, named: "carousel-duo-album-open")
        albumBack.tap()
        XCTAssertTrue(hint.waitForExistence(timeout: 5), "Closing the album should go back to the covers")
    }

    @MainActor
    func testAPhoneTurnedSidewaysKeepsBack() throws {
        let app = launchIntoCarousel(foldedOpen: false)
        let back = app.buttons["carousel.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 10), "Turned sideways, the carousel should offer Back")
        XCTAssertFalse(app.descendants(matching: .any)["carousel.closeHint"].exists)
        attachScreenshot(app, named: "carousel-turned")
    }
}
