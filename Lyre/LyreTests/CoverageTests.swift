//
//  CoverageTests.swift
//  LyreTests
//
//  Parts of Lyre that had no tests: moving subscriptions between podcast apps, the
//  podcast models, onboarding's path for each player, screen sizes, themes, saved
//  episodes and the stream player.
//

import Testing
import Foundation
import SwiftUI
import MusicKit
import MediaPlayer
@testable import Lyre

private func feedShow(_ url: String = "https://a.lyre.test/f.xml", title: String = "Show",
                      artwork: URL? = nil, episodes: [FeedEpisode]) -> FeedShow {
    FeedShow(feedURL: URL(string: url)!, title: title, author: nil, artworkURL: artwork,
             episodes: episodes, lastRefreshed: .now)
}

private func feedEpisode(_ guid: String, duration: TimeInterval? = 600, artwork: URL? = nil) -> FeedEpisode {
    FeedEpisode(guid: guid, title: "Episode \(guid)", audioURL: URL(string: "https://cdn.lyre.test/\(guid).mp3")!,
                published: nil, duration: duration, artworkURL: artwork)
}

// MARK: - OPML

@Suite("OPML")
struct OPMLTests {

    @Test func feedsAreReadInOrderWithoutRepeats() {
        let opml = """
        <?xml version="1.0"?>
        <opml version="2.0"><body>
          <outline text="Group">
            <outline type="rss" text="A" xmlUrl="https://a.lyre.test/feed"/>
            <outline type="rss" text="B" xmlUrl="  https://b.lyre.test/feed  "/>
          </outline>
          <outline type="rss" text="A again" xmlUrl="https://a.lyre.test/feed"/>
          <outline type="rss" text="Lowercase attribute" xmlurl="http://c.lyre.test/feed"/>
        </body></opml>
        """
        #expect(OPML.feedURLs(in: Data(opml.utf8)).map(\.absoluteString)
                == ["https://a.lyre.test/feed", "https://b.lyre.test/feed", "http://c.lyre.test/feed"])
    }

    @Test func onlyWebFeedsCount() {
        let opml = """
        <opml><body>
          <outline text="Folder"/>
          <outline xmlUrl="file:///etc/passwd"/>
          <outline xmlUrl="ftp://d.lyre.test/feed"/>
          <outline xmlUrl=""/>
          <outline xmlUrl="https://e.lyre.test/feed"/>
        </body></opml>
        """
        #expect(OPML.feedURLs(in: Data(opml.utf8)).map(\.absoluteString) == ["https://e.lyre.test/feed"])
    }

    @Test func aFileThatIsntOPMLHasNoFeeds() {
        #expect(OPML.feedURLs(in: Data()).isEmpty)
        #expect(OPML.feedURLs(in: Data("just some text".utf8)).isEmpty)
        #expect(OPML.feedURLs(in: Data([0xFF, 0xD8, 0xFF, 0xE0])).isEmpty)  // a JPEG picked by mistake
    }

    @Test func anExportReadsBackAsTheSameFeeds() {
        let feeds = [
            feedShow("https://a.lyre.test/feed?x=1&y=2", title: #"Rock & Roll "Live" <Uncut>"#, episodes: []),
            feedShow("https://b.lyre.test/feed", title: "Plain", episodes: []),
        ]
        let document = OPML.document(for: feeds)
        #expect(document.contains("&amp;") && document.contains("&quot;") && document.contains("&lt;"))
        #expect(OPML.feedURLs(in: Data(document.utf8)) == feeds.map(\.feedURL))
    }

    @Test func anExportWithNoSubscriptionsIsStillAValidFile() {
        let document = OPML.document(for: [])
        #expect(document.hasPrefix("<?xml"))
        #expect(OPML.feedURLs(in: Data(document.utf8)).isEmpty)
    }
}

// MARK: - Podcast Models

@Suite("Podcast models")
@MainActor
struct PodcastModelTests {

    @Test func aStreamedEpisodeTakesItsShowsArtworkWhenItHasNone() {
        let showArt = URL(string: "https://img.lyre.test/show.jpg")!
        let ownArt = URL(string: "https://img.lyre.test/ep.jpg")!
        let show = PodcastShow(feed: feedShow(artwork: showArt, episodes: [
            feedEpisode("1"), feedEpisode("2", artwork: ownArt),
        ]))
        #expect(show.episodes[0].artworkURL == showArt)
        #expect(show.episodes[1].artworkURL == ownArt)
        #expect(show.hasArtwork)
    }

    @Test func aStreamedShowIsKnownByItsFeed() {
        let show = PodcastShow(feed: feedShow(episodes: [feedEpisode("g")]))
        #expect(show.id == "feed:https://a.lyre.test/f.xml")
        #expect(show.isStreamed)
        #expect(show.artworkCacheKey == "podcast.feed:https://a.lyre.test/f.xml")
        let episode = show.episodes[0]
        #expect(episode.id == "feed.g")
        #expect(episode.streamURL?.absoluteString == "https://cdn.lyre.test/g.mp3")
        #expect(episode.mediaItem == nil)
        #expect(episode.showTitle == "Show")
    }

    @Test func anEpisodeOfUnknownLengthCountsAsZero() {
        let show = PodcastShow(feed: feedShow(episodes: [feedEpisode("g", duration: nil)]))
        #expect(show.episodes[0].duration == 0)
    }

    @Test func episodesAndShowsAreEqualByIdAlone() {
        let a = PodcastShow(feed: feedShow(title: "One", episodes: [feedEpisode("x")]))
        let b = PodcastShow(feed: feedShow(title: "Renamed", episodes: []))
        #expect(a == b)
        #expect(Set([a, b]).count == 1)
    }

    @Test func aShowWithNoArtworkSaysSo() {
        let show = PodcastShow(feed: feedShow(episodes: [feedEpisode("x")]))
        #expect(!show.hasArtwork)
        #expect(show.artwork == nil)
    }
}

// MARK: - Onboarding Paths

@Suite("Onboarding paths")
@MainActor
struct OnboardingPathTests {

