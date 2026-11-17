//
//  VaultStore.swift
//  Comet
//
//  The password vault, in the same envelope Comet's desktop app writes:
//  PBKDF2-SHA256 over the master password (600,000 iterations), with the vault
//  itself sealed by AES-256-GCM. A `comet-passwords` backup made on a desktop
//  opens here, and a backup made here opens there.
//
//  The master password is never stored, and the derived key only lives for as
//  long as the vault is unlocked.
//

import Foundation
import CryptoKit
import CommonCrypto
import UIKit
import Security

struct PasswordEntry: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String = ""
    var website: String = ""
    var username: String = ""
    var password: String = ""
    var notes: String = ""

    var siteHost: String? {
        guard !website.isEmpty else { return nil }
        let text = website.contains("://") ? website : "https://" + website
        guard let host = URL(string: text)?.host, host.contains(".") else { return nil }
        return host
    }
}

struct PasswordData: Codable {
    var format: String = "comet-passwords-data"
    var version: Int = 1
    var entries: [PasswordEntry] = []

    enum CodingKeys: String, CodingKey { case format, version, entries }

    init(entries: [PasswordEntry] = []) {
        self.entries = entries
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = (try? c.decode(String.self, forKey: .format)) ?? "comet-passwords-data"
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        entries = (try? c.decode([PasswordEntry].self, forKey: .entries)) ?? []
    }
}

struct PasswordEnvelope: Codable {
    var format: String = "comet-passwords"
    var version: Int = 1
    var kdf: String = "PBKDF2-SHA256"
    var iterations: Int = VaultCrypto.iterations
    var salt: String
    var iv: String
    var ciphertext: String
}

struct PasswordRecovery: Codable {
    var format: String = "comet-password-recovery"
    var version: Int = 1
    var salt: String
    var iv: String
    var wrappedKey: String
}

struct PasswordBundle: Codable {
    var format: String = "comet-passwords-bundle"
    var version: Int = 1
    var envelope: String
    var recovery: PasswordRecovery?
}

enum VaultError: LocalizedError {
    case wrongPassword
    case damaged
    case tooLarge
    case recoveryUnavailable
    case wrongRecovery

    var errorDescription: String? {
        switch self {
        case .wrongPassword: return "That master password doesn't open this vault."
        case .damaged: return "This vault is unknown or damaged; it has not been changed."
        case .tooLarge: return "This vault is too large to save safely."
        case .recoveryUnavailable: return "This vault has no recovery code."
        case .wrongRecovery: return "That recovery code doesn't open this vault."
        }
    }
}

enum VaultCrypto {
    static let iterations = 600_000
    static let saltBytes = 16
    static let ivBytes = 12
    static let keyBytes = 32

    static func randomBytes(_ count: Int) -> Data {
        var data = Data(count: count)
        _ = data.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        return data
    }

