//
//  AirChatServer.swift
//  AirChat
//
//  iOS port of app/src/main/java/com/example/skychatlocal/LocalServer.kt.
//  Same wire protocol as the Android host, so an iPhone can host a room that
//  Android phones, laptops and other iPhones join over plain HTTP + WebSocket —
//  and so the Android app can host a room this app joins.
//
//  Built on Network.framework because NanoHTTPD/NanoWSD are JVM-only.
//

import Foundation
import Network

protocol AirChatServerDelegate: AnyObject {
    /// A web client sent a frame; forward it into the mesh + react to buzz.
    func airChatServer(_ server: AirChatServer, didReceiveMessage json: String)
    /// Number of WebSocket clients changed (drives the host panel counter).
    func airChatServer(_ server: AirChatServer, didChangeClientCount count: Int)
    /// Last client went away (Android shows a toast here).
    func airChatServerDidLoseAllClients(_ server: AirChatServer)
    func airChatServer(_ server: AirChatServer, didFailWith message: String)
}

final class AirChatServer {

    struct Config {
        var port: UInt16 = 8080
        var hostIP: String = "127.0.0.1"
        var roomKey: String = ""
        var shortCode: String = "ABCD"
        /// Also listen on :80 so a guest's captive-portal probe (`/generate_204`,
        /// `hotspot-detect.html`, `success.txt`) lands here and bounces to the room.
        /// Best effort only: the OS may refuse it (it does in the simulator) and the
        /// app must not care. Android has no such listener and works fine, so nothing
        /// else in the design depends on it.
        var servePortalPort = true
    }

    // MARK: - State

    private(set) var config: Config
    weak var delegate: AirChatServerDelegate?

    private(set) var isRunning = false
    private(set) var startedAt = Date()
    var lastError: String?

    private let queue = DispatchQueue(label: "com.skidropz.airchat.server", qos: .userInitiated)
    private var listener: NWListener?
    private var portalListener: NWListener?
    private var clients: [WSClient] = []
    private let lock = NSLock()

    /// Last 50 persistent messages, replayed to every client that arrives —
    /// the exact behaviour of messageHistory in LocalServer.kt.
    private var history: [String] = []
    private let maxHistory = 50
    private let maxHTTPHeadBytes = 64 * 1024

    var clientCount: Int {
        lock.lock(); defer { lock.unlock() }
        return clients.filter { $0.isOpen }.count
    }

    init(config: Config) {
        self.config = config
    }

    // MARK: - Lifecycle

    func start() { queue.async { [weak self] in self?.startOnQueue() } }
    func stop() { queue.async { [weak self] in self?.stopOnQueue() } }

