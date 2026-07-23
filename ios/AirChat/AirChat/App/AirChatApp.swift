import SwiftUI

@main
struct AirChatApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Top-level navigation state.
enum Route: Equatable {
    case start
    case hostSetup
    case join
    case chat
}

struct RootView: View {
    @State private var route: Route = .start
    @State private var store: ChatStore?
    // Name + colour chosen on the start screen, kept for the join flow.
    @State private var pendingName: String = "Guest"
    @State private var pendingColor: String = "blue"
    // Connection details collected on the Join screen.
    @State private var joinHost: String = ""
    @State private var joinPort: UInt16 = AppConstants.port
    @State private var joinKey: String = ""

    var body: some View {
        NavigationStack {
            switch route {
            case .start:
                StartView { name, color, mode in
                    startFlow(name: name, color: color, mode: mode)
                }
            case .hostSetup:
                if let store {
                    HostSetupView(store: store) {
                        route = .chat
                    }
                }
            case .join:
                JoinView { host, port, key in
                    joinHost = host; joinPort = port; joinKey = key
                    let s = ChatStore(mode: .client, name: pendingName, color: pendingColor,
                                      roomKey: key, shortCode: "",
                                      localIp: NetworkUtils.localWiFiIPv4() ?? "0.0.0.0")
                    s.startAsClient(host: host, port: port, key: key)
                    store = s
                    route = .chat
                }
            case .chat:
                if let store {
                    ChatView(store: store) {
                        store.shutdown()
                        self.store = nil
                        route = .start
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func startFlow(name: String, color: String, mode: AppMode) {
        switch mode {
        case .host:
            // Generate room key (32 random bytes, base64url) + short code.
            let raw = (0..<32).map { _ in UInt8.random(in: 0...255) }
            let roomKey = Data(raw)
                .base64URLEncodedString()
            let shortCode = String((0..<4).map { _ in
                AppConstants.shortCodeAlphabet.randomElement()!
            })
            let ip = NetworkUtils.localWiFiIPv4() ?? "192.168.1.2"
            let s = ChatStore(mode: .host, name: name, color: color,
                              roomKey: roomKey, shortCode: shortCode, localIp: ip)
            s.startAsHost()
            store = s
            route = .hostSetup
        case .client:
            pendingName = name
            pendingColor = color
            route = .join
        }
    }
}

extension Data {
    /// base64url encoding (no padding), matching the web key format.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
