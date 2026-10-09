//
//  SearchView.swift
//  Lyre
//

import SwiftUI

// MARK: - Search Screen
//
// The Classic player's search, reached from Search on the main menu.
//
// Typing is done on the keyboard, which comes up as the screen opens (unless there's
// already a search to come back to). While it is up, LyreView lowers the click wheel out
// of view; pressing Search on the keyboard, or swiping the results, puts the keyboard
// away and the wheel comes back to scroll them. Tapping the field types again.
//
// The results (see LibrarySearch) are one list, artists first, then albums, songs,
// playlists and podcasts, each row marked with what it is. `selection` (bound from the
// parent, as on every list screen) is the wheel's cursor; ScrollWheelView acts on the
// highlighted row: a song plays, anything else opens.
struct SearchView: View {
    @Binding var query: String
    let results: [LibrarySearchResult]
    @Binding var selection: Int
    let themeSettings: ThemeSettings

    @FocusState private var isFieldFocused: Bool

    private var theme: LyreTheme { themeSettings.currentTheme }

    private var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.screenTextColor)
                Text(String(localized: "menu.search"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.screenTextColor)
                Spacer()
            }

            field

            Divider().background(theme.dividerColor)

            if !hasQuery {
                message(String(localized: "search.hint"))
            } else if results.isEmpty {
                message(String(localized: "search.noResults"))
            } else {
                resultsList
            }
        }
        .task {
            // A search being come back to (from an album opened in it, say) keeps the
            // keyboard down, so the wheel is there to carry on through the results.
            guard query.isEmpty else { return }
            // Focused once the screen's crossfade has started; a field that is not yet
            // in the window ignores the request.
            try? await Task.sleep(for: .milliseconds(150))
            isFieldFocused = true
        }
    }

    private var field: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.screenSecondaryTextColor)
                .accessibilityHidden(true)
            TextField(
                "",
                text: $query,
                prompt: Text(String(localized: "search.prompt"))
                    .foregroundStyle(theme.screenSecondaryTextColor)
            )
            .font(.system(size: 12))
            .foregroundStyle(theme.screenTextColor)
            .tint(theme.highlightColor)
            .focused($isFieldFocused)
            .submitLabel(.search)
            .onSubmit { isFieldFocused = false }
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .accessibilityIdentifier("search.field")

            if !query.isEmpty {
                Button {
                    query = ""
                    isFieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.screenSecondaryTextColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "search.clear"))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(theme.screenTextColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isFieldFocused ? theme.highlightColor : theme.dividerColor, lineWidth: 1)
        )
    }

    private func message(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.screenTextColor.opacity(0.5))
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
            Spacer()
        }
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(results.indices, id: \.self) { index in
                        row(results[index], isSelected: selection == index)
                            .id(index)
                    }
                }
            }
            // A swipe through the results is the sign typing is done.
            .scrollDismissesKeyboard(.immediately)
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
            .onChange(of: selection) { _, newValue in
                withAnimation { proxy.scrollTo(newValue, anchor: .center) }
            }
        }
    }

    private func row(_ result: LibrarySearchResult, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: result.systemImage)
                .font(.system(size: 10))
                .frame(width: 14)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Text(result.subtitle)
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .opacity(0.75)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(isSelected ? theme.highlightTextColor : theme.screenTextColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? theme.highlightColor : Color.clear)
        .selectionBarRefraction(when: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
