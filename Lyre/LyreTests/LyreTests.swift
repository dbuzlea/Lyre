//
//  LyreTests.swift
//  LyreTests
//

import Testing
import SceneKit
import simd
import UIKit
import MediaPlayer
import AVFoundation
import AudioToolbox
@testable import Lyre

// MARK: - RepeatMode

@Suite("RepeatMode")
struct RepeatModeTests {

    @Test func rawValues() {
        #expect(RepeatMode.off.rawValue == "Off")
        #expect(RepeatMode.one.rawValue == "One")
        #expect(RepeatMode.all.rawValue == "All")
    }

    @Test func icons() {
        #expect(RepeatMode.off.icon == "repeat")
        #expect(RepeatMode.one.icon == "repeat.1")
        #expect(RepeatMode.all.icon == "repeat")
    }

    @Test func mpRepeatModeMapping() {
        #expect(RepeatMode.off.mpRepeatMode == .none)
        #expect(RepeatMode.one.mpRepeatMode == .one)
        #expect(RepeatMode.all.mpRepeatMode == .all)
    }

    @Test func allCasesCount() {
        #expect(RepeatMode.allCases.count == 3)
    }

    @Test func initFromRawValue() {
        #expect(RepeatMode(rawValue: "Off") == .off)
        #expect(RepeatMode(rawValue: "One") == .one)
        #expect(RepeatMode(rawValue: "All") == .all)
        #expect(RepeatMode(rawValue: "invalid") == nil)
    }
}

// MARK: - ShuffleMode

@Suite("ShuffleMode")
struct ShuffleModeTests {

    @Test func rawValues() {
        #expect(ShuffleMode.off.rawValue == "Off")
        #expect(ShuffleMode.songs.rawValue == "Songs")
    }

    @Test func iconIsAlwaysShuffle() {
        #expect(ShuffleMode.off.icon == "shuffle")
        #expect(ShuffleMode.songs.icon == "shuffle")
    }

    @Test func mpShuffleModeMapping() {
        #expect(ShuffleMode.off.mpShuffleMode == .off)
        #expect(ShuffleMode.songs.mpShuffleMode == .songs)
    }

    @Test func allCasesCount() {
        #expect(ShuffleMode.allCases.count == 2)
    }

    @Test func initFromRawValue() {
        #expect(ShuffleMode(rawValue: "Off") == .off)
        #expect(ShuffleMode(rawValue: "Songs") == .songs)
        #expect(ShuffleMode(rawValue: "invalid") == nil)
    }
}

// MARK: - SelectionState

@Suite("SelectionState")
struct SelectionStateTests {

    @Test func defaultValues() {
        let state = SelectionState()
        #expect(state.menuSelection == 0)
        #expect(state.songSelection == 0)
        #expect(state.detailSelection == 0)
    }

    @Test func customInit() {
        let state = SelectionState(menuSelection: 2, songSelection: 5, detailSelection: 1)
        #expect(state.menuSelection == 2)
        #expect(state.songSelection == 5)
        #expect(state.detailSelection == 1)
    }

    @Test func equalityWhenSame() {
        let a = SelectionState(menuSelection: 1, songSelection: 2, detailSelection: 3)
        let b = SelectionState(menuSelection: 1, songSelection: 2, detailSelection: 3)
        #expect(a == b)
    }

    @Test func inequalityWhenDifferent() {
        let a = SelectionState(menuSelection: 0)
        let b = SelectionState(menuSelection: 1)
        #expect(a != b)
    }

    @Test func mutation() {
        var state = SelectionState()
        state.menuSelection = 3
        state.songSelection = 7
        #expect(state.menuSelection == 3)
        #expect(state.songSelection == 7)
        #expect(state.detailSelection == 0)
    }
}

// MARK: - AppTrack

@Suite("AppTrack")
@MainActor
struct AppTrackTests {

    @Test func basicInit() {
        let track = AppTrack(id: "1", title: "Song", artistName: "Artist", albumTitle: "Album", duration: 180)
        #expect(track.id == "1")
        #expect(track.title == "Song")
        #expect(track.artistName == "Artist")
        #expect(track.albumTitle == "Album")
        #expect(track.duration == 180)
        #expect(track.musicKitSong == nil)
        #expect(track.musicKitTrack == nil)
    }

    @Test func equalityBasedOnId() {
        let a = AppTrack(id: "42", title: "Song A", artistName: "X", albumTitle: "Y", duration: 100)
        let b = AppTrack(id: "42", title: "Song B", artistName: "Z", albumTitle: "W", duration: 200)
        #expect(a == b)
    }

    @Test func inequalityDifferentIds() {
        let a = AppTrack(id: "1", title: "Same", artistName: "Same", albumTitle: "Same", duration: 100)
        let b = AppTrack(id: "2", title: "Same", artistName: "Same", albumTitle: "Same", duration: 100)
        #expect(a != b)
    }

    @Test func usableInSet() {
        let t1 = AppTrack(id: "1", title: "A", artistName: "A", albumTitle: "A", duration: 0)
        let t2 = AppTrack(id: "1", title: "B", artistName: "B", albumTitle: "B", duration: 0)
        let t3 = AppTrack(id: "2", title: "C", artistName: "C", albumTitle: "C", duration: 0)
        let set: Set<AppTrack> = [t1, t2, t3]
        #expect(set.count == 2)
    }

    @Test func zeroDuration() {
        let track = AppTrack(id: "x", title: "Silent", artistName: "", albumTitle: "", duration: 0)
        #expect(track.duration == 0)
    }
}

// MARK: - PlaybackQueue

@Suite("PlaybackQueue")
@MainActor
struct PlaybackQueueTests {

    private func track(_ id: String) -> AppTrack {
        AppTrack(id: id, title: "Song \(id)", artistName: "Artist", albumTitle: "Album", duration: 100)
    }

    private func queue(_ ids: [String], currentIndex: Int = 0) -> PlaybackQueue {
        PlaybackQueue(tracks: ids.map(track), currentIndex: currentIndex)
    }

    @Test func emptyQueue() {
        let queue = PlaybackQueue()
        #expect(queue.isEmpty)
        #expect(queue.current == nil)
        #expect(queue.upNext.isEmpty)
        #expect(queue.upNextCount == 0)
    }

    @Test func currentIndexIsClampedToTheTrackCount() {
        #expect(queue(["a", "b"], currentIndex: 9).currentIndex == 1)
        #expect(queue(["a", "b"], currentIndex: -3).currentIndex == 0)
        #expect(PlaybackQueue(tracks: [], currentIndex: 4).currentIndex == 0)
    }

    @Test func upNextExcludesCurrentAndHistory() {
        let queue = self.queue(["a", "b", "c", "d"], currentIndex: 1)
        #expect(queue.current == track("b"))
        #expect(queue.upNext.map(\.id) == ["c", "d"])
        #expect(queue.upNextCount == 2)
    }

    @Test func upNextIsEmptyOnTheLastTrack() {
        let queue = self.queue(["a", "b"], currentIndex: 1)
        #expect(queue.upNext.isEmpty)
        #expect(queue.upNextCount == 0)
    }

    @Test func appendGoesToTheBottom() {
        var queue = self.queue(["a", "b"], currentIndex: 0)
        queue.append(track("c"))
        queue.append(track("d"))
        #expect(queue.upNext.map(\.id) == ["b", "c", "d"])
    }

    @Test func insertUpNextGoesStraightAfterTheCurrentTrack() {
        var queue = self.queue(["a", "b", "c"], currentIndex: 1)
        queue.insertUpNext([track("x"), track("y")])
        #expect(queue.tracks.map(\.id) == ["a", "b", "x", "y", "c"])
        #expect(queue.current == track("b"))
        #expect(queue.upNext.map(\.id) == ["x", "y", "c"])
    }

    @Test func insertUpNextOnAnEmptyQueueBecomesTheQueue() {
        var queue = PlaybackQueue()
        queue.insertUpNext([track("x"), track("y")])
        #expect(queue.tracks.map(\.id) == ["x", "y"])
        #expect(queue.currentIndex == 0)
    }

    @Test func moveUpNextReordersRelativeToUpNext() {
        var queue = self.queue(["a", "b", "c", "d"], currentIndex: 1)
        queue.moveUpNext(from: 1, to: 0)
        #expect(queue.upNext.map(\.id) == ["d", "c"])
        // The played track and the current one are untouched.
        #expect(queue.current == track("b"))
        #expect(queue.tracks.map(\.id) == ["a", "b", "d", "c"])
    }

    @Test func moveUpNextToTheEnd() {
        var queue = self.queue(["a", "b", "c", "d"], currentIndex: 0)
        queue.moveUpNext(from: 0, to: 2)
        #expect(queue.upNext.map(\.id) == ["c", "d", "b"])
    }

