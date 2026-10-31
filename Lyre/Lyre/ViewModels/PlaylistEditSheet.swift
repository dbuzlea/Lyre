//
//  PlaylistEditSheet.swift
//  Lyre
//

import SwiftUI
import MusicKit

// MARK: - Edit Playlist
//
// Edits one of the playlists Lyre made (LYRE-25), as the Music app edits a playlist:
// its name, its songs dragged into another order or taken out, and songs added from
// the library or Apple Music (a song the playlist has already isn't added again). Done
// saves it all at once, through MusicKit, so the Music app has it too; Cancel leaves the
// playlist as it was. Every player offers it on a playlist Lyre made (PlaylistEditButton;
// Classic as a row at the top of the playlist), and the app's root shows the sheet
// (PlaylistEditPresenter). Apple lets an app change only the playlists it made, and no
// app a playlist's artwork, so neither is offered.

@MainActor
@Observable
final class PlaylistEditCenter {
    static let shared = PlaylistEditCenter()

    /// The playlist being edited.
    var editing: AppPlaylist?
    /// Counts the edits saved: a list showing a playlist loads its songs again when it
    /// changes, so it shows the playlist as it now is.
    private(set) var revision = 0

    func edit(_ playlist: AppPlaylist) { editing = playlist }

    func didSave() { revision += 1 }
}

/// Shows the sheet whenever PlaylistEditCenter has a playlist to edit.
struct PlaylistEditPresenter: ViewModifier {
    @ObservedObject var musicService: MusicService

    func body(content: Content) -> some View {
        content.sheet(item: Binding(get: { PlaylistEditCenter.shared.editing },
                                    set: { PlaylistEditCenter.shared.editing = $0 })) { playlist in
            PlaylistEditSheet(playlist: playlist, musicService: musicService)
        }
    }
}

/// A player's Edit button, drawn in its own style (`label`): only on a playlist Lyre made.
struct PlaylistEditButton<Label: View>: View {
    let playlist: AppPlaylist?
    let identifier: String
    @ViewBuilder let label: () -> Label

    var body: some View {
        if let playlist, PlaylistAdder.shared.canEdit(playlist) {
            Button { PlaylistEditCenter.shared.edit(playlist) } label: { label() }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "playlist.edit.action"))
                .accessibilityIdentifier(identifier)
        }
    }
}

struct PlaylistEditSheet: View {
    let playlist: AppPlaylist
    @ObservedObject var musicService: MusicService
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var tracks: [AppTrack]?
    @State private var query = ""
    @State private var results: [AppTrack] = []
    @State private var isSaving = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section(String(localized: "playlist.edit.name")) {
                    TextField(String(localized: "playlist.new.placeholder"), text: $name)
                        .accessibilityIdentifier("playlist.edit.name")
                }
                Section(String(localized: "playlist.edit.songs")) {
                    if let tracks {
                        if tracks.isEmpty {
                            Text(String(localized: "empty.tracks")).foregroundStyle(.secondary)
                        }
                        // By place, not id: a playlist can carry the same song twice.
                        ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                            row(track)
                                .accessibilityIdentifier("playlist.edit.song.\(index)")
                        }
                        .onMove { self.tracks?.move(fromOffsets: $0, toOffset: $1) }
                        .onDelete { self.tracks?.remove(atOffsets: $0) }
                    } else {
                        ProgressView()
                    }
                }
                Section(String(localized: "playlist.edit.add")) {
                    TextField(String(localized: "playlist.edit.search"), text: $query)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("playlist.edit.search")
                    ForEach(Array(results.enumerated()), id: \.offset) { index, track in
                        Button { add(track) } label: {
                            HStack {
                                row(track)
                                Spacer(minLength: 8)
                                Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(format: String(localized: "playlist.edit.addSong"), track.title))
                        .accessibilityIdentifier("playlist.edit.result.\(index)")
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(String(localized: "playlist.edit.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "catalog.offer.cancel")) { dismiss() }
                        .accessibilityIdentifier("playlist.edit.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(String(localized: "playlist.edit.done")) { save() }
                            .disabled(tracks == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("playlist.edit.done")
                    }
                }
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button(String(localized: "albumInfo.done"), role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(isSaving)
        .task {
            name = playlist.name
            tracks = await musicService.loadTracks(for: playlist)
        }
        .task(id: query) { await search() }
    }

    private func row(_ track: AppTrack) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(track.title).lineLimit(1)
                if track.isExplicit { ExplicitTag() }
            }
            Text(track.artistName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    // MARK: Adding

    /// The library's songs that match, then Apple Music's the library hasn't, as typing
    /// pauses. The library's are looked through off the main thread.
    private func search() async {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { results = []; return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        let songs = musicService.songs
        let library = await Task.detached(priority: .userInitiated) {
            Array(songs.lazy.filter { song in
                let text = (song.title + " " + song.artistName).lowercased()
                return words.allSatisfy { text.contains($0) }
            }.prefix(15))
        }.value
        guard !Task.isCancelled else { return }
        results = library
        let catalog = await AppleMusicCatalog.shared.search(query)?.songs ?? []
        guard !Task.isCancelled else { return }
        let streamed = catalog
            .filter { song in
                AppleMusicCatalog.librarySong(title: song.title, artist: song.artistName, duration: song.duration,
                                              explicit: song.contentRating.map { $0 == .explicit }, in: musicService) == nil
            }
            .map { AppTrack(from: $0, catalog: true) }
        results = library + streamed
    }

    /// Puts a song at the end, unless the playlist has it already.
    private func add(_ track: AppTrack) {
        guard var tracks else { return }
        if PlaylistAdder.isDuplicate(PlaylistAdder.entry(track), among: tracks.map(PlaylistAdder.entry)) {
            message = String(format: String(localized: "playlist.add.duplicate"), track.title, name)
            return
        }
        tracks.append(track)
        self.tracks = tracks
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: Saving

    private func save() {
        guard let tracks else { return }
        isSaving = true
        Task {
            do {
                let saved = try await PlaylistAdder.shared.save(playlist, name: name, tracks: tracks)
                musicService.replacePlaylist(saved)
                PlaylistEditCenter.shared.didSave()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } catch {
                isSaving = false
                message = error.localizedDescription
            }
        }
    }
}
