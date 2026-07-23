import Foundation
import CryptoKit

/// Helpers for the RFC 6455 WebSocket handshake and minimal text-frame codec.
enum WebSocketFrame {
    /// `Sec-WebSocket-Accept` = base64(SHA1(key + GUID)).
    static func acceptValue(for key: String) -> String {
        let combined = Data((key + AppConstants.webSocketGUID).utf8)
        let digest = Insecure.SHA1.hash(data: combined)
        return Data(digest).base64EncodedString()
    }

    /// Builds an unmasked server→client text frame.
    static func textFrame(_ string: String) -> Data {
        let payload = Array(string.utf8)
        return makeFrame(opcode: 0x1, payload: payload, masked: false)
    }

    /// Builds a pong frame echoing a ping payload.
    static func pongFrame(_ payload: Data) -> Data {
        makeFrame(opcode: 0xA, payload: Array(payload), masked: false)
    }

    private static func makeFrame(opcode: UInt8, payload: [UInt8], masked: Bool) -> Data {
        var frame = Data()
        var byte0: UInt8 = 0x80 | opcode  // FIN + opcode
        frame.append(byte0)

        var byte1: UInt8 = masked ? 0x80 : 0x00
        var ext: Data? = nil
        if payload.count <= 125 {
            byte1 |= UInt8(payload.count)
        } else if payload.count <= 0xFFFF {
            byte1 |= 126
            var len = UInt16(payload.count).bigEndian
            ext = Data(bytes: &len, count: 2)
        } else {
            byte1 |= 127
            var len = UInt64(payload.count).bigEndian
            ext = Data(bytes: &len, count: 8)
        }
        frame.append(byte1)
        if let ext { frame.append(ext) }

        if masked {
            let mask = (0..<4).map { _ in UInt8.random(in: 0...255) }
            frame.append(contentsOf: mask)
            for i in 0..<payload.count {
                frame.append(payload[i] ^ mask[i % 4])
            }
        } else {
            frame.append(contentsOf: payload)
        }
        return frame
    }
}

/// Parses incoming (client→server, always masked) WebSocket frames from a stream.
final class WebSocketFrameDecoder {
    private var buffer = Data()

    func append(_ data: Data) { buffer.append(data) }

    /// Decodes as many complete frames as currently available.
    /// Returns an array of `(opcode, payload)`. Handles fragmentation minimally
    /// (our clients send single text frames).
    func decode() -> [(opcode: UInt8, payload: Data)] {
        var results: [(UInt8, Data)] = []
        while true {
            guard let frame = decodeOne() else { break }
            results.append(frame)
        }
        return results
    }

    private func decodeOne() -> (UInt8, Data)? {
        guard buffer.count >= 2 else { return nil }
        let b0 = buffer[0]
        let b1 = buffer[1]
        let opcode = b0 & 0x0F
        let masked = (b1 & 0x80) != 0
        var len = Int(b1 & 0x7F)
        var offset = 2

        if len == 126 {
            guard buffer.count >= offset + 2 else { return nil }
            len = (Int(buffer[offset]) << 8) | Int(buffer[offset + 1])
            offset += 2
        } else if len == 127 {
            guard buffer.count >= offset + 8 else { return nil }
            var v: UInt64 = 0
            for i in 0..<8 { v = (v << 8) | UInt64(buffer[offset + i]) }
            len = Int(v)
            offset += 8
        }

        var maskKey: [UInt8] = []
        if masked {
            guard buffer.count >= offset + 4 else { return nil }
            maskKey = Array(buffer[offset..<offset + 4])
            offset += 4
        }

        guard buffer.count >= offset + len else { return nil }
        var payload = buffer.subdata(in: offset..<(offset + len))
        if masked {
            for i in 0..<payload.count {
                payload[i] ^= maskKey[i % 4]
            }
        }
        buffer.removeSubrange(0..<(offset + len))
        return (opcode, payload)
    }
}
