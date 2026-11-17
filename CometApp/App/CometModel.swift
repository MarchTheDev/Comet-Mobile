//
//  CometModel.swift
//  Comet
//
//  The app's one source of truth: the folder it is pointed at, the files in it,
//  the profile beside them, the vault, and where the user is.
//
//  Views never touch the file system. They call a method here, which writes,
//  records the change in the sync journal and republishes. That is the whole
//  contract, and it is what will let sync arrive later without touching a
//  single screen.
//

import Foundation
import SwiftUI
import Combine
import UIKit
import UniformTypeIdentifiers

enum Module: String, Identifiable, CaseIterable, Hashable {
    case calendar
    case feeds
    case vault
    case tools
    case sync
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calendar: return "Calendar"
        case .feeds: return "Feeds"
        case .vault: return "Passwords"
        case .tools: return "Tools"
        case .sync: return "Sync"
        case .settings: return "Settings"
        }
    }

    var subtitle: String {
        switch self {
        case .calendar: return "Events kept on this device"
        case .feeds: return "RSS, Atom and JSON, read here"
        case .vault: return "An encrypted vault"
        case .tools: return "Everything that does arithmetic"
        case .sync: return "The next release"
        case .settings: return "Palette, type, workspace"
        }
    }

    var symbol: String {
        switch self {
        case .calendar: return "calendar"
        case .feeds: return "dot.radiowaves.left.and.right"
        case .vault: return "lock.shield"
        case .tools: return "function"
        case .sync: return "arrow.triangle.2.circlepath"
        case .settings: return "slider.horizontal.3"
        }
    }
}

@MainActor
final class CometModel: ObservableObject {
    // MARK: - Preferences

    @Published var settings: CometSettings {
        didSet {
            SettingsStore.shared.save(settings)
            Haptics.enabled = settings.haptics
        }
    }

    let toast = ToastCenter()
    let vault = VaultStore()

    // MARK: - Workspace

    private let store = WorkspaceStore()
    private var profileStore: ProfileStore?

    @Published private(set) var workspaces: [WorkspaceRef] = []
    @Published private(set) var currentWorkspace: WorkspaceRef?
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var profile = WorkspaceProfile()
    @Published private(set) var sync = SyncSummary(deviceID: "", deviceName: "",
                                                    pendingChanges: 0, lastRun: nil,
                                                    profileUpdated: Date())
    @Published private(set) var loadingWorkspace = false
    @Published var errorMessage: String?
    @Published private(set) var recentPaths: [String] = []

    // MARK: - Navigation

    @Published var tab: Tab = .today
    @Published var filesPath: String = ""
    @Published var openedFile: Entry?
    /// Set by a sheet that has just made something; the shell opens it once the
    /// sheet is gone, so the two presentations cannot fight over the screen.
    @Published var pendingOpen: Entry?
    @Published var module: Module?
    @Published var showingOrbit = false
    @Published var showingNewItem = false
    @Published var showingWorkspacePicker = false

    // MARK: - Search

    @Published var searchQuery: String = ""
    @Published private(set) var searchHits: [SearchHit] = []
    @Published private(set) var searching = false
    private var searchTask: Task<Void, Never>?

    // MARK: - Feeds

    @Published private(set) var refreshingFeeds = false
    @Published private(set) var feedErrors: [String: String] = [:]

    // MARK: - Lifecycle

    private var cancellables: Set<AnyCancellable> = []

