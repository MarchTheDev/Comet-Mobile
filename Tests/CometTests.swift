//
//  CometTests.swift
//  CometTests
//
//  The parts of the app that can be checked without a screen: arithmetic, the
//  Markdown subset, Comet's board formats, the calendar and feed encodings, the
//  workspace store's containment, and the pieces future sync leans on.
//

import XCTest
import CryptoKit
@testable import Comet

// MARK: - Calculator

final class CalculatorTests: XCTestCase {
    private func value(_ expression: String) throws -> Double {
        switch Calculator.evaluate(expression) {
        case .success(let number): return number
        case .failure(let error): throw error
        }
    }

    func testMultiplicationBindsTighterThanAddition() throws {
        XCTAssertEqual(try value("2 + 3 * 4"), 14, accuracy: 0.0001)
    }

    func testParentheses() throws {
        XCTAssertEqual(try value("(2 + 3) * 4"), 20, accuracy: 0.0001)
    }

    func testUnaryMinusAndNesting() throws {
        XCTAssertEqual(try value("-(3 + 4) * -2"), 14, accuracy: 0.0001)
    }

    func testDivision() throws {
        XCTAssertEqual(try value("10 / 4"), 2.5, accuracy: 0.0001)
    }

    func testDivisionByZeroIsReported() {
        if case .failure(let error) = Calculator.evaluate("1 / 0") {
            XCTAssertEqual(error, .divisionByZero)
        } else {
            XCTFail("Dividing by zero should fail")
        }
    }

    func testUnfinishedExpressionIsRejected() {
        if case .success = Calculator.evaluate("2 + ") {
            XCTFail("An unfinished expression should not evaluate")
        }
    }

    func testFormatting() {
        XCTAssertEqual(Calculator.format(44), "44")
        XCTAssertEqual(Calculator.format(2.5), "2.5")
        XCTAssertEqual(Calculator.format(-0.125), "-0.125")
    }
}

// MARK: - Tools

final class ToolTests: XCTestCase {
    func testPercentOf() {
        XCTAssertEqual(PercentTool.percentOf(15, 200), 30, accuracy: 0.0001)
    }

    func testChange() {
        XCTAssertEqual(try XCTUnwrap(PercentTool.change(from: 100, to: 120)), 20, accuracy: 0.0001)
    }

    func testTax() {
        let result = PercentTool.withTax(100, rate: 22)
        XCTAssertEqual(result.net, 100, accuracy: 0.0001)
        XCTAssertEqual(result.tax, 22, accuracy: 0.0001)
        XCTAssertEqual(result.gross, 122, accuracy: 0.0001)
    }

    func testTemperatureConversion() {
        XCTAssertEqual(UnitCategory.convertTemperature(100, from: "°C", to: "°F"), 212, accuracy: 0.0001)
        XCTAssertEqual(UnitCategory.convertTemperature(32, from: "°F", to: "°C"), 0, accuracy: 0.0001)
        XCTAssertEqual(UnitCategory.convertTemperature(0, from: "°C", to: "K"), 273.15, accuracy: 0.0001)
    }

    func testLengthConversion() throws {
        let category = try XCTUnwrap(UnitCategory.all.first { $0.name == "Length" })
        let metres = try XCTUnwrap(category.units.first { $0.symbol == "m" })
        let kilometres = try XCTUnwrap(category.units.first { $0.symbol == "km" })
        XCTAssertEqual(category.convert(1500, from: metres, to: kilometres), 1.5, accuracy: 0.000001)
    }

    func testPasswordGeneratorRespectsLengthAndUsesSeveralClasses() {
        let password = PasswordGenerator.generate(length: 24)
        XCTAssertEqual(password.count, 24)
        XCTAssertTrue(password.contains { $0.isUppercase })
        XCTAssertTrue(password.contains { $0.isLowercase })
        XCTAssertTrue(password.contains { $0.isNumber })
        XCTAssertGreaterThan(PasswordGenerator.strength(of: password), 0.6)
        XCTAssertLessThan(PasswordGenerator.strength(of: "abc"), 0.4)
    }
}

// MARK: - Markdown

final class MarkdownTests: XCTestCase {
    func testHeadingsParagraphsAndRules() {
        let blocks = Markdown.blocks("# Title\n\nA paragraph.\n\n---")
        guard blocks.count >= 3 else { return XCTFail("expected three blocks, got \(blocks.count)") }
        guard case .heading(let level, let inlines) = blocks[0] else { return XCTFail("expected a heading") }
        XCTAssertEqual(level, 1)
        XCTAssertEqual(Markdown.plainText(inlines), "Title")
        guard case .paragraph = blocks[1] else { return XCTFail("expected a paragraph") }
        guard case .rule = blocks[2] else { return XCTFail("expected a rule") }
    }