    @Test func moveUpNextIgnoresOutOfRangeOffsets() {
        var queue = self.queue(["a", "b", "c"], currentIndex: 0)
        queue.moveUpNext(from: 0, to: 5)
        queue.moveUpNext(from: -1, to: 0)
        queue.moveUpNext(from: 0, to: 0)
        #expect(queue.upNext.map(\.id) == ["b", "c"])
    }

    @Test func removeUpNextReturnsTheRemovedTrack() {
        var queue = self.queue(["a", "b", "c"], currentIndex: 0)
        #expect(queue.removeUpNext(at: 1) == track("c"))
        #expect(queue.upNext.map(\.id) == ["b"])
    }

    @Test func removeUpNextIgnoresOutOfRangeOffsets() {
        var queue = self.queue(["a", "b"], currentIndex: 0)
        #expect(queue.removeUpNext(at: 4) == nil)
        #expect(queue.removeUpNext(at: -1) == nil)
        #expect(queue.upNext.map(\.id) == ["b"])
    }

    @Test func removeUpNextCannotRemoveTheCurrentTrack() {
        var queue = self.queue(["a", "b"], currentIndex: 1)
        #expect(queue.removeUpNext(at: 0) == nil)
        #expect(queue.current == track("b"))
    }

    @Test func removeAllUpNextKeepsCurrentAndHistory() {
        var queue = self.queue(["a", "b", "c", "d"], currentIndex: 1)
        #expect(queue.removeAllUpNext() == 2)
        #expect(queue.tracks.map(\.id) == ["a", "b"])
        #expect(queue.current == track("b"))
        #expect(queue.upNext.isEmpty)
    }

    @Test func removeAllUpNextOnAnEmptyUpNextChangesNothing() {
        var queue = self.queue(["a", "b"], currentIndex: 1)
        #expect(queue.removeAllUpNext() == 0)
        #expect(queue.tracks.map(\.id) == ["a", "b"])
        #expect(queue.currentIndex == 1)
    }

    @Test func appendingACollectionKeepsItsOrder() {
        // Queueing a whole album appends its tracks one after another, so the album
        // has to come out of Up Next in the order it went in.
        var queue = self.queue(["a", "b"], currentIndex: 0)
        for id in ["c", "d", "e"] { queue.append(track(id)) }
        #expect(queue.upNext.map(\.id) == ["b", "c", "d", "e"])
    }

    @Test func appendKeepsHistoryIntactForSkippingBack() {
        // The player queue is rebuilt from `tracks` in full, so already-played songs
        // have to survive a queue change or skip-back would stop working.
        var queue = self.queue(["a", "b", "c"], currentIndex: 1)
        queue.append(track("d"))
        #expect(queue.tracks.map(\.id) == ["a", "b", "c", "d"])
        #expect(queue.currentIndex == 1)
        #expect(queue.upNext.map(\.id) == ["c", "d"])
    }

    @Test func advanceCurrentFailsWithoutBackingMediaItems() {
        // Tracks built by hand have no MPMediaItem, so nothing can match a persistent
        // ID — the model treats that as "the player left our queue".
        var queue = self.queue(["a", "b"], currentIndex: 0)
        #expect(queue.advanceCurrent(toPersistentID: 12345) == false)
        #expect(queue.currentIndex == 0)
    }
}

// MARK: - AppAlbum

@Suite("AppAlbum")
@MainActor
struct AppAlbumTests {

    @Test func basicInit() {
        let album = AppAlbum(id: "a1", title: "Abbey Road", artistName: "The Beatles")
        #expect(album.id == "a1")
        #expect(album.title == "Abbey Road")
        #expect(album.artistName == "The Beatles")
        #expect(album.releaseDate == nil)
        #expect(album.preloadedTracks.isEmpty)
    }

    @Test func equalityBasedOnId() {
        let a = AppAlbum(id: "same", title: "Title A", artistName: "X")
        let b = AppAlbum(id: "same", title: "Title B", artistName: "Y")
        #expect(a == b)
    }

    @Test func preloadedTracksAreMutable() {
        var album = AppAlbum(id: "a1", title: "Test", artistName: "Artist")
        let track = AppTrack(id: "t1", title: "Track 1", artistName: "Artist", albumTitle: "Test", duration: 200)
        album.preloadedTracks.append(track)
        #expect(album.preloadedTracks.count == 1)
        #expect(album.preloadedTracks[0].id == "t1")
    }

    @Test func usableInSet() {
        let a1 = AppAlbum(id: "1", title: "A", artistName: "X")
        let a2 = AppAlbum(id: "1", title: "B", artistName: "Y")
        let a3 = AppAlbum(id: "2", title: "C", artistName: "Z")
        let set: Set<AppAlbum> = [a1, a2, a3]
        #expect(set.count == 2)
    }
}

// MARK: - AppArtist

@Suite("AppArtist")
struct AppArtistTests {

    @Test func basicInit() {
        let artist = AppArtist(id: "ar1", name: "The Beatles")
        #expect(artist.id == "ar1")
        #expect(artist.name == "The Beatles")
        #expect(artist.musicKitArtist == nil)
        #expect(artist.preloadedAlbums.isEmpty)
    }

    @Test func equalityBasedOnId() {
        let a = AppArtist(id: "same", name: "A")
        let b = AppArtist(id: "same", name: "B")
        #expect(a == b)
    }

    @Test func preloadedAlbumsAreMutable() {
        var artist = AppArtist(id: "ar1", name: "Test Artist")
        let album = AppAlbum(id: "al1", title: "Album", artistName: "Test Artist")
        artist.preloadedAlbums.append(album)
        #expect(artist.preloadedAlbums.count == 1)
    }
}

// MARK: - AppPlaylist

@Suite("AppPlaylist")
struct AppPlaylistTests {

    @Test func basicInit() {
        let playlist = AppPlaylist(id: "p1", name: "Chill Mix")
        #expect(playlist.id == "p1")
        #expect(playlist.name == "Chill Mix")
        #expect(playlist.curatorName == nil)
        #expect(playlist.preloadedTracks.isEmpty)
    }

    @Test func withCuratorName() {
        let playlist = AppPlaylist(id: "p2", name: "Top Hits", curatorName: "Apple Music")
        #expect(playlist.curatorName == "Apple Music")
    }

    @Test func equalityBasedOnId() {
        let a = AppPlaylist(id: "same", name: "A")
        let b = AppPlaylist(id: "same", name: "B")
        #expect(a == b)
    }

    @Test func preloadedTracksAreMutable() {
        var playlist = AppPlaylist(id: "p1", name: "Mix")
        let track = AppTrack(id: "t1", title: "Track", artistName: "A", albumTitle: "B", duration: 100)
        playlist.preloadedTracks.append(track)
        #expect(playlist.preloadedTracks.count == 1)
    }
}

// MARK: - AppHelpers: formatTime

@Suite("AppHelpers.formatTime")
struct FormatTimeTests {

    @Test func zeroSeconds() {
        #expect(AppHelpers.formatTime(0) == "0:00")
    }

    @Test func belowOneMinute() {
        #expect(AppHelpers.formatTime(5) == "0:05")
        #expect(AppHelpers.formatTime(59) == "0:59")
    }

    @Test func exactlyOneMinute() {
        #expect(AppHelpers.formatTime(60) == "1:00")
    }

    @Test func minutesAndSeconds() {
        #expect(AppHelpers.formatTime(125) == "2:05")
        #expect(AppHelpers.formatTime(3661) == "61:01")
    }

    @Test func truncatesDecimalSeconds() {
        // TimeInterval with fractional part — should truncate, not round
        #expect(AppHelpers.formatTime(59.9) == "0:59")
    }
}

// MARK: - AppHelpers: firstLetter

@Suite("AppHelpers.firstLetter")
struct FirstLetterTests {

    @Test func regularLetters() {
        #expect(AppHelpers.firstLetter(of: "Abbey Road") == "A")
        #expect(AppHelpers.firstLetter(of: "born to run") == "B")
        #expect(AppHelpers.firstLetter(of: "Ziggy Stardust") == "Z")
    }

    @Test func uppercasesResult() {
        #expect(AppHelpers.firstLetter(of: "lowercase") == "L")
    }

    @Test func startsWithNumber() {
        #expect(AppHelpers.firstLetter(of: "1999") == "#")
        #expect(AppHelpers.firstLetter(of: "2001") == "#")
    }

    @Test func startsWithSpecialChar() {
        #expect(AppHelpers.firstLetter(of: "...Baby One More Time") == "#")
        #expect(AppHelpers.firstLetter(of: "!") == "#")
    }

    @Test func emptyString() {
        #expect(AppHelpers.firstLetter(of: "") == "#")
    }

    @Test func unicodeLetter() {
        // Accented letters are still letters
        #expect(AppHelpers.firstLetter(of: "Ólafur Arnalds") == "Ó")
    }

