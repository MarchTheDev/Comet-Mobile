//
//  Bridge.swift
//  Comet for iOS
//
//  The command table. Comet's front end calls these names; the desktop app
//  answers them from Rust. Anything genuinely desktop-only (the tray, launch at
//  login, Windows installer updates, Google OAuth through a system keyring)
//  answers with a plain refusal instead of pretending, so the UI can say so.
//

import Foundation
import UIKit

struct CometArguments {
    let values: [String: Any]

    func string(_ key: String) throws -> String {
        guard let value = values[key] as? String else {
            throw CometError("The request is missing \"\(key)\".")
        }
        return value
    }

    func integer(_ key: String) throws -> UInt64 {
        guard let number = values[key] as? NSNumber else {
            throw CometError("The request is missing \"\(key)\".")
        }
        let value = number.int64Value
        guard value >= 0 else { throw CometError("\"\(key)\" must not be negative.") }
        return UInt64(value)
    }

    func boolean(_ key: String) -> Bool {
        if let value = values[key] as? Bool { return value }
        if let number = values[key] as? NSNumber { return number.boolValue }
        return false
    }

    func options() -> CometArguments {
        guard let options = values["options"] as? [String: Any] else { return CometArguments(values: [:]) }
        return CometArguments(values: options)
    }

    /// Comet streams imports as `Array.from(new Uint8Array(...))`, so raw bytes
    /// arrive as an array of JSON numbers.
    func bytes(_ key: String) throws -> Data {
        guard let raw = values[key] as? [Any] else {
            throw CometError("The request is missing \"\(key)\".")
        }
        var data = Data()
        data.reserveCapacity(raw.count)
        for item in raw {
            guard let number = item as? NSNumber else {
                throw CometError("\"\(key)\" must be a list of bytes.")
            }
            let value = number.intValue
            guard value >= 0, value <= 255 else {
                throw CometError("\"\(key)\" must be a list of bytes.")
            }
            data.append(UInt8(value))
        }
        return data
    }
}

enum BridgeResult {
    case value(Any?)
    case failure(CometError)
}

final class Bridge {
    private let workspace: Workspace
    private let uploads: Uploads
    private let pickers: Pickers
    private let lock = NSLock()
    private var eventCounter = 1
    private var passwordBackups: Set<String> = []

    init(workspace: Workspace, uploads: Uploads, pickers: Pickers) {
        self.workspace = workspace
        self.uploads = uploads
        self.pickers = pickers
    }

