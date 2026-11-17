//
//  Feeds.swift
//  Comet
//
//  RSS, Atom and JSON feeds, read on the device with no service in between.
//  Two things matter here: the same feed URL must produce the same article IDs
//  every refresh (so read state survives), and a malformed feed must fail as a
//  feed rather than as a crash.
//

import Foundation

struct ParsedFeed {
    var title: String
    var articles: [FeedArticle]
}

enum FeedParser {
    static func parse(data: Data, feedID: String, fallbackTitle: String) -> ParsedFeed? {
        let trimmed = data.drop { $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 || $0 == 0xEF || $0 == 0xBB || $0 == 0xBF }
        if let first = trimmed.first, first == UInt8(ascii: "{") {
            return parseJSON(data: data, feedID: feedID, fallbackTitle: fallbackTitle)
        }
        let delegate = FeedXMLDelegate(feedID: feedID)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else { return nil }
        let title = delegate.feedTitle.isEmpty ? fallbackTitle : delegate.feedTitle
        return ParsedFeed(title: title, articles: delegate.articles)
    }

    private static func parseJSON(data: Data, feedID: String, fallbackTitle: String) -> ParsedFeed? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let title = (root["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackTitle
        let rawItems = root["items"] as? [[String: Any]] ?? []
        var articles: [FeedArticle] = []
        for item in rawItems.prefix(60) {
            let link = (item["url"] as? String) ?? (item["external_url"] as? String) ?? ""
            let name = (item["title"] as? String) ?? "Untitled"
            let content = (item["content_html"] as? String) ?? (item["content_text"] as? String) ?? ""
            let summary = (item["summary"] as? String) ?? HTMLText.plain(content, limit: 300)
            var author = ""
            if let authors = item["authors"] as? [[String: Any]], let first = authors.first {
                author = (first["name"] as? String) ?? ""
            }
            let published = (item["date_published"] as? String).flatMap(FeedDate.parse) ?? nil
            let identity = (item["id"] as? String) ?? link
            articles.append(FeedArticle(
                id: FeedID.article(feedID: feedID, identity: identity.isEmpty ? name : identity),
                feedID: feedID,
                title: name,
                link: link,
                summary: summary,
                content: content,
                author: author,
                published: published
            ))
        }
        return ParsedFeed(title: title, articles: articles)
    }
}

private final class FeedXMLDelegate: NSObject, XMLParserDelegate {
    let feedID: String
    var feedTitle = ""
    var articles: [FeedArticle] = []

    private struct Draft {
        var title = ""
        var link = ""
        var summary = ""
        var content = ""
        var author = ""
        var identity = ""
        var published: Date? = nil
    }

    private var draft: Draft?
    private var stack: [String] = []
    private var buffer = ""
    private var sawTitle = false

    init(feedID: String) {
        self.feedID = feedID
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        let name = FeedXMLDelegate.local(elementName)
        stack.append(name)
        buffer = ""

        switch name {
        case "item", "entry":
            draft = Draft()
        case "link":
            let href = attributeDict["href"] ?? attributeDict["url"] ?? ""
            let rel = attributeDict["rel"] ?? "alternate"
            if !href.isEmpty, rel == "alternate" || rel.isEmpty {
                if draft != nil { draft?.link = href } else { feedTitle = feedTitle.isEmpty ? feedTitle : feedTitle }
            }
        case "title":
            sawTitle = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let text = String(data: CDATABlock, encoding: .utf8) { buffer += text }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let name = FeedXMLDelegate.local(elementName)
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            if !stack.isEmpty { stack.removeLast() }
            buffer = ""
        }

        if draft == nil {
            if name == "title", feedTitle.isEmpty, !text.isEmpty {
                feedTitle = FeedXMLDelegate.decodeEntities(text)
            }
            return
        }

        switch name {
        case "item", "entry":
            guard let finished = draft else { return }
            draft = nil
            let title = FeedXMLDelegate.decodeEntities(finished.title)
            guard !title.isEmpty || !finished.link.isEmpty else { return }
            let identity = finished.identity.isEmpty ? finished.link : finished.identity
            let identifier = FeedID.article(feedID: feedID,
                                            identity: identity.isEmpty ? title : identity)
            let html = finished.content.isEmpty ? finished.summary : finished.content
            articles.append(FeedArticle(
                id: identifier,
                feedID: feedID,
                title: title.isEmpty ? "Untitled" : title,
                link: finished.link,
                summary: HTMLText.plain(finished.summary, limit: 320),
                content: html,
                author: FeedXMLDelegate.decodeEntities(finished.author),
                published: finished.published
            ))
        case "title":
            if draft?.title.isEmpty == true { draft?.title = text }
            else if feedTitle.isEmpty, !sawTitle { feedTitle = text }
        case "link":
            if draft?.link.isEmpty == true, !text.isEmpty { draft?.link = text }
        case "description", "summary":
            if draft?.summary.isEmpty == true { draft?.summary = text }
            else if draft?.content.isEmpty == true { draft?.content = text }
        case "encoded", "content":
            if draft?.content.isEmpty == true { draft?.content = text }
        case "pubdate", "published", "updated", "issued", "date":
            if draft?.published == nil, let parsed = FeedDate.parse(text) {
                draft?.published = parsed
            }
        case "guid", "id":
            if draft?.identity.isEmpty == true { draft?.identity = text }
        case "name":
            if draft?.author.isEmpty == true { draft?.author = text }
        case "author":
            if draft?.author.isEmpty == true { draft?.author = text }
        default:
            break
        }
    }

