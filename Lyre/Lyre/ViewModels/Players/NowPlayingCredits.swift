//
//  NowPlayingCredits.swift
//  Lyre
//

import SwiftUI

// MARK: - Who and What It's From, as Ways There
//
// Under the song's name in every player's Now Playing: "Artist — Album", each a way to
// them. The artist opens what the player has of theirs (Liquid's artist page; Classic's
// artist screen; the shelf or crate searched for them on Spool, Disc and the Gramophone);
// the album opens its songs (its page, screen, case or sleeve). A show's episode: the
// show's name, opening the show.
//
// Where the words are drawn as part of a thing (Disc's display, the Gramophone's plate in
// 3D), a finger can't pick one word from the other: there, tapping them offers both
// (NowPlayingCreditsMenu).

/// What's playing, for its credits: who, and what it's from.
struct NowPlayingCreditsInfo: Equatable {
    var artist: String
    /// The album's name; nil with none (or for a show's episode, whose show is `artist`).
    var album: String?
    var isShow = false

    init?(track: AppTrack?, episode: PodcastEpisode?) {
        if let episode, track == nil || track?.id == episode.id {
            artist = episode.showTitle
            album = nil
            isShow = true
        } else if let track, !track.artistName.isEmpty || !track.albumTitle.isEmpty {
            artist = track.artistName
            album = track.albumTitle.isEmpty ? nil : TapeFormat.displayTitle(track.albumTitle)
        } else {
            return nil
        }
    }
}

/// "Artist — Album" as two links, in the player's own lettering (`label`).
struct NowPlayingCredits<Label: View>: View {
    let info: NowPlayingCreditsInfo
    /// The player's accessibility prefix: `<prefix>.nowPlaying.artist`, `.album`.
    let idPrefix: String
    let onArtist: () -> Void
    let onAlbum: () -> Void
    /// Room for a finger above and below the words.
    var touchPadding: CGFloat = 6
    @ViewBuilder let label: (String) -> Label

    var body: some View {
        if info.isShow {
            link(info.artist, id: "\(idPrefix).nowPlaying.album", hint: "liquid.openAlbum.hint", action: onAlbum)
        } else if let album = info.album, !info.artist.isEmpty {
            HStack(spacing: 0) {
                link(info.artist, id: "\(idPrefix).nowPlaying.artist", hint: "liquid.openArtist.hint", action: onArtist)
                    .layoutPriority(1)
                label(" — ").accessibilityHidden(true)
                link(album, id: "\(idPrefix).nowPlaying.album", hint: "liquid.openAlbum.hint", action: onAlbum)
            }
        } else if let album = info.album {
            link(album, id: "\(idPrefix).nowPlaying.album", hint: "liquid.openAlbum.hint", action: onAlbum)
        } else {
            link(info.artist, id: "\(idPrefix).nowPlaying.artist", hint: "liquid.openArtist.hint", action: onArtist)
        }
    }

    private func link(_ text: String, id: String, hint: String.LocalizationValue,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label(text)
                .lineLimit(1)
                .padding(.vertical, touchPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(LyrePressStyle(isRow: true))
        .accessibilityHint(String(localized: hint))
        .accessibilityIdentifier(id)
    }
}

/// Where the credits are drawn as part of a thing: tapped, they offer the artist and the
/// album by name, to go to either.
struct NowPlayingCreditsMenu<Label: View>: View {
    let info: NowPlayingCreditsInfo?
    let idPrefix: String
    let onArtist: () -> Void
    let onAlbum: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        if let info {
            Menu {
                if !info.isShow, !info.artist.isEmpty {
                    Button(action: onArtist) { SwiftUI.Label(info.artist, systemImage: "music.mic") }
                        .accessibilityIdentifier("\(idPrefix).nowPlaying.artist")
                }
                if info.isShow || info.album != nil {
                    Button(action: onAlbum) {
                        SwiftUI.Label(info.isShow ? info.artist : info.album ?? "",
                                      systemImage: info.isShow ? "mic" : "square.stack")
                    }
                    .accessibilityIdentifier("\(idPrefix).nowPlaying.album")
                }
            } label: {
                label()
            }
            .accessibilityHint(String(localized: "nowPlaying.credits.hint"))
            .accessibilityIdentifier("\(idPrefix).nowPlaying.credits")
        } else {
            label()
        }
    }
}
