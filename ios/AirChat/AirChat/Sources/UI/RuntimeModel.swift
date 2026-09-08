//
//  RuntimeModel.swift
//  AirChat
//
//  Observable mirror of AppRuntime for the SwiftUI sheets. The runtime itself stays
//  UIKit-agnostic and just posts `.airChatStateChanged`; this object turns that into
//  @Published values so the panel re-renders.
//

import Combine
import Foundation

/// Everything here is touched from the main queue only (UIKit + SwiftUI), so no actor
/// annotations are needed; the notification and the timer both fire on .main.
final class RuntimeModel: ObservableObject {

    @Published var hostIP = "127.0.0.1"
    @Published var port: UInt16 = 8080
    @Published var shortCode = ""
    @Published var roomKey = ""
    @Published var clientCount = 0
    @Published var isHosting = false
    @Published var isServing = false
    @Published var hotspotUp = false
    @Published var interfaces: [InterfaceAddress] = []
    @Published var meshEnabled = false
    @Published var meshPeers: [MeshPeer] = []
    @Published var discoveredPeers: [MeshPeer] = []
    @Published var nearbyRooms: [DiscoveredRoom] = []
    @Published var keepAliveEnabled = false
    @Published var screenAwakeEnabled = false
    @Published var uptime = "—"
    @Published var statusLine = ""
    @Published var lastError: String?

    private var token: NSObjectProtocol?
    private var timer: AnyCancellable?

    init() {
        reload()
        token = NotificationCenter.default.addObserver(forName: .airChatStateChanged, object: nil, queue: .main) { [weak self] _ in
            self?.reload()
        }
        // Uptime/clients change without an explicit notification.
        timer = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.reload() }
    }

    deinit {
        if let token = token { NotificationCenter.default.removeObserver(token) }
    }

    func reload() {
        let runtime = AppRuntime.shared
        hostIP = runtime.currentHostIP
        port = runtime.port
        shortCode = runtime.room.shortCode
        roomKey = runtime.room.keyBase64URL
        clientCount = runtime.clientCount
        isHosting = runtime.isHosting
        isServing = runtime.isServing
        hotspotUp = NetworkInfo.isPersonalHotspotUp
        interfaces = NetworkInfo.all
        meshEnabled = runtime.isMeshEnabled
        meshPeers = runtime.meshPeers
        discoveredPeers = runtime.discoveredPeers
        nearbyRooms = runtime.nearbyRooms
        keepAliveEnabled = runtime.keepAliveEnabled
        screenAwakeEnabled = runtime.screenAwakeEnabled
        uptime = runtime.uptimeText
        statusLine = runtime.statusSummary
        lastError = runtime.server?.lastError
    }

    var browserAddress: String { "http://\(hostIP):\(port)/\(shortCode)" }
    var guideAddress: String { "http://\(hostIP):\(port)/ios-install" }
    var onlyCellular: Bool {
        !interfaces.isEmpty && interfaces.allSatisfy { $0.kind == .cellular || $0.kind == .other }
    }
}
