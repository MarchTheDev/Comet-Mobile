//
//  Services.swift
//  Comet
//
//  Three small services the model leans on: the first-run workspace, the feed
//  fetcher, and the calendar's .ics writer.
//

import Foundation

// MARK: - First run

enum StarterWorkspace {
    /// A workspace with something in it, so the app opens with a place to stand
    /// rather than an empty folder and an apology.
    static func seed(in folder: URL) {
        let manager = FileManager.default
        try? manager.createDirectory(at: folder.appendingPathComponent("Notes", isDirectory: true),
                                     withIntermediateDirectories: true)
        try? manager.createDirectory(at: folder.appendingPathComponent("Boards", isDirectory: true),
                                     withIntermediateDirectories: true)

        let welcome = """
        # Welcome to Comet

        Comet is a workspace, not an account. Everything you make here is an
        ordinary file in this folder — readable by any other app, backed up by
        whatever backs up your device, and yours to move.

        ## What is in this app

        - **Today** gathers what you touched, what is pinned and what is
          happening, so you do not have to go looking.
        - **Files** is the folder itself: notes, boards and media, with tags,
          pins and favourites.
        - **Studio** holds to-do boards and whiteboards, saved as
          `.comet-todo` and `.comet-whiteboard` documents that the desktop app
          opens too.
        - **The orb** in the dock opens the rest: the calendar, feeds, the
          password vault, the tools, sync and settings.

        ## The three things worth trying first

        1. Press the orb, then **Passwords**, and give the vault a master
           password. It is encrypted on this device with AES-256-GCM.
        2. Press the orb, then **Feeds**, and add a site. Paste its address; the
           reader finds the feed.
        3. Open the board in `Boards/`, drag a card between lists, then open
           `Boards/Sketch` and draw on it.

        ## Where things live

        Files live in this folder. Tags, pins, favourites, the calendar, feeds
        and their read state live in Comet's own storage beside the app, keyed
        to this workspace — which is what the sync setting will one day carry
        between devices. The vault never leaves this device unencrypted.

        — Comet
        """
        write(welcome, to: folder.appendingPathComponent("Notes/Welcome.md"), manager: manager)

        var board = TodoDocument()
        let ideas = TodoCategory(title: "Today", color: "#9c9fe1")
        var later = TodoCategory(title: "Later", color: "#7dd3fc")
        board.categories = [ideas, later]
        board.tasks = [
            TodoTask(text: "Read the welcome note", done: true, x: 100, y: 110, categoryID: ideas.id, subtasks: []),
            TodoTask(text: "Try a whiteboard", x: 100, y: 194, categoryID: ideas.id, subtasks: []),
            TodoTask(text: "Add a feed to the reader", x: 100, y: 278, categoryID: ideas.id, subtasks: []),
            TodoTask(text: "Set up the password vault", x: 100, y: 362, categoryID: later.id, subtasks: []),
        ]
        write(board.serialized(), to: folder.appendingPathComponent("Boards/Start here.comet-todo"), manager: manager)

        var sketch = WhiteboardDocument()
        var note = WhiteboardItem(type: .text, x: 90, y: 90, text: "A whiteboard is just a file.", color: "#9c9fe1", width: 260, height: 120)
        note.title = "Start"
        var list = WhiteboardItem(type: .todo, x: 400, y: 220, color: "#7dd3fc", width: 240, height: 150)
        list.title = "Things"
        list.todos = [
            WhiteboardTodoEntry(text: "Draw with a finger or a pencil"),
            WhiteboardTodoEntry(text: "Drag a card anywhere"),
            WhiteboardTodoEntry(text: "It saves as you go"),
        ]
        sketch.items = [note, list]
        sketch.connections = [WhiteboardConnection(from: note.id, to: list.id, color: "#9c9fe1")]
        write(sketch.serialized(), to: folder.appendingPathComponent("Boards/Sketch.comet-whiteboard"), manager: manager)

        let ideas2 = """
        # Ideas

        A second note, so the library has more than one thing in it.

        - [ ] Something to remember
        - [ ] Something to try

        Tags, pins and favourites are in the item's menu (press and hold it).
        """
        write(ideas2, to: folder.appendingPathComponent("Notes/Ideas.md"), manager: manager)
    }

    private static func write(_ text: String, to url: URL, manager: FileManager) {
        guard !manager.fileExists(atPath: url.path) else { return }
        try? Data(text.utf8).write(to: url, options: .atomic)
    }
}

// MARK: - Feeds

enum FeedServiceError: LocalizedError {
    case badAddress
    case badResponse(Int)
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .badAddress: return "That address isn't valid."
        case .badResponse(let code): return "The site answered with \(code)."
        case .tooLarge: return "That feed is larger than 8 MB."
        }
    }
}

enum FeedService {
    static func fetch(_ address: String) async throws -> (Data, HTTPURLResponse?) {
        guard let url = URL(string: address), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            throw FeedServiceError.badAddress
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(
            "Comet/1.0 (iOS) feed reader; +https://github.com/MarchTheDev/Comet",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(
            "application/rss+xml, application/atom+xml, application/feed+json, application/json, application/xml, text/xml;q=0.9, */*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FeedServiceError.badResponse(http.statusCode)
        }
        guard data.count <= 8 * 1024 * 1024 else { throw FeedServiceError.tooLarge }
        return (data, response as? HTTPURLResponse)
    }
}

// MARK: - Calendar export

enum CalendarExport {
    static func ics(_ events: [CalendarEvent]) -> String {
        let stamp = isoStamp(Date())
        var lines: [String] = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Comet//Calendar//EN",
            "CALSCALE:GREGORIAN",
        ]
        for event in events {
            let date = event.dateKey.replacingOccurrences(of: "-", with: "")
            guard date.count == 8 else { continue }
            lines.append("BEGIN:VEVENT")
            lines.append("UID:\(escape(event.id))@comet.local")
            lines.append("DTSTAMP:\(stamp)")
            if event.time.isEmpty {
                lines.append("DTSTART;VALUE=DATE:\(date)")
            } else {
                lines.append("DTSTART:\(date)T\(event.time.replacingOccurrences(of: ":", with: ""))00")
            }
            lines.append("SUMMARY:\(escape(event.title))")
            if !event.notes.isEmpty {
                lines.append("DESCRIPTION:\(escape(event.notes))")
            }
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    private static func isoStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
    }

    /// RFC 5545 folds content lines at 75 octets, never inside a character.
    private static func fold(_ line: String) -> String {
        var pieces: [String] = []
        var current = ""
        var bytes = 0
        for character in line {
            let count = String(character).utf8.count
            if bytes + count > 75 {
                pieces.append(current)
                current = " "
                bytes = 1
            }
            current.append(character)
            bytes += count
        }
        pieces.append(current)
        return pieces.joined(separator: "\r\n")
    }
}
