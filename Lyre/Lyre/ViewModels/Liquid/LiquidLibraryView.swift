//
//  LiquidLibraryView.swift
//  Lyre
//

import SwiftUI

// MARK: - Liquid Library
//
// The way into the music. The first page is a lava lamp (LiquidLavaMenu): a blob of wax
// for each of albums, artists, playlists, podcasts and search, in the colour of what's
// playing, drifting and tilting with the phone. Each opens its page:
//
//   albums, playlists, podcasts   a grid of covers, with search and an A–Z strip
//   artists                       the names in big type; one opens that artist's albums
//   search                        albums, playlists and shows that match, as covers
//   songs, recently played,       the songs, each with its cover, to play from or swipe
//   recently added                right to queue; every song has search and an A–Z strip
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
    case artists
    case artist(String)
    case playlists
    case podcasts
    case search
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
    /// Room kept clear at the bottom for the droplet.
    let bottomInset: CGFloat

    @Environment(\.windowSafeArea) private var safeArea
    @Environment(\.liquidFlood) private var flood

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
        // A cover swung open from a stack, over everything.
        .overlay {
            if let item = fold.item {
                LiquidFoldView(item: item, closedFrame: fold.frame, musicService: musicService) { fold.item = nil }
                    .id(item.id)
            }
        }
        .environment(\.liquidNavigator, navigator)
    }

    private var fold: LiquidFoldState { .shared }

    // MARK: Moving

    /// Pages pushed and popped by flooding: into a page's own colour (an album's cover
    /// colour, the library's ground for the rest), and back into the colour of the page
    /// underneath.
    private var navigator: LiquidNavigator {
        LiquidNavigator(
            push: { route in
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
            }
        )
    }

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
            items: Self.menuItems,
            onChoose: { route, centre, color in
                // The chosen blob's colour floods out from its middle, and the page is there.
                flood(color, from: centre) {
                    path.append(route)
                }
            },
            onOpenSettings: onOpenSettings,
            bottomInset: bottomInset
        )
        .toolbar(.hidden, for: .navigationBar)
    }

    private static var menuItems: [(id: String, title: String, route: LiquidRoute)] {
        [("albums", String(localized: "liquid.menu.albums"), .albums),
         ("artists", String(localized: "liquid.menu.artists"), .artists),
         ("songs", String(localized: "liquid.menu.songs"), .songs),
         ("playlists", String(localized: "liquid.menu.playlists"), .playlists),
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
                               layout: layout, musicService: musicService)
            }
        case .playlists:
            LiquidRememberedLayout("playlists") { layout in
                LiquidGridPage(title: String(localized: "liquid.menu.playlists"), items: library.mixtapes,
                               emptyText: String(localized: "spool.shelf.mixtapes.empty"), bottomInset: bottomInset,
                               layout: layout, musicService: musicService)
            }
        case .podcasts:
            LiquidRememberedLayout("podcasts") { layout in
                LiquidGridPage(title: String(localized: "liquid.menu.podcasts"), items: library.podcasts,
                               emptyText: String(localized: "spool.shelf.podcasts.empty"), bottomInset: bottomInset,
                               layout: layout, musicService: musicService,
                               emptyAction: (String(localized: "spool.shelf.findShows"), onFindShows),
                               searchAction: (String(localized: "spool.shelf.findShows"), "plus.magnifyingglass",
                                              "liquid.podcasts.findShows", onFindShows))
            }
        case .artists:
            LiquidArtistsPage(albums: library.albums, bottomInset: bottomInset)
        case .artist(let name):
            LiquidRememberedLayout("artist", place: "artist." + name) { layout in
                LiquidGridPage(title: name, items: library.albums.filter { $0.artistName == name },
                               emptyText: String(localized: "spool.shelf.empty"), bottomInset: bottomInset,
                               layout: layout, musicService: musicService, showsIndex: false)
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
    /// A button beside the search: Find Shows, on the podcasts page.
    var searchAction: (title: String, symbol: String, id: String, action: () -> Void)?

    @State private var query = ""

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
                LiquidPageTitle(title: title, layout: $layout)
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
                        LiquidPageTitle(title: title, layout: $layout)
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
                        if shown.isEmpty {
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
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                                      spacing: 18) {
                                ForEach(shown) { album in
                                    Button { navigator.push(.album(album)) } label: {
                                        LiquidCoverTile(album: album)
                                    }
                                    .modifier(LiquidAlbumHoldMenu(album: album))
                                    .buttonStyle(.plain)
                                    .id(album.id)
                                    .accessibilityIdentifier("liquid.cover.\(album.id)")
                                }
                            }
                        }
                    }
                    .padding(.leading, 20)
                    .padding(.trailing, showsIndex && shown.count >= 12 ? 40 : 20)
                    .padding(.bottom, bottomInset + 20)
                }
                .scrollDismissesKeyboard(.immediately)

                if showsIndex, shown.count >= 12 {
                    LiquidLetterStrip(titles: shown.map(\.title)) { index in
                        proxy.scrollTo(shown[index].id, anchor: .top)
                    }
                    .padding(.trailing, 6)
                    .padding(.bottom, bottomInset)
                }
            }
        }
        .transition(.opacity)
    }
}

