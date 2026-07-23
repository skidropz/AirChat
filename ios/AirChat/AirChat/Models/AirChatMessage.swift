import Foundation

// MARK: - Wire-format models
//
// These mirror the JSON contract used by the web client (`app.js`) so that the
// native app is fully interoperable with browser / Android clients.
//
// Outer (possibly encrypted) envelope:
//   {"type":"encrypted","innerType":"chat","payload":"<base64 xor>"}
// or a plain message object when no room key is in use.

/// The outer envelope that travels over the WebSocket / mesh wire.
struct WireEnvelope: Codable {
    var type: String
    var innerType: String?
    var payload: String?
}

/// A fully decoded chat message of any type (chat / image / audio / buzz / system /
/// location_update / seen).
struct AirChatMessage: Codable, Hashable {
    var type: String
    var id: String?
    var sender: String?
    var color: String?
    /// "general" / "all" for the global room, or a peer name for a 1-on-1 chat.
    var recipient: String?
    var text: String?
    var image: String?      // data URL
    var audio: String?      // data URL
    var replyTo: ReplyRef?
    var seenMsgId: String?
    var seenBy: String?
    var lat: Double?
    var lon: Double?
    var battery: Int?

    struct ReplyRef: Codable, Hashable {
        var id: String
        var sender: String
        var text: String
    }
}

// MARK: - Domain models for the UI

/// A known peer in the room.
struct RoomUser: Identifiable, Hashable {
    var id: String { name }
    let name: String
    var color: String
    var battery: Int?
    var lat: Double?
    var lon: Double?
    var lastSeen: Date
}

/// A grouped, displayable chat message.
struct DisplayMessage: Identifiable, Hashable {
    let id: String
    let type: MessageType
    let sender: String
    let color: String
    let chatGroup: String
    let isMine: Bool
    let text: String?
    let imageData: String?
    let audioData: String?
    let reply: AirChatMessage.ReplyRef?
    var seenBy: [String]
    var timestamp: Date
}

enum MessageType: String, Codable {
    case chat, image, audio, buzz, system
}
