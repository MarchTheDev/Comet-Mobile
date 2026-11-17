//
//  Markdown.swift
//  Comet
//
//  Comet's notes are Markdown files, and this is the subset the reader and the
//  editor agree on: headings, lists (including checkbox lists), quotes, fenced
//  code, rules, tables, links, emphasis and images. It parses to data, never to
//  HTML, so a note cannot inject anything into the reader.
//

import Foundation

enum Inline: Hashable {
    case text(String)
    case strong(String)
    case emphasis(String)
    case strike(String)
    case code(String)
    case link(label: String, href: String)
    case image(alt: String, src: String)
    case br

    var plain: String {
        switch self {
        case .text(let value), .strong(let value), .emphasis(let value),
             .strike(let value), .code(let value):
            return value
        case .link(let label, _):
            return label
        case .image(let alt, _):
            return alt
        case .br:
            return "\n"
        }
    }
}

struct ListItem: Hashable {
    var inlines: [Inline]
    var box: Bool = false
    var done: Bool = false
    var number: Int? = nil
}

enum Block: Hashable {
    case heading(level: Int, inlines: [Inline])
    case paragraph([Inline])
    case bullets([ListItem])
    case numbered([ListItem])
    case quote([Inline])
    case code(language: String, text: String)
    case rule
    case image(alt: String, src: String)
    case table(header: [String], rows: [[String]])
}

enum Markdown {
    static func blocks(_ text: String) -> [Block] {
        var out: [Block] = []
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var index = 0
        var paragraph: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            out.append(.paragraph(inline(paragraph.joined(separator: " "))))
            paragraph = []
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code
            if trimmed.hasPrefix("```") {
                flushParagraph()
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                index += 1
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    if candidate.hasPrefix("```") { index += 1; break }
                    body.append(lines[index])
                    index += 1
                }
                out.append(.code(language: language, text: body.joined(separator: "\n")))
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if isRule(trimmed) {
                flushParagraph()
                out.append(.rule)
                index += 1
                continue
            }

            if let heading = headingMatch(trimmed) {
                flushParagraph()
                out.append(.heading(level: heading.level, inlines: inline(heading.text)))
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoted: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    quoted.append(String(candidate.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                out.append(.quote(inline(quoted.joined(separator: " "))))
                continue
            }

            if let bullet = bulletMatch(trimmed) {
                flushParagraph()
                var items: [ListItem] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard let next = bulletMatch(candidate) else { break }
                    var item = ListItem(inlines: inline(next))
                    if next.hasPrefix("[ ] ") || next.lowercased().hasPrefix("[x] ") {
                        item.box = true
                        item.done = next.lowercased().hasPrefix("[x] ")
                        let content = String(next.dropFirst(4))
                        item.inlines = inline(content)
                    }
                    items.append(item)
                    index += 1
                }
                out.append(.bullets(items))
                continue
            }

            if let numbered = numberedMatch(trimmed) {
                flushParagraph()
                var items: [ListItem] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard let next = numberedMatch(candidate) else { break }
                    items.append(ListItem(inlines: inline(next.text), number: next.number))
                    index += 1
                }
                out.append(.numbered(items))
                continue
            }

            if trimmed.contains("|"), index + 1 < lines.count, isTableSeparator(lines[index + 1]) {
                flushParagraph()
                let header = cells(trimmed)
                var rows: [[String]] = []
                index += 2
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.contains("|"), !candidate.isEmpty else { break }
                    rows.append(cells(candidate))
                    index += 1
                }
                out.append(.table(header: header, rows: rows))
                continue
            }

            if let image = standaloneImage(trimmed) {
                flushParagraph()
                out.append(.image(alt: image.alt, src: image.src))
                index += 1
                continue
            }

