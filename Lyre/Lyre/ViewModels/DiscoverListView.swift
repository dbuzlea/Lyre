//
//  DiscoverListView.swift
//  Lyre
//

import SwiftUI

// What Apple Music offers (Discover), on the classic player's screen: from the main
// menu, a list of its sections (Made for You's groups, New Releases, the charts, the
// genres); a section, a list of what's in it, each opening as an album's list does
// (ScrollWheelView's handleSelect). Asked for when the list first shows.
struct DiscoverListView: View {
    let title: String
    let rows: [(title: String, subtitle: String?)]
    @Binding var selection: Int
    let themeSettings: ThemeSettings

    private var theme: LyreTheme { themeSettings.currentTheme }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.screenTextColor)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.screenTextColor)
                    .lineLimit(1)
                Spacer()
            }

            Divider().background(theme.dividerColor)

            if rows.isEmpty {
                VStack {
                    Spacer()
                    Text(Discover.emptyText)
                        .font(.system(size: 12))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(theme.screenTextColor.opacity(0.5))
                        .accessibilityIdentifier("discover.empty")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                                self.row(row, isSelected: selection == index)
                                    .frame(height: 32).id(index)
                            }
                        }
                    }
                    .onAppear { proxy.scrollTo(selection, anchor: .center) }
                    .onChange(of: selection) { _, newValue in
                        withAnimation { proxy.scrollTo(newValue, anchor: .center) }
                    }
                }
            }
        }
        // The wheel steps past the end of a section's list; kept to its rows.
        .onChange(of: selection) { _, newValue in
            guard !rows.isEmpty else { return }
            if newValue < 0 { selection = 0 }
            else if newValue >= rows.count { selection = rows.count - 1 }
        }
    }

    private func row(_ row: (title: String, subtitle: String?), isSelected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(row.title)
                    .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? theme.highlightTextColor : theme.screenTextColor)
                    .lineLimit(1)
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(isSelected ? theme.highlightTextColor.opacity(0.7) : theme.screenSecondaryTextColor)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(isSelected ? theme.highlightTextColor : theme.screenSecondaryTextColor)
                .padding(.trailing, 6)
        }
        .padding(.leading, 6).padding(.vertical, 2)
        .frame(maxHeight: .infinity)
        .background { if isSelected { Rectangle().fill(theme.highlightColor).selectionBarRefraction() } }
    }
}