    init() {
        let loaded = SettingsStore.shared.load()
        settings = loaded
        Haptics.enabled = loaded.haptics
        workspaces = SettingsStore.shared.loadWorkspaces()

        // The vault and the toast are their own objects; a screen watching the
        // model still has to redraw when either changes, so their changes are
        // folded into the model's.
        vault.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        toast.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func bootstrap() {
        guard currentWorkspace == nil, !loadingWorkspace else { return }
        let lastID = settings.openLastWorkspace ? SettingsStore.shared.lastWorkspaceID() : nil
        let target = workspaces.first { $0.id == lastID } ?? workspaces.first
        if let target {
            open(target)
        }
        // Whatever was remembered, if nothing is reachable now the app still
        // has to be usable: make the workspace it keeps for itself.
        if !store.isReachable {
            createStarterWorkspace()
        }
    }

    // MARK: - Workspaces

    @discardableResult
    func createStarterWorkspace() -> WorkspaceRef? {
        let folder = LocalStore.documentsDirectory.appendingPathComponent("Comet", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        StarterWorkspace.seed(in: folder)
        guard let bookmark = WorkspaceStore.makeBookmark(for: folder) else {
            errorMessage = "Comet couldn't create its first workspace."
            return nil
        }
        let ref = WorkspaceRef(id: UUID().uuidString, name: "Comet", bookmark: bookmark,
                              pathHint: folder.path, added: Date())
        workspaces.append(ref)
        SettingsStore.shared.saveWorkspaces(workspaces)
        open(ref)
        return ref
    }

    func addWorkspace(url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        // Open the folder that was just handed to us rather than round-tripping
        // it through a bookmark: the URL is known to be good right now, and a
        // bookmark is only needed for the next launch.
        let bookmark = WorkspaceStore.makeBookmark(for: url)
        let name = url.lastPathComponent

        if let existing = workspaces.first(where: { $0.pathHint == url.path }) {
            open(existing)
            return
        }

        let ref = WorkspaceRef(id: UUID().uuidString, name: name,
                               bookmark: bookmark ?? Data(), pathHint: url.path, added: Date())
        workspaces.append(ref)
        SettingsStore.shared.saveWorkspaces(workspaces)

        store.open(url: url)
        guard store.isReachable else {
            errorMessage = "Comet can open that folder only while this screen is up. Copies of its files are not kept."
            return
        }
        currentWorkspace = ref
        loadProfile(for: ref)
        entries = store.scan()
        filesPath = ""
        SettingsStore.shared.setLastWorkspaceID(ref.id)
        toast.show("Opened \(name)", tone: .success)
    }

    /// Confirm the folder is still there, re-bookmark it, and list it again.
    /// The Settings screen calls this; so does anything that finds the folder
    /// gone when it expected to write.
    @discardableResult
    func repairWorkspace() -> Bool {
        guard let ref = currentWorkspace else {
            if let first = workspaces.first { open(first) }
            return store.isReachable
        }
        do {
            try store.open(ref)
        } catch {
            store.close()
        }
        if !store.isReachable, let root = WorkspaceStore.existingFolder(at: ref.pathHint) {
            store.open(url: root)
        }
        guard store.isReachable else {
            errorMessage = "Comet cannot reach \(ref.name). Choose the folder again."
            return false
        }
        if let root = store.root, let bookmark = WorkspaceStore.makeBookmark(for: root) {
            var updated = ref
            updated.bookmark = bookmark
            updated.pathHint = root.path
            replace(ref, with: updated)
            currentWorkspace = updated
        }
        entries = store.scan()
        toast.show("Workspace checked", tone: .success)
        return true
    }

    private func replace(_ ref: WorkspaceRef, with updated: WorkspaceRef) {
        if let index = workspaces.firstIndex(where: { $0.id == ref.id }) {
            workspaces[index] = updated
            SettingsStore.shared.saveWorkspaces(workspaces)
        }
    }

    /// True when writes will land somewhere. Creates the app's own workspace in
    /// the last resort rather than letting a create button do nothing.
    @discardableResult
    func ensureWorkspace() -> Bool {
        if store.isReachable { return true }
        if let currentWorkspace {
            if let root = WorkspaceStore.existingFolder(at: currentWorkspace.pathHint)
                ?? WorkspaceStore.resolve(currentWorkspace.bookmark) {
                store.open(url: root)
            }
        }
        if !store.isReachable, let first = workspaces.first {
            if let root = WorkspaceStore.existingFolder(at: first.pathHint)
                ?? WorkspaceStore.resolve(first.bookmark) {
                store.open(url: root)
                currentWorkspace = first
                loadProfile(for: first)
            }
        }
        if !store.isReachable {
            createStarterWorkspace()
        }
        if store.isReachable {
            entries = store.scan()
            return true
        }
        errorMessage = "Comet could not open a folder to write to. Open one from the workspace button."
        return false
    }

    private func loadProfile(for ref: WorkspaceRef) {
        let key = LocalStore.workspaceKey(for: ref)
        let store = ProfileStore(key: key)
        store.load()
        profileStore = store
        profile = store.profile
        if profile.workspaceName.isEmpty {
            mutateProfile({ $0.workspaceName = ref.name }, record: nil)
        }
        recentPaths = UserDefaults.standard.stringArray(forKey: "comet.recent." + key) ?? []
        sync = store.summary
    }

    func open(_ ref: WorkspaceRef) {
        loadingWorkspace = true
        defer { loadingWorkspace = false }
        do {
            try store.open(ref)
        } catch {
            errorMessage = error.localizedDescription
            if currentWorkspace == nil, let fallback = workspaces.first(where: { $0.id != ref.id }) {
                open(fallback)
            }
            return
        }
        var ref = ref
        if let root = store.root {
            // Keep the bookmark pointing at wherever the folder really is now.
            if let bookmark = WorkspaceStore.makeBookmark(for: root) {
                ref.bookmark = bookmark
            }
            if ref.pathHint != root.path {
                ref.pathHint = root.path
            }
            replace(ref, with: ref)
        }
        currentWorkspace = ref
        let key = LocalStore.workspaceKey(for: ref)
        let profileStore = ProfileStore(key: key)
        profileStore.load()
        self.profileStore = profileStore
        profile = profileStore.profile
        if profile.workspaceName.isEmpty {
            mutateProfile({ $0.workspaceName = ref.name }, record: nil)
        }
        entries = store.scan()
        recentPaths = UserDefaults.standard.stringArray(forKey: "comet.recent." + key) ?? []
        sync = profileStore.summary
        SettingsStore.shared.setLastWorkspaceID(ref.id)
        filesPath = ""
        searchQuery = ""
        searchHits = []
    }

    func remove(_ ref: WorkspaceRef) {
        if currentWorkspace?.id == ref.id {
            store.close()
            currentWorkspace = nil
            entries = []
            profileStore = nil
            profile = WorkspaceProfile()
        }
        workspaces.removeAll { $0.id == ref.id }
        SettingsStore.shared.saveWorkspaces(workspaces)
        if currentWorkspace == nil {
            if let next = workspaces.first {
                open(next)
            } else {
                createStarterWorkspace()
            }
        }
    }

    func reload() {
        guard store.isReachable else {
            _ = ensureWorkspace()
            return
        }
        entries = store.scan()
        sync = profileStore?.summary ?? sync
    }

    // MARK: - Diagnostics

    var workspacePath: String { store.root?.path ?? "No folder open" }
    var isWorkspaceReachable: Bool { store.isReachable }
    var hasUsableBookmark: Bool {
        guard let currentWorkspace else { return false }
        return WorkspaceStore.resolve(currentWorkspace.bookmark) != nil
    }

    var workspaceName: String {
        let name = profile.workspaceName
        if !name.isEmpty { return name }
        return currentWorkspace?.name ?? "Comet"
    }

    // MARK: - Profile

    private func mutateProfile(_ change: (inout WorkspaceProfile) -> Void, record: ChangeRecord?) {
        var next = profile
        change(&next)
        next.updatedAt = Date()
        profile = next
        if let profileStore {
            profileStore.setProfile(next, reason: record)
            sync = profileStore.summary
        }
    }

    private func record(_ action: ChangeAction, path: String, previousPath: String? = nil, digest: String? = nil) {
        profileStore?.record(action, path: path, previousPath: previousPath, digest: digest)
        sync = profileStore?.summary ?? sync
    }

    // MARK: - Listing

    func children(of path: String) -> [Entry] {
        entries.filter { $0.parentPath == path }
    }

    func entry(at path: String) -> Entry? {
        entries.first { $0.relativePath == path }
    }

    func pathComponents(_ path: String) -> [(name: String, path: String)] {
        var result: [(String, String)] = []
        guard !path.isEmpty else { return result }
        var cursor = ""
        for component in path.components(separatedBy: "/") {
            cursor = cursor.isEmpty ? component : cursor + "/" + component
            result.append((component, cursor))
        }
        return result
    }

    func sortedChildren(of path: String, filter: EntryFilter = .all, sort: EntrySort = .name) -> [Entry] {
        let items = children(of: path).filter { filter.matches($0) }
        switch sort {
        case .name:
            return profile.sorted(items, in: path)
        case .recent:
            return items.sorted { $0.modified > $1.modified }
        case .created:
            return items.sorted { $0.modified < $1.modified }
        }
    }

    var pinnedEntries: [Entry] {
        entries.filter { profile.isPinned($0.relativePath) && !$0.isFolder }
            .sorted { $0.modified > $1.modified }
    }

    var favoriteEntries: [Entry] {
        entries.filter { profile.isFavorite($0.relativePath) && !$0.isFolder }
            .sorted { $0.modified > $1.modified }
    }

    var boardEntries: [Entry] {
        entries.filter { $0.kind.isBoard }.sorted { $0.modified > $1.modified }
    }

    var noteEntries: [Entry] {
        entries.filter { $0.kind == .note }
    }

    var recentEntries: [Entry] {
        recentPaths.compactMap { entry(at: $0) }.prefix(8).map { $0 }
    }

    var usedTags: [(tag: WorkspaceTag, count: Int)] {
        profile.tags.map { tag in
            let count = entries.filter { profile.meta(for: $0.relativePath).tags.contains(tag.id) }.count
            return (tag, count)
        }
        .filter { $0.count > 0 }
        .sorted { $0.tag.name.localizedStandardCompare($1.tag.name) == .orderedAscending }
    }

    // MARK: - Creating

    @discardableResult
    func createNote(named name: String = "Untitled", in folder: String? = nil,
                    contents: String = "") -> Entry? {
        guard ensureWorkspace() else { return nil }
        let target = folder ?? filesPath
        do {
            let entry = try store.createFile(folder: target, name: name.hasSuffix(".md") ? name : name + ".md",
                                             contents: contents)
            reload()
            record(.create, path: entry.relativePath)
            Haptics.success()
            return entry
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
            return nil
        }
    }

    @discardableResult
    func createBoard(_ kind: EntryKind, named name: String, in folder: String? = nil) -> Entry? {
        guard ensureWorkspace() else { return nil }
        let target = folder ?? filesPath
        let suffix = kind == .whiteboard ? ".comet-whiteboard" : ".comet-todo"
        let contents = kind == .whiteboard ? WhiteboardDocument().serialized() : TodoDocument().serialized()
        do {
            let entry = try store.createFile(folder: target,
                                             name: name.hasSuffix(suffix) ? name : name + suffix,
                                             contents: contents)
            reload()
            record(.create, path: entry.relativePath)
            Haptics.success()
            return entry
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func createFolder(named name: String, in folder: String? = nil) -> Entry? {
        guard ensureWorkspace() else { return nil }
        let target = folder ?? filesPath
        do {
            let entry = try store.createFolder(folder: target, name: name)
            reload()
            record(.create, path: entry.relativePath)
            Haptics.success()
            return entry
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func importFiles(_ urls: [URL], into folder: String? = nil) {
        guard ensureWorkspace() else { return }
        let target = folder ?? filesPath
        var imported = 0
        for url in urls {
            do {
                let entry = try store.importFile(from: url, folder: target)
                record(.create, path: entry.relativePath)
                imported += 1
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        if imported > 0 {
            reload()
            Haptics.success()
            toast.show(imported == 1 ? "Imported 1 file" : "Imported \(imported) files", tone: .success)
        }
    }

    /// A photo dragged in from the picker becomes a file beside the note.
    @discardableResult
    func importImage(data: Data, name: String, folder: String? = nil) -> Entry? {
        guard ensureWorkspace() else { return nil }
        let target = folder ?? filesPath
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: temporary, options: .atomic)
            let entry = try store.importFile(from: temporary, folder: target)
            try? FileManager.default.removeItem(at: temporary)
            reload()
            record(.create, path: entry.relativePath)
            return entry
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Editing files

    func readText(_ entry: Entry) -> String {
        do {
            return try store.readText(entry.relativePath)
        } catch {
            errorMessage = error.localizedDescription
            return ""
        }
    }

    @discardableResult
    func saveText(_ text: String, at entry: Entry, quiet: Bool = true) -> Bool {
        do {
            try store.writeText(text, to: entry.relativePath)
            let digest = Digest.of(text)
            // Coalesce typing into one journal fact per minute rather than one
            // per keystroke.
            let last = profileStore?.journal.records.last
            let recentSamePath = last?.path == entry.relativePath
                && last?.action == .update
                && (last?.at.timeIntervalSinceNow ?? -1000) > -60
            if !recentSamePath {
                record(.update, path: entry.relativePath, digest: digest)
            }
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                let updated = Entry(relativePath: entry.relativePath, name: entry.name, kind: entry.kind,
                                    size: Int64(text.utf8.count), modified: Date(), url: entry.url)
                entries[index] = updated
            }
            return true
        } catch {
            if !quiet {
                errorMessage = error.localizedDescription
                Haptics.error()
            }
            return false
        }
    }

    func rename(_ entry: Entry, to newName: String) {
        do {
            let newPath = try store.rename(entry.relativePath, to: normalizeRename(entry: entry, input: newName))
            let oldPath = entry.relativePath
            var next = profile
            next.items = remapKeys(next.items, from: oldPath, to: newPath)
            next.order = remapOrder(next.order, from: oldPath, to: newPath)
            profile = next
            profileStore?.setProfile(next, reason: ChangeRecord(device: profileStore?.device.id ?? "",
                                                               action: .rename, path: newPath,
                                                               previousPath: oldPath))
            recentPaths = recentPaths.map { $0 == oldPath || $0.hasPrefix(oldPath + "/")
                ? newPath + $0.dropFirst(oldPath.count) : $0 }
            persistRecent()
            reload()
            if openedFile?.relativePath == oldPath {
                openedFile = self.entry(at: newPath)
            }
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }

    /// Keep a special extension when a title is edited, the same rule Comet uses.
    private func normalizeRename(entry: Entry, input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entry.name }
        if entry.kind.isBoard || entry.kind == .shortcut {
            let ext = "." + entry.fileExtension
            return trimmed.lowercased().hasSuffix(ext) ? trimmed : trimmed + ext
        }
        if entry.kind == .note {
            if (trimmed as NSString).pathExtension.isEmpty { return trimmed + ".md" }
        }
        return trimmed
    }

    private func remapKeys<T>(_ source: [String: T], from old: String, to new: String) -> [String: T] {
        var result: [String: T] = [:]
        for (key, value) in source {
            if key == old || key.hasPrefix(old + "/") {
                result[new + key.dropFirst(old.count)] = value
            } else {
                result[key] = value
            }
        }
        return result
    }

    private func remapOrder(_ source: [String: [String]], from old: String, to new: String) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for (parent, children) in source {
            let nextParent = parent == old || parent.hasPrefix(old + "/") ? new + parent.dropFirst(old.count) : parent
            let nextChildren: [String] = children.map { child in
                child == old || child.hasPrefix(old + "/") ? new + child.dropFirst(old.count) : child
            }
            result[nextParent] = nextChildren
        }
        return result
    }

    func delete(_ entry: Entry) {
        do {
            try store.trash(entry.relativePath)
            var next = profile
            let prefix = entry.relativePath
            next.items = next.items.filter { !($0.key == prefix || $0.key.hasPrefix(prefix + "/")) }
            next.order = next.order.filter { !($0.key == prefix || $0.key.hasPrefix(prefix + "/")) }
                .mapValues { $0.filter { !($0 == prefix || $0.hasPrefix(prefix + "/")) } }
            profile = next
            profileStore?.setProfile(next, reason: ChangeRecord(device: profileStore?.device.id ?? "",
                                                               action: .delete, path: prefix))
            recentPaths.removeAll { $0 == prefix || $0.hasPrefix(prefix + "/") }
            persistRecent()
            if openedFile?.relativePath == prefix { openedFile = nil }
            reload()
            Haptics.warning()
            toast.show("Moved to the Trash", tone: .info)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func move(_ entry: Entry, to folder: String) {
        guard entry.parentPath != folder else { return }
        do {
            let newPath = try store.move(entry.relativePath, toFolder: folder)
            var next = profile
            next.items = remapKeys(next.items, from: entry.relativePath, to: newPath)
            next.order = remapOrder(next.order, from: entry.relativePath, to: newPath)
            profile = next
            profileStore?.setProfile(next, reason: ChangeRecord(device: profileStore?.device.id ?? "",
                                                               action: .rename, path: newPath,
                                                               previousPath: entry.relativePath))
            reload()
            Haptics.success()
            toast.show("Moved", tone: .success)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Organization

    func togglePin(_ entry: Entry) {
        mutateProfile({ profile in
            var meta = profile.meta(for: entry.relativePath)
            meta.pinned.toggle()
            profile.items[entry.relativePath] = meta
        }, record: ChangeRecord(device: profileStore?.device.id ?? "", action: .tag, path: entry.relativePath))
        Haptics.tap()
    }

    func toggleFavorite(_ entry: Entry) {
        mutateProfile({ profile in
            var meta = profile.meta(for: entry.relativePath)
            meta.favorite.toggle()
            profile.items[entry.relativePath] = meta
        }, record: ChangeRecord(device: profileStore?.device.id ?? "", action: .tag, path: entry.relativePath))
        Haptics.tap()
    }

    func toggleTag(_ tag: WorkspaceTag, on entry: Entry) {
        mutateProfile({ profile in
            var meta = profile.meta(for: entry.relativePath)
            if let index = meta.tags.firstIndex(of: tag.id) {
                meta.tags.remove(at: index)
            } else {
                meta.tags.append(tag.id)
            }
            profile.items[entry.relativePath] = meta
        }, record: ChangeRecord(device: profileStore?.device.id ?? "", action: .tag, path: entry.relativePath))
        Haptics.select()
    }

    func createTag(name: String, color: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let tag = WorkspaceTag(id: UUID().uuidString, name: clean, color: color)
        mutateProfile({ $0.tags.append(tag) },
                      record: ChangeRecord(device: profileStore?.device.id ?? "", action: .tag, path: SyncKey.tag))
        Haptics.success()
    }

    func deleteTag(_ tag: WorkspaceTag) {
        mutateProfile({ profile in
            profile.tags.removeAll { $0.id == tag.id }
            for (path, var meta) in profile.items {
                meta.tags.removeAll { $0 == tag.id }
                profile.items[path] = meta
            }
        }, record: ChangeRecord(device: profileStore?.device.id ?? "", action: .tag, path: SyncKey.tag))
    }

    func reorder(_ parent: String, moving: String, before target: String) {
        mutateProfile({ profile in
            var order = profile.order[parent] ?? self.children(of: parent).map { $0.relativePath }
            order.removeAll { $0 == moving }
            if let index = order.firstIndex(of: target) {
                order.insert(moving, at: index)
            } else {
                order.append(moving)
            }
            profile.order[parent] = order
        }, record: ChangeRecord(device: profileStore?.device.id ?? "", action: .reorder, path: parent))
    }

    // MARK: - Opening

    func open(_ entry: Entry) {
        openedFile = entry
        recentPaths.removeAll { $0 == entry.relativePath }
        recentPaths.insert(entry.relativePath, at: 0)
        if recentPaths.count > 20 { recentPaths.removeLast(recentPaths.count - 20) }
        persistRecent()
        Haptics.tap()
    }

    func openFolder(_ entry: Entry) {
        filesPath = entry.relativePath
        tab = .files
        Haptics.tap()
    }

    private func persistRecent() {
        guard let currentWorkspace else { return }
        let key = "comet.recent." + LocalStore.workspaceKey(for: currentWorkspace)
        UserDefaults.standard.set(recentPaths, forKey: key)
    }

    // MARK: - Search

    func updateSearch(_ query: String) {
        searchQuery = query
        searchTask?.cancel()
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 1 else {
            searchHits = []
            searching = false
            return
        }
        searching = true
        let snapshot = entries
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            let raw = await Task.detached(priority: .userInitiated) {
                WorkspaceStore.search(query: needle, in: snapshot)
            }.value
            guard !Task.isCancelled, let self else { return }
            let lookup = Dictionary(uniqueKeysWithValues: self.entries.map { ($0.relativePath, $0) })
            self.searchHits = raw.compactMap { hit in
                guard let entry = lookup[hit.relativePath] else { return nil }
                return SearchHit(entry: entry, snippet: hit.snippet)
            }
            self.searching = false
        }
    }

    // MARK: - Calendar

    var events: [CalendarEvent] { profile.events }

    func events(on date: Date) -> [CalendarEvent] {
        let key = CometDate.key(date)
        return profile.events.filter { $0.dateKey == key }
            .sorted { $0.time < $1.time }
    }

    var upcomingEvents: [CalendarEvent] {
        let today = CometDate.key(Date())
        return profile.events.filter { $0.dateKey >= today }
            .sorted { ($0.dateKey, $0.time) < ($1.dateKey, $1.time) }
            .prefix(6).map { $0 }
    }

    func saveEvent(_ event: CalendarEvent) {
        mutateProfile({ profile in
            if let index = profile.events.firstIndex(where: { $0.id == event.id }) {
                profile.events[index] = event
            } else {
                profile.events.append(event)
            }
        }, record: ChangeRecord(device: profileStore?.device.id ?? "", action: .calendar, path: SyncKey.calendar))
        Haptics.success()
    }

    func deleteEvent(_ event: CalendarEvent) {
        mutateProfile({ $0.events.removeAll { $0.id == event.id } },
                      record: ChangeRecord(device: profileStore?.device.id ?? "", action: .calendar, path: SyncKey.calendar))
    }

    func calendarExportURL() -> URL? {
        let text = CalendarExport.ics(profile.events)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Comet calendar.ics")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Feeds

    var feeds: [Feed] { profile.feeds }

    func articles(for feedID: String) -> [FeedArticle] {
        profile.articles.filter { $0.feedID == feedID }
            .sorted { ($0.published ?? .distantPast) > ($1.published ?? .distantPast) }
    }

    var allArticles: [FeedArticle] {
        profile.articles.sorted { ($0.published ?? .distantPast) > ($1.published ?? .distantPast) }
    }

    var unreadArticles: [FeedArticle] {
        let read = profile.readSet
        return allArticles.filter { !read.contains($0.id) }
    }

    func feed(for id: String) -> Feed? { profile.feeds.first { $0.id == id } }

    func unreadCount(for feed: Feed) -> Int {
        let read = profile.readSet
        return profile.articles.filter { $0.feedID == feed.id && !read.contains($0.id) }.count
    }

    var unreadTotal: Int {
        let read = profile.readSet
        return profile.articles.filter { !read.contains($0.id) }.count
    }

    func markRead(_ article: FeedArticle, read: Bool = true) {
        mutateProfile({ $0.markRead(article.id, read: read) }, record: nil)
    }

    func toggleSaved(_ article: FeedArticle) {
        mutateProfile({ $0.toggleSaved(article.id) }, record: nil)
        Haptics.tap()
    }

    func addFeed(_ raw: String) async -> Bool {
        guard let address = FeedAddress.normalize(raw) else {
            errorMessage = "That doesn't look like a feed address."
            return false
        }
        if profile.feeds.contains(where: { $0.url == address }) {
            errorMessage = "That feed is already in the list."
            return false
        }
        do {
            let (data, _) = try await FeedService.fetch(address)
            guard let parsed = FeedParser.parse(data: data, feedID: "pending", fallbackTitle: FeedAddress.host(address)) else {
                errorMessage = "That address isn't a feed Comet can read."
                return false
            }
            let feed = Feed(id: FeedID.new(), title: parsed.title, url: address,
                            color: BoardColor.palette[(address.hashValue & Int.max) % BoardColor.palette.count],
                            symbol: "dot.radiowaves.left.and.right", added: Date())
            let articles = parsed.articles.map { article -> FeedArticle in
                var copy = article
                copy.feedID = feed.id
                copy.id = FeedID.article(feedID: feed.id, identity: article.link.isEmpty ? article.title : article.link)
                return copy
            }
            mutateProfile({ profile in
                profile.feeds.append(feed)
                profile.articles.append(contentsOf: articles)
                self.trimArticles(&profile)
            }, record: ChangeRecord(device: profileStore?.device.id ?? "", action: .feeds, path: SyncKey.feeds))
            Haptics.success()
            toast.show("Added \(parsed.title)", tone: .success)
            return true
        } catch {
            errorMessage = "Couldn't reach that feed. \(error.localizedDescription)"
            return false
        }
    }

    func deleteFeed(_ feed: Feed) {
        mutateProfile({ profile in
            profile.feeds.removeAll { $0.id == feed.id }
            profile.articles.removeAll { $0.feedID == feed.id }
        }, record: ChangeRecord(device: profileStore?.device.id ?? "", action: .feeds, path: SyncKey.feeds))
    }

    func refreshFeeds() async {
        guard !refreshingFeeds, !profile.feeds.isEmpty else { return }
        refreshingFeeds = true
        defer { refreshingFeeds = false }
        var errors: [String: String] = [:]
        var incoming: [FeedArticle] = []
        var titles: [String: String] = [:]

        for feed in profile.feeds {
            do {
                let (data, _) = try await FeedService.fetch(feed.url)
                guard let parsed = FeedParser.parse(data: data, feedID: feed.id, fallbackTitle: feed.title) else {
                    errors[feed.id] = "This feed didn't parse."
                    continue
                }
                titles[feed.id] = parsed.title
                let articles = parsed.articles.map { article -> FeedArticle in
                    var copy = article
                    copy.feedID = feed.id
                    copy.id = FeedID.article(feedID: feed.id, identity: article.link.isEmpty ? article.title : article.link)
                    return copy
                }
                incoming.append(contentsOf: articles)
            } catch {
                errors[feed.id] = error.localizedDescription
            }
        }

        feedErrors = errors
        guard !incoming.isEmpty || !titles.isEmpty else { return }
        mutateProfile({ profile in
            // Newest first per feed, and never more than fifty kept.
            var merged = profile.articles
            for article in incoming {
                if let index = merged.firstIndex(where: { $0.id == article.id }) {
                    merged[index] = article
                } else {
                    merged.append(article)
                }
            }
            profile.articles = merged
            for (id, title) in titles {
                if let index = profile.feeds.firstIndex(where: { $0.id == id }) {
                    profile.feeds[index].title = title
                }
            }
            self.trimArticles(&profile)
        }, record: ChangeRecord(device: profileStore?.device.id ?? "", action: .feeds, path: SyncKey.feeds))
        Haptics.success()
    }

    private func trimArticles(_ profile: inout WorkspaceProfile) {
        var kept: [FeedArticle] = []
        for feed in profile.feeds {
            let items = profile.articles.filter { $0.feedID == feed.id }
                .sorted { ($0.published ?? .distantPast) > ($1.published ?? .distantPast) }
                .prefix(50)
            kept.append(contentsOf: items)
        }
        profile.articles = kept
        let ids = Set(profile.articles.map { $0.id })
        profile.readArticles = profile.readArticles.filter { ids.contains($0) }
        profile.savedArticles = profile.savedArticles.filter { ids.contains($0) }
    }

    func opmlExportURL() -> URL? {
        let text = OPML.export(profile.feeds)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Comet feeds.opml")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch { return nil }
    }

    func importOPML(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            errorMessage = "That OPML file could not be read."
            return
        }
        let found = OPML.importFeeds(data)
        guard !found.isEmpty else {
            errorMessage = "That file doesn't list any feeds."
            return
        }
        mutateProfile({ profile in
            for item in found {
                guard let address = FeedAddress.normalize(item.url),
                      !profile.feeds.contains(where: { $0.url == address }) else { continue }
                profile.feeds.append(Feed(id: FeedID.new(), title: item.title, url: address,
                                          color: BoardColor.palette[profile.feeds.count % BoardColor.palette.count]))
            }
        }, record: ChangeRecord(device: profileStore?.device.id ?? "", action: .feeds, path: SyncKey.feeds))
        toast.show("Imported \(found.count) feeds", tone: .success)
    }

    // MARK: - Export helpers

    func temporaryFile(name: String, contents: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch { return nil }
    }

    /// Sync is not consuming the journal yet, so compacting it is safe and
    /// honest: it drops the facts and changes nothing in the workspace.
    func compactJournal() {
        profileStore?.pruneJournal(keeping: 0)
        sync = profileStore?.summary ?? sync
        toast.show("Journal compacted", tone: .info)
    }

    func defaultName(for kind: EntryKind) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        switch kind {
        case .note: return "Note \(formatter.string(from: Date()))"
        case .todo: return "Board \(formatter.string(from: Date()))"
        case .whiteboard: return "Sketch \(formatter.string(from: Date()))"
        case .folder: return "Folder"
        default: return "Untitled"
        }
    }

    var storageSummary: String {
        let count = entries.count
        let folders = entries.filter { $0.isFolder }.count
        return "\(count) items · \(folders) folders"
    }
}
