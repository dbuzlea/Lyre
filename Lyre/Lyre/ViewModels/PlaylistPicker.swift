//
//  PlaylistPicker.swift
//  Lyre
//

import SwiftUI
import UIKit

// MARK: - Playlist Picker
//
// The sheet PlaylistAdder's `pending` song brings up: the listener's own playlists, the
// last edited first, then by name (LYRE-26). Tapping one adds the song, ticks the row and
// closes; a failure (no subscription, not in Apple Music, offline) is said under the list
// and the sheet stays.

struct PlaylistPicker: View {
    @ObservedObject var musicService: MusicService
    let item: PlaylistAdder.Item
    @Environment(\.dismiss) private var dismiss

    @State private var adding: String?
    @State private var added: String?
    @State private var failure: String?
    @State private var isNaming = false
    @State private var newName = ""

    /// The playlists, the last edited first (LYRE-26): put in order once, as the sheet
    /// opens, not on every redraw.
    @State private var playlists: [AppPlaylist] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // A playlist of its own, the song going in as it's made.
                    Button { newName = ""; isNaming = true } label: {
                        Label(String(localized: "playlist.new.action"), systemImage: "plus")
                    }
                    .disabled(adding != nil || added != nil)
                    .accessibilityIdentifier("playlist.new")
                    if playlists.isEmpty {
                        Text(String(localized: "playlist.add.none"))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(playlists) { playlist in
                        Button { add(to: playlist) } label: {
                            HStack {
                                Text(playlist.name).foregroundStyle(.primary)
                                Spacer()
                                if added == playlist.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                } else if adding == playlist.id {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(adding != nil || added != nil)
                        .accessibilityIdentifier("playlist.add.\(playlist.name)")
                    }
                } footer: {
                    if let failure {
                        Text(failure).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(String(localized: "playlist.add.title"))
            .onAppear {
                playlists = PlaylistAdder.editable(musicService.playlists, edited: PlaylistAdder.shared.edited)
            }
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                Text(item.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "catalog.offer.cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .alert(String(localized: "playlist.new.title"), isPresented: $isNaming) {
            TextField(String(localized: "playlist.new.placeholder"), text: $newName)
            Button(String(localized: "catalog.offer.cancel"), role: .cancel) {}
            Button(String(localized: "playlist.new.create")) { create() }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    /// Makes the playlist with the song in it, ticks it and closes.
    private func create() {
        let name = newName
        adding = "new"
        failure = nil
        Task {
            do {
                let made = try await PlaylistAdder.shared.createPlaylist(named: name, adding: item, in: musicService)
                adding = nil
                added = made.id
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                try? await Task.sleep(for: .milliseconds(700))
                dismiss()
            } catch {
                adding = nil
                failure = error.localizedDescription
            }
        }
    }

    private func add(to playlist: AppPlaylist) {
        adding = playlist.id
        failure = nil
        Task {
            do {
                try await PlaylistAdder.shared.add(item, to: playlist)
                adding = nil
                added = playlist.id
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                try? await Task.sleep(for: .milliseconds(700))
                dismiss()
            } catch {
                adding = nil
                failure = error.localizedDescription
            }
        }
    }
}

/// Shows the picker whenever PlaylistAdder has a song waiting.
struct PlaylistPickerPresenter: ViewModifier {
    @ObservedObject var musicService: MusicService

    func body(content: Content) -> some View {
        content.sheet(item: Binding(get: { PlaylistAdder.shared.pending },
                                    set: { PlaylistAdder.shared.pending = $0 })) { item in
            PlaylistPicker(musicService: musicService, item: item)
        }
    }
}

/// Names a new, empty playlist when a player's New Playlist button asks
/// (PlaylistAdder.isNamingNewPlaylist), and says how it went.
struct NewPlaylistPrompt: ViewModifier {
    @ObservedObject var musicService: MusicService
    var isActive = true
    @State private var name = ""
    @State private var outcome: String?

    func body(content: Content) -> some View {
        content
            .alert(String(localized: "playlist.new.title"),
                   isPresented: Binding(get: { isActive && PlaylistAdder.shared.isNamingNewPlaylist },
                                        set: { PlaylistAdder.shared.isNamingNewPlaylist = $0 })) {
                TextField(String(localized: "playlist.new.placeholder"), text: $name)
                Button(String(localized: "catalog.offer.cancel"), role: .cancel) { name = "" }
                Button(String(localized: "playlist.new.create")) { create() }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .alert(outcome ?? "", isPresented: Binding(get: { isActive && outcome != nil }, set: { if !$0 { outcome = nil } })) {
                Button(String(localized: "albumInfo.done"), role: .cancel) {}
            }
            // A song a playlist wouldn't let go of (PlaylistAdder.remove), and why.
            .alert(PlaylistAdder.shared.removalFailure ?? "",
                   isPresented: Binding(get: { isActive && PlaylistAdder.shared.removalFailure != nil },
                                        set: { if !$0 { PlaylistAdder.shared.removalFailure = nil } })) {
                Button(String(localized: "albumInfo.done"), role: .cancel) {}
            }
    }

    private func create() {
        let name = self.name
        self.name = ""
        Task {
            do {
                let made = try await PlaylistAdder.shared.createPlaylist(named: name, in: musicService)
                outcome = String(format: String(localized: "playlist.new.made"), made.name)
            } catch {
                outcome = error.localizedDescription
            }
        }
    }
}
