import Foundation
import Network

/// Wraps a single upgraded WebSocket connection (a browser client) and runs its
/// read loop. Text frames are forwarded to the owning `AirChatServer`.
final class ClientConnection {
    private let connection: NWConnection
    private weak var server: AirChatServer?
    private let decoder = WebSocketFrameDecoder()

    init(connection: NWConnection, server: AirChatServer) {
        self.connection = connection
        self.server = server
    }

    func startReading() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.decoder.append(data)
                for (opcode, payload) in self.decoder.decode() {
                    self.handle(opcode: opcode, payload: payload)
                }
            }
            if isComplete || error != nil {
                self.server?.clientDidDisconnect(self)
                return
            }
            self.startReading()
        }
    }

    private func handle(opcode: UInt8, payload: Data) {
        switch opcode {
        case 0x1, 0x0: // text / continuation
            if let text = String(data: payload, encoding: .utf8) {
                server?.client(self, didReceive: text)
            }
        case 0x9: // ping → pong
            connection.send(content: WebSocketFrame.pongFrame(payload), completion: .idempotent)
        case 0x8: // close
            server?.clientDidDisconnect(self)
        default:
            break
        }
    }

    func sendText(_ text: String) {
        connection.send(content: WebSocketFrame.textFrame(text), completion: .idempotent)
    }

    func close() {
        connection.cancel()
    }
}