    private static func local(_ name: String) -> String {
        let lower = name.lowercased()
        if let colon = lower.lastIndex(of: ":") {
            return String(lower[lower.index(after: colon)...])
        }
        return lower
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var value = text
        let map: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&apos;": "'", "&#39;": "'", "&nbsp;": " ", "&mdash;": "—", "&ndash;": "–",
        ]
        for (key, replacement) in map {
            value = value.replacingOccurrences(of: key, with: replacement)
        }
        return value
    }
}

enum FeedID {
    static func article(feedID: String, identity: String) -> String {
        Digest.of(feedID + "|" + identity)
    }
    static func new() -> String { UUID().uuidString }
}

enum FeedDate {
    static func parse(_ raw: String) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let iso = ISO8601DateFormatter().date(from: text) { return iso }
        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let iso = isoFractional.date(from: text) { return iso }
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEE, d MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm Z",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd",
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}

/// HTML in a feed is shown as text, never executed. This strips tags and keeps
/// the words, with a limit so a huge article cannot stall a list row.
enum HTMLText {
    static func plain(_ html: String, limit: Int = 400) -> String {
        guard !html.isEmpty else { return "" }
        var output = ""
        var insideTag = false
        var lastWasSpace = false
        for character in html {
            if character == "<" { insideTag = true; continue }
            if character == ">" {
                insideTag = false
                if !lastWasSpace { output.append(" "); lastWasSpace = true }
                continue
            }
            guard !insideTag else { continue }
            if character == "\n" || character == "\t" {
                if !lastWasSpace { output.append(" "); lastWasSpace = true }
                continue
            }
            if character == " " {
                if !lastWasSpace { output.append(character); lastWasSpace = true }
                continue
            }
            output.append(character)
            lastWasSpace = false
            if output.count > limit + 80 { break }
        }
        let collapsed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.count <= limit { return FeedXMLDelegate.decodeEntities(collapsed) }
        return FeedXMLDelegate.decodeEntities(String(collapsed.prefix(limit))) + "…"
    }
}

// MARK: - OPML

enum OPML {
    static func importFeeds(_ data: Data) -> [(title: String, url: String)] {
        let delegate = OPMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        _ = parser.parse()
        return delegate.feeds
    }

    static func export(_ feeds: [Feed]) -> String {
        var lines = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<opml version=\"2.0\">",
            "  <head><title>Comet feeds</title></head>",
            "  <body>",
        ]
        for feed in feeds {
            let title = escape(feed.title)
            let url = escape(feed.url)
            lines.append("    <outline type=\"rss\" text=\"\(title)\" title=\"\(title)\" xmlUrl=\"\(url)\" />")
        }
        lines.append("  </body>")
        lines.append("</opml>")
        return lines.joined(separator: "\n")
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private final class OPMLDelegate: NSObject, XMLParserDelegate {
        var feeds: [(title: String, url: String)] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String]) {
            guard let url = attributeDict["xmlUrl"] ?? attributeDict["xmlurl"], !url.isEmpty else { return }
            let title = attributeDict["title"] ?? attributeDict["text"] ?? url
            feeds.append((title, url))
        }
    }
}

enum FeedAddress {
    /// A pasted address that is really a feed, or nil.
    static func normalize(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 2048, !text.contains(" ") else { return nil }
        if text.lowercased().hasPrefix("feed:") {
            text = String(text.dropFirst(5))
        }
        if !text.contains("://") {
            guard text.contains(".") else { return nil }
            text = "https://" + text
        }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, host.contains("."),
              url.user == nil, url.password == nil else { return nil }
        return url.absoluteString
    }

    static func host(_ raw: String) -> String {
        URL(string: raw)?.host ?? raw
    }
}
