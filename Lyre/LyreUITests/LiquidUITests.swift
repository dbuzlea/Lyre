//
//  LiquidUITests.swift
//  LyreUITests
//

import XCTest

/// Drives the Liquid player with real touches: the waves and the Up Next handle on Now
/// Playing, the tide, the Big Type library down to an album's page, the droplet back to
/// Now Playing, and the settings.
///
/// Launches with `-SpoolSampleTapes YES` and `--spool-sample-queue`, so there's a library
/// and a queue on a simulator with no music. The sample songs have nothing behind them, so
/// nothing plays — the tests check the player, not the audio.
final class LiquidUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testNowPlayingShowsBothWavesAndItsControls() throws {
        let app = launchLiquid(["--liquid-sample-middle", "-LiquidShot", "nowPlaying"])
        XCTAssertTrue(element(app, "liquid.nowPlaying").waitForExistence(timeout: 10))
        // A touch, in case the waves have already rested away.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        XCTAssertTrue(element(app, "liquid.wave.next").waitForExistence(timeout: 3))
        for id in ["liquid.wave.next", "liquid.wave.previous", "liquid.playPause", "liquid.upNext",
                   "liquid.library", "liquid.settings", "liquid.airplay"] {
            XCTAssertTrue(element(app, id).exists, "\(id) is missing")
        }
        XCTAssertEqual(element(app, "liquid.wave.next").value as? String, "Sample Song 3",
                       "The right wave should carry the next song")
        XCTAssertEqual(element(app, "liquid.wave.previous").value as? String, "Sample Song 1",
                       "The left wave should carry the song before")
        attachScreenshot(app, named: "liquid-now-playing")
    }

    @MainActor
    func testTheWavesRestAwayAndATouchBringsThemBack() throws {
        let app = launchLiquid(["--liquid-sample-middle", "-LiquidShot", "nowPlaying"])
        let next = element(app, "liquid.wave.next")
        XCTAssertTrue(element(app, "liquid.nowPlaying").waitForExistence(timeout: 10))
        // The simulator's library alert can come late; it isn't a touch on the player.
        let dismiss = app.alerts.buttons["Dismiss"]
        if dismiss.waitForExistence(timeout: 8) { dismiss.tap() }
        // Left alone, the waves slip away and leave the cover.
        XCTAssertTrue(waitForDisappearance(next, timeout: 10), "The waves didn't rest away")
        XCTAssertFalse(element(app, "liquid.wave.previous").exists)
        attachScreenshot(app, named: "liquid-resting")
        // A touch anywhere brings them back.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        XCTAssertTrue(next.waitForExistence(timeout: 3), "A touch didn't bring the waves back")
        XCTAssertTrue(element(app, "liquid.wave.previous").exists)
    }

    @MainActor
    func testTappingTheCoverPutsTheWavesAwayAndBack() throws {
        let app = launchLiquid(["--liquid-sample-middle", "-LiquidShot", "nowPlaying"])
        XCTAssertTrue(element(app, "liquid.nowPlaying").waitForExistence(timeout: 10))
        let dismiss = app.alerts.buttons["Dismiss"]
        if dismiss.waitForExistence(timeout: 8) { dismiss.tap() }
        let cover = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        let next = element(app, "liquid.wave.next")
        // Out (or brought out), then a tap puts them away at once…
        if !next.exists { cover.tap() }
        XCTAssertTrue(next.waitForExistence(timeout: 3))
        cover.tap()
        XCTAssertTrue(waitForDisappearance(next, timeout: 3), "A tap didn't put the waves away")
        // …and another brings them back.
        cover.tap()
        XCTAssertTrue(next.waitForExistence(timeout: 3), "A tap didn't bring the waves back")
    }

    @MainActor
    func testDraggingNowPlayingDownGoesBackToTheAlbum() throws {
        let app = launchLiquid(["-LiquidShot", "album"])
        let play = element(app, "liquid.album.play")
        XCTAssertTrue(play.waitForExistence(timeout: 10), "The album didn't open")
        let droplet = element(app, "liquid.droplet")
        XCTAssertTrue(droplet.exists)
        droplet.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)).tap()
        let nowPlaying = element(app, "liquid.nowPlaying")
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 5))
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        top.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        XCTAssertTrue(play.waitForExistence(timeout: 5), "Dragging Now Playing down didn't return to the album")
        XCTAssertFalse(nowPlaying.exists)
    }

    @MainActor
    func testPullingUpNextUpRaisesItLikeASheet() throws {
        let app = launchLiquid(["-LiquidShot", "nowPlaying"])
        let handle = element(app, "liquid.upNext")
        XCTAssertTrue(handle.waitForExistence(timeout: 10))
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        XCTAssertTrue(element(app, "liquid.tide.band.0").waitForExistence(timeout: 5), "Pulling up didn't raise Up Next")
        // And dragged down by its top, it falls away.
        let tide = element(app, "liquid.tide")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.24))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        XCTAssertTrue(waitForDisappearance(tide), "Dragging Up Next down didn't let it fall")
    }

    @MainActor
    func testTheFirstSongHasNoWaveBack() throws {
        let app = launchLiquid(["-LiquidShot", "nowPlaying"])
        XCTAssertTrue(element(app, "liquid.nowPlaying").waitForExistence(timeout: 10))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        XCTAssertTrue(element(app, "liquid.wave.next").waitForExistence(timeout: 3))
        XCTAssertFalse(element(app, "liquid.wave.previous").exists, "There's no song before the first")
    }

    @MainActor
    func testTheBottomHandleRaisesTheTideAndItFallsBack() throws {
        let app = launchLiquid(["-LiquidShot", "nowPlaying"])
        let handle = element(app, "liquid.upNext")
        XCTAssertTrue(handle.waitForExistence(timeout: 10))
        handle.tap()
        let tide = element(app, "liquid.tide")
        XCTAssertTrue(tide.waitForExistence(timeout: 5), "Up Next didn't rise")
        XCTAssertTrue(element(app, "liquid.tide.band.0").waitForExistence(timeout: 5), "The tide has no songs")
        XCTAssertTrue(element(app, "liquid.tide.clear").exists, "The tide has no Clear")
        sleep(1)
        attachScreenshot(app, named: "liquid-tide")
        element(app, "liquid.tide.close").tap()
        XCTAssertTrue(waitForDisappearance(tide), "The tide didn't fall back")
    }

    /// LYRE-14: an album's page has a button at its top right that queues the album.
    @MainActor
    func testAnAlbumsQueueButtonOffersPlayNextAndAddToQueue() throws {
        let app = launchLiquid(["-LiquidShot", "library"])
        let albums = element(app, "liquid.menu.albums")
        XCTAssertTrue(albums.waitForExistence(timeout: 10), "The menu has no albums")
        albums.tap()
        let cover = element(app, "liquid.cover.sample-1")
        XCTAssertTrue(cover.waitForExistence(timeout: 5), "Albums didn't open")
        cover.tap()

        let queueButton = element(app, "liquid.album.queueMenu")
        XCTAssertTrue(queueButton.waitForExistence(timeout: 5), "The album has no queue button")
        queueButton.tap()
        let playNext = app.buttons["Play Next"]
        let addToQueue = app.buttons["Add to Queue"]
        XCTAssertTrue(playNext.waitForExistence(timeout: 3), "No Play Next in the queue menu")
        XCTAssertTrue(addToQueue.exists, "No Add to Queue in the queue menu")
        attachScreenshot(app, named: "liquid-album-queue-menu")

        addToQueue.tap()
        let notice = element(app, "liquid.notice")
        XCTAssertTrue(notice.waitForExistence(timeout: 5), "Adding the album to the queue said nothing")
        attachScreenshot(app, named: "liquid-album-queued")
    }

    @MainActor
    func testTheLibraryLeadsToAnAlbumAndTheDropletBackToNowPlaying() throws {
        let app = launchLiquid(["-LiquidShot", "library"])
        let albums = element(app, "liquid.menu.albums")
        XCTAssertTrue(albums.waitForExistence(timeout: 10), "The menu has no albums")
        for id in ["liquid.menu.artists", "liquid.menu.playlists", "liquid.menu.podcasts", "liquid.menu.search"] {
            XCTAssertTrue(element(app, id).exists, "\(id) is missing")
        }
        attachScreenshot(app, named: "liquid-menu")
        albums.tap()

        let cover = element(app, "liquid.cover.sample-1")
        XCTAssertTrue(cover.waitForExistence(timeout: 5), "Albums didn't open")
        XCTAssertTrue(element(app, "liquid.search.field").exists, "The grid has no search")
        cover.tap()
        XCTAssertTrue(element(app, "liquid.album.play").waitForExistence(timeout: 5), "The album has no Play")
        XCTAssertTrue(element(app, "liquid.album.shuffle").exists)
        XCTAssertTrue(element(app, "liquid.album.track.0").exists, "The album has no songs")
        sleep(1)
        attachScreenshot(app, named: "liquid-album")

        element(app, "liquid.back").tap()
        XCTAssertTrue(cover.waitForExistence(timeout: 5), "Back didn't return to the grid")

        let droplet = element(app, "liquid.droplet")
        XCTAssertTrue(droplet.exists, "No droplet for what's playing")
        droplet.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)).tap()
        XCTAssertTrue(element(app, "liquid.nowPlaying").waitForExistence(timeout: 5),
                      "The droplet didn't flood into Now Playing")
    }

    @MainActor
    func testSwipingASongRightOffersPlayNextAndAddToQueue() throws {
        let app = launchLiquid(["-LiquidShot", "album"])
        let song = element(app, "liquid.album.track.1")
        XCTAssertTrue(song.waitForExistence(timeout: 10), "The album didn't open")
        song.swipeRight()
        let playNext = app.buttons["Play Next"]
        XCTAssertTrue(playNext.waitForExistence(timeout: 3), "Swiping right didn't offer Play Next")
        XCTAssertTrue(app.buttons["Add to Queue"].exists, "Swiping right didn't offer Add to Queue")
        attachScreenshot(app, named: "liquid-swipe-actions")
        app.buttons["Add to Queue"].tap()
        XCTAssertTrue(element(app, "liquid.notice").waitForExistence(timeout: 5), "Queueing said nothing")
    }

    @MainActor
    func testTheMenuOpensSongsAndTheRecentLists() throws {
        let app = launchLiquid(["-LiquidShot", "library"])
        let songs = element(app, "liquid.menu.songs")
        XCTAssertTrue(songs.waitForExistence(timeout: 10), "The menu has no songs")
        XCTAssertTrue(element(app, "liquid.menu.recentlyPlayed").exists, "The menu has no recently played")
        XCTAssertTrue(element(app, "liquid.menu.recentlyAdded").exists, "The menu has no recently added")
        songs.tap()
        let first = element(app, "liquid.songs.track.0")
        XCTAssertTrue(first.waitForExistence(timeout: 5), "Songs didn't open")
        XCTAssertTrue(element(app, "liquid.songs.play").exists)
        XCTAssertTrue(element(app, "liquid.songs.shuffle").exists)
        first.swipeRight()
        XCTAssertTrue(app.buttons["Play Next"].waitForExistence(timeout: 3), "A song doesn't swipe to queue")
        attachScreenshot(app, named: "liquid-songs")
        app.buttons["Add to Queue"].tap()
        XCTAssertTrue(element(app, "liquid.notice").waitForExistence(timeout: 5), "Queueing said nothing")

        element(app, "liquid.back").tap()
        let recent = element(app, "liquid.menu.recentlyAdded")
        XCTAssertTrue(recent.waitForExistence(timeout: 5), "Back didn't return to the menu")
        recent.tap()
        XCTAssertTrue(element(app, "liquid.back").waitForExistence(timeout: 5), "Recently added didn't open")
    }

    @MainActor
    func testTurningThePhoneOpensTheArtworkCarouselAndUprightComesBack() throws {
        let app = launchLiquid(["-LiquidShot", "nowPlaying"])
        let nowPlaying = element(app, "liquid.nowPlaying")
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 10))
        defer { XCUIDevice.shared.orientation = .portrait }

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(element(app, "gatefold.trace").waitForExistence(timeout: 8),
                      "Turning the phone didn't open the Artwork Carousel")
        sleep(1)
        attachScreenshot(app, named: "liquid-carousel")

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 8), "Turning upright didn't come back to Liquid")
        XCTAssertFalse(element(app, "gatefold.trace").exists, "The carousel stayed open upright")
    }

    @MainActor
    func testTheSongsNameOpensItsAlbum() throws {
        let app = launchLiquid(["-LiquidShot", "nowPlaying"])
        let name = element(app, "liquid.nowPlaying")
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        XCTAssertTrue(element(app, "liquid.album.play").waitForExistence(timeout: 5),
                      "Tapping the song's name didn't open its album")
    }

    @MainActor
    func testHoldingACoverOffersToQueueIt() throws {
        let app = launchLiquid(["-LiquidShot", "albums"])
        let cover = element(app, "liquid.cover.sample-1")
        XCTAssertTrue(cover.waitForExistence(timeout: 10))
        cover.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Play Next"].waitForExistence(timeout: 3), "Holding a cover didn't offer Play Next")
        XCTAssertTrue(app.buttons["Add to Queue"].exists)
        app.buttons["Add to Queue"].tap()
        XCTAssertTrue(element(app, "liquid.notice").waitForExistence(timeout: 5), "Queueing the album said nothing")
    }

    @MainActor
    func testSettingsHaveTheTutorial() throws {
        let app = launchLiquid(["-LiquidShot", "nowPlaying"])
        let settings = element(app, "liquid.settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let lesson = element(app, "liquid.tour.lesson")
        XCTAssertTrue(lesson.waitForExistence(timeout: 5), "Settings have no tutorial")
        element(app, "liquid.tour.next").tap()
        expectation(for: NSPredicate(format: "label CONTAINS 'Just the Cover'"), evaluatedWith: lesson)
        waitForExpectations(timeout: 3)
        sleep(2)
        attachScreenshot(app, named: "liquid-tutorial")
    }

    @MainActor
    func testSwitchingToAnotherPlayerPlaysTheHandOverAndArrives() throws {
        let app = launchLiquid(["-LiquidShot", "nowPlaying"])
        let settings = element(app, "liquid.settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let disc = element(app, "liquid.settings.disc")
        XCTAssertTrue(element(app, "liquid.settings.done").waitForExistence(timeout: 5))
        for _ in 0..<4 where !disc.exists { app.swipeUp() }
        disc.tap()
        // The old player bows out, the song flies over, and the Disc comes in.
        XCTAssertTrue(element(app, "disc.lid").waitForExistence(timeout: 8), "The Disc never arrived")
        XCTAssertTrue(element(app, "disc.playPause").waitForExistence(timeout: 3))
        XCTAssertFalse(element(app, "liquid.nowPlaying").exists, "Liquid stayed on screen")
        attachScreenshot(app, named: "switched-to-disc")
    }

    @MainActor
    func testSwipingTurnsTheTutorialsLessons() throws {
        let app = launchLiquid(["-LiquidShot", "nowPlaying"])
        let settings = element(app, "liquid.settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let lesson = element(app, "liquid.tour.lesson")
        XCTAssertTrue(lesson.waitForExistence(timeout: 5), "Settings have no tutorial")
        XCTAssertTrue(lesson.label.contains("Change Songs"), "First lesson was \(lesson.label)")
        lesson.swipeLeft()
        expectation(for: NSPredicate(format: "label CONTAINS 'Just the Cover'"), evaluatedWith: lesson)
        waitForExpectations(timeout: 3)
        lesson.swipeRight()
        expectation(for: NSPredicate(format: "label CONTAINS 'Change Songs'"), evaluatedWith: lesson)
        waitForExpectations(timeout: 3)
    }

    @MainActor
    func testSearchFindsAnAlbum() throws {
        let app = launchLiquid(["-LiquidShot", "library"])
        let search = element(app, "liquid.menu.search")
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        let field = element(app, "liquid.search.field")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Tape 4")
        XCTAssertTrue(element(app, "Sample Tape 4").waitForExistence(timeout: 5) ||
                      app.staticTexts["Sample Tape 4"].waitForExistence(timeout: 2),
                      "Search didn't find the album")
    }

    @MainActor
    func testSettingsOpenAndOfferTheOtherPlayers() throws {
        let app = launchLiquid(["-LiquidShot", "nowPlaying"])
        let settings = element(app, "liquid.settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        let dismiss = app.alerts.buttons["Dismiss"]
        if dismiss.waitForExistence(timeout: 3) {
            dismiss.tap()
            sleep(1)
        }
        settings.tap()
        let done = element(app, "liquid.settings.done")
        if !done.waitForExistence(timeout: 3) {
            if dismiss.exists { dismiss.tap(); sleep(1) }
            settings.tap()
        }
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Settings didn't open")
        // Below the tutorial and playback: scroll down to it.
        let disc = element(app, "liquid.settings.disc")
        for _ in 0..<4 where !disc.exists { app.swipeUp() }
        XCTAssertTrue(disc.exists, "No way to switch to the Disc")
        // Just above the players: the cover's ripple, on until turned off.
        let ripple = element(app, "liquid.settings.ripple")
        XCTAssertTrue(ripple.exists, "No way to turn the cover's ripple off")
        XCTAssertEqual(ripple.value as? String, "1", "The ripple isn't on to begin with")
        // And looking up tempos from Deezer, on until turned off.
        let tempos = element(app, "liquid.settings.tempos")
        XCTAssertTrue(tempos.exists, "No way to turn tempo lookups off")
        XCTAssertEqual(tempos.value as? String, "1", "Tempo lookups aren't on to begin with")
        attachScreenshot(app, named: "liquid-settings-ripple")
        done.tap()
    }

    // MARK: - One at a Time

    func testTheStackFlipsThroughCoversAndOneSwingsOpen() throws {
        let app = launchLiquid(["-LiquidShot", "albums"])
        let layout = element(app, "liquid.layout")
        XCTAssertTrue(layout.waitForExistence(timeout: 10), "No layout switch")
        layout.tap()
        let top = element(app, "liquid.stack.top")
        XCTAssertTrue(top.waitForExistence(timeout: 10), "No stack of covers")
        XCTAssertEqual(top.value as? String, "1 of 12")

        // Swiped left, the next cover comes up; right, the one before.
        top.swipeLeft()
        sleep(1)
        XCTAssertEqual(element(app, "liquid.stack.top").value as? String, "2 of 12")
        element(app, "liquid.stack.top").swipeRight()
        sleep(1)
        XCTAssertEqual(element(app, "liquid.stack.top").value as? String, "1 of 12")

        // Tapped, it swings open: Play, Shuffle and the songs.
        element(app, "liquid.stack.top").tap()
        usleep(250_000)
        attachScreenshot(app, named: "fold-swinging")
        let play = element(app, "liquid.fold.play")
        XCTAssertTrue(play.waitForExistence(timeout: 5), "The cover didn't open")
        XCTAssertTrue(element(app, "liquid.fold.track.0").exists, "No songs inside")
        XCTAssertTrue(element(app, "liquid.fold.shuffle").exists)
        attachScreenshot(app, named: "fold-open")

        element(app, "liquid.fold.close").tap()
        XCTAssertTrue(waitForDisappearance(play), "The cover didn't close")

        // And back to every cover at once.
        element(app, "liquid.layout").tap()
        XCTAssertTrue(waitForDisappearance(element(app, "liquid.stack.top")), "The grid didn't come back")
    }

    /// On a closed iPhone Duo's short screen, the grid's letter index keeps below the name
    /// and search, level with the covers, instead of running up into the corner.
    func testTheGridsLetterIndexStartsBelowTheSearchOnAClosedDuo() throws {
        let app = launchLiquid(["-LiquidShot", "albums", "-SpoolFoldPosture", "closed"])
        let layout = element(app, "liquid.layout")
        XCTAssertTrue(layout.waitForExistence(timeout: 10), "No layout switch")
        if element(app, "liquid.stack.top").waitForExistence(timeout: 2) { layout.tap() }
        let index = element(app, "liquid.index")
        XCTAssertTrue(index.waitForExistence(timeout: 10), "No letter index on the grid")
        sleep(1)
        attachScreenshot(app, named: "duo-closed-grid-index")

        let search = element(app, "liquid.search.field")
        XCTAssertTrue(search.exists)
        XCTAssertGreaterThan(index.frame.minY, search.frame.maxY, "The index runs up past the search")
        XCTAssertGreaterThan(index.frame.minY, layout.frame.maxY, "The index runs up past the layout switch")
        XCTAssertLessThan(index.frame.maxY, app.windows.firstMatch.frame.maxY, "The index runs off the bottom")
    }

    func testASongInTheStackOpensOntoItsAlbum() throws {
        let app = launchLiquid(["-LiquidShot", "songs"])
        let layout = element(app, "liquid.layout")
        XCTAssertTrue(layout.waitForExistence(timeout: 10), "No layout switch")
        layout.tap()
        let top = element(app, "liquid.stack.top")
        XCTAssertTrue(top.waitForExistence(timeout: 10), "No stack of songs")
        top.tap()
        XCTAssertTrue(element(app, "liquid.fold.playNext").waitForExistence(timeout: 5), "The song didn't open")
        XCTAssertTrue(element(app, "liquid.fold.addToQueue").exists)
        XCTAssertTrue(element(app, "liquid.fold.track.0").waitForExistence(timeout: 5), "No album songs inside")
        attachScreenshot(app, named: "fold-song")
        element(app, "liquid.fold.close").tap()
        XCTAssertTrue(waitForDisappearance(element(app, "liquid.fold.play")), "The song didn't close")
        // Left as every song at once, for the tests after.
        layout.tap()
        XCTAssertTrue(waitForDisappearance(element(app, "liquid.stack.top")), "The list didn't come back")
    }

    func testEachListKeepsItsOwnLayout() throws {
        let app = launchLiquid(["-LiquidShot", "albums"])
        let layout = element(app, "liquid.layout")
        XCTAssertTrue(layout.waitForExistence(timeout: 10), "No layout switch")
        layout.tap()
        XCTAssertTrue(element(app, "liquid.stack.top").waitForExistence(timeout: 5), "The albums didn't stack")

        // The songs are still a list.
        element(app, "liquid.back").tap()
        let songs = element(app, "liquid.menu.songs")
        XCTAssertTrue(songs.waitForExistence(timeout: 5))
        songs.tap()
        XCTAssertTrue(element(app, "liquid.songs.track.0").waitForExistence(timeout: 5), "The songs weren't a list")
        XCTAssertFalse(element(app, "liquid.stack.top").exists, "The songs took the albums' layout")

        // And the albums are still one at a time.
        element(app, "liquid.back").tap()
        let albums = element(app, "liquid.menu.albums")
        XCTAssertTrue(albums.waitForExistence(timeout: 5))
        albums.tap()
        XCTAssertTrue(element(app, "liquid.stack.top").waitForExistence(timeout: 5), "The albums forgot their layout")

        // Held, a cover in the stack offers what it does in the grid.
        element(app, "liquid.stack.top").press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Play Next"].waitForExistence(timeout: 3), "Holding a stacked cover didn't offer Play Next")
        app.buttons["Add to Queue"].tap()
        XCTAssertTrue(element(app, "liquid.notice").waitForExistence(timeout: 5), "Queueing the album said nothing")

        // Left as every cover at once, for the tests after.
        element(app, "liquid.layout").tap()
        XCTAssertTrue(waitForDisappearance(element(app, "liquid.stack.top")), "The grid didn't come back")
    }

    func testTheStackOpensOnTheCoverItWasLeftOn() throws {
        let app = launchLiquid(["-LiquidShot", "albums"])
        let layout = element(app, "liquid.layout")
        XCTAssertTrue(layout.waitForExistence(timeout: 10), "No layout switch")
        layout.tap()
        let top = element(app, "liquid.stack.top")
        XCTAssertTrue(top.waitForExistence(timeout: 5), "The albums didn't stack")
        XCTAssertEqual(top.value as? String, "1 of 12")
        top.swipeLeft()
        sleep(1)
        element(app, "liquid.stack.top").swipeLeft()
        sleep(1)
        XCTAssertEqual(element(app, "liquid.stack.top").value as? String, "3 of 12")

        // Away and back: still on the third.
        element(app, "liquid.back").tap()
        let albums = element(app, "liquid.menu.albums")
        XCTAssertTrue(albums.waitForExistence(timeout: 5))
        albums.tap()
        let again = element(app, "liquid.stack.top")
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        XCTAssertEqual(again.value as? String, "3 of 12", "The stack started over")

        // Left as it was found, for the tests after: the first cover, every cover at once.
        again.swipeRight()
        sleep(1)
        element(app, "liquid.stack.top").swipeRight()
        sleep(1)
        XCTAssertEqual(element(app, "liquid.stack.top").value as? String, "1 of 12")
        element(app, "liquid.layout").tap()
        XCTAssertTrue(waitForDisappearance(element(app, "liquid.stack.top")), "The grid didn't come back")
    }

    func testTheTutorialTeachesOneAtATime() throws {
        let app = launchLiquid(["-LiquidShot", "nowPlaying"])
        let settings = element(app, "liquid.settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let lesson = element(app, "liquid.tour.lesson")
        XCTAssertTrue(lesson.waitForExistence(timeout: 5), "Settings have no tutorial")
        for _ in 0..<6 where !lesson.label.contains("One at a Time") {
            element(app, "liquid.tour.next").tap()
            usleep(400_000)
        }
        XCTAssertTrue(lesson.label.contains("One at a Time"), "No lesson for the stack: \(lesson.label)")
        sleep(1)
        attachScreenshot(app, named: "tour-stacked")
        sleep(3)
        attachScreenshot(app, named: "tour-open")
    }

    // MARK: - iPhone Duo

    /// Opened with the fold across the middle: the waves above, Up Next's pool below,
    /// which gives way to the library and back.
    @MainActor
    func testAnOpenDuoHasThePoolUnderTheWaves() throws {
        let app = launchLiquid(["-SpoolFoldPosture", "open", "-LyreHingeAngle", "110"])
        let pool = element(app, "liquid.pool")
        XCTAssertTrue(pool.waitForExistence(timeout: 10), "No pool under the waves")
        XCTAssertTrue(element(app, "liquid.nowPlaying").exists, "No Now Playing above the fold")
        XCTAssertTrue(element(app, "liquid.pool.drop.0").exists, "Up Next isn't in the pool")
        sleep(1)
        attachScreenshot(app, named: "duo-pool")

        // Flicked up, a drop rises into the wave: it plays next.
        let second = element(app, "liquid.pool.drop.2")
        XCTAssertTrue(second.exists)
        second.swipeUp()
        XCTAssertTrue(element(app, "liquid.notice").waitForExistence(timeout: 5), "Flicking it up said nothing")

        // The library in the pool's place, and back.
        element(app, "liquid.pool.library").tap()
        XCTAssertTrue(element(app, "liquid.menu.albums").waitForExistence(timeout: 5), "The library didn't come up")
        sleep(1)
        attachScreenshot(app, named: "duo-library-below")
        element(app, "liquid.pool.back").tap()
        XCTAssertTrue(pool.waitForExistence(timeout: 5), "The pool didn't come back")
    }

    /// Each artist has a rounded-square photo beside their name (here their album's
    /// cover, as the simulator has no Apple Music), and their page opens on it, large.
    @MainActor
    func testArtistsHavePhotosAndTheirPageOpensOnOne() throws {
        let app = launchLiquid(["-LiquidShot", "artists"])
        let row = element(app, "liquid.artist.Lyre")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "No artist in the list")
        XCTAssertGreaterThan(row.frame.height, 60, "The row has no room for a photo")
        sleep(1)
        attachScreenshot(app, named: "liquid-artists")
        row.tap()
        let photo = element(app, "liquid.artist.photo")
        XCTAssertTrue(photo.waitForExistence(timeout: 5), "The artist's page has no photo")
        XCTAssertGreaterThan(photo.frame.width, 200, "The photo isn't large")
        XCTAssertTrue(element(app, "liquid.cover.sample-1").waitForExistence(timeout: 5), "The artist's albums are missing")
        sleep(1)
        attachScreenshot(app, named: "liquid-artist-page")
    }

    // MARK: - iPhone Duo held as a book: Now Playing and the bubbles

    /// Only the Duo's inner screen turns Liquid sideways, which the simulator can't do:
    /// the book layout is asked for in an upright window instead.
    private func launchBook(_ extra: [String] = []) -> XCUIApplication {
        launchLiquid(["-SpoolFoldPosture", "open", "-LiquidDuoLayout", "book"] + extra)
    }

    /// Opened and held wide, as a real Duo is, without asking for the layout: Now Playing
    /// beside the bubbles, not the Artwork Carousel, which a wide window used to open
    /// over them. Only a simulator whose window turns wide can show it (an iPhone 18 Pro
    /// turned sideways, with the hinge reported open); the Duo's can't, so it's skipped.
    @MainActor
    func testAnOpenDuoHeldWideShowsTheBubblesNotTheCarousel() throws {
        defer { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launchLiquid(["-SpoolFoldPosture", "open"])
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        sleep(2)
        guard window.frame.width > window.frame.height else {
            throw XCTSkip("This simulator's window doesn't turn wide")
        }
        XCTAssertTrue(element(app, "liquid.bubbles").waitForExistence(timeout: 8),
                      "Opened wide, Liquid didn't show the bubbles")
        XCTAssertTrue(element(app, "liquid.nowPlaying").exists, "No Now Playing beside the bubbles")
        XCTAssertFalse(element(app, "gatefold.trace").exists, "The Artwork Carousel opened over them")
        attachScreenshot(app, named: "duo-open-wide")
    }

    /// Now Playing on the left page, the bubbles on the right, with their tabs.
    @MainActor
    func testAnOpenDuoHeldAsABookHasNowPlayingBesideTheBubbles() throws {
        let app = launchBook()
        let bubble = element(app, "liquid.bubble.sample-1")
        XCTAssertTrue(bubble.waitForExistence(timeout: 10), "No bubbles on the right page")
        let nowPlaying = element(app, "liquid.nowPlaying")
        XCTAssertTrue(nowPlaying.exists, "No Now Playing on the left page")
        XCTAssertLessThan(nowPlaying.frame.midX, bubble.frame.midX, "Now Playing isn't left of the bubbles")
        for tab in ["albums", "playlists", "podcasts"] {
            XCTAssertTrue(element(app, "liquid.bubbles.tab.\(tab)").exists, "No \(tab) tab")
        }
        XCTAssertFalse(element(app, "liquid.bubbles.tab.artists").exists, "There's an artists tab")
        sleep(1)
        attachScreenshot(app, named: "duo-book-bubbles")

        element(app, "liquid.bubbles.tab.playlists").tap()
        XCTAssertTrue(element(app, "liquid.bubble.mixtape:sample-mix-0").waitForExistence(timeout: 3), "No playlist bubbles")
        element(app, "liquid.bubbles.tab.podcasts").tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'liquid.bubble.podcast:'"))
            .firstMatch.waitForExistence(timeout: 3), "No show bubbles")
        sleep(1)
        attachScreenshot(app, named: "duo-book-podcasts")
    }

    /// Tapped, an album's bubble is taken into Now Playing and plays (the samples have
    /// nothing behind them, so playing says so).
    @MainActor
    func testTappingABubblePlaysIt() throws {
        let app = launchBook()
        let bubble = element(app, "liquid.bubble.sample-2")
        XCTAssertTrue(bubble.waitForExistence(timeout: 10))
        bubble.tap()
        XCTAssertTrue(element(app, "liquid.notice").waitForExistence(timeout: 6), "Tapping the bubble didn't play it")
    }

    /// Dragged across the fold, a bubble is taken in and plays.
    @MainActor
    func testDraggingABubbleIntoNowPlayingPlaysIt() throws {
        let app = launchBook()
        let bubble = element(app, "liquid.bubble.sample-2")
        let nowPlaying = element(app, "liquid.nowPlaying")
        XCTAssertTrue(bubble.waitForExistence(timeout: 10))
        let start = bubble.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: nowPlaying.frame.midX * 0.6, dy: bubble.frame.midY))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertTrue(element(app, "liquid.notice").waitForExistence(timeout: 6), "Dragging the bubble in didn't play it")
    }

    /// A short drag that doesn't reach the fold floats back and plays nothing.
    @MainActor
    func testABubbleLetGoShortOfTheFoldFloatsBack() throws {
        let app = launchBook()
        let bubble = element(app, "liquid.bubble.sample-2")
        XCTAssertTrue(bubble.waitForExistence(timeout: 10))
        let before = bubble.frame
        let start = bubble.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -24, dy: 0)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)
        sleep(1)
        XCTAssertFalse(element(app, "liquid.notice").exists, "A short drag played it")
        XCTAssertEqual(bubble.frame.midX, before.midX, accuracy: 8, "The bubble didn't float back")
    }

    /// Held, a bubble opens its page to choose a song; back from it, the bubbles again.
    @MainActor
    func testHoldingABubbleOpensItsPage() throws {
        let app = launchBook()
        let bubble = element(app, "liquid.bubble.sample-1")
        XCTAssertTrue(bubble.waitForExistence(timeout: 10))
        bubble.press(forDuration: 0.8)
        XCTAssertTrue(element(app, "liquid.album.play").waitForExistence(timeout: 5), "Holding didn't open the album")
        XCTAssertFalse(element(app, "liquid.notice").exists, "Holding played it")
        sleep(1)
        attachScreenshot(app, named: "duo-book-album")
        element(app, "liquid.back").tap()
        XCTAssertTrue(bubble.waitForExistence(timeout: 5), "Back didn't bring the bubbles back")
    }

    /// A show's bubble opens its episodes when tapped; it plays nothing by itself.
    @MainActor
    func testAShowsBubbleOpensItsEpisodes() throws {
        let app = launchBook()
        XCTAssertTrue(element(app, "liquid.bubbles.tab.podcasts").waitForExistence(timeout: 10))
        element(app, "liquid.bubbles.tab.podcasts").tap()
        let show = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'liquid.bubble.podcast:'"))
            .firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 5))
        show.tap()
        XCTAssertTrue(element(app, "liquid.album.play").waitForExistence(timeout: 5), "Tapping a show didn't open it")
        XCTAssertFalse(element(app, "liquid.notice").exists, "Tapping a show played it")
    }

    /// Now Playing's library button swaps the bubbles for the whole library, and back.
    @MainActor
    func testTheLibraryButtonSwapsTheBubblesForTheLibrary() throws {
        let app = launchBook()
        XCTAssertTrue(element(app, "liquid.bubbles").waitForExistence(timeout: 10))
        element(app, "liquid.library").tap()
        XCTAssertTrue(element(app, "liquid.menu.albums").waitForExistence(timeout: 5), "No library")
        XCTAssertFalse(element(app, "liquid.bubbles").exists)
        element(app, "liquid.bubbles.back").tap()
        XCTAssertTrue(element(app, "liquid.bubbles").waitForExistence(timeout: 5), "The bubbles didn't come back")
    }

    /// A bubble held near the fold: Now Playing's edge reaching out for it.
    @MainActor
    func testNowPlayingReachesForABubbleNearTheFold() throws {
        let app = launchBook(["-LiquidBubbleShot", "30"])
        XCTAssertTrue(element(app, "liquid.bubbles").waitForExistence(timeout: 10))
        sleep(3)
        attachScreenshot(app, named: "duo-book-reaching")
    }

    /// Stood half open and left alone: the visualizer, until it's touched.
    @MainActor
    func testTheVisualizerGivesWayToATouch() throws {
        let app = launchLiquid(["-SpoolFoldPosture", "open", "-LyreHingeAngle", "100", "--liquid-visualizer"])
        let visualizer = element(app, "liquid.visualizer")
        XCTAssertTrue(visualizer.waitForExistence(timeout: 10), "No visualizer")
        sleep(1)
        attachScreenshot(app, named: "duo-visualizer")
        visualizer.tap()
        XCTAssertTrue(waitForDisappearance(visualizer), "A touch didn't bring the player back")
    }

    // MARK: - Helpers

    /// The cover ripples like water on a speaker (see LiquidRipple). Live, it never holds
    /// still and UI tests turn it off, so `-LiquidRippleShot` draws one moment of it: the
    /// middle of the cover has to come out different from the same cover without it.
    @MainActor
    func testTheNowPlayingCoverRipples() throws {
        var middles: [Data] = []
        for shot in [false, true] {
            let app = launchLiquid(["--liquid-sample-middle", "-LiquidShot", "nowPlaying"]
                                   + (shot ? ["-LiquidRippleShot", "YES"] : []))
            XCTAssertTrue(element(app, "liquid.nowPlaying").waitForExistence(timeout: 10))
            sleep(1)
            let screenshot = app.screenshot()
            attachScreenshot(app, named: shot ? "liquid-cover-rippling" : "liquid-cover-still")
            middles.append(try XCTUnwrap(middle(of: screenshot.image)))
            app.terminate()
        }
        XCTAssertNotEqual(middles[0], middles[1], "The ripples didn't change the cover")
    }

    /// Turned off in Settings (here by launch argument), even the still moment of ripples
    /// isn't drawn: the cover comes out as it is.
    @MainActor
    func testTurningTheRippleOffKeepsTheCoverStill() throws {
        var middles: [Data] = []
        for off in [false, true] {
            let app = launchLiquid(["--liquid-sample-middle", "-LiquidShot", "nowPlaying"]
                                   + (off ? ["-LiquidRippleShot", "YES", "-LyreLiquidRipple", "NO"] : []))
            XCTAssertTrue(element(app, "liquid.nowPlaying").waitForExistence(timeout: 10))
            sleep(1)
            let screenshot = app.screenshot()
            attachScreenshot(app, named: off ? "liquid-cover-ripple-off" : "liquid-cover-plain")
            middles.append(try XCTUnwrap(middle(of: screenshot.image)))
            app.terminate()
        }
        XCTAssertEqual(middles[0], middles[1], "The ripples showed though they were turned off")
    }

    /// The pixels of the middle of a screenshot, clear of the clock and the side waves.
    private func middle(of image: UIImage) -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        let w = CGFloat(cgImage.width), h = CGFloat(cgImage.height)
        guard let crop = cgImage.cropping(to: CGRect(x: w * 0.3, y: h * 0.3, width: w * 0.4, height: h * 0.3)),
              let data = crop.dataProvider?.data else { return nil }
        return data as Data
    }

    private func launchLiquid(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "--uitest", "--uitest-complete-onboarding",
            "-LyrePlayerStyle", "liquid",
            "-SpoolSampleTapes", "YES",
            "--spool-sample-queue",
        ] + extra
        app.launch()
        // The simulator's library alert can take a while to come; drags under it go nowhere.
        let dismiss = app.alerts.buttons["Dismiss"]
        if dismiss.waitForExistence(timeout: 8) {
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