    @Test(arguments: PlayerStyle.allCases)
    func everyPlayerStartsTheSameWayAndEndsOnTheSummary(_ style: PlayerStyle) {
        let path = OnboardingStep.path(for: style)
        #expect(Array(path.prefix(4)) == [.welcome, .permissions, .musicAccess, .choosePlayer])
        #expect(path.last == .done)
        #expect(Set(path).count == path.count, "No step twice")
    }

    @Test(arguments: PlayerStyle.allCases)
    func noPlayerIsShownAnotherPlayersSteps(_ style: PlayerStyle) {
        let own: [PlayerStyle: Set<OnboardingStep>] = [
            .classic: [.meetTheWheel, .practice, .shortcuts, .makeItYours, .bodyStyle, .finish,
                       .highlight, .screenSize, .wheelFeel, .backlight],
            .spool: [.meetTheSpool, .spoolStyle],
            .gramophone: [.gramophoneStyle],
            .disc: [.meetTheDisc, .discStyle],
            .liquid: [.meetLiquid],
        ]
        let path = Set(OnboardingStep.path(for: style))
        for (other, steps) in own where other != style {
            #expect(path.isDisjoint(with: steps), "\(style) shows \(other)'s steps")
        }
    }

    @Test func everyStepIsOnSomePlayersPath() {
        let reachable = Set(PlayerStyle.allCases.flatMap(OnboardingStep.path(for:)))
        #expect(reachable == Set(OnboardingStep.allCases))
    }

    @Test func thePreviewIsShownOnlyWhereThereIsRoomForIt() {
        // Steps with their own working wheel or preview don't get the shared one.
        for step in [OnboardingStep.welcome, .permissions, .musicAccess, .choosePlayer, .wheelFeel, .meetLiquid] {
            for style in PlayerStyle.allCases {
                #expect(step.previewHeight(for: style) == nil, "\(step) / \(style)")
            }
        }
        for style in PlayerStyle.allCases {
            #expect((OnboardingStep.done.previewHeight(for: style) ?? 0) > 0, "\(style)'s summary has a preview")
        }
    }
}

// MARK: - Player Style and Settings Values

@Suite("Saved setting values")
@MainActor
struct SavedSettingValueTests {

    @Test func playerStylesKeepTheRawValuesInstallsHaveSaved() {
        #expect(PlayerStyle.allCases.map(\.rawValue) == ["classic", "spool", "gramophone", "disc", "liquid"])
    }

    @Test func everyPlayerHasItsOwnName() {
        let names = PlayerStyle.allCases.map(\.displayName)
        #expect(names.allSatisfy { !$0.isEmpty && !$0.hasPrefix("settings.") }, "\(names)")
        #expect(Set(names).count == names.count)
    }

    @Test func backlightDurationsAreInOrderWithAlwaysOnLast() {
        #expect(BacklightDuration.fiveSeconds.interval == 5)
        #expect(BacklightDuration.tenSeconds.interval == 10)
        #expect(BacklightDuration.thirtySeconds.interval == 30)
        #expect(BacklightDuration.alwaysOn.interval == nil)
        #expect(BacklightDuration.allCases.last == .alwaysOn)
    }

    @Test func aMoreSensitiveWheelStepsSoonerAndSpeedsUpSooner() {
        #expect(ScrollSensitivity.high.scrollThreshold < ScrollSensitivity.medium.scrollThreshold)
        let low = ScrollSensitivity.low.velocityStepThresholds
        let medium = ScrollSensitivity.medium.velocityStepThresholds
        let high = ScrollSensitivity.high.velocityStepThresholds
        #expect(high.t1 < medium.t1 && medium.t1 < low.t1)
        for t in [low, medium, high] { #expect(t.t1 < t.t2 && t.t2 < t.t3) }
    }

    @Test func screenSizeRawValuesAreUnique() {
        #expect(Set(ScreenSize.allCases.map(\.rawValue)).count == ScreenSize.allCases.count)
    }
}

// MARK: - Screen Sizes

@Suite("ScreenSize")
struct ScreenSizeTests {

    private let ladder = ScreenSize.heightLadder

    @Test func theLadderRunsShortestToTallest() {
        #expect(ladder.count == ScreenSize.allCases.count)
        #expect(zip(ladder, ladder.dropFirst()).allSatisfy { $0.dimensions.height <= $1.dimensions.height })
    }

    @Test func aPresetsOwnHeightGivesThatPreset() {
        for size in ladder {
            let layout = ScreenSize.interpolatedLayout(forHeight: size.dimensions.height, in: ladder)
            #expect(layout.dimensions.width == size.dimensions.width, "\(size)")
            #expect(layout.wheelSize == size.wheelSize, "\(size)")
            #expect(ScreenSize.nearest(toHeight: size.dimensions.height, in: ladder) == size)
        }
    }

    @Test func halfwayBetweenTwoPresetsIsHalfOfEach() {
        let lower = ladder[0], upper = ladder[1]
        let mid = (lower.dimensions.height + upper.dimensions.height) / 2
        let layout = ScreenSize.interpolatedLayout(forHeight: mid, in: ladder)
        #expect(abs(layout.dimensions.width - (lower.dimensions.width + upper.dimensions.width) / 2) < 0.001)
        #expect(abs(layout.wheelSize - (lower.wheelSize + upper.wheelSize) / 2) < 0.001)
        #expect(layout.dimensions.height == mid)
    }

    @Test func draggingPastEitherEndHoldsTheWidthAndWheel() {
        let first = ladder.first!, last = ladder.last!
        let short = ScreenSize.interpolatedLayout(forHeight: 10, in: ladder)
        #expect(short.dimensions == CGSize(width: first.dimensions.width, height: 10))
        #expect(short.wheelSize == first.wheelSize)
        let tall = ScreenSize.interpolatedLayout(forHeight: 5000, in: ladder)
        #expect(tall.dimensions == CGSize(width: last.dimensions.width, height: 5000))
        #expect(tall.wheelSize == last.wheelSize)
        #expect(ScreenSize.nearest(toHeight: 5000, in: ladder) == last)
        #expect(ScreenSize.nearest(toHeight: -50, in: ladder) == first)
    }

