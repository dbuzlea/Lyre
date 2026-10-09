//
//  GramophoneTextures.swift
//  Lyre
//

import MediaPlayer
import MusicKit
import SwiftUI
import UIKit

// MARK: - Gramophone Textures
//
// The pictures the 3D machine is dressed in, painted when it's built:
//
//   woodGrain     a finish's wood, with its grain
//   room          the room's light, which the brass and the record's shine reflect
//   plate         the card in the front plate, with the song playing
//   escutcheons   the brass plates behind the play switch and the speed knob
//   record        a record's face: its grooves in bands, and its label

enum GramophoneTextures {

    /// A finish's wood: the grain running across in fine wavy lines, darker and
    /// lighter, the same each time for the same seed.
    static func woodGrain(_ theme: GramophoneTheme, seed: UInt64, size: CGFloat = 512) -> UIImage {
        var random = SeededRandom(seed: seed)
        let base = UIColor(theme.wood), dark = UIColor(theme.woodDark), light = UIColor(theme.woodLight)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { context in
            let cg = context.cgContext
            base.setFill()
            cg.fill(CGRect(x: 0, y: 0, width: size, height: size))
            // Broad bands of lighter and darker wood.
            for _ in 0..<14 {
                let y = random.next(in: 0...size), height = random.next(in: 10...60)
                (random.next(in: 0...1) > 0.5 ? light : dark).withAlphaComponent(random.next(in: 0.08...0.2)).setFill()
                cg.fill(CGRect(x: 0, y: y, width: size, height: height))
            }
            // The grain: long wavy lines.
            for line in 0..<170 {
                let y0 = random.next(in: -20...(size + 20))
                let amplitude = random.next(in: 1...7)
                let frequency = random.next(in: 0.004...0.02)
                let phase = random.next(in: 0...(2 * .pi))
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 0, y: y0 + sin(phase) * amplitude))
                for x in stride(from: CGFloat(8), through: size, by: 8) {
                    path.addLine(to: CGPoint(x: x, y: y0 + sin(x * frequency + phase) * amplitude))
                }
                let isDark = line % 5 != 0
                (isDark ? dark : light).withAlphaComponent(random.next(in: isDark ? 0.1...0.35 : 0.06...0.16)).setStroke()
                path.lineWidth = random.next(in: 0.5...2.6)
                path.stroke()
            }
        }
    }

    /// The room's light, as a panorama: a warm glow overhead, two lamps catching the
    /// brass, and the dark floor below.
    static func room(size: CGSize = CGSize(width: 512, height: 256)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let colors = [UIColor(red: 0.24, green: 0.2, blue: 0.16, alpha: 1),
                          UIColor(red: 0.22, green: 0.16, blue: 0.12, alpha: 1),
                          UIColor(red: 0.08, green: 0.06, blue: 0.05, alpha: 1),
                          UIColor(red: 0.03, green: 0.02, blue: 0.02, alpha: 1)]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: colors.map(\.cgColor) as CFArray, locations: [0, 0.35, 0.55, 1])!
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            // The lamps: soft bright patches, front-left and behind to the right.
            for (x, y, w) in [(0.12, 0.3, 0.12), (0.62, 0.26, 0.09), (0.86, 0.38, 0.05)] as [(CGFloat, CGFloat, CGFloat)] {
                let rect = CGRect(x: size.width * (x - w / 2), y: size.height * (y - w / 2),
                                  width: size.width * w, height: size.height * w * 1.4)
                let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [UIColor(white: 1, alpha: 0.8).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray,
                                      locations: [0, 1])!
                cg.drawRadialGradient(glow, startCenter: CGPoint(x: rect.midX, y: rect.midY), startRadius: 0,
                                      endCenter: CGPoint(x: rect.midX, y: rect.midY), endRadius: rect.width,
                                      options: [])
            }
        }
    }

    /// The card in the front plate, with the song playing on it.
    static func plate(title: String, subtitle: String, theme: GramophoneTheme) -> UIImage? {
        render(GramophonePlateFace(title: title, subtitle: subtitle, theme: theme), scale: 2)
    }

    /// The plate behind the play switch, marked STOP and START.
    static func switchPlate(theme: GramophoneTheme) -> UIImage? {
        render(GramophoneEscutcheon(theme: theme, kind: .playSwitch), scale: 2)
    }

    /// The plate behind the speed knob, with its marks.
    static func speedPlate(theme: GramophoneTheme) -> UIImage? {
        render(GramophoneEscutcheon(theme: theme, kind: .speed), scale: 2)
    }

    /// A record's face: its grooves in bands, one per song, and its label, with the
    /// label's picture when there is one.
    static func record(_ record: RecordOnPlatter, labelImage: UIImage?) -> UIImage? {
        // On black, so nothing shows through round the edge of the disc.
        render(RecordDisc(kind: record.kind, title: record.title, label: record.label,
                          grooves: record.grooves, diameter: 1024, still: .init(image: labelImage))
                .background(Color(white: 0.05)), scale: 1)
    }

    private static func render(_ view: some View, scale: CGFloat) -> UIImage? {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
        renderer.scale = scale
        return renderer.uiImage
    }
}

/// The card in the front plate: the maker's name over the song playing, as printed and
/// slipped into the frame.
private struct GramophonePlateFace: View {
    let title: String
    let subtitle: String
    let theme: GramophoneTheme

