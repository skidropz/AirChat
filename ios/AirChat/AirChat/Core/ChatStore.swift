import Foundation
import SwiftUI
import Combine
import CoreLocation
import MultipeerConnectivity

/// The central hub that owns the message protocol, the transports (server /
/// mesh / client) and all UI state. Observable so SwiftUI views react live.
@MainActor
final class ChatStore: ObservableObject {

    // MARK: - Identity & config
    let mode: AppMode
    let myName: String
    private(set) var myColor: String
    let roomKey: String          // base64url room key (XOR key + AES source)
    let shortCode: String
    let localIp: String
    let port: UInt16

    private let xor: XORCipher

    // MARK: - UI state
    @Published var messages: [DisplayMessage] = []
    @Published var users: [String: RoomUser] = [:]
    @Published var activeChat: String = "general"
    @Published var unreadCounts: [String: Int] = [:]
    @Published var connected: Bool = false
    @Published var meshPeers: [String] = []
    @Published var shakeTrigger: Int = 0           // increments on Buzz
    @Published var buzzBanner: String? = nil       // transient buzz notification

    // MARK: - Transports (host)
    private var server: AirChatServer?
    private var mesh: MeshManager?

    // MARK: - Transports (client)
    private var wsClient: WebSocketClient?
    @Published var clientReconnecting: Bool = false

    // MARK: - Sensors
    let locationManager = LocationManager()
    let batteryMonitor = BatteryMonitor()
    private var statusTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(mode: AppMode, name: String, color: String, roomKey: String,
         shortCode: String, localIp: String, port: UInt16 = AppConstants.port) {
        self.mode = mode
        self.myName = name
        self.myColor = color
        self.roomKey = roomKey
        self.shortCode = shortCode
        self.localIp = localIp
        self.port = port
        self.xor = XORCipher(key: roomKey)

        observeSensors()
        startStatusBroadcast()
    }

    // MARK: - Lifecycle

    func startAsHost() {
        let server = AirChatServer(port: port, localIp: localIp,
                                   roomKey: roomKey, shortCode: shortCode)
        server.delegate = self
        do {
            try server.start()
        } catch {
            print("AirChatServer failed to start: \(error)")
        }
        self.server = server

        let mesh = MeshManager(displayName: "iOS-\(myName)", roomKeyBase64: roomKey)
        mesh.delegate = self
        mesh.start()
        self.mesh = mesh

        connected = true
        announceJoin()
    }

    func startAsClient(host: String, port: UInt16, key: String) {
        guard let url = URL(string: "ws://\(host):\(port)/") else { return }
        let client = WebSocketClient(url: url)
        client.delegate = self
        client.connect()
        self.wsClient = client
        connected = false // becomes true on connect
    }

    func shutdown() {
        statusTimer?.invalidate()
        server?.stop()
        mesh?.stop()
        wsClient?.disconnect()
    }

    // MARK: - Public actions (called from the UI)

    func sendText(_ text: String, replyTo: AirChatMessage.ReplyRef? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var msg = AirChatMessage(type: "chat", id: genId())
        msg.text = trimmed
        msg.replyTo = replyTo
        sendOutgoing(msg)
    }

    func sendImage(dataURL: String, replyTo: AirChatMessage.ReplyRef? = nil) {
        var msg = AirChatMessage(type: "image", id: genId())
        msg.image = dataURL
        msg.replyTo = replyTo
        sendOutgoing(msg)
    }

    func sendAudio(dataURL: String, replyTo: AirChatMessage.ReplyRef? = nil) {
        var msg = AirChatMessage(type: "audio", id: genId())
        msg.audio = dataURL
        msg.replyTo = replyTo
        sendOutgoing(msg)
    }

    func sendBuzz(to recipient: String) {
        var msg = AirChatMessage(type: "buzz", id: genId())
        msg.recipient = recipient
        sendOutgoing(msg)
    }

    func sendSeen(messageId: String) {
        var msg = AirChatMessage(type: "seen")
        msg.seenMsgId = messageId
        msg.seenBy = myName
        sendOutgoing(msg, isTransient: true)
    }

