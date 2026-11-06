//
//  UsageStatsTests.swift
//  LyreTests
//
//  Usage statistics (UsageStats): nothing counted unless it's on, the working-out done
//  on the phone (first play, dead ends, features found), and nothing that names anything.
//

import Testing
import Foundation
import UIKit
@testable import Lyre

final class TestClock: @unchecked Sendable {
    var date = Date(timeIntervalSince1970: 1_793_000_000)
    func advance(_ seconds: TimeInterval) { date += seconds }
}

struct UsageStatsTests {
    private func stats(enabled: Bool = true, clock: TestClock = TestClock()) -> (UsageStats, UserDefaults) {
        let name = "usage-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(enabled, forKey: UsageStats.enabledKey)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("usage-\(UUID().uuidString).json")
        return (UsageStats(defaults: defaults, fileURL: file, now: { clock.date }), defaults)
    }

    @Test func nothingIsCountedUnlessItsOn() {
        let (stats, _) = stats(enabled: false)
        stats.sessionBegan()
        stats.screenShown("Liquid: albums")
        stats.played()
        stats.used(.shuffle)
        #expect(stats.waiting().isEmpty)
        #expect(stats.takeBatch().isEmpty)
    }

    @Test func theSessionsFirstPlayIsTimedAndSaysWhereFrom() {
        let clock = TestClock()
        let (stats, _) = stats(clock: clock)
        stats.sessionBegan()
        stats.screenShown("Liquid: card deck, 12 cards")
        clock.advance(6.24)
        stats.played()
        clock.advance(30)
        stats.played()
        let firsts = stats.waiting().filter { $0.name == "first_play" }
        #expect(firsts.count == 1)
        #expect(firsts.first?.value == 6.2)
        #expect(firsts.first?.source == "card")
        #expect(stats.waiting().filter { $0.name == "play" }.count == 2)
    }

    @Test func aNewSessionAfterHalfAnHourAwayTimesItsFirstPlayAgain() {
        let clock = TestClock()
        let (stats, _) = stats(clock: clock)
        stats.sessionBegan()
        stats.played()
        stats.resignedActive()
        clock.advance(60)
        stats.becameActive()   // a minute away: the same session
        stats.played()
        stats.resignedActive()
        clock.advance(UsageStats.sessionGap)
        stats.becameActive()
        clock.advance(3)
        stats.played()
        let firsts = stats.waiting().filter { $0.name == "first_play" }
        #expect(firsts.count == 2)
        #expect(firsts.last?.value == 3)
    }

    @Test func aPageLeftWithinTwoSecondsIsADeadEnd() {
        let clock = TestClock()
        let (stats, _) = stats(clock: clock)
        stats.screenShown("Liquid: menu")
        clock.advance(5)
        stats.screenShown("Liquid: playlists")
        clock.advance(1.2)
        stats.screenShown("Liquid: menu")
        let bounces = stats.waiting().filter { $0.name == "bounce" }
        #expect(bounces.count == 1)
        #expect(bounces.first?.screen == "Liquid: playlists")
        #expect(bounces.first?.value == 1.2)
    }

    @Test func switchingPlayersSaysHowLongTheLastWasUsed() {
        let clock = TestClock()
        let (stats, _) = stats(clock: clock)
        stats.playerShown("spool")
        clock.advance(120)
        stats.screenShown("Player: liquid")   // as ThemeSettings reports it
        let switches = stats.waiting().filter { $0.name == "player_switch" }
        #expect(switches.count == 1)
        #expect(switches.first?.detail == "spool")
        #expect(switches.first?.value == 120)
        #expect(stats.waiting().last?.player == "liquid")
        // Each player used today, once, in the batch.
        let active = stats.takeBatch().filter { $0.name == "active" }.map(\.player).sorted()
        #expect(active == ["liquid", "spool"])
    }

    @Test func aFeaturesFirstUseIsCountedOnce() {
        let (stats, defaults) = stats()
        stats.used(.shuffle)
        stats.used(.shuffle)
        stats.screenShown("Shelf: songs")
        let events = stats.waiting()
        #expect(events.filter { $0.name == "feature_first" }.compactMap(\.detail) == ["shuffle", "songsShelf"])
        #expect(events.filter { $0.name == "feature" }.count == 3)
        #expect(defaults.bool(forKey: "UsageStatsFound.shuffle"))
    }

    @Test func aSearchIsCountedOnceTypingPausesAndNeverItsWords() async throws {
        let (stats, _) = stats()
        stats.searched(found: true)
        stats.searched(found: true)
        stats.searched(found: false)
        try await Task.sleep(for: .milliseconds(1900))
        let searches = stats.waiting().filter { $0.name == "search" }
        #expect(searches.count == 1)
        #expect(searches.first?.detail == "empty")
    }

