//
//  PodcastSearchView.swift
//  Lyre
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Podcast Search
//
// The one screen in Lyre that isn't driven by the scroll wheel: finding a show needs a
// keyboard. Presented as a sheet from the "Search Podcasts" row of the Podcasts list.
//
// Searching goes through PodcastDirectory (Apple's public search API — no account).
// Pasting a feed URL instead adds that feed directly, which covers shows the directory
// doesn't list and private or premium feeds. With the search field empty the sheet
// lists current subscriptions, where swiping a row unsubscribes, and the space taken
// by downloaded episodes. The toolbar menu imports and exports subscriptions as OPML,
// the format other podcast apps use.
struct PodcastSearchView: View {
    @ObservedObject var musicService: MusicService
    @ObservedObject private var downloads = PodcastDownloads.shared
    @AppStorage(PodcastDownloads.autoDownloadNewKey) private var autoDownloadNew = false
    @AppStorage(PodcastDownloads.removeAfterPlayingKey) private var removeAfterPlaying = false
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [PodcastDirectory.SearchResult] = []
    @State private var isSearching = false
    @State private var searchError: String?
    /// Feeds being fetched after a Subscribe tap.
    @State private var subscribing: Set<URL> = []
    @State private var subscribeError: String?
    @State private var isImporting = false
    @State private var isImportRunning = false
    @State private var importMessage: String?
    @State private var exportDocument: OPMLDocument?

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The query as a feed address, when it looks like one.
    private var pastedFeedURL: URL? {
        guard let url = URL(string: trimmedQuery),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host() != nil else { return nil }
        return url
    }

    private var subscribedShows: [PodcastShow] {
        musicService.podcastShows.filter(\.isStreamed)
    }