    func testTaskListKeepsItsBoxes() {
        let blocks = Markdown.blocks("- [ ] write\n- [x] ship")
        guard case .bullets(let items) = blocks.first else { return XCTFail("expected bullets") }
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items[0].box)
        XCTAssertFalse(items[0].done)
        XCTAssertTrue(items[1].done)
    }

    func testFencedCodeKeepsLanguageAndBody() {
        let blocks = Markdown.blocks("```swift\nlet a = 1\n```")
        guard case .code(let language, let text) = blocks.first else { return XCTFail("expected code") }
        XCTAssertEqual(language, "swift")
        XCTAssertEqual(text, "let a = 1")
    }

    func testQuoteAndTable() {
        let blocks = Markdown.blocks("> quiet\n\n| a | b |\n| --- | --- |\n| 1 | 2 |")
        guard blocks.count >= 2 else { return XCTFail("expected a quote and a table") }
        guard case .quote = blocks[0] else { return XCTFail("expected a quote") }
        guard case .table(let header, let rows) = blocks[1] else { return XCTFail("expected a table") }
        XCTAssertEqual(header, ["a", "b"])
        XCTAssertEqual(rows, [["1", "2"]])
    }

    func testInlineStyling() {
        let bold = Markdown.inline("**bold**")
        XCTAssertEqual(bold, [.strong("bold")])
        let soft = Markdown.inline("*soft*")
        XCTAssertEqual(soft, [.emphasis("soft")])
        XCTAssertEqual(Markdown.inline("`code`"), [.code("code")])
        XCTAssertEqual(Markdown.inline("[Comet](https://example.com)"),
                       [.link(label: "Comet", href: "https://example.com")])
        let mixed = Markdown.inline("a **b** c")
        XCTAssertTrue(mixed.contains(.strong("b")))
        XCTAssertEqual(Markdown.plainText(mixed), "a b c")
    }

    func testTitleFallsBackToTheFirstLine() {
        XCTAssertEqual(Markdown.title(of: "# Aurora\n\nbody", fallback: "Untitled"), "Aurora")
        XCTAssertEqual(Markdown.title(of: "", fallback: "Untitled"), "Untitled")
    }

    func testSummaryStripsMarkdown() {
        let summary = Markdown.plainSummary(of: "## Heading\n\nSome **bold** text and a [link](https://x.dev).", limit: 80)
        XCTAssertFalse(summary.contains("**"))
        XCTAssertFalse(summary.contains("##"))
        XCTAssertTrue(summary.contains("bold"))
    }
}

// MARK: - Boards

final class BoardTests: XCTestCase {
    private let todoJSON = """
    {
      "format": "comet-todo",
      "version": 3,
      "tasks": [
        {"id": "t1", "text": "Feed the starter", "done": false, "categoryId": "today"},
        {"id": "t2", "text": "Bake", "done": true, "categoryId": null}
      ],
      "categories": [
        {"id": "today", "title": "Today", "color": "#9c9fe1"}
      ],
      "connections": []
    }
    """

    func testParsingADesktopBoard() throws {
        let document = try XCTUnwrap(TodoDocument.parse(todoJSON))
        XCTAssertEqual(document.version, 3)
        XCTAssertEqual(document.tasks.count, 2)
        XCTAssertEqual(document.tasks(in: "today").count, 1)
        XCTAssertEqual(document.openCount, 1)
        XCTAssertEqual(document.categories.first?.title, "Today")
    }

    func testRoundTripKeepsEverything() throws {
        var document = try XCTUnwrap(TodoDocument.parse(todoJSON))
        document.addTask("Shape", categoryID: "today")
        let serialized = document.serialized()
        XCTAssertEqual(TodoDocument.parse(serialized), document)
        XCTAssertTrue(serialized.contains("\"format\" : \"comet-todo\""))
        XCTAssertTrue(serialized.contains("\"version\" : 3"))
    }

    func testTogglingATaskCompletesItsSubtasks() {
        var document = TodoDocument()
        document.tasks = [TodoTask(id: "a", text: "Parent",
                                   subtasks: [TodoSubtask(id: "s", text: "Child")])]
        document.toggle("a")
        XCTAssertTrue(document.tasks[0].done)
        XCTAssertTrue(document.tasks[0].subtasks[0].done)
    }

