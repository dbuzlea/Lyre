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
// is playing while browsing, plus an AirPlay button for changing where it plays.
struct LyreScreenView: View {
    let currentScreen: LyreScreen
    @ObservedObject var musicService: MusicService
    let themeSettings: ThemeSettings
    @Binding var menuSelection: Int
    @Binding var songSelection: Int
    @Binding var detailSelection: Int
    let isBacklightOn: Bool
    /// Up Next offset of the row being carried on the Queue screen, if any.
    var queueMoveOffset: Int? = nil
    /// Transient message about the last wheel action, shown over the screen.
    var banner: String? = nil
    /// What's typed on the Search screen, and what it found (see LibrarySearch).
    var searchQuery: Binding<String> = .constant("")
    var searchResults: [LibrarySearchResult] = []

    private var showNowPlayingFooter: Bool {
        switch currentScreen {
        // Both of these screens already show what is playing.
        case .nowPlaying, .queue: return false
        default: break
        }
        return musicService.hasNowPlaying
    }

    private var nowPlayingTitle: String {
        musicService.currentTrack?.title
            ?? musicService.currentMediaItem?.title
            ?? musicService.currentEpisode?.title
            ?? ""
    }

    private var nowPlayingArtist: String {
        musicService.currentTrack?.artistName
            ?? musicService.currentMediaItem?.artist
            ?? musicService.currentEpisode?.showTitle
            ?? ""
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // The footer is stacked below the content (not overlaid) so lists end
            // above it instead of having their last rows hidden underneath.
            VStack(spacing: 0) {
                Group {
                    switch currentScreen {
                    case .menu:
                        MainMenuView(selection: $menuSelection, themeSettings: themeSettings)
                    case .nowPlaying:
                        NowPlayingView(musicService: musicService, themeSettings: themeSettings, selection: $menuSelection)
                    case .queue:
                        QueueView(
                            musicService: musicService,
                            themeSettings: themeSettings,
                            selection: $songSelection,
                            movingOffset: queueMoveOffset
                        )
                    case .songs:
                        SongListView(
                            songs: musicService.songs,
                            selection: $songSelection,
                            musicService: musicService,
                            themeSettings: themeSettings,
                            sectionLetters: musicService.songSectionLetters
                        )
                    case .recentlyAdded:
                        SongListView(
                            songs: musicService.recentlyAdded,
                            selection: $songSelection,
                            musicService: musicService,
                            themeSettings: themeSettings,
                            title: String(localized: "menu.recentlyAdded"),
                            sectionLetters: musicService.recentlyAddedSectionLetters
                        )
                    case .recentlyPlayed:
                        SongListView(
                            songs: musicService.recentlyPlayed,
                            selection: $songSelection,
                            musicService: musicService,
                            themeSettings: themeSettings,
                            title: String(localized: "menu.recentlyPlayed"),
                            sectionLetters: musicService.recentlyPlayedSectionLetters
                        )
                    case .albums:
                        AlbumListView(
                            albums: musicService.albums,
                            selection: $menuSelection,
                            themeSettings: themeSettings,
                            sectionLetters: musicService.albumSectionLetters,
                            isAuthorized: musicService.isAuthorized
                        )
                    case .artists:
                        ArtistListView(
                            artists: musicService.artists,
                            selection: $menuSelection,
                            themeSettings: themeSettings,
                            sectionLetters: musicService.artistSectionLetters,
                            isAuthorized: musicService.isAuthorized
                        )
                    case .playlists:
                        PlaylistListView(
                            playlists: musicService.playlists,
                            selection: $menuSelection,
                            themeSettings: themeSettings,
                            isAuthorized: musicService.isAuthorized
                        )
                    case .podcasts:
                        PodcastsScreen(
                            mode: .all,
                            musicService: musicService,
                            selection: $menuSelection,
                            themeSettings: themeSettings
                        )
                        .task { await musicService.refreshPodcasts() }
                    case .downloadedPodcasts:
                        PodcastsScreen(
                            mode: .downloaded,
                            musicService: musicService,
                            selection: $menuSelection,
                            themeSettings: themeSettings
                        )
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
                    case .search:
                        SearchView(
                            query: searchQuery,
                            results: searchResults,
                            selection: $menuSelection,
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
                    case .playerStyleSelection:
                        PlayerStyleSelectionView(selection: $menuSelection, themeSettings: themeSettings)
                    case .about:
                        AboutView(themeSettings: themeSettings)
                    }
                }
                .id(currentScreen)
                .transition(.opacity)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showNowPlayingFooter {
                    nowPlayingFooter
                        .transition(.opacity)
                }
            }

            if let banner {
                bannerView(banner)
                    .padding(.bottom, showNowPlayingFooter ? 22 : 8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: currentScreen)
        .animation(.easeInOut(duration: 0.2), value: showNowPlayingFooter)
        .animation(.easeOut(duration: 0.2), value: banner)
        .clipped()
    }

    // Confirmation for an action taken on the wheel, where the wheel itself gives no
    // feedback beyond a haptic. Sits above the now-playing footer when both are shown.
    private func bannerView(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(themeSettings.currentTheme.highlightTextColor)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(themeSettings.currentTheme.highlightColor)
            )
            .padding(.horizontal, 12)
            .accessibilityAddTraits(.updatesFrequently)
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
                // Sized to the footer's 9pt text so it does not grow the footer.
                AirPlayButton(themeSettings: themeSettings, size: 9)
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
