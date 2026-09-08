//
//  HTTPRequest.swift
//  AirChat
//
//  Minimal, allocation-light HTTP/1.1 request parser. AirChat only ever serves
//  GET requests (plus the WebSocket upgrade), so we deliberately do not implement
//  the whole RFC 7230 state machine — what NanoHTTPD does for us on Android.
//

import Foundation

struct HTTPRequest {
    var method = "GET"
    var target = "/"
    var version = "HTTP/1.1"
    var headers: [String: String] = [:]      // keys are lower-cased
    var body = Data()

    var path: String {
        if let r = target.firstIndex(of: "?") { return String(target[target.startIndex..<r]) }
        return target
    }

    /// Number of bytes this request occupies in the stream, so the caller knows
    /// where the next thing (e.g. an already-pipelined WebSocket frame) begins.
    var bytesConsumed = 0
    var query: [String: String] {
        guard let q = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: true).dropFirst().first else { return [:] }
        var out: [String: String] = [:]
        for pair in q.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let k = String(kv[0]).removingPercentEncoding ?? String(kv[0])
            let v = kv.count > 1 ? (String(kv[1]).removingPercentEncoding ?? String(kv[1])) : ""
            out[k] = v
        }
        return out
    }

    func header(_ name: String) -> String? { headers[name.lowercased()] }

    var isWebSocketUpgrade: Bool {
        (header("upgrade")?.lowercased().contains("websocket") ?? false)
            && header("sec-websocket-key") != nil
    }
}

enum HTTPParser {

    private static let crlfcrlf: [UInt8] = [13, 10, 13, 10]

    /// Returns nil when the buffer does not contain a whole request yet.
    static func parse(_ data: Data) -> HTTPRequest? {
        guard !data.isEmpty else { return nil }
        let bytes = [UInt8](data)
        guard let headerEnd = indexOfCRLFCRLF(bytes) else { return nil }
        let headerRegion = bytes[0..<headerEnd]

        guard let headerText = String(bytes: headerRegion, encoding: .utf8) else { return nil }
        var lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        lines.removeFirst()

        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }

        var req = HTTPRequest()
        req.method = String(parts[0]).uppercased()
        req.target = String(parts[1])
        req.version = parts.count > 2 ? String(parts[2]) : "HTTP/1.1"

        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { req.headers[name] = value }
        }

        let contentLength = Int(req.header("content-length") ?? "") ?? 0
        let bodyStart = headerEnd + 4
        if contentLength > 0 {
            guard bytes.count >= bodyStart + contentLength else { return nil }   // keep reading
            req.body = Data(bytes[(bodyStart)..<(bodyStart + contentLength)])
        }
        req.bytesConsumed = bodyStart + contentLength
        return req
    }

    private static func indexOfCRLFCRLF(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 4 else { return nil }
        let limit = bytes.count - 4
        var i = 0
        while i <= limit {
            if bytes[i] == crlfcrlf[0], bytes[i+1] == crlfcrlf[1],
               bytes[i+2] == crlfcrlf[2], bytes[i+3] == crlfcrlf[3] {
                return i
            }
            i += 1
        }
        return nil
    }
}

/// Small helpers to serialise responses; mirrors newFixedLengthResponse /
/// newChunkedResponse from the Kotlin NanoHTTPD layer.
struct HTTPResponse {
    var status = 200
    var reason = "OK"
    var contentType = "text/plain"
    var headers: [(String, String)] = []
    var body = Data()

    init(status: Int = 200, reason: String? = nil, contentType: String = "text/plain",
         headers: [(String, String)] = [], body: Data = Data()) {
        self.status = status
        self.reason = reason ?? HTTPResponse.defaultReason(for: status)
        self.contentType = contentType
        self.headers = headers
        self.body = body
    }

    static func text(_ s: String, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, contentType: "text/plain; charset=utf-8", body: Data(s.utf8))
    }

    static func html(_ s: String, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, contentType: "text/html; charset=utf-8", body: Data(s.utf8))
    }

    static func redirect(to location: String) -> HTTPResponse {
        HTTPResponse(status: 302, reason: "Found", contentType: "text/plain",
                     headers: [("Location", location)], body: Data())
    }

    static func notFound(_ message: String = "Nu s-a găsit fișierul!") -> HTTPResponse {
        .text(message, status: 404)
    }

    static func defaultReason(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 204: return "No Content"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 304: return "Not Modified"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 500: return "Internal Server Error"
        case 503: return "Service Unavailable"
        default: return "OK"
        }
    }

    var serializedHead: Data {
        var lines = "HTTP/1.1 \(status) \(reason)\r\n"
        lines += "Content-Type: \(contentType)\r\n"
        lines += "Content-Length: \(body.count)\r\n"
        lines += "Connection: close\r\n"
        // Only set the default when the caller did not choose one, otherwise the
        // response carries two conflicting Cache-Control headers.
        if !headers.contains(where: { $0.0.caseInsensitiveCompare("Cache-Control") == .orderedSame }) {
            lines += "Cache-Control: no-store\r\n"
        }
        lines += "Access-Control-Allow-Origin: *\r\n"
        for (k, v) in headers { lines += "\(k): \(v)\r\n" }
        lines += "Server: AirChat/3.0 (iOS)\r\n\r\n"
        return Data(lines.utf8)
    }

    /// Full wire bytes (head + body).
    var wireBytes: Data {
        var d = serializedHead
        d.append(body)
        return d
    }
}
