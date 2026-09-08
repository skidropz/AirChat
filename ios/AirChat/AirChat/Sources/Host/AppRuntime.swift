//
//  AppRuntime.swift
//  AirChat
//
//  The object that plays the role MainActivity plays on Android: it owns the room
//  key, the HTTP/WebSocket server, the mesh, the sensors and the keep-alive, and it
//  hands events to whoever is showing UI.
//

import CoreLocation
import Foundation
import UIKit

protocol AppRuntimeObserver: AnyObject {
    func runtimeDidUpdateHeading(_ degrees: Double)
    func runtimeDidUpdateLocation(latitude: Double, longitude: Double)
    func runtimeDidFindMeshPeer(_ peer: MeshPeer)
    func runtimeDidReceiveMeshJSON(_ json: String)
    func runtimeDidUpdateState()
    func runtimeDidFail(_ message: String)
}

extension AppRuntimeObserver {
    func runtimeDidUpdateHeading(_ degrees: Double) {}
    func runtimeDidUpdateLocation(latitude: Double, longitude: Double) {}
    func runtimeDidFindMeshPeer(_ peer: MeshPeer) {}
    func runtimeDidReceiveMeshJSON(_ json: String) {}
    func runtimeDidUpdateState() {}
    func runtimeDidFail(_ message: String) {}
}

extension Notification.Name {
    static let airChatStateChanged = Notification.Name("com.skidropz.airchat.state")
    /// object: URL — "load this other host's page instead of my own room".
    static let airChatJoinRequested = Notification.Name("com.skidropz.airchat.join")
}

final class AppRuntime: NSObject {

    static let shared = AppRuntime()

