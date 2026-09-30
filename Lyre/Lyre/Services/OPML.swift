//
//  OPML.swift
//  Lyre
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - OPML
//
// OPML is the file every podcast app exports its subscriptions as: an outline whose
// entries carry each show's feed URL in `xmlUrl`. Importing one moves a user's shows
// over from another app in one go; exporting does the reverse.

nonisolated enum OPML {
    static let contentType = UTType(filenameExtension: "opml", conformingTo: .xml) ?? .xml

    /// Every feed URL in the document, in order, without duplicates.
    static func feedURLs(in data: Data) -> [URL] {
        let reader = OutlineReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.parse()
        var seen = Set<URL>()
        return reader.urls.filter { seen.insert($0).inserted }
    }

    static func document(for feeds: [FeedShow]) -> String {
        let outlines = feeds.map { feed in
            #"    <outline type="rss" text="\#(escape(feed.title))" title="\#(escape(feed.title))" xmlUrl="\#(escape(feed.feedURL.absoluteString))"/>"#
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head>
            <title>Lyre Podcast Subscriptions</title>
          </head>
          <body>
        \(outlines.joined(separator: "\n"))
          </body>
        </opml>
        """
    }

    private static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private final class OutlineReader: NSObject, XMLParserDelegate {
        var urls: [URL] = []

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            guard name.lowercased() == "outline",
                  let value = attributes["xmlUrl"] ?? attributes["xmlurl"],
                  let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
                  url.scheme?.hasPrefix("http") == true else { return }
            urls.append(url)
        }
    }
}

/// Wraps an OPML export for `fileExporter`.
struct OPMLDocument: FileDocument {
    static var readableContentTypes: [UTType] { [OPML.contentType, .xml] }

    let text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
