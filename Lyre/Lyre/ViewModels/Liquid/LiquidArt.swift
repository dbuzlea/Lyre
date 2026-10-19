//
//  LiquidArt.swift
//  Lyre
//

import SwiftUI
import UIKit
import MusicKit

// MARK: - Liquid Art
//
// The Liquid player is dressed in its music: every surface takes the colour of the cover
// it belongs to. `LiquidColors` finds a cover's colour, once, and keeps it: Apple Music's
// own extracted background colour when there is one, or else the cover shrunk to a single
// pixel. `LiquidCover` draws a cover filling whatever space it's given.

@MainActor
final class LiquidColors {
    static let shared = LiquidColors()

    private var cache: [String: Color] = [:]

    /// A cover's colour, if it's been found already.
    func cached(_ key: String) -> Color? { cache[key] }

    func color(for track: AppTrack) async -> Color {
        let key = "track:" + track.albumTitle + "|" + track.artistName
        if let color = cache[key] { return color }
        let found: Color
        if let background = track.musicKitSong?.artwork?.backgroundColor ?? track.musicKitTrack?.artwork?.backgroundColor {
            found = Color(cgColor: background)
        } else if let image = await RecordLabelArt.image(for: track, size: 48), let average = Self.average(of: image) {
            found = average
        } else {
            found = Self.fallback(for: track.albumTitle.isEmpty ? track.title : track.albumTitle)
        }
        cache[key] = found
        return found
    }

    func color(for album: AppAlbum) async -> Color {
        let key = "album:" + album.id
        if let color = cache[key] { return color }
        let found: Color
        if let background = album.musicKitAlbum?.artwork?.backgroundColor ?? album.mixtape?.musicKitPlaylist?.artwork?.backgroundColor {
            found = Color(cgColor: background)
        } else if let image = await RecordLabelArt.image(for: .album(album), size: 48), let average = Self.average(of: image) {
            found = average
        } else {
            found = Self.fallback(for: album.title)
        }
        cache[key] = found
        return found
    }

    /// The average colour of an image: the image drawn into a single pixel.
    private static func average(of image: UIImage) -> Color? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let pixel = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        guard let cgImage = pixel.cgImage, let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data), CFDataGetLength(data) >= 3 else { return nil }
        // BGRA or RGBA: read by the image's own byte order.
        let isBGR = cgImage.bitmapInfo.contains(.byteOrder32Little)
        let r = Double(bytes[isBGR ? 2 : 0]) / 255
        let g = Double(bytes[1]) / 255
        let b = Double(bytes[isBGR ? 0 : 2]) / 255
        return Color(red: r, green: g, blue: b)
    }

    /// A colour of its own for a cover with no picture: a hue from its name.
    static func fallback(for name: String) -> Color {
        let hash = name.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.45, brightness: 0.5)
    }
}

extension Color {
    /// The colour made deep enough for white type to sit on: the Liquid player's grounds.
    var liquidDeep: Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        return Color(hue: Double(h), saturation: Double(min(max(s, 0.25), 0.85)), brightness: Double(min(b, 0.32)))
    }

    /// Whether the colour is light enough to need dark type on it.
    var liquidIsLight: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return false }
        return 0.299 * r + 0.587 * g + 0.114 * b > 0.62
    }
}

/// A cover filling the space it's given, cropped to fit: a song's, an album's or a show's.
struct LiquidCover: View {
    enum Source {
        case track(AppTrack)
        case album(AppAlbum)
    }

    let source: Source

    var body: some View {
        GeometryReader { geometry in
            let side = max(geometry.size.width, geometry.size.height).rounded()
            Group {
                if let artwork = musicKitArtwork {
                    // Apple Music's covers aren't all square: drawn wide enough to fill
                    // the space either way, then cropped, so none sits in a frame of
                    // empty space.
                    let ratio = artworkAspect(artwork)
                    let width = (side * max(1, ratio)).rounded()
                    ArtworkImage(artwork, width: width)
                        .frame(width: width, height: width / ratio)
                } else {
                    switch source {
                case .track(let track): TrackArtwork(track: track, size: side)
                case .album(let album):
                    if album.isMixtape {
                        MixtapeArtwork(album: album, size: side)
                    } else {
                        TapeArtwork(album: album, size: side)
                    }
                }
                }
            }
            .frame(width: side, height: side)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
    }

    /// The Apple Music cover, when there is one (a playlist's own, not a mixtape's
    /// collage).
    private var musicKitArtwork: Artwork? {
        switch source {
        case .track(let track):
            return track.musicKitSong?.artwork ?? track.musicKitTrack?.artwork
        case .album(let album):
            guard album.podcast == nil else { return nil }
            if album.isMixtape { return nil }
            return album.musicKitAlbum?.artwork
        }
    }

    /// Width over height, for a cover that says; square otherwise.
    private func artworkAspect(_ artwork: Artwork) -> CGFloat {
        guard artwork.maximumWidth > 0, artwork.maximumHeight > 0 else { return 1 }
        return CGFloat(artwork.maximumWidth) / CGFloat(artwork.maximumHeight)
    }
}
