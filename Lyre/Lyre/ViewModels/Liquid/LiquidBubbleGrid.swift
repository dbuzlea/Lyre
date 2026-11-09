//
//  LiquidBubbleGrid.swift
//  Lyre
//

import SwiftUI

// MARK: - Liquid Bubble Grid
//
// Liquid's covers laid out as soap bubbles rather than a grid of squares (the albums,
// playlists and shows, an artist's albums, search's matches, an opened Discover
// section): staggered, every other column half a row lower, so each bubble sits in the
// gap between two of its neighbours, as bubbles do gathered on water. Each floats a
// little, out of step with the rest (BubbleFloat), and holds still while the page
// scrolls (StillWhileScrolling, on the page's scroll view).
//
// Each column is a lazy stack of its own, so only the bubbles in view are made, however
// big the library; VoiceOver still reads them in order, across then down.

struct LiquidBubbleGrid: View {
    let albums: [AppAlbum]
    /// How wide the grid lays out in (the page's measured width).
    let width: CGFloat
    /// Each bubble's identifier, by its album.
    var identifier: (AppAlbum) -> String = { "liquid.cover.\($0.id)" }
    /// Whether holding a bubble offers to queue it (LiquidAlbumHoldMenu).
    var holdMenu = true
    let open: (Int) -> Void
    /// Shared with the page an album opens to, for the zoom out of its bubble.
    @Environment(\.liquidDiscoverZoom) private var zoom

    /// Room for the name and byline under a bubble.
    static let labelHeight: CGFloat = 44
    /// The gap between one bubble's byline and the next bubble down its column.
    static let rowGap: CGFloat = 18

    var body: some View {
        let columns = Self.columnCount(for: width)
        let side = Self.bubbleSide(for: width)
        let tile = side + 8 + Self.labelHeight
        HStack(alignment: .top, spacing: LiquidCoverTile.spacing) {
            ForEach(0..<columns, id: \.self) { column in
                LazyVStack(spacing: Self.rowGap) {
                    ForEach(Array(stride(from: column, to: albums.count, by: columns)), id: \.self) { index in
                        bubble(at: index, side: side, height: tile)
                    }
                }
                // Every other column half a bubble lower: staggered, not side by side.
                .padding(.top, Self.isLowered(column) ? (tile + Self.rowGap) / 2 : 0)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .accessibilityElement(children: .contain)
        // The bubbles answer to the phone's tilt while they're up (BubbleTilt).
        .onAppear { BubbleTilt.shared.attach() }
        .onDisappear { BubbleTilt.shared.detach() }
    }

    private func bubble(at index: Int, side: CGFloat, height: CGFloat) -> some View {
        let album = albums[index]
        return Button {
            LiquidZoom.tapped(album.id)
            open(index)
        } label: {
            LiquidBubbleTile(album: album, diameter: side)
                .frame(height: height, alignment: .top)
        }
        .buttonStyle(BubblePressStyle())
        .modifier(DiscoverZoomSource(id: LiquidZoom.sourceID(album.id), namespace: zoom))
        .modifier(LiquidAlbumHoldMenu(album: album, isEnabled: holdMenu))
        .id(album.id)
        .accessibilityIdentifier(identifier(album))
        // Read across then down, as the bubbles are laid out, not one column after another.
        .accessibilitySortPriority(Double(albums.count - index))
    }

    static func columnCount(for width: CGFloat) -> Int { LiquidCoverTile.columnCount(for: width) }

    /// A column lowered half a row (the second, fourth…).
    static func isLowered(_ column: Int) -> Bool { !column.isMultiple(of: 2) }

    /// A bubble as wide as a column, less a little room round it to float in.
    static func bubbleSide(for width: CGFloat) -> CGFloat {
        let columns = CGFloat(columnCount(for: width))
        let column = (max(width, 160) - LiquidCoverTile.spacing * (columns - 1)) / columns
        return (column * 0.9).rounded()
    }
}
