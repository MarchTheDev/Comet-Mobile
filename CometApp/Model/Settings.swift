//
//  Settings.swift
//  Comet
//
//  Preferences and the list of workspaces. Both are small and both are the
//  app's own, so they live in UserDefaults; nothing here is ever written into a
//  workspace.
//

import Foundation

struct CometSettings: Codable, Equatable {
    var paletteID: String = "auto"
    var editorFontSize: Double = 17
    var textScale: Double = 1
    var haptics: Bool = true
    var spellcheck: Bool = true
    var openLastWorkspace: Bool = true
    var weekStartsMonday: Bool = true
    var showWordCount: Bool = true
    /// The switch the sync release will use. It is stored now so a profile made
    /// today already carries the answer.
    var syncEnabled: Bool = false

    enum CodingKeys: String, CodingKey {
        case paletteID, editorFontSize, textScale, haptics, spellcheck
        case openLastWorkspace, weekStartsMonday, showWordCount, syncEnabled
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        paletteID = (try? c.decode(String.self, forKey: .paletteID)) ?? "auto"
        editorFontSize = (try? c.decode(Double.self, forKey: .editorFontSize)) ?? 17
        textScale = (try? c.decode(Double.self, forKey: .textScale)) ?? 1
        haptics = (try? c.decode(Bool.self, forKey: .haptics)) ?? true
        spellcheck = (try? c.decode(Bool.self, forKey: .spellcheck)) ?? true
        openLastWorkspace = (try? c.decode(Bool.self, forKey: .openLastWorkspace)) ?? true
        weekStartsMonday = (try? c.decode(Bool.self, forKey: .weekStartsMonday)) ?? true
        showWordCount = (try? c.decode(Bool.self, forKey: .showWordCount)) ?? true
        syncEnabled = (try? c.decode(Bool.self, forKey: .syncEnabled)) ?? false
    }
}

struct WorkspaceRef: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var bookmark: Data
    var pathHint: String
    var added: Date

    var folderName: String { (pathHint as NSString).lastPathComponent }
}

enum LocalStore {
    static let supportDirectory: URL = {
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? manager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Comet", isDirectory: true)
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    static let documentsDirectory: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }()

    static func profilesDirectory() -> URL {
        let directory = supportDirectory.appendingPathComponent("Profiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func workspaceKey(for ref: WorkspaceRef) -> String {
        // Stable per install and per folder: derived from the path the bookmark
        // points at, so a profile survives a rebuild that changes no paths.
        Digest.of(ref.pathHint + "|" + ref.name)
    }
}

// MARK: - Preferences file

final class SettingsStore {
    static let shared = SettingsStore()

    private let key = "comet.settings.v2"
    private let workspacesKey = "comet.workspaces.v2"
    private let lastWorkspaceKey = "comet.last-workspace.v2"
    private let deviceKey = "comet.device.v2"

    func load() -> CometSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(CometSettings.self, from: data) else {
            return CometSettings()
        }
        return settings
    }

    func save(_ settings: CometSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func loadWorkspaces() -> [WorkspaceRef] {
        guard let data = UserDefaults.standard.data(forKey: workspacesKey),
              let list = try? JSONDecoder().decode([WorkspaceRef].self, from: data) else { return [] }
        return list
    }

    func saveWorkspaces(_ list: [WorkspaceRef]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: workspacesKey)
    }

    func lastWorkspaceID() -> String? {
        UserDefaults.standard.string(forKey: lastWorkspaceKey)
    }

    func setLastWorkspaceID(_ id: String?) {
        if let id {
            UserDefaults.standard.set(id, forKey: lastWorkspaceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: lastWorkspaceKey)
        }
    }

    func device() -> DeviceIdentity {
        if let data = UserDefaults.standard.data(forKey: deviceKey),
           let identity = try? JSONDecoder().decode(DeviceIdentity.self, from: data) {
            return identity
        }
        let identity = DeviceIdentity.create()
        if let data = try? JSONEncoder().encode(identity) {
            UserDefaults.standard.set(data, forKey: deviceKey)
        }
        return identity
    }
}
