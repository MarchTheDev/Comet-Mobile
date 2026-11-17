//
//  Profile.swift
//  Comet
//
//  Everything Comet knows that is not a file: tags, pins, favourites, the order
//  of a folder, the local calendar, feeds and which articles were read. Comet
//  keeps this per workspace in the app's own storage — the workspace folder
//  stays exactly what the user wrote — and this app does the same, one JSON
//  document per workspace.
//
//  The document is decoded field by field so an older build can open a newer
//  profile without throwing the whole thing away.
//

import Foundation

struct WorkspaceTag: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var color: String
}

struct ItemMeta: Codable, Hashable {
    var tags: [String] = []
    var pinned: Bool = false
    var favorite: Bool = false

    var isEmpty: Bool { tags.isEmpty && !pinned && !favorite }
}

struct CalendarEvent: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var dateKey: String
    var time: String = ""
    var notes: String = ""

    var date: Date? { CometDate.date(fromKey: dateKey) }
    var hasTime: Bool { !time.isEmpty }
}

struct Feed: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var url: String
    var color: String = ""
    var symbol: String = "dot.radiowaves.left.and.right"
    var added: Date = Date()
}

struct FeedArticle: Codable, Identifiable, Hashable {
    var id: String
    var feedID: String
    var title: String
    var link: String
    var summary: String = ""
    var content: String = ""
    var author: String = ""
    var published: Date? = nil
}

struct WorkspaceProfile: Codable {
    static let schemaVersion = 1

    var schema: Int = WorkspaceProfile.schemaVersion
    var workspaceName: String = ""
    var tags: [WorkspaceTag] = []
    var items: [String: ItemMeta] = [:]
    var order: [String: [String]] = [:]
    var events: [CalendarEvent] = []
    var feeds: [Feed] = []
    var articles: [FeedArticle] = []
    var readArticles: [String] = []
    var savedArticles: [String] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case schema, workspaceName, tags, items, order, events, feeds, articles
        case readArticles, savedArticles, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = (try? c.decode(Int.self, forKey: .schema)) ?? 0
        workspaceName = (try? c.decode(String.self, forKey: .workspaceName)) ?? ""
        tags = (try? c.decode([WorkspaceTag].self, forKey: .tags)) ?? []
        items = (try? c.decode([String: ItemMeta].self, forKey: .items)) ?? [:]
        order = (try? c.decode([String: [String]].self, forKey: .order)) ?? [:]
        events = (try? c.decode([CalendarEvent].self, forKey: .events)) ?? []
        feeds = (try? c.decode([Feed].self, forKey: .feeds)) ?? []
        articles = (try? c.decode([FeedArticle].self, forKey: .articles)) ?? []
        readArticles = (try? c.decode([String].self, forKey: .readArticles)) ?? []
        savedArticles = (try? c.decode([String].self, forKey: .savedArticles)) ?? []
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(WorkspaceProfile.schemaVersion, forKey: .schema)
        try c.encode(workspaceName, forKey: .workspaceName)
        try c.encode(tags, forKey: .tags)
        try c.encode(items, forKey: .items)
        try c.encode(order, forKey: .order)
        try c.encode(events, forKey: .events)
        try c.encode(feeds, forKey: .feeds)
        try c.encode(articles, forKey: .articles)
        try c.encode(readArticles, forKey: .readArticles)
        try c.encode(savedArticles, forKey: .savedArticles)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }

    // MARK: - Organization

    func meta(for path: String) -> ItemMeta {
        items[path] ?? ItemMeta()
    }

    func isPinned(_ path: String) -> Bool { meta(for: path).pinned }
    func isFavorite(_ path: String) -> Bool { meta(for: path).favorite }

    func tag(withID id: String) -> WorkspaceTag? { tags.first { $0.id == id } }

    func tags(for path: String) -> [WorkspaceTag] {
        let ids = meta(for: path).tags
        return tags.filter { ids.contains($0.id) }
    }

    /// Sort children with the user's order first, then folders, then names.
    func sorted(_ entries: [Entry], in parent: String) -> [Entry] {
        let custom = order[parent] ?? []
        return entries.sorted { left, right in
            let li = custom.firstIndex(of: left.relativePath)
            let ri = custom.firstIndex(of: right.relativePath)
            if li != nil || ri != nil {
                return (li ?? Int.max) < (ri ?? Int.max)
            }
            if left.isFolder != right.isFolder { return left.isFolder }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    // MARK: - Articles

    var readSet: Set<String> { Set(readArticles) }
    var savedSet: Set<String> { Set(savedArticles) }

    func isRead(_ articleID: String) -> Bool { readArticles.contains(articleID) }
    func isSaved(_ articleID: String) -> Bool { savedArticles.contains(articleID) }

    mutating func markRead(_ articleID: String, read: Bool) {
        var set = readSet
        if read { set.insert(articleID) } else { set.remove(articleID) }
        readArticles = Array(set).sorted()
    }

    mutating func toggleSaved(_ articleID: String) {
        var set = savedSet
        if set.contains(articleID) { set.remove(articleID) } else { set.insert(articleID) }
        savedArticles = Array(set).sorted()
    }
}

// MARK: - Dates

enum CometDate {
    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func key(_ date: Date) -> String { dayFormatter.string(from: date) }

    static func date(fromKey key: String) -> Date? {
        dayFormatter.date(from: key)
    }

    static func relative(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        if calendar.isDateInToday(date) {
            let minutes = Int(now.timeIntervalSince(date) / 60)
            if minutes < 1 { return "just now" }
            if minutes < 60 { return "\(minutes)m ago" }
            return "\(Int(now.timeIntervalSince(date) / 3600))h ago"
        }
        if calendar.isDateInYesterday(date) { return "yesterday" }
        let days = calendar.dateComponents([.day], from: date, to: now).day ?? 0
        if days < 7 { return "\(days)d ago" }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: date)
    }

    static func greeting(_ date: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        case 18..<23: return "Good evening"
        default: return "Still up"
        }
    }
}

enum CalendarMath {
    static func startOfMonth(_ date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    static func monthGrid(for month: Date, weekStartsOnMonday: Bool) -> [Date] {
        let calendar = Calendar.current
        let start = startOfMonth(month)
        let weekday = calendar.component(.weekday, from: start)
        // Apple weekdays: 1 = Sunday. Monday-first grids begin on Monday.
        let leading = weekStartsOnMonday ? (weekday + 5) % 7 : weekday - 1
        return (0..<42).compactMap { offset in
            calendar.date(byAdding: .day, value: offset - leading, to: start)
        }
    }

    static func isSameDay(_ left: Date, _ right: Date) -> Bool {
        Calendar.current.isDate(left, inSameDayAs: right)
    }

    static func add(days: Int, to date: Date = Date()) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
    }

    static func polite(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func weekdayLetter(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("EEEEE")
        return formatter.string(from: date)
    }
}
