//
//  LiquidLibraryView.swift
//  Lyre
//

import SwiftUI
import MusicKit

// MARK: - Liquid Library
//
// The way into the music. The first page is a lava lamp (LiquidLavaMenu): a blob of wax
// for each of albums, artists, playlists, Discover, podcasts and search, in the colour
// of what's playing, drifting and tilting with the phone. Each opens its page:
//
//   albums, playlists, podcasts   a grid of covers, with search and an A–Z strip
//   artists                       the names in big type; one opens that artist's albums
//   search                        albums, playlists and shows that match, as covers,
//                                 then Apple Music's songs, albums and artists
//   songs, recently played,       the songs, each with its cover, to play from or swipe
//   recently added                right to queue; every song has search and an A–Z strip
//
//   discover                      what Apple Music offers (Discover): Made for You, New
//                                 Releases, the charts and the genres, a row of covers each
//
// A cover opens its page (LiquidAlbumPage): the cover melting into its own colour, the
// name, Play and Shuffle, and the songs. What's played floods into Now Playing (the
// parent does that). Every move between pages is a flood too (see LiquidFlow), forward
// and back; Back is the arrow at the top of each page, or a swipe in from the left edge.

enum LiquidRoute: Hashable {
    case albums
    case songs
    case recentlyPlayed
    case recentlyAdded
    case mostPlayed
    case artists
    case artist(String)
    case playlists
    case podcasts
    case search
    case discover
    case album(AppAlbum)
}

struct LiquidLibraryView: View {
    @ObservedObject var musicService: MusicService
    @Binding var path: [LiquidRoute]
    /// Plays `tracks` of `album` from `index`; true when the whole of it was asked for
    /// (Play, Shuffle) rather than one song.
    let onPlay: (AppAlbum, [AppTrack], Int, Bool) -> Void
    /// Plays a list of songs from `index`: true when the whole of it was asked for. The
    /// name is the list's, for what queueing it instead says.
    let onPlaySongs: ([AppTrack], Int, Bool, String) -> Void
    let onQueue: ([AppTrack], QueuePlacement, String) -> Void
    let onFindShows: () -> Void
    let onOpenSettings: () -> Void
    let themeSettings: ThemeSettings
    /// Room kept clear at the bottom for the droplet.
    let bottomInset: CGFloat
    /// The hinge's pull on the lava (iPhone Duo, partly open).
    var lavaPull: CGVector = .zero

    /// Shows a short message over the player (queued, added, …).
    var onNotice: (String) -> Void = { _ in }

    @Environment(\.windowSafeArea) private var safeArea
    @Environment(\.liquidFlood) private var flood
    @Environment(\.openURL) private var openURL
    @State private var catalogOffer: CatalogOffer?
    /// What's open as a card over the library, if anything (LiquidCardDeck).
    @State private var deck: LiquidDeck?

    private var library: ShelfLibrary { ShelfLibrary(musicService: musicService) }

