//
//  ProfileStore.swift
//  Comet
//
//  One JSON document per workspace for everything that is not a file, and one
//  journal of the changes made to it. Both are written atomically and both are
//  cheap to sync later: the document holds the state, the journal holds how it
//  got there.
//

import Foundation

final class ProfileStore {
    let key: String
    let device: DeviceIdentity

    private(set) var profile = WorkspaceProfile()
    private(set) var journal = SyncJournal()

    private let profileURL: URL
    private let journalURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(key: String) {
        self.key = key
        self.device = SettingsStore.shared.device()
        let directory = LocalStore.profilesDirectory()
        profileURL = directory.appendingPathComponent("\(key).json")
        journalURL = directory.appendingPathComponent("\(key).journal.json")
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
    }

    // MARK: - Loading

    func load() {
        if let data = try? Data(contentsOf: profileURL),
           let decoded = try? decoder.decode(WorkspaceProfile.self, from: data) {
            profile = decoded
        } else {
            profile = WorkspaceProfile()
        }
        if let data = try? Data(contentsOf: journalURL),
           let decoded = try? decoder.decode(SyncJournal.self, from: data) {
            journal = decoded
        } else {
            journal = SyncJournal()
        }
    }

    func reset() {
        profile = WorkspaceProfile()
        journal = SyncJournal()
    }

    // MARK: - Saving

    func saveProfile() {
        profile.updatedAt = Date()
        guard let data = try? encoder.encode(profile) else { return }
        try? data.write(to: profileURL, options: .atomic)
    }

    func saveJournal() {
        guard let data = try? encoder.encode(journal) else { return }
        try? data.write(to: journalURL, options: .atomic)
    }

    func setProfile(_ next: WorkspaceProfile, reason: ChangeRecord?) {
        profile = next
        if let reason { journal.record(reason) }
        saveProfile()
        if reason != nil { saveJournal() }
    }

    // MARK: - Journal

    func record(_ action: ChangeAction, path: String, previousPath: String? = nil, digest: String? = nil) {
        journal.record(ChangeRecord(device: device.id, action: action, path: path,
                                    previousPath: previousPath, digest: digest))
        saveJournal()
    }

    func markSyncRun(at date: Date = Date()) {
        journal.lastRun = date
        saveJournal()
    }

    /// Everything a future transport needs to describe this device's state.
    var summary: SyncSummary {
        SyncSummary(
            deviceID: device.id,
            deviceName: device.name,
            pendingChanges: journal.pending,
            lastRun: journal.lastRun,
            profileUpdated: profile.updatedAt
        )
    }

    func pruneJournal(keeping limit: Int = 0) {
        if journal.records.count > limit {
            journal.records.removeFirst(journal.records.count - limit)
            saveJournal()
        }
    }
}

struct SyncSummary: Hashable {
    let deviceID: String
    let deviceName: String
    let pendingChanges: Int
    let lastRun: Date?
    let profileUpdated: Date
}