    @Test func skipsLeadingArticle() {
        // The Music library files these under the word after the article, so the
        // scrubber and section headers must too.
        #expect(AppHelpers.firstLetter(of: "The Game Has Changed") == "G")
        #expect(AppHelpers.firstLetter(of: "the weeknd") == "W")
        #expect(AppHelpers.firstLetter(of: "A Day in the Life") == "D")
        #expect(AppHelpers.firstLetter(of: "An Ending") == "E")
    }

    @Test func keepsArticleThatIsTheWholeNameOrAWordPrefix() {
        #expect(AppHelpers.firstLetter(of: "The") == "T")
        #expect(AppHelpers.firstLetter(of: "A") == "A")
        #expect(AppHelpers.firstLetter(of: "Theory") == "T")
        #expect(AppHelpers.firstLetter(of: "Another One Bites the Dust") == "A")
    }
}

// MARK: - AppHelpers: sortsBefore

@Suite("AppHelpers.sortsBefore")
struct SortsBeforeTests {

    @Test func ordersIgnoringLeadingArticle() {
        let sorted = ["Gasoline", "The Game Has Changed", "Gangnam Style", "Thriller"]
            .sorted(by: AppHelpers.sortsBefore)
        #expect(sorted == ["The Game Has Changed", "Gangnam Style", "Gasoline", "Thriller"])
    }

    @Test func sectionLettersNeverGoBackwards() {
        // A list sorted this way must never produce an out-of-order section letter,
        // which is what made the scrubber jump from G to T mid-section.
        let letters = ["Zebra", "The Beatles", "A Tribe Called Quest", "Coldplay", "The Weeknd"]
            .sorted(by: AppHelpers.sortsBefore)
            .map { AppHelpers.firstLetter(of: $0) }
        #expect(letters == letters.sorted())
    }
}

// MARK: - AppHelpers: batteryIconName

@Suite("AppHelpers.batteryIconName")
struct BatteryIconNameTests {

    @Test func chargingAlwaysReturnsBolt() {
        #expect(AppHelpers.batteryIconName(level: 0.0, state: .charging) == "battery.100.bolt")
        #expect(AppHelpers.batteryIconName(level: 0.5, state: .charging) == "battery.100.bolt")
        #expect(AppHelpers.batteryIconName(level: 1.0, state: .charging) == "battery.100.bolt")
    }

    @Test func fullStateReturnsBolt() {
        #expect(AppHelpers.batteryIconName(level: 1.0, state: .full) == "battery.100.bolt")
    }

    @Test func highBattery() {
        #expect(AppHelpers.batteryIconName(level: 0.90, state: .unplugged) == "battery.100")
        #expect(AppHelpers.batteryIconName(level: 1.00, state: .unplugged) == "battery.100")
    }

    @Test func mediumHighBattery() {
        #expect(AppHelpers.batteryIconName(level: 0.75, state: .unplugged) == "battery.75")
        #expect(AppHelpers.batteryIconName(level: 0.89, state: .unplugged) == "battery.75")
    }

    @Test func mediumBattery() {
        #expect(AppHelpers.batteryIconName(level: 0.50, state: .unplugged) == "battery.50")
        #expect(AppHelpers.batteryIconName(level: 0.74, state: .unplugged) == "battery.50")
    }

    @Test func lowMediumBattery() {
        #expect(AppHelpers.batteryIconName(level: 0.25, state: .unplugged) == "battery.25")
        #expect(AppHelpers.batteryIconName(level: 0.49, state: .unplugged) == "battery.25")
    }

    @Test func lowBattery() {
        #expect(AppHelpers.batteryIconName(level: 0.01, state: .unplugged) == "battery.0")
        #expect(AppHelpers.batteryIconName(level: 0.24, state: .unplugged) == "battery.0")
        #expect(AppHelpers.batteryIconName(level: 0.00, state: .unplugged) == "battery.0")
    }
}

// MARK: - AppHelpers: batteryIsLow

@Suite("AppHelpers.batteryIsLow")
struct BatteryIsLowTests {

    @Test func trueWhenBelowThresholdAndUnplugged() {
        #expect(AppHelpers.batteryIsLow(level: 0.19, state: .unplugged) == true)
        #expect(AppHelpers.batteryIsLow(level: 0.00, state: .unplugged) == true)
    }

    @Test func falseAtThreshold() {
        #expect(AppHelpers.batteryIsLow(level: 0.20, state: .unplugged) == false)
    }

    @Test func falseWhenCharging() {
        #expect(AppHelpers.batteryIsLow(level: 0.05, state: .charging) == false)
    }

    @Test func falseWhenFull() {
        #expect(AppHelpers.batteryIsLow(level: 0.05, state: .full) == false)
    }

    @Test func falseWhenAboveThreshold() {
        #expect(AppHelpers.batteryIsLow(level: 0.50, state: .unplugged) == false)
        #expect(AppHelpers.batteryIsLow(level: 1.00, state: .unplugged) == false)
    }
}

// MARK: - MusicLoadError

@Suite("MusicLoadError")
struct MusicLoadErrorTests {

    @Test func alertTitles() {
        #expect(MusicLoadError.notAuthorized.alertTitle == "Permission Required")
        #expect(MusicLoadError.noNetwork.alertTitle    == "No Internet Connection")
        #expect(MusicLoadError.serverError.alertTitle  == "Service Unavailable")
        #expect(MusicLoadError.unknown.alertTitle      == "Something Went Wrong")
    }

    @Test func allTitlesAreUnique() {
        let titles = [
            MusicLoadError.notAuthorized.alertTitle,
            MusicLoadError.noNetwork.alertTitle,
            MusicLoadError.serverError.alertTitle,
            MusicLoadError.unknown.alertTitle
        ]
        #expect(Set(titles).count == 4)
    }

    @Test func errorDescriptionsAreNonEmpty() {
        for error in [MusicLoadError.notAuthorized, .noNetwork, .serverError, .unknown] {
            #expect(!error.localizedDescription.isEmpty)
        }
    }

    @Test func notAuthorizedDescriptionMentionsSettings() {
        #expect(MusicLoadError.notAuthorized.localizedDescription.contains("Settings"))
    }

    @Test func noNetworkDescriptionMentionsConnectivity() {
        let desc = MusicLoadError.noNetwork.localizedDescription
        #expect(desc.lowercased().contains("internet") || desc.lowercased().contains("wi-fi"))
    }

    @Test func serverErrorDescriptionMentionsAppleMusic() {
        let desc = MusicLoadError.serverError.localizedDescription
        #expect(desc.contains("Apple Music") || desc.lowercased().contains("unavailable"))
    }

    @Test func retryability() {
        #expect(MusicLoadError.notAuthorized.isRetryable == false)
        #expect(MusicLoadError.noNetwork.isRetryable    == true)
        #expect(MusicLoadError.serverError.isRetryable  == true)
        #expect(MusicLoadError.unknown.isRetryable      == true)
    }

    @Test func equatable() {
        #expect(MusicLoadError.notAuthorized == .notAuthorized)
        #expect(MusicLoadError.noNetwork     == .noNetwork)
        #expect(MusicLoadError.noNetwork     != .serverError)
        #expect(MusicLoadError.unknown       != .notAuthorized)
    }

    @Test func classifiesNoInternetURLError() {
        let error = URLError(.notConnectedToInternet)
        #expect(MusicLoadError.from(error) == .noNetwork)
    }

    @Test func classifiesTimedOutURLError() {
        let error = URLError(.timedOut)
        #expect(MusicLoadError.from(error) == .noNetwork)
    }

    @Test func classifiesNetworkConnectionLostURLError() {
        let error = URLError(.networkConnectionLost)
        #expect(MusicLoadError.from(error) == .noNetwork)
    }

    @Test func classifiesOtherURLErrorAsServerError() {
        let error = URLError(.badServerResponse)
        #expect(MusicLoadError.from(error) == .serverError)
    }

    @Test func classifiesUnknownErrorAsUnknown() {
        struct SomeRandomError: Error {}
        #expect(MusicLoadError.from(SomeRandomError()) == .unknown)
    }
}

// MARK: - MusicService

@Suite("MusicService")
@MainActor
struct MusicServiceTests {

    @Test func initialLibraryIsEmpty() {
        let service = MusicService()
        #expect(service.songs.isEmpty)
        #expect(service.albums.isEmpty)
        #expect(service.artists.isEmpty)
        #expect(service.playlists.isEmpty)
        #expect(service.podcastShows.isEmpty)
    }

    /// A subscription to a show, with episodes published `days` ago.
    private func feedShow(_ title: String, url: String, episodes: [(String, Double)]) -> PodcastShow {
        PodcastShow(feed: FeedShow(
            feedURL: URL(string: url)!, title: title, author: nil, artworkURL: nil,
            episodes: episodes.map { name, days in
                FeedEpisode(guid: "\(url)#\(name)", title: name,
                            audioURL: URL(string: "https://example.invalid/\(name.hashValue).mp3")!,
                            published: Date(timeIntervalSinceNow: -days * 86_400), duration: 600, artworkURL: nil)
            },
            lastRefreshed: .now))
    }

