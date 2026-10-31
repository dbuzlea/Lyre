//
//  AlbumInfoSheet.swift
//  Lyre
//

import SwiftUI
import MusicKit

// MARK: - Album Info Sheet
//
// Everything known about an album (see AlbumInfo), in a sheet over any player: the cover
// and name, Play, the facts (released, genre, length, label, copyright, audio, kind),
// Apple's write-up, the songs with their composers, and other versions and albums like
// it, each of which opens its own info. What Apple Music knows fills in when it arrives;
// without Apple Music access, the library's facts are all there is.

struct AlbumInfoSheet: View {
    @ObservedObject var musicService: MusicService
    let album: AppAlbum

    var body: some View {
        NavigationStack {
            AlbumInfoPage(musicService: musicService, album: album)
                .navigationDestination(for: AppAlbum.self) { other in
                    AlbumInfoPage(musicService: musicService, album: other)
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private struct AlbumInfoPage: View {
    @ObservedObject var musicService: MusicService
    let album: AppAlbum
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var tracks: [AppTrack]?
    @State private var showsAllNotes = false

    private var details: AppleMusicCatalog.AlbumDetails? { AppleMusicCatalog.shared.details(forAlbum: album) }
    private var more: AppleMusicCatalog.AlbumMore? { AppleMusicCatalog.shared.more(forAlbum: album) }

    var body: some View {
        List {
            header
            facts
            if let notes = details?.notes {
                Section(String(localized: "albumInfo.about")) {
                    Text(notes)
                        .font(.callout)
                        .lineLimit(showsAllNotes ? nil : 6)
                        .onTapGesture { withAnimation { showsAllNotes.toggle() } }
                        .accessibilityIdentifier("albumInfo.notes")
                }
            }
            songs
            related(String(localized: "albumInfo.otherVersions"), more?.otherVersions ?? [])
            related(String(localized: "albumInfo.related"), more?.related ?? [])
            if let url = details?.url ?? album.musicKitAlbum?.url {
                Section {
                    Button { openURL(url) } label: {
                        Label(String(localized: "catalog.offer.open"), systemImage: "arrow.up.right.square")
                    }
                }
            }
        }
        .navigationTitle(String(localized: "albumInfo.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "albumInfo.done")) { AlbumInfoCenter.shared.pending = nil; dismiss() }
            }
        }
        .task(id: album.id) {
            // The songs straight away; Apple Music's facts as they come.
            async let catalogue: Void = {
                await AppleMusicCatalog.shared.loadAlbum(album)
                await AppleMusicCatalog.shared.loadMore(forAlbum: album)
            }()
            tracks = await musicService.loadTracks(for: album)
            await catalogue
        }
        .accessibilityIdentifier("albumInfo")
    }

    // MARK: Header

    private var header: some View {
        Section {
            HStack(alignment: .top, spacing: 14) {
                TapeArtwork(album: album, size: 96)
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(album.tapeTitle).font(.headline).lineLimit(3)
                        if album.musicKitAlbum?.contentRating == .explicit { ExplicitMark() }
                    }
                    Text(album.artistName).font(.subheadline).foregroundStyle(.secondary)
                    if let kind {
                        Text(kind).font(.caption).foregroundStyle(.secondary)
                    }
                    Button { play(from: 0) } label: {
                        // Drawn as symbol and word rather than a Label: a Label in a List
                        // takes the list's style, its symbol tinted (blue on the blue
                        // button) in a column of its own, leaving the word off to one
                        // side (LYRE-22).
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                            Text(String(localized: "detail.play"))
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(tracks?.isEmpty != false)
                    .padding(.top, 4)
                    .accessibilityIdentifier("albumInfo.play")
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// Single, EP-length, compilation: what Apple Music says it is.
    private var kind: String? {
        if details?.isSingle == true { return String(localized: "albumInfo.kind.single") }
        if details?.isCompilation == true { return String(localized: "albumInfo.kind.compilation") }
        return nil
    }

    // MARK: Facts

    private var released: Date? { album.releaseDate ?? details?.releaseDate }
    /// The first few: Apple can file an album under a dozen.
    private var genres: [String] {
        if let genres = details?.genres, !genres.isEmpty { return Array(genres.prefix(3)) }
        return album.genre.map { [$0] } ?? []
    }

    private var facts: some View {
        Section {
            if let released {
                fact(String(localized: "albumInfo.released"), AppAlbum.releaseText(released), id: "released")
            }
            if !genres.isEmpty {
                fact(String(localized: "albumInfo.genre"), genres.joined(separator: ", "), id: "genre")
            }
            if let tracks, !tracks.isEmpty {
                let count = album.tapeFormat.count(tracks.count)
                let length = AlbumInfoText.length(tracks.reduce(0) { $0 + $1.duration })
                fact(String(localized: "albumInfo.length"), [count, length].compactMap { $0 }.joined(separator: " · "), id: "length")
            }
            if let label = details?.recordLabel, !label.isEmpty {
                fact(String(localized: "albumInfo.label"), label, id: "label")
            }
            if let variants = details?.variants, !variants.isEmpty {
                fact(String(localized: "albumInfo.audio"),
                     variants.map(AudioVariantBadges.name(of:)).joined(separator: ", "), id: "audio")
            }
            if let copyright = details?.copyright, !copyright.isEmpty {
                fact(String(localized: "albumInfo.copyright"), copyright, id: "copyright")
            }
        }
    }

    private func fact(_ name: String, _ value: String, id: String) -> some View {
        LabeledContent(name) {
            Text(value).multilineTextAlignment(.trailing)
        }
        .accessibilityIdentifier("albumInfo.\(id)")
    }

    // MARK: Songs

    @ViewBuilder
    private var songs: some View {
        if let tracks, !tracks.isEmpty {
            let discs = Set(tracks.compactMap(\.discNumber))
            Section(String(localized: "albumInfo.songs")) {
                ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                    Button { play(from: index) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(number(track, index: index, showsDisc: discs.count > 1))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 26, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title).foregroundStyle(.primary).lineLimit(2)
                                if let composer = track.composer {
                                    Text(composer).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 6)
                            Text(Self.time(track.duration))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    // Rows read as text, not links.
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("albumInfo.song.\(index)")
                }
            }
        } else if tracks == nil {
            Section { ProgressView().frame(maxWidth: .infinity) }
        }
    }

    /// "3", or "2-3" on a second disc where an album has several.
    private func number(_ track: AppTrack, index: Int, showsDisc: Bool) -> String {
        let place = track.trackNumber ?? index + 1
        guard showsDisc, let disc = track.discNumber else { return "\(place)" }
        return "\(disc)-\(place)"
    }

    private static func time(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "" }
        let whole = Int(seconds.rounded())
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    // MARK: More

    @ViewBuilder
    private func related(_ title: String, _ albums: [Album]) -> some View {
        if !albums.isEmpty {
            Section(title) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(albums) { other in
                            let next = mine(other) ?? AppAlbum(from: other, catalog: true)
                            NavigationLink(value: next) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Group {
                                        if let art = other.artwork { ArtworkImage(art, width: 110, height: 110) }
                                        else { Color.secondary.opacity(0.2) }
                                    }
                                    .frame(width: 110, height: 110)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    Text(other.title).font(.caption).lineLimit(2).foregroundStyle(.primary)
                                    if let date = other.releaseDate {
                                        Text(date.formatted(.dateTime.year())).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: 110, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 0))
            }
        }
    }

    /// The library's copy of a catalogue album, so it plays from the library.
    private func mine(_ other: Album) -> AppAlbum? {
        AppleMusicCatalog.libraryAlbum(title: other.title, artist: other.artistName, in: musicService.albums)
    }

    // MARK: Playing

    private func play(from index: Int) {
        guard let tracks, tracks.indices.contains(index) else { return }
        Task { await musicService.play(tracks: tracks, startingAt: index) }
        AlbumInfoCenter.shared.pending = nil
        dismiss()
    }
}

/// The "E" an explicit album is marked with, in the system's colours.
private struct ExplicitMark: View {
    var body: some View {
        Text("E")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color(.systemBackground))
            .frame(width: 15, height: 15)
            .background(Color.secondary, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            .accessibilityLabel(String(localized: "catalog.explicit"))
    }
}

/// Shows Album Info whenever AlbumInfoCenter has an album waiting. `isActive` is false
/// where something else is presented over this view, which shows it instead.
struct AlbumInfoPresenter: ViewModifier {
    @ObservedObject var musicService: MusicService
    var isActive = true

    func body(content: Content) -> some View {
        content.sheet(item: Binding(get: { isActive ? AlbumInfoCenter.shared.pending : nil },
                                    set: { AlbumInfoCenter.shared.pending = $0 })) { album in
            AlbumInfoSheet(musicService: musicService, album: album)
        }
    }
}