    func dispatch(command: String, arguments: [String: Any], complete: @escaping (BridgeResult) -> Void) {
        let args = CometArguments(values: arguments)
        do {
            switch command {
            // MARK: Tauri core plugins

            case "plugin:window|show", "plugin:window|hide", "plugin:window|set_focus",
                 "plugin:window|destroy", "plugin:window|close", "plugin:window|unminimize",
                 "plugin:window|set_title", "plugin:window|set_decorations":
                complete(.value(nil))

            case "plugin:window|is_visible":
                complete(.value(true))

            case "plugin:window|is_focused":
                DispatchQueue.main.async { complete(.value(UIApplication.shared.applicationState == .active)) }

            case "plugin:window|scale_factor":
                DispatchQueue.main.async { complete(.value(Double(UIScreen.main.scale))) }

            case "plugin:window|internal_toggle_maximize", "plugin:window|maximize", "plugin:window|unmaximize":
                complete(.value(nil))

            case "plugin:event|listen":
                lock.lock()
                let id = eventCounter
                eventCounter += 1
                lock.unlock()
                complete(.value(id))

            case "plugin:event|unlisten", "plugin:event|emit", "plugin:event|emit_to":
                complete(.value(nil))

            case "plugin:opener|open_url":
                openExternally(try args.string("url")) { result in complete(result) }

            case "plugin:opener|open_path":
                openExternally(try args.string("path")) { result in complete(result) }

            case "plugin:opener|reveal_item_in_dir":
                complete(.value(nil))

            case "plugin:dialog|open":
                let options = args.options()
                if options.boolean("directory") {
                    pickers.pickFolder { result in
                        switch result {
                        case .success(let path): complete(.value(path))
                        case .failure(let error): complete(.failure(error))
                        }
                    }
                } else {
                    pickers.pickFiles(multiple: options.boolean("multiple")) { result in
                        switch result {
                        case .success(let paths): complete(.value(paths.isEmpty ? nil : paths))
                        case .failure(let error): complete(.failure(error))
                        }
                    }
                }

            case "plugin:dialog|save", "plugin:dialog|message", "plugin:dialog|ask", "plugin:dialog|confirm":
                complete(.failure(CometError("This dialog isn't available in Comet for iOS.")))

            case "plugin:autostart|is_enabled":
                complete(.value(false))

            case "plugin:autostart|enable", "plugin:autostart|disable":
                complete(.failure(CometError("Launch at login doesn't exist on iOS.")))

            case "plugin:app|version":
                complete(.value(Self.shortVersion))

            case "plugin:app|name":
                complete(.value("Comet"))

            // MARK: Workspace

            case "list_vault":
                complete(.value(workspace.list(try args.string("path"))))

            case "restore_vault_access":
                let path = try args.string("path")
                let resolved = Workspace.canonical(path)
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: resolved, isDirectory: &isDirectory), isDirectory.boolValue else {
                    throw CometError("The saved workspace is not a folder.")
                }
                workspace.register(root: resolved)
                Bookmarks.shared.access(path)
                complete(.value(nil))

            case "read_note":
                complete(.value(try workspace.readNote(vault: args.string("vault"), path: args.string("path"))))

            case "write_note":
                try workspace.writeNote(vault: args.string("vault"), path: args.string("path"), content: args.string("content"))
                complete(.value(nil))

            case "create_note":
                try workspace.createNote(vault: args.string("vault"), path: args.string("path"), content: args.string("content"))
                complete(.value(nil))

            case "create_dir":
                try workspace.createFolder(vault: args.string("vault"), path: args.string("path"))
                complete(.value(nil))

            case "rename_entry":
                try workspace.rename(vault: args.string("vault"), path: args.string("path"), newName: args.string("newName"))
                complete(.value(nil))

            case "move_entry":
                complete(.value(try workspace.move(vault: args.string("vault"), path: args.string("path"), folder: args.string("folder"))))

            case "delete_entry":
                try workspace.delete(vault: args.string("vault"), path: args.string("path"))
                complete(.value(nil))

            case "copy_asset":
                try workspace.copyAsset(vault: args.string("vault"), source: args.string("src"), destination: args.string("dest"))
                complete(.value(nil))

            case "search_vault":
                let vault = try args.string("vault")
                let query = try args.string("query")
                complete(.value(workspace.search(vault: vault, query: query)))

            case "open_vault":
                pickers.pickFolder { result in
                    switch result {
                    case .success(let path): complete(.value(path))
                    case .failure(let error): complete(.failure(error))
                    }
                }

            case "open_vault_file":
                let entry = try workspace.checkedEntry(vault: args.string("vault"), path: args.string("path"))
                pickers.share(path: entry)
                complete(.value(nil))

            case "reveal_vault_entry":
                // There is no file explorer to reveal into; the workspace is
                // already visible in the Files app.
                complete(.value(nil))

            case "open_workspace_directory":
                // There is no file manager to hand a folder to; the workspace
                // is already reachable through the Files app, so this succeeds
                // once the folder is known to exist inside a granted location.
                let path = try args.string("path")
                var directory: ObjCBool = false
                guard path.hasPrefix("/"),
                      FileManager.default.fileExists(atPath: path, isDirectory: &directory),
                      directory.boolValue,
                      workspace.allowsFile(path) else {
                    throw CometError("Choose a workspace folder on this device.")
                }
                complete(.value(nil))

            case "tray_available":
                complete(.value(false))

            case "quit_app":
                complete(.value(nil))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exit(0) }

            // MARK: Streamed imports

            case "begin_dropped_upload":
                let id = try uploads.begin(
                    vault: args.string("vault"),
                    path: args.string("path"),
                    size: args.integer("size")
                )
                complete(.value(id))

            case "append_dropped_upload":
                try uploads.append(id: args.string("id"), offset: args.integer("offset"), bytes: args.bytes("bytes"))
                complete(.value(nil))

            case "finish_dropped_upload":
                try uploads.finish(id: args.string("id"))
                complete(.value(nil))

            case "abort_dropped_upload":
                uploads.abort(id: try args.string("id"))
                complete(.value(nil))

            // MARK: Password backups

            case "choose_password_backup":
                let token = Workspace.randomToken()
                lock.lock()
                passwordBackups.insert(token)
                lock.unlock()
                complete(.value(token))

            case "cancel_password_backup":
                let token = try args.string("token")
                lock.lock()
                passwordBackups.remove(token)
                lock.unlock()
                complete(.value(nil))

            case "write_password_backup":
                let token = try args.string("token")
                lock.lock()
                let known = passwordBackups.remove(token) != nil
                lock.unlock()
                guard known else { throw CometError("The backup selection expired. Choose a location again.") }
                let encrypted = try args.string("encrypted")
                pickers.savePasswordBackup(encrypted) { result in
                    switch result {
                    case .success: complete(.value(nil))
                    case .failure(let error): complete(.failure(error))
                    }
                }

            // MARK: Not available in this build

            case "google_status":
                complete(.value(false))

            case "google_disconnect":
                complete(.value(nil))

            case "google_connect", "google_calendar_list", "google_calendar_create",
                 "google_calendar_update", "google_calendar_delete", "google_drive_list",
                 "google_drive_backup", "google_drive_import", "google_sync_list",
                 "google_sync_import", "google_sync_now":
                complete(.failure(CometError("Google Calendar and Drive aren't connected in this Comet for iOS build. Your local workspace works without them.")))

            case "install_update":
                complete(.failure(CometError("Comet for iOS is updated by installing a new build; the desktop installer doesn't apply here.")))

            case "lookup_music_cover", "read_cached_music_cover", "read_music_cover_for_file",
                 "read_audio_metadata", "music_file_fingerprint":
                // Cover artwork falls back to the on-device cache and the music
                // catalog lookup the page already does for itself.
                complete(.value(nil))

            case "remember_music_cover_for_file", "remember_audio_metadata":
                complete(.value(nil))

            default:
                complete(.failure(CometError("Comet for iOS doesn't implement \(command).")))
            }
        } catch let error as CometError {
            complete(.failure(error))
        } catch {
            complete(.failure(CometError(error.localizedDescription)))
        }
    }

    private func openExternally(_ target: String, complete: @escaping (BridgeResult) -> Void) {
        guard let url = URL(string: target), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" || scheme == "mailto" else {
            complete(.failure(CometError("That isn't a link Comet can open.")))
            return
        }
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:]) { opened in
                complete(opened ? .value(nil) : .failure(CometError("Couldn't open that link.")))
            }
        }
    }

    static var shortVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }
}