    var body: some View {
        NavigationStack(path: $path) {
            menu
                .navigationDestination(for: LiquidRoute.self) { route in
                    page(for: route)
                        // Back by a swipe in from the left edge, as anywhere else.
                        .overlay(alignment: .leading) {
                            Color.clear
                                .frame(width: 22)
                                .contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance: 12).onEnded { value in
                                    if value.translation.width > 60 { navigator.back() }
                                })
                        }
                }
        }
        .tint(.white)
        // Where Liquid is, for the diagnostics log (no names: a page's kind, a count).
        .onChange(of: path) { _, path in
            Diagnostics.shared.show("Liquid: \(path.last.map(Self.diagnosticName) ?? "menu")")
        }
        .onChange(of: deck?.id) { _, _ in
            Diagnostics.shared.show(deck.map { "Liquid: card deck, \($0.items.count) cards" }
                                    ?? "Liquid: \(path.last.map(Self.diagnosticName) ?? "menu")")
        }
        // Behind a card, the list is dimmed, out of VoiceOver's way too.
        .accessibilityHidden(deck != nil)
        // A cover swung open from a stack, over everything.
        .overlay {
            if let item = fold.item {
                LiquidFoldView(item: item, closedFrame: fold.frame, musicService: musicService) { fold.item = nil }
                    .id(item.id)
            }
        }
        // Something chosen from a list, as a card over it.
        .overlay {
            if let deck {
                LiquidCardDeckView(deck: deck, onClose: closeDeck) { item in card(for: item) }
                    .id(deck.id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .environment(\.liquidNavigator, navigator)
        .confirmationDialog(catalogOffer.map { String(format: String(localized: "catalog.offer.title"), $0.title) } ?? "",
                            isPresented: Binding(get: { catalogOffer != nil }, set: { if !$0 { catalogOffer = nil } }),
                            titleVisibility: .visible, presenting: catalogOffer) { offer in
            if case .album(let album) = offer, musicService.canStream {
                Button(String(localized: "catalog.offer.play")) { play(album) }
            }
            // Without a subscription, Apple's trial, for what was picked.
            if musicService.subscriptionState == .notSubscribed {
                Button(String(localized: "onboarding.trySubscription")) {
                    SubscriptionOffer.shared.offer(itemID: offer.itemID, toPlay: true)
                }
            }
            Button(String(localized: "catalog.offer.add")) { add(offer) }
            if case .song(let song) = offer {
                Button(String(localized: "playlist.add.action")) { PlaylistAdder.shared.offer(.song(song)) }
            }
            if let url = offer.url {
                Button(String(localized: "catalog.offer.open")) { openURL(url) }
            }
            Button(String(localized: "catalog.offer.cancel"), role: .cancel) {}
        } message: { _ in
            Text(String(localized: "catalog.offer.message"))
        }
    }

    private var fold: LiquidFoldState { .shared }

    // MARK: Moving

    /// Pages pushed and popped by flooding: into a page's own colour (an album's cover
    /// colour, the library's ground for the rest), and back into the colour of the page
    /// underneath.
    private var navigator: LiquidNavigator {
        LiquidNavigator(
            push: { route in
                deck = nil
                Task {
                    let color = await Self.color(of: route)
                    flood(color) { path.append(route) }
                }
            },
            back: {
                guard !path.isEmpty else { return }
                let under = path.count >= 2 ? path[path.count - 2] : nil
                Task {
                    var color = Color.liquidGround
                    if let under { color = await Self.color(of: under) }
                    flood(color) { if !path.isEmpty { path.removeLast() } }
                }
            },
            queueAlbum: { album, placement in
                guard !album.isPodcast else { return }
                Task {
                    let tracks = await library.tracks(for: album)
                    onQueue(tracks, placement, album.tapeTitle)
                }
            },
            findShows: onFindShows,
            play: onPlay,
            playSongs: onPlaySongs,
            queue: onQueue,
            loadTracks: { album in await library.tracks(for: album) },
            album: { track in
                let title = TapeFormat.displayTitle(track.albumTitle)
                let albums = library.albums.filter { $0.tapeTitle == title }
                return albums.first { $0.artistName == track.artistName } ?? albums.first
            },
            catalogSong: { song, list, name in
                guard librarySong(song) != nil || musicService.canStream else {
                    catalogOffer = .song(song)
                    return
                }
                let songs = list.contains(song) ? list : [song]
                let tracks = songs.map(catalogTrack)
                onPlaySongs(tracks, songs.firstIndex(of: song) ?? 0, false, name)
            },
            catalogAlbum: { album in
                if let mine = AppleMusicCatalog.libraryAlbum(title: album.title, artist: album.artistName, in: library.albums) {
                    navigator.push(.album(mine))
                } else {
                    catalogOffer = .album(album)
                }
            },
            addSong: { song in await addQuietly(song) },
            librarySong: librarySong,
            catalogTrack: catalogTrack,
            hasArtist: { name in
                let key = ArtistPhotos.key(for: name)
                return library.albums.contains { ArtistPhotos.key(for: $0.artistName) == key }
            },
            openCatalogAlbums: { albums, index, title in
                let mine = library.albums
                let items: [LiquidDeckItem] = albums.map { album in
                    .album(AppleMusicCatalog.libraryAlbum(title: album.title, artist: album.artistName, in: mine)
                           ?? AppAlbum(from: album, catalog: true))
                }
                navigator.openDeck(items, index, title)
            },
            addAlbum: { album in add(.album(album)) },
            openDeck: { items, index, title in
                guard items.indices.contains(index) else { return }
                // Chosen from a search: the keyboard goes, rather than covering the card.
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                    deck = LiquidDeck(items: items, index: index, title: title)
                }
            }
        )
    }

    /// A page's kind, with nothing of what's on it.
    private static func diagnosticName(_ route: LiquidRoute) -> String {
        switch route {
        case .album(let album): album.isPodcast ? "show" : album.isMixtape ? "playlist" : "album"
        case .artist: "artist"
        default: String(describing: route)
        }
    }

    private func closeDeck() {
        guard deck != nil else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { deck = nil }
    }

    /// A card's page: an album's or playlist's own, or an artist's page of albums, whose
    /// albums open as cards in turn.
    @ViewBuilder
    private func card(for item: LiquidDeckItem) -> some View {
        switch item {
        case .album(let album):
            LiquidAlbumPage(album: album, library: library, musicService: musicService,
                            onPlay: onPlay, onQueue: onQueue, bottomInset: bottomInset)
        case .artist(let name):
            LiquidGridPage(title: name, items: library.albums.filter { $0.artistName == name },
                           emptyText: String(localized: "spool.shelf.empty"), bottomInset: bottomInset,
                           layout: .constant(.grid), musicService: musicService, showsIndex: false,
                           isArtist: true, opensInDeck: true)
        }
    }

    private func librarySong(_ song: Song) -> AppTrack? {
        AppleMusicCatalog.librarySong(title: song.title, artist: song.artistName, duration: song.duration,
                                      explicit: song.contentRating.map { $0 == .explicit }, in: musicService)
    }

    private func catalogTrack(_ song: Song) -> AppTrack {
        librarySong(song) ?? AppTrack(from: song, catalog: true)
    }

    /// Streams a catalogue album the library hasn't, from the top.
    private func play(_ album: Album) {
        Task {
            let tracks = (try? await album.with([.tracks]).tracks).map { $0.map { AppTrack(from: $0, catalog: true) } } ?? []
            guard !tracks.isEmpty else { return onNotice(String(localized: "catalog.play.failed")) }
            onPlaySongs(tracks, 0, true, album.title)
        }
    }

    /// Something from the catalogue that isn't in the library, offered to be added.
    enum CatalogOffer: Identifiable {
        case song(Song)
        case album(Album)

        var id: String {
            switch self {
            case .song(let song): "song:" + song.id.rawValue
            case .album(let album): "album:" + album.id.rawValue
            }
        }
        var title: String {
            switch self {
            case .song(let song): song.title
            case .album(let album): album.title
            }
        }
        var url: URL? {
            switch self {
            case .song(let song): song.url
            case .album(let album): album.url
            }
        }
        var itemID: String {
            switch self {
            case .song(let song): song.id.rawValue
            case .album(let album): album.id.rawValue
            }
        }
    }

    /// Adds it to the library, then, once Apple has put it there, opens its page (an
    /// album). A song isn't played: adding isn't asking to play it (App Review 4.5.2:
    /// the listener starts every Apple Music stream). Apple can take a little while; if
    /// it hasn't arrived after half a minute, it's left to turn up on its own.
    private func add(_ offer: CatalogOffer) {
        Task {
            do {
                let subscribed = musicService.subscriptionState.isSubscribed
                switch offer {
                case .song(let song): try await AppleMusicCatalog.shared.add(song, subscribed: subscribed)
                case .album(let album): try await AppleMusicCatalog.shared.add(album, subscribed: subscribed)
                }
                onNotice(String(format: String(localized: "catalog.added"), offer.title))
            } catch {
                onNotice(error.localizedDescription)
                return
            }
            for _ in 0..<10 {
                try? await Task.sleep(for: .seconds(3))
                await musicService.refreshOnForeground()
                switch offer {
                case .song(let song):
                    if librarySong(song) != nil { return }
                case .album(let album):
                    if let mine = AppleMusicCatalog.libraryAlbum(title: album.title, artist: album.artistName, in: library.albums) {
                        // Over a card (added from its page), the card stays.
                        if deck == nil { navigator.push(.album(mine)) }
                        return
                    }
                }
            }
            onNotice(String(format: String(localized: "catalog.added.later"), offer.title))
        }
    }

    /// Adds a song to the library without playing it, as a row's + asks: says so, then
    /// looks for it in the library a few times so the row's tick comes from the library.
    private func addQuietly(_ song: Song) async -> Bool {
        do {
            try await AppleMusicCatalog.shared.add(song, subscribed: musicService.subscriptionState.isSubscribed)
        } catch {
            onNotice(error.localizedDescription)
            return false
        }
        onNotice(String(format: String(localized: "catalog.added.quiet"), song.title))
        Task {
            for _ in 0..<10 where librarySong(song) == nil {
                try? await Task.sleep(for: .seconds(3))
                await musicService.refreshOnForeground()
            }
        }
        return true
    }

    /// The most played songs, worked out at most every half minute for the same
    /// library: each song's count is a lookup in the media library, and the page is
    /// redrawn far more often than counts change.
    private static func mostPlayed(_ songs: [AppTrack]) -> [AppTrack] {
        if let memo = mostPlayedMemo, memo.songs == songs, Date().timeIntervalSince(memo.at) < 30 { return memo.result }
        let result = AppTrack.mostPlayed(songs)
        mostPlayedMemo = (songs, result, Date())
        return result
    }

    private static var mostPlayedMemo: (songs: [AppTrack], result: [AppTrack], at: Date)?

    private static func color(of route: LiquidRoute) async -> Color {
        if case .album(let album) = route {
            return await LiquidColors.shared.color(for: album).liquidDeep
        }
        return .liquidGround
    }

    // MARK: Big Type

    /// The first page: a lava lamp, a blob for each way in (see LiquidLavaMenu).
    private var menu: some View {
        LiquidLavaMenu(
            musicService: musicService,
            themeSettings: themeSettings,
            items: Self.menuItems,
            onChoose: { route, centre, color in
                // The chosen blob's colour floods out from its middle, and the page is there.
                flood(color, from: centre) {
                    path.append(route)
                }
            },
            onOpenSettings: onOpenSettings,
            bottomInset: bottomInset,
            pull: lavaPull,
            isShowing: path.isEmpty
        )
        .toolbar(.hidden, for: .navigationBar)
    }

    private static var menuItems: [(id: String, title: String, route: LiquidRoute)] {
        [("albums", String(localized: "liquid.menu.albums"), .albums),
         ("artists", String(localized: "liquid.menu.artists"), .artists),
         ("songs", String(localized: "liquid.menu.songs"), .songs),
         ("playlists", String(localized: "liquid.menu.playlists"), .playlists),
         ("discover", String(localized: "discover.title").lowercased(), .discover),
         ("recentlyAdded", String(localized: "liquid.menu.recentlyAdded"), .recentlyAdded),
         ("recentlyPlayed", String(localized: "liquid.menu.recentlyPlayed"), .recentlyPlayed),
         ("podcasts", String(localized: "liquid.menu.podcasts"), .podcasts),
         ("search", String(localized: "liquid.menu.search"), .search)]
    }

    // MARK: Pages

    @ViewBuilder
    private func page(for route: LiquidRoute) -> some View {
        switch route {
        // Each list keeps its own way of being shown: all at once, or one at a time.
        case .albums:
            LiquidRememberedLayout("albums") { layout in
                LiquidGridPage(title: String(localized: "liquid.menu.albums"), items: library.albums,
                               emptyText: String(localized: "spool.shelf.empty"), bottomInset: bottomInset,
                               layout: layout, musicService: musicService, opensInDeck: true)
            }
        case .playlists:
            LiquidRememberedLayout("playlists") { layout in
                LiquidGridPage(title: String(localized: "liquid.menu.playlists"), items: library.mixtapes,
                               emptyText: String(localized: "spool.shelf.mixtapes.empty"), bottomInset: bottomInset,
                               layout: layout, musicService: musicService, opensInDeck: true,
                               searchAction: (String(localized: "playlist.new.action"), "plus", "liquid.newPlaylist",
                                              { PlaylistAdder.shared.promptNewPlaylist() }))
            }
        case .podcasts:
            LiquidRememberedLayout("podcasts") { layout in
                LiquidGridPage(title: String(localized: "liquid.menu.podcasts"), items: library.podcasts,
                               emptyText: String(localized: "spool.shelf.podcasts.empty"), bottomInset: bottomInset,
                               layout: layout, musicService: musicService,
                               emptyAction: (String(localized: "spool.shelf.findShows"), onFindShows), opensInDeck: true,
                               searchAction: (String(localized: "spool.shelf.findShows"), "plus.magnifyingglass",
                                              "liquid.podcasts.findShows", onFindShows))
            }
        case .artists:
            LiquidArtistsPage(albums: library.albums, bottomInset: bottomInset)
        case .artist(let name):
            LiquidRememberedLayout("artist", place: "artist." + name) { layout in
                LiquidGridPage(title: name, items: library.albums.filter { $0.artistName == name },
                               emptyText: String(localized: "spool.shelf.empty"), bottomInset: bottomInset,
                               layout: layout, musicService: musicService, showsIndex: false,
                               isArtist: true)
            }
        case .songs:
            LiquidRememberedLayout("songs") { layout in
                LiquidSongsPage(title: String(localized: "liquid.menu.songs"), tracks: library.songs,
                                emptyText: String(localized: "liquid.songs.empty"), isAlphabetical: true,
                                musicService: musicService, onPlay: onPlaySongs, onQueue: onQueue,
                                bottomInset: bottomInset, layout: layout)
            }
        case .recentlyPlayed:
            LiquidRememberedLayout("recentlyPlayed") { layout in
                LiquidSongsPage(title: String(localized: "liquid.menu.recentlyPlayed"), tracks: musicService.recentlyPlayed,
                                emptyText: String(localized: "liquid.recentlyPlayed.empty"), isAlphabetical: false,
                                musicService: musicService, onPlay: onPlaySongs, onQueue: onQueue,
                                bottomInset: bottomInset, layout: layout,
                                link: (String(localized: "liquid.menu.mostPlayed"), .mostPlayed))
            }
        case .mostPlayed:
            LiquidRememberedLayout("mostPlayed") { layout in
                LiquidSongsPage(title: String(localized: "liquid.menu.mostPlayed"), tracks: Self.mostPlayed(library.songs),
                                emptyText: String(localized: "liquid.mostPlayed.empty"), isAlphabetical: false,
                                musicService: musicService, onPlay: onPlaySongs, onQueue: onQueue,
                                bottomInset: bottomInset, layout: layout)
            }
        case .recentlyAdded:
            LiquidRememberedLayout("recentlyAdded") { layout in
                LiquidSongsPage(title: String(localized: "liquid.menu.recentlyAdded"), tracks: musicService.recentlyAdded,
                                emptyText: String(localized: "liquid.recentlyAdded.empty"), isAlphabetical: false,
                                musicService: musicService, onPlay: onPlaySongs, onQueue: onQueue,
                                bottomInset: bottomInset, layout: layout)
            }
        case .search:
            LiquidSearchPage(library: library, bottomInset: bottomInset)
        case .discover:
            LiquidDiscoverPage(musicService: musicService, bottomInset: bottomInset)
        case .album(let album):
            LiquidAlbumPage(album: album, library: library, musicService: musicService,
                            onPlay: onPlay, onQueue: onQueue, bottomInset: bottomInset)
        }
    }
}

