import Foundation
import Network

/// Returns the device's primary IPv4 address on Wi-Fi (en0/en1),
/// mirroring `getSmartIpAddress()` from the Android app.
enum NetworkUtils {
    static func localWiFiIPv4() -> String? {
        var address: String?
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let iface = ptr {
            let info = iface.pointee
            let addrPtr = info.ifa_addr
            if (info.ifa_flags & UInt32(IFF_UP)) != 0 && (info.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 {
                let family = addrPtr.pointee.sa_family
                if family == sa_family_t(AF_INET) {
                    let name = String(cString: info.ifa_name)
                    if name.hasPrefix("en") || name.hasPrefix("pdp") {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(addrPtr, socklen_t(info.ifa_addr.pointee.sa_len),
                                    &hostname, socklen_t(hostname.count),
                                    nil, 0, NI_NUMERICHOST)
                        let candidate = String(cString: hostname)
                        if address == nil { address = candidate }
                        if name == "en0" { address = candidate; break }
                    }
                }
            }
            ptr = info.ifa_next
        }
        return address ?? "192.168.1.2"
    }
}

/// Delegate notified when a browser client sends a chat payload.
protocol AirChatServerDelegate: AnyObject {
    /// A raw wire text arrived from a browser WebSocket client.
    func webClientDidSendMessage(_ text: String)
}

/// Embedded HTTP + WebSocket server.
///
/// Replaces `NanoHTTPD` + `NanoWSD` from the Android app. Built entirely on the
/// system `Network` framework (no third-party dependencies).
///
/// Responsibilities:
///   - Serve the bundled web assets (index.html, app.js, style.css, ...) so
///     laptop / other-phone users can join through their browser.
///   - Implement the captive-portal / short-code redirects.
///   - Run a WebSocket hub with a rolling 50-message history replay.
final class AirChatServer {
    weak var delegate: AirChatServerDelegate?

    private let port: NWEndpoint.Port
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.skidropz.airchat.server")

    private let localIp: String
    private let roomKey: String
    private let shortCode: String

    /// Connected WebSocket clients.
    private var connections: [ObjectIdentifier: ClientConnection] = [:]
    private let lock = NSLock()

    /// Rolling message history (last 50), mirroring the Android server.
    private var messageHistory: [String] = []
    private let historyLock = NSLock()

    init(port: UInt16, localIp: String, roomKey: String, shortCode: String) {
        self.port = NWEndpoint.Port(rawValue: port) ?? 8080
        self.localIp = localIp
        self.roomKey = roomKey
        self.shortCode = shortCode
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: port)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        lock.lock(); let conns = connections; connections.removeAll(); lock.unlock()
        conns.values.forEach { $0.close() }
    }

    // MARK: - Broadcast (called by ChatStore to push to browsers)

    /// Sends a wire text to every connected browser client and stores it in
    /// history (when persistent). Mirrors Android `broadcastToAll`.
    func broadcastToAll(_ text: String) {
        if isPersistent(text) {
            historyLock.lock()
            messageHistory.append(text)
            if messageHistory.count > AppConstants.maxHistory {
                messageHistory.removeFirst(messageHistory.count - AppConstants.maxHistory)
            }
            historyLock.unlock()
        }
        lock.lock(); let conns = Array(connections.values); lock.unlock()
        conns.forEach { $0.sendText(text) }
    }

    private func isPersistent(_ text: String) -> Bool {
        !(text == "ping" ||
          text.contains("\"type\":\"location_update\"") ||
          text.contains("\"type\":\"seen\"") ||
          text.contains("\"innerType\":\"location_update\"") ||
          text.contains("\"innerType\":\"seen\""))
    }