    @Test func aShowHeardTwoWaysIsOneShowWithEveryEpisodeOnce() {
        let service = MusicService()
        service.podcastShows = [
            feedShow("Morning Somewhere", url: "https://example.invalid/a.xml", episodes: [("Monday", 3), ("Tuesday", 2)]),
            feedShow("Morning Somewhere", url: "https://example.invalid/b.xml", episodes: [("Tuesday", 2), ("Wednesday", 1)]),
            feedShow("Other Show", url: "https://example.invalid/c.xml", episodes: [("Pilot", 10)])
        ]
        let shows = service.mergedPodcastShows()
        #expect(shows.map(\.title) == ["Morning Somewhere", "Other Show"])
        // Together, each episode once, newest first.
        #expect(shows[0].episodes.map(\.title) == ["Wednesday", "Tuesday", "Monday"])
        #expect(shows[1].episodes.map(\.title) == ["Pilot"])
    }

    @Test func initialPlaybackState() {
        let service = MusicService()
        #expect(service.isPlaying == false)
        #expect(service.currentTrack == nil)
        #expect(service.currentTime == 0)
        #expect(service.isScrubbing == false)
    }

    @Test func initialErrorIsNil() {
        let service = MusicService()
        #expect(service.lastError == nil)
    }

    @Test func withNothingStreamingUpcomingIsUpNextAndCanBeEdited() {
        let service = MusicService()
        let tracks = (1...3).map { AppTrack(id: "\($0)", title: "Song \($0)", artistName: "A", albumTitle: "B", duration: 60) }
        service.seedQueueForUITests(tracks)
        #expect(service.upcoming.map(\.id) == ["2", "3"])
        #expect(service.canEditUpcoming)
        #expect(!service.isPlayingPodcast)
        #expect(service.nowPlayingTrack?.id == "1")
    }

    @Test func podcastSpeedIsKeptAndOffersTheUsualSteps() {
        let service = MusicService()
        let saved = service.podcastRate
        defer { service.setPodcastRate(saved) }
        service.setPodcastRate(1.5)
        #expect(service.podcastRate == 1.5)
        #expect(MusicService().podcastRate == 1.5)
        #expect(MusicService.podcastRates.first == 0.75 && MusicService.podcastRates.last == 2)
        #expect(MusicService.podcastRates.contains(1))
    }

    @Test func speedsReadAsADecksPitchMarkings() {
        #expect(SpoolPlayerView.speedText(1) == "1×")
        #expect(SpoolPlayerView.speedText(1.25) == "1.25×")
        #expect(SpoolPlayerView.speedText(0.75) == "0.75×")
        #expect(SpoolPlayerView.speedText(2) == "2×")
    }

    @Test func anEpisodeAsATrackKeepsItsIdAndShow() {
        let feed = FeedShow(feedURL: URL(string: "https://example.invalid/f.xml")!, title: "Show", author: nil,
                            artworkURL: nil,
                            episodes: [FeedEpisode(guid: "g", title: "Ep", audioURL: URL(string: "https://example.invalid/g.mp3")!,
                                                   published: nil, duration: 900, artworkURL: nil)],
                            lastRefreshed: .now)
        let track = PodcastShow(feed: feed).episodes[0].asTrack
        #expect(track.id == "feed.g")
        #expect(track.artistName == "Show" && track.title == "Ep" && track.duration == 900)
    }

    @Test func initialModesAreOff() {
        let service = MusicService()
        #expect(service.repeatMode == .off)
        #expect(service.shuffleMode == .off)
    }

    @Test func setAndClearLastError() {
        let service = MusicService()
        service.lastError = .noNetwork
        #expect(service.lastError == .noNetwork)
        service.lastError = nil
        #expect(service.lastError == nil)
    }

    @Test func scrubbingToggle() {
        let service = MusicService()
        #expect(service.isScrubbing == false)
        service.startScrubbing()
        #expect(service.isScrubbing == true)
        service.stopScrubbing()
        #expect(service.isScrubbing == false)
    }

    @Test func repeatModeCyclesOffAllOneOff() async {
        let service = MusicService()
        #expect(service.repeatMode == .off)
        await service.toggleRepeatMode()
        #expect(service.repeatMode == .all)
        await service.toggleRepeatMode()
        #expect(service.repeatMode == .one)
        await service.toggleRepeatMode()
        #expect(service.repeatMode == .off)
    }

    @Test func shuffleModeTogglesBetweenOffAndSongs() async {
        let service = MusicService()
        #expect(service.shuffleMode == .off)
        await service.toggleShuffleMode()
        #expect(service.shuffleMode == .songs)
        await service.toggleShuffleMode()
        #expect(service.shuffleMode == .off)
    }

    @Test func playEmptyTracksIsNoOp() async {
        let service = MusicService()
        await service.play(tracks: [], startingAt: 0)
        #expect(service.isPlaying == false)
    }

    @Test func playOutOfBoundsIndexIsNoOp() async {
        let service = MusicService()
        let track = AppTrack(id: "t1", title: "Song", artistName: "Artist", albumTitle: "Album", duration: 180)
        // index 5 is beyond a 1-item array — guarded in play(tracks:startingAt:)
        await service.play(tracks: [track], startingAt: 5)
        #expect(service.isPlaying == false)
    }
}

// MARK: - Vinyl Sides

@Suite("vinylSides")
struct VinylSidesTests {

    /// Builds a run of tracks with the given durations in seconds.
    private func tracks(_ durations: [TimeInterval]) -> [AppTrack] {
        durations.enumerated().map { index, duration in
            AppTrack(
                id: "t\(index)",
                title: "Track \(index + 1)",
                artistName: "Artist",
                albumTitle: "Album",
                duration: duration
            )
        }
    }

    private func runtime(_ side: [AppTrack]) -> TimeInterval {
        side.reduce(0) { $0 + $1.duration }
    }

    @Test func emptyTrackListHasNoSides() {
        #expect(vinylSides([]).isEmpty)
    }

    @Test func singleTrackIsOneSide() {
        let result = vinylSides(tracks([210]))
        #expect(result.count == 1)
        #expect(result.first?.count == 1)
    }

    @Test func exactlyTwentyTwoMinutesStaysOneSide() {
        // 11 tracks x 2:00 == 22:00 exactly, the ceiling for a single side.
        let result = vinylSides(tracks(Array(repeating: 120, count: 11)))
        #expect(runtime(result.flatMap { $0 }) == 22 * 60)
        #expect(result.count == 1)
    }

    @Test func justOverTwentyTwoMinutesBecomesTwoSides() {
        let result = vinylSides(tracks(Array(repeating: 120, count: 11) + [1]))
        #expect(result.count == 2)
    }

    @Test func unevenAlbumSplitsNearTheMiddleByTime() {
        // Front-loaded: three long tracks then six short ones. A track-count split would
        // cut 4/5 and leave the sides wildly uneven, so the cut has to be time-based.
        let result = vinylSides(tracks([600, 600, 600] + Array(repeating: 100, count: 6)))
        #expect(result.count == 2)

        let a = runtime(result[0])
        let b = runtime(result[1])
        // The best available cut is after track 2: 1200 vs 1200.
        #expect(abs(a - b) < 60)
        #expect(result[0].count == 2)
        #expect(result[1].count == 7)
    }

    @Test func albumOverFortyFourMinutesBecomesFourSides() {
        // 20 tracks x 2:30 == 50:00, past the two-side ceiling.
        let result = vinylSides(tracks(Array(repeating: 150, count: 20)))
        #expect(result.count == 4)
        #expect(result.allSatisfy { !$0.isEmpty })
        #expect(result.flatMap { $0 }.count == 20)
        #expect(result.allSatisfy { runtime($0) <= 22 * 60 })
    }

    @Test func everyTrackSurvivesTheSplitInOrder() {
        let source = tracks([300, 240, 420, 180, 360, 200, 480, 260, 340, 220])
        let flattened = vinylSides(source).flatMap { $0 }
        #expect(flattened.map(\.id) == source.map(\.id))
    }

    @Test func sideCountNeverExceedsTrackCount() {
        // Two very long tracks would want four sides by runtime, but cannot be cut finer
        // than the tracks themselves.
        let result = vinylSides(tracks([1800, 1800]))
        #expect(result.count == 2)
        #expect(result.allSatisfy { !$0.isEmpty })
    }

    @Test func sideLabelsRunAlphabetically() {
        #expect(vinylSideLabel(0) == "A")
        #expect(vinylSideLabel(1) == "B")
        #expect(vinylSideLabel(3) == "D")
    }
}

// MARK: - Shake to Shuffle

@Suite("Shake to Shuffle")
@MainActor
struct ShakeToShuffleTests {

    @Test func shakeShufflesWhenHoldIsOff() {
        let controller = ShakeViewController()
        var shakes = 0
        controller.onShake = { shakes += 1 }
        controller.motionEnded(.motionShake, with: nil)
        #expect(shakes == 1)
    }

