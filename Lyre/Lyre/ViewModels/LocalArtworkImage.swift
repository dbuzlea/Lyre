//
//  LocalArtworkImage.swift
//  Lyre
//

import SwiftUI
import MediaPlayer

// MARK: - LocalArtworkCache
//
// On-device artwork (MPMediaItemArtwork) has to be decoded before it can be drawn, and
// `image(at:)` does that synchronously. Called from a view body it decoded on the main
// thread on every redraw — in the carousel that meant every visible cover, repeatedly,
// while dragging. Covers are now decoded once, off the main thread, and kept here.
//
// Apple Music artwork does not come through here: MusicKit's `ArtworkImage` already
// loads and caches asynchronously.

nonisolated final class LocalArtworkCache: @unchecked Sendable {
    static let shared = LocalArtworkCache()

    /// NSCache is thread-safe and drops entries under memory pressure by itself.
    private let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 400
        return cache
    }()

    /// Keyed by owner and size, because the same cover is drawn at several sizes.
    static func key(_ owner: String, size: CGFloat) -> NSString {
        "\(owner)@\(Int(size.rounded()))" as NSString
    }

    func cachedImage(for key: NSString) -> UIImage? {
        images.object(forKey: key)
    }

    /// Decodes `artwork` at `size` and caches it. Runs off the main thread.
    @concurrent
    func image(for artwork: MPMediaItemArtwork, key: NSString, size: CGFloat) async -> UIImage? {
        if let hit = images.object(forKey: key) { return hit }
        guard let image = artwork.image(at: CGSize(width: size, height: size)) else { return nil }
        // `image(at:)` can hand back an image that still decodes lazily on first draw,
        // which would put the work back on the main thread. Force it here instead.
        let decoded = image.preparingForDisplay() ?? image
        images.setObject(decoded, forKey: key)
        return decoded
    }
}

// MARK: - LocalArtworkImage

/// Draws on-device artwork from the cache, decoding it in the background on a miss.
///
/// Shaped like `AsyncImage`: `content` styles the loaded image, and `placeholder` is
/// shown while it loads and when there is no artwork at all.
///
/// `artwork` is an autoclosure because reading `MPMediaItem.artwork` is itself a call
/// into the media library. It is only evaluated on a cache miss.
struct LocalArtworkImage<Content: View, Placeholder: View>: View {
    private let cacheKey: NSString
    private let size: CGFloat
    private let artwork: () -> MPMediaItemArtwork?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder

    /// The image this view loaded, tagged with the key it was loaded for, so a reused
    /// view (the carousel recycles covers across indices) never shows a stale cover.
    @State private var loaded: (key: NSString, image: UIImage)?

    init(
        cacheKey owner: String,
        size: CGFloat,
        artwork: @autoclosure @escaping () -> MPMediaItemArtwork?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.cacheKey = LocalArtworkCache.key(owner, size: size)
        self.size = size
        self.artwork = artwork
        self.content = content
        self.placeholder = placeholder
    }

    private var image: UIImage? {
        if let loaded, loaded.key == cacheKey { return loaded.image }
        return LocalArtworkCache.shared.cachedImage(for: cacheKey)
    }

    var body: some View {
        Group {
            if let image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: cacheKey) {
            guard image == nil, let artwork = artwork() else { return }
            let key = cacheKey
            if let decoded = await LocalArtworkCache.shared.image(for: artwork, key: key, size: size) {
                loaded = (key, decoded)
            }
        }
    }
}
