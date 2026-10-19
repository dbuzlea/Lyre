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
    /// A streamed show's cover as downloaded, so each size it's drawn at (a tile, an
    /// open case, the droplet) is cut from one download rather than fetching it again.
    private let downloads: NSCache<NSURL, NSData> = {
        let cache = NSCache<NSURL, NSData>()
        cache.totalCostLimit = 40 * 1024 * 1024
        return cache
    }()
    /// Downloads under way, so covers asked for together share one.
    private var inFlight: [URL: Task<Data?, Never>] = [:]
    private let lock = NSLock()

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

    /// Downloads artwork for a streamed podcast, scales it to `size` and caches it.
    @concurrent
    func image(from url: URL, key: NSString, size: CGFloat) async -> UIImage? {
        if let hit = images.object(forKey: key) { return hit }
        guard let data = await data(from: url), let image = UIImage(data: data) else { return nil }
        // Feed artwork is often 3000pt square; keep only what the screen can show.
        let pixels = size * 3
        let target = image.size.width > pixels ? CGSize(width: pixels, height: pixels * image.size.height / image.size.width) : image.size
        let decoded = await image.byPreparingThumbnail(ofSize: target) ?? image
        images.setObject(decoded, forKey: key)
        return decoded
    }

    /// A cover's bytes: kept from an earlier download, joined to one under way, or
    /// downloaded now.
    @concurrent
    private func data(from url: URL) async -> Data? {
        if let kept = downloads.object(forKey: url as NSURL) { return kept as Data }
        let task: Task<Data?, Never> = lock.withLock {
            if let running = inFlight[url] { return running }
            let task = Task<Data?, Never> { try? await URLSession.shared.data(from: url).0 }
            inFlight[url] = task
            return task
        }
        let data = await task.value
        lock.withLock { inFlight[url] = nil }
        if let data { downloads.setObject(data as NSData, forKey: url as NSURL, cost: data.count) }
        return data
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
    /// Downloaded when there is no on-device artwork — a streamed podcast's cover.
    private let remoteURL: URL?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder

    /// The image this view loaded, tagged with the key it was loaded for, so a reused
    /// view (the carousel recycles covers across indices) never shows a stale cover.
    @State private var loaded: (key: NSString, image: UIImage)?

    init(
        cacheKey owner: String,
        size: CGFloat,
        artwork: @autoclosure @escaping () -> MPMediaItemArtwork?,
        remoteURL: URL? = nil,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.cacheKey = LocalArtworkCache.key(owner, size: size)
        self.size = size
        self.artwork = artwork
        self.remoteURL = remoteURL
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
            guard image == nil else { return }
            let key = cacheKey
            let decoded: UIImage?
            if let artwork = artwork() {
                decoded = await LocalArtworkCache.shared.image(for: artwork, key: key, size: size)
            } else if let remoteURL {
                decoded = await LocalArtworkCache.shared.image(from: remoteURL, key: key, size: size)
            } else {
                return
            }
            if let decoded { loaded = (key, decoded) }
        }
    }
}