    // MARK: - Connection handling

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        readHTTPRequest(conn) { [weak self] request in
            guard let self else { return }
            guard let request else { conn.cancel(); return }
            self.route(conn: conn, request: request)
        }
    }

    /// Reads and parses HTTP request headers from a fresh TCP connection.
    private func readHTTPRequest(_ conn: NWConnection, completion: @escaping (HTTPRequest?) -> Void) {
        var buffer = Data()
        func readMore() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, isComplete, error in
                if let data { buffer.append(data) }
                if error != nil || isComplete { completion(nil); return }
                if let (request, consumed) = HTTPParser.parse(buffer) {
                    // Discard the consumed header bytes (no request body expected here).
                    _ = consumed
                    completion(request)
                    return
                }
                if buffer.count > 64 * 1024 { completion(nil); return }
                readMore()
            }
        }
        readMore()
    }

    private func route(conn: NWConnection, request: HTTPRequest) {
        let host = request.headers["host"] ?? ""
        let uri = request.target

        // Captive portal / connectivity probes → bounce into the app.
        let probePaths = ["generate_204", "hotspot-detect.html", "success.txt"]
        if probePaths.contains(where: { uri.contains($0) }) {
            respondRedirect(conn, to: "http://\(localIp):\(port)/\(shortCode)")
            return
        }

        // Requests arriving on a non-local host (captive portal hostname) → redirect.
        let isLocal = host.contains(localIp) || host.contains("127.0.0.1") || host.contains("localhost")
        if !host.isEmpty && !isLocal {
            respondRedirect(conn, to: "http://\(localIp):\(port)/\(shortCode)")
            return
        }

        // WebSocket upgrade?
        if request.headers["upgrade"]?.lowercased() == "websocket" {
            upgrade(conn: conn, request: request)
            return
        }

        // Root / short code → index with room key.
        if uri == "/" || uri.lowercased() == "/\(shortCode.lowercased())" || uri.lowercased() == "/\(shortCode.lowercased())/" {
            respondRedirect(conn, to: "/index.html#\(roomKey)")
            return
        }

        if uri == "/download-app" {
            respondDownloadAppPage(conn)
            return
        }

        serveAsset(conn: conn, path: uri)
    }

    // MARK: - HTTP responses

    private func respondRedirect(_ conn: NWConnection, to location: String) {
        let resp = "HTTP/1.1 302 Found\r\nLocation: \(location)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        sendAndClose(conn, data: Data(resp.utf8))
    }

    private func respondDownloadAppPage(_ conn: NWConnection) {
        let html = """
        <!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>AirChat</title>
        <style>body{font-family:-apple-system,sans-serif;background:#111;color:#fff;display:flex;flex-direction:column;align-items:center;justify-content:center;height:100vh;margin:0;text-align:center;padding:24px;box-sizing:border-box}
        a{color:#0084ff}</style></head>
        <body><h2>📡 AirChat</h2><p>Acest host rulează pe iOS.<br>Aplicația nativă pentru Android poate fi distribuită doar de un host Android.</p>
        <p>Pentru a continua pe acest dispozitiv, rămâi în această pagină și conectează-te cu un nume.</p></body></html>
        """
        let body = Data(html.utf8)
        let header = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        sendAndClose(conn, data: Data(header.utf8) + body)
    }

    private func serveAsset(conn: NWConnection, path: String) {
        var resource = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if resource.isEmpty { resource = "index.html" }

        let ext = (resource as NSString).pathExtension
        let name = (resource as NSString).deletingPathExtension
        let mimeType = mimeType(for: ext)

        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let data = try? Data(contentsOf: url) else {
            let body = Data("Nu s-a găsit fișierul!".utf8)
            let header = "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            sendAndClose(conn, data: Data(header.utf8) + body)
            return
        }

        let header = "HTTP/1.1 200 OK\r\nContent-Type: \(mimeType)\r\nContent-Length: \(data.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        sendAndClose(conn, data: Data(header.utf8) + data)
    }

    private func sendAndClose(_ conn: NWConnection, data: Data) {
        conn.send(content: data, completion: .contentProcessed { _ in conn.cancel() })
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "css":  return "text/css; charset=utf-8"
        case "js":   return "application/javascript; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "png":  return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "svg":  return "image/svg+xml"
        default:     return "text/plain; charset=utf-8"
        }
    }

    // MARK: - WebSocket upgrade

    private func upgrade(conn: NWConnection, request: HTTPRequest) {
        guard let key = request.headers["sec-websocket-key"] else {
            conn.cancel(); return
        }
        let accept = WebSocketFrame.acceptValue(for: key)
        let response = """
        HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n
        """
        conn.send(content: Data(response.utf8)) { [weak self] _ in
            guard let self else { return }
            let client = ClientConnection(connection: conn, server: self)
            self.lock.lock()
            self.connections[ObjectIdentifier(client)] = client
            self.lock.unlock()

            // Replay history to the new client.
            self.historyLock.lock(); let history = self.messageHistory; self.historyLock.unlock()
            for old in history { client.sendText(old) }

            client.startReading()
        }
    }

    // MARK: - Called by ClientConnection when a frame arrives

    func client(_ client: ClientConnection, didReceive text: String) {
        if text == "ping" { client.sendText("pong"); return }
        // Echo to all browser clients + history, then notify the app for mesh/UI.
        broadcastToAll(text)
        delegate?.webClientDidSendMessage(text)
    }

    func clientDidDisconnect(_ client: ClientConnection) {
        lock.lock(); connections.removeValue(forKey: ObjectIdentifier(client)); lock.unlock()
    }
}
