//
//  SyncJournal.swift
//  Comet
//
//  Sync is not switched on yet, but the shape it needs is already here: every
//  change the app makes to a workspace is recorded as a small, ordered,
//  device-stamped fact. A future transport can replay those facts instead of
//  comparing two folders and guessing.
//
//  Two rules make that possible and both are cheap now:
//
//    - identity is the relative path, never an absolute one, and
//    - every fact carries content digests, so a conflict is detectable without
//      downloading anything.
//

import Foundation
import UIKit

enum ChangeAction: String, Codable, Hashable {
    case create
    case update
    case delete
    case rename
    case reorder
    case tag
    case calendar
    case feeds
}

struct ChangeRecord: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var at: Date = Date()
    var device: String
    var action: ChangeAction
    /// A relative path, or one of the `SyncKey` names for profile documents.
    var path: String
    var previousPath: String? = nil
    var digest: String? = nil
}

enum SyncKey {
    static let calendar = "@calendar"
    static let feeds = "@feeds"
    static let tag = "@tag"
    static let profile = "@profile"
}

struct DeviceIdentity: Codable, Hashable {
    var id: String
    var name: String
    var createdAt: Date

    static func create() -> DeviceIdentity {
        let name = UIDevice.current.name
        return DeviceIdentity(id: UUID().uuidString, name: name, createdAt: Date())
    }
}

struct SyncJournal: Codable {
    var records: [ChangeRecord] = []
    var lastRun: Date? = nil
    var lastError: String? = nil

    /// Keep the journal bounded; the oldest facts are folded into the baseline.
    static let limit = 4_000

    mutating func record(_ record: ChangeRecord) {
        records.append(record)
        if records.count > SyncJournal.limit {
            records.removeFirst(records.count - SyncJournal.limit)
        }
    }

    var pending: Int { records.count }
}

/// A digest is used for conflict detection, not security, so a fast 64-bit
/// FNV-1a over the bytes is enough and does not need CryptoKit on the hot path.
enum Digest {
    static func of(_ string: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    static func of(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    static func ofFile(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return of(data)
    }
}
