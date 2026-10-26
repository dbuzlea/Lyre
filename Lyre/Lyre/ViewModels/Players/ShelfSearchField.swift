//
//  ShelfSearchField.swift
//  Lyre
//

import SwiftUI

// MARK: - Shelf Search
//
// The search field over the Spool's rack and the Gramophone's crate. What's typed narrows
// every shelf to the tapes or records that match (see LibrarySearch.shelfMatches); each
// divider counts what's left on it, and when the shelf in front has nothing the rack
// turns to one that does. Clearing the field puts everything back.
//
// `ShelfSearching` does the searching for either player: it waits for a pause in the
// typing, searches once, and hands back the matches with the query they're for, which
// the players use to rebuild the rack once per search rather than once per keystroke.

struct ShelfSearchField: View {
    @Binding var query: String
    let prompt: String
    var isFocused: FocusState<Bool>.Binding
    @Environment(\.spoolTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .accessibilityHidden(true)
            TextField("", text: $query, prompt: Text(prompt).foregroundStyle(theme.keySymbol.opacity(0.55)))
                .font(.system(size: 15))
                .focused(isFocused)
                .submitLabel(.search)
                .onSubmit { isFocused.wrappedValue = false }
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("shelf.search.field")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(theme.keySymbol.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "search.clear"))
            }
        }
        .foregroundStyle(theme.keySymbol)
        .tint(theme.keySymbol)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.keyLight.opacity(0.85), in: Capsule())
    }
}

extension ShelfSearchMatches {
    /// A divider's title, followed while searching by how many matches are on its shelf.
    static func dividerTitle(_ title: String, on shelf: SpoolShelf, matches: ShelfSearchMatches?) -> String {
        guard let matches else { return title }
        return "\(title) \(matches.items(on: shelf).count)"
    }
}

/// Searches the shelves as `query` changes, a moment after the typing stops.
struct ShelfSearching: ViewModifier {
    let query: String
    let library: ShelfLibrary
    @Binding var shelf: SpoolShelf
    @Binding var matches: ShelfSearchMatches?

    func body(content: Content) -> some View {
        content.task(id: query) {
            if matches != nil || !query.isEmpty {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
            }
            let found = LibrarySearch.shelfMatches(for: query, in: library)
            withAnimation(.easeInOut(duration: 0.2)) {
                matches = found
                if let other = found?.shelfWithMatches(preferring: shelf) { shelf = other }
            }
        }
    }
}
