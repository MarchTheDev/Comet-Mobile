//
//  EPUB.swift
//  Comet
//
//  Books are zip files full of XHTML. This reads the container, the package
//  document and the spine with a small, read-only zip reader, then hands the
//  reader one chapter's HTML at a time with its images inlined as data URLs.
//
//  Read-only is the point: nothing here writes to a book, and nothing in a book
//  is ever evaluated — scripts are dropped before the HTML reaches the web view.
//

import Foundation
import Compression
import SwiftUI
import UIKit

struct ZipEntry {
    let name: String
    let method: UInt16
    let compressedSize: Int
    let uncompressedSize: Int
    let localOffset: Int
}

struct ZipArchive {
    let data: Data
    private(set) var entries: [String: ZipEntry] = [:]

    init?(data: Data) {
        self.data = data
        guard let directory = ZipArchive.endOfDirectory(data) else { return nil }
        var cursor = directory.centralOffset
        var count = 0
        while cursor + 46 <= data.count, count < directory.count {
            guard data.uint32(at: cursor) == 0x02014b50 else { break }
            let method = data.uint16(at: cursor + 10)
            let compressed = Int(data.uint32(at: cursor + 20))
            let uncompressed = Int(data.uint32(at: cursor + 24))
            let nameLength = Int(data.uint16(at: cursor + 28))
            let extraLength = Int(data.uint16(at: cursor + 30))
            let commentLength = Int(data.uint16(at: cursor + 32))
            let localOffset = Int(data.uint32(at: cursor + 42))
            guard cursor + 46 + nameLength <= data.count else { break }
            let nameData = data.subdata(in: (cursor + 46)..<(cursor + 46 + nameLength))
            let name = String(data: nameData, encoding: .utf8) ?? ""
            if !name.isEmpty {
                entries[name] = ZipEntry(name: name, method: method, compressedSize: compressed,
                                         uncompressedSize: uncompressed, localOffset: localOffset)
            }
            cursor += 46 + nameLength + extraLength + commentLength
            count += 1
        }
        guard !entries.isEmpty else { return nil }
    }

    private static func endOfDirectory(_ data: Data) -> (count: Int, centralOffset: Int)? {
        guard data.count >= 22 else { return nil }
        let lowest = max(0, data.count - 66_000)
        var cursor = data.count - 22
        while cursor >= lowest {
            if data.uint32(at: cursor) == 0x06054b50 {
                let count = Int(data.uint16(at: cursor + 10))
                let offset = Int(data.uint32(at: cursor + 16))
                return (count, offset)
            }
            cursor -= 1
        }
        return nil
    }

    func contains(_ name: String) -> Bool { entries[name] != nil }

    func read(_ name: String) -> Data? {
        guard let entry = entries[name], entry.localOffset + 30 <= data.count else { return nil }
        guard data.uint32(at: entry.localOffset) == 0x04034b50 else { return nil }
        let nameLength = Int(data.uint16(at: entry.localOffset + 26))
        let extraLength = Int(data.uint16(at: entry.localOffset + 28))
        let start = entry.localOffset + 30 + nameLength + extraLength
        guard start <= data.count else { return nil }
        let end = min(data.count, start + entry.compressedSize)
        guard start < end else { return Data() }
        let payload = data.subdata(in: start..<end)
        switch entry.method {
        case 0:
            return payload
        case 8:
            return ZipArchive.inflate(payload, expected: entry.uncompressedSize)
        default:
            return nil
        }
    }

    func text(_ name: String) -> String? {
        guard let bytes = read(name) else { return nil }
        return String(data: bytes, encoding: .utf8)
    }

