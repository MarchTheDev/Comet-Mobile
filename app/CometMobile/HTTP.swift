//
//  HTTP.swift
//  Comet for iOS
//
//  The smallest HTTP/1.1 pieces the shell needs: parse one request, describe one
//  response, and resolve a byte range. Everything here is Foundation only and
//  free of side effects, so the awkward parts (ranges, framing, escaping) are
//  separable from the socket and the web view.
//

import Foundation

struct HTTPRequest {
    let method: String
    /// Percent-decoded path, always beginning with "/".
    let path: String
    /// Percent-decoded query values.
    let query: [String: String]
    /// Header names are lowercased.
    let headers: [String: String]
    let body: Data

    var isGetOrHead: Bool { method == "GET" || method == "HEAD" }
}

enum HTTPParseResult {
    case needMore
    case invalid(String)
    case complete(HTTPRequest)
}

enum HTTPParser {
    /// A request head larger than this is treated as hostile.
    static let maximumHeadBytes = 64 * 1024
    /// Comet sends a 16 MB note as JSON; leaving room for escaping keeps that
    /// possible while still refusing anything unbounded.
    static let maximumBodyBytes = 64 * 1024 * 1024

    private static let separator = Data("\r\n\r\n".utf8)

    static func parse(_ raw: Data) -> HTTPParseResult {
        // The receive loop builds every buffer from index zero; normalise anyway
        // so nothing downstream has to think about slice offsets.
        let data = raw.startIndex == 0 ? raw : Data(raw)

        guard let headEnd = data.range(of: separator) else {
            return data.count > maximumHeadBytes ? .invalid("The request head is too large.") : .needMore
        }
        guard let head = String(data: data[data.startIndex..<headEnd.lowerBound], encoding: .utf8) else {
            return .invalid("The request head is not UTF-8.")
        }

        var lines = head.components(separatedBy: "\r\n")
        guard let requestLine = lines.first, !requestLine.isEmpty else { return .invalid("The request line is missing.") }
        lines.removeFirst()

        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return .invalid("The request line is malformed.") }
        let method = String(parts[0]).uppercased()
        let target = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { headers[name] = value }
        }

        let declared = Int(headers["content-length"] ?? "0") ?? 0
        guard declared >= 0, declared <= maximumBodyBytes else {
            return .invalid("The request body is too large.")
        }

        let bodyStart = headEnd.upperBound
        guard data.count - (bodyStart - data.startIndex) >= declared else { return .needMore }
        let body = data.subdata(in: bodyStart..<(bodyStart + declared))

        let split = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let path = decode(String(split.first ?? "/")).isEmpty ? "/" : decode(String(split.first ?? "/"))
        var query: [String: String] = [:]
        if split.count > 1 {
            for pair in split[1].split(separator: "&") {
                let halves = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let key = decode(String(halves.first ?? ""))
                let value = halves.count > 1 ? decode(String(halves[1])) : ""
                if !key.isEmpty { query[key] = value }
            }
        }

        return .complete(HTTPRequest(method: method, path: path, query: query, headers: headers, body: body))
    }

    /// `removingPercentEncoding` is lenient about malformed sequences but
    /// returns nil for them; fall back to the raw text rather than failing.
    private static func decode(_ value: String) -> String {
        value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? value
    }
}

/// Where a response body comes from. Files are streamed so that a long video
/// never has to be held in memory, and so Range requests stay cheap.
enum HTTPBodySource {
    case data(Data)
    case file(url: URL, offset: UInt64, length: UInt64)

    var length: UInt64 {
        switch self {
        case .data(let data): return UInt64(data.count)
        case .file(_, _, let length): return length
        }
    }
}

struct HTTPResponse {
    var status: Int
    var headers: [String: String]
    var body: HTTPBodySource

    init(status: Int = 200, headers: [String: String] = [:], body: HTTPBodySource = .data(Data())) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    var reason: String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 206: return "Partial Content"
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 416: return "Range Not Satisfiable"
        case 500: return "Internal Server Error"
        case 503: return "Service Unavailable"
        default: return "OK"
        }
    }

    func serializedHead() -> Data {
        var merged = headers
        merged["Content-Length"] = String(body.length)
        merged["Connection"] = "close"
        merged["Server"] = "Comet"
        if merged["Cache-Control"] == nil { merged["Cache-Control"] = "no-store" }

        var text = "HTTP/1.1 \(status) \(reason)\r\n"
        for (name, value) in merged {
            text += "\(name): \(value)\r\n"
        }
        text += "\r\n"
        return Data(text.utf8)
    }
}