/// A word in the menu: it dims a little while pressed.
private struct LiquidWordStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.5 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1, anchor: .leading)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The library's ground: near-black with the colours of what's playing drifting in it.
struct LiquidWash: View {
    @ObservedObject var musicService: MusicService
    @State private var color: Color = Color(red: 0.17, green: 0.29, blue: 0.48)

    var body: some View {
        Color(red: 0.063, green: 0.063, blue: 0.071)
            .overlay {
                Circle()
                    .fill(color)
                    .frame(width: 440, height: 440)
                    .blur(radius: 120)
                    .opacity(0.45)
                    .offset(x: 140, y: -160)
                Circle()
                    .fill(color.liquidDeep)
                    .frame(width: 380, height: 380)
                    .blur(radius: 110)
                    .opacity(0.7)
                    .offset(x: -150, y: 260)
            }
            .clipped()
            .ignoresSafeArea()
        .accessibilityHidden(true)
        .task(id: musicService.nowPlayingTrack?.id) {
            guard let track = musicService.nowPlayingTrack else { return }
            let found = await LiquidColors.shared.color(for: track)
            withAnimation(.easeInOut(duration: 0.8)) { color = found }
        }
    }
}

// MARK: - Grid

struct LiquidGridPage: View {
    @Environment(\.liquidNavigator) private var navigator
    let title: String
    let items: [AppAlbum]
    let emptyText: String
    let bottomInset: CGFloat
    /// All at once or one at a time, as this list was last left.
    @Binding var layout: LiquidLayout
    @ObservedObject var musicService: MusicService
    var emptyAction: (title: String, action: () -> Void)?
    var showsIndex = true
    /// One artist's albums: the page opens on their photo.
    var isArtist = false
    /// A cover tapped in the grid opens as a card, the other covers either side of it
    /// (LiquidCardDeck), rather than as a page.
    var opensInDeck = false
    /// A button beside the search: Find Shows, on the podcasts page.
    var searchAction: (title: String, symbol: String, id: String, action: () -> Void)?

    @Environment(\.liquidCard) private var card
    @State private var query = ""
    /// How tall the name and search are at the top of the grid: the letter index starts
    /// below them, so on a short screen (an iPhone Duo closed) it isn't run up past the
    /// search and the back button into the corner.
    @State private var headerHeight: CGFloat = 0
    /// How wide the covers have to lay out in, for how many go across.
    @State private var gridWidth: CGFloat = 0

