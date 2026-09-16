//
//  MusicArtworkView.swift
//  Lyre
//

import SwiftUI
import MusicKit

// Reusable MusicKit artwork image component. Renders the album art at the requested
// size with rounded corners and a drop shadow, or a grey placeholder with a music-note
// icon when no MusicKit artwork is available.
struct MusicArtworkView: View {
    let artwork: Artwork?
    let size: CGFloat

    init(artwork: Artwork?, size: CGFloat = 120) {
        self.artwork = artwork
        self.size = size
    }

    var body: some View {
        Group {
            if let artwork {
                ArtworkImage(artwork, width: size)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            } else {
                placeholderView
            }
        }
    }

    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(LinearGradient(
                colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.2)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.35))
                    .foregroundStyle(.black.opacity(0.3))
            }
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Helpers

extension TimeInterval {
    var formattedTime: String {
        String(format: "%d:%02d", Int(self) / 60, Int(self) % 60)
    }
}

extension Array where Element == AppTrack {
    var totalDuration: TimeInterval { reduce(0) { $0 + $1.duration } }
}
