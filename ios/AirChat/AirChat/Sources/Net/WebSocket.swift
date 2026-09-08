//
//  WebSocket.swift
//  AirChat
//
//  Hand-rolled RFC 6455 framing, because NanoWSD (used on Android) has no iOS
//  counterpart. Only what AirChat needs: text frames, ping/pong, close,
//  client-to-server masking, 16/64-bit extended lengths and fragmentation.
//

import Foundation
import CryptoKit

struct WebSocketOpcode: UInt8 {
    static let continuation: UInt8 = 0x0
    static let text: UInt8 = 0x1
    static let binary: UInt8 = 0x2
    static let close: UInt8 = 0x8
    static let ping: UInt8 = 0x9
    static let pong: UInt8 = 0xA
}

struct WebSocketFrame {
    let fin: Bool
    let opcode: UInt8
    let payload: Data
}

/// Incremental frame reader. Feed it socket bytes, it calls back once per complete
/// message (continuation frames are coalesced back into one payload).
final class WebSocketFrameReader {

    var onText: ((String) -> Void)?
    var onBinary: ((Data) -> Void)?
    var onPing: ((Data) -> Void)?
    var onClose: ((String?) -> Void)?

    private var buffer = Data()
    private var fragmentationOpcode: UInt8 = 0
    private var fragmented = Data()
    private(set) var isClosed = false

    /// Hard cap so a misbehaving client cannot make us allocate forever.
    private let maxMessageSize = 8 * 1024 * 1024

    func consume(_ data: Data) {
        if isClosed || data.isEmpty { return }
        buffer.append(data)
        parseLoop()
    }

    private func parseLoop() {
        while true {
            guard let frame = nextFrame() else { return }
            if !handle(frame) { return }
        }
    }

    private func nextFrame() -> WebSocketFrame? {
        let bytes = [UInt8](buffer)
        guard bytes.count >= 2 else { return nil }

        let fin = (bytes[0] & 0x80) != 0
        let opcode = bytes[0] & 0x0F
        let masked = (bytes[1] & 0x80) != 0
        var length = Int(bytes[1] & 0x7F)
        var offset = 2

        if length == 126 {
            guard bytes.count >= offset + 2 else { return nil }
            length = (Int(bytes[offset]) << 8) | Int(bytes[offset + 1])
            offset += 2
        } else if length == 127 {
            guard bytes.count >= offset + 8 else { return nil }
            var l = 0
            for i in 0..<8 { l = (l << 8) | Int(bytes[offset + i]) }
            length = l
            offset += 8
        }

        guard length <= maxMessageSize else { isClosed = true; buffer.removeAll(); return nil }

        var maskKey: [UInt8] = []
        if masked {
            guard bytes.count >= offset + 4 else { return nil }
            maskKey = Array(bytes[offset..<(offset + 4)])
            offset += 4
        }
        guard bytes.count >= offset + length else { return nil }

        var payload = Data(bytes[offset..<(offset + length)])
        if masked {
            let raw = payload.withUnsafeBytes { Array($0) }
            var unmasked = [UInt8](repeating: 0, count: raw.count)
            for i in 0..<raw.count { unmasked[i] = raw[i] ^ maskKey[i % 4] }
            payload = Data(unmasked)
        }

        buffer.removeSubrange(buffer.startIndex..<buffer.index(buffer.startIndex, offsetBy: offset + length))
        return WebSocketFrame(fin: fin, opcode: opcode, payload: payload)
    }

    /// returns false to stop parsing for now
    private func handle(_ frame: WebSocketFrame) -> Bool {
        switch frame.opcode {
        case WebSocketOpcode.close:
            isClosed = true
            let reason = String(data: frame.payload, encoding: .utf8)
            onClose?(reason)
            return false

        case WebSocketOpcode.ping:
            onPing?(frame.payload)
            return true

        case WebSocketOpcode.pong:
            return true

        case WebSocketOpcode.continuation:
            fragmented.append(frame.payload)
            if frame.fin {
                deliver(opcode: fragmentationOpcode, payload: fragmented)
                fragmented = Data()
                fragmentationOpcode = 0
            }
            return true

        case WebSocketOpcode.text, WebSocketOpcode.binary:
            if frame.fin && fragmented.isEmpty {
                deliver(opcode: frame.opcode, payload: frame.payload)
            } else {
                fragmentationOpcode = frame.opcode
                fragmented = frame.payload
                if frame.fin {
                    deliver(opcode: fragmentationOpcode, payload: fragmented)
                    fragmented = Data()
                    fragmentationOpcode = 0
                }
            }
            return true

        default:
            isClosed = true
            return false
        }
    }

    private func deliver(opcode: UInt8, payload: Data) {
        switch opcode {
        case WebSocketOpcode.binary: onBinary?(payload)
        default:
            if let s = String(data: payload, encoding: .utf8) { onText?(s) }
        }
    }

    // MARK: - Encoding

    static func encode(text: String) -> Data { encode(opcode: WebSocketOpcode.text, payload: Data(text.utf8)) }
    static func encode(binary: Data) -> Data { encode(opcode: WebSocketOpcode.binary, payload: binary) }
    static func pong(_ payload: Data) -> Data { encode(opcode: WebSocketOpcode.pong, payload: payload) }
    static func close() -> Data { encode(opcode: WebSocketOpcode.close, payload: Data()) }

    static func encode(opcode: UInt8, payload: Data, mask: Bool = false) -> Data {
        var out = Data()
        out.append(0x80 | opcode)                     // FIN + opcode
        let len = payload.count
        var lengthByte: UInt8 = mask ? 0x80 : 0x00
        if len < 126 {
            lengthByte |= UInt8(len)
            out.append(lengthByte)
        } else if len <= 0xFFFF {
            lengthByte |= 126
            out.append(lengthByte)
            out.append(UInt8((len >> 8) & 0xFF))
            out.append(UInt8(len & 0xFF))
        } else {
            lengthByte |= 127
            out.append(lengthByte)
            for i in stride(from: 7, through: 0, by: -1) {
                out.append(UInt8((UInt64(len) >> (8 * i)) & 0xFF))
            }
        }
        out.append(payload)                           // servers never mask (RFC 6455 §5.1)
        return out
    }

    // MARK: - Handshake

    static let magicGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    /// 101 response. `requestedProtocol` must be echoed back only when the client
    /// actually offered that subprotocol — sending Sec-WebSocket-Protocol unprompted
    /// makes Chrome/Safari fail the handshake outright.
    static func acceptResponse(for secWebSocketKey: String, requestedProtocol: String? = nil) -> Data {
        let combined = secWebSocketKey + magicGUID
        let digest = Insecure.SHA1.hash(data: Data(combined.utf8))
        let accept = Data(digest).base64EncodedString()
        var head = "HTTP/1.1 101 Switching Protocols\r\n"
        head += "Upgrade: websocket\r\n"
        head += "Connection: Upgrade\r\n"
        head += "Sec-WebSocket-Accept: \(accept)\r\n"
        if let offered = requestedProtocol,
           offered.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }).contains("airchat") {
            head += "Sec-WebSocket-Protocol: airchat\r\n"
        }
        head += "\r\n"
        return Data(head.utf8)
    }
}