            paragraph.append(trimmed)
            index += 1
        }

        flushParagraph()
        return out
    }

    /// The first heading, or the first line, as a title for lists and previews.
    static func title(of text: String, fallback: String) -> String {
        for block in blocks(text) {
            switch block {
            case .heading(_, let inlines):
                let value = plainText(inlines)
                if !value.isEmpty { return value }
            case .paragraph(let inlines):
                let value = plainText(inlines)
                if !value.isEmpty { return value }
            default:
                continue
            }
        }
        return fallback
    }

    /// A one-line summary with the syntax taken out.
    static func plainSummary(of text: String, limit: Int = 160) -> String {
        var pieces: [String] = []
        for block in blocks(text) {
            switch block {
            case .heading(_, let inlines), .paragraph(let inlines), .quote(let inlines):
                pieces.append(plainText(inlines))
            case .bullets(let items), .numbered(let items):
                pieces.append(contentsOf: items.map { plainText($0.inlines) })
            default:
                continue
            }
            if pieces.joined(separator: " ").count > limit { break }
        }
        let joined = pieces.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if joined.count <= limit { return joined }
        return String(joined.prefix(limit)) + "…"
    }

    static func plainText(_ inlines: [Inline]) -> String {
        inlines.map { $0.plain }.joined()
    }

    // MARK: - Inline parsing

    static func inline(_ text: String) -> [Inline] {
        guard !text.isEmpty else { return [] }
        var result: [Inline] = []
        var buffer = ""
        var index = text.startIndex

        func flush() {
            guard !buffer.isEmpty else { return }
            result.append(.text(buffer))
            buffer = ""
        }

        while index < text.endIndex {
            let rest = text[index...]

            if rest.hasPrefix("!["), let match = matchLink(text, at: index, image: true) {
                flush()
                result.append(.image(alt: match.label, src: match.href))
                index = match.end
                continue
            }

            if rest.hasPrefix("["), let match = matchLink(text, at: index, image: false) {
                flush()
                result.append(.link(label: match.label, href: match.href))
                index = match.end
                continue
            }

            if rest.hasPrefix("<http"), let close = rest.firstIndex(of: ">") {
                let href = String(rest[rest.index(after: rest.startIndex)..<close])
                flush()
                result.append(.link(label: href, href: href))
                index = text.index(after: close)
                continue
            }

            if rest.hasPrefix("http://") || rest.hasPrefix("https://") {
                var end = index
                while end < text.endIndex, !text[end].isWhitespace, text[end] != ")" {
                    end = text.index(after: end)
                }
                var href = String(text[index..<end])
                while href.hasSuffix(".") || href.hasSuffix(",") || href.hasSuffix(";") {
                    href.removeLast()
                    end = text.index(before: end)
                }
                if href.count > 8 {
                    flush()
                    result.append(.link(label: href, href: href))
                    index = end
                    continue
                }
            }

            if let match = matchDelimited(text, at: index, marker: "***") {
                flush()
                result.append(.strong(match.value))
                index = match.end
                continue
            }
            if let match = matchDelimited(text, at: index, marker: "**") {
                flush()
                result.append(.strong(match.value))
                index = match.end
                continue
            }
            if let match = matchDelimited(text, at: index, marker: "__") {
                flush()
                result.append(.emphasis(match.value))
                index = match.end
                continue
            }
            if let match = matchDelimited(text, at: index, marker: "~~") {
                flush()
                result.append(.strike(match.value))
                index = match.end
                continue
            }
            if let match = matchDelimited(text, at: index, marker: "||") {
                flush()
                result.append(.strike(match.value))
                index = match.end
                continue
            }
            if let match = matchDelimited(text, at: index, marker: "`") {
                flush()
                result.append(.code(match.value))
                index = match.end
                continue
            }
            if let match = matchDelimited(text, at: index, marker: "*", avoidIntraWord: true) {
                flush()
                result.append(.emphasis(match.value))
                index = match.end
                continue
            }
            if let match = matchDelimited(text, at: index, marker: "_", avoidIntraWord: true) {
                flush()
                result.append(.emphasis(match.value))
                index = match.end
                continue
            }

            buffer.append(text[index])
            index = text.index(after: index)
        }

        flush()
        return result
    }

    private static func matchDelimited(
        _ text: String,
        at index: String.Index,
        marker: String,
        avoidIntraWord: Bool = false
    ) -> (value: String, end: String.Index)? {
        guard text[index...].hasPrefix(marker) else { return nil }
        if avoidIntraWord, marker.count == 1 {
            // Don't turn snake_case into emphasis.
            let previous = index > text.startIndex ? text[text.index(before: index)] : " "
            if previous.isLetter || previous.isNumber { return nil }
        }
        var cursor = text.index(index, offsetBy: marker.count)
        let contentStart = cursor
        while cursor < text.endIndex {
            let rest = text[cursor...]
            if rest.hasPrefix(marker) {
                // A single-character marker must not sit on a doubled marker.
                if marker == "*", rest.hasPrefix("**") { cursor = text.index(after: cursor); continue }
                if marker == "_", rest.hasPrefix("__") { cursor = text.index(after: cursor); continue }
                let value = String(text[contentStart..<cursor])
                if value.isEmpty { return nil }
                if avoidIntraWord, marker.count == 1 {
                    let after = text.index(after: cursor)
                    if after < text.endIndex, text[after].isLetter || text[after].isNumber { return nil }
                }
                return (value, text.index(cursor, offsetBy: marker.count))
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }

    private static func matchLink(
        _ text: String,
        at index: String.Index,
        image: Bool
    ) -> (label: String, href: String, end: String.Index)? {
        var cursor = index
        if image {
            guard text[cursor...].hasPrefix("![") else { return nil }
            cursor = text.index(cursor, offsetBy: 2)
        } else {
            guard text[cursor...].hasPrefix("[") else { return nil }
            cursor = text.index(after: cursor)
        }
        guard let closeBracket = text[cursor...].firstIndex(of: "]") else { return nil }
        let label = String(text[cursor..<closeBracket])
        let after = text.index(after: closeBracket)
        guard after < text.endIndex, text[after] == "(" else { return nil }
        guard let closeParen = text[text.index(after: after)...].firstIndex(of: ")") else { return nil }
        let href = String(text[text.index(after: after)..<closeParen]).trimmingCharacters(in: .whitespaces)
        guard !href.isEmpty else { return nil }
        return (label, href, text.index(after: closeParen))
    }

    // MARK: - Block helpers

    private static func headingMatch(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        var cursor = line.startIndex
        while cursor < line.endIndex, line[cursor] == "#", level < 6 {
            level += 1
            cursor = line.index(after: cursor)
        }
        guard level > 0, cursor < line.endIndex, line[cursor] == " " else { return nil }
        let text = String(line[line.index(after: cursor)...]).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (min(level, 4), text)
    }

    private static func bulletMatch(_ line: String) -> String? {
        guard line.count > 2 else { return nil }
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func numberedMatch(_ line: String) -> (number: Int, text: String)? {
        var digits = ""
        var cursor = line.startIndex
        while cursor < line.endIndex, line[cursor].isNumber, digits.count < 4 {
            digits.append(line[cursor])
            cursor = line.index(after: cursor)
        }
        guard !digits.isEmpty, cursor < line.endIndex else { return nil }
        guard line[cursor] == "." || line[cursor] == ")" else { return nil }
        let afterMarker = line.index(after: cursor)
        guard afterMarker < line.endIndex, line[afterMarker] == " " else { return nil }
        let text = String(line[line.index(after: afterMarker)...]).trimmingCharacters(in: .whitespaces)
        return (Int(digits) ?? 1, text)
    }

    private static func isRule(_ line: String) -> Bool {
        guard line.count >= 3 else { return false }
        let characters = Set(line)
        return characters.count == 1 && (characters.contains("-") || characters.contains("*") || characters.contains("_"))
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-") else { return false }
        let allowed = Set("-|: ")
        return trimmed.allSatisfy { allowed.contains($0) }
    }

    private static func cells(_ line: String) -> [String] {
        var body = line.trimmingCharacters(in: .whitespaces)
        if body.hasPrefix("|") { body.removeFirst() }
        if body.hasSuffix("|") { body.removeLast() }
        return body.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func standaloneImage(_ line: String) -> (alt: String, src: String)? {
        guard line.hasPrefix("!["), line.hasSuffix(")"),
              let closeBracket = line.firstIndex(of: "]"),
              line.index(after: closeBracket) < line.endIndex,
              line[line.index(after: closeBracket)] == "(" else { return nil }
        let alt = String(line[line.index(line.startIndex, offsetBy: 2)..<closeBracket])
        let src = String(line[line.index(closeBracket, offsetBy: 2)..<line.index(before: line.endIndex)])
        guard !src.isEmpty else { return nil }
        return (alt, src)
    }
}
