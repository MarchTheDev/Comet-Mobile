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
}