    @Test func shakeIsIgnoredWhileHoldIsOn() {
        let controller = ShakeViewController()
        var shakes = 0
        controller.onShake = { shakes += 1 }
        controller.isHoldEnabled = true
        controller.motionEnded(.motionShake, with: nil)
        #expect(shakes == 0)
    }

    @Test func shakeWorksAgainOnceHoldIsOff() {
        let controller = ShakeViewController()
        var shakes = 0
        controller.onShake = { shakes += 1 }
        controller.isHoldEnabled = true
        controller.motionEnded(.motionShake, with: nil)
        controller.isHoldEnabled = false
        controller.motionEnded(.motionShake, with: nil)
        #expect(shakes == 1)
    }

    @Test func shakeIsIgnoredWithTheSpoolPlayer() {
        let controller = ShakeViewController()
        var shakes = 0
        controller.onShake = { shakes += 1 }
        controller.isShakeOff = true
        controller.motionEnded(.motionShake, with: nil)
        #expect(shakes == 0)
        // Nor does it hold first responder, which brings the keyboard up with menus.
        #expect(!controller.canBecomeFirstResponder)
        // Back to the classic player: shaking shuffles again.
        controller.isShakeOff = false
        controller.motionEnded(.motionShake, with: nil)
        #expect(shakes == 1)
    }

    @Test func otherMotionsNeverShuffle() {
        let controller = ShakeViewController()
        var shakes = 0
        controller.onShake = { shakes += 1 }
        controller.motionEnded(.none, with: nil)
        #expect(shakes == 0)
    }
}

// MARK: - Queue Rules

/// The rules every player's queue follows, kept in MusicService so the classic wheel, the
/// Artwork Carousel and the Spool can't drift apart.
@Suite("Queue Rules")
@MainActor
struct QueueRuleTests {

    private func tracks(_ count: Int) -> [AppTrack] {
        (1...count).map { AppTrack(id: "\($0)", title: "Song \($0)", artistName: "A", albumTitle: "B", duration: 60) }
    }

    private var episode: PodcastEpisode {
        let feed = FeedShow(feedURL: URL(string: "https://example.invalid/f.xml")!, title: "Show", author: nil,
                            artworkURL: nil,
                            episodes: [FeedEpisode(guid: "g", title: "Ep", audioURL: URL(string: "https://example.invalid/g.mp3")!,
                                                   published: nil, duration: 900, artworkURL: nil)],
                            lastRefreshed: .now)
        return PodcastShow(feed: feed).episodes[0]
    }

    @Test func everyPlayerSaysTheSameThingAboutAnAdd() {
        let next = QueueAddOutcome.queued(count: 1, skipped: 0)
        #expect(next.message(name: "Song", requested: 1, placement: .next, isCollection: false) == "Playing next: Song")
        #expect(next.message(name: "Song", requested: 1, placement: .last, isCollection: false) == "Queued: Song")
        #expect(QueueAddOutcome.startedPlaying(count: 1, skipped: 0)
            .message(name: "Song", requested: 1, placement: .last, isCollection: false) == "Playing: Song")
        #expect(QueueAddOutcome.unavailable.message(name: "X", requested: 1, placement: .last, isCollection: false)
            == String(localized: "queue.unavailable"))
        #expect(QueueAddOutcome.unavailable.message(name: "X", requested: 9, placement: .last, isCollection: true)
            == String(localized: "queue.collectionUnavailable"))
        #expect(QueueAddOutcome.podcastPlaying.message(name: "X", requested: 1, placement: .next, isCollection: false)
            == "Songs can't be queued while a podcast plays")
        #expect(next.succeeded && !QueueAddOutcome.podcastPlaying.succeeded && !QueueAddOutcome.unavailable.succeeded)
    }

    @Test func aPartAddSaysHowMuchWentIn() {
        let partial = QueueAddOutcome.queued(count: 9, skipped: 3)
        #expect(partial.message(name: "Album", requested: 12, placement: .last, isCollection: true)
            == String(format: String(localized: "queue.addedPartial"), 9, 12, "Album"))
        #expect(partial.message(name: "Album", requested: 12, placement: .next, isCollection: true)
            == String(format: String(localized: "queue.addedNextPartial"), 9, 12, "Album"))
    }

    @Test func songsAreTurnedAwayWhileAPodcastStreams() async {
        let service = MusicService()
        service.currentEpisode = episode
        #expect(service.isPlayingPodcast)
        let outcome = await service.addToQueue(tracks: tracks(2), placement: .next)
        #expect(outcome == .podcastPlaying)
    }

    @Test func anOnDevicePodcastsEpisodesCantBeEdited() {
        let service = MusicService()
        service.seedQueueForUITests(tracks(4))
        service.currentPodcastShowTitle = "Show"
        service.currentTrack = tracks(1)[0]
        #expect(service.isPlayingPodcast)
        #expect(!service.canEditUpcoming)
        #expect(service.removeFromQueue(at: 0) == nil)
        #expect(service.clearQueue() == 0)
        service.reorderUpNext(from: 0, to: 2)
        #expect(service.upcoming.map(\.id) == ["2", "3", "4"])
    }

    @Test func aFinishedOnDevicePodcastNoLongerCounts() {
        let service = MusicService()
        // The show's queue ran out: nothing is playing, so songs can be queued again.
        service.currentPodcastShowTitle = "Show"
        service.currentTrack = nil
        #expect(!service.isPlayingPodcast)
    }

    @Test func aSongQueueCanBeEdited() {
        let service = MusicService()
        service.seedQueueForUITests(tracks(4))
        #expect(service.canEditUpcoming)
        service.reorderUpNext(from: 0, to: 2)
        #expect(service.upcoming.map(\.id) == ["3", "4", "2"])
    }

    @Test func anAlbumLoadsEachSongOnceForEveryPlayer() async {
        let service = MusicService()
        let songs = [AppTrack(id: "1", title: "Take My Breath", artistName: "A", albumTitle: "B", duration: 339),
                     AppTrack(id: "2", title: "Sacrifice", artistName: "A", albumTitle: "B", duration: 188),
                     AppTrack(id: "3", title: "Sacrifice", artistName: "A", albumTitle: "B", duration: 188)]
        let album = AppAlbum(id: "a", title: "Dawn FM", artistName: "A", preloadedTracks: songs)
        #expect(await service.loadTracks(for: album).map(\.id) == ["1", "2"])
        // A playlist keeps its repeats.
        let playlist = AppPlaylist(id: "p", name: "Mix", preloadedTracks: songs)
        #expect(await service.loadTracks(for: playlist).count == 3)
    }

    @Test func showsInTheCarouselOfferNoQueueing() {
        #expect(!ArtworkCarouselContent.podcasts([]).isQueueable)
        #expect(ArtworkCarouselContent.albums([]).isQueueable)
        #expect(ArtworkCarouselContent.playlists([]).isQueueable)
    }

    @Test func theQueueScreenHasNoClearRowForEpisodes() {
        #expect(QueueView.topOffset(canEdit: true) == QueueView.clearRowOffset)
        #expect(QueueView.topOffset(canEdit: false) == 0)
    }
}

// MARK: - Gramophone

@Suite("Gramophone")
struct GramophoneTests {

    // MARK: 3D

    /// Projects `point` through a camera at `pose` with a horizontal field of view, into
    /// a view `size` points big, as SceneKit would.
    private func project(_ point: SIMD3<Float>, pose: GramophoneCameraPose, fov: Float, size: CGSize) -> CGPoint {
        let q = pose.orientation
        let local = q.inverse.act(point - pose.position)
        let tanHalf = tan(fov * .pi / 360)
        let x = local.x / (-local.z * tanHalf)
        let y = local.y / (-local.z * tanHalf * Float(size.height / size.width))
        return CGPoint(x: size.width / 2 * CGFloat(1 + x), y: size.height / 2 * CGFloat(1 - y))
    }

    @Test func theOverheadCameraPutsTheRecordWhereThe2DTurntableDrawsIt() {
        let size = CGSize(width: 402, height: 874)
        let center = CGPoint(x: 170, y: 360), radius: CGFloat = 148
        let record = SIMD3<Float>(-0.04, 0.36, 0.02)
        let pose = GramophoneCameraPose.overhead(recordCenter: record, recordRadius: 0.15, screenCenter: center,
                                                 screenRadius: radius, viewSize: size, fieldOfView: 34)
        let projectedCenter = project(record, pose: pose, fov: 34, size: size)
        let projectedEdge = project(record + SIMD3(0.15, 0, 0), pose: pose, fov: 34, size: size)
        let projectedFront = project(record + SIMD3(0, 0, 0.15), pose: pose, fov: 34, size: size)
        #expect(abs(projectedCenter.x - center.x) < 0.5 && abs(projectedCenter.y - center.y) < 0.5)
        #expect(abs(projectedEdge.x - projectedCenter.x - radius) < 0.5)
        // The front of the machine is toward the bottom of the screen.
        #expect(abs(projectedFront.y - projectedCenter.y - radius) < 0.5)
    }