    private var shown: [AppAlbum] {
        let terms = query.lowercased().split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return items }
        return items.filter { album in
            let text = (album.title + " " + album.artistName).lowercased()
            return terms.allSatisfy { text.contains($0) }
        }
    }

    var body: some View {
        Group {
            if layout == .stack {
                stack
            } else {
                grid
            }
        }
        .background(LiquidPageGround())
        .toolbar(.hidden, for: .navigationBar)
    }

    /// One cover at a time.
    private var stack: some View {
        let shown = self.shown
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 16) {
                LiquidPageTitle(title: title, layout: $layout, artist: isArtist ? (title, items.first) : nil)
                searchRow
            }
            .padding(.horizontal, 20)
            if shown.isEmpty {
                empty.padding(.horizontal, 20)
                Spacer()
            } else {
                LiquidCardStack(items: shown.map { .album($0) }, isAlphabetical: showsIndex,
                                musicService: musicService, bottomInset: bottomInset)
            }
        }
        .transition(.opacity)
    }

    private var searchRow: some View {
        HStack(spacing: 10) {
            LiquidSearchField(query: $query, prompt: String(format: String(localized: "liquid.search.in"), title))
            if let searchAction {
                Button(action: searchAction.action) {
                    Image(systemName: searchAction.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(.white.opacity(0.1), in: Circle())
                }
                .accessibilityLabel(searchAction.title)
                .accessibilityIdentifier(searchAction.id)
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(query.isEmpty ? emptyText : String(localized: "search.noResults"))
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.7))
            if let emptyAction, query.isEmpty {
                Button(emptyAction.title, action: emptyAction.action)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(.white, in: Capsule())
            }
        }
        .padding(.top, 20)
    }

    /// Every cover at once.
    private var grid: some View {
        let shown = self.shown
        return ScrollViewReader { proxy in
            ZStack(alignment: .trailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 16) {
                            LiquidPageTitle(title: title, layout: $layout, artist: isArtist ? (title, items.first) : nil)
                            // Nothing of theirs in the library to search (an artist from Apple Music).
                            if !(isArtist && items.isEmpty) {
                            HStack(spacing: 10) {
                                LiquidSearchField(query: $query, prompt: String(format: String(localized: "liquid.search.in"), title))
                                if let searchAction {
                                    Button(action: searchAction.action) {
                                        Image(systemName: searchAction.symbol)
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .frame(width: 46, height: 46)
                                            .background(.white.opacity(0.1), in: Circle())
                                    }
                                    .accessibilityLabel(searchAction.title)
                                    .accessibilityIdentifier(searchAction.id)
                                }
                            }
                            }
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                        // An artist's page: what Apple Music says of them, above their albums.
                        if isArtist, query.isEmpty {
                            LiquidArtistIntro(name: title)
                                .padding(.trailing, 20)
                        }
                        if isArtist, items.isEmpty, AppleMusicCatalog.isAvailable {
                            // An artist the library hasn't (a similar artist, one found in
                            // search): what Apple Music has of them.
                            LiquidCatalogArtistAlbums(name: title, width: gridWidth)
                                .padding(.trailing, 20)
                        } else if shown.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(query.isEmpty ? emptyText : String(localized: "search.noResults"))
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white.opacity(0.7))
                                if let emptyAction, query.isEmpty {
                                    Button(emptyAction.title, action: emptyAction.action)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 18)
                                        .frame(height: 44)
                                        .background(.white, in: Capsule())
                                }
                            }
                            .padding(.top, 20)
                        } else {
                            LazyVGrid(columns: LiquidCoverTile.columns(for: gridWidth),
                                      spacing: 18) {
                                ForEach(shown) { album in
                                    Button { open(album, in: shown) } label: {
                                        LiquidCoverTile(album: album)
                                    }
                                    .modifier(LiquidAlbumHoldMenu(album: album))
                                    .buttonStyle(.plain)
                                    .id(album.id)
                                    .accessibilityIdentifier("liquid.cover.\(album.id)")
                                }
                            }
                        }
                        if isArtist, query.isEmpty {
                            LiquidSimilarArtists(name: title)
                                .padding(.top, 10)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
                    .padding(.leading, 20)
                    .padding(.trailing, showsIndex && shown.count >= 12 ? 40 : 20)
                    .padding(.bottom, bottomInset + 20)
                }
                .scrollDismissesKeyboard(.immediately)
                .reportsLiquidCardScroll(card)

                if showsIndex, shown.count >= 12 {
                    LiquidLetterStrip(titles: shown.map(\.title)) { index in
                        proxy.scrollTo(shown[index].id, anchor: .top)
                    }
                    .padding(.trailing, 6)
                    // Level with the first row of covers, below the name and search.
                    .padding(.top, headerHeight + 16)
                    .padding(.bottom, bottomInset + 12)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .transition(.opacity)
    }

    private func open(_ album: AppAlbum, in shown: [AppAlbum]) {
        if opensInDeck, let index = shown.firstIndex(of: album) {
            navigator.openDeck(shown.map { .album($0) }, index, title)
        } else {
            navigator.push(.album(album))
        }
    }
}

/// A cover in a grid, with its name and artist under it.
struct LiquidCoverTile: View {
    let album: AppAlbum

    /// The columns for a grid of covers `width` wide: two on a phone, more where there's
    /// room (an iPhone Duo open, an iPad), and always an even number, so on a Duo held
    /// as a book the fold falls between two columns rather than across one.
    static func columns(for width: CGFloat) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnCount(for: width))
    }

    static func columnCount(for width: CGFloat) -> Int {
        let fit = Int((width + spacing) / (minimumWidth + spacing))
        return max(2, fit - fit % 2)
    }

    static let spacing: CGFloat = 14
    /// The narrowest a cover gets before a column is dropped.
    private static let minimumWidth: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LiquidCover(source: .album(album))
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 10, y: 6)
            HStack(spacing: 5) {
                Text(album.tapeTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                // An explicit album is marked, beside its clean version (LYRE-23).
                if album.isExplicit { ExplicitBadge() }
            }
            Text(album.caseByline ?? album.artistName)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A page's name in big type, with the way back above it.
struct LiquidPageTitle: View {
    let title: String
    /// The page's layout, when it has a choice: a switch beside the name.
    var layout: Binding<LiquidLayout>? = nil
    /// An artist's page: their name, and an album to stand in for their photo, which
    /// goes large above the title.
    var artist: (name: String, fallback: AppAlbum?)? = nil
    @Environment(\.liquidNavigator) private var navigator
    @Environment(\.liquidCard) private var card

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // In a card, the way back closes it.
            Button { navigator.back() } label: {
                Image(systemName: card == nil ? "chevron.left" : "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.1), in: Circle())
            }
            .foregroundStyle(.white)
            // Its own button: on a list's first row, a tap elsewhere on the row isn't one.
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: card == nil ? "liquid.back" : "liquid.card.close"))
            .accessibilityIdentifier("liquid.back")
            if let artist {
                // Their photo, large, in a slowly drifting soap bubble (LiquidSoapBubble).
                LiquidSoapBubble(diameter: 240, wobbles: true) {
                    ArtistPhoto(name: artist.name, fallback: artist.fallback, size: 240)
                }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(format: String(localized: "artist.photo"), artist.name))
                    .accessibilityAddTraits(.isImage)
                    .accessibilityIdentifier("liquid.artist.photo")
            }
            HStack(alignment: .center) {
                Text(title.lowercasedKeepingAppleMusic)
                    .font(.system(size: 44, weight: .medium))
                    .tracking(-1.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let layout, card == nil {
                    LiquidLayoutSwitch(layout: layout)
                }
            }
        }
        .padding(.top, 8)
    }
}

struct LiquidSearchField: View {
    @Binding var query: String
    let prompt: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.6))
                .accessibilityHidden(true)
            TextField("", text: $query, prompt: Text(prompt).foregroundStyle(.white.opacity(0.45)))
                .foregroundStyle(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .accessibilityIdentifier("liquid.search.field")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.6))
                }
                .accessibilityLabel(String(localized: "search.clear"))
            }
        }
        .font(.system(size: 16))
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(.white.opacity(0.1), in: Capsule())
    }
}

/// The ground behind the library's pages.
struct LiquidPageGround: View {
    var body: some View {
        Color(red: 0.063, green: 0.063, blue: 0.071).ignoresSafeArea()
    }
}

/// An A–Z strip down the edge: a finger on it jumps to the first title under each letter.
/// The first title under a letter, in an A–Z index.
struct LiquidLetterEntry {
    let letter: String
    let index: Int

    /// Each letter once, pointing at its first title, in the order an index reads:
    /// "#" first, then A–Z, then letters of other scripts as they come. An accented
    /// letter files under its plain one ("Ánimo" under A), so the strip isn't split
    /// into A and Á however the titles happen to be ordered.
    static func index(_ titles: [String]) -> [LiquidLetterEntry] {
        var seen = Set<String>()
        var result: [LiquidLetterEntry] = []
        for (index, title) in titles.enumerated() {
            let letter = filingLetter(of: title)
            if seen.insert(letter).inserted { result.append(LiquidLetterEntry(letter: letter, index: index)) }
        }
        return result.enumerated().sorted { lhs, rhs in
            let left = rank(lhs.element.letter), right = rank(rhs.element.letter)
            return left != right ? left < right : lhs.offset < rhs.offset
        }.map(\.element)
    }

