//
//  Workspace.swift
//  Comet for iOS
//
//  The file half of Comet's native surface, ported from the desktop app's Rust
//  commands so the front end cannot tell the difference: same arguments, same
//  JSON shapes, same refusals.
//
//  The rules that matter are kept: every path is checked to be inside the
//  chosen workspace (lexically and after resolving symlinks), renames and moves
//  never replace an existing item, new files are created exclusively, imports
//  are staged in a temporary ".part" file and only published once complete.
//

import Foundation

struct CometError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

final class Workspace {
    static let maximumTextBytes = 16 * 1024 * 1024
    static let maximumChunkBytes = 512 * 1024

    /// Workspaces the page has been told about, used to bound which files the
    /// asset endpoint will serve.
    private let lock = NSLock()
    private var roots: Set<String> = []

    // MARK: - Path rules

    static func normalize(_ path: String) -> String {
        var value = path
        while value.count > 1 && value.hasSuffix("/") { value.removeLast() }
        return value
    }

    static func canonical(_ path: String) -> String {
        normalize(URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path)
    }

    static func isInside(_ root: String, _ path: String) -> Bool {
        let root = normalize(root)
        let path = normalize(path)
        return path == root || path.hasPrefix(root + "/")
    }

    private static func hasParentComponent(_ path: String) -> Bool {
        path.split(separator: "/", omittingEmptySubsequences: true).contains("..")
    }

    /// Absolute, no "..", strictly below the workspace, compared as text.
    static func lexicalChild(vault: String, path: String) throws -> String {
        let root = normalize(vault)
        let target = normalize(path)
        guard root.hasPrefix("/"), target.hasPrefix("/") else {
            throw CometError("That item is outside the workspace.")
        }
        guard !hasParentComponent(root), !hasParentComponent(target) else {
            throw CometError("That item is outside the workspace.")
        }
        guard target != root, isInside(root, target) else {
            throw CometError("That item is outside the workspace.")
        }
        return target
    }

