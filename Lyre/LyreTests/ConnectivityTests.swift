//
//  ConnectivityTests.swift
//  LyreTests
//
//  How Lyre behaves on every kind of connection: online, offline, on a flaky or slow
//  network, with cellular data off, and against a server that's down or answers with
//  something that isn't a podcast. Requests to URLSession.shared are answered by
//  StubNetwork, so nothing here touches the real network.
//

import Testing
import Foundation
@testable import Lyre

// MARK: - Stub Network

/// Answers URLSession.shared requests from a table of canned responses, keyed by URL
/// (or by search term, for the podcast directory). Anything not in the table goes to
/// the real network as usual, so the host app is unaffected.
nonisolated final class StubNetwork: URLProtocol {
    enum Response {
        case ok(String)
        case status(Int)
        case fail(URLError.Code)
        case redirect(to: URL)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var routes: [String: Response] = [:]
    nonisolated(unsafe) private static var registered = false

    static func route(_ url: URL, _ response: Response) {
        set(key(for: url), response)
    }

    static func routeSearch(term: String, _ response: Response) {
        set("search:" + term, response)
    }

    static func remove(_ url: URL) {
        lock.withLock { routes[key(for: url)] = nil }
    }

    private static func set(_ key: String, _ response: Response) {
        lock.withLock {
            routes[key] = response
            if !registered {
                registered = true
                URLProtocol.registerClass(StubNetwork.self)
            }
        }
    }

    private static func key(for url: URL) -> String {
        if url.host() == "itunes.apple.com",
           let term = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "term" })?.value {
            return "search:" + term
        }
        return url.absoluteString
    }

    private static func response(for url: URL) -> Response? {
        lock.withLock { routes[key(for: url)] }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url.map { response(for: $0) != nil } ?? false
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let response = Self.response(for: url) else { return }
        switch response {
        case .ok(let body):
            send(url, status: 200, body: Data(body.utf8))
        case .status(let code):
            send(url, status: code, body: Data())
        case .fail(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .redirect(let target):
            let redirect = HTTPURLResponse(url: url, statusCode: 301, httpVersion: "HTTP/1.1",
                                           headerFields: ["Location": target.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: redirect)
        }
    }

    override func stopLoading() {}

    private func send(_ url: URL, status: Int, body: Data) {
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// A feed address no other test uses, so tests running side by side don't collide.
private func uniqueFeedURL(_ name: String = "feed") -> URL {
    URL(string: "https://\(UUID().uuidString.lowercased()).lyre.test/\(name).xml")!
}

/// A podcast feed with the given items, each `(title, guid, pubDate, duration)`.
private func rss(title: String = "Morning Somewhere",
                 extraChannel: String = "",
                 items: [(String, String, String?, String?)]) -> String {
    let body = items.map { title, guid, date, duration in
        """
        <item>
          <title>\(title)</title>
          <guid>\(guid)</guid>
          \(date.map { "<pubDate>\($0)</pubDate>" } ?? "")
          \(duration.map { "<itunes:duration>\($0)</itunes:duration>" } ?? "")
          <enclosure url="https://cdn.lyre.test/\(guid).mp3" type="audio/mpeg"/>
        </item>
        """
    }.joined(separator: "\n")
    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
      <channel>
        <title>\(title)</title>
        \(extraChannel)
        \(body)
      </channel>
    </rss>
    """
}

private let twoEpisodes = rss(items: [
    ("Monday", "mon", "Mon, 01 Jun 2026 06:00:00 +0000", "10:00"),
    ("Tuesday", "tue", "Tue, 02 Jun 2026 06:00:00 +0000", "10:00"),
])

// MARK: - MusicLoadError: Every Connection State

@Suite("MusicLoadError across connection states")
struct ConnectionErrorClassificationTests {

    @Test(arguments: [
        URLError.Code.notConnectedToInternet,  // airplane mode, no Wi‑Fi or cellular
        .networkConnectionLost,                // dropped mid-request (lift, tunnel)
        .timedOut,                             // slow or captive network
        .cannotConnectToHost,
        .dnsLookupFailed,
        .cannotFindHost,                       // captive portal, broken DNS
        .dataNotAllowed,                       // cellular data off for Lyre
        .internationalRoamingOff,              // abroad with roaming off
    ])
    func noConnectionReadsAsNoNetwork(_ code: URLError.Code) {
        #expect(MusicLoadError.from(URLError(code)) == .noNetwork)
    }

    @Test(arguments: [URLError.Code.badServerResponse, .cannotParseResponse, .resourceUnavailable, .badURL])
    func aServerProblemReadsAsServerError(_ code: URLError.Code) {
        #expect(MusicLoadError.from(URLError(code)) == .serverError)
    }

    @Test func messagesAreClassifiedWhenThereIsNoURLError() {
        func error(_ message: String) -> NSError {
            NSError(domain: "MusicKit", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        #expect(MusicLoadError.from(error("The user is not authorized")) == .notAuthorized)
        #expect(MusicLoadError.from(error("Missing permission")) == .notAuthorized)
        #expect(MusicLoadError.from(error("The device is offline")) == .noNetwork)
        #expect(MusicLoadError.from(error("The Internet connection appears to be offline.")) == .noNetwork)
        #expect(MusicLoadError.from(error("Service temporarily unavailable")) == .serverError)
        #expect(MusicLoadError.from(error("Something odd")) == .unknown)
    }

    @Test func onlyAnErrorTheUserCanFixByRetryingOffersRetry() {
        // Offline, server down or unknown: try again later. No access: off to Settings.
        #expect(MusicLoadError.noNetwork.isRetryable)
        #expect(MusicLoadError.serverError.isRetryable)
        #expect(MusicLoadError.unknown.isRetryable)
        #expect(!MusicLoadError.notAuthorized.isRetryable)
    }
}

// MARK: - Streaming Offline

@Suite("Stream failures")
@MainActor
struct StreamFailureTests {

    @Test(arguments: [
        NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorDataNotAllowed,
        NSURLErrorInternationalRoamingOff, NSURLErrorCannotFindHost, NSURLErrorTimedOut,
    ])
    func aStreamThatFailsForWantOfAConnectionSaysOffline(_ code: Int) {
        #expect(MusicService.isOffline(NSError(domain: NSURLErrorDomain, code: code)))
    }

    @Test func theConnectionErrorIsFoundUnderAVFoundationsWrapping() {
        // AVPlayerItem reports its own error with the network failure underneath.
        let network = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let media = NSError(domain: "CoreMediaErrorDomain", code: -12938, userInfo: [NSUnderlyingErrorKey: network])
        let item = NSError(domain: "AVFoundationErrorDomain", code: -11800, userInfo: [NSUnderlyingErrorKey: media])
        #expect(MusicService.isOffline(item))
    }

    @Test func aBrokenEpisodeOnAGoodConnectionIsNotOffline() {
        #expect(!MusicService.isOffline(nil))
        #expect(!MusicService.isOffline(NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse)))
        #expect(!MusicService.isOffline(NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist)))
        #expect(!MusicService.isOffline(NSError(domain: "AVFoundationErrorDomain", code: -11828)))
    }
}

// MARK: - Podcast Directory Search

@Suite("Podcast search")
struct PodcastSearchConnectivityTests {

    @Test func resultsListShowsWithAFeedAndDropThoseWithout() async throws {
        let term = "search-\(UUID().uuidString)"
        StubNetwork.routeSearch(term: term, .ok("""
        {"resultCount": 3, "results": [
          {"collectionName": "Morning Somewhere", "artistName": "Radio", "feedUrl": "https://a.lyre.test/feed.xml",
           "artworkUrl600": "https://a.lyre.test/600.jpg", "artworkUrl100": "https://a.lyre.test/100.jpg"},
          {"collectionName": "Apple Exclusive", "artistName": "Nobody"},
          {"feedUrl": "https://b.lyre.test/feed.xml", "artworkUrl100": "https://b.lyre.test/100.jpg"}
        ]}
        """))
        let results = try await PodcastDirectory.search(term)
        #expect(results.map(\.title) == ["Morning Somewhere", "Untitled"])
        #expect(results[0].author == "Radio")
        #expect(results[0].artworkURL?.absoluteString == "https://a.lyre.test/600.jpg")
        // The small artwork stands in when there's no large one.
        #expect(results[1].artworkURL?.absoluteString == "https://b.lyre.test/100.jpg")
        #expect(results[1].author == "")
    }

    @Test func aSearchThatFindsNothingIsEmptyNotAnError() async throws {
        let term = "nothing-\(UUID().uuidString)"
        StubNetwork.routeSearch(term: term, .ok(#"{"resultCount": 0, "results": []}"#))
        #expect(try await PodcastDirectory.search(term).isEmpty)
    }

    @Test(arguments: [URLError.Code.notConnectedToInternet, .timedOut, .networkConnectionLost, .dataNotAllowed])
    func searchingWithoutAConnectionThrowsTheConnectionError(_ code: URLError.Code) async {
        let term = "offline-\(code.rawValue)-\(UUID().uuidString)"
        StubNetwork.routeSearch(term: term, .fail(code))
        await #expect {
            try await PodcastDirectory.search(term)
        } throws: { error in
            (error as? URLError)?.code == code
        }
    }

    @Test(arguments: [500, 503, 404, 429])
    func aDirectoryThatIsDownIsABadResponse(_ status: Int) async {
        let term = "down-\(status)-\(UUID().uuidString)"
        StubNetwork.routeSearch(term: term, .status(status))
        await #expect(throws: PodcastDirectory.DirectoryError.self) {
            try await PodcastDirectory.search(term)
        }
    }

    @Test func aGarbledAnswerThrowsRatherThanShowingNothing() async {
        let term = "garbled-\(UUID().uuidString)"
        // A captive portal's sign-in page arrives as a 200 too.
        StubNetwork.routeSearch(term: term, .ok("<html><body>Sign in to the hotel Wi‑Fi</body></html>"))
        await #expect(throws: (any Error).self) {
            try await PodcastDirectory.search(term)
        }
    }

    @Test func termsWithSpacesAndSymbolsAreSentWhole() async throws {
        let term = "rock & roll café \(UUID().uuidString)"
        StubNetwork.routeSearch(term: term, .ok(#"{"results": [{"collectionName": "Found", "feedUrl": "https://c.lyre.test/f.xml"}]}"#))
        #expect(try await PodcastDirectory.search(term).map(\.title) == ["Found"])
    }

    @Test func everyDirectoryErrorTellsTheUserSomething() {
        for error in [PodcastDirectory.DirectoryError.badResponse, .notAFeed, .noEpisodes] {
            #expect(!(error.errorDescription ?? "").isEmpty)
        }
    }
}

// MARK: - Reading Feeds

@Suite("Podcast feeds")
struct PodcastFeedTests {

    private func fetch(_ body: String, at url: URL = uniqueFeedURL()) async throws -> FeedShow {
        StubNetwork.route(url, .ok(body))
        defer { StubNetwork.remove(url) }
        return try await PodcastDirectory.fetchFeed(url)
    }

    @Test func aFeedIsReadNewestFirst() async throws {
        let feed = try await fetch(twoEpisodes)
        #expect(feed.title == "Morning Somewhere")
        #expect(feed.episodes.map(\.title) == ["Tuesday", "Monday"])
        #expect(feed.episodes.map(\.guid) == ["tue", "mon"])
        #expect(feed.episodes[0].audioURL.absoluteString == "https://cdn.lyre.test/tue.mp3")
    }

    @Test func theShowsAuthorAndArtworkAreRead() async throws {
        let feed = try await fetch(rss(
            extraChannel: """
            <itunes:author>Lyre Radio</itunes:author>
            <itunes:image href="https://img.lyre.test/show.jpg"/>
            """,
            items: [("One", "1", nil, nil)]))
        #expect(feed.author == "Lyre Radio")
        #expect(feed.artworkURL?.absoluteString == "https://img.lyre.test/show.jpg")
    }

    @Test func thePlainRSSImageIsUsedWhenThereIsNoItunesImage() async throws {
        let feed = try await fetch(rss(
            extraChannel: "<image><url>https://img.lyre.test/plain.png</url><title>Show</title></image>",
            items: [("One", "1", nil, nil)]))
        #expect(feed.artworkURL?.absoluteString == "https://img.lyre.test/plain.png")
        // The image's own <title> isn't the show's.
        #expect(feed.title == "Morning Somewhere")
    }

    @Test(arguments: [("90", 90.0), ("12:30", 750.0), ("1:02:03", 3723.0), ("", -1), ("soon", -1)])
    func durationsAreReadInEveryShapeFeedsUse(_ text: String, _ seconds: Double) async throws {
        let feed = try await fetch(rss(items: [("One", "1", nil, text)]))
        #expect(feed.episodes[0].duration == (seconds < 0 ? nil : seconds))
    }

    @Test(arguments: [
        "Tue, 02 Jun 2026 06:00:00 +0000",
        "Tue, 02 Jun 2026 06:00:00 GMT",
        "Tue, 02 Jun 2026 06:00 +0000",
        "02 Jun 2026 06:00:00 +0000",
        "Tue, 2 Jun 2026 06:00:00 +0000",
    ])
    func datesAreReadInEveryShapeFeedsUse(_ text: String) async throws {
        let feed = try await fetch(rss(items: [("One", "1", text, nil)]))
        let expected = Date(timeIntervalSince1970: 1_780_380_000)  // 2 June 2026, 06:00 UTC
        #expect(feed.episodes[0].published == expected)
    }

    @Test func undatedEpisodesGoLast() async throws {
        let feed = try await fetch(rss(items: [
            ("Undated", "u", nil, nil),
            ("Old", "o", "Mon, 01 Jun 2026 06:00:00 +0000", nil),
            ("New", "n", "Wed, 03 Jun 2026 06:00:00 +0000", nil),
        ]))
        #expect(feed.episodes.map(\.title) == ["New", "Old", "Undated"])
    }

    @Test func anItemWithNoAudioIsLeftOut() async throws {
        let body = """
        <rss><channel><title>Show</title>
          <item><title>Trailer page</title><guid>t</guid></item>
          <item><title>Real</title><guid>r</guid><enclosure url="https://cdn.lyre.test/r.mp3"/></item>
        </channel></rss>
        """
        #expect(try await fetch(body).episodes.map(\.title) == ["Real"])
    }

    @Test func missingTitlesAndGuidsGetSensibleStandIns() async throws {
        let body = """
        <rss><channel><title></title>
          <item><enclosure url="https://cdn.lyre.test/x.mp3"/></item>
        </channel></rss>
        """
        let url = uniqueFeedURL()
        let feed = try await fetch(body, at: url)
        #expect(feed.title == url.host())
        #expect(feed.episodes[0].title == "Episode")
        // With no guid, the audio address keeps the episode's identity.
        #expect(feed.episodes[0].guid == "https://cdn.lyre.test/x.mp3")
    }

    @Test func cdataTitlesAndEpisodeArtworkAreRead() async throws {
        let body = """
        <rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel><title><![CDATA[Rock & Roll]]></title>
          <item><title><![CDATA[Part <1>]]></title><guid>p1</guid>
            <itunes:image href="https://img.lyre.test/p1.jpg"/>
            <enclosure url="https://cdn.lyre.test/p1.mp3"/></item>
        </channel></rss>
        """
        let feed = try await fetch(body)
        #expect(feed.title == "Rock & Roll")
        #expect(feed.episodes[0].title == "Part <1>")
        #expect(feed.episodes[0].artworkURL?.absoluteString == "https://img.lyre.test/p1.jpg")
    }

    @Test func aHugeBackCatalogueIsCutToTheNewest() async throws {
        let count = PodcastDirectory.maxEpisodes + 25
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        let items = (0..<count).map { day in
            ("Day \(day)", "d\(day)", formatter.string(from: Date(timeIntervalSince1970: Double(day) * 86_400)), nil as String?)
        }
        let feed = try await fetch(rss(items: items))
        #expect(feed.episodes.count == PodcastDirectory.maxEpisodes)
        #expect(feed.episodes.first?.title == "Day \(count - 1)")
    }

    @Test func aFeedCutOffMidDownloadStillGivesTheEpisodesRead() async throws {
        // A connection that drops part way can leave the XML unfinished.
        let body = """
        <rss><channel><title>Show</title>
          <item><title>Whole</title><guid>w</guid><enclosure url="https://cdn.lyre.test/w.mp3"/></item>
          <item><title>Cut
        """
        #expect(try await fetch(body).episodes.map(\.title) == ["Whole"])
    }

    @Test func aWebPageIsNotAFeed() async {
        await #expect {
            try await fetch("<html><head><title>Hello</title></head><body>Not a feed</body></html>")
        } throws: { error in
            if case PodcastDirectory.DirectoryError.notAFeed = error { return true }
            return false
        }
    }

    @Test func aFeedWithNothingToPlaySaysSo() async {
        await #expect {
            try await fetch("<rss><channel><title>Empty</title></channel></rss>")
        } throws: { error in
            if case PodcastDirectory.DirectoryError.noEpisodes = error { return true }
            return false
        }
    }

    @Test(arguments: [404, 410, 500, 503])
    func aFeedThatIsGoneOrDownIsABadResponse(_ status: Int) async {
        let url = uniqueFeedURL()
        StubNetwork.route(url, .status(status))
        await #expect {
            try await PodcastDirectory.fetchFeed(url)
        } throws: { error in
            if case PodcastDirectory.DirectoryError.badResponse = error { return true }
            return false
        }
    }

    @Test(arguments: [URLError.Code.notConnectedToInternet, .timedOut, .networkConnectionLost, .internationalRoamingOff])
    func fetchingAFeedOfflineThrowsTheConnectionError(_ code: URLError.Code) async {
        let url = uniqueFeedURL()
        StubNetwork.route(url, .fail(code))
        await #expect {
            try await PodcastDirectory.fetchFeed(url)
        } throws: { error in
            (error as? URLError)?.code == code
        }
    }

    @Test func aMovedFeedIsStillKnownByTheAddressSubscribedTo() async throws {
        let old = uniqueFeedURL("old")
        let new = uniqueFeedURL("new")
        StubNetwork.route(old, .redirect(to: new))
        StubNetwork.route(new, .ok(twoEpisodes))
        let feed = try await PodcastDirectory.fetchFeed(old)
        #expect(feed.feedURL == old)
        #expect(feed.episodes.count == 2)
    }
}

// MARK: - Subscribing, Importing and Refreshing

@Suite("Podcast subscriptions online and offline", .serialized)
@MainActor
struct PodcastSubscriptionConnectivityTests {

    @Test func subscribingOnlineAddsTheShow() async throws {
        let service = MusicService()
        let url = uniqueFeedURL()
        StubNetwork.route(url, .ok(twoEpisodes))
        defer { service.unsubscribe(from: url) }

        try await service.subscribe(to: url)
        #expect(service.isSubscribed(to: url))
        let show = try #require(service.podcastShows.first { $0.feedURL == url })
        #expect(show.episodes.map(\.title) == ["Tuesday", "Monday"])
        #expect(service.exportSubscriptionsOPML().contains(url.absoluteString))
    }

    @Test(arguments: [URLError.Code.notConnectedToInternet, .timedOut, .dataNotAllowed])
    func subscribingOfflineFailsAndAddsNothing(_ code: URLError.Code) async {
        let service = MusicService()
        let url = uniqueFeedURL()
        StubNetwork.route(url, .fail(code))
        await #expect(throws: URLError.self) {
            try await service.subscribe(to: url)
        }
        #expect(!service.isSubscribed(to: url))
        #expect(!service.podcastShows.contains { $0.feedURL == url })
    }

    @Test func subscribingToAPageThatIsntAFeedSaysWhy() async {
        let service = MusicService()
        let url = uniqueFeedURL()
        StubNetwork.route(url, .ok("<html><body>Blog</body></html>"))
        await #expect {
            try await service.subscribe(to: url)
        } throws: { error in
            (error as? LocalizedError)?.errorDescription == PodcastDirectory.DirectoryError.notAFeed.errorDescription
        }
        #expect(!service.isSubscribed(to: url))
    }

    @Test func unsubscribingRemovesTheShow() async throws {
        let service = MusicService()
        let url = uniqueFeedURL()
        StubNetwork.route(url, .ok(twoEpisodes))
        try await service.subscribe(to: url)
        service.unsubscribe(from: url)
        #expect(!service.isSubscribed(to: url))
        #expect(!service.podcastShows.contains { $0.feedURL == url })
    }

    @Test func anImportOnAPatchyConnectionAddsWhatItCanAndCountsTheRest() async {
        let service = MusicService()
        let good = uniqueFeedURL("good"), down = uniqueFeedURL("down"), offline = uniqueFeedURL("offline")
        StubNetwork.route(good, .ok(twoEpisodes))
        StubNetwork.route(down, .status(500))
        StubNetwork.route(offline, .fail(.networkConnectionLost))
        defer { [good, down, offline].forEach(service.unsubscribe(from:)) }

        let result = await service.importSubscriptions(from: [good, down, offline])
        #expect(result.added == 1)
        #expect(result.failed == 2)
        #expect(service.isSubscribed(to: good))
        #expect(!service.isSubscribed(to: down) && !service.isSubscribed(to: offline))
    }

    @Test func anImportSkipsShowsAlreadySubscribedTo() async throws {
        let service = MusicService()
        let url = uniqueFeedURL()
        StubNetwork.route(url, .ok(twoEpisodes))
        defer { service.unsubscribe(from: url) }
        try await service.subscribe(to: url)

        // Offline now: had it been fetched again, it would have counted as failed.
        StubNetwork.route(url, .fail(.notConnectedToInternet))
        let result = await service.importSubscriptions(from: [url])
        #expect(result.added == 0 && result.failed == 0)
    }

    @Test func anImportWhollyOfflineAddsNothing() async {
        let service = MusicService()
        let urls = (0..<8).map { uniqueFeedURL("f\($0)") }
        for url in urls { StubNetwork.route(url, .fail(.notConnectedToInternet)) }
        let result = await service.importSubscriptions(from: urls)
        #expect(result.added == 0)
        #expect(result.failed == urls.count)
    }

    @Test func goingOfflineKeepsTheLastCopyOfEveryShow() async throws {
        let service = MusicService()
        let url = uniqueFeedURL()
        StubNetwork.route(url, .ok(twoEpisodes))
        defer { service.unsubscribe(from: url) }
        try await service.subscribe(to: url)

        StubNetwork.route(url, .fail(.notConnectedToInternet))
        await service.refreshSubscribedFeeds(force: true)
        let show = try #require(service.podcastShows.first { $0.feedURL == url })
        #expect(show.episodes.map(\.title) == ["Tuesday", "Monday"])
    }

    @Test func aServerOutageKeepsTheLastCopyToo() async throws {
        let service = MusicService()
        let url = uniqueFeedURL()
        StubNetwork.route(url, .ok(twoEpisodes))
        defer { service.unsubscribe(from: url) }
        try await service.subscribe(to: url)

        StubNetwork.route(url, .status(503))
        await service.refreshSubscribedFeeds(force: true)
        #expect(service.podcastShows.first { $0.feedURL == url }?.episodes.count == 2)
    }

    @Test func backOnlineANewEpisodeArrivesButNotMoreOftenThanEveryHalfHour() async throws {
        let service = MusicService()
        let url = uniqueFeedURL()
        StubNetwork.route(url, .ok(twoEpisodes))
        defer { service.unsubscribe(from: url) }
        try await service.subscribe(to: url)
        await service.refreshSubscribedFeeds(force: true)

        StubNetwork.route(url, .ok(rss(items: [
            ("Monday", "mon", "Mon, 01 Jun 2026 06:00:00 +0000", nil),
            ("Tuesday", "tue", "Tue, 02 Jun 2026 06:00:00 +0000", nil),
            ("Wednesday", "wed", "Wed, 03 Jun 2026 06:00:00 +0000", nil),
        ])))
        // Just refreshed: an ordinary visit doesn't fetch again.
        await service.refreshSubscribedFeeds()
        #expect(service.podcastShows.first { $0.feedURL == url }?.episodes.count == 2)

        // Pulling to refresh does.
        await service.refreshSubscribedFeeds(force: true)
        #expect(service.podcastShows.first { $0.feedURL == url }?.episodes.first?.title == "Wednesday")
    }
}

// MARK: - Waiting With a Limit

@Suite("Access recovery timing")
@MainActor
struct AccessRecoveryTimingTests {

    /// LYRE-5: "Access Restored" waited for a library load through every retry.
    @Test func aSlowOperationIsWaitedForNoLongerThanTheLimit() async {
        let start = ContinuousClock.now
        var finished = false
        await MusicService.awaitAtMost(.milliseconds(200)) {
            try? await Task.sleep(for: .seconds(5))
            finished = true
        }
        let waited = ContinuousClock.now - start
        #expect(waited < .seconds(2), "Waited \(waited)")
        #expect(!finished, "The operation should still be running")
    }

    @Test func aQuickOperationIsWaitedForToTheEnd() async {
        let start = ContinuousClock.now
        var finished = false
        await MusicService.awaitAtMost(.seconds(5)) {
            try? await Task.sleep(for: .milliseconds(100))
            finished = true
        }
        #expect(finished)
        #expect(ContinuousClock.now - start < .seconds(2))
    }

    @Test func theRecoveryScreenWaitsOnlyAFewSeconds() {
        #expect(MusicService.recoveryReloadLimit <= .seconds(5))
    }
}
