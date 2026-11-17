//
//  WorkspaceStore.swift
//  Comet
//
//  The file half of the app. A workspace is a folder the user chose; iOS hands
//  back a security-scoped bookmark, which is what makes it still reachable after
//  a launch. Every path is checked to stay inside that folder, and every write
//  is atomic so an interrupted save cannot truncate a note.
//
//  Nothing here is Comet-specific: it lists, reads, writes, moves and trashes
//  ordinary files. What they mean is decided above it.
//

import Foundation

struct WorkbookError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

final class WorkspaceStore {
    static let maximumTextBytes = 16 * 1024 * 1024
    static let maximumEntries = 20_000

    private(set) var root: URL?
    private var scoped = false

    deinit {
        if scoped, let root { root.stopAccessingSecurityScopedResource() }
    }

    // MARK: - Opening

    func open(_ ref: WorkspaceRef) throws {
        var stale = false
        let url: URL
        do {
            url = try URL(resolvingBookmarkData: ref.bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        } catch {
            throw WorkbookError("Comet can't reach this workspace any more. Choose the folder again.")
        }
        close()
        let started = url.startAccessingSecurityScopedResource()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            if started { url.stopAccessingSecurityScopedResource() }
            throw WorkbookError("This workspace folder is missing. It may have been moved or deleted.")
        }
        root = url
        scoped = started
    }

    func open(url: URL) {
        close()
        let started = url.startAccessingSecurityScopedResource()
        scoped = started
        root = url
    }

    func close() {
        if scoped, let root { root.stopAccessingSecurityScopedResource() }
        scoped = false
        root = nil
    }

    static func makeBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    // MARK: - Paths

    func url(for relativePath: String) -> URL? {
        guard let root else { return nil }
        if relativePath.isEmpty { return root }
        let candidate = root.appendingPathComponent(relativePath)
        let standardized = candidate.standardizedFileURL
        let base = root.standardizedFileURL.path
        guard standardized.path == base || standardized.path.hasPrefix(base + "/") else { return nil }
        guard !relativePath.components(separatedBy: "/").contains("..") else { return nil }
        return candidate
    }

    func relativePath(of url: URL) -> String? {
        guard let root else { return nil }
        let base = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(base) else { return nil }
        var relative = String(path.dropFirst(base.count))
        while relative.hasPrefix("/") { relative.removeFirst() }
        return relative
    }

    // MARK: - Listing

    private static let skipDirectories: Set<String> = [".git", "node_modules", ".Trash"]

