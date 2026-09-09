//
//  LocalServer.swift
//  AirChat
//
//  A self-contained HTTP/1.1 + RFC 6455 (WebSocket) server built on Network.framework.
//  It serves the exact same web bundle the Android phone serves (`app/src/main/assets/`),
//  so an iPhone can host a room full of Android phones, laptops and other iPhones — offline.
//
//  The Android counterpart uses NanoHTTPD + NanoWSD; this implementation speaks the same
//  protocol (asset serving, captive-portal intercept, short-code redirect, /api/status,
//  /download-app, message history of the last 50 messages) so the two hosts can't drift apart.
//

import Foundation
import Network
import CryptoKit

/// Routes / discovery data needed by the server.
struct ServerInfo {
    let hostIP: String
    let port: UInt16
    let roomKey: String
    let shortCode: String
    let isHotspotActive: Bool
}

/// Callbacks from the server into the host app (mirrors Android's `WebServerListener`).
protocol LocalServerDelegate: AnyObject {
    /// A web/WS client sent a JSON message. The host forwards it into the mesh and vibrates on BUZZ.
    func server(_ server: LocalServer, didReceiveMessage json: String)
    /// The last connected web client went away.
    func serverDidLoseLastClient(_ server: LocalServer)
}

final class LocalServer {

    weak var delegate: LocalServerDelegate?

    private let info: ServerInfo
    private let webRootURL: URL
    private let queue = DispatchQueue(label: "com.skidropz.airchat.server")

    private var listener: NWListener?
    private var webSocketPeers: [WebSocketPeer] = []
    private var messageHistory: [String] = []
    private let maxHistory = 50
    private let startedAt = Date()

    var hostIP: String { info.hostIP }
    var port: UInt16 { info.port }
    var shortCode: String { info.shortCode }
    var roomKey: String { info.roomKey }
    var clientCount: Int { webSocketPeers.count }
    var uptimeSeconds: Int { Int(Date().timeIntervalSince(startedAt)) }
    var isRunning: Bool { listener != nil }

    init(info: ServerInfo, webRootURL: URL) {
        self.info = info
        self.webRootURL = webRootURL
    }

    // MARK: - Lifecycle

