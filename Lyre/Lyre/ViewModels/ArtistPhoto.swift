//
//  ArtistPhoto.swift
//  Lyre
//

import SwiftUI
import MusicKit

// MARK: - Artist Photo
//
// An artist's picture as a rounded square: their photo from Apple Music (ArtistPhotos),
// or until there is one, or where there's none, the cover of one of their albums, or,
// with no album either, their initial on a soft tint. Asks for the photo when it comes
// into view.

struct ArtistPhoto: View {
    let name: String
    /// One of their albums, whose cover stands in.
    var fallback: AppAlbum?
    let size: CGFloat

    static func cornerRadius(for size: CGFloat) -> CGFloat { size * 0.22 }

    var body: some View {
        ZStack {
            if let artwork = ArtistPhotos.shared.artwork(for: name) {
                ArtworkImage(artwork, width: size, height: size)
                    .transition(.opacity)
            } else if let fallback {
                LiquidCover(source: .album(fallback))
            } else {
                initial
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius(for: size), style: .continuous))
        .animation(.easeInOut(duration: 0.3), value: ArtistPhotos.shared.artwork(for: name) != nil)
        .task(id: name) { ArtistPhotos.shared.lookUp(name) }
        .accessibilityHidden(true)
    }

    private var initial: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.32), Color(white: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(String(name.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)).prefix(1)).uppercased())
                .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}