    @Test func anEmptyLadderFallsBackToStandard() {
        let layout = ScreenSize.interpolatedLayout(forHeight: 300, in: [])
        #expect(layout.dimensions.width == ScreenSize.standard.dimensions.width)
        #expect(layout.wheelSize == ScreenSize.standard.wheelSize)
        #expect(ScreenSize.nearest(toHeight: 300, in: []) == nil)
    }
}

// MARK: - Themes

@Suite("LyreTheme")
@MainActor
struct LyreThemeTests {

    @Test(arguments: LyreThemeStyle.allCases)
    func everyFinishBuildsATheme(_ style: LyreThemeStyle) {
        let theme = LyreTheme.theme(for: style)
        #expect(theme.style == style)
        #expect(!theme.screenBackgroundLight.isEmpty && !theme.screenBackgroundDark.isEmpty)
        #expect(!theme.wheelOuterGradientColors.isEmpty && !theme.wheelCenterGradientColors.isEmpty)
    }

    @Test(arguments: LyreThemeStyle.allCases)
    func aCustomHighlightWinsOnEveryFinish(_ style: LyreThemeStyle) {
        let pink = Color(red: 1, green: 0.2, blue: 0.6)
        let highlight = LyreTheme.theme(for: style, highlightColor: pink).highlightColor.toStorableColor()
        #expect(abs(highlight.red - 1) < 0.01 && abs(highlight.green - 0.2) < 0.01 && abs(highlight.blue - 0.6) < 0.01)
    }

    @Test(arguments: LyreThemeStyle.allCases)
    func everyFinishHasADefaultScreenSize(_ style: LyreThemeStyle) {
        #expect(ScreenSize.allCases.contains(style.defaultScreenSize))
    }
}

// MARK: - Downloads

@Suite("PodcastDownloads")
@MainActor
struct PodcastDownloadTests {

    @Test func aDownloadsFileNameIsStableAndSafeWhateverTheGuid() {
        let guid = "https://example.com/episodes/42?utm=feed&x=../../etc"
        let name = PodcastDownloads.fileName(for: guid, remoteURL: URL(string: "https://cdn.lyre.test/ep.MP3"))
        #expect(name == PodcastDownloads.fileName(for: guid, remoteURL: URL(string: "https://cdn.lyre.test/ep.MP3")))
        #expect(!name.contains("/") && !name.contains(".."))
        #expect(name.hasSuffix(".mp3"))
        #expect(name != PodcastDownloads.fileName(for: guid + "x", remoteURL: nil))
    }

    @Test(arguments: [("m4a", "m4a"), ("aac", "aac"), ("mp4", "mp4"), ("opus", "opus"),
                      ("php", "mp3"), ("", "mp3"), ("exe", "mp3")])
    func onlyAudioExtensionsAreKept(_ ext: String, _ expected: String) {
        let url = URL(string: "https://cdn.lyre.test/episode\(ext.isEmpty ? "" : "." + ext)")
        #expect(PodcastDownloads.fileName(for: "id", remoteURL: url).hasSuffix("." + expected))
    }

    @Test func anEpisodeNotDownloadedOffersToDownload() {
        let id = "feed.\(UUID().uuidString)"
        let downloads = PodcastDownloads.shared
        #expect(downloads.state(for: id) == nil)
        #expect(downloads.localFile(for: id) == nil)
        #expect(downloads.actionTitle(for: id).symbol == "arrow.down.circle")
    }

    @Test func removingSomethingNeverDownloadedChangesNothing() {
        let id = "feed.\(UUID().uuidString)"
        PodcastDownloads.shared.remove(id)
        #expect(PodcastDownloads.shared.state(for: id) == nil)
    }

}

// MARK: - Stream Player

@Suite("PodcastStreamPlayer", .serialized)
@MainActor
struct PodcastStreamPlayerTests {

    private func episodes(_ count: Int) -> [PodcastEpisode] {
        let feed = feedShow(episodes: (1...count).map { feedEpisode("s\($0)-\(UUID().uuidString)") })
        return PodcastShow(feed: feed).episodes
    }

    /// A player that never reaches the network: every episode "plays" from a file
    /// that isn't there.
    private func offlinePlayer() -> PodcastStreamPlayer {
        let player = PodcastStreamPlayer()
        player.playbackURL = { URL(fileURLWithPath: "/nonexistent/\($0.id).mp3") }
        return player
    }

    private func waitUntil(_ condition: () -> Bool, timeout: Duration = .seconds(5)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now > deadline { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }

    @Test func playingStartsAtTheChosenEpisodeWithTheRestUpNext() {
        let player = offlinePlayer()
        defer { player.stop() }
        let list = episodes(4)
        player.play(list, startingAt: 1)
        #expect(player.current == list[1])
        #expect(player.upcoming.map(\.id) == list[2...].map(\.id))
    }

    @Test func anEpisodeOutsideTheListPlaysNothing() {
        let player = offlinePlayer()
        player.play(episodes(2), startingAt: 7)
        #expect(player.current == nil)
        player.play([], startingAt: 0)
        #expect(player.current == nil)
    }

    @Test func nextStopsAtTheLastEpisodeAndPreviousAtTheFirst() {
        let player = offlinePlayer()
        defer { player.stop() }
        let list = episodes(2)
        player.play(list, startingAt: 0)
        player.skipToPrevious()
        #expect(player.current == list[0])
        player.skipToNext()
        #expect(player.current == list[1])
        player.skipToNext()
        #expect(player.current == list[1])
        #expect(player.upcoming.isEmpty)
    }

    @Test func stoppingForgetsTheEpisode() {
        let player = offlinePlayer()
        var changes = 0
        player.onChange = { changes += 1 }
        player.play(episodes(3), startingAt: 0)
        player.stop()
        #expect(player.current == nil)
        #expect(player.upcoming.isEmpty)
        #expect(!player.isPlaying)
        #expect(changes > 0)
    }

    @Test func untilItLoadsTheFeedsLengthIsTheDuration() {
        let player = offlinePlayer()
        defer { player.stop() }
        player.play(episodes(1), startingAt: 0)
        #expect(player.duration == 600)
        #expect(player.currentTime == 0)
    }

    @Test func anEpisodeThatCantBeReachedReportsAFailureAndStops() async {
        let player = offlinePlayer()
        defer { player.stop() }
        var failed: PodcastEpisode?
        player.onFailure = { episode, _ in failed = episode }
        let list = episodes(2)
        player.play(list, startingAt: 0)
        #expect(await waitUntil { failed != nil }, "No failure was reported")
        #expect(failed == list[0])
        #expect(!player.isPlaying)
    }

    @Test func theSavedPlaceIsAskedForWhenAnEpisodeLoads() {
        let player = offlinePlayer()
        defer { player.stop() }
        var asked: [String] = []
        player.loadPosition = { asked.append($0); return 0 }
        let list = episodes(2)
        player.play(list, startingAt: 0)
        player.skipToNext()
        #expect(asked == list.map(\.id))
    }

    @Test func theSpeedIsKept() {
        let player = offlinePlayer()
        player.rate = 1.5
        #expect(player.rate == 1.5)
    }
}

// MARK: - Helpers' Edges

@Suite("AppHelpers edges")
struct AppHelperEdgeTests {