    static func filingLetter(of title: String) -> String {
        AppHelpers.firstLetter(of: title).folding(options: .diacriticInsensitive, locale: nil)
    }

    /// Where a letter goes along the strip: "#", then A–Z, then the rest.
    private static func rank(_ letter: String) -> Int {
        if letter == "#" { return 0 }
        if let scalar = letter.unicodeScalars.first, letter.unicodeScalars.count == 1,
           ("A"..."Z").contains(scalar) {
            return 1 + Int(scalar.value - UnicodeScalar("A").value)
        }
        return 100
    }
}

/// The letter under a finger on a Liquid index, large and bold on a disc beside it, as
/// the other players' indexes show it.
struct LiquidLetterBubble: View {
    let letter: String

    var body: some View {
        Text(letter)
            .font(.system(size: 26, weight: .bold, design: .rounded))
            .foregroundStyle(.black)
            .frame(width: 50, height: 50)
            .background(Circle().fill(.white))
            .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct LiquidLetterStrip: View {
    let titles: [String]
    let onJump: (Int) -> Void
    /// The letters' colour: white on Liquid's dark pages; the Spool's J-card and the
    /// Disc's booklet are pale, and ask for dark.
    var ink: Color = .white

    @State private var lastLetter: String?
    /// Where along the strip the finger is, for the letter's bubble.
    @State private var fingerAt: CGFloat = 0

    /// The first title under each letter: worked out when the titles change, not on
    /// every redraw (a finger along the index redraws it at every letter it crosses).
    @State private var letters: [LiquidLetterEntry] = []

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ForEach(letters, id: \.letter) { entry in
                    Text(entry.letter)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(ink.opacity(lastLetter == entry.letter ? 1 : 0.6))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !letters.isEmpty else { return }
                        let row = Int((value.location.y - 8) / max(1, (geometry.size.height - 16) / CGFloat(letters.count)))
                        let entry = letters[min(letters.count - 1, max(0, row))]
                        fingerAt = min(max(value.location.y, 26), geometry.size.height - 26)
                        guard entry.letter != lastLetter else { return }
                        withAnimation(lastLetter == nil ? .spring(response: 0.25, dampingFraction: 0.7) : nil) {
                            lastLetter = entry.letter
                        }
                        UISelectionFeedbackGenerator().selectionChanged()
                        onJump(entry.index)
                    }
                    .onEnded { _ in withAnimation(.easeOut(duration: 0.15)) { lastLetter = nil } }
            )
            .overlay(alignment: .topLeading) {
                // Beside the finger, to its left, where the finger doesn't cover it.
                if let lastLetter {
                    LiquidLetterBubble(letter: lastLetter)
                        .position(x: -34, y: fingerAt)
                }
            }
        }
        .frame(width: 24)
        .frame(maxHeight: 520)
        .background(ink.opacity(0.07), in: Capsule())
        .onChange(of: titles, initial: true) { letters = LiquidLetterEntry.index(titles) }
        .accessibilityElement()
        .accessibilityLabel(String(localized: "liquid.index"))
        .accessibilityIdentifier("liquid.index")
    }
}

// MARK: - Artists

struct LiquidArtistsPage: View {
    @Environment(\.liquidNavigator) private var navigator
    let albums: [AppAlbum]
    let bottomInset: CGFloat

    typealias Artist = (name: String, count: Int, album: AppAlbum?)

    /// Each artist with how many albums, and one to stand in for their photo. Grouped
    /// and sorted once for a set of albums, not on every redraw (that took a fifth of
    /// a second with a big library).
    private var artists: [Artist] {
        if let memo = Self.memo, memo.albums == albums { return memo.artists }
        let artists: [Artist] = Dictionary(grouping: albums, by: \.artistName)
            .map { ($0.key, $0.value.count, $0.value.first) }
            .filter { !$0.0.isEmpty }
            .sorted { AppHelpers.sortsBefore($0.0, $1.0) }
        Self.memo = (albums, artists)
        return artists
    }

    private static var memo: (albums: [AppAlbum], artists: [Artist])?

    @State private var query = ""
    @State private var headerHeight: CGFloat = 0

    /// The artists whose name has every word typed, as the other lists search.
    private var shown: [Artist] {
        let terms = LibrarySearch.terms(query)
        guard !terms.isEmpty else { return artists }
        return artists.filter { LibrarySearch.matches(terms, $0.name) }
    }

    var body: some View {
        let shown = self.shown
        let showsIndex = query.isEmpty && shown.count >= 12
        return ScrollViewReader { proxy in
            ZStack(alignment: .topTrailing) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        VStack(alignment: .leading, spacing: 16) {
                            LiquidPageTitle(title: String(localized: "liquid.menu.artists"))
                            LiquidSearchField(query: $query, prompt: String(format: String(localized: "liquid.search.in"),
                                                                            String(localized: "liquid.menu.artists")))
                        }
                        .padding(.bottom, 12)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                        if shown.isEmpty {
                            Text(String(localized: query.isEmpty ? "spool.shelf.empty" : "search.noResults"))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        ForEach(Array(shown.enumerated()), id: \.element.name) { index, artist in
                            Button {
                                navigator.openDeck(shown.map { .artist($0.name) }, index, String(localized: "liquid.menu.artists"))
                            } label: {
                                HStack(alignment: .center, spacing: 14) {
                                    LiquidSoapBubble(diameter: 56) {
                                        ArtistPhoto(name: artist.name, fallback: artist.album, size: 56)
                                    }
                                    Text(artist.name)
                                        .font(.system(size: 30, weight: .medium))
                                        .tracking(-0.8)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.6)
                                    Spacer(minLength: 8)
                                    Text("\(artist.count)")
                                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                .foregroundStyle(.white)
                                .frame(minHeight: 64)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(LiquidWordStyle())
                            .id(artist.name)
                            .accessibilityIdentifier("liquid.artist.\(artist.name)")
                        }
                    }
                    .padding(.leading, 20)
                    .padding(.trailing, showsIndex ? 40 : 20)
                    .padding(.bottom, bottomInset + 20)
                }
                .scrollDismissesKeyboard(.immediately)

                // A to Z down the side, as the albums have.
                if showsIndex {
                    LiquidLetterStrip(titles: Self.names(of: shown)) { index in
                        proxy.scrollTo(shown[index].name, anchor: .top)
                    }
                    .padding(.trailing, 6)
                    .padding(.top, headerHeight + 16)
                    .padding(.bottom, bottomInset + 12)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .background(LiquidPageGround())
        .toolbar(.hidden, for: .navigationBar)
    }

    /// The names for the A–Z strip, kept for the same list (the strip compares them).
    private static func names(of artists: [Artist]) -> [String] {
        if let namesMemo, namesMemo.count == artists.count, namesMemo.first == artists.first?.name,
           namesMemo.last == artists.last?.name { return namesMemo }
        let names = artists.map(\.name)
        namesMemo = names
        return names
    }

    private static var namesMemo: [String]?
}

// MARK: - Search

struct LiquidSearchPage: View {
    @Environment(\.liquidNavigator) private var navigator
    let library: ShelfLibrary
    let bottomInset: CGFloat

    @State private var query = ""
    @State private var matches: ShelfSearchMatches?
    /// What Apple Music has for the query, below the library's.
    @State private var catalog: AppleMusicCatalog.SearchResults?
    /// What Apple Music suggests searching for as the query's typed: each tapped, it's
    /// searched for.
    @State private var suggestions: [(display: String, search: String)] = []
    @State private var gridWidth: CGFloat = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LiquidPageTitle(title: String(localized: "liquid.menu.search"))
                LiquidSearchField(query: $query, prompt: String(localized: "liquid.search.prompt"))
                    .focused($isFocused)
                if !query.isEmpty, !suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestions, id: \.search) { suggestion in
                                Button { query = suggestion.search } label: {
                                    Label(suggestion.display, systemImage: "magnifyingglass")
                                        .font(.system(size: 14, weight: .medium))
                                        .lineLimit(1)
                                        .padding(.horizontal, 12)
                                        .frame(minHeight: 36)
                                        .background(.white.opacity(0.12), in: Capsule())
                                }
                                .foregroundStyle(.white)
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("liquid.search.suggestion")
                            }
                        }
                    }
                    .accessibilityLabel(String(localized: "search.suggestions"))
                }
                if let matches {
                    let sections: [(String, [AppAlbum])] = [
                        (String(localized: "liquid.menu.albums"), matches.albums),
                        (String(localized: "liquid.menu.playlists"), matches.mixtapes),
                        (String(localized: "liquid.menu.podcasts"), matches.podcasts)
                    ].filter { !$0.1.isEmpty }
                    if sections.isEmpty, catalog?.isEmpty != false {
                        Text(String(localized: "search.noResults"))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    ForEach(sections, id: \.0) { section in
                        Text(section.0.lowercasedKeepingAppleMusic)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(.white)
                        LazyVGrid(columns: LiquidCoverTile.columns(for: gridWidth), spacing: 18) {
                            ForEach(Array(section.1.enumerated()), id: \.element.id) { index, album in
                                Button { navigator.openDeck(section.1.map { .album($0) }, index, section.0) } label: {
                                    LiquidCoverTile(album: album)
                                }
                                    .modifier(LiquidAlbumHoldMenu(album: album))
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("liquid.search.cover.\(album.id)")
                            }
                        }
                    }
                }
                if let catalog, !catalog.isEmpty, !query.isEmpty {
                    LiquidCatalogSearch(results: catalog)
                        .padding(.top, 6)
                }
                // Nothing typed yet: what's most played on Apple Music.
                if query.isEmpty {
                    LiquidCharts()
                        .padding(.top, 6)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
            .padding(.horizontal, 20)
            .padding(.bottom, bottomInset + 20)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(LiquidPageGround())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: query) {
            if !query.isEmpty {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
            }
            matches = LibrarySearch.shelfMatches(for: query, in: library)
        }
        .task(id: query) {
            // Suggestions as typing pauses; none once one is what's typed.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let found = await AppleMusicCatalog.shared.suggestions(for: query)
            guard !Task.isCancelled else { return }
            suggestions = found.filter { $0.search.caseInsensitiveCompare(query) != .orderedSame }
        }
        .task(id: query) {
            // The catalogue is asked once typing has paused a little longer.
            guard AppleMusicCatalog.searchTerm(query) != nil else { catalog = nil; return }
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            let found = await AppleMusicCatalog.shared.search(query)
            guard !Task.isCancelled else { return }
            catalog = found
        }
        .onAppear { isFocused = true }
    }
}

