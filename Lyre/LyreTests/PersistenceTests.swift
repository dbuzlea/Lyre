//
//  PersistenceTests.swift
//  LyreTests
//
//  What Lyre remembers between launches, for every kind of user: someone on their
//  first launch, someone upgrading from a 1.x install with old setting names, someone
//  whose saved files are damaged, and someone with a huge library.
//

import Testing
import Foundation
import SwiftUI
@testable import Lyre

/// Runs `body` with the given UserDefaults keys cleared, putting back whatever was
/// there afterwards, so a test can't change the host app's settings.
@MainActor
private func withCleanDefaults(_ keys: [String], _ body: () throws -> Void) rethrows {
    let defaults = UserDefaults.standard
    let saved = keys.map { defaults.object(forKey: $0) }
    keys.forEach(defaults.removeObject(forKey:))
    defer {
        for (key, value) in zip(keys, saved) {
            if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
    }
    try body()
}

private let themeKeys = [
    "LyreThemeStyle", "LyreCustomHighlightColor", "LyreUseCustomHighlight", "LyreScreenSize",
    "LyreUseAutoScreenSize", "LyreScrollSensitivity", "LyreClickSoundEnabled", "LyreBacklightDuration",
    "LyrePlayerStyle", "LyreSpoolModel", "LyreSpoolFinish", "LyreGramophoneModel", "LyreGramophoneFinish",
    "LyreDiscFinish", "LyreGramophoneSurfaceNoise",
]

// MARK: - Settings

@Suite("ThemeSettings persistence", .serialized)
@MainActor
struct ThemeSettingsPersistenceTests {

    @Test func aFirstLaunchGetsTheDefaults() {
        withCleanDefaults(themeKeys) {
            let settings = ThemeSettings()
            #expect(settings.themeStyle == .porcelain)
            #expect(settings.screenSize == LyreThemeStyle.porcelain.defaultScreenSize)
            #expect(settings.scrollSensitivity == .medium)
            #expect(settings.clickSoundEnabled, "Clicks are on until turned off")
            #expect(!settings.useCustomHighlight)
            #expect(!settings.useAutoScreenSize)
            #expect(settings.playerStyle == .classic)
        }
    }

    @Test func everyChoiceSurvivesARelaunch() {
        withCleanDefaults(themeKeys) {
            let settings = ThemeSettings()
            settings.themeStyle = .onyx
            settings.scrollSensitivity = .high
            settings.clickSoundEnabled = false
            settings.backlightDuration = .alwaysOn
            settings.playerStyle = .gramophone
            settings.useCustomHighlight = true
            settings.customHighlightColor = Color(red: 1, green: 0, blue: 0)
            settings.screenSize = .jumbo

            let relaunched = ThemeSettings()
            #expect(relaunched.themeStyle == .onyx)
            #expect(relaunched.scrollSensitivity == .high)
            #expect(!relaunched.clickSoundEnabled)
            #expect(relaunched.backlightDuration == .alwaysOn)
            #expect(relaunched.playerStyle == .gramophone)
            #expect(relaunched.useCustomHighlight)
            #expect(relaunched.screenSize == .jumbo)
            let red = relaunched.customHighlightColor.toStorableColor()
            #expect(abs(red.red - 1) < 0.01 && red.green < 0.01 && red.blue < 0.01)
        }
    }

    @Test(arguments: [
        ("Classic White", LyreThemeStyle.porcelain), ("Classic Black", .onyx), ("U2 Black & Red", .crimson),
        ("Lyre Nano", .slim), ("Nano Space Gray", .slimGraphite), ("Shuffle Gold", .clipGold),
        ("Lyre Mini Pink", .pebblePink), ("Green Screen", .phosphor),
    ])
    func anUpgradeFromBefore1_0KeepsItsFinish(_ legacy: String, _ style: LyreThemeStyle) {
        withCleanDefaults(themeKeys) {
            UserDefaults.standard.set(legacy, forKey: "LyreThemeStyle")
            #expect(ThemeSettings().themeStyle == style)
        }
    }

    @Test func aDamagedSettingFallsBackRatherThanCrashing() {
        withCleanDefaults(themeKeys) {
            let defaults = UserDefaults.standard
            defaults.set("No Such Finish", forKey: "LyreThemeStyle")
            defaults.set("Gigantic", forKey: "LyreScreenSize")
            defaults.set("Ludicrous", forKey: "LyreScrollSensitivity")
            defaults.set(Data("not json".utf8), forKey: "LyreCustomHighlightColor")
            defaults.set("theremin", forKey: "LyrePlayerStyle")

            let settings = ThemeSettings()
            #expect(settings.themeStyle == .porcelain)
            #expect(settings.screenSize == LyreThemeStyle.porcelain.defaultScreenSize)
            #expect(settings.scrollSensitivity == .medium)
            #expect(settings.playerStyle == .classic)
        }
    }

    @Test func automaticScreenSizeFollowsTheBody() {
        withCleanDefaults(themeKeys) {
            let settings = ThemeSettings()
            settings.screenSize = .jumbo
            settings.useAutoScreenSize = true
            #expect(settings.screenSize == settings.themeStyle.defaultScreenSize)

            for style in LyreThemeStyle.allCases {
                settings.themeStyle = style
                #expect(settings.screenSize == style.defaultScreenSize, "\(style)")
            }
        }
    }

    @Test func aChosenScreenSizeStaysWhenTheBodyChanges() {
        withCleanDefaults(themeKeys) {
            let settings = ThemeSettings()
            settings.useAutoScreenSize = false
            settings.screenSize = .jumbo
            settings.themeStyle = .slim
            #expect(settings.screenSize == .jumbo)
        }
    }

    @Test func theHighlightIsTheBodysOwnUntilACustomOneIsTurnedOn() {
        withCleanDefaults(themeKeys) {
            let settings = ThemeSettings()
            settings.customHighlightColor = Color(red: 0, green: 1, blue: 0)
            settings.useCustomHighlight = false
            let own = settings.currentTheme.highlightColor.toStorableColor()
            settings.useCustomHighlight = true
            let custom = settings.currentTheme.highlightColor.toStorableColor()
            #expect(abs(custom.green - 1) < 0.01 && custom.red < 0.01)
            #expect(own.green != custom.green || own.red != custom.red)
        }
    }
}

// MARK: - Colors

@Suite("StorableColor")
@MainActor
struct StorableColorTests {

    @Test func aColorRoundTripsThroughStorage() throws {
        let original = StorableColor(red: 0.2, green: 0.4, blue: 0.6, opacity: 0.8)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StorableColor.self, from: data)
        let back = decoded.toColor().toStorableColor()
        #expect(abs(back.red - 0.2) < 0.01)
        #expect(abs(back.green - 0.4) < 0.01)
        #expect(abs(back.blue - 0.6) < 0.01)
        #expect(abs(back.opacity - 0.8) < 0.01)
    }

    @Test func aGreyIsStoredAsEqualChannels() {
        let grey = Color(white: 0.5).toStorableColor()
        #expect(abs(grey.red - grey.green) < 0.01 && abs(grey.green - grey.blue) < 0.01)
        #expect(abs(grey.red - 0.5) < 0.05)
        #expect(grey.opacity == 1)
    }
}

