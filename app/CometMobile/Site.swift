//
//  Site.swift
//  Comet for iOS
//
//  What the loopback server serves: the built Comet page, the workspace files
//  the page asks for through convertFileSrc, and the command bridge itself.
//

import Foundation

final class Site {
    private let root: String
    private let workspace: Workspace
    private let bridge: Bridge

    init(root: URL, workspace: Workspace, bridge: Bridge) {
        self.root = Workspace.normalize(root.path)
        self.workspace = workspace
        self.bridge = bridge
    }

    func respond(_ request: HTTPRequest, _ complete: @escaping (HTTPResponse) -> Void) {
        switch request.path {
        case "/__invoke":
            invoke(request, complete)
        case "/__file":
            asset(request, complete)
        default:
            staticFile(request, complete)
        }
    }

    // MARK: - The page

    private func staticFile(_ request: HTTPRequest, _ complete: @escaping (HTTPResponse) -> Void) {
        guard request.isGetOrHead else {
            complete(.text("Method not allowed.", status: 405))
            return
        }
        var relative = String(request.path.drop(while: { $0 == "/" }))
        if relative.isEmpty { relative = "index.html" }
        guard !relative.split(separator: "/").contains("..") else {
            complete(.text("Not found.", status: 404))
            return
        }

        var candidate = Workspace.normalize(root + "/" + relative)
        guard Workspace.isInside(root, candidate) else {
            complete(.text("Not found.", status: 404))
            return
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory) else {
            complete(.text("Not found.", status: 404))
            return
        }
        if isDirectory.boolValue {
            candidate = Workspace.normalize(candidate + "/index.html")
            guard FileManager.default.fileExists(atPath: candidate) else {
                complete(.text("Not found.", status: 404))
                return
            }
        }
        complete(.file(URL(fileURLWithPath: candidate), contentType: MimeType.forPath(candidate), rangeHeader: request.headers["range"]))
    }

    // MARK: - Workspace files

    private func asset(_ request: HTTPRequest, _ complete: @escaping (HTTPResponse) -> Void) {
        guard request.isGetOrHead else {
            complete(.text("Method not allowed.", status: 405))
            return
        }
        guard let raw = request.query["path"], !raw.isEmpty else {
            complete(.text("A path is required.", status: 400))
            return
        }
        let path = Workspace.normalize(raw)
        guard path.hasPrefix("/"), !path.split(separator: "/").contains("..") else {
            complete(.text("That path is not allowed.", status: 403))
            return
        }
        // Only files inside a workspace the page has been granted, or inside
        // this app's own container. Nothing else on the device is readable.
        guard workspace.allowsFile(path) else {
            complete(.text("That path is not allowed.", status: 403))
            return
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            complete(.text("Not found.", status: 404))
            return
        }
        complete(.file(URL(fileURLWithPath: path), contentType: MimeType.forPath(path), rangeHeader: request.headers["range"]))
    }

    // MARK: - Commands

    private func invoke(_ request: HTTPRequest, _ complete: @escaping (HTTPResponse) -> Void) {
        guard request.method == "POST" else {
            complete(.text("Method not allowed.", status: 405))
            return
        }
        guard let object = try? JSONSerialization.jsonObject(with: request.body),
              let payload = object as? [String: Any],
              let command = payload["cmd"] as? String,
              !command.isEmpty else {
            complete(.text("Malformed bridge request.", status: 400))
            return
        }
        let arguments = (payload["args"] as? [String: Any]) ?? [:]
        bridge.dispatch(command: command, arguments: arguments) { result in
            switch result {
            case .value(let value):
                complete(.json(["ok": true, "value": value ?? NSNull()]))
            case .failure(let error):
                complete(.json(["ok": false, "error": error.message]))
            }
        }
    }
}

final class AppServices {
    static let shared = AppServices()

    let workspace = Workspace()
    let uploads = Uploads()
    let pickers = Pickers()

    private(set) lazy var bridge = Bridge(workspace: workspace, uploads: uploads, pickers: pickers)
    private(set) lazy var site = Site(
        root: Bundle.main.bundleURL.appendingPathComponent("www", isDirectory: true),
        workspace: workspace,
        bridge: bridge
    )
    private(set) lazy var server = HTTPServer { [unowned self] request, respond in
        self.site.respond(request, respond)
    }

    func shutdown() {
        uploads.discardAll()
        server.stop()
    }
}
