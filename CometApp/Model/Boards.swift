//
//  Boards.swift
//  Comet
//
//  To-do boards and whiteboards are Comet documents, not app database rows: a
//  `.comet-todo` or `.comet-whiteboard` JSON file in the workspace that the
//  desktop app can open too. These types read and write that format rather than
//  a private one, so a board made here is still a Comet board.
//

import Foundation
import SwiftUI

// MARK: - To-do board

struct TodoSubtask: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var text: String = ""
    var done: Bool = false
}

struct TodoTask: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var text: String = ""
    var done: Bool = false
    var notes: String = ""
    var x: Double = 0
    var y: Double = 0
    var categoryID: String? = nil
    var subtasks: [TodoSubtask] = []

    enum CodingKeys: String, CodingKey {
        case id, text, done, notes, x, y, categoryId, subtasks
    }

    init(id: String = UUID().uuidString, text: String = "", done: Bool = false,
         notes: String = "", x: Double = 0, y: Double = 0,
         categoryID: String? = nil, subtasks: [TodoSubtask] = []) {
        self.id = id
        self.text = text
        self.done = done
        self.notes = notes
        self.x = x
        self.y = y
        self.categoryID = categoryID
        self.subtasks = subtasks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        done = (try? c.decode(Bool.self, forKey: .done)) ?? false
        notes = (try? c.decode(String.self, forKey: .notes)) ?? ""
        x = (try? c.decode(Double.self, forKey: .x)) ?? 0
        y = (try? c.decode(Double.self, forKey: .y)) ?? 0
        categoryID = try? c.decodeIfPresent(String.self, forKey: .categoryId)
        subtasks = (try? c.decode([TodoSubtask].self, forKey: .subtasks)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(text, forKey: .text)
        try c.encode(done, forKey: .done)
        try c.encode(notes, forKey: .notes)
        try c.encode(x, forKey: .x)
        try c.encode(y, forKey: .y)
        try c.encode(categoryID, forKey: .categoryId)
        try c.encode(subtasks, forKey: .subtasks)
    }
}

struct TodoCategory: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var title: String = "List"
    var color: String = "#9c9fe1"
}

struct TodoConnection: Codable, Hashable {
    var from: String
    var to: String
    var color: String = "#9c9fe1"
}

struct TodoListConnection: Codable, Hashable {
    var from: String
    var to: String
}

struct TodoDocument: Codable, Equatable {
    static let connectionColor = "#9c9fe1"

    var format: String = "comet-todo"
    var version: Int = 3
    var tasks: [TodoTask] = []
    var categories: [TodoCategory] = []
    var connections: [TodoConnection] = []
    var legacyListConnections: [TodoListConnection] = []

    enum CodingKeys: String, CodingKey {
        case format, version, tasks, categories, connections, legacyListConnections
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = (try? c.decode(String.self, forKey: .format)) ?? "comet-todo"
        version = (try? c.decode(Int.self, forKey: .version)) ?? 3
        tasks = (try? c.decode([TodoTask].self, forKey: .tasks)) ?? []
        categories = (try? c.decode([TodoCategory].self, forKey: .categories)) ?? []
        connections = (try? c.decode([TodoConnection].self, forKey: .connections)) ?? []
        legacyListConnections = (try? c.decode([TodoListConnection].self, forKey: .legacyListConnections)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("comet-todo", forKey: .format)
        try c.encode(3, forKey: .version)
        try c.encode(tasks, forKey: .tasks)
        try c.encode(categories, forKey: .categories)
        try c.encode(connections, forKey: .connections)
        try c.encode(legacyListConnections, forKey: .legacyListConnections)
    }

    static func parse(_ text: String) -> TodoDocument? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TodoDocument.self, from: data)
    }

    func serialized() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return "{}" }
        return (String(data: data, encoding: .utf8) ?? "{}") + "\n"
    }

    func tasks(in categoryID: String?) -> [TodoTask] {
        tasks.filter { $0.categoryID == categoryID }
    }

    var openCount: Int { tasks.filter { !$0.done }.count }

    mutating func addTask(_ text: String, categoryID: String?) {
        let count = tasks(in: categoryID).count
        let task = TodoTask(text: text, x: 100, y: 110 + Double(count) * 84, categoryID: categoryID)
        tasks.append(task)
    }

    mutating func toggle(_ id: String) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].done.toggle()
        if tasks[index].done {
            for i in tasks[index].subtasks.indices { tasks[index].subtasks[i].done = true }
        }
    }

    /// Move a task to a list, which is the kanban gesture.
    mutating func move(_ id: String, to categoryID: String?) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].categoryID = categoryID
        tasks[index].y = 110 + Double(tasks(in: categoryID).count) * 84
    }

    mutating func delete(_ id: String) {
        tasks.removeAll { $0.id == id }
        connections.removeAll { $0.from == id || $0.to == id }
    }
}

// MARK: - Whiteboard

enum WhiteboardItemType: String, Codable, Hashable {
    case text, todo, image, shape, link
}