    // MARK: - Persistent settings

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let hosting = "host.hostingEnabled"
        static let mesh = "host.meshEnabled"
        static let keepAlive = "host.keepAliveEnabled"
        static let screenAwake = "host.screenAwakeEnabled"
        static let port = "host.port"
    }

    /// Port the room listens on. 8080 matches Android so existing habits, saved QR
    /// codes and the Android app's own links keep working. Ports below 1024 (80 =
    /// a real captive portal) are offered in the panel but iOS often refuses them for
    /// non-root apps; the listener reports the failure instead of crashing.
    var port: UInt16 {
        get {
            let stored = defaults.integer(forKey: Keys.port)
            return stored > 0 && stored < 65536 ? UInt16(stored) : 8080
        }
        set {
            defaults.set(Int(newValue), forKey: Keys.port)
            restartServer()
        }
    }

    var isHostingEnabled: Bool {
        get { defaults.object(forKey: Keys.hosting) == nil ? true : defaults.bool(forKey: Keys.hosting) }
        set { defaults.set(newValue, forKey: Keys.hosting); newValue ? startHosting() : stopHosting() }
    }

    var isMeshEnabled: Bool {
        get { defaults.object(forKey: Keys.mesh) == nil ? true : defaults.bool(forKey: Keys.mesh) }
        set {
            defaults.set(newValue, forKey: Keys.mesh)
            newValue ? startMesh() : stopMesh()
        }
    }

    /// Background serving through a silent audio session. On by default: on iOS it is
    /// the difference between "a phone that hosts" and "a phone that stops hosting the
    /// moment it is locked". See Host/KeepAlive.swift.
    var keepAliveEnabled: Bool {
        get { defaults.object(forKey: Keys.keepAlive) == nil ? true : defaults.bool(forKey: Keys.keepAlive) }
        set {
            defaults.set(newValue, forKey: Keys.keepAlive)
            if newValue { _ = KeepAlive.shared.enable() } else { KeepAlive.shared.disable() }
            notify()
        }
    }

    var screenAwakeEnabled: Bool {
        get { defaults.object(forKey: Keys.screenAwake) == nil ? true : defaults.bool(forKey: Keys.screenAwake) }
        set {
            defaults.set(newValue, forKey: Keys.screenAwake)
            UIApplication.shared.isIdleTimerDisabled = newValue && isHosting
        }
    }

    // MARK: - Components

    let room = RoomState()
    private(set) var server: AirChatServer?
    private(set) var mesh: MeshManager?
    let location = LocationProvider()
    let bonjour = AirChatBonjour()

    weak var observer: AppRuntimeObserver?

    private var ipTimer: Timer?
    private var announcedIP = ""
    private(set) var currentHostIPValue = "127.0.0.1"
    var currentHostIP: String { currentHostIPValue }

    var isHosting: Bool { server != nil && isHostingEnabled }
    var clientCount: Int { server?.clientCount ?? 0 }
    var meshPeers: [MeshPeer] { mesh?.connectedPeers ?? [] }
    var discoveredPeers: [MeshPeer] { mesh?.pendingInvites ?? [] }
    var nearbyRooms: [DiscoveredRoom] { bonjour.discovered }
    var isServing: Bool { server?.isRunning ?? false }

    var uptimeText: String {
        guard let started = server?.startedAt else { return "—" }
        let seconds = Int(Date().timeIntervalSince(started))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
    }

    var statusSummary: String {
        if let error = server?.lastError { return error }
        guard isHosting else { return Localization.t("SERVER_STOPPED", "Server stopped") }
        let net = NetworkInfo.isPersonalHotspotUp
            ? Localization.t("NET_HOTSPOT", "Personal Hotspot")
            : Localization.t("NET_LAN", "Wi-Fi / LAN")
        return Localization.f("SERVER_LIVE", "Live on %@:%d · %@ · %d client(s)",
                             [currentHostIP, Int(port), net, clientCount])
    }

    // MARK: - Boot

    override private init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(appDidEnterBackground),
                           name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(appWillEnterForeground),
                           name: UIApplication.willEnterForegroundNotification, object: nil)
        center.addObserver(self, selector: #selector(sceneMayNeedRebind),
                           name: UIScene.didActivateNotification, object: nil)
    }

    @objc private func sceneMayNeedRebind() {
        location.start()
        if isMeshEnabled { startMesh() }
        bonjour.startBrowsing()
        refreshIP(force: true)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        ipTimer?.invalidate()
    }

    /// Called once the first scene is on screen (SceneDelegate).
    func activate() {
        location.delegate = self
        bonjour.onRoomsChanged = { [weak self] _ in self?.notify() }
        startIPWatcher()
        if isHostingEnabled { startHosting() }
        location.requestPermissionAndStart()
        if isMeshEnabled { startMesh() }
        bonjour.startBrowsing()
    }

    @objc private func appDidEnterBackground() {
        if isHosting && keepAliveEnabled {
            _ = KeepAlive.shared.enable()
            KeepAlive.shared.beginBackgroundTask()
        }
    }

    @objc private func appWillEnterForeground() {
        KeepAlive.shared.endBackgroundTask()
        refreshIP(force: true)
    }

    // MARK: - Hosting

    func startHosting() {
        guard isHostingEnabled else { return }
        refreshIPValue()
        var config = AirChatServer.Config()
        config.port = port
        config.hostIP = currentHostIP
        config.roomKey = room.keyBase64URL
        config.shortCode = room.shortCode
        let server = AirChatServer(config: config)
        server.delegate = self
        server.start()
        self.server = server
        bonjour.publish(code: room.shortCode, port: port)
        if keepAliveEnabled { _ = KeepAlive.shared.enable() }
        UIApplication.shared.isIdleTimerDisabled = screenAwakeEnabled
        NSLog("AirChat: hosting started ip=\(currentHostIP) port=\(port)")
        notify()
    }

    func stopHosting() {
        server?.stop()
        server = nil
        bonjour.stopPublishing()
        KeepAlive.shared.disable()
        UIApplication.shared.isIdleTimerDisabled = false
        notify()
    }

    func restartServer() {
        guard isHostingEnabled else { notify(); return }
        stopHosting()
        startHosting()
    }

    /// New room key + code, i.e. a brand new room. Connected clients must reload.
    func rotateRoom() {
        room.rotate()
        server?.updateRoom(key: room.keyBase64URL, code: room.shortCode)
        if isHosting { bonjour.publish(code: room.shortCode, port: port) }
        restartMesh()
        notify()
    }

    var joinURL: URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = currentHostIP
        components.port = Int(port)
        components.path = "/" + room.shortCode
        components.fragment = room.keyBase64URL
        return components.url
    }

    /// airchat:// deep link, so a scanned QR can open this app directly instead of
    /// dumping the user into Safari on a captive-portal-less network.
    var deepLink: URL? {
        var components = URLComponents()
        components.scheme = "airchat"
        components.host = "join"
        components.queryItems = [
            URLQueryItem(name: "host", value: currentHostIP),
            URLQueryItem(name: "port", value: String(port)),
            URLQueryItem(name: "code", value: room.shortCode)
        ]
        return components.url
    }

    /// What we tell friends to type in a browser (identical UX to the Android app).
    var browserAddress: String { "http://\(currentHostIP):\(port)/\(room.shortCode)" }

    /// Stop hosting and open somebody else's room in the WebView instead.
    func joinRoom(url: URL) {
        stopHosting()
        NotificationCenter.default.post(name: .airChatJoinRequested, object: url)
    }

    func joinRoom(host: String, port: UInt16, code: String?) {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = Int(port)
        components.path = (code?.isEmpty == false) ? "/\(code!)" : "/"
        if let url = components.url { joinRoom(url: url) }
    }

    /// airchat://join?host=..&port=..&code=..  — what the QR code / guide page links to
    /// so an iPhone can hop straight into the app instead of Safari.
    @discardableResult
    func handleDeepLink(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "airchat" else { return false }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ key: String) -> String? { items.first { $0.name == key }?.value }
        guard let host = value("host"), !host.isEmpty else { return false }
        let portValue = UInt16(value("port") ?? "") ?? 8080
        joinRoom(host: host, port: portValue, code: value("code"))
        return true
    }

    /// No public API can enable tethering, so the closest thing is dropping the user
    /// on the right Settings pane. Works on non-App-Store builds; App-prefs: is a
    /// private scheme and would be rejected in review — another reason this app is
    /// distributed outside the store.
    /// Settings cannot be toggled programmatically on iOS: there is no API for
    /// Personal Hotspot, so the best a third-party app can do is leave the app.
    /// Since iOS 10 the private `App-prefs:` panes only answer for the *calling*
    /// app's own page, hence the probe plus the plain-settings fallback. The UI keeps
    /// telling the user to switch the hotspot on by hand.
    func openHotspotSettings() {
        let candidates = ["App-prefs:WI-Fi&tethering", "App-prefs:tethering", "prefs:root=WI-Fi"]
        for candidate in candidates {
            if let url = URL(string: candidate), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:]) { opened in
                    if !opened { self.openSystemSettings() }
                }
                return
            }
        }
        openSystemSettings()
    }

    func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    func connectMeshPeer(_ peer: MeshPeer) {
        guard let mesh = mesh else { startMesh(); return }
        mesh.connect(to: peer)
    }

    func disconnectMeshPeer(_ peer: MeshPeer) {
        mesh?.disconnect(from: peer)
        notify()
    }

    // MARK: - Mesh

    func startMesh() {
        guard isMeshEnabled, mesh == nil else { return }
        let manager = MeshManager(roomKeyBase64URL: room.keyBase64URL)
        manager.delegate = self
        manager.start()
        mesh = manager
        notify()
    }

    func stopMesh() {
        mesh?.stop()
        mesh = nil
        notify()
    }

    private func restartMesh() {
        stopMesh()
        startMesh()
    }

    // MARK: - IP watcher

    private func startIPWatcher() {
        guard ipTimer == nil else { return }
        let timer = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refreshIP(force: false)
        }
        RunLoop.main.add(timer, forMode: .common)
        ipTimer = timer
    }

    private func refreshIPValue() {
        currentHostIPValue = NetworkInfo.bestHostAddress()?.ip ?? "127.0.0.1"
    }

    private func refreshIP(force: Bool) {
        let previous = currentHostIPValue
        refreshIPValue()
        guard force || currentHostIPValue != previous || previous == "127.0.0.1" else { return }
        announcedIP = currentHostIPValue
        server?.updateHostIP(currentHostIPValue)
        if isHosting { bonjour.publish(code: room.shortCode, port: port) }
        notify()
    }

    /// A frame that came from the WebView / a browser client: put it on the mesh.
    func forwardToMesh(_ json: String) {
        mesh?.send(json: json)
    }

    func notify() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.observer?.runtimeDidUpdateState()
            NotificationCenter.default.post(name: .airChatStateChanged, object: self)
        }
    }
}