    func testMovingATaskChangesItsList() throws {
        var document = try XCTUnwrap(TodoDocument.parse(todoJSON))
        document.move("t2", to: "today")
        XCTAssertEqual(document.tasks(in: "today").count, 2)
    }

    func testANewerBoardOpensWithoutLosingFields() {
        let future = """
        {"format":"comet-todo","version":9,"tasks":[],"categories":[],"connections":[],"unknown":[1,2]}
        """
        XCTAssertNotNil(TodoDocument.parse(future))
    }

    func testWhiteboardRoundTrip() {
        var document = WhiteboardDocument()
        document.items = [WhiteboardItem(type: .text, x: 10, y: 20, text: "rain", color: "#9c9fe1")]
        document.strokes = [WhiteboardStroke(points: [WhiteboardStroke.Point(x: 0, y: 0)])]
        let serialized = document.serialized()
        XCTAssertEqual(WhiteboardDocument.parse(serialized), document)
        XCTAssertTrue(serialized.contains("\"version\" : 5"))
    }

    func testOlderWhiteboardStillParses() throws {
        let legacy = """
        {"format":"comet-whiteboard","version":2,"items":[{"type":"text","x":1,"y":2,"text":"old"}]}
        """
        let document = try XCTUnwrap(WhiteboardDocument.parse(legacy))
        XCTAssertEqual(document.items.count, 1)
        XCTAssertEqual(document.version, 2)
    }
}

// MARK: - Calendar

final class CalendarTests: XCTestCase {
    func testDateKeysRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_765_000_000)
        let key = CometDate.key(date)
        let parsed = try XCTUnwrap(CometDate.date(fromKey: key))
        XCTAssertTrue(CalendarMath.isSameDay(date, parsed))
    }

    func testMonthGridStartsOnMondayWhenAsked() {
        let month = CalendarMath.startOfMonth(Date(timeIntervalSince1970: 1_765_000_000))
        let grid = CalendarMath.monthGrid(for: month, weekStartsOnMonday: true)
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        XCTAssertEqual(calendar.component(.weekday, from: grid[0]), 2)
        XCTAssertEqual(grid.count % 7, 0)
    }

    func testICSEscapesAndFolds() {
        let event = CalendarEvent(id: "e1", title: "Dinner, with Elena; bring wine",
                                  dateKey: "2026-11-17", time: "18:30",
                                  notes: "Line one\nLine two")
        let ics = CalendarExport.ics([event])
        XCTAssertTrue(ics.hasPrefix("BEGIN:VCALENDAR\r\n"))
        XCTAssertTrue(ics.contains("SUMMARY:Dinner\\, with Elena\\; bring wine"))
        XCTAssertTrue(ics.contains("DESCRIPTION:Line one\\nLine two"))
        XCTAssertTrue(ics.contains("DTSTART:20261117T183000"))
        XCTAssertTrue(ics.hasSuffix("END:VCALENDAR\r\n"))
        for line in ics.components(separatedBy: "\r\n") {
            XCTAssertLessThanOrEqual(line.utf8.count, 75, "ICS lines fold at 75 octets: \(line)")
        }
    }

    func testAllDayEventUsesADate() {
        let ics = CalendarExport.ics([CalendarEvent(id: "e2", title: "Birthday", dateKey: "2026-11-18")])
        XCTAssertTrue(ics.contains("DTSTART;VALUE=DATE:20261118"))
    }
}

// MARK: - Feeds