    static func deriveKey(password: String, salt: Data, iterations: Int) -> SymmetricKey? {
        guard let passwordData = password.data(using: .utf8), !salt.isEmpty else { return nil }
        var derived = Data(count: keyBytes)
        let status = derived.withUnsafeMutableBytes { derivedBytes -> Int32 in
            passwordData.withUnsafeBytes { passwordBytes -> Int32 in
                salt.withUnsafeBytes { saltBytes -> Int32 in
                    guard let derivedAddress = derivedBytes.bindMemory(to: UInt8.self).baseAddress,
                          let passwordAddress = passwordBytes.bindMemory(to: Int8.self).baseAddress,
                          let saltAddress = saltBytes.bindMemory(to: UInt8.self).baseAddress else {
                        return Int32(kCCParamError)
                    }
                    return CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordAddress, passwordData.count,
                        saltAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedAddress, keyBytes
                    )
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return SymmetricKey(data: derived)
    }

    static func seal(_ plaintext: Data, key: SymmetricKey) -> (iv: Data, ciphertext: Data)? {
        let iv = randomBytes(ivBytes)
        guard let nonce = try? AES.GCM.Nonce(data: iv),
              let box = try? AES.GCM.seal(plaintext, using: key, nonce: nonce) else { return nil }
        return (iv, box.ciphertext + box.tag)
    }

    static func open(iv: Data, ciphertext: Data, key: SymmetricKey) -> Data? {
        guard ciphertext.count > 16,
              let nonce = try? AES.GCM.Nonce(data: iv),
              let box = try? AES.GCM.SealedBox(nonce: nonce,
                                               ciphertext: ciphertext.prefix(ciphertext.count - 16),
                                               tag: ciphertext.suffix(16)) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }

    static func makeEnvelope(_ data: PasswordData, password: String, salt: Data, iterations: Int) throws -> String {
        guard let key = deriveKey(password: password, salt: salt, iterations: iterations) else { throw VaultError.damaged }
        let plaintext = try JSONEncoder().encode(data)
        guard let sealed = seal(plaintext, key: key) else { throw VaultError.damaged }
        let envelope = PasswordEnvelope(
            iterations: iterations,
            salt: salt.base64EncodedString(),
            iv: sealed.iv.base64EncodedString(),
            ciphertext: sealed.ciphertext.base64EncodedString()
        )
        guard let output = try? JSONEncoder().encode(envelope),
              let text = String(data: output, encoding: .utf8) else { throw VaultError.damaged }
        guard text.count < 8_000_000 else { throw VaultError.tooLarge }
        return text
    }

    static func readEnvelope(_ raw: String) -> PasswordEnvelope? {
        guard raw.count < 8_000_000, let data = raw.data(using: .utf8) else { return nil }
        guard let envelope = try? JSONDecoder().decode(PasswordEnvelope.self, from: data),
              envelope.format == "comet-passwords", envelope.version == 1,
              envelope.kdf == "PBKDF2-SHA256",
              envelope.iterations >= 600_000, envelope.iterations <= 2_000_000,
              let salt = Data(base64Encoded: envelope.salt), salt.count == saltBytes,
              let iv = Data(base64Encoded: envelope.iv), iv.count == ivBytes,
              let ciphertext = Data(base64Encoded: envelope.ciphertext), ciphertext.count > 16 else { return nil }
        return envelope
    }

    static func unlock(raw: String, password: String) throws -> (data: PasswordData, key: SymmetricKey) {
        guard let envelope = readEnvelope(raw) else { throw VaultError.damaged }
        guard let salt = Data(base64Encoded: envelope.salt),
              let iv = Data(base64Encoded: envelope.iv),
              let ciphertext = Data(base64Encoded: envelope.ciphertext),
              let key = deriveKey(password: password, salt: salt, iterations: envelope.iterations) else {
            throw VaultError.damaged
        }
        guard let plaintext = open(iv: iv, ciphertext: ciphertext, key: key) else { throw VaultError.wrongPassword }
        guard let data = try? JSONDecoder().decode(PasswordData.self, from: plaintext) else { throw VaultError.damaged }
        return (data, key)
    }

    // MARK: - Recovery

    static func generateRecoveryCode() -> String {
        let bytes = randomBytes(32).map { String(format: "%02X", $0) }.joined()
        var groups: [String] = []
        var index = bytes.startIndex
        while index < bytes.endIndex, groups.count < 8 {
            let end = bytes.index(index, offsetBy: 8)
            groups.append(String(bytes[index..<end]))
            index = end
        }
        return groups.joined(separator: "-")
    }

    static func recoveryKey(from code: String) -> SymmetricKey? {
        let hex = code.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
        guard hex.count == 64 else { return nil }
        var bytes = [UInt8]()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let value = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(value)
            index = next
        }
        return SymmetricKey(data: Data(bytes))
    }

    static func wrapKey(_ key: SymmetricKey, salt: Data, code: String) -> PasswordRecovery? {
        guard let recoveryKey = recoveryKey(from: code) else { return nil }
        let rawKey = key.withUnsafeBytes { Data($0) }
        let iv = randomBytes(ivBytes)
        guard let nonce = try? AES.GCM.Nonce(data: iv),
              let box = try? AES.GCM.seal(rawKey, using: recoveryKey, nonce: nonce) else { return nil }
        let ciphertext = box.ciphertext + box.tag
        return PasswordRecovery(
            salt: salt.base64EncodedString(),
            iv: iv.base64EncodedString(),
            wrappedKey: ciphertext.base64EncodedString()
        )
    }

    static func unwrapKey(_ recovery: PasswordRecovery, code: String) -> SymmetricKey? {
        guard let recoveryKey = recoveryKey(from: code),
              let iv = Data(base64Encoded: recovery.iv),
              let wrapped = Data(base64Encoded: recovery.wrappedKey),
              let nonce = try? AES.GCM.Nonce(data: iv),
              wrapped.count > 16,
              let box = try? AES.GCM.SealedBox(nonce: nonce,
                                               ciphertext: wrapped.prefix(wrapped.count - 16),
                                               tag: wrapped.suffix(16)),
              let rawKey = try? AES.GCM.open(box, using: recoveryKey),
              rawKey.count == keyBytes else { return nil }
        return SymmetricKey(data: rawKey)
    }
}

@MainActor
final class VaultStore: ObservableObject {
    enum State: Equatable {
        case empty
        case locked
        case unlocked
    }