    @Test func anHourLongSongCountsInMinutes() {
        #expect(AppHelpers.formatTime(3600) == "60:00")
        #expect(AppHelpers.formatTime(3661.9) == "61:01")
    }

    @Test func articlesAreOnlySkippedAsWholeWords() {
        #expect(AppHelpers.sortKey(for: "The Weeknd") == "Weeknd")
        #expect(AppHelpers.sortKey(for: "An Horse") == "Horse")
        #expect(AppHelpers.sortKey(for: "Theory of a Deadman") == "Theory of a Deadman")
        #expect(AppHelpers.sortKey(for: "Anberlin") == "Anberlin")
        #expect(AppHelpers.sortKey(for: "THE   KILLERS") == "KILLERS")
        #expect(AppHelpers.sortKey(for: "The") == "The")
        #expect(AppHelpers.sortKey(for: "") == "")
    }

    @Test func nonLatinNamesFileUnderTheirOwnLetter() {
        #expect(AppHelpers.firstLetter(of: "Ásgeir") == "Á")
        #expect(AppHelpers.firstLetter(of: "坂本龍一") == "坂")
        #expect(AppHelpers.firstLetter(of: "🎸 Band") == "#")
    }

    @Test func batteryLevelsAtTheBoundaries() {
        #expect(AppHelpers.batteryIconName(level: 0.9, state: .unplugged) == "battery.100")
        #expect(AppHelpers.batteryIconName(level: 0.75, state: .unplugged) == "battery.75")
        #expect(AppHelpers.batteryIconName(level: 0.5, state: .unplugged) == "battery.50")
        #expect(AppHelpers.batteryIconName(level: 0.25, state: .unplugged) == "battery.25")
    }

    @Test func aBatteryThatCantBeReadIsNeverShownAsLow() {
        // A Mac with no battery, or the simulator, reports level -1 and state unknown.
        #expect(!AppHelpers.batteryIsLow(level: -1, state: .unknown))
        #expect(!AppHelpers.batteryIsLow(level: 0.1, state: .unknown))
        #expect(AppHelpers.batteryIsLow(level: 0.1, state: .unplugged))
        #expect(AppHelpers.batteryIsLow(level: 0, state: .unplugged))
    }
}

// MARK: - Liquid Index

@Suite("Gramophone drawer")
struct RecordStackSwipeTests {
    /// LYRE-19: swiped left, the drawer goes on down the list; right, back up it.
    @Test func leftIsNextAndRightIsBack() {
        #expect(RecordStackView.listStep(forPull: -120) == 1)
        #expect(RecordStackView.listStep(forPull: 120) == -1)
    }
}

@Suite("Artwork carousel")
@MainActor
struct ArtworkCarouselEmptyTests {
    /// LYRE-18: an empty carousel names what's missing.
    @Test func eachListSaysWhatItHasNoneOf() {
        #expect(ArtworkCarouselContent.albums([]).emptyMessage == String(localized: "empty.albums"))
        #expect(ArtworkCarouselContent.playlists([]).emptyMessage == String(localized: "empty.playlists"))
        #expect(ArtworkCarouselContent.podcasts([]).emptyMessage == String(localized: "empty.podcasts"))
        #expect(ArtworkCarouselContent.albums([]).itemCount == 0)
    }
}

@Suite("Liquid cover grid columns")
@MainActor
struct LiquidGridColumnTests {
    /// A phone (an iPhone Duo closed among them) keeps two columns.
    @Test func aPhoneHasTwoColumns() {
        #expect(LiquidCoverTile.columnCount(for: 322) == 2)
        #expect(LiquidCoverTile.columnCount(for: 0) == 2)
    }

    /// The wider inner display gets more columns, as an iPad does, and always an even
    /// number, so the fold of a Duo held as a book falls between two columns.
    @Test func wideScreensGetAnEvenNumberOfColumns() {
        for width in stride(from: 300.0, through: 1400, by: 25) {
            let count = LiquidCoverTile.columnCount(for: width)
            #expect(count >= 2 && count % 2 == 0, "\(count) columns at \(width)")
        }
        #expect(LiquidCoverTile.columnCount(for: 700) == 4)
        #expect(LiquidCoverTile.columnCount(for: 1100) == 6)
    }
}

@Suite("Liquid letter index")
@MainActor
struct LiquidLetterIndexTests {

    @Test func lettersReadHashThenAToZWhateverOrderTheTitlesComeIn() {
        // As a library can arrive: not in the order its index should read.
        let titles = ["Black", "Money", "Sun", "Alpha", "Ánimo", "99 Problems", "Cold", "Échale", "Zebra", "بلادي"]
        let index = LiquidLetterEntry.index(titles)
        #expect(index.map(\.letter) == ["#", "A", "B", "C", "E", "M", "S", "Z", "ب"])
    }

    @Test func eachLetterJumpsToItsFirstTitle() {
        let titles = ["Black", "Alpha", "Ánimo", "Bravo", "Azure"]
        let index = Dictionary(uniqueKeysWithValues: LiquidLetterEntry.index(titles).map { ($0.letter, $0.index) })
        #expect(index["A"] == 1)
        #expect(index["B"] == 0)
    }