    var body: some View {
        NavigationStack {
            List {
                if trimmedQuery.isEmpty {
                    subscriptionsSection
                } else if let feedURL = pastedFeedURL {
                    Section {
                        Button {
                            subscribe(to: feedURL)
                        } label: {
                            HStack {
                                Label(String(localized: "podcastSearch.addFeed"), systemImage: "link")
                                Spacer()
                                subscribeIndicator(for: feedURL)
                            }
                        }
                        .disabled(subscribing.contains(feedURL) || musicService.isSubscribed(to: feedURL))
                    } footer: {
                        Text(feedURL.absoluteString)
                    }
                } else {
                    resultsSection
                }
            }
            .navigationTitle(String(localized: "podcasts.search"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: String(localized: "podcastSearch.prompt")
            )
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "podcastSearch.done")) { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if isImportRunning {
                        ProgressView()
                    } else {
                        Menu {
                            Button(String(localized: "podcastSearch.import"), systemImage: "square.and.arrow.down") {
                                isImporting = true
                            }
                            Button(String(localized: "podcastSearch.export"), systemImage: "square.and.arrow.up") {
                                exportDocument = OPMLDocument(text: musicService.exportSubscriptionsOPML())
                            }
                            .disabled(subscribedShows.isEmpty)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [OPML.contentType, .xml]) { result in
                if case .success(let url) = result { importOPML(from: url) }
            }
            .fileExporter(
                isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
                document: exportDocument,
                contentType: OPML.contentType,
                defaultFilename: "Lyre Podcasts"
            ) { _ in exportDocument = nil }
            .alert(
                String(localized: "podcastSearch.importDone"),
                isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importMessage ?? "")
            }
            .task(id: trimmedQuery) { await search() }
            .alert(
                String(localized: "podcastSearch.subscribeFailed"),
                isPresented: Binding(get: { subscribeError != nil }, set: { if !$0 { subscribeError = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(subscribeError ?? "")
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var subscriptionsSection: some View {
        if subscribedShows.isEmpty {
            Section {
                Text(String(localized: "podcastSearch.intro"))
                    .foregroundStyle(.secondary)
            }
        } else {
            Section(String(localized: "podcastSearch.subscribed")) {
                ForEach(subscribedShows) { show in
                    row(title: show.title, subtitle: "\(show.episodes.count) episode\(show.episodes.count == 1 ? "" : "s")",
                        artworkURL: show.artworkURL)
                }
                .onDelete { offsets in
                    for index in offsets {
                        if let feedURL = subscribedShows[index].feedURL {
                            musicService.unsubscribe(from: feedURL)
                        }
                    }
                }
            }
            downloadsSection
        }
    }

    private var downloadsSection: some View {
        Section {
            Toggle(String(localized: "download.autoNew"), isOn: $autoDownloadNew)
            Toggle(String(localized: "download.removeAfterPlaying"), isOn: $removeAfterPlaying)
            if downloads.hasDownloads {
                Button(String(localized: "podcastSearch.removeDownloads"), role: .destructive) {
                    downloads.removeAll()
                }
            }
        } header: {
            Text(String(localized: "podcastSearch.downloads"))
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if downloads.hasDownloads {
                    Text(String(format: String(localized: "podcastSearch.downloadsUsage"),
                                ByteCountFormatter.string(fromByteCount: downloads.totalSize(), countStyle: .file)))
                }
                if autoDownloadNew {
                    Text(String(localized: "download.autoNewFooter"))
                }
                Text(String(localized: "podcastSearch.downloadsHint"))
            }
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        if isSearching && results.isEmpty {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .listRowBackground(Color.clear)
        } else if let searchError {
            Text(searchError).foregroundStyle(.secondary)
        } else if results.isEmpty {
            Text(String(localized: "podcastSearch.noResults")).foregroundStyle(.secondary)
        } else {
            ForEach(results) { result in
                HStack {
                    row(title: result.title, subtitle: result.author, artworkURL: result.artworkURL)
                    Spacer()
                    Button {
                        subscribe(to: result.feedURL)
                    } label: {
                        subscribeIndicator(for: result.feedURL)
                    }
                    .buttonStyle(.borderless)
                    .disabled(subscribing.contains(result.feedURL) || musicService.isSubscribed(to: result.feedURL))
                }
            }
        }
    }

    private func row(title: String, subtitle: String, artworkURL: URL?) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: artworkURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.secondary.opacity(0.2)
                    .overlay { Image(systemName: "mic.fill").foregroundStyle(.secondary) }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium)).lineLimit(2)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private func subscribeIndicator(for feedURL: URL) -> some View {
        if subscribing.contains(feedURL) {
            ProgressView()
        } else if musicService.isSubscribed(to: feedURL) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel(String(localized: "podcastSearch.subscribed"))
        } else {
            Image(systemName: "plus.circle")
                .font(.title3)
                .accessibilityLabel(String(localized: "podcastSearch.subscribe"))
        }
    }

    // MARK: Actions

    private func search() async {
        searchError = nil
        guard !trimmedQuery.isEmpty, pastedFeedURL == nil else {
            results = []
            return
        }
        // Debounce: the task is cancelled and restarted on every keystroke.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }

        isSearching = true
        defer { isSearching = false }
        do {
            let found = try await PodcastDirectory.search(trimmedQuery)
            guard !Task.isCancelled else { return }
            results = found
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            searchError = String(localized: "podcastSearch.failed")
        }
    }

    private func importOPML(from url: URL) {
        // A picked file outside the app's sandbox must be opened with scoped access.
        let scoped = url.startAccessingSecurityScopedResource()
        let data = try? Data(contentsOf: url)
        if scoped { url.stopAccessingSecurityScopedResource() }

        let feeds = data.map(OPML.feedURLs(in:)) ?? []
        guard !feeds.isEmpty else {
            importMessage = String(localized: "podcastSearch.importEmpty")
            return
        }
        isImportRunning = true
        Task {
            let result = await musicService.importSubscriptions(from: feeds)
            isImportRunning = false
            importMessage = result.failed == 0
                ? String(format: String(localized: "podcastSearch.importResult"), result.added)
                : String(format: String(localized: "podcastSearch.importResultFailed"), result.added, result.failed)
        }
    }

    private func subscribe(to feedURL: URL) {
        subscribing.insert(feedURL)
        Task {
            defer { subscribing.remove(feedURL) }
            do {
                try await musicService.subscribe(to: feedURL)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                subscribeError = error.localizedDescription
            }
        }
    }
}