// MARK: - Songs

/// A list of songs: every song (by name, with an A–Z strip), or the recently played or
/// added (newest first). Each row has its cover; tapped, it plays from there through the
/// rest of the list, and swiped right, it offers Play Next and Add to Queue.
struct LiquidSongsPage: View {
    let title: String
    let tracks: [AppTrack]
    let emptyText: String
    /// Every song, by name, with the A–Z strip. (Every list is searchable.)
    let isAlphabetical: Bool
    @ObservedObject var musicService: MusicService
    let onPlay: ([AppTrack], Int, Bool, String) -> Void
    let onQueue: ([AppTrack], QueuePlacement, String) -> Void
    let bottomInset: CGFloat
    /// All at once or one at a time, as this list was last left.
    @Binding var layout: LiquidLayout
    /// Another list, offered under the title (Most Played, from Recently Played).
    var link: (title: String, route: LiquidRoute)? = nil

    @State private var query = ""
    @Environment(\.liquidNavigator) private var linkNavigator

    /// The other list, as a pill under the title.
    @ViewBuilder private var linkButton: some View {
        if let link {
            Button { linkNavigator.push(link.route) } label: {
                Label(link.title, systemImage: "chart.bar.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(.white.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("liquid.link.\(link.title)")
        }
    }

    private var shown: [AppTrack] {
        let terms = query.lowercased().split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return tracks }
        return tracks.filter { track in
            let text = (track.title + " " + track.artistName + " " + track.albumTitle).lowercased()
            return terms.allSatisfy { text.contains($0) }
        }
    }

    var body: some View {
        Group {
            if layout == .stack {
                stack
            } else {
                list
            }
        }
        .foregroundStyle(.white)
        .background(LiquidPageGround())
        .toolbar(.hidden, for: .navigationBar)
    }

    /// One cover at a time.
    private var stack: some View {
        let shown = self.shown
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 16) {
                LiquidPageTitle(title: title, layout: $layout)
                linkButton
                // Every list can be searched; only every song, filed by name, has the A–Z strip.
                LiquidSearchField(query: $query, prompt: String(format: String(localized: "liquid.search.in"), title))
                if !shown.isEmpty {
                    playAndShuffle(shown, height: 44)
                }
            }
            .padding(.horizontal, 20)
            if shown.isEmpty {
                Text(query.isEmpty ? emptyText : String(localized: "search.noResults"))
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                Spacer()
            } else {
                LiquidCardStack(items: shown.enumerated().map { .song($1, list: shown, index: $0, listName: title) },
                                isAlphabetical: isAlphabetical && query.isEmpty,
                                musicService: musicService, bottomInset: bottomInset)
            }
        }
        .transition(.opacity)
    }

    /// Every song at once.
    private var list: some View {
        let shown = self.shown
        let playingID = musicService.currentTrack?.id
        let hasIndex = isAlphabetical && shown.count >= 12 && query.isEmpty
        return ScrollViewReader { proxy in
            ZStack(alignment: .trailing) {
                List {
                    VStack(alignment: .leading, spacing: 16) {
                        LiquidPageTitle(title: title, layout: $layout)
                linkButton
                        LiquidSearchField(query: $query, prompt: String(format: String(localized: "liquid.search.in"), title))
                        if !shown.isEmpty {
                            playAndShuffle(shown, height: 50)
                        } else {
                            Text(query.isEmpty ? emptyText : String(localized: "search.noResults"))
                                .font(.system(size: 16))
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.top, 8)
                        }
                    }
                    .padding(.bottom, 8)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    ForEach(Array(shown.enumerated()), id: \.offset) { index, track in
                        row(track, isPlaying: track.id == playingID) { onPlay(shown, index, false, title) }
                            .id(index)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button { onQueue([track], .next, track.title) } label: {
                                    Label(String(localized: "queue.action.playNext"), systemImage: "text.insert")
                                }
                                .tint(RowSwipeAction.playNextTint)
                                Button { onQueue([track], .last, track.title) } label: {
                                    Label(String(localized: "queue.action.addToQueue"), systemImage: "text.append")
                                }
                                .tint(RowSwipeAction.addToQueueTint)
                            }
                            .modifier(QueueMenu(isEnabled: true, track: track,
                                                onQueue: { onQueue($0, $1, track.title) }))
                            .accessibilityIdentifier("liquid.songs.track.\(index)")
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: hasIndex ? 40 : 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(.white.opacity(0.12))
                    }

                    Color.clear
                        .frame(height: bottomInset + 20)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.immediately)
                .environment(\.defaultMinListRowHeight, 1)

                if hasIndex {
                    LiquidLetterStrip(titles: Self.titles(of: shown)) { index in
                        proxy.scrollTo(index, anchor: .top)
                    }
                    .padding(.trailing, 6)
                    // Below the name, search, and Play and Shuffle.
                    .padding(.top, 250)
                    .padding(.bottom, bottomInset)
                }
            }
        }
        .transition(.opacity)
    }

    /// The songs' titles for the A–Z strip, kept for the same list: a big library's
    /// titles were mapped again, and compared again by the strip, on every redraw.
    private static func titles(of tracks: [AppTrack]) -> [String] {
        if let memo = titlesMemo, memo.tracks == tracks { return memo.titles }
        let titles = tracks.map(\.title)
        titlesMemo = (tracks, titles)
        return titles
    }

    private static var titlesMemo: (tracks: [AppTrack], titles: [String])?

    /// Play and Shuffle for the whole list, in either layout.
    private func playAndShuffle(_ shown: [AppTrack], height: CGFloat) -> some View {
        HStack(spacing: 10) {
            Button { onPlay(shown, 0, true, title) } label: {
                Label(String(localized: "detail.play"), systemImage: "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.liquidGround)
                    .frame(maxWidth: .infinity, minHeight: height)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("liquid.songs.play")
            Button { onPlay(shown.shuffled(), 0, true, title) } label: {
                Label(String(localized: "detail.shuffle"), systemImage: "shuffle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: height)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("liquid.songs.shuffle")
        }
    }

    private func row(_ track: AppTrack, isPlaying: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                LiquidCover(source: .track(track))
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(alignment: .center) {
                        if isPlaying {
                            Image(systemName: "waveform")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(track.title)
                            .font(.system(size: 16, weight: isPlaying ? .bold : .regular))
                            .lineLimit(1)
                        if track.isExplicit { ExplicitBadge() }
                    }
                    Text(track.albumTitle.isEmpty ? track.artistName : "\(track.artistName) · \(TapeFormat.displayTitle(track.albumTitle))")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if track.duration > 0 {
                    Text(AppHelpers.formatTime(track.duration))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(minHeight: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Album

/// An album (or playlist, or show) opened: its cover across the top, melting into its own
/// colour, then its name, Play and Shuffle, and its songs.
struct LiquidAlbumPage: View {
    let album: AppAlbum
    let library: ShelfLibrary
    @ObservedObject var musicService: MusicService
    let onPlay: (AppAlbum, [AppTrack], Int, Bool) -> Void
    let onQueue: ([AppTrack], QueuePlacement, String) -> Void
    let bottomInset: CGFloat

    @State private var tracks: [AppTrack]?
    @State private var color: Color
    @Environment(\.liquidNavigator) private var navigator
    @Environment(\.liquidCard) private var card

    init(album: AppAlbum, library: ShelfLibrary, musicService: MusicService,
         onPlay: @escaping (AppAlbum, [AppTrack], Int, Bool) -> Void,
         onQueue: @escaping ([AppTrack], QueuePlacement, String) -> Void, bottomInset: CGFloat) {
        self.album = album
        self.library = library
        self.musicService = musicService
        self.onPlay = onPlay
        self.onQueue = onQueue
        self.bottomInset = bottomInset
        // The flood that opened the page was this colour; start in it, so nothing jumps.
        _color = State(initialValue: LiquidColors.shared.cached("album:" + album.id) ?? Color(white: 0.12))
    }

    var body: some View {
        let ground = color.liquidDeep
        // A list, so each song can be swiped right to queue it.
        List {
            header(ground: ground)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            details(ground: ground)
                .listRowInsets(EdgeInsets(top: 4, leading: 24, bottom: 8, trailing: 24))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            if let tracks, !tracks.isEmpty {
                trackRows(tracks)
            }

            // Apple's write-up and the record label, after the songs.
            LiquidAlbumCredits(album: album)
                .listRowInsets(EdgeInsets(top: 20, leading: 24, bottom: 8, trailing: 24))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            Color.clear
                .frame(height: bottomInset + 24)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .reportsLiquidCardScroll(card)
        .environment(\.defaultMinListRowHeight, 1)
        .ignoresSafeArea(edges: .top)
        .foregroundStyle(.white)
        .background(ground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if tracks == nil, !album.preloadedTracks.isEmpty { tracks = album.tapeSongs(album.preloadedTracks) }
            async let found = LiquidColors.shared.color(for: album)
            let loaded = await library.tracks(for: album)
            if !loaded.isEmpty || tracks == nil { tracks = loaded }
            let tint = await found
            withAnimation(.easeInOut(duration: 0.4)) { color = tint }
            await AppleMusicCatalog.shared.loadAlbum(album)
        }
        // An edit saved (PlaylistEditSheet): the playlist's songs as they now are.
        .onChange(of: PlaylistEditCenter.shared.revision) {
            Task { tracks = await library.tracks(for: album) }
        }
    }

    /// The cover across the top, melting into the page's colour, with the way back and,
    /// opposite it, the album's queue menu.
    private func header(ground: Color) -> some View {
        ZStack(alignment: .topLeading) {
            LiquidCover(source: .album(album))
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .bottom) {
                    LiquidEdgeShape(amplitude: 0.55)
                        .fill(ground)
                        .frame(height: 60)
                        .offset(y: 1)
                }
            Button { navigator.back() } label: {
                Image(systemName: card == nil ? "chevron.left" : "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.3), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .padding(.leading, 16)
            // A card starts below the status bar.
            .padding(.top, card == nil ? 56 : 16)
            .accessibilityLabel(String(localized: card == nil ? "liquid.back" : "liquid.card.close"))
            .accessibilityIdentifier("liquid.back")
        }
        .overlay(alignment: .topTrailing) {
            // LYRE-14: the whole album to Up Next, without holding its cover. A show's
            // episodes can't be queued, so a show has none.
            HStack(spacing: 10) {
            // An album from Apple Music the library hasn't (from Discover, the charts,
            // search, an artist's card): added from here.
            if album.isCatalog, album.mixtape == nil, let catalogue = album.musicKitAlbum {
                Button { navigator.addAlbum(catalogue) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.3), in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .accessibilityLabel(String(localized: "catalog.offer.add"))
                .accessibilityIdentifier("liquid.album.add")
            }
            // A playlist Lyre made can be edited (LYRE-25).
            PlaylistEditButton(playlist: album.mixtape, identifier: "liquid.album.edit") {
                Image(systemName: "pencil")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.3), in: Circle())
                    .foregroundStyle(.white)
            }
            if !album.isPodcast {
                Menu {
                    Button { navigator.queueAlbum(album, .next) } label: {
                        Label(String(localized: "queue.action.playNext"), systemImage: "text.insert")
                    }
                    Button { navigator.queueAlbum(album, .last) } label: {
                        Label(String(localized: "queue.action.addToQueue"), systemImage: "text.append")
                    }
                } label: {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.3), in: Circle())
                }
                .foregroundStyle(.white)
                .accessibilityLabel(String(localized: "liquid.album.queueMenu"))
                .accessibilityIdentifier("liquid.album.queueMenu")
            }
            }
            .padding(.trailing, 16)
            .padding(.top, 56)
        }
    }

    /// The name, what's on it, and Play and Shuffle.
    private func details(ground: Color) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(album.tapeTitle)
                        .font(.system(size: 30, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    if album.isExplicit { ExplicitBadge() }
                }
                Text(detailsText)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                // The audio it comes in, as Apple Music has it (see LiquidCatalog).
                if let variants = AppleMusicCatalog.shared.details(forAlbum: album)?.variants, !variants.isEmpty {
                    AudioVariantBadges(variants: variants)
                        .padding(.top, 6)
                }
            }
            if let tracks, !tracks.isEmpty {
                HStack(spacing: 10) {
                    Button { onPlay(album, tracks, 0, true) } label: {
                        Label(String(localized: album.isPodcast ? "spool.podcast.playLatest" : "detail.play"),
                              systemImage: "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(ground)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("liquid.album.play")
                    if !album.isPodcast {
                        Button { onPlay(album, tracks.shuffled(), 0, true) } label: {
                            Label(String(localized: "detail.shuffle"), systemImage: "shuffle")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("liquid.album.shuffle")
                    }
                }
            } else if tracks == nil {
                ProgressView().tint(.white).frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Text(String(localized: "spool.jcard.empty")).foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var detailsText: String {
        var parts: [String] = []
        if let byline = album.caseByline { parts.append(byline) }
        if let released = album.releaseLine { parts.append(released) }
        if album.hasAlbumInfo, let genre = album.genre { parts.append(genre) }
        if let tracks, !tracks.isEmpty {
            parts.append(album.tapeFormat.count(tracks.count))
            let minutes = Int(tracks.reduce(0) { $0 + $1.duration } / 60)
            if minutes > 0 { parts.append(String(format: String(localized: "liquid.minutes"), minutes)) }
        }
        return parts.joined(separator: " · ")
    }

    /// The songs. Tapped, one plays from there; swiped right, it offers Play Next and Add
    /// to Queue, as Apple Music's lists do, a full swipe playing it next. Held, the same
    /// in a menu. A show's episodes can't be queued, so they don't swipe.
    @ViewBuilder
    private func trackRows(_ tracks: [AppTrack]) -> some View {
        let playingID = musicService.currentEpisode?.id ?? musicService.currentTrack?.id
        let episodes = album.podcast?.episodesNewestFirst
        ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
            Button { onPlay(album, tracks, index, false) } label: {
                HStack(spacing: 14) {
                    Group {
                        if track.id == playingID {
                            Image(systemName: "waveform").font(.system(size: 12, weight: .bold))
                        } else {
                            Text("\(index + 1)").font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    .frame(width: 26, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        // An episode's marked if played before, or part way through.
                        HStack(spacing: 6) {
                            EpisodeTitle(track.title, episode: episodes.flatMap { $0.indices.contains(index) ? $0[index] : nil })
                                .font(.system(size: 16, weight: track.id == playingID ? .bold : .regular))
                                .lineLimit(2)
                            if track.isExplicit { ExplicitBadge() }
                        }
                        if album.isMixtape {
                            Text(track.artistName).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    Spacer(minLength: 8)
                    if album.isPodcast {
                        // Whether the episode is downloaded, as on every player.
                        EpisodeDownloadMark(episodeID: track.id)
                    }
                    if track.duration > 0 {
                        Text(AppHelpers.formatTime(track.duration))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(QueueMenu(isEnabled: !album.isPodcast, track: track,
                                episode: episodes.flatMap { $0.indices.contains(index) ? $0[index] : nil },
                                onQueue: { onQueue($0, $1, $0.count == 1 ? $0[0].title : album.tapeTitle) },
                                onRemove: PlaylistAdder.shared.removeAction(track, at: index, from: album) { self.tracks?.remove(at: index) }))
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if !album.isPodcast {
                    Button {
                        onQueue([track], .next, track.title)
                    } label: {
                        Label(String(localized: "queue.action.playNext"), systemImage: "text.insert")
                    }
                    .tint(RowSwipeAction.playNextTint)
                    Button {
                        onQueue([track], .last, track.title)
                    } label: {
                        Label(String(localized: "queue.action.addToQueue"), systemImage: "text.append")
                    }
                    .tint(RowSwipeAction.addToQueueTint)
                } else if let episode = episodes.flatMap({ $0.indices.contains(index) ? $0[index] : nil }) {
                    // An episode offers its download, as in every player.
                    ForEach(RowSwipeAction.download(episode)) { action in
                        Button(action: action.action) { Label(action.title, systemImage: action.symbol) }
                            .tint(action.tint)
                    }
                }
            }
            .accessibilityIdentifier("liquid.album.track.\(index)")
            .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(.white.opacity(0.12))
        }
    }
}

// MARK: - Droplet

/// What's playing, docked at the bottom of the library as a drop of its colour, its cover
/// turning like a record while it plays. Tapped, it floods open into Now Playing.
struct LiquidDroplet: View {
    @ObservedObject var musicService: MusicService
    let onOpen: (CGPoint) -> Void

    @State private var color: Color = Color(red: 0.17, green: 0.29, blue: 0.48)
    @State private var frame: CGRect = .zero

    var body: some View {
        if let track = musicService.nowPlayingTrack {
            HStack(spacing: 12) {
                // The cover as a record, turning while it plays.
                // A small record turning slowly: 30 frames a second is smooth enough.
                DiscSpinner(isSpinning: musicService.isPlaying, frameRate: 30) {
                    LiquidCover(source: .track(track))
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                        .overlay {
                            // Grooves, and the spindle hole.
                            Circle().strokeBorder(.black.opacity(0.18), lineWidth: 0.75).padding(8)
                            Circle().strokeBorder(.black.opacity(0.14), lineWidth: 0.75).padding(15)
                            Circle().fill(.black.opacity(0.75)).frame(width: 7, height: 7)
                                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.75))
                        }
                }
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1.5))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(1)
                    Text(track.artistName)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    Task { await musicService.togglePlayPause() }
                } label: {
                    Image(systemName: musicService.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(color.liquidDeep)
                        .frame(width: 50, height: 50)
                        .background(.white, in: Circle())
                }
                .accessibilityLabel(String(localized: musicService.isPlaying ? "spool.pause" : "spool.play"))
                .accessibilityIdentifier("liquid.droplet.playPause")
            }
            .foregroundStyle(.white)
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .frame(height: 70)
            .background(
                Capsule()
                    .fill(LinearGradient(colors: [color, color.liquidDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 1))
                    .shadow(color: .black.opacity(0.55), radius: 16, y: 10)
            )
            .contentShape(Capsule())
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            .onTapGesture { onOpen(CGPoint(x: frame.minX + 36, y: frame.midY)) }
            .gesture(DragGesture(minimumDistance: 10).onEnded { value in
                if value.translation.height < -30 { onOpen(CGPoint(x: frame.minX + 36, y: frame.midY)) }
            })
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: String(localized: "liquid.openNowPlaying")) {
                onOpen(CGPoint(x: frame.midX, y: frame.midY))
            }
            .accessibilityIdentifier("liquid.droplet")
            .task(id: track.albumTitle + track.artistName) {
                let found = await LiquidColors.shared.color(for: track)
                withAnimation(.easeInOut(duration: 0.5)) { color = found }
            }
        }
    }
}

/// Holding a cover offers to queue the whole of it, as holding an album does on every
/// player. A show's episodes aren't queued, so a show has no menu.
struct LiquidAlbumHoldMenu: ViewModifier {
    let album: AppAlbum
    @Environment(\.liquidNavigator) private var navigator

    func body(content: Content) -> some View {
        if album.isPodcast {
            content
        } else {
            content.contextMenu {
                Button { navigator.queueAlbum(album, .next) } label: {
                    Label(String(localized: "queue.action.playNext"), systemImage: "text.insert")
                }
                Button { navigator.queueAlbum(album, .last) } label: {
                    Label(String(localized: "queue.action.addToQueue"), systemImage: "text.append")
                }
                if album.hasAlbumInfo {
                    Button { AlbumInfoCenter.shared.show(album) } label: {
                    Label(String(localized: "albumInfo.action"), systemImage: "info.circle")
                }
                }
            }
        }
    }
}

/// A list's layout, kept under its own name, so each list stays as it was last left: the
/// songs as a list, say, and the albums one at a time.
struct LiquidRememberedLayout<Content: View>: View {
    @AppStorage private var layout: LiquidLayout
    @ViewBuilder let content: (Binding<LiquidLayout>) -> Content

    private let list: String

    /// `list` names the list for its layout; `place`, when given, for the cover its
    /// stack was left on (one artist's albums apart from another's).
    init(_ list: String, place: String? = nil, @ViewBuilder content: @escaping (Binding<LiquidLayout>) -> Content) {
        _layout = AppStorage(wrappedValue: .grid, "LiquidLayout." + list)
        self.list = place ?? list
        self.content = content
    }

    var body: some View {
        content($layout)
            .environment(\.liquidListKey, list)
    }
}
