//
//  UsageStatsTests.swift
//  LyreTests
//
//  Usage statistics (UsageStats): nothing counted unless it's on, the working-out done
//  on the phone (first play, dead ends, features found), and nothing that names anything.
//

import Testing
import Foundation
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
}
