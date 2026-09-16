//
//  LyreScreenView.swift
//  Lyre
//

import SwiftUI
import MediaPlayer

// MARK: - Screen Content Router
//
// LyreScreenView is the display-dispatch layer between the navigation controller
// (ScrollWheelView) and the actual content view for each screen. It switches on the
// current `LyreScreen` enum case and renders the matching view.
//
// Screen transitions are crossfade animations keyed on `currentScreen`. The
// `.id(currentScreen)` modifier forces SwiftUI to tear down and rebuild the content
// view on every screen change, ensuring onAppear hooks (e.g. scroll restoration via
// ScrollViewReader) fire correctly rather than being skipped on re-render.
//
// A persistent Now Playing mini-footer slides in at the bottom of every screen
// except the Now Playing screen itself, whenever a track is currently loaded. It
// shows the track title, artist, and play/pause icon so the user always knows what
// is playing while browsing.
struct LyreScreenView: View {
    let currentScreen: LyreScreen
    @ObservedObject var musicService: MusicService
    let themeSettings: ThemeSettings
    @Binding var menuSelection: Int
    @Binding var songSelection: Int
    @Binding var detailSelection: Int
    let isBacklightOn: Bool

    private var showNowPlayingFooter: Bool {
        if case .nowPlaying = currentScreen { return false }
        return musicService.currentTrack != nil || musicService.currentMediaItem != nil
    }

    private var nowPlayingTitle: String {
        musicService.currentTrack?.title
            ?? musicService.currentMediaItem?.title
            ?? ""
    }

    private var nowPlayingArtist: String {
        musicService.currentTrack?.artistName
            ?? musicService.currentMediaItem?.artist
            ?? ""
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch currentScreen {
                case .menu:
                    MainMenuView(selection: $menuSelection, themeSettings: themeSettings)
                case .nowPlaying:
                    NowPlayingView(musicService: musicService, themeSettings: themeSettings, selection: $menuSelection)
                case .songs:
                    SongListView(
                        songs: musicService.songs,
                        selection: $songSelection,
                        musicService: musicService,
                        themeSettings: themeSettings
                    )
                case .recentlyAdded:
                    SongListView(
                        songs: musicService.recentlyAdded,
                        selection: $songSelection,
                        musicService: musicService,
                        themeSettings: themeSettings,
                        title: String(localized: "menu.recentlyAdded")
                    )
                case .recentlyPlayed:
                    SongListView(
                        songs: musicService.recentlyPlayed,
                        selection: $songSelection,
                        musicService: musicService,
                        themeSettings: themeSettings,
                        title: String(localized: "menu.recentlyPlayed")
                    )
                case .albums:
                    AlbumListView(
                        albums: musicService.albums,
                        selection: $menuSelection,
                        themeSettings: themeSettings
                    )
                case .artists:
                    ArtistListView(
                        artists: musicService.artists,
                        selection: $menuSelection,
                        themeSettings: themeSettings
                    )
                case .playlists:
                    PlaylistListView(
                        playlists: musicService.playlists,
                        selection: $menuSelection,
                        themeSettings: themeSettings
                    )
                case .podcasts:
                    PodcastListView(
                        podcastShows: musicService.podcastShows,
                        selection: $menuSelection,
                        themeSettings: themeSettings
                    )
                    .task { await musicService.refreshPodcasts() }
                case .podcastDetail(let show):
                    PodcastDetailView(
                        show: show,
                        selection: $detailSelection,
                        themeSettings: themeSettings
                    )
                case .albumDetail(let album):
                    AlbumDetailView(
                        album: album,
                        musicService: musicService,
                        selection: $detailSelection,
                        themeSettings: themeSettings
                    )
                case .playlistDetail(let playlist):
                    PlaylistDetailView(
                        playlist: playlist,
                        musicService: musicService,
                        selection: $detailSelection,
                        themeSettings: themeSettings
                    )
                case .artistDetail(let artist):
                    ArtistDetailView(
                        artist: artist,
                        musicService: musicService,
                        selection: $detailSelection,
                        themeSettings: themeSettings
                    )
                case .settings:
                    SettingsView(selection: $menuSelection, themeSettings: themeSettings)
                case .themeSelection:
                    ThemeSelectionView(selection: $menuSelection, themeSettings: themeSettings)
                case .screenSizeSelection:
                    ScreenSizeSelectionView(selection: $menuSelection, themeSettings: themeSettings)
                case .highlightColorSelection:
                    HighlightColorView(selection: $menuSelection, themeSettings: themeSettings)
                case .scrollSensitivitySelection:
                    ScrollSensitivityView(selection: $menuSelection, themeSettings: themeSettings)
                case .clickSoundSelection:
                    ClickSoundSelectionView(selection: $menuSelection, themeSettings: themeSettings)
                case .backlightDurationSelection:
                    BacklightDurationSelectionView(selection: $menuSelection, themeSettings: themeSettings)
                case .about:
                    AboutView(themeSettings: themeSettings)
                }
            }
            .id(currentScreen)
            .transition(.opacity)
            .padding(8)

            if showNowPlayingFooter {
                nowPlayingFooter
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: currentScreen)
        .animation(.easeInOut(duration: 0.2), value: showNowPlayingFooter)
        .clipped()
    }

    private var nowPlayingFooter: some View {
        VStack(spacing: 0) {
            Divider().background(themeSettings.currentTheme.dividerColor)
            HStack(spacing: 4) {
                Image(systemName: musicService.isPlaying ? "play.fill" : "pause.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(themeSettings.currentTheme.highlightColor)
                Text(nowPlayingTitle)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(themeSettings.currentTheme.screenTextColor)
                Spacer()
                Text(nowPlayingArtist)
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .foregroundStyle(themeSettings.currentTheme.screenSecondaryTextColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                LinearGradient(
                    colors: isBacklightOn
                        ? themeSettings.currentTheme.screenBackgroundLight
                        : themeSettings.currentTheme.screenBackgroundDark,
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}