enum WhiteboardShape: String, Codable, Hashable, CaseIterable {
    case rectangle, ellipse, diamond, triangle

    var symbol: String {
        switch self {
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .diamond: return "diamond"
        case .triangle: return "triangle"
        }
    }
}

struct WhiteboardTodoEntry: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var text: String = ""
    var done: Bool = false
}

struct WhiteboardLinkEntry: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var url: String = ""
    var showEmbed: Bool = true
}

struct WhiteboardItem: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var type: WhiteboardItemType = .text
    var x: Double = 0
    var y: Double = 0
    var text: String = ""
    var done: Bool = false
    var color: String = "#9c9fe1"
    var image: String = ""
    var width: Double = 240
    var height: Double = 140
    var shape: WhiteboardShape = .rectangle
    var filled: Bool = false
    var title: String = ""
    var todos: [WhiteboardTodoEntry] = []
    var links: [WhiteboardLinkEntry] = []

    enum CodingKeys: String, CodingKey {
        case id, type, x, y, text, done, color, image, width, height, shape, filled, title, todos, links
    }

    init() {}

    init(type: WhiteboardItemType, x: Double, y: Double, text: String = "",
         color: String = "#9c9fe1", width: Double = 240, height: Double = 140) {
        self.type = type
        self.x = x
        self.y = y
        self.text = text
        self.color = color
        self.width = width
        self.height = height
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        type = (try? c.decode(WhiteboardItemType.self, forKey: .type)) ?? .text
        x = (try? c.decode(Double.self, forKey: .x)) ?? 0
        y = (try? c.decode(Double.self, forKey: .y)) ?? 0
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        done = (try? c.decode(Bool.self, forKey: .done)) ?? false
        color = (try? c.decode(String.self, forKey: .color)) ?? "#9c9fe1"
        image = (try? c.decode(String.self, forKey: .image)) ?? ""
        width = (try? c.decode(Double.self, forKey: .width)) ?? 240
        height = (try? c.decode(Double.self, forKey: .height)) ?? 140
        shape = (try? c.decode(WhiteboardShape.self, forKey: .shape)) ?? .rectangle
        filled = (try? c.decode(Bool.self, forKey: .filled)) ?? false
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        todos = (try? c.decode([WhiteboardTodoEntry].self, forKey: .todos)) ?? []
        links = (try? c.decode([WhiteboardLinkEntry].self, forKey: .links)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(type, forKey: .type)
        try c.encode(x, forKey: .x)
        try c.encode(y, forKey: .y)
        try c.encode(text, forKey: .text)
        try c.encode(done, forKey: .done)
        try c.encode(color, forKey: .color)
        try c.encode(image, forKey: .image)
        try c.encode(width, forKey: .width)
        try c.encode(height, forKey: .height)
        try c.encode(shape, forKey: .shape)
        try c.encode(filled, forKey: .filled)
        try c.encode(title, forKey: .title)
        try c.encode(todos, forKey: .todos)
        try c.encode(links, forKey: .links)
    }
}

struct WhiteboardConnection: Codable, Hashable {
    var from: String
    var to: String
    var color: String = "#9c9fe1"
}

struct WhiteboardStroke: Codable, Hashable {
    struct Point: Codable, Hashable {
        var x: Double
        var y: Double
    }

    var id: String = UUID().uuidString
    var color: String = "#9c9fe1"
    var width: Double = 3
    var points: [Point] = []
}

struct WhiteboardDocument: Codable, Equatable {
    var format: String = "comet-whiteboard"
    var version: Int = 5
    var items: [WhiteboardItem] = []
    var connections: [WhiteboardConnection] = []
    var strokes: [WhiteboardStroke] = []

    enum CodingKeys: String, CodingKey {
        case format, version, items, connections, strokes
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = (try? c.decode(String.self, forKey: .format)) ?? "comet-whiteboard"
        version = (try? c.decode(Int.self, forKey: .version)) ?? 2
        items = (try? c.decode([WhiteboardItem].self, forKey: .items)) ?? []
        connections = (try? c.decode([WhiteboardConnection].self, forKey: .connections)) ?? []
        strokes = (try? c.decode([WhiteboardStroke].self, forKey: .strokes)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("comet-whiteboard", forKey: .format)
        try c.encode(5, forKey: .version)
        try c.encode(items, forKey: .items)
        try c.encode(connections, forKey: .connections)
        try c.encode(strokes, forKey: .strokes)
    }

    static func parse(_ text: String) -> WhiteboardDocument? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WhiteboardDocument.self, from: data)
    }

    func serialized() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return "{}" }
        return (String(data: data, encoding: .utf8) ?? "{}") + "\n"
    }
}

// MARK: - Board colours

enum BoardColor {
    static let palette: [String] = [
        "#9c9fe1", "#7dd3fc", "#6ee7b7", "#fcd34d", "#fca5a5", "#f0abfc", "#a3e635", "#fdba74",
    ]

    static func color(_ hex: String) -> Color { Color(hex: hex) }
}