    func start() throws {
        stop()

        let parameters = NWParameters.tcp
        // Allow reuse so a quick restart doesn't fail with "address already in use".
        parameters.allowLocalEndpointReuse = true

        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: info.port)!)
        listener.stateUpdateHandler = { state in
            switch state {
            case .failed(let error):
                NSLog("AirChat server failed: %@", error.localizedDescription)
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        queue.async { [weak self] in
            self?.webSocketPeers.forEach { $0.close() }
            self?.webSocketPeers.removeAll()
        }
    }

    /// Sends a message to every connected WebSocket client AND records it in history.
    /// Transient messages (location/seen/ping) are not persisted — same policy as Android.
    func broadcast(_ message: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let transient = message.contains("\"type\":\"location_update\"")
                || message.contains("\"type\":\"seen\"")
                || message.contains("\"innerType\":\"location_update\"")
                || message.contains("\"innerType\":\"seen\"")
                || message == "ping"

            if !transient {
                if self.messageHistory.count >= self.maxHistory {
                    self.messageHistory.removeFirst()
                }
                self.messageHistory.append(message)
            }

            self.webSocketPeers = self.webSocketPeers.filter { !$0.isClosed }
            for peer in self.webSocketPeers {
                peer.send(text: message)
            }
        }
    }

    // MARK: - Connection handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        readHTTPRequest(connection) { [weak self] result in
            guard let self = self else { connection.cancel(); return }
            switch result {
            case .http(let request):
                self.serveHTTP(connection, request)
            case .websocket(let key):
                self.upgradeToWebSocket(connection, key: key)
            case .error, .incomplete:
                connection.cancel()
            }
        }
    }

    private enum RequestResult {
        case http(HTTPRequest)
        case websocket(String) // Sec-WebSocket-Key
        case incomplete
        case error
    }

    private struct HTTPRequest {
        var method: String = "GET"
        var path: String = "/"
        var version: String = "HTTP/1.1"
        var headers: [String: String] = [:]
        func header(_ name: String) -> String? { headers[name.lowercased()] }
    }

    private func readHTTPRequest(_ connection: NWConnection, completion: @escaping (RequestResult) -> Void) {
        var accumulated = Data()
        let maxHeaderBytes = 32 * 1024

        func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, isComplete, error in
                if let data = data {
                    accumulated.append(data)
                }
                if accumulated.count > maxHeaderBytes {
                    completion(.error)
                    return
                }
                if let range = accumulated.range(of: Data("\r\n\r\n".utf8)) {
                    let headerData = accumulated.subdata(in: 0..<range.lowerBound)
                    completion(Self.parseRequestHeader(headerData))
                    return
                }
                if error != nil || isComplete {
                    completion(accumulated.isEmpty ? .error : .incomplete)
                    return
                }
                receive()
            }
        }
        receive()
    }

    private static func parseRequestHeader(_ data: Data) -> RequestResult {
        guard let text = String(data: data, encoding: .utf8) else { return .error }
        let lines = text.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return .error }
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else { return .error }

        var request = HTTPRequest(method: parts[0], path: parts[1], version: parts.count > 2 ? parts[2] : "HTTP/1.1")
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            request.headers[key] = value
        }

        let upgrade = request.header("upgrade")?.lowercased().contains("websocket") == true
        if upgrade, let key = request.header("sec-websocket-key") {
            return .websocket(key)
        }
        return .http(request)
    }

    // MARK: - HTTP serving

    private func serveHTTP(_ connection: NWConnection, _ request: HTTPRequest) {
        let response = buildHTTPResponse(for: request)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func buildHTTPResponse(for request: HTTPRequest) -> Data {
        let uri = request.path
        let host = request.header("host") ?? ""

        // --- Captive-portal intercept (parity with Android) ---
        let isLocalHost = host.contains(info.hostIP) || host.contains("127.0.0.1") || host.contains("localhost")
        if !host.isEmpty && !isLocalHost {
            return redirect(to: "http://\(info.hostIP):\(info.port)/\(info.shortCode)")
        }
        if uri.contains("generate_204") || uri.contains("hotspot-detect.html") || uri.contains("success.txt") {
            return redirect(to: "http://\(info.hostIP):\(info.port)/\(info.shortCode)")
        }

        // --- Root / short code -> index + room key in the URL fragment ---
        if uri == "/" || uri.caseInsensitiveCompare("/\(info.shortCode)") == .orderedSame
            || uri.caseInsensitiveCompare("/\(info.shortCode)/") == .orderedSame {
            return redirect(to: "/index.html#\(info.roomKey)")
        }

        // --- Install guide ---
        if uri == "/ios-install" || uri == "/guide" {
            return redirect(to: "/install.html")
        }

        // --- Status JSON (used by install.html and the host panel) ---
        if uri == "/api/status" {
            let json = "{\"app\":\"AirChat\",\"platform\":\"iOS\",\"port\":\(info.port)," +
                "\"hostIP\":\"\(info.hostIP)\",\"shortCode\":\"\(info.shortCode)\"," +
                "\"clients\":\(clientCount),\"uptime\":\(uptimeSeconds),\"hotspot\":\(info.isHotspotActive)}"
            return httpResponse(status: "200 OK", contentType: "application/json", body: Data(json.utf8))
        }

        // --- Viral app download ---
        if uri == "/download-app" || uri.hasPrefix("/download-app/") {
            // An iPhone has no .apk to hand out. Apple devices are sent to the install guide;
            // everyone else is pointed at the GitHub releases (the Android host serves its own APK).
            let agent = (request.header("user-agent") ?? "").lowercased()
            let isApple = agent.contains("iphone") || agent.contains("ipad")
                || agent.contains("ipod") || (agent.contains("macintosh") && agent.contains("safari"))
            if isApple {
                return redirect(to: "/install.html")
            }
            return redirect(to: "https://github.com/skidropz/AirChat/releases")
        }

        // --- Static asset ---
        var assetPath = uri.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if assetPath.isEmpty { assetPath = "index.html" }
        // Drop any query string
        if let q = assetPath.firstIndex(of: "?") { assetPath = String(assetPath[..<q]) }

        let fileURL = webRootURL.appendingPathComponent(assetPath).standardizedFileURL
        // Prevent path traversal outside the web root.
        if !fileURL.path.hasPrefix(webRootURL.path), assetPath.contains("..") {
            return httpResponse(status: "404 Not Found", contentType: "text/plain",
                                body: Data("Nu s-a găsit fișierul!".utf8))
        }
        guard let body = try? Data(contentsOf: fileURL) else {
            return httpResponse(status: "404 Not Found", contentType: "text/plain",
                                body: Data("Nu s-a găsit fișierul!".utf8))
        }
        let mime = Self.mimeType(for: fileURL.pathExtension)
        return httpResponse(status: "200 OK", contentType: mime, body: body)
    }

    private func redirect(to location: String) -> Data {
        var response = Data("HTTP/1.1 302 Found\r\n".utf8)
        response.append(Data("Location: \(location)\r\n".utf8))
        response.append(Data("Content-Length: 0\r\nConnection: close\r\n\r\n".utf8))
        return response
    }

    private func httpResponse(status: String, contentType: String, body: Data) -> Data {
        var response = Data("HTTP/1.1 \(status)\r\n".utf8)
        response.append(Data("Content-Type: \(contentType)\r\n".utf8))
        response.append(Data("Content-Length: \(body.count)\r\n".utf8))
        response.append(Data("Connection: close\r\nCache-Control: no-store\r\n\r\n".utf8))
        response.append(body)
        return response
    }

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html"
        case "css": return "text/css"
        case "js": return "application/javascript"
        case "json": return "application/json"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "ico": return "image/x-icon"
        case "m4a": return "audio/mp4"
        case "webm": return "audio/webm"
        case "p12": return "application/x-pkcs12"
        case "txt": return "text/plain"
        default: return "application/octet-stream"
        }
    }

    // MARK: - WebSocket

    private func upgradeToWebSocket(_ connection: NWConnection, key: String) {
        let accept = Self.websocketAccept(key: key)
        var response = Data("HTTP/1.1 101 Switching Protocols\r\n".utf8)
        response.append(Data("Upgrade: websocket\r\nConnection: Upgrade\r\n".utf8))
        response.append(Data("Sec-WebSocket-Accept: \(accept)\r\n\r\n".utf8))
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in
            guard let self = self else { return }
            let peer = WebSocketPeer(connection: connection, queue: self.queue)
            peer.onMessage = { [weak self] message in
                guard let self = self else { return }
                // Forward to the host (mesh + BUZZ handling) …
                DispatchQueue.main.async { self.delegate?.server(self, didReceiveMessage: message) }
                // … and to every other web client (saved to history automatically).
                self.broadcast(message)
            }
            peer.onClose = { [weak self] in
                guard let self = self else { return }
                self.queue.async {
                    self.webSocketPeers.removeAll { $0 === peer }
                    if self.webSocketPeers.isEmpty {
                        DispatchQueue.main.async { self.delegate?.serverDidLoseLastClient(self) }
                    }
                }
            }
            self.webSocketPeers.append(peer)
            // Sync history to the newcomer.
            let history = self.messageHistory
            for old in history { peer.send(text: old) }
            peer.start()
        })
    }

    private static func websocketAccept(key: String) -> String {
        let guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let hash = Insecure.SHA1.hash(data: Data((key + guid).utf8))
        return Data(hash).base64EncodedString()
    }
}

