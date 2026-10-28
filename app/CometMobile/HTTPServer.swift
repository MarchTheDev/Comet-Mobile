//
//  HTTPServer.swift
//  Comet for iOS
//
//  A loopback-only HTTP/1.1 server on top of Network.framework.
//
//  Why a server at all? Comet's front end is a normal web page that expects to
//  be running somewhere with a real origin: it fetches workspace media, streams
//  PDF.js assets, and keeps its settings, tags and password vault in
//  localStorage. A `file://` page is opaque-origin and not a secure context, so
//  WebCrypto (the password vault) would not even exist. Serving the same bytes
//  from http://127.0.0.1 puts the app back on a normal, secure origin that is
//  stable across launches.
//
//  Every response is one request per connection and closes afterwards: the
//  traffic here is a page load, a handful of bridge calls, and media streaming,
//  none of which benefits from the complexity of keep-alive.
//

import Foundation
import Network

final class HTTPServer {
    typealias Router = (HTTPRequest, @escaping (HTTPResponse) -> Void) -> Void

    private let queue = DispatchQueue(label: "com.marco.comet.bridge", qos: .userInitiated, attributes: .concurrent)
    private let router: Router
    private var listener: NWListener?
    private var boundPort: UInt16 = 0

    /// How long a client may hold a connection open without sending a request.
    /// Once the request has arrived the clock stops: a response may legitimately
    /// take a while (a picker, a share sheet) and a media stream can run for
    /// hours.
    private let requestTimeout: TimeInterval = 60

    init(router: @escaping Router) {
        self.router = router
    }

    var port: UInt16 { boundPort }

    /// Binds `port` on 127.0.0.1. The port is fixed by the caller because the
    /// page's origin — and therefore all of Comet's local storage — is keyed by
    /// it; a changing port would look like a fresh install every launch.
    func start(port: UInt16, ready: @escaping (UInt16) -> Void, failed: @escaping (Error) -> Void) {
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            failed(ServerError.invalidPort)
            return
        }
        startLoopback(nwPort, ready: ready, failed: failed)
    }

    private func startLoopback(_ nwPort: NWEndpoint.Port, ready: @escaping (UInt16) -> Void, failed: @escaping (Error) -> Void) {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        // Bind to loopback only: nothing off this device should be able to
        // reach the bridge, and no local-network permission prompt is needed.
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host("127.0.0.1"), port: nwPort)

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            // Fall back to an unqualified listener; WKWebView still talks to
            // 127.0.0.1, which is what the page is loaded from either way.
            startUnqualified(nwPort, ready: ready, failed: failed)
            return
        }

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.boundPort = nwPort.rawValue
                ready(nwPort.rawValue)
            case .failed(let error):
                self?.listener?.cancel()
                self?.listener = nil
                failed(error)
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    private func startUnqualified(_ nwPort: NWEndpoint.Port, ready: @escaping (UInt16) -> Void, failed: @escaping (Error) -> Void) {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: nwPort)
        } catch {
            failed(error)
            return
        }
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.boundPort = nwPort.rawValue
                ready(nwPort.rawValue)
            case .failed(let error):
                self?.listener?.cancel()
                self?.listener = nil
                failed(error)
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    enum ServerError: LocalizedError {
        case invalidPort

        var errorDescription: String? { "The requested port is not usable." }
    }

    // MARK: - Connections

    private final class ConnectionState {
        var receivedRequest = false
    }

    private func accept(_ connection: NWConnection) {
        let state = ConnectionState()
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + requestTimeout) {
            if !state.receivedRequest { connection.cancel() }
        }
        receive(on: connection, buffer: RequestBuffer(), state: state)
    }

    /// One owner for the bytes as they arrive: appending into a class keeps
    /// Data from copying the whole request on every chunk.
    private final class RequestBuffer {
        var data = Data()
    }

    private func receive(on connection: NWConnection, buffer: RequestBuffer, state: ConnectionState) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] chunk, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if error != nil {
                connection.cancel()
                return
            }

            if let chunk { buffer.data.append(chunk) }

            switch HTTPParser.parse(buffer.data) {
            case .needMore:
                if isComplete {
                    connection.cancel()
                } else {
                    // Hop through the queue instead of recursing so that a very
                    // large upload cannot grow the stack.
                    self.queue.async { self.receive(on: connection, buffer: buffer, state: state) }
                }
            case .invalid(let message):
                self.send(HTTPResponse.text(message, status: 400), on: connection, method: "GET")
            case .complete(let request):
                state.receivedRequest = true
                self.respond(to: request, on: connection)
            }
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        let lock = NSLock()
        var answered = false
        let finish: (HTTPResponse) -> Void = { [weak self] response in
            lock.lock()
            let alreadyAnswered = answered
            answered = true
            lock.unlock()
            guard !alreadyAnswered else { return }
            self?.send(response, on: connection, method: request.method)
        }
        router(request, finish)
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection, method: String) {
        let head = response.serializedHead()
        switch response.body {
        case .data(let body):
            var payload = head
            if method != "HEAD" { payload.append(body) }
            connection.send(content: payload, completion: .contentProcessed { _ in
                connection.cancel()
            })
        case .file(let url, let offset, let length):
            connection.send(content: head, completion: .contentProcessed { [weak self] error in
                guard error == nil, method != "HEAD" else {
                    connection.cancel()
                    return
                }
                self?.stream(url: url, offset: offset, length: length, on: connection)
            })
        }
    }

    private func stream(url: URL, offset: UInt64, length: UInt64, on connection: NWConnection) {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            connection.cancel()
            return
        }
        if offset > 0 {
            do { try handle.seek(toOffset: offset) } catch {
                handle.closeFile()
                connection.cancel()
                return
            }
        }

        var remaining = length
        func pump() {
            if remaining == 0 {
                handle.closeFile()
                connection.send(content: nil, isComplete: true, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }
            let wanted = Int(min(remaining, 1024 * 1024))
            let chunk = try? handle.read(upToCount: wanted)
            guard let chunk, !chunk.isEmpty else {
                handle.closeFile()
                connection.cancel()
                return
            }
            remaining -= UInt64(chunk.count)
            connection.send(content: chunk, isComplete: false, completion: .contentProcessed { error in
                if error != nil {
                    handle.closeFile()
                    connection.cancel()
                    return
                }
                pump()
            })
        }
        pump()
    }
}