    /// An existing item inside the workspace. Returns the path as the caller
    /// wrote it, which is what the front end stores and compares.
    @discardableResult
    func checkedEntry(vault: String, path: String) throws -> String {
        let entry = try Workspace.lexicalChild(vault: vault, path: path)
        let root = Workspace.canonical(vault)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CometError("The workspace is not a folder.")
        }
        let target = Workspace.canonical(entry)
        guard target != root, Workspace.isInside(root, target) else {
            throw CometError("That item is outside the workspace.")
        }
        var entryIsDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: entry, isDirectory: &entryIsDirectory) else {
            throw CometError("That item no longer exists.")
        }
        register(root: root)
        return entry
    }

    /// A path that may not exist yet. The nearest existing ancestor is resolved
    /// so that a symlink cannot redirect creation outside the workspace, and
    /// missing folders are created only after that check.
    @discardableResult
    static func checkedNewEntry(vault: String, path: String, createParent: Bool) throws -> String {
        let root = canonical(vault)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CometError("The workspace is not a folder.")
        }
        let target = try lexicalChild(vault: vault, path: path)
        let name = (target as NSString).lastPathComponent
        guard !name.isEmpty else { throw CometError("Choose a path inside the workspace.") }

        let parent = (target as NSString).deletingLastPathComponent
        var ancestor = parent
        var steps = 0
        while !FileManager.default.fileExists(atPath: ancestor) {
            steps += 1
            guard steps < 4096 else { throw CometError("The item has no accessible parent folder.") }
            let next = (ancestor as NSString).deletingLastPathComponent
            guard next != ancestor else { throw CometError("The item has no accessible parent folder.") }
            ancestor = next
        }
        guard isInside(root, canonical(ancestor)) else {
            throw CometError("That item is outside the workspace.")
        }
        if createParent {
            try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
        }
        guard isInside(root, canonical(parent)) else {
            throw CometError("That item is outside the workspace.")
        }
        return target
    }

    func register(root path: String) {
        let resolved = Workspace.canonical(path)
        lock.lock()
        roots.insert(resolved)
        lock.unlock()
    }

    /// What the `/__file` endpoint will read: anything inside this app's own
    /// container, plus workspace folders the page has been granted.
    func allowsFile(_ path: String) -> Bool {
        let resolved = Workspace.canonical(path)
        if Workspace.isInside(NSHomeDirectory(), resolved) { return true }
        lock.lock()
        let known = roots
        lock.unlock()
        return known.contains { Workspace.isInside($0, resolved) }
    }

    // MARK: - Listing and searching

    func list(_ path: String) -> [[String: Any]] {
        var entries: [[String: Any]] = []
        let fileManager = FileManager.default
        let root = Workspace.canonical(path)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root, isDirectory: &isDirectory), isDirectory.boolValue else { return [] }
        register(root: root)

        var visited: Set<String> = []
        var scheduled: Set<String> = [root]
        var stack: [String] = [Workspace.normalize(path)]

        while let current = stack.popLast() {
            let resolved = Workspace.canonical(current)
            guard Workspace.isInside(root, resolved) else { continue }
            guard visited.insert(resolved).inserted else { continue }
            guard let children = try? fileManager.contentsOfDirectory(atPath: current) else { continue }

            for name in children.sorted() {
                let child = current.hasSuffix("/") ? current + name : current + "/" + name
                let resolvedChild = Workspace.canonical(child)
                guard Workspace.isInside(root, resolvedChild) else { continue }
                var childIsDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: child, isDirectory: &childIsDirectory) else { continue }
                let folder = childIsDirectory.boolValue
                if folder && !scheduled.insert(resolvedChild).inserted { continue }
                entries.append(["name": name, "path": child, "kind": folder ? "folder" : "file"])
                if folder { stack.append(child) }
            }
        }
        return entries
    }

    private static let searchableExtensions: Set<String> = [
        "md", "markdown", "txt", "text", "log", "csv", "tsv", "json", "jsonl", "xml",
        "yaml", "yml", "toml", "ini", "cfg", "conf", "html", "htm", "css", "js", "jsx",
        "ts", "tsx", "py", "rs", "sh", "sql", "tex", "rst", "url", "comet-todo"
    ]

    func search(vault: String, query: String) -> [[String: Any]] {
        let needle = query.lowercased()
        guard !needle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let fileManager = FileManager.default
        let root = Workspace.canonical(vault)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root, isDirectory: &isDirectory), isDirectory.boolValue else { return [] }
        register(root: root)

        var hits: [[String: Any]] = []
        var visited: Set<String> = []
        var scheduled: Set<String> = [root]
        var stack: [String] = [Workspace.normalize(vault)]

        while let current = stack.popLast() {
            let resolved = Workspace.canonical(current)
            guard Workspace.isInside(root, resolved) else { continue }
            guard visited.insert(resolved).inserted else { continue }
            guard let children = try? fileManager.contentsOfDirectory(atPath: current) else { continue }

            for name in children {
                let path = current.hasSuffix("/") ? current + name : current + "/" + name
                let resolvedChild = Workspace.canonical(path)
                guard Workspace.isInside(root, resolvedChild) else { continue }
                var childIsDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: path, isDirectory: &childIsDirectory) else { continue }
                if childIsDirectory.boolValue {
                    if scheduled.insert(resolvedChild).inserted { stack.append(path) }
                    continue
                }
                let ext = (name as NSString).pathExtension.lowercased()
                guard Workspace.searchableExtensions.contains(ext) else { continue }
                let attributes = try? fileManager.attributesOfItem(atPath: path)
                guard let size = (attributes?[.size] as? NSNumber)?.uint64Value else { continue }
                guard size <= UInt64(Workspace.maximumTextBytes) else { continue }
                guard let data = fileManager.contents(atPath: path),
                      let text = String(data: data, encoding: .utf8),
                      !text.contains("\u{0}") else { continue }
                let nameMatches = name.lowercased().contains(needle)
                let contentMatches = text.lowercased().contains(needle)
                guard nameMatches || contentMatches else { continue }
                var snippet = "Matching filename"
                for line in text.components(separatedBy: .newlines) where line.lowercased().contains(needle) {
                    snippet = line.trimmingCharacters(in: .whitespaces)
                    break
                }
                hits.append(["path": path, "name": name, "snippet": snippet])
            }
        }
        return hits.sorted { left, right in
            (left["name"] as? String ?? "").lowercased() < (right["name"] as? String ?? "").lowercased()
        }
    }

    // MARK: - Reading and writing

    func readNote(vault: String, path: String) throws -> String {
        let entry = try checkedEntry(vault: vault, path: path)
        let attributes = try? FileManager.default.attributesOfItem(atPath: entry)
        let type = attributes?[.type] as? FileAttributeType
        let size = (attributes?[.size] as? NSNumber)?.uint64Value ?? UInt64.max
        guard type == .typeRegular, size <= UInt64(Workspace.maximumTextBytes) else {
            throw CometError("This file is not a text file or is too large to edit (16 MB maximum).")
        }
        guard let data = FileManager.default.contents(atPath: entry), let text = String(data: data, encoding: .utf8) else {
            throw CometError("This file isn't UTF-8 text.")
        }
        guard !text.contains("\u{0}") else {
            throw CometError("This file contains binary data and can't be edited as text.")
        }
        return text
    }

    func writeNote(vault: String, path: String, content: String) throws {
        let bytes = Data(content.utf8)
        guard bytes.count <= Workspace.maximumTextBytes else {
            throw CometError("Text files are limited to 16 MB. Reduce the text before saving.")
        }
        guard !content.contains("\u{0}") else {
            throw CometError("This text contains a NUL character and cannot be saved as an editable file.")
        }
        let entry = try checkedEntry(vault: vault, path: path)
        // Atomic so that an interrupted save leaves the previous contents whole.
        try bytes.write(to: URL(fileURLWithPath: entry), options: .atomic)
    }

    func createNote(vault: String, path: String, content: String) throws {
        let note = try Workspace.checkedNewEntry(vault: vault, path: path, createParent: true)
        try Workspace.createExclusively(at: note, contents: Data(content.utf8))
    }

    func createFolder(vault: String, path: String) throws {
        let folder = try Workspace.checkedNewEntry(vault: vault, path: path, createParent: false)
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: false)
    }

    func rename(vault: String, path: String, newName: String) throws {
        let source = try checkedEntry(vault: vault, path: path)
        guard !newName.isEmpty, newName != ".", newName != ".." else {
            throw CometError("Choose a valid file name.")
        }
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|")
        if newName.unicodeScalars.contains(where: { forbidden.contains($0) || CharacterSet.controlCharacters.contains($0) }) {
            throw CometError("Choose a valid file name.")
        }
        let parent = (source as NSString).deletingLastPathComponent
        let destination = (parent as NSString).appendingPathComponent(newName)
        if destination == source { return }
        if FileManager.default.fileExists(atPath: destination) {
            throw CometError("An item with that name already exists.")
        }
        try Workspace.moveWithoutReplacing(from: source, to: destination)
    }

    func move(vault: String, path: String, folder: String) throws -> String {
        let source = try checkedEntry(vault: vault, path: path)
        let root = Workspace.canonical(vault)
        // Swift refuses `try` to the right of ?:, and this reads better anyway.
        var destinationFolder = vault
        if Workspace.normalize(folder) != Workspace.normalize(vault) {
            destinationFolder = try checkedEntry(vault: vault, path: folder)
        }
        let resolvedFolder = Workspace.canonical(destinationFolder)
        var folderIsDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolvedFolder, isDirectory: &folderIsDirectory),
              folderIsDirectory.boolValue,
              Workspace.isInside(root, resolvedFolder) else {
            throw CometError("Choose a folder inside the workspace.")
        }
        let resolvedSource = Workspace.canonical(source)
        var sourceIsDirectory: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: resolvedSource, isDirectory: &sourceIsDirectory)
        if sourceIsDirectory.boolValue && Workspace.isInside(resolvedSource, resolvedFolder) {
            throw CometError("A folder cannot be moved into itself.")
        }
        let name = (source as NSString).lastPathComponent
        let destination = (destinationFolder as NSString).appendingPathComponent(name)
        if destination == source { return path }
        _ = try Workspace.checkedNewEntry(vault: vault, path: destination, createParent: false)
        if FileManager.default.fileExists(atPath: destination) {
            throw CometError("An item with that name already exists.")
        }
        try Workspace.moveWithoutReplacing(from: source, to: destination)
        return destination
    }

    func delete(vault: String, path: String) throws {
        let target = try checkedEntry(vault: vault, path: path)
        try FileManager.default.removeItem(atPath: target)
    }

    func copyAsset(vault: String, source: String, destination: String) throws {
        guard let handle = FileHandle(forReadingAtPath: source) else {
            throw CometError("Couldn't read the file to import.")
        }
        var staged: StagedFile?
        defer {
            handle.closeFile()
            staged?.discard()
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: source)
        let size = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        let staging = try StagedFile(vault: vault, destination: destination, expected: size, createParent: true)
        staged = staging
        while true {
            let chunk = try? handle.read(upToCount: 1024 * 1024)
            guard let chunk, !chunk.isEmpty else { break }
            try staging.append(offset: staging.written, bytes: chunk)
        }
        try staging.publish()
    }

    // MARK: - File helpers

    /// 516 is NSFileWriteFileExistsError: the destination appeared between the
    /// check and the move.
    private static let fileExistsErrorCode = 516

    static func moveWithoutReplacing(from source: String, to destination: String) throws {
        do {
            try FileManager.default.moveItem(atPath: source, toPath: destination)
        } catch {
            if (error as NSError).code == fileExistsErrorCode {
                throw CometError("An item with that name already exists.")
            }
            throw CometError(error.localizedDescription)
        }
    }

    /// `create_new` equivalents: the file appears complete or not at all, and an
    /// existing file is never replaced.
    static func createExclusively(at path: String, contents: Data) throws {
        let descriptor = Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
        guard descriptor >= 0 else {
            if errno == EEXIST { throw CometError("An item with that name already exists.") }
            throw CometError(String(cString: strerror(errno)))
        }
        defer { Darwin.close(descriptor) }
        let bytes = [UInt8](contents)
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { buffer -> Int in
                guard let base = buffer.baseAddress else { return -1 }
                return Darwin.write(descriptor, base.advanced(by: offset), bytes.count - offset)
            }
            guard written > 0 else { throw CometError("Couldn't write the file.") }
            offset += written
        }
    }

    static func randomToken() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}

