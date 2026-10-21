//
//  UITestNetwork.swift
//  Lyre
//

import Foundation

#if DEBUG

// MARK: - UI Test Network
//
// Puts the app's own network requests (podcast search and feeds, which go through
// URLSession.shared) into a known state for a UI test, since a simulator can't be taken
// offline from inside a test:
//
//   -UITestNetwork offline       every request fails as if there were no connection
//   -UITestNetwork serverError   every request gets an HTTP 503
//   -UITestNetwork stub          the directory and feeds answer with canned shows
//
// MusicKit and AVPlayer don't use URLSession.shared, so Apple Music and episode audio
// are untouched. Debug builds only.

nonisolated final class UITestNetwork: URLProtocol {
    enum Mode: String {
        case offline
        case serverError
        case stub
    }

    private static var mode: Mode = .stub

    /// The feed the stubbed directory lists, and that a test can paste.
    static let stubFeedURL = URL(string: "https://feeds.lyre.test/morning-somewhere.xml")!

    static func install(from defaults: UserDefaults) {
        guard let value = defaults.string(forKey: "UITestNetwork"), let mode = Mode(rawValue: value) else { return }
        self.mode = mode
        URLProtocol.registerClass(UITestNetwork.self)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme?.hasPrefix("http") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        switch Self.mode {
        case .offline:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        case .serverError:
            respond(url, status: 503, body: Data())
        case .stub:
            if url.host() == "itunes.apple.com" {
                respond(url, status: 200, body: Data(Self.searchJSON.utf8))
            } else if url == Self.stubFeedURL {
                respond(url, status: 200, body: Data(Self.feedXML.utf8))
            } else {
                respond(url, status: 404, body: Data())
            }
        }
    }

    override func stopLoading() {}

    private func respond(_ url: URL, status: Int, body: Data) {
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static let searchJSON = """
    {"resultCount": 2, "results": [
      {"collectionName": "Morning Somewhere", "artistName": "Lyre Test Radio",
       "feedUrl": "\(stubFeedURL.absoluteString)"},
      {"collectionName": "No Public Feed", "artistName": "Nobody"}
    ]}
    """

    private static let feedXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
      <channel>
        <title>Morning Somewhere</title>
        <itunes:author>Lyre Test Radio</itunes:author>
        <item>
          <title>Tuesday</title>
          <guid>morning-tuesday</guid>
          <pubDate>Tue, 02 Jun 2026 06:00:00 +0000</pubDate>
          <itunes:duration>12:30</itunes:duration>
          <enclosure url="https://feeds.lyre.test/tuesday.mp3" type="audio/mpeg"/>
        </item>
        <item>
          <title>Monday</title>
          <guid>morning-monday</guid>
          <pubDate>Mon, 01 Jun 2026 06:00:00 +0000</pubDate>
          <itunes:duration>750</itunes:duration>
          <enclosure url="https://feeds.lyre.test/monday.mp3" type="audio/mpeg"/>
        </item>
      </channel>
    </rss>
    """
}

#endif