extension HTTPResponse {
    static func json(_ object: Any, status: Int = 200) -> HTTPResponse {
        let encoded = (try? JSONSerialization.data(withJSONObject: object, options: [])) ?? Data("{}".utf8)
        return HTTPResponse(status: status, headers: ["Content-Type": "application/json; charset=utf-8"], body: .data(encoded))
    }

    static func text(_ message: String, status: Int) -> HTTPResponse {
        HTTPResponse(status: status, headers: ["Content-Type": "text/plain; charset=utf-8"], body: .data(Data(message.utf8)))
    }

    /// Serves a file, honouring a single `Range` request. Media elements in
    /// WKWebView always ask for ranges, and refuse to seek without them.
    static func file(_ url: URL, contentType: String, rangeHeader: String?) -> HTTPResponse {
        let size: UInt64
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        if let number = attributes?[.size] as? NSNumber {
            size = number.uint64Value
        } else if let length = FileManager.default.fileSize(at: url) {
            size = length
        } else {
            return .text("Not found.", status: 404)
        }

        var headers: [String: String] = [
            "Content-Type": contentType,
            "Accept-Ranges": "bytes"
        ]
        switch ByteRange.resolve(rangeHeader, size: size) {
        case .unsatisfiable:
            headers["Content-Range"] = "bytes */\(size)"
            return HTTPResponse(status: 416, headers: headers, body: .data(Data()))
        case .partial(let offset, let length):
            headers["Content-Range"] = "bytes \(offset)-\(offset + length - 1)/\(size)"
            return HTTPResponse(status: 206, headers: headers, body: .file(url: url, offset: offset, length: length))
        case .full:
            return HTTPResponse(status: 200, headers: headers, body: .file(url: url, offset: 0, length: size))
        }
    }
}

private extension FileManager {
    /// `attributesOfItem` can fail for a file that exists but is being written;
    /// fall back to a plain stat through the URL resource values.
    func fileSize(at url: URL) -> UInt64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]), let size = values.fileSize else { return nil }
        return UInt64(size)
    }
}

enum ByteRange {
    enum Resolved {
        case full
        case partial(offset: UInt64, length: UInt64)
        case unsatisfiable
    }

    /// Parses `bytes=start-end`, `bytes=start-` and `bytes=-suffix`. Anything it
    /// cannot make sense of is ignored and the whole file is served, which is
    /// what RFC 9110 permits.
    static func resolve(_ header: String?, size: UInt64) -> Resolved {
        guard let header, !header.isEmpty else { return .full }
        let trimmed = header.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed.hasPrefix("bytes=") else { return .full }

        let specs = trimmed.dropFirst("bytes=".count).split(separator: ",")
        guard let first = specs.first else { return .full }
        let bounds = first.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard bounds.count == 2 else { return .full }

        let startText = bounds[0].trimmingCharacters(in: .whitespaces)
        let endText = bounds[1].trimmingCharacters(in: .whitespaces)

        if startText.isEmpty {
            // A suffix range: the last N bytes.
            guard let suffix = UInt64(endText), suffix > 0 else { return .full }
            guard size > 0 else { return .unsatisfiable }
            let length = min(suffix, size)
            return .partial(offset: size - length, length: length)
        }

        guard let start = UInt64(startText) else { return .full }
        guard start < size else { return .unsatisfiable }

        if endText.isEmpty {
            return .partial(offset: start, length: size - start)
        }
        guard let end = UInt64(endText), end >= start else { return .full }
        let clamped = min(end, size - 1)
        return .partial(offset: start, length: clamped - start + 1)
    }
}

enum MimeType {
    static func forPath(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "ico": return "image/x-icon"
        case "bmp": return "image/bmp"
        case "txt", "md", "markdown": return "text/plain; charset=utf-8"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "wasm": return "application/wasm"
        case "bcmap": return "application/octet-stream"
        case "pdf": return "application/pdf"
        case "epub": return "application/epub+zip"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        case "aac": return "audio/aac"
        case "wav": return "audio/wav"
        case "flac": return "audio/flac"
        case "ogg", "opus": return "audio/ogg"
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "webm": return "video/webm"
        case "ics": return "text/calendar; charset=utf-8"
        case "url": return "text/plain; charset=utf-8"
        case "comet-todo", "comet-whiteboard": return "application/json; charset=utf-8"
        default: return "application/octet-stream"
        }
    }
}
