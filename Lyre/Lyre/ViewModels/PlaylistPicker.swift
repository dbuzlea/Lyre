//
//  PlaylistPicker.swift
//  Lyre
//

import SwiftUI
import UIKit

// MARK: - Playlist Picker
//
// The sheet PlaylistAdder's `pending` song brings up: the listener's own playlists, by
// name. Tapping one adds the song, ticks the row and closes; a failure (no subscription,
// not in Apple Music, offline) is said under the list and the sheet stays.

struct PlaylistPicker: View {
    @ObservedObject var musicService: MusicService
    let item: PlaylistAdder.Item
    @Environment(\.dismiss) private var dismiss

    @State private var adding: String?
    @State private var added: String?
    @State private var failure: String?

    private var playlists: [AppPlaylist] { PlaylistAdder.editable(musicService.playlists) }

    var body: some View {
        NavigationStack {
            List {
                Section {
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