    @Test func accentedLettersFileUnderTheirPlainLetter() {
        #expect(LiquidLetterEntry.filingLetter(of: "Ánimo") == "A")
        #expect(LiquidLetterEntry.filingLetter(of: "Être") == "E")
        #expect(LiquidLetterEntry.filingLetter(of: "The Über") == "U")
        #expect(LiquidLetterEntry.filingLetter(of: "#1 Hits") == "#")
    }

    @Test func anEmptyListHasNoIndex() {
        #expect(LiquidLetterEntry.index([]).isEmpty)
    }
}

// MARK: - Gramophone Up Next Bin

@Suite("Gramophone Up Next bin")
@MainActor
struct GramophoneBinTests {

    /// A record's lie partway between two places, as the stage animates it.
    private func lie(_ depth: Float) -> (z: Float, y: Float, angle: Float) {
        let low = depth.rounded(.down), t = depth - low
        let a = GramophoneStage.rackLie(low), b = GramophoneStage.rackLie(low + 1)
        return (a.z + (b.z - a.z) * t, a.y + (b.y - a.y) * t, a.angle + (b.angle - a.angle) * t)
    }

    /// LYRE-1: records flipped forward showed lying through the bin's front wall.
    @Test func noRecordEverPassesThroughTheFrontWall() {
        let wallZ = GramophoneStage.rackWallInside, wallTop = GramophoneStage.rackWallTop
        let side = GramophoneStage.rackSleeveSide
        for step in 0...200 {
            let depth = -4 + Float(step) * 0.02
            let record = lie(depth)
            #expect(record.y >= GramophoneStage.rackFloor - 0.0001, "Below the floor at depth \(depth)")
            // Where the record crosses the wall's inner face, it must be above the wall.
            let reach = side * sin(record.angle)
            guard record.z + reach > wallZ, record.angle > 0 else { continue }
            let along = (wallZ - record.z) / sin(record.angle)
            let height = record.y + along * cos(record.angle)
            #expect(height >= wallTop, "Through the wall at depth \(depth): \(height) under \(wallTop)")
        }
    }

    @Test func theLastRecordFlippedLiesOnTopOfTheOthers() {
        let last = GramophoneStage.rackLie(-1), before = GramophoneStage.rackLie(-2)
        // Higher where it crosses the wall, and more upright.
        let wallZ = GramophoneStage.rackWallInside
        func heightAtWall(_ l: (z: Float, y: Float, angle: Float, opacity: Float)) -> Float {
            l.y + (wallZ - l.z) / tan(l.angle)
        }
        #expect(heightAtWall(last) > heightAtWall(before))
        #expect(last.angle < before.angle)
    }

    @Test func standingRecordsStandOnTheFloor() {
        for depth in 0...10 {
            #expect(GramophoneStage.rackLie(Float(depth)).y == GramophoneStage.rackFloor)
        }
    }
}

@Suite("Liquid cover ripples")
@MainActor
struct LiquidRippleTests {
    private let anchor = Date(timeIntervalSinceReferenceDate: 1_000)
    private let size = CGSize(width: 400, height: 900)

    /// At 120 beats a minute a ring starts every half second, and each runs for
    /// `LiquidRipple.life` seconds, so the beats of the last 2.6 s are out.
    @Test func everyBeatInTheLastFewSecondsIsRippling() {
        let drops = LiquidRipple.beatDrops(anchor: anchor, beatsPerMinute: 120,
                                           now: anchor.addingTimeInterval(10.2), end: nil, size: size)
        #expect(drops.map { $0.start.timeIntervalSince(anchor) } == [8, 8.5, 9, 9.5, 10])
    }

    /// The first beat of every bar rings harder than the rest.
    @Test func eachBarStartsWithAStrongerRing() {
        let drops = LiquidRipple.beatDrops(anchor: anchor, beatsPerMinute: 60,
                                           now: anchor.addingTimeInterval(4.1), end: nil, size: size)
        #expect(drops.map(\.strength) == [LiquidRipple.beatStrength, LiquidRipple.beatStrength,
                                          LiquidRipple.barStrength])
    }

    /// Stopped, no new ring starts, and the last ones run out.
    @Test func noBeatRipplesAfterTheMusicStops() {
        let end = anchor.addingTimeInterval(5.25)
        let soon = LiquidRipple.beatDrops(anchor: anchor, beatsPerMinute: 120,
                                          now: anchor.addingTimeInterval(6), end: end, size: size)
        #expect(soon.last?.start == anchor.addingTimeInterval(5))
        let later = LiquidRipple.beatDrops(anchor: anchor, beatsPerMinute: 120,
                                           now: anchor.addingTimeInterval(9), end: end, size: size)
        #expect(later.isEmpty)
    }

    /// A song with no tempo ripples at 90; none before the song starts.
    @Test func anUntaggedSongRipplesAtNinety() {
        let drops = LiquidRipple.beatDrops(anchor: anchor, beatsPerMinute: nil,
                                           now: anchor.addingTimeInterval(1.5), end: nil, size: size)
        // To the millisecond: a Date's seconds don't come out exact.
        #expect(drops.map { ($0.start.timeIntervalSince(anchor) * 1000).rounded() } == [0, 667, 1333])
        #expect(LiquidRipple.beatDrops(anchor: anchor, beatsPerMinute: 120,
                                       now: anchor.addingTimeInterval(-1), end: nil, size: size).isEmpty)
    }

    /// A beat lands near the middle, and in the same place every frame.
    @Test func aBeatLandsNearTheMiddleTheSameWayEachTime() {
        for beat in 0..<200 {
            let point = LiquidRipple.landing(of: beat, in: size)
            #expect(abs(point.x - 200) <= 40 && abs(point.y - 378) <= 54, "beat \(beat) at \(point)")
            #expect(point == LiquidRipple.landing(of: beat, in: size))
        }
    }

    /// Turned off in settings, it doesn't ripple, and nor does anything asking for less
    /// motion or less power.
    @Test func itRipplesOnlyWhenOnAndNothingAsksForLess() {
        #expect(LiquidRipple.isAllowed(isOn: true, reduceMotion: false, lowPower: false, uiTesting: false))
        #expect(!LiquidRipple.isAllowed(isOn: false, reduceMotion: false, lowPower: false, uiTesting: false))
        #expect(!LiquidRipple.isAllowed(isOn: true, reduceMotion: true, lowPower: false, uiTesting: false))
        #expect(!LiquidRipple.isAllowed(isOn: true, reduceMotion: false, lowPower: true, uiTesting: false))
        #expect(!LiquidRipple.isAllowed(isOn: true, reduceMotion: false, lowPower: false, uiTesting: true))
    }

    /// The shader gets at most `maxDrops` rings, four numbers each, timed from the epoch.
    @Test func theShaderGetsFourNumbersARing() {
        let drop = LiquidRipple.Drop(center: CGPoint(x: 10, y: 20), start: anchor.addingTimeInterval(1.5),
                                     strength: 0.5)
        #expect(LiquidRipple.shaderValues([drop], epoch: anchor) == [10, 20, 1.5, 0.5])
        let many = Array(repeating: drop, count: 30)
        #expect(LiquidRipple.shaderValues(many, epoch: anchor).count == LiquidRipple.maxDrops * 4)
    }
}