final class FeedTests: XCTestCase {
    private let rss = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0"><channel>
      <title>Example feed</title>
      <item>
        <title>First &amp; best</title>
        <link>https://example.com/one</link>
        <description>&lt;p&gt;A &lt;b&gt;short&lt;/b&gt; summary.&lt;/p&gt;</description>
        <pubDate>Tue, 17 Nov 2026 08:30:00 +0000</pubDate>
        <guid>one</guid>
      </item>
    </channel></rss>
    """

    func testParsingRSS() throws {
        let parsed = try XCTUnwrap(FeedParser.parse(data: Data(rss.utf8), feedID: "f1", fallbackTitle: "Fallback"))
        XCTAssertEqual(parsed.title, "Example feed")
        XCTAssertEqual(parsed.articles.count, 1)
        XCTAssertEqual(parsed.articles[0].title, "First & best")
        XCTAssertEqual(parsed.articles[0].feedID, "f1")
        XCTAssertNotNil(parsed.articles[0].published)
    }

    func testGarbageIsNotAFeed() {
        XCTAssertNil(FeedParser.parse(data: Data("not a feed".utf8), feedID: "f", fallbackTitle: "x"))
    }

    func testFeedDates() {
        XCTAssertNotNil(FeedDate.parse("Tue, 17 Nov 2026 08:30:00 +0000"))
        XCTAssertNotNil(FeedDate.parse("2026-11-17T08:30:00Z"))
        XCTAssertNotNil(FeedDate.parse("2026-11-17"))
        XCTAssertNil(FeedDate.parse("sometime"))
    }

    func testHTMLBecomesText() {
        XCTAssertEqual(HTMLText.plain("<p>Hello <b>there</b>&nbsp;friend</p>"), "Hello there friend")
        XCTAssertFalse(HTMLText.plain("<script>alert(1)</script>hi").contains("alert(1)"))
    }

    func testAddressesAreNormalised() {
        XCTAssertEqual(FeedAddress.normalize("example.com/feed"), "https://example.com/feed")
        XCTAssertEqual(FeedAddress.normalize("https://example.com/feed"), "https://example.com/feed")
        XCTAssertNil(FeedAddress.normalize("   "))
    }

    func testOPMLRoundTrip() {
        let feeds = [Feed(id: "1", title: "Comet & Co", url: "https://example.com/rss")]
        let opml = OPML.export(feeds)
        XCTAssertTrue(opml.contains("Comet &amp; Co"))
        let imported = OPML.importFeeds(Data(opml.utf8))
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported[0].title, "Comet & Co")
        XCTAssertEqual(imported[0].url, "https://example.com/rss")
    }

    func testArticleIDsAreStable() {
        XCTAssertEqual(FeedID.article(feedID: "f", identity: "one"),
                       FeedID.article(feedID: "f", identity: "one"))
        XCTAssertNotEqual(FeedID.article(feedID: "f", identity: "one"),
                          FeedID.article(feedID: "f", identity: "two"))
    }
}

// MARK: - Workspace and profile

final class WorkspaceTests: XCTestCase {
    private var folder: URL!
    private var store: WorkspaceStore!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        store = WorkspaceStore()
        store.open(url: folder)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testStoreWritesReadsAndRefusesEscapes() throws {
        _ = try store.createFile(folder: "", name: "First.md", contents: "# First")
        XCTAssertEqual(try store.readText("First.md"), "# First")
        XCTAssertEqual(store.entry(at: "")?.kind, .folder)
        XCTAssertThrowsError(try store.readText("../outside.txt"))
        XCTAssertThrowsError(try store.createFile(folder: "", name: "../escape.md", contents: "no"))
    }

    func testRenameMoveAndTrash() throws {
        _ = try store.createFile(folder: "", name: "a.md", contents: "a")
        _ = try store.createFolder(folder: "", name: "archive")
        XCTAssertEqual(try store.rename("a.md", to: "b.md"), "b.md")
        XCTAssertEqual(try store.move("b.md", toFolder: "archive"), "archive/b.md")
        try store.trash("archive/b.md")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("archive/b.md").path))
    }

    func testNamesAreMadeUnique() throws {
        _ = try store.createFile(folder: "", name: "Ideas.md", contents: "one")
        let second = try store.createFile(folder: "", name: "Ideas.md", contents: "two")
        XCTAssertEqual(second.name, "Ideas 2.md")
        XCTAssertEqual(try store.readText("Ideas.md"), "one")
    }

    func testSearchLooksInsideNotes() throws {
        _ = try store.createFile(folder: "", name: "aurora.md", contents: "The sky was green over the canal.")
        _ = try store.createFile(folder: "", name: "other.md", contents: "Nothing to see.")
        let hits = WorkspaceStore.search(query: "green", in: store.scan())
        XCTAssertEqual(hits.first?.relativePath, "aurora.md")
    }

    func testScanFindsNestedFoldersAndBoards() throws {
        _ = try store.createFolder(folder: "", name: "journal")
        _ = try store.createFile(folder: "journal", name: "Night.comet-whiteboard",
                                 contents: WhiteboardDocument().serialized())
        let entries = store.scan()
        XCTAssertEqual(entries.first { $0.name == "journal" }?.kind, .folder)
        XCTAssertEqual(entries.first { $0.name == "Night.comet-whiteboard" }?.kind, .whiteboard)
    }

    func testWorkspaceKeyFollowsTheFolderNotTheBookmark() {
        let ref = WorkspaceRef(id: "1", name: "Comet", bookmark: Data([1, 2, 3]),
                               pathHint: "/private/a/Comet", added: Date())
        let moved = WorkspaceRef(id: "2", name: "Comet", bookmark: Data([9]),
                                 pathHint: "/private/a/Comet", added: Date())
        let other = WorkspaceRef(id: "3", name: "Comet", bookmark: Data([1]),
                                 pathHint: "/private/b/Comet", added: Date())
        XCTAssertEqual(LocalStore.workspaceKey(for: ref), LocalStore.workspaceKey(for: moved))
        XCTAssertNotEqual(LocalStore.workspaceKey(for: ref), LocalStore.workspaceKey(for: other))
    }

    func testProfileSurvivesUnknownFields() throws {
        var profile = WorkspaceProfile()
        profile.tags["aurora.md"] = ItemMeta(tags: ["night"], pinned: true)
        profile.order[""] = ["aurora.md"]
        let data = try JSONEncoder().encode(profile)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["somethingFromTheFuture"] = ["a": 1]
        let patched = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(WorkspaceProfile.self, from: patched)
        XCTAssertEqual(decoded.tags["aurora.md"]?.tags, ["night"])
        XCTAssertTrue(decoded.meta("aurora.md").pinned)
    }

    func testJournalRecordsFacts() {
        var journal = SyncJournal()
        journal.record(ChangeRecord(device: "Test", action: .create,
                                    path: "notes/First.md", digest: Digest.of("hello")))
        XCTAssertEqual(journal.records.count, 1)
        XCTAssertEqual(journal.records.first?.path, "notes/First.md")
        XCTAssertEqual(journal.records.first?.action, .create)
    }

    func testDigestsAreStable() {
        XCTAssertEqual(Digest.of("hello"), Digest.of("hello"))
        XCTAssertNotEqual(Digest.of("hello"), Digest.of("hello!"))
    }
}

// MARK: - Vault

final class VaultCryptoTests: XCTestCase {
    private func key() -> SymmetricKey { SymmetricKey(data: VaultCrypto.randomBytes(32)) }

    func testSealingAndOpeningRoundTrips() throws {
        let key = self.key()
        let payload = Data("{\"entries\":[]}".utf8)
        let sealed = try XCTUnwrap(VaultCrypto.seal(payload, key: key))
        XCTAssertEqual(try XCTUnwrap(VaultCrypto.open(iv: sealed.iv, ciphertext: sealed.ciphertext, key: key)),
                       payload)
    }

    func testTheWrongKeyDoesNotOpen() throws {
        let sealed = try XCTUnwrap(VaultCrypto.seal(Data("secret".utf8), key: key()))
        XCTAssertNil(VaultCrypto.open(iv: sealed.iv, ciphertext: sealed.ciphertext, key: key()))
    }

    func testRandomBytesAreRandom() {
        XCTAssertNotEqual(VaultCrypto.randomBytes(16), VaultCrypto.randomBytes(16))
    }

    func testTheEnvelopeIsComet() throws {
        var data = PasswordData()
        data.entries = [PasswordEntry(id: "p1", name: "GitHub", username: "march", password: "hunter2")]
        let salt = VaultCrypto.randomBytes(VaultCrypto.saltBytes)
        // The tests use a low iteration count only because they are tests; the
        // app always writes 600,000 and refuses envelopes below it.
        let text = try VaultCrypto.makeEnvelope(data, password: "correct horse", salt: salt, iterations: 600_000)
        XCTAssertTrue(text.contains("\"format\":\"comet-passwords\"") || text.contains("\"format\" : \"comet-passwords\""))
        let envelope = try XCTUnwrap(VaultCrypto.readEnvelope(text))
        XCTAssertEqual(envelope.iterations, 600_000)
        let opened = try VaultCrypto.unlock(raw: text, password: "correct horse")
        XCTAssertEqual(opened.data.entries.first?.name, "GitHub")
        XCTAssertThrowsError(try VaultCrypto.unlock(raw: text, password: "wrong"))
    }

    func testRecoveryCodesAreReadableAndUnique() {
        let one = VaultCrypto.generateRecoveryCode()
        let two = VaultCrypto.generateRecoveryCode()
        XCTAssertNotEqual(one, two)
        XCTAssertTrue(one.contains("-"))
    }
}