/// A file being written next to its destination and renamed into place only
/// once every byte has arrived. Mirrors the desktop app's staged imports so a
/// cancelled or interrupted import never leaves a half-written file in the
/// workspace.
final class StagedFile {
    private(set) var written: UInt64 = 0
    private(set) var expected: UInt64 = 0
    private var destination: String = ""
    private var vault: String = ""
    private var parent: String = ""
    private var temporary: String = ""
    private var handle: FileHandle?

    init(vault: String, destination: String, expected: UInt64, createParent: Bool) throws {
        let target = try Workspace.checkedNewEntry(vault: vault, path: destination, createParent: createParent)
        if FileManager.default.fileExists(atPath: target) {
            throw CometError("An item with that name already exists.")
        }
        let parentPath = (target as NSString).deletingLastPathComponent

        var created = ""
        for _ in 0..<20 {
            let candidate = (parentPath as NSString).appendingPathComponent(".comet-upload-\(Workspace.randomToken()).part")
            let descriptor = Darwin.open(candidate, O_WRONLY | O_CREAT | O_EXCL, 0o644)
            if descriptor >= 0 {
                self.handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
                created = candidate
                break
            }
            if errno != EEXIST { throw CometError(String(cString: strerror(errno))) }
        }
        guard !created.isEmpty else { throw CometError("Couldn't create a unique temporary import file.") }

        self.temporary = created
        self.destination = destination
        self.vault = vault
        self.parent = Workspace.canonical(parentPath)
        self.expected = expected
    }