// MARK: - WebSocket peer

private final class WebSocketPeer {
    let connection: NWConnection
    private let queue: DispatchQueue
    private let parser = WebSocketParser()

    var onMessage: ((String) -> Void)?
    var onClose: (() -> Void)?
    private(set) var isClosed = false

    init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
        parser.onMessage = { [weak self] message in self?.onMessage?(message) }
        parser.onClose = { [weak self] in self?.handleRemoteClose() }
        parser.onPing = { [weak self] in self?.sendPong() }
    }

    func start() {
        connection.start(queue: queue)
        receiveLoop()
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        connection.cancel()
    }

    func send(text: String) {
        guard !isClosed else { return }
        sendFrame(opcode: 0x1, data: Data(text.utf8))
    }

    private func sendPong() {
        sendFrame(opcode: 0xA, data: Data())
    }

    private func handleRemoteClose() {
        guard !isClosed else { return }
        isClosed = true
        sendFrame(opcode: 0x8, data: Data())
        connection.cancel()
        onClose?()
    }

    private func sendFrame(opcode: UInt8, data: Data) {
        var header = Data([0x80 | opcode])
        let len = data.count
        if len < 126 {
            header.append(UInt8(len))
        } else if len <= 0xFFFF {
            header.append(126)
            var l = UInt16(len).bigEndian
            header.append(Data(bytes: &l, count: 2))
        } else {
            header.append(127)
            var l = UInt64(len).bigEndian
            header.append(Data(bytes: &l, count: 8))
        }
        var frame = header
        frame.append(data)
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                self.parser.feed(data)
            }
            if error != nil || isComplete {
                if !self.isClosed {
                    self.isClosed = true
                    self.connection.cancel()
                    self.onClose?()
                }
                return
            }
            self.receiveLoop()
        }
    }
}

