//
//  LiquidDiscover.swift
//  Lyre
//

import SwiftUI

// MARK: - Liquid Discover
//
// What Apple Music offers (Discover), on a page of its own from the lava menu: each of
// Made for You's groups, New Releases and the charts as a row of covers, and the genres
// as names to tap. A cover opens its page as any album or playlist does; one the library
// hasn't streams. A genre opens as a playlist of its top songs. Asked for when the page
// first opens, and filled in a section at a time.

struct LiquidDiscoverPage: View {
    @Environment(\.liquidNavigator) private var navigator
    @ObservedObject var musicService: MusicService
    let bottomInset: CGFloat

    private static let coverSide: CGFloat = 140

    var body: some View {
        let sections = Discover.shared.sections
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                LiquidPageTitle(title: String(localized: "discover.title"))
                if sections.isEmpty {
                    Text(Discover.emptyText)
                        .foregroundStyle(.white.opacity(0.7))
                        .accessibilityIdentifier("liquid.discover.empty")
                }
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(section.title.lowercasedKeepingAppleMusic)
                            .font(.system(size: 24, weight: .medium))
                            .tracking(-0.6)
                            .foregroundStyle(.white)
                            .accessibilityAddTraits(.isHeader)
                        if section.kind == .genres {
                            genres(section.items)
                        } else {
                            covers(section.items)
                        }
                    }
                    .accessibilityIdentifier("liquid.discover.\(section.id)")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, bottomInset + 20)
        }
        .background(LiquidPageGround())
        .toolbar(.hidden, for: .navigationBar)
        .task { await Discover.shared.load(in: musicService) }
    }

    private func covers(_ items: [AppAlbum]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(items) { album in
                    Button { navigator.push(.album(album)) } label: {
                        LiquidCoverTile(album: album).frame(width: Self.coverSide)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("liquid.discover.item")
                }
            }
        }
    }

    private func genres(_ items: [AppAlbum]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(items) { genre in
                Button { navigator.push(.album(genre)) } label: {
                    Text(genre.title)
                        .font(.system(size: 15, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.horizontal, 10)
                        .background(.white.opacity(0.12), in: Capsule())
                }
                .foregroundStyle(.white)
                .buttonStyle(.plain)
                .accessibilityIdentifier("liquid.discover.genre")
            }
        }
    }
}