    func scan() -> [Entry] {
        guard let root else { return [] }
        let manager = FileManager.default
        var results: [Entry] = []
        var queue: [URL] = [root]
        var visited = 0

        while let folder = queue.popLast() {
            guard let children = try? manager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for child in children {
                let name = child.lastPathComponent
                if name.hasPrefix(".") { continue }
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey])
                if values?.isSymbolicLink == true { continue }
                let isDirectory = values?.isDirectory ?? false
                if isDirectory && WorkspaceStore.skipDirectories.contains(name) { continue }
                guard let relative = relativePath(of: child), !relative.isEmpty else { continue }
                let kind = EntryKind.detect(name: name, isDirectory: isDirectory)
                results.append(Entry(
                    relativePath: relative,
                    name: name,
                    kind: kind,
                    size: isDirectory ? 0 : Int64(values?.fileSize ?? 0),
                    modified: values?.contentModificationDate ?? Date.distantPast,
                    url: child
                ))
                visited += 1
                if visited >= WorkspaceStore.maximumEntries { break }
                if isDirectory { queue.append(child) }
            }
            if visited >= WorkspaceStore.maximumEntries { break }
        }
        return results
    }

    // MARK: - Reading and writing

    func readText(_ relativePath: String) throws -> String {
        guard let url = url(for: relativePath) else { throw WorkbookError("That item is outside the workspace.") }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values?.isRegularFile != false else { throw WorkbookError("That item is not a file.") }
        if let size = values?.fileSize, size > WorkspaceStore.maximumTextBytes {
            throw WorkbookError("This file is larger than 16 MB and can't be edited here.")
        }
        guard let data = try? Data(contentsOf: url) else { throw WorkbookError("This file could not be read.") }
        guard let text = String(data: data, encoding: .utf8) else {
            throw WorkbookError("This file isn't UTF-8 text.")
        }
        guard !text.contains("\u{0}") else { throw WorkbookError("This file contains binary data.") }
        return text
    }

    func writeText(_ text: String, to relativePath: String) throws {
        guard let url = url(for: relativePath) else { throw WorkbookError("That item is outside the workspace.") }
        let data = Data(text.utf8)
        guard data.count <= WorkspaceStore.maximumTextBytes else {
            throw WorkbookError("Notes are limited to 16 MB.")
        }
        guard !text.contains("\u{0}") else { throw WorkbookError("That text can't be saved.") }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw WorkbookError("This note could not be saved: \(error.localizedDescription)")
        }
    }

    /// A name that does not collide, keeping the requested one when it is free.
    func availablePath(folder: String, name: String) -> String {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = name
        var counter = 2
        while let url = url(for: Entry.join(folder, candidate)), FileManager.default.fileExists(atPath: url.path) {
            candidate = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            counter += 1
            if counter > 500 { break }
        }
        return Entry.join(folder, candidate)
    }

    @discardableResult
    func createFile(folder: String, name: String, contents: String) throws -> Entry {
        let path = availablePath(folder: folder, name: name)
        guard let url = url(for: path) else { throw WorkbookError("That name is not allowed.") }
        let parent = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        let data = Data(contents.utf8)
        do {
            try data.write(to: url, options: [.withoutOverwriting, .atomic])
        } catch {
            throw WorkbookError("This file could not be created: \(error.localizedDescription)")
        }
        return entry(at: path) ?? Entry(relativePath: path, name: url.lastPathComponent,
                                       kind: EntryKind.detect(name: url.lastPathComponent, isDirectory: false),
                                       size: Int64(data.count), modified: Date(), url: url)
    }

    @discardableResult
    func createFolder(folder: String, name: String) throws -> Entry {
        let path = availablePath(folder: folder, name: name)
        guard let url = url(for: path) else { throw WorkbookError("That name is not allowed.") }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        } catch {
            throw WorkbookError("This folder could not be created: \(error.localizedDescription)")
        }
        return entry(at: path) ?? Entry(relativePath: path, name: url.lastPathComponent, kind: .folder,
                                       size: 0, modified: Date(), url: url)
    }

    func entry(at relativePath: String) -> Entry? {
        guard let url = url(for: relativePath) else { return nil }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
        guard values != nil else { return nil }
        let isDirectory = values?.isDirectory ?? false
        let name = url.lastPathComponent
        return Entry(relativePath: relativePath, name: name,
                     kind: EntryKind.detect(name: name, isDirectory: isDirectory),
                     size: Int64(values?.fileSize ?? 0),
                     modified: values?.contentModificationDate ?? Date(),
                     url: url)
    }

    func rename(_ relativePath: String, to newName: String) throws -> String {
        guard let source = url(for: relativePath) else { throw WorkbookError("That item is outside the workspace.") }
        let cleaned = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|")
        guard !cleaned.isEmpty, cleaned != ".", cleaned != "..",
              cleaned.rangeOfCharacter(from: forbidden) == nil,
              cleaned.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw WorkbookError("Use a name without slashes or special characters.")
        }
        let destination = source.deletingLastPathComponent().appendingPathComponent(cleaned)
        if destination.path == source.path { return relativePath }
        if FileManager.default.fileExists(atPath: destination.path) {
            throw WorkbookError("An item with that name already exists.")
        }
        do {
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            throw WorkbookError("This item could not be renamed: \(error.localizedDescription)")
        }
        guard let newRelative = self.relativePath(of: destination) else { throw WorkbookError("The rename did not complete.") }
        return newRelative
    }

    func move(_ relativePath: String, toFolder folder: String) throws -> String {
        guard let source = url(for: relativePath) else { throw WorkbookError("That item is outside the workspace.") }
        guard let destinationFolder = url(for: folder) else { throw WorkbookError("Choose a folder inside the workspace.") }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: destinationFolder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw WorkbookError("That folder no longer exists.")
        }
        let sourcePath = source.standardizedFileURL.path
        let destinationFolderPath = destinationFolder.standardizedFileURL.path
        if destinationFolderPath == sourcePath || destinationFolderPath.hasPrefix(sourcePath + "/") {
            throw WorkbookError("A folder cannot be moved into itself.")
        }
        let destination = destinationFolder.appendingPathComponent(source.lastPathComponent)
        if destination.path == source.path { return relativePath }
        if FileManager.default.fileExists(atPath: destination.path) {
            throw WorkbookError("An item with that name already exists.")
        }
        do {
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            throw WorkbookError("This item could not be moved: \(error.localizedDescription)")
        }
        guard let newRelative = self.relativePath(of: destination) else { throw WorkbookError("The move did not complete.") }
        return newRelative
    }

    func trash(_ relativePath: String) throws {
        guard let url = url(for: relativePath), !relativePath.isEmpty else {
            throw WorkbookError("That item is outside the workspace.")
        }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            // A workspace in iCloud Drive can refuse a trash; removing is the
            // honest fallback, and the app says so before calling this.
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                throw WorkbookError("This item could not be deleted: \(error.localizedDescription)")
            }
        }
    }

    /// Copy an outside file into the workspace, staging it next to its
    /// destination and renaming only once the whole file has arrived.
    @discardableResult
    func importFile(from source: URL, folder: String, preferredName: String? = nil) throws -> Entry {
        let needsScope = source.startAccessingSecurityScopedResource()
        defer { if needsScope { source.stopAccessingSecurityScopedResource() } }

        let name = preferredName ?? source.lastPathComponent
        let path = availablePath(folder: folder, name: name)
        guard let destination = url(for: path) else { throw WorkbookError("That name is not allowed.") }
        let parent = destination.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }

        let staging = parent.appendingPathComponent(".comet-import-\(UUID().uuidString).part")
        do {
            if FileManager.default.fileExists(atPath: staging.path) {
                try FileManager.default.removeItem(at: staging)
            }
            try FileManager.default.copyItem(at: source, to: staging)
            try FileManager.default.moveItem(at: staging, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw WorkbookError("This file could not be imported: \(error.localizedDescription)")
        }
        guard let entry = entry(at: path) else { throw WorkbookError("The import did not complete.") }
        return entry
    }

    func writeBoard(_ text: String, to relativePath: String) throws {
        try writeText(text, to: relativePath)
    }

    // MARK: - Search

    struct RawHit {
        let relativePath: String
        let snippet: String
    }

    /// Filenames and file contents, never outside the workspace. Runs off the
    /// main thread so a big folder cannot freeze the search field.
    static func search(query: String, in entries: [Entry]) -> [RawHit] {
        let needle = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 1 else { return [] }
        var hits: [RawHit] = []
        for entry in entries where !entry.isFolder {
            let nameMatches = entry.name.lowercased().contains(needle)
            var snippet = nameMatches ? entry.kind.displayLabel : ""
            if entry.kind.isText || entry.fileExtension == "txt" {
                if let data = try? Data(contentsOf: entry.url, options: .mappedIfSafe),
                   data.count <= 2 * 1024 * 1024,
                   let text = String(data: data, encoding: .utf8) {
                    if text.lowercased().contains(needle) {
                        for line in text.components(separatedBy: .newlines) where line.lowercased().contains(needle) {
                            let trimmed = line.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty { snippet = trimmed; break }
                        }
                    } else if !nameMatches {
                        continue
                    }
                } else if !nameMatches {
                    continue
                }
            } else if !nameMatches {
                // Media matches by name only; opening every image to search it
                // would cost more than the result is worth.
                continue
            }
            hits.append(RawHit(relativePath: entry.relativePath, snippet: String(snippet.prefix(160))))
            if hits.count >= 120 { break }
        }
        return hits.sorted { left, right in
            left.relativePath.localizedStandardCompare(right.relativePath) == .orderedAscending
        }
    }
}