// MARK: - WebSocket frame parser

private final class WebSocketParser {
    private var buffer = Data()
    private var fragments = Data()

    var onMessage: ((String) -> Void)?
    var onClose: (() -> Void)?
    var onPing: (() -> Void)?

    func feed(_ data: Data) {
        buffer.append(data)
        parse()
    }

    private func parse() {
        while buffer.count >= 2 {
            let b0 = buffer[buffer.startIndex]
            let b1 = buffer[buffer.startIndex + 1]
            let fin = (b0 & 0x80) != 0
            let opcode = b0 & 0x0F
            let masked = (b1 & 0x80) != 0
            var length = UInt64(b1 & 0x7F)
            var offset = 2

            if length == 126 {
                guard buffer.count >= 4 else { return }
                length = UInt64(buffer[buffer.startIndex + 2]) << 8 | UInt64(buffer[buffer.startIndex + 3])
                offset = 4
            } else if length == 127 {
                guard buffer.count >= 10 else { return }
                var big: UInt64 = 0
                for i in 0..<8 { big = (big << 8) | UInt64(buffer[buffer.startIndex + 2 + i]) }
                length = big
                offset = 10
            }

            var maskKey = [UInt8]()
            if masked {
                guard buffer.count >= offset + 4 else { return }
                maskKey = [buffer[buffer.startIndex + offset],
                           buffer[buffer.startIndex + offset + 1],
                           buffer[buffer.startIndex + offset + 2],
                           buffer[buffer.startIndex + offset + 3]]
                offset += 4
            }

            guard buffer.count >= offset + Int(length) else { return }

            var payload = buffer.subdata(in: (buffer.startIndex + offset)..<(buffer.startIndex + offset + Int(length)))
            if masked {
                for i in 0..<payload.count { payload[i] ^= maskKey[i % 4] }
            }
            buffer.removeSubrange(0..<(offset + Int(length)))

            handleFrame(fin: fin, opcode: opcode, payload: payload)
        }
    }

    private func handleFrame(fin: Bool, opcode: UInt8, payload: Data) {
        switch opcode {
        case 0x0: // continuation
            fragments.append(payload)
            if fin {
                if let message = String(data: fragments, encoding: .utf8) { onMessage?(message) }
                fragments = Data()
            }
        case 0x1, 0x2: // text / binary
            if fin {
                if let message = String(data: payload, encoding: .utf8) { onMessage?(message) }
            } else {
                fragments = payload
            }
        case 0x8: // close
            onClose?()
        case 0x9: // ping
            onPing?()
        default:
            break
        }
    }
}