/// A cover in a grid, with its name and artist under it.
struct LiquidCoverTile: View {
    let album: AppAlbum

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LiquidCover(source: .album(album))
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 10, y: 6)
            Text(album.tapeTitle)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
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
    @Environment(\.liquidNavigator) private var navigator

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { navigator.back() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.1), in: Circle())
            }
            .foregroundStyle(.white)
            // Its own button: on a list's first row, a tap elsewhere on the row isn't one.
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "liquid.back"))
            .accessibilityIdentifier("liquid.back")
            HStack(alignment: .center) {
                Text(title.lowercased())
                    .font(.system(size: 44, weight: .medium))
                    .tracking(-1.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let layout {
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

    static func index(_ titles: [String]) -> [LiquidLetterEntry] {
        var seen = Set<String>()
        var result: [LiquidLetterEntry] = []
        for (index, title) in titles.enumerated() {
            let letter = AppHelpers.firstLetter(of: title)
            if seen.insert(letter).inserted { result.append(LiquidLetterEntry(letter: letter, index: index)) }
        }
        return result
    }
}

struct LiquidLetterStrip: View {
    let titles: [String]
    let onJump: (Int) -> Void

    @State private var lastLetter: String?

    /// The first title under each letter: worked out when the titles change, not on
    /// every redraw (a finger along the index redraws it at every letter it crosses).
    @State private var letters: [LiquidLetterEntry] = []

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ForEach(letters, id: \.letter) { entry in
                    Text(entry.letter)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(lastLetter == entry.letter ? 1 : 0.6))
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
                        guard entry.letter != lastLetter else { return }
                        lastLetter = entry.letter
                        UISelectionFeedbackGenerator().selectionChanged()
                        onJump(entry.index)
                    }
                    .onEnded { _ in lastLetter = nil }
            )
        }
        .frame(width: 24)
        .frame(maxHeight: 520)
        .background(.white.opacity(0.07), in: Capsule())
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

    private var artists: [(name: String, count: Int)] {
        Dictionary(grouping: albums, by: \.artistName)
            .map { ($0.key, $0.value.count) }
            .filter { !$0.0.isEmpty }
            .sorted { AppHelpers.sortsBefore($0.0, $1.0) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                LiquidPageTitle(title: String(localized: "liquid.menu.artists"))
                    .padding(.bottom, 12)
                if artists.isEmpty {
                    Text(String(localized: "spool.shelf.empty"))
                        .foregroundStyle(.white.opacity(0.7))
                }
                ForEach(artists, id: \.name) { artist in
                    Button { navigator.push(.artist(artist.name)) } label: {
                        HStack(alignment: .firstTextBaseline) {
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
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(LiquidWordStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, bottomInset + 20)
        }
        .background(LiquidPageGround())
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Search

struct LiquidSearchPage: View {
    @Environment(\.liquidNavigator) private var navigator
    let library: ShelfLibrary
    let bottomInset: CGFloat

    @State private var query = ""
    @State private var matches: ShelfSearchMatches?
    @FocusState private var isFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LiquidPageTitle(title: String(localized: "liquid.menu.search"))
                LiquidSearchField(query: $query, prompt: String(localized: "liquid.search.prompt"))
                    .focused($isFocused)
                if let matches {
                    let sections: [(String, [AppAlbum])] = [
                        (String(localized: "liquid.menu.albums"), matches.albums),
                        (String(localized: "liquid.menu.playlists"), matches.mixtapes),
                        (String(localized: "liquid.menu.podcasts"), matches.podcasts)
                    ].filter { !$0.1.isEmpty }
                    if sections.isEmpty {
                        Text(String(localized: "search.noResults"))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    ForEach(sections, id: \.0) { section in
                        Text(section.0.lowercased())
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(.white)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 18) {
                            ForEach(section.1) { album in
                                Button { navigator.push(.album(album)) } label: { LiquidCoverTile(album: album) }
                                    .modifier(LiquidAlbumHoldMenu(album: album))
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
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
    /// Every song, by name: searchable, with the A–Z strip.
    let isAlphabetical: Bool
    @ObservedObject var musicService: MusicService
    let onPlay: ([AppTrack], Int, Bool, String) -> Void
    let onQueue: ([AppTrack], QueuePlacement, String) -> Void
    let bottomInset: CGFloat
    /// All at once or one at a time, as this list was last left.
    @Binding var layout: LiquidLayout

    @State private var query = ""

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
                if isAlphabetical {
                    LiquidSearchField(query: $query, prompt: String(format: String(localized: "liquid.search.in"), title))
                }
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
                        if isAlphabetical {
                            LiquidSearchField(query: $query, prompt: String(format: String(localized: "liquid.search.in"), title))
                        }
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
                    LiquidLetterStrip(titles: shown.map(\.title)) { index in
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
                    Text(track.title)
                        .font(.system(size: 16, weight: isPlaying ? .bold : .regular))
                        .lineLimit(1)
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

            Color.clear
                .frame(height: bottomInset + 24)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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
        }
    }

    /// The cover across the top, melting into the page's colour, with the way back.
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
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.3), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .padding(.leading, 16)
            .padding(.top, 56)
            .accessibilityLabel(String(localized: "liquid.back"))
            .accessibilityIdentifier("liquid.back")
        }
    }

    /// The name, what's on it, and Play and Shuffle.
    private func details(ground: Color) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(album.tapeTitle)
                    .font(.system(size: 30, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text(detailsText)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
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
                        Text(track.title)
                            .font(.system(size: 16, weight: track.id == playingID ? .bold : .regular))
                            .lineLimit(2)
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
                                onQueue: { onQueue($0, $1, $0.count == 1 ? $0[0].title : album.tapeTitle) }))
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