@Suite("Liquid bubbles")
@MainActor
struct LiquidBubbleLayoutTests {
    /// One song is the smallest bubble, thirty or more the largest, and more songs never
    /// make a smaller one.
    @Test func moreSongsMakeABiggerBubble() {
        let width: CGFloat = 500
        #expect(LiquidBubbleLayout.diameter(forSongs: 1, width: width) == LiquidBubbleLayout.smallest)
        #expect(LiquidBubbleLayout.diameter(forSongs: 30, width: width) == LiquidBubbleLayout.largest)
        #expect(LiquidBubbleLayout.diameter(forSongs: 200, width: width) == LiquidBubbleLayout.largest)
        let sizes = (1...40).map { LiquidBubbleLayout.diameter(forSongs: $0, width: width) }
        #expect(sizes == sizes.sorted())
        #expect(LiquidBubbleLayout.diameter(forSongs: 12, width: width) > LiquidBubbleLayout.diameter(forSongs: 4, width: width))
    }

    /// On a narrow page, the largest bubble still leaves room for another beside it.
    @Test func aBubbleIsNeverMoreThanHalfThePage() {
        #expect(LiquidBubbleLayout.diameter(forSongs: 30, width: 180) <= 90)
        #expect(LiquidBubbleLayout.diameter(forSongs: 1, width: 100) == LiquidBubbleLayout.smallest)
    }

    /// Packed, no two bubbles touch, every one is inside the page, and the same list
    /// packs the same way every time.
    @Test func bubblesPackWithoutTouching() {
        let width: CGFloat = 420
        let diameters = (0..<120).map { LiquidBubbleLayout.diameter(forSongs: [1, 4, 9, 12, 20, 35][$0 % 6], width: width) }
        let packed = LiquidBubbleLayout.pack(diameters, width: width)
        #expect(packed.centers.count == diameters.count)
        for i in diameters.indices {
            let r = diameters[i] / 2
            #expect(packed.centers[i].x - r >= 0 && packed.centers[i].x + r <= width, "bubble \(i) is off the page")
            #expect(packed.centers[i].y + r <= packed.height)
            for j in diameters.indices where j > i {
                let apart = hypot(packed.centers[i].x - packed.centers[j].x, packed.centers[i].y - packed.centers[j].y)
                #expect(apart >= r + diameters[j] / 2 + LiquidBubbleLayout.gap - 0.5, "bubbles \(i) and \(j) touch")
            }
        }
        #expect(LiquidBubbleLayout.pack(diameters, width: width).centers == packed.centers)
    }

    /// They fill the page instead of standing in a column: a page of bubbles is no
    /// taller than a third more than their area needs.
    @Test func bubblesFillThePage() {
        let width: CGFloat = 420
        let diameters = (0..<80).map { LiquidBubbleLayout.diameter(forSongs: [1, 8, 15, 30][$0 % 4], width: width) }
        let area = diameters.reduce(0) { $0 + ($1 + LiquidBubbleLayout.gap) * ($1 + LiquidBubbleLayout.gap) }
        #expect(LiquidBubbleLayout.pack(diameters, width: width).height <= area / width * 1.35)
    }

    /// A show is as big as its episodes; an album as its songs.
    @Test func aShowCountsItsEpisodes() {
        let tracks = (1...7).map { AppTrack(id: "t\($0)", title: "Song \($0)", artistName: "A", albumTitle: "B", duration: 120) }
        let album = AppAlbum(id: "a", title: "B", artistName: "A", preloadedTracks: tracks)
        #expect(LiquidBubbleLayout.songCount(of: album) == 7)
        #expect(LiquidBubbleLayout.songCount(of: AppAlbum(id: "x", title: "X", artistName: "A")) == nil)
    }
}

@Suite("Artwork carousel on an open Duo")
@MainActor
struct CarouselPostureTests {
    /// The classic player always turns wide into the carousel; Liquid only when the
    /// phone is shut: an open Duo's wide screen is Now Playing beside the bubbles.
    @Test func liquidKeepsAnOpenDuosWideScreen() {
        #expect(LyreView.opensCarousel(.classic, posture: .closed))
        #expect(LyreView.opensCarousel(.classic, posture: .open))
        #expect(LyreView.opensCarousel(.liquid, posture: .closed))
        #expect(!LyreView.opensCarousel(.liquid, posture: .open))
        #expect(!LyreView.opensCarousel(.liquid, posture: .tent))
        #expect(!LyreView.opensCarousel(.spool, posture: .closed))
    }
}

@Suite("Song tempos from Deezer")
@MainActor
struct SongTempoTests {
    private func song(_ title: String, by artist: String, length: TimeInterval = 200) -> AppTrack {
        AppTrack(id: UUID().uuidString, title: title, artistName: artist, albumTitle: "Album", duration: length)
    }

    /// Titles and names compare by what identifies them, not how a store happens to
    /// spell them.
    @Test func titlesCompareWithoutTheTrimmings() {
        #expect(DeezerTempo.normalized("Bad Guy") == "badguy")
        #expect(DeezerTempo.normalized("Here Comes the Sun (Remastered 2009)") == DeezerTempo.normalized("Here Comes The Sun"))
        #expect(DeezerTempo.normalized("Café del Mar") == "cafedelmar")
        #expect(DeezerTempo.normalized("Levitating feat. DaBaby") == "levitating")
        #expect(DeezerTempo.normalized("Sample Song - Single") == "samplesong")
        #expect(DeezerTempo.normalized("Song [Live]") == "song")
    }