    /// ZIP entries hold raw DEFLATE, which is what COMPRESSION_ZLIB decodes.
    private static func inflate(_ input: Data, expected: Int) -> Data? {
        guard !input.isEmpty else { return Data() }
        let capacity = max(expected, input.count * 4, 1)
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { destination -> Int in
            input.withUnsafeBytes { source -> Int in
                guard let destinationAddress = destination.bindMemory(to: UInt8.self).baseAddress,
                      let sourceAddress = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    destinationAddress, capacity,
                    sourceAddress, input.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { return nil }
        output.removeSubrange(written..<output.count)
        return output
    }
}

private extension Data {
    func uint16(at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { return 0 }
        return withUnsafeBytes { buffer -> UInt16 in
            let base = buffer.bindMemory(to: UInt8.self)
            return UInt16(base[offset]) | (UInt16(base[offset + 1]) << 8)
        }
    }

    func uint32(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        return withUnsafeBytes { buffer -> UInt32 in
            let base = buffer.bindMemory(to: UInt8.self)
            return UInt32(base[offset])
                | (UInt32(base[offset + 1]) << 8)
                | (UInt32(base[offset + 2]) << 16)
                | (UInt32(base[offset + 3]) << 24)
        }
    }
}

// MARK: - Book

struct BookChapter: Identifiable, Hashable {
    let id: String
    let title: String
    let href: String
}

struct Book {
    let title: String
    let author: String
    let chapters: [BookChapter]
    let archive: ZipArchive
    let rootDirectory: String

    static func open(url: URL) -> Book? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let archive = ZipArchive(data: data),
              let container = archive.text("META-INF/container.xml"),
              let packagePath = XML.firstAttributeValue(in: container, element: "rootfile", attribute: "full-path"),
              let package = archive.text(packagePath) else { return nil }

        let rootDirectory: String = {
            let parent = (packagePath as NSString).deletingLastPathComponent
            return parent == "." ? "" : parent
        }()

        let title = XML.firstElementText(in: package, element: "dc:title")
            ?? XML.firstElementText(in: package, element: "title")
            ?? url.deletingPathExtension().lastPathComponent
        let author = XML.firstElementText(in: package, element: "dc:creator")
            ?? XML.firstElementText(in: package, element: "creator")
            ?? ""

        // Manifest: id -> href
        var manifest: [String: String] = [:]
        for attributes in XML.attributes(in: package, element: "item") {
            if let id = attributes["id"], let href = attributes["href"] {
                manifest[id] = href
            }
        }

        // Spine order
        var spineIDs: [String] = []
        for attributes in XML.attributes(in: package, element: "itemref") {
            if let idref = attributes["idref"] { spineIDs.append(idref) }
        }

        // Titles, from the navigation document when there is one.
        var titles: [String: String] = [:]
        let navHref = XML.attributes(in: package, element: "item")
            .first { ($0["properties"] ?? "").contains("nav") }?["href"]
        if let navHref, let nav = archive.text(join(rootDirectory, navHref)) {
            for attributes in XML.attributes(in: nav, element: "a") {
                if let href = attributes["href"] {
                    let key = href.components(separatedBy: "#").first ?? href
                    let text = XML.text(of: attributes, in: nav)
                    if !text.isEmpty { titles[normalize(key)] = text }
                }
            }
        }
        if titles.isEmpty {
            for attributes in XML.attributes(in: package, element: "navPoint") {
                if let src = attributes["src"] {
                    let text = XML.text(of: attributes, in: package)
                    if !text.isEmpty { titles[normalize(src)] = text }
                }
            }
        }

        var chapters: [BookChapter] = []
        for (index, id) in spineIDs.enumerated() {
            guard let href = manifest[id] else { continue }
            let full = join(rootDirectory, href)
            guard archive.contains(full) else { continue }
            let label = titles[normalize(href)] ?? "Chapter \(index + 1)"
            chapters.append(BookChapter(id: full, title: label, href: href))
        }
        guard !chapters.isEmpty else { return nil }

        return Book(title: title, author: author, chapters: chapters, archive: archive, rootDirectory: rootDirectory)
    }

    /// One chapter as a self-contained HTML document, images inlined.
    func html(for chapter: BookChapter, theme: CometTheme, textScale: Double) -> String {
        guard let raw = archive.text(chapter.id) else {
            return "<!doctype html><html><body><p>This chapter could not be read.</p></body></html>"
        }
        let body = HTML.body(of: raw)
        let withImages = inlineImages(in: body, chapterDirectory: (chapter.id as NSString).deletingLastPathComponent)
        let styles = """
        :root { color-scheme: \(theme.isDark ? "dark" : "light"); }
        body {
          margin: 0; padding: 28px 22px 72px;
          font: \(Int(18 * textScale))px/1.72 -apple-system, "New York", Georgia, serif;
          color: \(theme.ink.cssHex);
          background: transparent;
          -webkit-text-size-adjust: 100%;
        }
        h1, h2, h3, h4 { font-family: -apple-system, "SF Pro Rounded", sans-serif; line-height: 1.25; color: \(theme.ink.cssHex); }
        h1 { font-size: 1.55em; } h2 { font-size: 1.3em; } h3 { font-size: 1.12em; }
        p { margin: 0 0 1em; }
        a { color: \(theme.accent.cssHex); text-decoration: none; }
        img, svg { max-width: 100%; height: auto; border-radius: 12px; }
        blockquote { margin: 0 0 1em; padding-left: 14px; border-left: 3px solid \(theme.accent.cssHex); color: \(theme.secondary.cssHex); }
        pre, code { font-family: ui-monospace, Menlo, monospace; font-size: 0.9em; background: \(theme.raised.cssHex); border-radius: 8px; }
        pre { padding: 12px; overflow-x: auto; }
        hr { border: 0; border-top: 1px solid \(theme.hairline.cssHex); }
        figure { margin: 0 0 1em; }
        figcaption { font-size: 0.82em; color: \(theme.secondary.cssHex); }
        """
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>\(styles)</style></head><body>\(withImages)</body></html>
        """
    }

    private func inlineImages(in html: String, chapterDirectory: String) -> String {
        var output = html
        let pattern = "<img([^>]*?)src\\s*=\\s*[\"']([^\"']+)[\"']([^>]*)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return html }
        let matches = regex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))
        for match in matches.reversed() {
            guard match.numberOfRanges >= 3,
                  let whole = Range(match.range(at: 0), in: html),
                  let sourceRange = Range(match.range(at: 2), in: html) else { continue }
            let source = String(html[sourceRange])
            guard !source.hasPrefix("data:"), !source.hasPrefix("http") else { continue }
            let decoded = source.removingPercentEncoding ?? source
            let path = normalizedPath(decoded, relativeTo: chapterDirectory)
            guard let bytes = archive.read(path) else { continue }
            let mime = mimeType(for: path)
            let replacement = "<img src=\"data:\(mime);base64,\(bytes.base64EncodedString())\" alt=\"\" />"
            output.replaceSubrange(whole, with: replacement)
        }
        return output
    }

    private func mimeType(for path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        default: return "image/jpeg"
        }
    }

    private func normalizedPath(_ href: String, relativeTo directory: String) -> String {
        let combined = join(directory, href)
        var parts: [String] = []
        for piece in combined.components(separatedBy: "/") {
            if piece.isEmpty || piece == "." { continue }
            if piece == ".." { if !parts.isEmpty { parts.removeLast() }; continue }
            parts.append(piece)
        }
        return parts.joined(separator: "/")
    }
}

private func join(_ directory: String, _ href: String) -> String {
    if directory.isEmpty { return href }
    if href.hasPrefix("/") { return String(href.dropFirst()) }
    return directory + "/" + href
}

private func normalize(_ href: String) -> String {
    let decoded = href.removingPercentEncoding ?? href
    let trimmed = decoded.components(separatedBy: "#").first ?? decoded
    var parts: [String] = []
    for piece in trimmed.components(separatedBy: "/") {
        if piece.isEmpty || piece == "." { continue }
        if piece == ".." { if !parts.isEmpty { parts.removeLast() }; continue }
        parts.append(piece)
    }
    return parts.joined(separator: "/")
}

// MARK: - Small XML helpers

enum XML {
    static func firstAttributeValue(in text: String, element: String, attribute: String) -> String? {
        for values in attributes(in: text, element: element) {
            if let value = values[attribute] { return value }
        }
        return nil
    }

    static func firstElementText(in text: String, element: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "<\(NSRegularExpression.escapedPattern(for: element))[^>]*>(.*?)</\(NSRegularExpression.escapedPattern(for: element))>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }
        guard let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return HTML.decode(String(text[range])).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Attribute dictionaries for every occurrence of an element.
    static func attributes(in text: String, element: String) -> [[String: String]] {
        guard let regex = try? NSRegularExpression(
            pattern: "<\(NSRegularExpression.escapedPattern(for: element))\\b([^>]*)>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        return regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
            return parseAttributes(String(text[range]))
        }
    }

    static func parseAttributes(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        guard let regex = try? NSRegularExpression(
            pattern: "([a-zA-Z_:][-a-zA-Z0-9_:.]*)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')",
            options: []
        ) else { return result }
        for match in regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text)) {
            guard match.numberOfRanges >= 3,
                  let keyRange = Range(match.range(at: 1), in: text) else { continue }
            let key = String(text[keyRange]).lowercased()
            let valueRange = Range(match.range(at: 2), in: text) ?? Range(match.range(at: 3), in: text)
            let value = valueRange.map { String(text[$0]) } ?? ""
            result[key] = value
        }
        return result
    }

    /// Text near a match: used for table-of-contents labels.
    static func text(of attributes: [String: String], in text: String) -> String {
        guard let anchor = attributes["href"] ?? attributes["src"] else { return "" }
        guard let regex = try? NSRegularExpression(
            pattern: "<a[^>]*" + NSRegularExpression.escapedPattern(for: anchor) + "[^>]*>(.*?)</a>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return "" }
        guard let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return "" }
        return HTML.decode(HTML.stripTags(String(text[range]))).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum HTML {
    static func body(of document: String) -> String {
        if let regex = try? NSRegularExpression(pattern: "<body[^>]*>(.*?)</body>", options: [.caseInsensitive, .dotMatchesLineSeparators]),
           let match = regex.firstMatch(in: document, options: [], range: NSRange(document.startIndex..., in: document)),
           match.numberOfRanges > 1,
           let range = Range(match.range(at: 1), in: document) {
            return stripActiveContent(String(document[range]))
        }
        return stripActiveContent(document)
    }

    static func stripActiveContent(_ html: String) -> String {
        var output = html
        let patterns = [
            "<script[^>]*>.*?</script>",
            "<style[^>]*>.*?</style>",
            "<iframe[^>]*>.*?</iframe>",
            "<object[^>]*>.*?</object>",
            "<embed[^>]*>",
            "\\s(on[a-z]+)\\s*=\\s*\"[^\"]*\"",
            "\\s(on[a-z]+)\\s*=\\s*'[^']*'",
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { continue }
            output = regex.stringByReplacingMatches(in: output, options: [], range: NSRange(output.startIndex..., in: output), withTemplate: "")
        }
        return output
    }

    static func stripTags(_ html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: [.dotMatchesLineSeparators]) else { return html }
        return regex.stringByReplacingMatches(in: html, options: [], range: NSRange(html.startIndex..., in: html), withTemplate: "")
    }

    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var value = text
        let named: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'",
            "&nbsp;": " ", "&mdash;": "—", "&ndash;": "–", "&hellip;": "…", "&rsquo;": "’", "&lsquo;": "‘",
            "&ldquo;": "“", "&rdquo;": "”",
        ]
        for (key, replacement) in named {
            value = value.replacingOccurrences(of: key, with: replacement)
        }
        if let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);", options: []) {
            let matches = regex.matches(in: value, options: [], range: NSRange(value.startIndex..., in: value))
            for match in matches.reversed() {
                guard match.numberOfRanges >= 3,
                      let whole = Range(match.range(at: 0), in: value),
                      let hexRange = Range(match.range(at: 1), in: value),
                      let digitsRange = Range(match.range(at: 2), in: value) else { continue }
                let radix = value[hexRange].isEmpty ? 10 : 16
                if let code = UInt32(value[digitsRange], radix: radix), let scalar = Unicode.Scalar(code) {
                    value.replaceSubrange(whole, with: String(Character(scalar)))
                }
            }
        }
        return value
    }
}

// MARK: - CSS colour

extension Color {
    /// A CSS `#RRGGBB` for the few places HTML needs a colour.
    var cssHex: String {
        let ui = UIColor(self)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard ui.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return "#000000" }
        return String(format: "#%02X%02X%02X",
                      Int(round(red * 255)), Int(round(green * 255)), Int(round(blue * 255)))
    }
}