    deinit {
        discard()
    }

    func append(offset: UInt64, bytes: Data) throws {
        guard !bytes.isEmpty,
              bytes.count <= Workspace.maximumChunkBytes,
              offset == written,
              written + UInt64(bytes.count) <= expected else {
            throw CometError("The upload chunk is invalid or out of order.")
        }
        guard let handle else { throw CometError("The upload is already closed.") }
        try handle.write(contentsOf: bytes)
        written += UInt64(bytes.count)
    }

    func publish() throws {
        guard written == expected else {
            throw CometError("The file import was incomplete; nothing was added.")
        }
        guard let handle else { throw CometError("The upload is already closed.") }
        self.handle = nil
        do {
            try handle.synchronize()
        } catch {
            handle.closeFile()
            throw CometError("Couldn't finish the import.")
        }
        handle.closeFile()

        // Both the workspace boundary and the actual parent are rechecked after
        // the copy, so a folder swapped mid-import cannot redirect the file.
        let target = try Workspace.checkedNewEntry(vault: vault, path: destination, createParent: false)
        let parentPath = (target as NSString).deletingLastPathComponent
        guard Workspace.canonical(parentPath) == parent else {
            throw CometError("The destination folder changed during the import; nothing was added.")
        }
        let finalPath = (parentPath as NSString).appendingPathComponent((target as NSString).lastPathComponent)
        if FileManager.default.fileExists(atPath: finalPath) {
            throw CometError("An item with that name already exists.")
        }
        try Workspace.moveWithoutReplacing(from: temporary, to: finalPath)
        temporary = ""
    }