    // MARK: - Outgoing pipeline

    private func sendOutgoing(_ msg: AirChatMessage, isTransient: Bool = false) {
        var m = msg
        m.sender = myName
        m.color = myColor
        if m.recipient == nil { m.recipient = activeChat }

        if !isTransient {
            applyMessage(m, isMine: true, raw: nil)
        }

        let raw = encode(m)
        switch mode {
        case .host:
            server?.broadcastToAll(raw)
            mesh?.send(raw)
        case .client:
            wsClient?.send(raw)
        }
    }

    // MARK: - Incoming routing

    func fromWeb(_ raw: String) {
        // Already echoed to browsers + history by the server; forward to mesh + UI.
        applyRaw(raw)
        if mode == .host { mesh?.send(raw) }
    }

    func fromMesh(_ raw: String) {
        applyRaw(raw)
        if mode == .host { server?.broadcastToAll(raw) }
    }

    func fromRemote(_ raw: String) {
        applyRaw(raw)
    }

    private func applyRaw(_ raw: String) {
        guard let msg = decode(raw) else { return }
        switch msg.type {
        case "location_update":
            handleLocationUpdate(msg)
        case "seen":
            handleSeen(msg)
        default:
            applyMessage(msg, isMine: (msg.sender == myName), raw: raw)
        }
    }

    // MARK: - Message application

    private func applyMessage(_ msg: AirChatMessage, isMine: Bool, raw: String?) {
        switch msg.type {
        case "buzz":
            handleBuzz(msg, isMine: isMine)
        case "system":
            handleSystem(msg, isMine: isMine)
        case "chat", "image", "audio":
            addDisplayMessage(msg, isMine: isMine)
        default:
            break
        }
    }

    private func addDisplayMessage(_ msg: AirChatMessage, isMine: Bool) {
        // Private routing filter: ignore 1-on-1 messages not addressed to me.
        let group = chatGroup(for: msg, isMine: isMine)
        if group != "general" && !isMine {
            let recipient = (msg.recipient ?? "").lowercased()
            if recipient != myName.lowercased() && (msg.sender ?? "").lowercased() != myName.lowercased() {
                return
            }
        }

        guard let id = msg.id else { return }

        // Dedup by id.
        if messages.contains(where: { $0.id == id }) { return }

        let display = DisplayMessage(
            id: id,
            type: MessageType(rawValue: msg.type) ?? .chat,
            sender: msg.sender ?? (isMine ? myName : "?"),
            color: msg.color ?? "blue",
            chatGroup: group,
            isMine: isMine,
            text: msg.text,
            imageData: msg.image,
            audioData: msg.audio,
            reply: msg.replyTo,
            seenBy: [],
            timestamp: Date()
        )
        messages.append(display)

        // Track the sender as a known user.
        if let sender = msg.sender, !sender.isEmpty, sender != myName {
            var user = users[sender] ?? RoomUser(name: sender, color: msg.color ?? "blue",
                                                  battery: nil, lat: nil, lon: nil, lastSeen: Date())
            user.color = msg.color ?? user.color
            user.lastSeen = Date()
            users[sender] = user
        }

        // Unread handling.
        if group != activeChat && !isMine {
            unreadCounts[group, default: 0] += 1
        } else if group == activeChat && !isMine {
            sendSeen(messageId: id)
        }
    }

    private func handleSystem(_ msg: AirChatMessage, isMine: Bool) {
        // Detect join announcements ("X joined." / "X s-a conectat.").
        if let text = msg.text {
            let name = text
                .replacingOccurrences(of: " joined.", with: "")
                .replacingOccurrences(of: " s-a conectat.", with: "")
            if !name.isEmpty && name != text {
                if users[name] == nil && name != myName {
                    users[name] = RoomUser(name: name, color: "blue", battery: nil,
                                            lat: nil, lon: nil, lastSeen: Date())
                }
            }
            messages.append(DisplayMessage(
                id: msg.id ?? UUID().uuidString,
                type: .system,
                sender: msg.sender ?? "",
                color: "white",
                chatGroup: "general",
                isMine: false,
                text: text,
                imageData: nil, audioData: nil, reply: nil,
                seenBy: [], timestamp: Date()
            ))
        }
    }