    @Test func anEventCarriesItsCohortNotAnIdentity() throws {
        let clock = TestClock()
        let (stats, _) = stats(clock: clock)
        clock.advance(3 * 86_400)
        stats.hang(milliseconds: 781, screen: "Liquid: card deck, 4 cards")
        let event = try #require(stats.waiting().first)
        #expect(event.day == 3)
        #expect(event.cohort.contains("-W"))
        #expect(event.screen == "Liquid: card deck")
        #expect(event.value == 781)
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as? [String: Any])
        #expect(Set(json.keys).isSubset(of: ["name", "player", "screen", "source", "detail", "value", "date", "day",
                                             "cohort", "version", "build", "device", "os"]))
    }

    @Test func waitingEventsSurviveARelaunchUnlessTurnedOff() {
        let name = "usage-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(true, forKey: UsageStats.enabledKey)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("usage-\(UUID().uuidString).json")
        let first = UsageStats(defaults: defaults, fileURL: file)
        first.used(.love)
        first.resignedActive()
        #expect(UsageStats(defaults: defaults, fileURL: file).waiting().count == 2)
        defaults.set(false, forKey: UsageStats.enabledKey)
        first.save()
        #expect(UsageStats(defaults: defaults, fileURL: file).waiting().isEmpty)
    }

    @Test func playsAreSourcedByTheScreenShowing() {
        #expect(UsageStats.source(forScreen: "Shelf: songs") == "shelf")
        #expect(UsageStats.source(forScreen: "Shelf: discover") == "discover")
        #expect(UsageStats.source(forScreen: "Liquid: search") == "search")
        #expect(UsageStats.source(forScreen: "Liquid: album") == "page")
        #expect(UsageStats.source(forScreen: "Liquid: songs") == "list")
        #expect(UsageStats.source(forScreen: nil) == "other")
    }

    // MARK: Round 2

    @Test func aSongsEndSaysHowItWentAndWhereItWasStarted() {
        let clock = TestClock()
        let (stats, _) = stats(clock: clock)
        stats.screenShown("Shelf: songs")
        stats.used(.shuffle)
        stats.played(kind: "library")
        clock.advance(1)
        stats.songChanged(heard: 1, duration: 200)        // the new play replacing the old: not counted
        clock.advance(10)
        stats.skipped(back: false)
        stats.songChanged(heard: 12, duration: 200)       // skipped from Lyre
        clock.advance(5)
        stats.songChanged(heard: 8, duration: 200)        // skipped elsewhere (lock screen, headphones)
        clock.advance(100)
        stats.songChanged(heard: 120, duration: 200)
        clock.advance(200)
        stats.songChanged(heard: 195, duration: 200)
        stats.skipped(back: true)
        stats.songChanged(heard: 40, duration: 200)
        let ends = stats.waiting().filter { $0.name == "song_end" }
        #expect(ends.compactMap(\.detail) == ["skip", "skip-elsewhere", "partial", "complete", "back"])
        #expect(ends.allSatisfy { $0.source == "shuffle" })
        #expect(stats.waiting().first { $0.name == "play" }?.detail == "library")
    }

    @Test func aStretchOfListeningIsCountedWhenItStops() {
        let clock = TestClock()
        let (stats, _) = stats(clock: clock)
        stats.played()
        stats.playbackChanged(isPlaying: true)
        clock.advance(60)
        stats.resignedActive()
        clock.advance(600)
        stats.playbackChanged(isPlaying: false)
        stats.playbackChanged(isPlaying: true)
        clock.advance(2)
        stats.playbackChanged(isPlaying: false)            // too short to count
        let listens = stats.waiting().filter { $0.name == "listen" }
        #expect(listens.count == 1)
        #expect(listens.first?.value == 660)
        #expect(listens.first?.detail == "background")
    }

    @Test func screensBeforeTheFirstSongAndLoopsAreCounted() {
        let clock = TestClock()
        let (stats, _) = stats(clock: clock)
        stats.sessionBegan()
        stats.screenShown("Liquid: menu")
        clock.advance(4)
        stats.screenShown("Liquid: playlists")
        clock.advance(5)
        stats.screenShown("Liquid: menu")                  // back again: a loop through playlists
        clock.advance(3)
        stats.screenShown("Liquid: albums")
        stats.played()
        let path = stats.waiting().first { $0.name == "first_play_path" }
        #expect(path?.value == 4)
        let loops = stats.waiting().filter { $0.name == "loop" }
        #expect(loops.map(\.screen) == ["Liquid: playlists"])
    }

    @Test func aSearchLeadsToAPlayOrNowhere() async throws {
        let clock = TestClock()
        let (stats, _) = stats(clock: clock)
        stats.searched(found: true, length: 5)
        try await Task.sleep(for: .milliseconds(1700))
        clock.advance(8)
        stats.played(kind: "streamed")
        stats.searched(found: true, length: 2)
        try await Task.sleep(for: .milliseconds(1700))
        stats.searched(found: false, length: 11)
        try await Task.sleep(for: .milliseconds(1700))
        let events = stats.waiting()
        #expect(events.first { $0.name == "search_play" }?.value == 8)
        #expect(events.first { $0.name == "search_play" }?.detail == "streamed")
        #expect(events.filter { $0.name == "search_no_play" }.count == 1)
        #expect(events.filter { $0.name == "search" }.compactMap(\.source) == ["4-7", "1-3", "8+"])
    }

    @Test func theWheelsTurnsAndOvershootsAreCountedAtEachPress() {
        let (stats, _) = stats()
        for _ in 0..<6 { stats.wheelStepped(down: true) }
        stats.wheelStepped(down: false)
        stats.wheelStepped(down: true)
        stats.wheelPressed(screen: "albums", sensitivity: "medium")
        stats.wheelPressed(screen: "albums", sensitivity: "medium")   // no turning: not counted
        let wheel = stats.waiting().filter { $0.name == "wheel" }
        #expect(wheel.count == 1)
        #expect(wheel.first?.value == 8)
        #expect(wheel.first?.detail == "reversals 2")
        #expect(wheel.first?.source == "medium")
    }

    @Test func onboardingIsKeptOnThePhoneUntilCountingIsTurnedOn() {
        let clock = TestClock()
        let (stats, defaults) = stats(enabled: false, clock: clock)
        stats.onboardingStep("welcome")
        clock.advance(4)
        stats.onboardingStep("permissions")
        clock.advance(10)
        stats.onboardingMusicAccess(granted: true)
        stats.onboardingFinished(player: "liquid")
        #expect(stats.waiting().isEmpty)
        defaults.set(true, forKey: UsageStats.enabledKey)
        stats.sessionBegan()
        let steps = stats.waiting().filter { $0.name == "onboarding_step" }
        #expect(steps.compactMap(\.detail) == ["welcome", "permissions"])
        #expect(steps.compactMap(\.value) == [4, 10])
        #expect(stats.waiting().first { $0.name == "onboarding_done" }?.value == 14)
        #expect(stats.waiting().first { $0.name == "music_access" }?.detail == "granted")
        // A week on: whether the player chosen is still the one in use.
        stats.playerShown("spool")
        clock.advance(8 * 86_400)
        stats.sessionBegan()
        let kept = stats.waiting().first { $0.name == "onboarding_kept" }
        #expect(kept?.detail == "liquid")
        #expect(kept?.source == "spool")
    }

    @Test func theDailyBatchCarriesTheLibrarysBandAndTheSnapshot() {
        let (stats, _) = stats()
        stats.libraryLoaded(songs: 3400, subscribed: true)
        stats.snapshot = { [("setting", "theme:dark"), ("a11y", "voiceover:off")] }
        let batch = stats.takeBatch()
        let context = batch.filter { ["context", "setting", "a11y"].contains($0.name) }.compactMap(\.detail)
        #expect(context == ["library:2k-10k", "subscriber:yes", "theme:dark", "voiceover:off"])
    }

    @Test func savedSettingsBecomeShortWords() {
        #expect(UsageSnapshot.word(true) == "on")
        #expect(UsageSnapshot.word("Dark Silver!") == "DarkSilver")
        #expect(UsageSnapshot.word(3) == "3")
        #expect(UsageSnapshot.word(NSNumber(value: 1)) == "1")
        #expect(UsageSnapshot.textSize(.large) == "default")
        #expect(UsageSnapshot.textSize(.accessibilityExtraLarge) == "accessibility")
        let name = "snapshot-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.set("Midnight", forKey: "LyreThemeStyle")
        defaults.set(false, forKey: "LyreClickSoundEnabled")
        let settings = UsageSnapshot.current(defaults: defaults).filter { $0.name == "setting" }.map(\.detail)
        #expect(settings.contains("theme:Midnight"))
        #expect(settings.contains("click-sound:off"))
        #expect(!settings.contains { $0.hasPrefix("backlight") })   // never set: Lyre's own
    }

    @Test func repeatedTapsArentCountedInTheClassicPlayer() {
        let (stats, _) = stats()
        stats.playerShown("classic")
        stats.repeatedTaps()
        stats.playerShown("liquid")
        stats.screenShown("Liquid: albums")
        stats.repeatedTaps()
        #expect(stats.waiting().filter { $0.name == "repeated_taps" }.map(\.screen) == ["Liquid: albums"])
    }

    @Test func iOSsDailyFiguresAreKeptAsNumbers() {
        let (stats, _) = stats()
        stats.dailyMetric("launch-ms", value: 412.345)
        stats.dailyMetric("hang-ms", value: .nan)
        #expect(stats.waiting().map(\.value) == [412.35])
    }

    @Test func aClassicScreenIsNamedByItsKindAlone() {
        let album = AppAlbum(id: "a", title: "Private Title", artistName: "Someone")
        #expect(LyreScreen.albumDetail(album).diagnosticName == "albumDetail")
        #expect(LyreScreen.songs.diagnosticName == "songs")
        #expect(UsageStats.source(forScreen: "Classic: albumDetail") == "page")
        #expect(UsageStats.source(forScreen: "Classic: nowPlaying") == "queue")
        #expect(UsageStats.source(forScreen: "Classic: search") == "search")
    }
}