    @Test func theFrontCameraSeesTheWholeMachine() {
        let size = CGSize(width: 402, height: 874)
        let bounds = (min: SIMD3<Float>(-0.27, 0, -0.2), max: SIMD3<Float>(0.29, 1, 0.27))
        let pose = GramophoneCameraPose.front(bounds: bounds, aspect: Float(size.width / size.height),
                                              fieldOfView: 34, yaw: 0.18, pitch: 0.24, margin: 0.03, topInset: 0.12)
        for k in 0..<8 {
            let corner = SIMD3(k & 1 == 0 ? bounds.min.x : bounds.max.x, k & 2 == 0 ? bounds.min.y : bounds.max.y,
                               k & 4 == 0 ? bounds.min.z : bounds.max.z)
            let point = project(corner, pose: pose, fov: 34, size: size)
            #expect((0...size.width).contains(point.x), "corner \(k) at \(point)")
            // Clear of the top bar.
            #expect((size.height * 0.11...size.height).contains(point.y), "corner \(k) at \(point)")
        }
        // Looking down a little at the machine, from in front and to the right.
        #expect(pose.position.y > pose.target.y && pose.position.z > 1 && pose.position.x > 0)
    }

    @Test func theCameraPathRunsFromTheFrontToStraightDown() {
        let front = GramophoneCameraPose(position: SIMD3(0.3, 0.9, 2), target: SIMD3(0, 0.5, 0), up: SIMD3(0, 1, 0))
        let overhead = GramophoneCameraPose(position: SIMD3(0, 1, 0.1), target: SIMD3(0, 0.36, 0.1), up: SIMD3(0, 0, -1))
        let path = GramophoneCameraPath(from: front, to: overhead)
        #expect(simd_distance(path.pose(at: 0).position, front.position) < 1e-4)
        #expect(simd_distance(path.pose(at: 1).position, overhead.position) < 1e-4)
        let down = path.pose(at: 1).orientation.act(SIMD3(0, 0, -1))
        #expect(simd_distance(down, SIMD3(0, -1, 0)) < 1e-3)
        // On the way it rises over the front edge and tips down.
        let middle = path.pose(at: 0.5)
        #expect(middle.position.z < front.position.z && middle.position.z > overhead.position.z)
        #expect(middle.orientation.act(SIMD3(0, 0, -1)).y < -0.3)
    }

    @Test func aTurnedPartsNormalsPointOut() {
        let geometry = GramophoneMesh.lathe([SIMD2(0, 0), SIMD2(0.02, 0), SIMD2(0.02, 0), SIMD2(0.02, 0.05),
                                             SIMD2(0.02, 0.05), SIMD2(0, 0.05)], segments: 12)
        let positions = geometry.sources(for: .vertex).first!
        let normals = geometry.sources(for: .normal).first!
        #expect(positions.vectorCount == 6 * 13)
        #expect(normals.vectorCount == positions.vectorCount)
        #expect(geometry.elements.first!.primitiveCount == 5 * 12 * 2)
    }

    @Test func theHornWidensToItsMouth() {
        let horn = GramophoneMesh.horn(spine: [SIMD3(0, 0, 0), SIMD3(0, 0.2, 0), SIMD3(0, 0.4, 0.1)],
                                       throat: 0.01, mouth: 0.2, rings: 20, segments: 40)
        let vertices = horn.inner.sources(for: .vertex).first!
        #expect(vertices.vectorCount == 20 * 41)
        // The inside is shaded, dark at the throat.
        #expect(horn.inner.sources(for: .color).count == 1)
        #expect(GramophoneMesh.petal(0, count: 10) == 0)
        #expect(abs(GramophoneMesh.petal(.pi / 10, count: 10) - 1) < 1e-5)
    }

    @Test func eachSongIsABandAsWideAsItIsLong() {
        let map = GrooveMap(durations: [60, 120, 60])
        #expect(map.total == 240)
        #expect(map.bandStarts == [0, 0.25, 0.75])
        #expect(map.fraction(track: 1, time: 60) == 0.5)
        #expect(map.fraction(track: 2, time: 999) == 1)
    }

    @Test func aPlaceOnTheRecordIsASongAndATimeInIt() {
        let map = GrooveMap(durations: [60, 120, 60])
        let middle = map.position(at: 0.5)
        #expect(middle.index == 1 && middle.time == 60)
        let start = map.position(at: 0)
        #expect(start.index == 0 && start.time == 0)
        let end = map.position(at: 1)
        #expect(end.index == 2 && end.time == 60)
        // Round trip.
        let back = map.position(at: map.fraction(track: 2, time: 30))
        #expect(back.index == 2 && abs(back.time - 30) < 0.001)
    }

    @Test func aSongOfUnknownLengthCountsAsThreeMinutes() {
        let map = GrooveMap(durations: [0, 180])
        #expect(map.bandStarts == [0, 0.5])
    }

    @Test func theNeedleLandsWhereTheArmAngleSays() {
        let arm = TonearmGeometry(center: CGPoint(x: 150, y: 150), radius: 100)
        for fraction in stride(from: 0.0, through: 1.0, by: 0.1) {
            let angle = arm.angle(forFraction: fraction)
            #expect(abs((arm.fraction(at: angle) ?? -1) - fraction) < 0.001, "At \(fraction)")
        }
        // The arm swings inward from the edge: the inner groove is further round.
        #expect(arm.innerAngle > arm.angle(forFraction: 0))
        #expect(arm.restAngle < arm.angle(forFraction: 0))
    }

    @Test func theArmOnItsRestIsOffTheRecord() {
        let arm = TonearmGeometry(center: CGPoint(x: 150, y: 150), radius: 100)
        #expect(arm.fraction(at: arm.restAngle) == nil)
        #expect(arm.radius(at: arm.restAngle) > arm.outerRadius)
    }

    @Test func aFingerCanOnlyCarryTheArmBetweenItsRestAndTheInnerGroove() {
        let arm = TonearmGeometry(center: CGPoint(x: 150, y: 150), radius: 100)
        // Far off to the right: the arm stops at its rest.
        #expect(arm.angle(toward: CGPoint(x: 600, y: arm.pivot.y)) == arm.restAngle)
        // Up past the spindle, toward the top left: it stops at the inner groove.
        #expect(arm.angle(toward: CGPoint(x: -200, y: -50)) == arm.innerAngle)
    }

    @Test func recordsArePressedForWhatTheyHold() {
        let playlist = AppAlbum(mixtape: AppPlaylist(id: "p", name: "Mix"))
        #expect(RecordKind(playlist) == .homeRecording)
        #expect(RecordKind(AppAlbum(id: "a", title: "A", artistName: "B")) == .album)
        #expect(RecordKind(nil) == .album)
    }

    @Test func theCrackleTakesItsPiecesInTurn() {
        #expect((0..<4).map(GramophoneSound.nextCrackle(after:)) == [.crackle1, .crackle2, .crackle3, .crackle1])
    }
}

// MARK: - Spool Sounds

@Suite("Spool Sounds")
@MainActor
struct SpoolSoundTests {

    /// The Spool's sounds, the Gramophone's and the Disc's.
    private var allNames: [String] {
        SpoolSound.allCases.map(\.rawValue) + GramophoneSound.allCases.map(\.rawValue)
            + DiscSound.allCases.map(\.rawValue)
    }