    private func handleBuzz(_ msg: AirChatMessage, isMine: Bool) {
        let sender = msg.sender ?? "?"
        let isGeneral = (msg.recipient ?? "general").lowercased() == "general" || msg.recipient == nil
        if !isGeneral {
            let recipient = (msg.recipient ?? "").lowercased()
            if recipient != myName.lowercased() && (msg.sender ?? "").lowercased() != myName.lowercased() {
                return
            }
        }
        Buzz.trigger()
        shakeTrigger &+= 1
        let banner = String(format: NSLocalizedString("buzz_msg", comment: ""), sender)
        buzzBanner = banner
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if self?.buzzBanner == banner { self?.buzzBanner = nil }
        }
        messages.append(DisplayMessage(
            id: msg.id ?? UUID().uuidString,
            type: .system,
            sender: sender, color: "white",
            chatGroup: chatGroup(for: msg, isMine: isMine),
            isMine: false, text: banner,
            imageData: nil, audioData: nil, reply: nil,
            seenBy: [], timestamp: Date()
        ))
    }

    private func handleSeen(_ msg: AirChatMessage) {
        guard let msgId = msg.seenMsgId, let who = msg.seenBy, who != myName else { return }
        if let idx = messages.firstIndex(where: { $0.id == msgId }) {
            if !messages[idx].seenBy.contains(who) {
                messages[idx].seenBy.append(who)
            }
        }
    }

    private func handleLocationUpdate(_ msg: AirChatMessage) {
        guard let sender = msg.sender, sender != myName else { return }
        var user = users[sender] ?? RoomUser(name: sender, color: "blue",
                                              battery: nil, lat: nil, lon: nil, lastSeen: Date())
        if let lat = msg.lat, let lon = msg.lon, lat != 0 || lon != 0 {
            user.lat = lat
            user.lon = lon
        }
        user.battery = msg.battery
        user.lastSeen = Date()
        users[sender] = user
    }

    // MARK: - Helpers

    private func chatGroup(for msg: AirChatMessage, isMine: Bool) -> String {
        let r = (msg.recipient ?? "general").lowercased()
        let isGeneral = r == "general" || r == "all" || msg.recipient == nil || msg.recipient == ""
        if isGeneral { return "general" }
        return isMine ? (msg.recipient ?? "general") : (msg.sender ?? "general")
    }

    private func announceJoin() {
        var msg = AirChatMessage(type: "system")
        msg.text = "\(myName)" + NSLocalizedString("joined_suffix", comment: "")
        sendOutgoing(msg, isTransient: false)
    }

    private func genId() -> String {
        "msg-\(Int(Date().timeIntervalSince1970 * 1000))-\(Int.random(in: 0..<10000))"
    }

    // MARK: - Sensors / status broadcast

    private func observeSensors() {
        locationManager.$coordinate
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in }
            .store(in: &cancellables)
        batteryMonitor.refresh()
    }

    private func startStatusBroadcast() {
        statusTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.broadcastStatus() }
        }
    }

    private func broadcastStatus() {
        var msg = AirChatMessage(type: "location_update")
        msg.sender = myName
        msg.color = myColor
        msg.lat = locationManager.coordinate?.latitude ?? 0
        msg.lon = locationManager.coordinate?.longitude ?? 0
        msg.battery = batteryMonitor.level
        let raw = encode(msg)
        switch mode {
        case .host:
            server?.broadcastToAll(raw)
            mesh?.send(raw)
        case .client:
            wsClient?.send(raw)
        }
    }
}

// MARK: - Codec