// MARK: - Server delegate

extension AppRuntime: AirChatServerDelegate {
    func airChatServer(_ server: AirChatServer, didReceiveMessage json: String) {
        forwardToMesh(json)
    }

    func airChatServer(_ server: AirChatServer, didChangeClientCount count: Int) {
        notify()
    }

    func airChatServerDidLoseAllClients(_ server: AirChatServer) {
        NSLog("AirChat: last client disconnected")
        notify()
    }

    func airChatServer(_ server: AirChatServer, didFailWith message: String) {
        observer?.runtimeDidFail(message)
        notify()
    }
}

// MARK: - Mesh delegate

extension AppRuntime: MeshManagerDelegate {
    func meshManager(_ manager: MeshManager, didReceiveJSON json: String) {
        // Mesh traffic has to reach the WebSocket clients too — same as MeshManager.kt
        // calling onMessageReceived -> server.broadcastToAll.
        server?.broadcastToAll(json)
        observer?.runtimeDidReceiveMeshJSON(json)
    }

    func meshManager(_ manager: MeshManager, didFindPeer peer: MeshPeer) {
        observer?.runtimeDidFindMeshPeer(peer)
        notify()
    }

    func meshManager(_ manager: MeshManager, didLosePeer peer: MeshPeer) {
        notify()
    }

    func meshManager(_ manager: MeshManager, didChangeConnectedPeers peers: [MeshPeer]) {
        notify()
    }

    func meshManager(_ manager: MeshManager, didFailWith message: String) {
        observer?.runtimeDidFail(message)
        notify()
    }
}

// MARK: - Location delegate

extension AppRuntime: LocationProviderDelegate {
    func locationProvider(_ provider: LocationProvider, didUpdateLatitude lat: Double, longitude lon: Double) {
        observer?.runtimeDidUpdateLocation(latitude: lat, longitude: lon)
    }

    func locationProvider(_ provider: LocationProvider, didUpdateHeading degrees: Double) {
        observer?.runtimeDidUpdateHeading(degrees)
    }

    func locationProvider(_ provider: LocationProvider, didChangeAuthorization status: CLAuthorizationStatus) {
        notify()
    }
}