    @Test func everySoundIsBundledAsAPlayableSystemSound() throws {
        for name in allNames {
            let url = try #require(Bundle.main.url(forResource: name, withExtension: "wav"),
                                   "\(name).wav is not in the app")
            var id: SystemSoundID = 0
            #expect(AudioServicesCreateSystemSoundID(url as CFURL, &id) == kAudioServicesNoError,
                    "\(name) can't be played as a system sound")
            AudioServicesDisposeSystemSoundID(id)
        }
    }

    @Test func theGramophonesSoundsAreShortEnoughToKeepUp() throws {
        // The crank's tick has to finish before the next tooth comes round, and the
        // rest have to land with what they're for.
        for sound in GramophoneSound.allCases {
            let url = try #require(Bundle.main.url(forResource: sound.rawValue, withExtension: "wav"))
            let file = try AVAudioFile(forReading: url)
            let seconds = Double(file.length) / file.fileFormat.sampleRate
            #expect(seconds > 0.03 && seconds < 0.8, "\(sound.rawValue) runs \(seconds) s")
        }
        let tick = try AVAudioFile(forReading: #require(Bundle.main.url(forResource: GramophoneSound.ratchet.rawValue, withExtension: "wav")))
        #expect(Double(tick.length) / tick.fileFormat.sampleRate < 0.1)
    }

    @Test func soundsAreCutTight() throws {
        // Trimmed of the recordings' silence: each is well under a second, so it
        // plays with the action and not after it.
        for sound in SpoolSound.allCases {
            let url = try #require(Bundle.main.url(forResource: sound.rawValue, withExtension: "wav"))
            let file = try AVAudioFile(forReading: url)
            let seconds = Double(file.length) / file.fileFormat.sampleRate
            #expect(seconds > 0.1 && seconds < 0.8, "\(sound.rawValue) runs \(seconds) s")
        }
    }

    @Test func theDiscsSoundsLandWithWhatTheyreFor() throws {
        for sound in DiscSound.allCases {
            let url = try #require(Bundle.main.url(forResource: sound.rawValue, withExtension: "wav"))
            let file = try AVAudioFile(forReading: url)
            let seconds = Double(file.length) / file.fileFormat.sampleRate
            #expect(seconds > 0.05 && seconds < 0.8, "\(sound.rawValue) runs \(seconds) s")
        }
    }

    @Test func theRewindWhirTakesItsPiecesInTurnAndOverlapsThem() throws {
        #expect((0..<6).map(SpoolSound.nextRewind(after:)) == [.rewind1, .rewind2, .rewind3, .rewind1, .rewind2, .rewind3])
        // Each piece lasts longer than the gap before the next starts, so the whir has
        // no holes.
        let interval = Double(SpoolSound.rewindInterval.components.attoseconds) / 1e18
            + Double(SpoolSound.rewindInterval.components.seconds)
        for piece in SpoolSound.rewind {
            let url = try #require(Bundle.main.url(forResource: piece.rawValue, withExtension: "wav"))
            let file = try AVAudioFile(forReading: url)
            #expect(Double(file.length) / file.fileFormat.sampleRate > interval)
        }
    }
}

// MARK: - TapeTransport

@Suite("TapeTransport")
struct TapeTransportTests {

    private let hub = TapeTransport.hubRadius

    @Test func startOfSongIsAllOnSupplyReel() {
        let t = TapeTransport(time: 0, duration: 200)
        #expect(t.progress == 0)
        #expect(abs(t.supplyRadius - 1) < 1e-9)
        #expect(abs(t.takeUpRadius - hub) < 1e-9)
    }

    @Test func endOfSongIsAllOnTakeUpReel() {
        let t = TapeTransport(time: 200, duration: 200)
        #expect(t.progress == 1)
        #expect(abs(t.supplyRadius - hub) < 1e-9)
        #expect(abs(t.takeUpRadius - 1) < 1e-9)
    }

    @Test func tapeAreaIsConserved() {
        for time in stride(from: 0.0, through: 180, by: 15) {
            let t = TapeTransport(time: time, duration: 180)
            let area = t.supplyRadius * t.supplyRadius + t.takeUpRadius * t.takeUpRadius
            #expect(abs(area - (1 + hub * hub)) < 1e-9)
        }
    }

    @Test func positionIsClampedToSong() {
        #expect(TapeTransport(time: -5, duration: 100) == TapeTransport(time: 0, duration: 100))
        #expect(TapeTransport(time: 500, duration: 100) == TapeTransport(time: 100, duration: 100))
    }

    @Test func reelsTurnAtTapeSpeedOverTheirPack() {
        // Over a short step, each reel's angle advances by about v·dt / r.
        let duration = 240.0, time = 60.0, dt = 0.01
        let a = TapeTransport(time: time, duration: duration)
        let b = TapeTransport(time: time + dt, duration: duration)
        let v = TapeTransport.tapeSpeed
        #expect(abs((b.takeUpAngle - a.takeUpAngle) - v * dt / a.takeUpRadius) < 1e-4)
        #expect(abs((b.supplyAngle - a.supplyAngle) - v * dt / a.supplyRadius) < 1e-4)
    }

    @Test func emptierReelSpinsFaster() {
        let a = TapeTransport(time: 10, duration: 200)
        let b = TapeTransport(time: 11, duration: 200)
        // Early in the song the take-up reel is nearly bare, so it turns more.
        #expect(b.takeUpAngle - a.takeUpAngle > b.supplyAngle - a.supplyAngle)
    }

    @Test func unknownDurationStillTurnsReels() {
        let a = TapeTransport(time: 10, duration: 0)
        let b = TapeTransport(time: 11, duration: 0)
        #expect(a.progress == 0)
        #expect(b.takeUpAngle > a.takeUpAngle)
        #expect(b.supplyAngle > a.supplyAngle)
    }
}

// MARK: - FoldPostureMonitor

@Suite("FoldPostureMonitor")
struct FoldPostureMonitorTests {

    @Test func reportsClosedWithoutFoldAPI() {
        #expect(FoldPostureMonitor().posture == .closed)
    }

    @Test func debugOverrideWinsAndClears() {
        let monitor = FoldPostureMonitor()
        monitor.debugOverride = .tent
        #expect(monitor.posture == .tent)
        monitor.debugOverride = nil
        #expect(monitor.posture == .closed)
    }

    /// Every iPhone without a hinge reports none, and must behave exactly as before.
    @Test func noHingeReadsAsClosed() {
        #expect(FoldPosture(.absent) == .closed)
    }

    @Test func hingeStatusMapsToPosture() {
        #expect(FoldPosture(.closed) == .closed)
        #expect(FoldPosture(.open) == .open)
    }

    @Test func hingeUpdatesSystemPosture() {
        let monitor = FoldPostureMonitor()
        monitor.update(.open)
        #expect(monitor.posture == .open)
        monitor.update(.closed)
        #expect(monitor.posture == .closed)
    }

    @Test func debugOverrideBeatsTheHinge() {
        let monitor = FoldPostureMonitor()
        monitor.debugOverride = .tent
        monitor.update(.open)
        #expect(monitor.posture == .tent)
    }
}

// MARK: - TapeFormat

@Suite("TapeFormat")
struct TapeFormatTests {

    private func track(_ id: String, _ title: String, _ duration: Double) -> AppTrack {
        AppTrack(id: id, title: title, artistName: "A", albumTitle: "B", duration: duration)
    }

    @Test func standInCopiesWithNoLengthAreDropped() {
        let tracks = [track("1", "Paranoid", 0), track("2", "Paranoid", 221),
                      track("3", "Rich & Sad", 0), track("4", "Rich & Sad", 206)]
        #expect(tracks.withoutDuplicates.map(\.id) == ["2", "4"])
    }

    @Test func songsThatShareATitleStay() {
        let tracks = [track("1", "Interlude", 60), track("2", "Interlude", 75), track("3", "Outro", 0)]
        #expect(tracks.withoutDuplicates.map(\.id) == ["1", "2", "3"])
    }

    @Test func aSongAddedTwiceIsListedOnce() {
        // Dawn FM with Sacrifice in the library twice, both copies 3:08.
        let tracks = [track("1", "Take My Breath", 339), track("2", "Sacrifice", 188),
                      track("3", "Sacrifice", 188), track("4", "A Tale By Quincy", 96)]
        #expect(tracks.withoutDuplicates.map(\.id) == ["1", "2", "4"])
    }

    @Test func copiesRoundedDifferentlyStillCountAsOne() {
        let tracks = [track("1", "Sacrifice", 188.4), track("2", "sacrifice ", 189.9), track("3", "Sacrifice", 191)]
        // The third is three seconds off the first: a different recording.
        #expect(tracks.withoutDuplicates.map(\.id) == ["1", "3"])
    }

    @Test func aRepeatLaterInTheAlbumIsDroppedWhereItIs() {
        let tracks = [track("1", "Intro", 60), track("2", "Song", 200), track("3", "Intro", 60), track("4", "End", 90)]
        #expect(tracks.withoutDuplicates.map(\.id) == ["1", "2", "4"])
    }

    @Test func anAlbumWithNoLengthsKeepsEverySong() {
        let tracks = [track("1", "Song", 0), track("2", "Song", 0)]
        #expect(tracks.withoutDuplicates.count == 2)
    }

    // MARK: Mixtapes

    private func mixtape(_ tracks: [AppTrack], curator: String? = nil) -> AppAlbum {
        AppAlbum(mixtape: AppPlaylist(id: "p1", name: "The Road Trip - EP", curatorName: curator,
                                      preloadedTracks: tracks))
    }

    @Test func aMixtapeGoesOnTheShortestBlankThatHoldsIt() {
        #expect(TapeFormat.blank(for: 0) == nil)
        #expect(TapeFormat.blank(for: 40 * 60) == 46)
        #expect(TapeFormat.blank(for: 46 * 60) == 46)
        #expect(TapeFormat.blank(for: 46 * 60 + 1) == 60)
        #expect(TapeFormat.blank(for: 75 * 60) == 90)
        // Longer than any blank: still a C120.
        #expect(TapeFormat.blank(for: 200 * 60) == 120)
    }