// MARK: - Library Cache

@Suite("LibraryCache", .serialized)
@MainActor
struct LibraryCacheTests {

    private var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LibrarySnapshot.plist")
    }

    /// Keeps whatever cache the host app had, and puts it back afterwards.
    private func preservingCache(_ body: () async throws -> Void) async rethrows {
        let saved = try? Data(contentsOf: cacheURL)
        defer {
            if let saved { try? saved.write(to: cacheURL) } else { LibraryCache.clear() }
        }
        try await body()
    }

    private func snapshot() -> LibrarySnapshot {
        let a = AppTrack(id: "a", title: "Alpha", artistName: "Band", albumTitle: "First", duration: 200,
                         mpPersistentID: UInt64.max)  // the top of the range, stored as a bit pattern
        let b = AppTrack(id: "b", title: "Beta", artistName: "Band", albumTitle: "First", duration: 180,
                         mpPersistentID: 42)
        let c = AppTrack(id: "c", title: "Gamma", artistName: "Solo", albumTitle: "Second", duration: 0)
        var snapshot = LibrarySnapshot()
        snapshot.songs = [a, b, c]
        snapshot.recentlyAdded = [c]
        snapshot.recentlyPlayed = [b, a]
        let first = AppAlbum(id: "al1", title: "First", artistName: "Band",
                             releaseDate: Date(timeIntervalSince1970: 1_000_000), preloadedTracks: [a, b])
        snapshot.albums = [first]
        snapshot.artists = [AppArtist(id: "ar1", name: "Band", preloadedAlbums: [first])]
        snapshot.playlists = [AppPlaylist(id: "p1", name: "Mix", curatorName: "Me", preloadedTracks: [c, a, c])]
        return snapshot
    }

    @Test func aLibraryComesBackAsItWasSaved() async throws {
        try await preservingCache {
            await LibraryCache.save(snapshot(), source: .localMedia)
            let restored = try #require(await LibraryCache.load())
            let library = restored.snapshot
            #expect(restored.source == .localMedia)
            #expect(library.songs.map(\.id) == ["a", "b", "c"])
            #expect(library.recentlyAdded.map(\.id) == ["c"])
            #expect(library.recentlyPlayed.map(\.id) == ["b", "a"])
            #expect(library.albums.first?.preloadedTracks.map(\.id) == ["a", "b"])
            #expect(library.albums.first?.releaseDate == Date(timeIntervalSince1970: 1_000_000))
            #expect(library.artists.first?.preloadedAlbums.first?.title == "First")
            // A playlist keeps a song it lists twice.
            #expect(library.playlists.first?.preloadedTracks.map(\.id) == ["c", "a", "c"])
            #expect(library.playlists.first?.curatorName == "Me")
            #expect(library.songs.first?.mpPersistentID == UInt64.max)
            #expect(library.songs[1].mpPersistentID == 42)
            #expect(library.songs[2].mpPersistentID == nil)
        }
    }

    @Test func anEmptyLibraryRoundTrips() async throws {
        try await preservingCache {
            await LibraryCache.save(LibrarySnapshot(), source: .none)
            let restored = try #require(await LibraryCache.load())
            #expect(restored.snapshot.songs.isEmpty)
            #expect(restored.snapshot.albums.isEmpty)
        }
    }

    @Test func noCacheIsAnOrdinaryFirstLaunch() async {
        await preservingCache {
            LibraryCache.clear()
            #expect(await LibraryCache.load() == nil)
        }
    }

    @Test func aDamagedCacheIsThrownAway() async {
        await preservingCache {
            try? Data("half a plist".utf8).write(to: cacheURL)
            #expect(await LibraryCache.load() == nil)
            #expect(!FileManager.default.fileExists(atPath: cacheURL.path), "A file that can't be read is deleted")
        }
    }

    @Test func aCacheFromAnOlderVersionIsIgnored() async throws {
        try await preservingCache {
            let old: [String: Any] = [
                "formatVersion": 1, "source": "localMedia", "tracks": [], "songIDs": [], "recentlyAddedIDs": [],
                "recentlyPlayedIDs": [], "albums": [], "artists": [], "playlists": [],
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: old, format: .binary, options: 0)
            try data.write(to: cacheURL)
            #expect(await LibraryCache.load() == nil)
        }
    }

    @Test func revokingAccessClearsTheCache() async {
        await preservingCache {
            await LibraryCache.save(snapshot(), source: .localMedia)
            LibraryCache.clear()
            #expect(await LibraryCache.load() == nil)
        }
    }
}

