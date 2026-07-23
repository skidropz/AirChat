import Foundation

/// Constants shared across the whole app.
enum AppConstants {
    /// Port the embedded host server listens on (matches the Android app).
    static let port: UInt16 = 8080

    /// Bonjour service type used by MultipeerConnectivity for the iOS mesh.
    /// Must be <= 14 chars and unique to the app.
    static let meshServiceType = "airchat-mesh"

    /// Maximum chat messages kept for replaying to newly connected clients.
    static let maxHistory = 50

    /// Bubble colours and their hex values (identical to the web client).
    static let colors: [String] = ["blue", "red", "green", "purple", "orange", "white"]

    static let colorHex: [String: String] = [
        "blue":   "#0084FF",
        "red":    "#FF3B30",
        "green":  "#34C759",
        "purple": "#AF52DE",
        "orange": "#FF9500",
        "white":  "#FFFFFF"
    ]

    /// Characters used for the 4-letter short connection code.
    static let shortCodeAlphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

    /// Magic GUID appended to the WebSocket key during the RFC 6455 handshake.
    static let webSocketGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
}

/// Top-level navigation / operating mode of the app.
enum AppMode: Equatable {
    case host
    case client
}