    @Published private(set) var state: State = .empty
    @Published private(set) var entries: [PasswordEntry] = []
    @Published private(set) var hasRecovery: Bool = false
    @Published var lastError: String?

    private var envelopeText: String = ""
    private var key: SymmetricKey?
    private var salt = Data()
    private var iterations = VaultCrypto.iterations
    private var recovery: PasswordRecovery?

    private var storageURL: URL {
        LocalStore.supportDirectory.appendingPathComponent("vault.json")
    }

    init() {
        loadFromDisk()
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: storageURL),
              let raw = String(data: data, encoding: .utf8) else {
            state = .empty
            return
        }
        envelopeText = raw
        if let bundle = PasswordBundle.decode(from: raw) {
            envelopeText = bundle.envelope
            recovery = bundle.recovery
            hasRecovery = bundle.recovery != nil
        } else {
            hasRecovery = false
        }
        state = VaultCrypto.readEnvelope(envelopeText) == nil ? .empty : .locked
    }

    private func persist(_ envelope: String, recovery: PasswordRecovery?) {
        let bundle = PasswordBundle(envelope: envelope, recovery: recovery)
        guard let data = try? JSONEncoder().encode(bundle) else { return }
        try? data.write(to: storageURL, options: [.atomic, .completeFileProtection])
        envelopeText = envelope
        self.recovery = recovery
        hasRecovery = recovery != nil
    }

    // MARK: - Creating and unlocking

    func createVault(masterPassword: String, withRecovery: Bool) async throws -> String? {
        guard masterPassword.count >= 8 else {
            throw WorkbookError("Use a master password of at least 8 characters.")
        }
        let salt = VaultCrypto.randomBytes(VaultCrypto.saltBytes)
        let empty = PasswordData()
        let envelope = try VaultCrypto.makeEnvelope(empty, password: masterPassword, salt: salt, iterations: VaultCrypto.iterations)
        var code: String?
        var recoveryRecord: PasswordRecovery?
        if withRecovery, let key = VaultCrypto.deriveKey(password: masterPassword, salt: salt, iterations: VaultCrypto.iterations) {
            let generated = VaultCrypto.generateRecoveryCode()
            recoveryRecord = VaultCrypto.wrapKey(key, salt: salt, code: generated)
            if recoveryRecord != nil { code = generated }
        }
        persist(envelope, recovery: recoveryRecord)
        self.key = VaultCrypto.deriveKey(password: masterPassword, salt: salt, iterations: VaultCrypto.iterations)
        self.salt = salt
        self.iterations = VaultCrypto.iterations
        entries = []
        state = .unlocked
        return code
    }

    func unlock(masterPassword: String) async throws {
        let current = envelopeText
        let result = try await Task.detached(priority: .userInitiated) {
            try VaultCrypto.unlock(raw: current, password: masterPassword)
        }.value
        let envelope = VaultCrypto.readEnvelope(envelopeText)
        salt = envelope.flatMap { Data(base64Encoded: $0.salt) } ?? Data()
        iterations = envelope?.iterations ?? VaultCrypto.iterations
        key = result.key
        entries = result.data.entries
        state = .unlocked
        lastError = nil
    }