extension ChatStore {
    /// Serialises an `AirChatMessage` to the wire format (optionally XOR-wrapped).
    func encode(_ msg: AirChatMessage) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: msg.dictionary()),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        guard !roomKey.isEmpty else { return json }
        let payload = xor.encrypt(json)
        let env: [String: Any] = ["type": "encrypted", "innerType": msg.type, "payload": payload]
        guard let envData = try? JSONSerialization.data(withJSONObject: env),
              let envString = String(data: envData, encoding: .utf8) else { return json }
        return envString
    }

    /// Parses a wire text into a typed message.
    func decode(_ raw: String) -> AirChatMessage? {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let type = obj["type"] as? String, type == "encrypted",
           let payload = obj["payload"] as? String {
            guard let inner = xor.decrypt(payload),
                  let innerData = inner.data(using: .utf8),
                  let innerObj = try? JSONSerialization.jsonObject(with: innerData) as? [String: Any] else {
                return nil
            }
            return AirChatMessage(dictionary: innerObj)
        }
        return AirChatMessage(dictionary: obj)
    }
}

// MARK: - Dictionary bridging

extension AirChatMessage {
    init(dictionary d: [String: Any]) {
        self.type = (d["type"] as? String) ?? "chat"
        self.id = d["id"] as? String
        self.sender = d["sender"] as? String
        self.color = d["color"] as? String
        self.recipient = d["recipient"] as? String
        self.text = d["text"] as? String
        self.image = d["image"] as? String
        self.audio = d["audio"] as? String
        self.seenMsgId = d["seenMsgId"] as? String
        self.seenBy = d["seenBy"] as? String
        self.lat = (d["lat"] as? Double) ?? (d["lat"] as? Int).map(Double.init)
        self.lon = (d["lon"] as? Double) ?? (d["lon"] as? Int).map(Double.init)
        if let b = d["battery"] as? Int { self.battery = b }
        else if let b = d["battery"] as? Double { self.battery = Int(b) }
        if let r = d["replyTo"] as? [String: Any],
           let id = r["id"] as? String, let sender = r["sender"] as? String, let text = r["text"] as? String {
            self.replyTo = ReplyRef(id: id, sender: sender, text: text)
        }
    }

    func dictionary() -> [String: Any] {
        var d: [String: Any] = ["type": type]
        if let id { d["id"] = id }
        if let sender { d["sender"] = sender }
        if let color { d["color"] = color }
        if let recipient { d["recipient"] = recipient }
        if let text { d["text"] = text }
        if let image { d["image"] = image }
        if let audio { d["audio"] = audio }
        if let seenMsgId { d["seenMsgId"] = seenMsgId }
        if let seenBy { d["seenBy"] = seenBy }
        if let lat { d["lat"] = lat }
        if let lon { d["lon"] = lon }
        if let battery { d["battery"] = battery }
        if let replyTo {
            d["replyTo"] = ["id": replyTo.id, "sender": replyTo.sender, "text": replyTo.text]
        }
        return d
    }
}

// MARK: - Server delegate

extension ChatStore: AirChatServerDelegate {
    nonisolated func webClientDidSendMessage(_ text: String) {
        Task { @MainActor in self.fromWeb(text) }
    }
}

// MARK: - Mesh delegate

extension ChatStore: MeshManagerDelegate {
    nonisolated func mesh(_ mesh: MeshManager, didReceiveMessage text: String) {
        Task { @MainActor in self.fromMesh(text) }
    }
    nonisolated func mesh(_ mesh: MeshManager, connectedPeersChanged peers: [String]) {
        Task { @MainActor in self.meshPeers = peers }
    }
    nonisolated func mesh(_ mesh: MeshManager, didDiscoverPeer name: String, id: MCPeerID) {
        // Auto-connect handled in MeshManager; no UI prompt needed.
    }
}

// MARK: - WebSocket client delegate

extension ChatStore: WebSocketClientDelegate {
    nonisolated func webSocketClient(_ client: WebSocketClient, didReceive text: String) {
        Task { @MainActor in
            if text == "ping" { return }
            self.fromRemote(text)
        }
    }
    nonisolated func webSocketClientDidConnect(_ client: WebSocketClient) {
        Task { @MainActor in
            self.connected = true
            self.clientReconnecting = false
            self.announceJoin()
        }
    }
    nonisolated func webSocketClientDidDisconnect(_ client: WebSocketClient) {
        Task { @MainActor in
            self.connected = false
            self.clientReconnecting = true
        }
    }
}