    /// The host IP changes when the user toggles Personal Hotspot; the captive
    /// portal redirect and the QR/short-code links depend on it.
    func updateHostIP(_ ip: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.config.hostIP = ip
        }
    }

    func updateRoom(key: String, code: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.config.roomKey = key
            self.config.shortCode = code
        }
    }

    private func startOnQueue() {
        guard listener == nil else { return }
        do {
            listener = try makeListener(on: config.port, primary: true)
            listener?.start(queue: queue)
        } catch {
            isRunning = false
            fail("Could not start server: \(error.localizedDescription)")
            return
        }
        if config.servePortalPort, let extra = try? makeListener(on: 80, primary: false) {
            portalListener = extra
            extra.start(queue: queue)
        }
    }

    /// `primary` listeners drive the UI state; the :80 one only exists to catch probes
    /// and is silently dropped when iOS refuses it.
    private func makeListener(on port: UInt16, primary: Bool) throws -> NWListener {
        // No `guard let`: NWEndpoint.Port(rawValue:) is written so that it compiles
        // whether or not the initialiser is failable, and NWListener's `on:` takes an
        // optional port either way.
        let service = NWEndpoint.Port(rawValue: port)
        var params = NWParameters.tcp
        params.includePeerToPeer = true           // peer-to-peer / hotspot-linked traffic
        params.allowLocalEndpointReuse = true

        let l = try NWListener(using: params, on: service)
        l.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                if primary {
                    self.isRunning = true
                    NSLog("AirChat: server listening on \(self.config.hostIP):\(port)")
                } else {
                    NSLog("AirChat: captive-portal listener up on :80")
                }
            case .waiting(let err):
                NSLog("AirChat: listener waiting (\(err)) — usually the local-network permission prompt")
            case .failed(let err):
                if primary {
                    self.isRunning = false
                    self.fail("Server failed: \(err.localizedDescription)")
                } else {
                    NSLog("AirChat: :80 listener refused (\(err)) — ignoring, guests can still join by QR")
                    self.portalListener = nil
                }
            case .cancelled:
                if primary { self.isRunning = false }
            default:
                break
            }
        }
        l.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        return l
    }

    private func stopOnQueue() {
        listener?.cancel()
        listener = nil
        portalListener?.cancel()
        portalListener = nil
        lock.lock()
        let all = clients
        clients.removeAll()
        lock.unlock()
        all.forEach { $0.hardClose() }
        isRunning = false
        notifyCount()
    }

    private func fail(_ message: String) {
        lastError = message
        NSLog("AirChat: \(message)")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.airChatServer(self, didFailWith: message)
        }
    }

    private func accept(_ connection: NWConnection) {
        let client = WSClient(connection: connection, queue: queue, server: self)
        // The NWConnection completion handlers capture `self` weakly, so the server
        // has to own the client or it would be released (and its socket cancelled)
        // the instant this method returns. `remove(_:)` drops it again on close.
        lock.lock()
        clients.append(client)
        lock.unlock()
        client.begin()
    }

    // MARK: - Broadcast (LocalServer.broadcastToAll)

    /// Send to every connected client and remember it for late joiners.
    /// Used both for frames coming from browsers and for frames relayed by the mesh.
    func broadcastToAll(_ message: String) {
        queue.async { [weak self] in
            guard let self = self else { return }

            if !Self.isTransient(message) {
                if self.history.count >= self.maxHistory { self.history.removeFirst() }
                self.history.append(message)
            }

            self.lock.lock()
            let targets = self.clients
            self.lock.unlock()

            // `isOpen` is only true once the socket became a WebSocket: a browser
            // still fetching index.html must not be kicked off the connection.
            for c in targets where c.isOpen {
                if !c.sendText(message) { c.hardClose() }
            }
        }
    }

    /// pings / location chatter / read receipts never enter the replay buffer.
    private static func isTransient(_ message: String) -> Bool {
        if message == "ping" { return true }
        let compact = message.replacingOccurrences(of: "\", \"", with: "\",\"")
            .replacingOccurrences(of: "\": \"", with: "\":\"")
            .replacingOccurrences(of: " ", with: "")
        return compact.contains("\"type\":\"location_update\"")
            || compact.contains("\"type\":\"seen\"")
            || compact.contains("\"innerType\":\"location_update\"")
            || compact.contains("\"innerType\":\"seen\"")
    }

    fileprivate func register(_ client: WSClient) {
        lock.lock()
        if !clients.contains(where: { $0 === client }) { clients.append(client) }
        let snapshot = history
        lock.unlock()
        notifyCount()
        for old in snapshot { client.sendText(old) }
    }

    fileprivate func remove(_ client: WSClient) {
        lock.lock()
        let wasHere = clients.contains { $0 === client }
        clients.removeAll { $0 === client }
        let remaining = clients.filter { $0.isOpen }.count
        lock.unlock()
        guard wasHere else { return }
        notifyCount()
        if remaining == 0 {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.airChatServerDidLoseAllClients(self)
            }
        }
    }

    fileprivate func notifyCount() {
        let n = clientCount
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.airChatServer(self, didChangeClientCount: n)
        }
    }

    fileprivate func handleMessage(_ text: String) {
        // 1. onward into the mesh + buzz feedback (MainActivity.onMessageFromWeb)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.airChatServer(self, didReceiveMessage: text)
        }
        // 2. onward to every other web client (and into history)
        broadcastToAll(text)
    }

    // MARK: - Routing (LocalServer.serveHttp)

    fileprivate func response(for request: HTTPRequest) -> HTTPResponse {
        let host = request.header("host") ?? ""
        let uri = request.path
        let isOurs = host.isEmpty
            || host.contains(config.hostIP)
            || host.contains("127.0.0.1")
            || host.contains("localhost")
            || host.hasPrefix("[::1]")

        // --- Captive portal interception ------------------------------------
        // Requests aimed at some other hostname (a phone that still thinks it has
        // internet) and OS connectivity probes are redirected to our landing page.
        let isProbe = uri.contains("generate_204")
            || uri.contains("hotspot-detect.html")
            || uri.contains("success.txt")
            || uri.contains("connectivity-check")
            || uri.contains("redirect.html")
            || uri.contains("ncsi.txt")
        if !isOurs || isProbe {
            return .redirect(to: "http://\(config.hostIP):\(config.port)/\(config.shortCode)")
        }

        // --- Root or short code -> index.html#<roomKey> ---------------------
        if uri == "/"
            || uri.caseInsensitiveCompare("/\(config.shortCode)") == .orderedSame
            || uri.caseInsensitiveCompare("/\(config.shortCode)/") == .orderedSame {
            return .redirect(to: "/index.html#\(config.roomKey)")
        }

        // --- Viral app sharing --------------------------------------------
        if uri == "/download-app" || uri == "/install" {
            return WebContent.appDownloadResponse()
        }
        if uri.hasPrefix("/download-app/") {
            return WebContent.artifactDownload(named: String(uri.dropFirst("/download-app/".count)))
        }
        if uri == "/ios-install" || uri == "/guide" {
            return WebContent.installGuideResponse()
        }

        // --- Diagnostics -----------------------------------------------------
        if uri == "/api/status" {
            return WebContent.statusResponse(port: config.port, hostIP: config.hostIP,
                                             shortCode: config.shortCode, clients: clientCount,
                                             uptime: Date().timeIntervalSince(startedAt))
        }

        if let file = WebContent.fileResponse(forPath: uri) { return file }
        return .notFound()
    }
}