    /// A track Deezer knows gives its tempo; 0 (unknown), nonsense, or "no data" gives none.
    @Test func aTracksTempoIsReadOnlyWhenItsReal() {
        let known = Data(#"{"id":655095912,"title":"bad guy","duration":194,"bpm":135.11,"artist":{"name":"Billie Eilish"}}"#.utf8)
        #expect(DeezerTempo.track(from: known)?.tempo == 135.11)
        let unknown = Data(#"{"id":2801558042,"title":"CHIHIRO","duration":303,"bpm":0,"artist":{"name":"Billie Eilish"}}"#.utf8)
        #expect(DeezerTempo.track(from: unknown)?.tempo == nil)
        let wild = Data(#"{"id":1,"title":"x","bpm":999}"#.utf8)
        #expect(DeezerTempo.track(from: wild)?.tempo == nil)
        let missing = Data(#"{"error":{"type":"DataException","message":"no data","code":800}}"#.utf8)
        #expect(DeezerTempo.track(from: missing) == nil)
    }

    /// Searching, only the song itself counts: not a cover by someone else, not a
    /// different-length version, not a song that merely has the name in its title.
    @Test func searchMatchesOnlyTheSameRecording() {
        let results = Data(#"""
        {"data":[
          {"id":3514926211,"title":"Billie Eilish - Chihiro (Lofi Version)","duration":220,"artist":{"name":"Late Arc"}},
          {"id":2858772942,"title":"Chihiro","duration":129,"artist":{"name":"Gravagerz"}},
          {"id":9,"title":"CHIHIRO","duration":250,"artist":{"name":"Billie Eilish"}},
          {"id":2801558042,"title":"CHIHIRO","duration":303,"artist":{"name":"Billie Eilish"}}
        ]}
        """#.utf8)
        #expect(DeezerTempo.bestMatch(in: results, title: "CHIHIRO", artist: "Billie Eilish", duration: 302) == 2801558042)
        #expect(DeezerTempo.bestMatch(in: results, title: "Chihiro", artist: "Someone Else", duration: 129) == nil)
        // A song with no length known takes the first with the same title and artist.
        #expect(DeezerTempo.bestMatch(in: results, title: "CHIHIRO", artist: "Billie Eilish", duration: 0) == 9)
        // "Artist & Guest" matches Deezer's "Artist".
        #expect(DeezerTempo.bestMatch(in: results, title: "Chihiro", artist: "Gravagerz & Friend", duration: 130) == 2858772942)
    }

    /// A song without an ISRC is filed under its artist and title.
    @Test func aSongIsFiledUnderItsArtistAndTitle() {
        #expect(SongTempos.key(for: song("Bad Guy (Remastered)", by: "Billie Eilish")) == "song:billieeilish|badguy")
        #expect(SongTempos.key(for: song("", by: "Nobody")) == nil)
    }

    /// A tempo found is used and not asked for again; "Deezer doesn't know" is asked
    /// again only after a while.
    @Test func answersAreKeptAndUnknownsAskedAgainLater() {
        let tempos = SongTempos(fileURL: nil)
        let track = song("Bad Guy", by: "Billie Eilish")
        let key = SongTempos.key(for: track)!
        #expect(tempos.needsAsking(track))
        tempos.record(135.11, for: key)
        #expect(tempos.bpm(for: track) == 135.11)
        #expect(!tempos.needsAsking(track))

        tempos.record(nil, for: key, at: .now.addingTimeInterval(-86_400))
        #expect(tempos.bpm(for: track) == nil)
        #expect(!tempos.needsAsking(track), "Asked again too soon")
        tempos.record(nil, for: key, at: .now.addingTimeInterval(-SongTempos.retryAfter - 60))
        #expect(tempos.needsAsking(track), "Never asked again")
    }

    /// What's found survives a relaunch.
    @Test func temposSurviveARelaunch() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("tempos-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let track = song("Levitating", by: "Dua Lipa")
        let first = SongTempos(fileURL: file)
        first.record(103, for: try #require(SongTempos.key(for: track)))
        first.save()
        await first.finishSaving()
        #expect(SongTempos(fileURL: file).bpm(for: track) == 103)
    }
}

@Suite("Artist photos")
@MainActor
struct ArtistPhotoTests {
    /// An artist is filed under their name as it identifies them, so "The 1975" and
    /// "the 1975" are one artist; a name with nothing to file under isn't asked for.
    @Test func artistsAreFiledByName() {
        #expect(ArtistPhotos.key(for: "The 1975") == ArtistPhotos.key(for: "the 1975"))
        #expect(ArtistPhotos.key(for: "Beyoncé") == "beyonce")
        #expect(ArtistPhotos.key(for: "*") == nil)
    }

    /// An artist Apple Music has no photo for isn't asked about again for a while, and
    /// what's known survives a relaunch.
    @Test func noPhotoIsRememberedThenAskedAgainLater() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("photos-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let photos = ArtistPhotos(fileURL: file)
        let name = "21 Savage, Offset & Metro Boomin"
        #expect(photos.needsAsking(name))
        photos.record(nil, for: try #require(ArtistPhotos.key(for: name)))
        #expect(!photos.needsAsking(name))
        #expect(photos.artwork(for: name) == nil)
        photos.save()
        #expect(!ArtistPhotos(fileURL: file).needsAsking(name), "Forgotten after a relaunch")
        photos.record(nil, for: try #require(ArtistPhotos.key(for: name)),
                      at: .now.addingTimeInterval(-ArtistPhotos.retryAfter - 60))
        #expect(photos.needsAsking(name), "Never asked again")
    }
}

@Suite("Apple Music catalogue")
@MainActor
struct AppleMusicCatalogTests {
    private func song(_ title: String, by artist: String, length: TimeInterval = 200) -> AppTrack {
        AppTrack(id: UUID().uuidString, title: title, artistName: artist, albumTitle: "Album", duration: length)
    }

    /// Apple's write-ups lose their markup but keep their line breaks.
    @Test func writeUpsAreReadAsPlainText() {
        #expect(AppleMusicCatalog.plainText("<i>After Hours</i> is a <b>dark</b> turn &amp; a triumph.<br/>Second line.")
                == "After Hours is a dark turn & a triumph.\nSecond line.")
        #expect(AppleMusicCatalog.plainText("  ") == nil)
        #expect(AppleMusicCatalog.plainText(nil) == nil)
    }

    /// Badges go best first, and Hi-Res stands for Lossless rather than beside it.
    @Test func onlyTheBestVariantsGetABadge() {
        #expect(AppleMusicCatalog.badges([.lossyStereo, .lossless, .dolbyAtmos]) == [.dolbyAtmos, .lossless])
        #expect(AppleMusicCatalog.badges([.lossless, .highResolutionLossless]) == [.highResolutionLossless])
        #expect(AppleMusicCatalog.badges([.lossyStereo]).isEmpty)
    }

    /// A catalogue song is the library's when the title, artist and length match.
    @Test func aCatalogueSongIsFoundInTheLibrary() {
        let mine = [song("Blinding Lights", by: "The Weeknd", length: 200), song("Save Your Tears", by: "The Weeknd")]
        #expect(AppleMusicCatalog.librarySong(title: "Blinding Lights", artist: "The Weeknd", duration: 201, in: mine)?.id == mine[0].id)
        #expect(AppleMusicCatalog.librarySong(title: "Blinding Lights", artist: "Someone", duration: 200, in: mine) == nil)
        #expect(AppleMusicCatalog.librarySong(title: "Blinding Lights", artist: "The Weeknd", duration: 260, in: mine) == nil,
                "A different-length version counted")
    }

    /// A catalogue album is the library's by title and artist, whatever the edition
    /// marks.
    @Test func aCatalogueAlbumIsFoundInTheLibrary() {
        let albums = [AppAlbum(id: "a", title: "After Hours", artistName: "The Weeknd")]
        #expect(AppleMusicCatalog.libraryAlbum(title: "After Hours (Deluxe)", artist: "The Weeknd", in: albums)?.id == "a")
        #expect(AppleMusicCatalog.libraryAlbum(title: "Starboy", artist: "The Weeknd", in: albums) == nil)
    }

    /// Most played: played at least twice, most first, then by name.
    @Test func mostPlayedGoesMostFirst() {
        let a = song("A", by: "X"), b = song("B", by: "X"), c = song("C", by: "X"), d = song("D", by: "X")
        let counts = [a.id: 3, b.id: 9, c.id: 1, d.id: 3]
        let order = AppTrack.mostPlayed([a, b, c, d], count: { counts[$0.id] ?? 0 }).map(\.title)
        #expect(order == ["B", "A", "D"])
    }
}

@MainActor
struct PlaylistAdderTests {
    @Test func onlyTheListenersOwnPlaylistsCanBeAddedTo() {
        #expect(PlaylistAdder.isEditable(id: "p.abc", kind: nil, curatorName: nil))
        #expect(PlaylistAdder.isEditable(id: "p.abc", kind: .userShared, curatorName: "Daniel"))
        #expect(!PlaylistAdder.isEditable(id: "pl.123", kind: .editorial, curatorName: "Apple Music Pop"))
        #expect(!PlaylistAdder.isEditable(id: "p.abc", kind: nil, curatorName: "Apple Music"))
        #expect(!PlaylistAdder.isEditable(id: "p.abc", kind: .personalMix, curatorName: nil))
        // The device's own library, without MusicKit, can't be edited.
        #expect(!PlaylistAdder.isEditable(id: "mp.playlist.42", kind: nil, curatorName: nil))
    }

    @Test func playlistsAreOfferedByName() {
        let playlists = [AppPlaylist(id: "p.2", name: "Running"),
                         AppPlaylist(id: "mp.playlist.1", name: "Device"),
                         AppPlaylist(id: "p.1", name: "Afternoon"),
                         AppPlaylist(id: "p.3", name: "Hits", curatorName: "Apple Music")]
        #expect(PlaylistAdder.editable(playlists).map(\.name) == ["Afternoon", "Running"])
    }

    @Test func theCatalogueIsAskedOnlyForTwoLettersOrMore() {
        #expect(AppleMusicCatalog.searchTerm("") == nil)
        #expect(AppleMusicCatalog.searchTerm("  a ") == nil)
        #expect(AppleMusicCatalog.searchTerm("  ab ") == "ab")
        #expect(AppleMusicCatalog.searchTerm("Radiohead\n") == "Radiohead")
    }
}

/// Songs streamed from Apple Music sit in the player's queue beside library songs, but
/// each descriptor holds one kind: a mixed list goes in as runs, in order.
struct StreamingQueueTests {
    @Test func aMixedListGoesInAsRunsOfOneKind() {
        let item = MPMediaItem()
        let entries: [PlaybackEntry] = [.item(item), .item(item), .store("1"), .store("2"), .item(item), .store("3")]
        let runs = MusicService.runs(of: entries)
        #expect(runs.map(\.count) == [2, 2, 1, 1])
        #expect(runs.map { $0.first?.isStore } == [false, true, false, true])
        #expect(runs[1].compactMap(\.storeID) == ["1", "2"])
        #expect(MusicService.runs(of: []).isEmpty)
    }

    @Test func aCatalogueSongStreamsAndALibrarySongDoesNot() {
        let streamed = AppTrack(id: "1440934248", title: "a", artistName: "", albumTitle: "", duration: 1, storeID: "1440934248")
        let owned = AppTrack(id: "i.abc", title: "a", artistName: "", albumTitle: "", duration: 1,
                             mpPersistentID: 6493, storeID: "1440934248")
        #expect(streamed.isStreamOnly && streamed.queueKey == "s1440934248")
        // The library's copy is played from the library, offline and without a subscription.
        #expect(!owned.isStreamOnly && owned.queueKey == "p6493")
        #expect(AppTrack.catalogID(MusicItemID("1440934248")) == "1440934248")
        #expect(AppTrack.catalogID(MusicItemID("i.abc")) == nil)
    }
}