    func discard() {
        handle?.closeFile()
        handle = nil
        guard !temporary.isEmpty else { return }
        try? FileManager.default.removeItem(atPath: temporary)
        temporary = ""
    }
}

/// The table of imports Comet streams a dropped file through, 512 KB at a time.
final class Uploads {
    private static let maximumActive = 16
    private let lock = NSLock()
    private var sessions: [String: StagedFile] = [:]

    func begin(vault: String, path: String, size: UInt64) throws -> String {
        lock.lock()
        let count = sessions.count
        lock.unlock()
        guard count < Uploads.maximumActive else {
            throw CometError("Too many file imports are active; wait for one to finish.")
        }
        let staged = try StagedFile(vault: vault, destination: path, expected: size, createParent: false)
        let id = Workspace.randomToken()
        lock.lock()
        sessions[id] = staged
        lock.unlock()
        return id
    }

    func append(id: String, offset: UInt64, bytes: Data) throws {
        lock.lock()
        let staged = sessions[id]
        lock.unlock()
        guard let staged else { throw CometError("The upload is no longer active.") }
        try staged.append(offset: offset, bytes: bytes)
    }

    func finish(id: String) throws {
        lock.lock()
        let staged = sessions.removeValue(forKey: id)
        lock.unlock()
        guard let staged else { throw CometError("The upload is no longer active.") }
        defer { staged.discard() }
        try staged.publish()
    }

    func abort(id: String) {
        lock.lock()
        let staged = sessions.removeValue(forKey: id)
        lock.unlock()
        staged?.discard()
    }

    func discardAll() {
        lock.lock()
        let all = Array(sessions.values)
        sessions.removeAll()
        lock.unlock()
        all.forEach { $0.discard() }
    }
}