    @Test func sideBStartsWithTheFirstSongThatWontFitOnSideA() {
        // 40 minutes in all: a C46, 23 minutes a side.
        let tracks = (1...8).map { track("\($0)", "Song \($0)", 300) }
        #expect(TapeFormat.sideBreak(in: tracks) == 4)
    }

    @Test func aMixtapeThatFitsOneSideOrHasNoLengthsIsntSplit() {
        #expect(TapeFormat.sideBreak(in: [track("1", "Only", 200)]) == nil)
        #expect(TapeFormat.sideBreak(in: [track("1", "A", 0), track("2", "B", 0)]) == nil)
    }

    @Test func aMixtapeKeepsASongTapedTwiceAndItsName() {
        let tracks = [track("1", "Sacrifice", 188), track("2", "Sacrifice", 188)]
        let tape = mixtape(tracks, curator: "Sam")
        #expect(tape.tapeFormat == .mixtape)
        #expect(tape.tapeTitle == "The Road Trip - EP")
        #expect(tape.tapeSongs(tracks).count == 2)
        #expect(tape.tapeTrackCount == 2)
        #expect(tape.comesInCase)
        #expect(tape.tapeBlank == "C46")
        #expect(tape.tapeDetail == "C46 · 2 songs")
        #expect(tape.id == "mixtape:p1")
        #expect(!tape.tapeFormat.isShort)
    }

    // MARK: Podcasts

    private func show(_ episodes: [(String, Date?)]) -> PodcastShow {
        PodcastShow(feed: FeedShow(
            feedURL: URL(string: "https://example.invalid/feed.xml")!, title: "The Show", author: nil,
            artworkURL: nil,
            episodes: episodes.map { guid, date in
                FeedEpisode(guid: guid, title: "Episode \(guid)", audioURL: URL(string: "https://example.invalid/\(guid).mp3")!,
                            published: date, duration: 1_800, artworkURL: nil)
            },
            lastRefreshed: .now))
    }

    @Test func episodesGoOnTheTapeNewestFirstWithUndatedOnesLast() {
        let day: TimeInterval = 86_400
        let show = show([("old", Date(timeIntervalSince1970: day)), ("none", nil),
                         ("new", Date(timeIntervalSince1970: 3 * day)), ("mid", Date(timeIntervalSince1970: 2 * day))])
        #expect(show.episodesNewestFirst.map(\.id) == ["feed.new", "feed.mid", "feed.old", "feed.none"])
        // The tape's tracks are in the same order, so a track's place is its episode's.
        let tape = AppAlbum(podcast: show)
        #expect(tape.preloadedTracks.map(\.id) == show.episodesNewestFirst.map(\.id))
        #expect(tape.releaseDate == Date(timeIntervalSince1970: 3 * day))
    }

    @Test func aPodcastIsASpokenWordTapeInACase() {
        let tape = AppAlbum(podcast: show([("1", nil)]))
        #expect(tape.tapeFormat == .spokenWord)
        #expect(tape.isPodcast && !tape.isMixtape)
        // Even with one episode: the case is where an episode is chosen.
        #expect(tape.comesInCase)
        #expect(tape.tapeDetail == "1 episode")
        #expect(tape.tapeBlank == nil)
        #expect(tape.caseByline == "Podcast")
        #expect(tape.id.hasPrefix("podcast:"))
    }

    @Test func episodesThatShareATitleAndLengthAllStay() {
        let tape = AppAlbum(podcast: show([("1", nil), ("2", nil)]))
        let same = [AppTrack(id: "a", title: "Trailer", artistName: "S", albumTitle: "S", duration: 60),
                    AppTrack(id: "b", title: "Trailer", artistName: "S", albumTitle: "S", duration: 60)]
        #expect(tape.tapeSongs(same).count == 2)
        #expect(TapeFormat.spokenWord.count(12) == "12 episodes")
    }

    @Test func storeSuffixesMarkSinglesAndEPs() {
        #expect(TapeFormat.detect(title: "Ave - Single", isSingle: nil) == .single)
        #expect(TapeFormat.detect(title: "Bad at Love (Remixes) - EP", isSingle: nil) == .ep)
        #expect(TapeFormat.detect(title: "Back In Black", isSingle: nil) == .album)
    }

    @Test func appleMusicSingleFlagCountsWithoutASuffix() {
        #expect(TapeFormat.detect(title: "Ave", isSingle: true) == .single)
        #expect(TapeFormat.detect(title: "Ave", isSingle: false) == .album)
    }

    @Test func onlyATrailingSuffixCounts() {
        // "EP" or "Single" inside a title is just part of the name.
        #expect(TapeFormat.detect(title: "Single Ladies - The Remixes", isSingle: nil) == .album)
        #expect(TapeFormat.detect(title: "The EP Collection", isSingle: nil) == .album)
    }

    @Test func displayTitleDropsTheSuffix() {
        #expect(TapeFormat.displayTitle("Azizam - Single") == "Azizam")
        #expect(TapeFormat.displayTitle("Bad at Love (Remixes) - EP") == "Bad at Love (Remixes)")
        #expect(TapeFormat.displayTitle("Back In Black") == "Back In Black")
    }

    @Test func detailIsTheStampOrTheSongCount() {
        let track = AppTrack(id: "t", title: "Song", artistName: "A", albumTitle: "X", duration: 1)
        let single = AppAlbum(id: "1", title: "Ave - Single", artistName: "A", preloadedTracks: [track])
        let album = AppAlbum(id: "2", title: "Back In Black", artistName: "A",
                             preloadedTracks: (1...10).map {
                                 AppTrack(id: "t\($0)", title: "Song \($0)", artistName: "A", albumTitle: "X", duration: 1)
                             })
        let unknown = AppAlbum(id: "3", title: "Bad", artistName: "A")
        #expect(single.tapeDetail == "Single")
        #expect(album.tapeDetail == "10 songs")
        #expect(unknown.tapeDetail == nil)
    }
}

// MARK: - LibrarySearch

@Suite("LibrarySearch")
@MainActor
struct LibrarySearchTests {

    private func track(_ id: String, _ title: String, artist: String = "Artist", album: String = "Album") -> AppTrack {
        AppTrack(id: id, title: title, artistName: artist, albumTitle: album, duration: 200)
    }

    @Test func emptyQueryHasNoTerms() {
        #expect(LibrarySearch.terms("   ").isEmpty)
        #expect(!LibrarySearch.matches(LibrarySearch.terms(""), "Anything"))
    }

    @Test func matchingIgnoresCaseAndAccents() {
        let terms = LibrarySearch.terms("BEYONCE")
        #expect(LibrarySearch.matches(terms, "Lemonade", "Beyoncé"))
    }

    @Test func everyWordMustMatchSomewhere() {
        let terms = LibrarySearch.terms("abbey beatles")
        #expect(LibrarySearch.matches(terms, "Abbey Road", "The Beatles"))
        #expect(!LibrarySearch.matches(terms, "Abbey Road", "George Benson"))
    }

    @Test func resultsListArtistsAlbumsThenSongs() {
        let service = MusicService()
        service.songs = [track("s1", "Here Comes the Sun", artist: "The Beatles", album: "Abbey Road")]
        service.albums = [AppAlbum(id: "a1", title: "Abbey Road", artistName: "The Beatles")]
        service.artists = [AppArtist(id: "r1", name: "The Beatles")]

        let results = LibrarySearch.results(for: "beatles", in: service)
        #expect(results.map(\.id) == ["artist.r1", "album.a1", "song.s1"])
    }

    @Test func titlesStartingWithTheQueryComeFirst() {
        let service = MusicService()
        service.songs = [track("s1", "Into the Sun"), track("s2", "Sunday")]

        let results = LibrarySearch.results(for: "sun", in: service)
        #expect(results.map(\.id) == ["song.s2", "song.s1"])
    }

    @Test func aSongBringsUpItsAlbumOnTheShelf() {
        let albums = [AppAlbum(id: "a1", title: "Abbey Road", artistName: "The Beatles"),
                      AppAlbum(id: "a2", title: "Revolver", artistName: "The Beatles")]
        let songs = [track("s1", "Something", artist: "The Beatles", album: "Abbey Road")]

        let found = LibrarySearch.filter(albums, matching: "something", songs: songs)
        #expect(found.map(\.id) == ["a1"])
    }

    @Test func anEmptyQueryLeavesTheShelfWhole() {
        let albums = [AppAlbum(id: "a1", title: "Abbey Road", artistName: "The Beatles")]
        #expect(LibrarySearch.filter(albums, matching: " ", songs: []).count == 1)
    }

    @Test func searchTurnsToAShelfWithMatches() {
        let mixtape = AppAlbum(mixtape: AppPlaylist(id: "p1", name: "Road Trip"))
        let matches = ShelfSearchMatches(query: "road", albums: [], mixtapes: [mixtape], podcasts: [])
        #expect(matches.shelfWithMatches(preferring: .albums) == .mixtapes)
        #expect(matches.shelfWithMatches(preferring: .mixtapes) == nil)
    }
}