// MARK: - Podcast Subscriptions On Disk

@Suite("PodcastSubscriptions", .serialized)
@MainActor
struct PodcastSubscriptionStoreTests {

    private func feed(_ url: String, title: String = "Show", episodes: Int = 1) -> FeedShow {
        FeedShow(feedURL: URL(string: url)!, title: title, author: nil, artworkURL: nil,
                 episodes: (0..<episodes).map {
                     FeedEpisode(guid: "\(url)#\($0)", title: "Ep \($0)", audioURL: URL(string: "\(url)/\($0).mp3")!,
                                 published: nil, duration: 60, artworkURL: nil)
                 },
                 lastRefreshed: .now)
    }

    @Test func storingTheSameFeedAgainReplacesIt() {
        let store = PodcastSubscriptions()
        let url = "https://\(UUID().uuidString).lyre.test/f.xml"
        defer { store.remove(URL(string: url)!) }
        store.store(feed(url, episodes: 1))
        store.store(feed(url, episodes: 3))
        #expect(store.feeds.filter { $0.feedURL.absoluteString == url }.count == 1)
        #expect(store.feeds.first { $0.feedURL.absoluteString == url }?.episodes.count == 3)
    }

    @Test func aFeedThatMovedReplacesItsOldAddress() {
        let store = PodcastSubscriptions()
        let old = "https://\(UUID().uuidString).lyre.test/old.xml"
        let new = "https://\(UUID().uuidString).lyre.test/new.xml"
        defer { store.remove(URL(string: old)!); store.remove(URL(string: new)!) }
        store.store(feed(old))
        store.store(feed(new), replacing: URL(string: old)!)
        #expect(!store.isSubscribed(URL(string: old)!))
        #expect(store.isSubscribed(URL(string: new)!))
    }

    @Test func anEpisodePicksUpWhereItWasLeftAndFinishingForgetsIt() {
        let store = PodcastSubscriptions()
        let id = "feed.\(UUID().uuidString)"
        #expect(store.position(for: id) == 0)
        store.setPosition(754, for: id)
        #expect(store.position(for: id) == 754)
        #expect(PodcastSubscriptions().position(for: id) == 754, "Positions survive a relaunch")
        store.setPosition(0, for: id)
        #expect(store.position(for: id) == 0)
        #expect(PodcastSubscriptions().position(for: id) == 0)
    }

    @Test func aNegativePositionCountsAsTheStart() {
        let store = PodcastSubscriptions()
        let id = "feed.\(UUID().uuidString)"
        store.setPosition(-3, for: id)
        #expect(store.position(for: id) == 0)
    }

    @Test func aFeedRecordRoundTripsThroughJSON() throws {
        let original = FeedShow(
            feedURL: URL(string: "https://a.lyre.test/f.xml")!, title: "Show", author: "Host",
            artworkURL: URL(string: "https://a.lyre.test/a.jpg"),
            episodes: [FeedEpisode(guid: "g", title: "Ep", audioURL: URL(string: "https://a.lyre.test/g.mp3")!,
                                   published: Date(timeIntervalSince1970: 1_700_000_000), duration: nil,
                                   artworkURL: nil)],
            lastRefreshed: Date(timeIntervalSince1970: 1_700_000_100))
        let decoded = try JSONDecoder().decode(FeedShow.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }
}
