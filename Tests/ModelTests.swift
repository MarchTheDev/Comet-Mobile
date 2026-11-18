//
//  ModelTests.swift
//  CometTests
//
//  The model is what the screens call, so these tests call it the way a screen
//  does: open a folder, make a note, make a folder, go into it, make another
//  note. They exist because "the buttons do nothing" is not a symptom that a
//  compile can catch.
//

import XCTest
@testable import Comet

@MainActor
final class ModelTests: XCTestCase {
    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("comet-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func exists(_ folder: URL, _ name: String) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path)
    }

    func testOpeningAPickedFolderAndWritingIntoIt() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let model = CometModel()
        model.addWorkspace(url: folder)

        XCTAssertEqual(model.currentWorkspace?.pathHint, folder.path)
        XCTAssertTrue(model.isWorkspaceReachable)

        let note = try XCTUnwrap(model.createNote(named: "Hello"))
        XCTAssertEqual(note.relativePath, "Hello.md")
        XCTAssertTrue(exists(folder, "Hello.md"))
        XCTAssertTrue(model.entries.contains { $0.relativePath == "Hello.md" })

        let project = try XCTUnwrap(model.createFolder(named: "Projects"))
        XCTAssertEqual(project.relativePath, "Projects")
        XCTAssertTrue(model.entries.contains { $0.relativePath == "Projects" })

        model.openFolder(project)
        XCTAssertEqual(model.filesPath, "Projects")

        let inside = try XCTUnwrap(model.createNote(named: "Inside"))
        XCTAssertEqual(inside.relativePath, "Projects/Inside.md")
        XCTAssertTrue(exists(folder, "Projects/Inside.md"))
    }

    func testABoardIsWrittenInCometsFormat() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let model = CometModel()
        model.addWorkspace(url: folder)
        let board = try XCTUnwrap(model.createBoard(.todo, named: "Release"))

        XCTAssertEqual(board.relativePath, "Release.comet-todo")
        let text = try String(contentsOf: folder.appendingPathComponent("Release.comet-todo"), encoding: .utf8)
        XCTAssertTrue(text.contains("\"format\" : \"comet-todo\""))
        XCTAssertNotNil(TodoDocument.parse(text))
    }

    func testWritingAndReadingANoteThroughTheModel() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let model = CometModel()
        model.addWorkspace(url: folder)
        let note = try XCTUnwrap(model.createNote(named: "Draft"))
        XCTAssertTrue(model.saveText("# Draft\n\nWords.", at: note))
        XCTAssertEqual(model.readText(note), "# Draft\n\nWords.")
    }

    func testRenamingAndDeleting() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let model = CometModel()
        model.addWorkspace(url: folder)
        let note = try XCTUnwrap(model.createNote(named: "Working title"))

        model.rename(note, to: "Final title")
        XCTAssertTrue(exists(folder, "Final title.md"))
        XCTAssertFalse(exists(folder, "Working title.md"))

        let renamed = try XCTUnwrap(model.entries.first { $0.relativePath == "Final title.md" })
        model.delete(renamed)
        XCTAssertFalse(exists(folder, "Final title.md"))
    }

    func testOpeningAWorkspaceSurvivesABrokenBookmark() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        // What a reinstall, a restore or a moved folder looks like: the bookmark
        // is meaningless, the path still names a real folder.
        let ref = WorkspaceRef(id: "test", name: "Comet", bookmark: Data([0, 1, 2, 3]),
                               pathHint: folder.path, added: Date())
        let store = WorkspaceStore()
        XCTAssertNoThrow(try store.open(ref))
        XCTAssertTrue(store.isReachable)
        XCTAssertNotNil(store.url(for: ""))
    }

    func testCreatingPutsItselfInTheJournal() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let model = CometModel()
        model.addWorkspace(url: folder)
        let before = model.sync.pendingChanges
        _ = model.createNote(named: "Recorded")
        XCTAssertGreaterThan(model.sync.pendingChanges, before)
    }

    func testTheWorkspaceRepairKeepsTheFolder() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let model = CometModel()
        model.addWorkspace(url: folder)
        XCTAssertTrue(model.repairWorkspace())
        XCTAssertEqual(model.currentWorkspace?.pathHint, folder.path)
    }

    // MARK: - Paths

    /// The bug this guards against: iOS hands out `/var/...` for a container
    /// whose real path is `/private/var/...`, and the workspace used to compare
    /// standardized paths with `hasPrefix` — which failed for every name that
    /// did not exist yet, so creating anything answered "That name is not
    /// allowed". The folder below is reached through a symlinked parent, the
    /// way a container is.
    func testCreatingWorksWhenTheWorkspaceSitsUnderASymlinkedPath() throws {
        let realRoot = try temporaryFolder()
        let folder = realRoot.appendingPathComponent("Workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let link = realRoot.deletingLastPathComponent()
            .appendingPathComponent("comet-link-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: realRoot)
        defer {
            try? FileManager.default.removeItem(at: link)
            try? FileManager.default.removeItem(at: realRoot)
        }

        let throughLink = link.appendingPathComponent("Workspace", isDirectory: true)
        let store = WorkspaceStore()
        store.open(url: throughLink)

        let entry = try store.createFile(folder: "", name: "Linked.md", contents: "hello")
        XCTAssertEqual(entry.relativePath, "Linked.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Linked.md").path))
        XCTAssertEqual(try store.readText(entry.relativePath), "hello")

        let nested = try store.createFolder(folder: "", name: "Deep")
        let inside = try store.createFile(folder: nested.relativePath, name: "In.md", contents: "in")
        XCTAssertEqual(inside.relativePath, "Deep/In.md")

        // Listing must agree with creating, however the path is spelled.
        XCTAssertTrue(store.scan().contains { $0.relativePath == "Deep/In.md" })
        // And a child reached by its real path is still named inside the root.
        XCTAssertEqual(store.relativePath(of: folder.appendingPathComponent("Deep/In.md")),
                       "Deep/In.md")
    }

    func testTheModelCanStillCreateAfterOpeningASymlinkedWorkspace() throws {
        let real = try temporaryFolder()
        let link = FileManager.default.temporaryDirectory
            .appendingPathComponent("comet-link-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        defer {
            try? FileManager.default.removeItem(at: link)
            try? FileManager.default.removeItem(at: real)
        }

        let model = CometModel()
        model.addWorkspace(url: link)
        let note = try XCTUnwrap(model.createNote(named: "Through the link"))
        XCTAssertEqual(note.relativePath, "Through the link.md")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: real.appendingPathComponent("Through the link.md").path))
    }

    func testAPathCannotEscapeTheWorkspace() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = WorkspaceStore()
        store.open(url: folder)
        XCTAssertNotNil(store.url(for: "untitled.md"))
        XCTAssertNil(store.url(for: "../escape.md"))
        XCTAssertNil(store.url(for: "a/../../escape.md"))
        XCTAssertNil(store.url(for: "."))
    }
}
