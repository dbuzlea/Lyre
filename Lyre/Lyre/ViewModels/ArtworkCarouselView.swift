//
//  ArtworkCarouselView.swift
//  Lyre
//
//  Created by Daniel Buzlea on 5/14/26.
//

import SwiftUI
import MusicKit
import MediaPlayer

// MARK: - Artwork Carousel
//
// Full-screen landscape browser showing cover art in a perspective carousel, activated
// when the device rotates to landscape orientation. Inspired by the Lyre classic's
// Artwork Carousel feature. Supports albums, playlists, and podcast shows.
//
// Architecture:
// • `position` is a continuous CGFloat (not an Int) so drag deltas accumulate into
//   smooth sub-item scrolling rather than discrete jumps.
// • A momentum physics loop (startMomentum) runs on @MainActor, decaying velocity by
//   a fixed friction coefficient each 60 fps tick until it drops below the stop
//   threshold, then snaps to the nearest index via a spring animation.
// • Cards beyond `visibleRadius` (±4 from center) are not rendered; the remaining
//   ones are sorted by distance so the center card always draws on top.
// • Tapping the center card "flips" it 180° to show the track/episode list on the
//   back face. Albums and playlists load their tracks asynchronously (spinner shown
//   during load); podcast episodes are already on the PodcastShow model and flip
//   instantly.

// MARK: - Content Type

enum ArtworkCarouselContent {
    case albums([AppAlbum])
    case playlists([AppPlaylist])
    case podcasts([PodcastShow])

    var itemCount: Int {
        switch self {
        case .albums(let items): return items.count
        case .playlists(let items): return items.count
        case .podcasts(let items): return items.count
        }
    }

    var backLabel: String {
        switch self {
        case .albums: return "Albums"
        case .playlists: return "Playlists"
        case .podcasts: return "Podcasts"
        }
    }

    func title(at index: Int) -> String {
        switch self {
        case .albums(let items): return index < items.count ? items[index].title : ""
        case .playlists(let items): return index < items.count ? items[index].name : ""
        case .podcasts(let items): return index < items.count ? items[index].title : ""
        }
    }

    func subtitle(at index: Int) -> String? {
        switch self {
        case .albums(let items):
            return index < items.count ? items[index].artistName : nil
        case .playlists:
            return nil
        case .podcasts(let items):
            guard index < items.count else { return nil }
            let count = items[index].episodes.count
            return "\(count) episode\(count == 1 ? "" : "s")"
        }
    }
}

// MARK: - View

struct ArtworkCarouselView: View {
    let content: ArtworkCarouselContent
    @ObservedObject var musicService: MusicService
    @Binding var selectedIndex: Int
    let onDismiss: () -> Void

    @State private var position: CGFloat = 0
    @State private var lastTranslation: CGFloat = 0
    @State private var isFlipped = false
    @State private var flipDegrees: Double = 0
    @State private var backFaceTracks: [AppTrack] = []
    @State private var backFaceEpisodes: [MPMediaItem] = []
    @State private var backFacePlaylistID: String? = nil
    @State private var backFacePodcastShowTitle: String? = nil
    @State private var isLoadingBackFace = false
    @State private var momentumTask: Task<Void, Never>? = nil

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var coverSize: CGFloat { verticalSizeClass == .compact ? 210 : 260 }
    private var reflectionRatio: CGFloat { 0.75 }
    private var baseSpacing: CGFloat { verticalSizeClass == .compact ? 42 : 52 }
    private let sideAngle: Double = 70
    private let minVisibleRadius = 3
    private let maxVisibleRadius = 9
    private let expandedScale: CGFloat = 1.06

    private var carouselHeight: CGFloat { coverSize * (1 + reflectionRatio) + 2 }
    private var pixelsPerItem: CGFloat { coverSize * 0.5 + baseSpacing }