// MARK: - One TCP connection that may be upgraded to a WebSocket

private final class WSClient {

    let id = UUID()
    private let connection: NWConnection
    private let queue: DispatchQueue
    private weak var server: AirChatServer?
    private var inbound = Data()
    private var upgraded = false
    private var closed = false
    private let reader = WebSocketFrameReader()
    private var handshakeTimeout: DispatchWorkItem?

    init(connection: NWConnection, queue: DispatchQueue, server: AirChatServer) {
        self.connection = connection
        self.queue = queue
        self.server = server

        reader.onText = { [weak server] text in
            server?.handleMessage(text)
        }
        reader.onPing = { [weak self] payload in
            self?.rawSend(WebSocketFrameReader.pong(payload))
        }
        reader.onBinary = { [weak self] data in
            // AirChat's protocol is JSON-only; echo a close like NanoWSD does on junk.
            _ = data
            self?.hardClose()
        }
        reader.onClose = { [weak self] _ in
            self?.hardClose()
        }
    }

    var isOpen: Bool { !closed && upgraded }

    func begin() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.hardClose()
            default: break
            }
        }
        connection.start(queue: queue)

        // A client that connects and never speaks must not linger.
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, !self.upgraded else { return }
            self.hardClose()
        }
        handshakeTimeout = item
        queue.asyncAfter(deadline: .now() + 15, execute: item)

        receiveHead()
    }

    // MARK: HTTP phase

    private func receiveHead() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8 * 1024) { [weak self] content, _, isComplete, error in
            guard let self = self, !self.closed else { return }
            if let content = content, !content.isEmpty { self.inbound.append(content) }
            if error != nil { self.hardClose(); return }
            if self.inbound.count > 64 * 1024 { self.hardClose(); return }

            guard let request = HTTPParser.parse(self.inbound) else {
                if isComplete { self.hardClose() } else { self.receiveHead() }
                return
            }
            self.handshakeTimeout?.cancel()

            let consumed = min(request.bytesConsumed, self.inbound.count)
            let leftover = consumed < self.inbound.count
                ? Data(self.inbound.suffix(from: self.inbound.startIndex + consumed))
                : Data()

            guard request.isWebSocketUpgrade else {
                let response = self.server?.response(for: request) ?? .notFound()
                self.sendAndClose(response.wireBytes)
                return
            }


            guard let key = request.header("sec-websocket-key") else {
                self.sendAndClose(HTTPResponse(status: 400).wireBytes)
                return
            }

            self.upgraded = true
            let accept = WebSocketFrameReader.acceptResponse(for: key,
                                                              requestedProtocol: request.header("sec-websocket-protocol"))
            self.connection.send(content: accept, completion: .contentProcessed { [weak self] err in
                guard let self = self else { return }
                if err != nil { self.hardClose(); return }
                self.server?.register(self)
                if !leftover.isEmpty { self.reader.consume(leftover) }
                self.receiveFrames()
            })
        }
    }

    private func sendAndClose(_ data: Data) {
        connection.send(content: data, completion: .contentAndClose)
        closed = true
        // contentAndClose already shuts the socket down after flushing; give the
        // server a moment to finish writing, then let go of the client object.
        queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            self.upgraded = false
            self.server?.remove(self)
        }
    }

    // MARK: WebSocket phase

    private func receiveFrames() {
        guard !closed else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] content, _, isComplete, _ in
            guard let self = self, !self.closed else { return }
            if let content = content, !content.isEmpty { self.reader.consume(content) }
            if isComplete || self.reader.isClosed { self.hardClose(); return }
            self.receiveFrames()
        }
    }

    /// Returns false when the socket is gone, so the server can prune it.
    func sendText(_ text: String) -> Bool {
        guard upgraded, !closed else { return false }
        rawSend(WebSocketFrameReader.encode(text: text))
        return true
    }

    private func rawSend(_ data: Data) {
        guard !closed else { return }
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if error != nil { self?.hardClose() }
        })
    }

    /// Cancels the socket and unregisters from the server. Safe to call twice,
    /// safe to call from any queue.
    func hardClose() {
        queue.async { [weak self] in
            guard let self = self else { return }
            let alreadyClosed = self.closed
            self.closed = true
            self.upgraded = false
            self.connection.cancel()
            if !alreadyClosed { self.server?.remove(self) }
        }
    }
}

