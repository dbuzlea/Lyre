//
//  LyreTests.swift
//  LyreTests
//

import Testing
import UIKit
import MediaPlayer
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
