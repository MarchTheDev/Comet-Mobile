//
//  Entry.swift
//  Comet
//
//  A workspace is a folder of ordinary files. This is what one row of it looks
//  like to the app, whichever view is drawing it.
//

import Foundation

enum EntryKind: String, Codable, CaseIterable, Hashable {
    case folder
    case note
    case todo
    case whiteboard
    case shortcut
    case image
    case pdf
    case epub
    case audio
    case video
    case archive
    case other

    var isFolder: Bool { self == .folder }

    var isText: Bool {
        switch self {
        case .note, .todo, .whiteboard, .shortcut: return true
        default: return false
        }
    }

    var isBoard: Bool { self == .todo || self == .whiteboard }

    var symbol: String {
        switch self {
        case .folder: return "folder.fill"
        case .note: return "doc.richtext"
        case .todo: return "checklist"
        case .whiteboard: return "scribble.variable"
        case .shortcut: return "link"
        case .image: return "photo"
        case .pdf: return "doc.richtext.fill"
        case .epub: return "book.closed"
        case .audio: return "waveform"
        case .video: return "play.rectangle.fill"
        case .archive: return "archivebox"
        case .other: return "doc"
        }
    }

    var displayLabel: String {
        switch self {
        case .folder: return "Folder"
        case .note: return "Note"
        case .todo: return "To-do board"
        case .whiteboard: return "Whiteboard"
        case .shortcut: return "Link"
        case .image: return "Image"
        case .pdf: return "PDF"
        case .epub: return "Book"
        case .audio: return "Audio"
        case .video: return "Video"
        case .archive: return "Archive"
        case .other: return "File"
        }
    }

    static func detect(name: String, isDirectory: Bool) -> EntryKind {
        guard !isDirectory else { return .folder }
        let lower = name.lowercased()
        if lower.hasSuffix(".md") || lower.hasSuffix(".markdown") || lower.hasSuffix(".txt") { return .note }
        if lower.hasSuffix(".comet-todo") { return .todo }
        if lower.hasSuffix(".comet-whiteboard") { return .whiteboard }
        if lower.hasSuffix(".url") { return .shortcut }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "bmp": return .image
        case "pdf": return .pdf
        case "epub": return .epub
        case "mp3", "m4a", "m4b", "wav", "aac", "flac", "aiff", "ogg", "opus": return .audio
        case "mp4", "mov", "m4v", "mkv", "webm", "avi": return .video
        case "zip", "tar", "gz", "7z", "rar", "bz2": return .archive
        default: return .other
        }
    }
}

struct Entry: Identifiable, Hashable {
    /// Slash-separated, relative to the workspace root. This is the app's
    /// identity for an item, and what organization is keyed by.
    let relativePath: String
    let name: String
    let kind: EntryKind
    let size: Int64
    let modified: Date
    let url: URL

    var id: String { relativePath }
    var isFolder: Bool { kind == .folder }
    var parentPath: String {
        let parent = (relativePath as NSString).deletingLastPathComponent
        return parent == "." ? "" : parent
    }
    var depth: Int {
        relativePath.split(separator: "/").count - 1
    }

    var displayName: String {
        switch kind {
        case .note, .todo, .whiteboard, .shortcut, .epub, .pdf:
            let stripped = (name as NSString).deletingPathExtension
            return stripped.isEmpty ? name : stripped
        default:
            return name
        }
    }

    var fileExtension: String { (name as NSString).pathExtension.lowercased() }

    var childrenDirectoryPath: String { relativePath }

    static func join(_ folder: String, _ name: String) -> String {
        folder.isEmpty ? name : "\(folder)/\(name)"
    }

    func isInside(_ path: String) -> Bool {
        relativePath == path || relativePath.hasPrefix(path + "/")
    }
}

enum EntryFilter: String, CaseIterable, Identifiable {
    case all
    case folders
    case notes
    case boards
    case media

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .folders: return "Folders"
        case .notes: return "Notes"
        case .boards: return "Boards"
        case .media: return "Media"
        }
    }
    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .folders: return "folder"
        case .notes: return "doc.text"
        case .boards: return "checklist"
        case .media: return "photo.on.rectangle"
        }
    }

    func matches(_ entry: Entry) -> Bool {
        switch self {
        case .all: return true
        case .folders: return entry.kind == .folder
        case .notes: return entry.kind == .note
        case .boards: return entry.kind.isBoard
        case .media: return [.image, .pdf, .epub, .audio, .video].contains(entry.kind)
        }
    }
}

enum EntrySort: String, CaseIterable, Identifiable {
    case name
    case recent
    case created

    var id: String { rawValue }
    var title: String {
        switch self {
        case .name: return "Name"
        case .recent: return "Edited"
        case .created: return "Added"
        }
    }
}

struct SearchHit: Identifiable, Hashable {
    let entry: Entry
    let snippet: String
    var id: String { entry.id }
}