    func unlockWithRecovery(code: String) async throws {
        guard let recovery else { throw VaultError.recoveryUnavailable }
        guard let recoveredKey = VaultCrypto.unwrapKey(recovery, code: code) else { throw VaultError.wrongRecovery }
        guard let envelope = VaultCrypto.readEnvelope(envelopeText),
              let iv = Data(base64Encoded: envelope.iv),
              let ciphertext = Data(base64Encoded: envelope.ciphertext) else { throw VaultError.damaged }
        guard let plaintext = VaultCrypto.open(iv: iv, ciphertext: ciphertext, key: recoveredKey),
              let data = try? JSONDecoder().decode(PasswordData.self, from: plaintext) else {
            throw VaultError.wrongRecovery
        }
        key = recoveredKey
        salt = Data(base64Encoded: envelope.salt) ?? Data()
        iterations = envelope.iterations
        entries = data.entries
        state = .unlocked
    }

    func lock() {
        key = nil
        entries = []
        state = envelopeText.isEmpty ? .empty : .locked
    }

    // MARK: - Editing

    func save() throws {
        guard let key else { throw VaultError.wrongPassword }
        let plaintext = try JSONEncoder().encode(PasswordData(entries: entries))
        guard let sealed = VaultCrypto.seal(plaintext, key: key) else { throw VaultError.damaged }
        let envelope = PasswordEnvelope(
            iterations: iterations,
            salt: salt.base64EncodedString(),
            iv: sealed.iv.base64EncodedString(),
            ciphertext: sealed.ciphertext.base64EncodedString()
        )
        guard let data = try? JSONEncoder().encode(envelope),
              let text = String(data: data, encoding: .utf8) else { throw VaultError.damaged }
        guard text.count < 8_000_000 else { throw VaultError.tooLarge }
        persist(text, recovery: recovery)
    }

    func upsert(_ entry: PasswordEntry) throws {
        var updated = entry
        if updated.id.isEmpty { updated.id = UUID().uuidString }
        if let index = entries.firstIndex(where: { $0.id == updated.id }) {
            entries[index] = updated
        } else {
            entries.append(updated)
        }
        entries.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        try save()
    }

    func delete(_ entry: PasswordEntry) throws {
        entries.removeAll { $0.id == entry.id }
        try save()
    }

    func changeMasterPassword(current: String, next: String) async throws {
        guard next.count >= 8 else { throw WorkbookError("Use a master password of at least 8 characters.") }
        let currentEnvelope = envelopeText
        _ = try await Task.detached(priority: .userInitiated) {
            try VaultCrypto.unlock(raw: currentEnvelope, password: current)
        }.value
        let salt = VaultCrypto.randomBytes(VaultCrypto.saltBytes)
        let envelope = try VaultCrypto.makeEnvelope(PasswordData(entries: entries), password: next, salt: salt, iterations: VaultCrypto.iterations)
        self.salt = salt
        self.iterations = VaultCrypto.iterations
        self.key = VaultCrypto.deriveKey(password: next, salt: salt, iterations: VaultCrypto.iterations)
        persist(envelope, recovery: nil)
    }

    // MARK: - Backups

    func backupData() -> Data? {
        guard !envelopeText.isEmpty else { return nil }
        return try? JSONEncoder().encode(PasswordBundle(envelope: envelopeText, recovery: recovery))
    }

    func exportFile() -> URL? {
        guard let data = backupData() else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let name = "Comet passwords \(formatter.string(from: Date())).cometpasswords"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    func importBackup(data: Data) throws {
        guard let raw = String(data: data, encoding: .utf8),
              VaultCrypto.readEnvelope(raw) != nil || PasswordBundle.decode(from: raw) != nil else {
            throw VaultError.damaged
        }
        let bundle = PasswordBundle.decode(from: raw)
        let envelope = bundle?.envelope ?? raw
        guard VaultCrypto.readEnvelope(envelope) != nil else { throw VaultError.damaged }
        let stored = bundle == nil ? envelope : raw
        try stored.write(to: storageURL, atomically: true, encoding: .utf8)
        loadFromDisk()
    }
}

extension PasswordBundle {
    static func decode(from raw: String) -> PasswordBundle? {
        guard raw.contains("comet-passwords-bundle") else { return nil }
        guard let data = raw.data(using: .utf8),
              let bundle = try? JSONDecoder().decode(PasswordBundle.self, from: data),
              bundle.format == "comet-passwords-bundle", bundle.version == 1,
              VaultCrypto.readEnvelope(bundle.envelope) != nil else { return nil }
        return bundle
    }
}
