//
//  Pickers.swift
//  Comet for iOS
//
//  The two places Comet needs the system to choose something: a workspace
//  folder, files to import, and where to put an encrypted password backup.
//
//  Picked files are handed back as paths inside this app's container (the file
//  picker copies them), because Comet's own import command expects a readable
//  path rather than a sandbox token.
//

import Foundation
import UIKit
import UniformTypeIdentifiers

/// Where modal UI may be presented from. Set once by the web view controller.
enum UIHost {
    weak static var presenter: UIViewController?
}

/// Kept alive by `Pickers` while the picker is on screen: a
/// UIDocumentPickerViewController only holds its delegate weakly.
final class PickerCoordinator: NSObject, UIDocumentPickerDelegate {
    private let handler: (Result<[URL], CometError>) -> Void
    private let onFinish: (PickerCoordinator) -> Void
    private var finished = false

    init(handler: @escaping (Result<[URL], CometError>) -> Void, onFinish: @escaping (PickerCoordinator) -> Void) {
        self.handler = handler
        self.onFinish = onFinish
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        finish(.success(urls))
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finish(.success([]))
    }

    private func finish(_ result: Result<[URL], CometError>) {
        guard !finished else { return }
        finished = true
        handler(result)
        onFinish(self)
    }
}

final class Pickers {
    private let lock = NSLock()
    private var active: [PickerCoordinator] = []

    // MARK: - Presenting

    private func topViewController() -> UIViewController? {
        var top = UIHost.presenter
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    private func present(_ controller: UIViewController, onMissing: @escaping (CometError) -> Void) {
        DispatchQueue.main.async {
            guard let top = self.topViewController() else {
                onMissing(CometError("Comet couldn't open a picker right now."))
                return
            }
            top.present(controller, animated: true)
        }
    }

    private func keep(_ coordinator: PickerCoordinator) {
        lock.lock()
        active.append(coordinator)
        lock.unlock()
    }

    private func forget(_ coordinator: PickerCoordinator) {
        lock.lock()
        active.removeAll { $0 === coordinator }
        lock.unlock()
    }

    // MARK: - Workspace folder

    func pickFolder(completion: @escaping (Result<String?, CometError>) -> Void) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true

        let coordinator = PickerCoordinator(handler: { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let urls):
                guard let url = urls.first else {
                    // Cancelled: Comet treats null as "no workspace chosen".
                    completion(.success(nil))
                    return
                }
                // Keeping the scope open for the life of the process is what
                // makes the workspace usable; the bookmark brings it back on
                // the next launch.
                _ = url.startAccessingSecurityScopedResource()
                Bookmarks.shared.remember(url)
                completion(.success(url.path))
            }
        }, onFinish: { [weak self] coordinator in
            self?.forget(coordinator)
        })
        picker.delegate = coordinator
        keep(coordinator)
        present(picker) { [weak self] error in
            self?.forget(coordinator)
            completion(.failure(error))
        }
    }

    // MARK: - Files to import

    func pickFiles(multiple: Bool, completion: @escaping (Result<[String], CometError>) -> Void) {
        // `asCopy` gives Comet a path it can read for as long as it needs;
        // security-scoped originals would expire the moment the picker closes.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.item], asCopy: true)
        picker.allowsMultipleSelection = multiple

        let coordinator = PickerCoordinator(handler: { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let urls):
                completion(.success(urls.map(\.path)))
            }
        }, onFinish: { [weak self] coordinator in
            self?.forget(coordinator)
        })
        picker.delegate = coordinator
        keep(coordinator)
        present(picker) { [weak self] error in
            self?.forget(coordinator)
            completion(.failure(error))
        }
    }

    // MARK: - Sharing a file

    func share(path: String) {
        DispatchQueue.main.async {
            guard let top = self.topViewController() else { return }
            let url = URL(fileURLWithPath: path)
            let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let popover = controller.popoverPresentationController {
                popover.sourceView = top.view
                popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
                popover.permittedArrowDirections = []
            }
            top.present(controller, animated: true)
        }
    }

    // MARK: - Encrypted password backups

    /// The desktop app asks for a destination and then writes to it. iOS has no
    /// persistent save panel, so the write lands in this app's own
    /// "Comet backups" folder — which is visible in the Files app — and the
    /// share sheet is offered so it can be moved into iCloud Drive or sent on.
    func savePasswordBackup(_ encrypted: String, completion: @escaping (Result<Void, CometError>) -> Void) {
        let fileManager = FileManager.default
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            completion(.failure(CometError("Couldn't reach this device's storage.")))
            return
        }
        guard !encrypted.isEmpty else {
            completion(.failure(CometError("This isn't a valid encrypted Comet password backup. Nothing was saved.")))
            return
        }

        let folder = documents.appendingPathComponent("Comet backups", isDirectory: true)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            completion(.failure(CometError("Couldn't prepare the backup folder.")))
            return
        }

        var target = folder.appendingPathComponent("comet-passwords-encrypted.json")
        var counter = 2
        while fileManager.fileExists(atPath: target.path) {
            target = folder.appendingPathComponent("comet-passwords-encrypted-\(counter).json")
            counter += 1
            if counter > 99 {
                completion(.failure(CometError("There are too many backups here already. Move or delete some, then try again.")))
                return
            }
        }

        do {
            try Data(encrypted.utf8).write(to: target, options: .atomic)
        } catch {
            completion(.failure(CometError("Couldn't write the encrypted backup.")))
            return
        }

        share(path: target.path)
        completion(.success(()))
    }
}

/// Security-scoped bookmarks for workspace folders chosen outside this app's
/// container, so a workspace on iCloud Drive keeps working across launches.
final class Bookmarks {
    static let shared = Bookmarks()

    private let key = "comet.vault.bookmarks.v1"
    private let lock = NSLock()
    private var open: [String: URL] = [:]

    private func stored() -> [String: Data] {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: Data]) ?? [:]
    }

    private func store(_ values: [String: Data]) {
        UserDefaults.standard.set(values, forKey: key)
    }

    func remember(_ url: URL) {
        guard let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        lock.lock()
        var values = stored()
        values[url.path] = data
        store(values)
        lock.unlock()
    }

    /// Reopens a remembered folder. Called by Comet's restore_vault_access the
    /// first time it touches a workspace after launch.
    @discardableResult
    func access(_ path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if open[path] != nil { return true }
        guard let data = stored()[path] else { return false }

        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return false
        }
        _ = url.startAccessingSecurityScopedResource()
        open[path] = url
        if stale, let refreshed = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            var values = stored()
            values[path] = refreshed
            store(values)
        }
        return true
    }
}