    var body: some View {
        VStack(spacing: 6) {
            Text(String(localized: "gramophone.brand").uppercased())
                .font(.system(size: 20, weight: .heavy, design: .serif))
                .tracking(9)
                .foregroundStyle(theme.plateInk.opacity(0.85))
            Rectangle().fill(theme.plateInk.opacity(0.4)).frame(width: 300, height: 1.5)
            Text(title)
                .font(.system(size: 40, weight: .semibold, design: .serif))
                .foregroundStyle(SpoolPalette.labelInk)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
            Text(subtitle)
                .font(.system(size: 26, design: .serif))
                .italic()
                .foregroundStyle(SpoolPalette.labelInk.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding(.horizontal, 28)
        .frame(width: 520, height: 200)
        .background(
            LinearGradient(colors: [theme.paper, theme.paper.opacity(0.92)], startPoint: .top, endPoint: .bottom)
        )
        .overlay(Rectangle().strokeBorder(theme.plateInk.opacity(0.25), lineWidth: 3).padding(8))
    }
}

/// The brass plates behind the controls, engraved.
private struct GramophoneEscutcheon: View {
    enum Kind { case playSwitch, speed }
    let theme: GramophoneTheme
    let kind: Kind

    var body: some View {
        ZStack {
            LinearGradient(colors: [theme.metalLight, theme.metal, theme.metalDark],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            switch kind {
            case .playSwitch:
                VStack {
                    HStack {
                        Text(String(localized: "gramophone.brake.stop"))
                        Spacer()
                        Text(String(localized: "gramophone.brake.start"))
                    }
                    .font(.system(size: 26, weight: .heavy, design: .serif))
                    .padding(.horizontal, 22)
                    .padding(.top, 20)
                    Spacer()
                }
            case .speed:
                // Marks around the knob, and the name over them.
                ZStack {
                    ForEach(0..<9) { mark in
                        Capsule()
                            .frame(width: 5, height: mark % 4 == 0 ? 26 : 16)
                            .offset(y: -92)
                            .rotationEffect(.degrees(Double(mark - 4) * 22))
                    }
                    Text(String(localized: "gramophone.speed").uppercased())
                        .font(.system(size: 22, weight: .heavy, design: .serif))
                        .tracking(4)
                        .offset(y: 82)
                }
            }
        }
        .foregroundStyle(theme.plateInk.opacity(0.8))
        .frame(width: 256, height: 256)
    }
}

/// Random numbers that come out the same for the same seed, so the grain does.
nonisolated struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(in range: ClosedRange<CGFloat>) -> CGFloat {
        let unit = CGFloat(next() >> 11) / CGFloat(1 << 53)
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }
}

// MARK: - Label Art

/// A record's picture for the 3D machine, which paints it once rather than drawing it
/// live: the album's cover, the song's, or the show's, when one can be had. For the
/// record playing, the player's own artwork comes first.
enum RecordLabelArt {
    static func image(for label: RecordLabel, size: CGFloat = 340) async -> UIImage? {
        switch label {
        case .album(let album):
            if let show = album.podcast {
                let key = LocalArtworkCache.key(show.artworkCacheKey, size: size)
                if let artwork = show.artwork { return await LocalArtworkCache.shared.image(for: artwork, key: key, size: size) }
                if let url = show.artworkURL { return await LocalArtworkCache.shared.image(from: url, key: key, size: size) }
                return nil
            }
            if let artwork = album.mpArtwork {
                return await LocalArtworkCache.shared.image(for: artwork, key: LocalArtworkCache.key(album.id, size: size), size: size)
            }
            if let artwork = album.musicKitAlbum?.artwork ?? album.mixtape?.musicKitPlaylist?.artwork,
               let image = await download(artwork.url(width: Int(size), height: Int(size)), key: album.id, size: size) {
                return image
            }
            // A playlist's name isn't an album's: with no art of its own, its label is
            // written on instead.
            guard !album.isMixtape else { return nil }
            return await library(albumTitle: album.title, size: size)
        case .track(let track):
            return await image(for: track, size: size)
        case .plain:
            return nil
        }
    }

    static func image(for track: AppTrack, size: CGFloat = 340) async -> UIImage? {
        if let artwork = track.mpItem?.artwork {
            return await LocalArtworkCache.shared.image(for: artwork, key: LocalArtworkCache.key(track.id, size: size), size: size)
        }
        if let artwork = track.musicKitSong?.artwork ?? track.musicKitTrack?.artwork,
           let image = await download(artwork.url(width: Int(size), height: Int(size)), key: track.id, size: size) {
            return image
        }
        return await library(albumTitle: track.albumTitle, size: size)
    }

    /// The player's artwork for what's playing.
    static func image(for artwork: MPMediaItemArtwork, id: UInt64, size: CGFloat = 340) async -> UIImage? {
        await LocalArtworkCache.shared.image(for: artwork, key: LocalArtworkCache.key("mp.\(id)", size: size), size: size)
    }

    /// Apple Music's covers come from the web; a library cover's address can't be
    /// fetched, so those are found in the media library instead.
    private static func download(_ url: URL?, key: String, size: CGFloat) async -> UIImage? {
        guard let url, url.scheme == "https" || url.scheme == "http" else { return nil }
        return await LocalArtworkCache.shared.image(from: url, key: LocalArtworkCache.key("label.\(key)", size: size), size: size)
    }

    /// The cover of an album in the media library, found by its title.
    private static func library(albumTitle: String, size: CGFloat) async -> UIImage? {
        guard !albumTitle.isEmpty, MPMediaLibrary.authorizationStatus() == .authorized else { return nil }
        let key = LocalArtworkCache.key("library.\(albumTitle)", size: size)
        if let hit = LocalArtworkCache.shared.cachedImage(for: key) { return hit }
        let query = MPMediaQuery.albums()
        query.addFilterPredicate(MPMediaPropertyPredicate(value: albumTitle, forProperty: MPMediaItemPropertyAlbumTitle))
        guard let artwork = query.items?.lazy.compactMap(\.artwork).first else { return nil }
        return await LocalArtworkCache.shared.image(for: artwork, key: key, size: size)
    }
}