    private var centeredIndex: Int {
        max(0, min(content.itemCount - 1, Int(position.rounded())))
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if isFlipped {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { flipBack() }
            }

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                carouselSection
                Spacer(minLength: 0)
                    .frame(height: isFlipped ? 4 : (verticalSizeClass == .compact ? 10 : 18))
                if !isFlipped { infoSection }
                Spacer(minLength: verticalSizeClass == .compact ? 10 : 22)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isFlipped)
        .onAppear {
            position = CGFloat(selectedIndex)
        }
        .onChange(of: selectedIndex) { _, newValue in
            if abs(position - CGFloat(newValue)) > 0.5 {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                    position = CGFloat(newValue)
                }
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button(action: {
                if isFlipped { flipBack() } else { onDismiss() }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text(isFlipped ? content.backLabel : "Back")
                        .font(.system(size: 14))
                }
                .foregroundColor(.white)
            }
            .padding(.leading, 20)
            .padding(.top, verticalSizeClass == .compact ? 8 : 14)
            Spacer()
        }
        .frame(height: verticalSizeClass == .compact ? 36 : 50)
    }

    // MARK: - Info Section

    private var infoSection: some View {
        Group {
            if content.itemCount > 0, centeredIndex < content.itemCount {
                VStack(alignment: .leading, spacing: 3) {
                    Text(content.title(at: centeredIndex))
                        .font(.system(size: verticalSizeClass == .compact ? 16 : 20, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if let subtitle = content.subtitle(at: centeredIndex) {
                        Text(subtitle)
                            .font(.system(size: verticalSizeClass == .compact ? 12 : 14))
                            .foregroundColor(Color(white: 0.62))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .id(centeredIndex)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.18), value: centeredIndex)
            }
        }
    }

    // MARK: - Carousel

    private var carouselSection: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(visibleIndices(in: geometry.size.width), id: \.self) { index in
                    coverCard(for: index)
                        .zIndex(index == centeredIndex ? 200 : zIndex(for: index))
                }
            }
            .frame(width: geometry.size.width, height: carouselHeight)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .frame(height: carouselHeight)
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    guard !isFlipped else { return }
                    momentumTask?.cancel()
                    momentumTask = nil
                    let delta = value.translation.width - lastTranslation
                    lastTranslation = value.translation.width
                    let maxIdx = CGFloat(max(0, content.itemCount - 1))
                    position = max(0, min(maxIdx, position - delta / pixelsPerItem))
                    if isFlipped && centeredIndex != selectedIndex { flipBack() }
                }
                .onEnded { value in
                    guard !isFlipped else { return }
                    lastTranslation = 0
                    let initialVelocity = value.velocity.width / pixelsPerItem
                    startMomentum(initialVelocity: initialVelocity)
                }
        )
    }

    // MARK: - Card Dispatch

    @ViewBuilder
    private func coverCard(for index: Int) -> some View {
        let isCentered = index == centeredIndex
        let rawPosition = CGFloat(index) - position

        if isCentered {
            centerCard(for: index)
                .scaleEffect(isFlipped ? expandedScale : 1.0)
                .rotation3DEffect(
                    .degrees(centerCardRotation(rawPosition: rawPosition)),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.42
                )
                .offset(x: isFlipped ? 0 : xOffset(for: index))
                .animation(.spring(response: 0.52, dampingFraction: 0.78), value: isFlipped)
        } else {
            sideCard(for: index)
                .scaleEffect(coverScale(rawPosition: rawPosition))
                .rotation3DEffect(
                    .degrees(rotationAngle(rawPosition: rawPosition)),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.35
                )
                .offset(x: xOffset(for: index))
                .opacity(isFlipped ? 0 : 1)
                .animation(.easeInOut(duration: 0.28), value: isFlipped)
        }
    }

    // MARK: - Center Card

    @ViewBuilder
    private func centerCard(for index: Int) -> some View {
        ZStack {
            artWithReflection(for: index)
                .opacity(flipDegrees < 90 ? 1 : 0)
                .allowsHitTesting(flipDegrees < 90)
                .onTapGesture {
                    Task { await loadAndFlip(index: index) }
                }

            backFace(for: index)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(flipDegrees >= 90 ? 1 : 0)
                .allowsHitTesting(flipDegrees >= 90)
        }
        .frame(width: coverSize, height: carouselHeight)
    }

    // MARK: - Side Card

    @ViewBuilder
    private func sideCard(for index: Int) -> some View {
        artWithReflection(for: index)
            .onTapGesture {
                guard !isFlipped else { return }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                    position = CGFloat(index)
                    selectedIndex = index
                }
            }
    }

    // MARK: - Art + Reflection

    @ViewBuilder
    private func artWithReflection(for index: Int) -> some View {
        VStack(spacing: 0) {
            artworkImage(for: index)
                .frame(width: coverSize, height: coverSize)
                .cornerRadius(5)
                .shadow(color: .black.opacity(0.85), radius: 14, x: 0, y: 7)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.clear, Color(white: 0.65).opacity(0.75), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: coverSize, height: 1)

            artworkImage(for: index)
                .frame(width: coverSize, height: coverSize)
                .cornerRadius(5)
                .scaleEffect(x: 1, y: -1)
                .mask(
                    LinearGradient(
                        colors: [Color.black.opacity(0.52), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: coverSize * reflectionRatio)
                    .frame(maxHeight: .infinity, alignment: .top)
                )
                .frame(height: coverSize * reflectionRatio)
                .clipped()
        }
        .frame(width: coverSize, height: carouselHeight)
    }

    // MARK: - Artwork Image

    @ViewBuilder
    private func artworkImage(for index: Int) -> some View {
        switch content {
        case .albums(let items):
            if index < items.count {
                let album = items[index]
                if let artwork = album.musicKitAlbum?.artwork {
                    ArtworkImage(artwork, width: coverSize)
                } else {
                    placeholderArt(icon: "music.note")
                }
            } else {
                placeholderArt(icon: "music.note")
            }
        case .playlists(let items):
            if index < items.count {
                let playlist = items[index]
                if let artwork = playlist.musicKitPlaylist?.artwork {
                    ArtworkImage(artwork, width: coverSize)
                } else {
                    placeholderArt(icon: "music.note.list")
                }
            } else {
                placeholderArt(icon: "music.note.list")
            }
        case .podcasts(let items):
            if index < items.count,
               let artwork = items[index].artwork,
               let image = artwork.image(at: CGSize(width: coverSize, height: coverSize)) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholderArt(icon: "mic.fill")
            }
        }
    }

    @ViewBuilder
    private func placeholderArt(icon: String) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Color(white: 0.18))
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: coverSize * 0.28))
                    .foregroundColor(Color(white: 0.44))
            }
    }

    // MARK: - Back Face

    @ViewBuilder
    private func backFace(for index: Int) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(white: 0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(white: 0.26), lineWidth: 0.5)
                )

            if isLoadingBackFace {
                ProgressView()
                    .tint(Color(white: 0.7))
                    .scaleEffect(0.85)
            } else {
                VStack(spacing: 0) {
                    Text(content.title(at: index))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(white: 0.72))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.top, 7)
                        .padding(.bottom, 5)

                    Rectangle()
                        .fill(Color(white: 0.28))
                        .frame(height: 0.5)

                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            switch content {
                            case .albums, .playlists:
                                ForEach(Array(backFaceTracks.enumerated()), id: \.offset) { i, track in
                                    trackRow(track: track, index: i)
                                    if i < backFaceTracks.count - 1 {
                                        Rectangle()
                                            .fill(Color(white: 0.17))
                                            .frame(height: 0.5)
                                            .padding(.leading, 27)
                                    }
                                }
                            case .podcasts:
                                ForEach(Array(backFaceEpisodes.enumerated()), id: \.offset) { i, episode in
                                    episodeRow(episode: episode, index: i)
                                    if i < backFaceEpisodes.count - 1 {
                                        Rectangle()
                                            .fill(Color(white: 0.17))
                                            .frame(height: 0.5)
                                            .padding(.leading, 27)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func trackRow(track: AppTrack, index: Int) -> some View {
        let isCurrentTrack = musicService.currentTrack?.title == track.title && musicService.isPlaying

        Button {
            Task { await musicService.play(tracks: backFaceTracks, startingAt: index, playlistID: backFacePlaylistID) }
        } label: {
            HStack(spacing: 5) {
                Group {
                    if isCurrentTrack {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 7))
                            .foregroundColor(.blue)
                    } else {
                        Text("\(index + 1)")
                            .font(.system(size: 8))
                            .foregroundColor(Color(white: 0.42))
                    }
                }
                .frame(width: 14, alignment: .trailing)

                Text(track.title)
                    .font(.system(size: 10, weight: isCurrentTrack ? .semibold : .regular))
                    .foregroundColor(isCurrentTrack ? .blue : .white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(formatDuration(track.duration))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color(white: 0.38))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isCurrentTrack ? Color.blue.opacity(0.28) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func episodeRow(episode: MPMediaItem, index: Int) -> some View {
        let isCurrentEpisode = musicService.currentMediaItem?.persistentID == episode.persistentID && musicService.isPlaying

        Button {
            Task { await musicService.playPodcastEpisodes(items: backFaceEpisodes, startingAt: index, podcastShowTitle: backFacePodcastShowTitle) }
        } label: {
            HStack(spacing: 5) {
                Group {
                    if isCurrentEpisode {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 7))
                            .foregroundColor(.blue)
                    } else {
                        Text("\(index + 1)")
                            .font(.system(size: 8))
                            .foregroundColor(Color(white: 0.42))
                    }
                }
                .frame(width: 14, alignment: .trailing)

                Text(episode.title ?? "Episode \(index + 1)")
                    .font(.system(size: 10, weight: isCurrentEpisode ? .semibold : .regular))
                    .foregroundColor(isCurrentEpisode ? .blue : .white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(formatDuration(episode.playbackDuration))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color(white: 0.38))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isCurrentEpisode ? Color.blue.opacity(0.28) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Flip Actions

    private func loadAndFlip(index: Int) async {
        switch content {
        case .podcasts(let items):
            // Episodes are already loaded — no spinner needed
            let episodes = index < items.count ? items[index].episodes : []
            await MainActor.run {
                backFaceEpisodes = episodes
                backFacePodcastShowTitle = index < items.count ? items[index].title : nil
                withAnimation(.spring(response: 0.6, dampingFraction: 0.74)) {
                    flipDegrees = 180
                    isFlipped = true
                }
            }

        case .albums(let items):
            guard index < items.count else { return }
            await MainActor.run {
                isLoadingBackFace = true
                withAnimation(.spring(response: 0.6, dampingFraction: 0.74)) {
                    flipDegrees = 180
                    isFlipped = true
                }
            }
            let albumTracks = await musicService.loadTracks(for: items[index])
            await MainActor.run {
                backFaceTracks = albumTracks
                isLoadingBackFace = false
            }

        case .playlists(let items):
            guard index < items.count else { return }
            await MainActor.run {
                isLoadingBackFace = true
                withAnimation(.spring(response: 0.6, dampingFraction: 0.74)) {
                    flipDegrees = 180
                    isFlipped = true
                }
            }
            let playlistTracks = await musicService.loadTracks(for: items[index])
            await MainActor.run {
                backFaceTracks = playlistTracks
                backFacePlaylistID = items[index].id
                isLoadingBackFace = false
            }
        }
    }

    private func flipBack() {
        withAnimation(.spring(response: 0.46, dampingFraction: 0.82)) {
            flipDegrees = 0
            isFlipped = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            backFaceTracks = []
            backFaceEpisodes = []
            backFacePlaylistID = nil
            backFacePodcastShowTitle = nil
        }
    }

    // MARK: - Momentum

    private func startMomentum(initialVelocity: CGFloat) {
        let maxIdx = CGFloat(max(0, content.itemCount - 1))
        momentumTask?.cancel()
        momentumTask = Task { @MainActor in
            var vel = initialVelocity    // items/sec; negative = swipe left = move forward
            let decay: CGFloat = 0.965  // fraction retained per frame at 60 fps
            let stopThreshold: CGFloat = 0.03
            let dt: CGFloat = 1.0 / 60.0

            while !Task.isCancelled && abs(vel) > stopThreshold {
                withTransaction(Transaction(animation: nil)) {
                    position = max(0, min(maxIdx, position - vel * dt))
                }
                vel *= decay
                try? await Task.sleep(nanoseconds: 16_666_667)
            }

            guard !Task.isCancelled else { return }

            let target = max(0, min(maxIdx, position.rounded()))
            withAnimation(.spring(response: 0.14, dampingFraction: 0.88)) {
                position = target
            }
            selectedIndex = Int(target)
        }
    }

    // MARK: - Layout Helpers

    private func visibleIndices(in containerWidth: CGFloat) -> [Int] {
        guard content.itemCount > 0 else { return [] }
        let center = centeredIndex
        let halfWidth = containerWidth / 2
        let radius: Int
        if pixelsPerItem < halfWidth {
            let extra = Int((halfWidth - pixelsPerItem) / baseSpacing + 0.5)
            radius = max(minVisibleRadius, min(maxVisibleRadius, 1 + extra))
        } else {
            radius = minVisibleRadius
        }
        let start = max(0, center - radius)
        let end = min(content.itemCount - 1, center + radius)
        return (start...end).sorted { abs(CGFloat($0) - position) > abs(CGFloat($1) - position) }
    }

    private func xOffset(for index: Int) -> CGFloat {
        let raw = CGFloat(index) - position
        guard abs(raw) > 0.0001 else { return 0 }
        let sign: CGFloat = raw < 0 ? -1 : 1
        let magnitude = abs(raw)
        if magnitude <= 1 {
            return sign * magnitude * pixelsPerItem
        } else {
            return sign * (pixelsPerItem + (magnitude - 1) * baseSpacing)
        }
    }

    private func rotationAngle(rawPosition: CGFloat) -> Double {
        let clamped = max(-1.0, min(1.0, Double(rawPosition)))
        return -clamped * sideAngle
    }

    private func centerCardRotation(rawPosition: CGFloat) -> Double {
        if isFlipped { return flipDegrees }
        return Double(-rawPosition) * sideAngle
    }

    private func coverScale(rawPosition: CGFloat) -> CGFloat {
        let m = abs(rawPosition)
        if m < 1 { return 1.0 - m * 0.13 }
        if m < 2 { return 0.87 - (m - 1) * 0.10 }
        return max(0.68, 0.77 - (m - 2) * 0.09)
    }

    private func zIndex(for index: Int) -> Double {
        Double(100 - abs(CGFloat(index) - position) * 10)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
