//
//  ViewController.swift
//  AirChat
//
//  The native shell: a WKWebView hosting the same chat UI the Android phone serves, a slim
//  native header (invite link + QR + server panel) and all the hardware WKWebView can't reach
//  from a plain http:// origin — microphone, photo picker, haptics, compass, GPS and battery.
//

import UIKit
import WebKit
import Darwin
import AVFoundation
import PhotosUI
import CoreHaptics
import AudioToolbox
import CoreLocation
import CoreImage
import Security

final class ViewController: UIViewController {

    private let port: UInt16 = 8080

    // MARK: - UI
    var webView: WKWebView!
    private var topBar: UIView!
    private var infoLabel: UILabel!
    private var qrButton: UIButton!
    private var panelButton: UIButton!

    // MARK: - Components
    var server: LocalServer!
    private var meshManager: MeshManager!
    private let bridge = NativeBridge()
    let keepAlive = BackgroundKeepAlive()
    private let locationManager = CLLocationManager()
    private var hapticEngine: CHHapticEngine?
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    // MARK: - State
    private var roomKey = ""
    var shortCode = ""
    private var hostIP = "192.168.43.1"
    var isHotspotActive = false
    private var cachedBattery = 100

    // MARK: - Bonjour
    private var netService: NetService?
    private var netServiceBrowser: NetServiceBrowser?
    var nearbyRooms: [NearbyRoom] = []
    var bonjourEnabled = true

    struct NearbyRoom {
        let name: String
        let host: String
        let port: Int
        let code: String
        var inviteURL: String { "http://\(host):\(port)/\(code)" }
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        generateCredentials()
        hostIP = Self.currentLocalIP()
        isHotspotActive = Self.isHotspotActive()

        buildUI()
        setupHaptics()
        setupLocation()
        setupWebView()

        startServer()
        startMesh()
        startBonjourAdvertising()
        startBonjourBrowsing()

        bridge.viewController = self

        NotificationCenter.default.addObserver(self, selector: #selector(handleJoinRoom(_:)),
                                               name: .airchatJoinRoom, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        server?.stop()
        meshManager?.stop()
        netService?.stop()
        netServiceBrowser?.stop()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return view.backgroundColor == .white ? .darkContent : .lightContent
    }

    // MARK: - Credentials

    private func generateCredentials() {
        var keyData = Data(count: 32)
        _ = keyData.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        roomKey = keyData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        shortCode = String((0..<4).map { _ in chars.randomElement()! })
    }

    // MARK: - UI construction

    private func buildUI() {
        topBar = UIView()
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.backgroundColor = .black
        view.addSubview(topBar)

        infoLabel = UILabel()
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        infoLabel.textColor = .white
        infoLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        infoLabel.textAlignment = .center
        infoLabel.numberOfLines = 1
        infoLabel.adjustsFontSizeToFitWidth = true
        infoLabel.minimumScaleFactor = 0.5
        infoLabel.isUserInteractionEnabled = true
        infoLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(copyInviteLink)))
        topBar.addSubview(infoLabel)

        qrButton = UIButton(type: .system)
        qrButton.translatesAutoresizingMaskIntoConstraints = false
        qrButton.setImage(qrThumbnail(), for: .normal)
        qrButton.tintColor = .white
        qrButton.addTarget(self, action: #selector(showLargeQR), for: .touchUpInside)
        qrButton.accessibilityLabel = "QR code"
        topBar.addSubview(qrButton)

        panelButton = UIButton(type: .system)
        panelButton.translatesAutoresizingMaskIntoConstraints = false
        panelButton.setImage(UIImage(systemName: "gearshape"), for: .normal)
        panelButton.tintColor = .white
        panelButton.addTarget(self, action: #selector(showServerPanel), for: .touchUpInside)
        panelButton.accessibilityLabel = "Server panel"
        topBar.addSubview(panelButton)

        webView = makeWebView()
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 52),

            qrButton.trailingAnchor.constraint(equalTo: panelButton.leadingAnchor, constant: -14),
            qrButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            qrButton.widthAnchor.constraint(equalToConstant: 34),
            qrButton.heightAnchor.constraint(equalToConstant: 34),

            panelButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -14),
            panelButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            panelButton.widthAnchor.constraint(equalToConstant: 30),
            panelButton.heightAnchor.constraint(equalToConstant: 30),

            infoLabel.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 14),
            infoLabel.trailingAnchor.constraint(equalTo: qrButton.leadingAnchor, constant: -10),
            infoLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            webView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        updateInfoLabel()
    }

    private func updateInfoLabel() {
        infoLabel.text = "\(hostIP):\(port)/\(shortCode)"
    }

    // MARK: - WebView

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let contentController = WKUserContentController()
        contentController.addScriptMessageHandler(bridge, contentWorld: .page, name: "airchat")
        configuration.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = self
        webView.uiDelegate = self
        return webView
    }

    private func setupWebView() {
        // Same entry point Android uses.
        webView.load(URLRequest(url: URL(string: "http://127.0.0.1:\(port)/#\(roomKey)")!))
    }

    private func callJS(_ script: String) {
        DispatchQueue.main.async { [weak self] in
            self?.webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    /// Safely encodes a Swift string as a JS string literal (via JSON quoting).
    static func jsString(_ s: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [s]),
           let str = String(data: data, encoding: .utf8) {
            return String(str.dropFirst().dropLast())
        }
        return "\"\""
    }

    // MARK: - Server / mesh

    private func startServer() {
        let info = ServerInfo(hostIP: hostIP, port: port, roomKey: roomKey, shortCode: shortCode,
                              isHotspotActive: isHotspotActive)
        guard let webRoot = Bundle.main.resourceURL?.appendingPathComponent("www") else {
            showToast("Could not locate the web assets bundle.")
            return
        }
        server = LocalServer(info: info, webRootURL: webRoot)
        server.delegate = self
        do {
            try server.start()
        } catch {
            showToast("Server error: \(error.localizedDescription)")
        }
    }

    private func startMesh() {
        meshManager = MeshManager(
            name: "Node-\(UIDevice.current.model)",
            base64RoomKey: roomKey,
            onMessage: { [weak self] json in self?.server.broadcast(json) },
            onDeviceLost: { [weak self] in self?.showToast("Deconectat!") },
            onPeerFound: { [weak self] id, name in
                guard let self = self else { return }
                self.callJS("if (typeof startPulsing === 'function') startPulsing();")
                let alert = UIAlertController(title: "AirChat Detectat",
                                              message: "Găsit Mesh '\(name)'. Conectare?",
                                              preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Conectare", style: .default) { _ in
                    self.meshManager.connect(toPeer: id)
                    self.callJS("if (typeof stopPulsing === 'function') stopPulsing();")
                })
                alert.addAction(UIAlertAction(title: "Nu", style: .cancel) { _ in
                    self.callJS("if (typeof stopPulsing === 'function') stopPulsing();")
                })
                self.present(alert, animated: true)
            }
        )
        meshManager.start()
    }

    // MARK: - Bonjour (advertise + browse)

    func startBonjourAdvertising() {
        guard bonjourEnabled else { return }
        let service = NetService(domain: "local.", type: "_airchat-http._tcp",
                                 name: "AirChat-\(shortCode)", port: Int32(port))
        let txtRecord: [String: Data] = [
            "code": shortCode.data(using: .utf8) ?? Data(),
            "port": String(port).data(using: .utf8) ?? Data(),
            "v": "1".data(using: .utf8) ?? Data()
        ]
        service.setTXTRecord(NetService.data(fromTXTRecord: txtRecord))
        service.delegate = self
        service.publish()
        netService = service
    }

    func stopBonjourAdvertising() {
        netService?.stop()
        netService = nil
    }

    private func startBonjourBrowsing() {
        let browser = NetServiceBrowser()
        browser.delegate = self
        browser.searchForServices(ofType: "_airchat-http._tcp", inDomain: "local.")
        netServiceBrowser = browser
    }

    private func handleResolvedService(_ service: NetService) {
        guard let host = ipAddress(from: service) else { return }
        guard let txtData = service.txtRecordData() else { return }
        let txt = NetService.dictionary(fromTXTRecord: txtData)
        let code = txt["code"].flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let room = NearbyRoom(name: service.name, host: host, port: Int(service.port), code: code)
        if !nearbyRooms.contains(where: { $0.host == host && $0.port == room.port }) {
            nearbyRooms.append(room)
        }
        if let panel = presentedViewController as? ServerPanelViewController {
            panel.reloadRooms()
        }
    }

    private func ipAddress(from service: NetService) -> String? {
        guard let addresses = service.addresses else { return nil }
        for data in addresses {
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            data.withUnsafeBytes { raw in
                guard let ptr = raw.baseAddress?.assumingMemoryBound(to: sockaddr.self) else { return }
                _ = getnameinfo(ptr, socklen_t(raw.count), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            }
            let ip = String(cString: hostname)
            if ip.contains(".") { return ip } // prefer IPv4
        }
        return nil
    }

    // MARK: - Native capabilities (bridge actions)

    func batteryLevel() -> Int {
        return cachedBattery
    }

    func applyNativeTheme(_ theme: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let light = theme == "light"
            let bg: UIColor = light ? .white : .black
            let fg: UIColor = light ? .black : .white
            self.overrideUserInterfaceStyle = light ? .light : .dark
            self.view.backgroundColor = bg
            self.topBar.backgroundColor = bg
            self.infoLabel.textColor = fg
            self.qrButton.tintColor = fg
            self.panelButton.tintColor = fg
            self.setNeedsStatusBarAppearanceUpdate()
        }
    }

    func triggerBuzz() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        guard let engine = hapticEngine else { return }
        do {
            try engine.start()
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            try engine.makePlayer(with: pattern).start(atTime: 0)
        } catch {}
    }

    func pickImage() {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    // MARK: - Recording

    func startRecording(completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted: completion(beginRecording())
            case .denied: completion(false)
            case .undetermined:
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async { completion(granted ? self.beginRecording() : false) }
                }
            @unknown default: completion(false)
            }
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted: completion(beginRecording())
            case .denied: completion(false)
            case .undetermined:
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    DispatchQueue.main.async { completion(granted ? self.beginRecording() : false) }
                }
            @unknown default: completion(false)
            }
        }
    }

    private func beginRecording() -> Bool {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("airchat-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        guard let rec = try? AVAudioRecorder(url: url, settings: settings) else { return false }
        rec.record()
        recorder = rec
        recordingURL = url
        return true
    }

    func stopRecording() {
        guard let recorder = recorder else { return }
        let url = recordingURL
        recorder.stop()
        self.recorder = nil
        self.recordingURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        if let url = url, let data = try? Data(contentsOf: url) {
            let dataUrl = "data:audio/m4a;base64," + data.base64EncodedString()
            callJS("__onNativeAudio(\(Self.jsString(dataUrl)))")
            try? FileManager.default.removeItem(at: url)
        }
    }

    func cancelRecording() {
        guard let recorder = recorder else { return }
        let url = recordingURL
        recorder.stop()
        self.recorder = nil
        self.recordingURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if let url = url { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - Sensors (location + compass + battery)

    private func setupLocation() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        UIDevice.current.isBatteryMonitoringEnabled = true
        cachedBattery = max(1, Int(UIDevice.current.batteryLevel * 100))
        NotificationCenter.default.addObserver(self, selector: #selector(batteryDidChange),
                                               name: UIDevice.batteryLevelDidChangeNotification, object: nil)
    }

    @objc private func batteryDidChange() {
        let level = Int(UIDevice.current.batteryLevel * 100)
        cachedBattery = max(1, level)
    }

    // MARK: - Haptics

    private func setupHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        hapticEngine = try? CHHapticEngine()
        try? hapticEngine?.start()
        hapticEngine?.resetHandler = { [weak self] in try? self?.hapticEngine?.start() }
    }

    // MARK: - QR code

    private func qrImage(from string: String, size: CGFloat) -> UIImage? {
        guard let data = string.data(using: .ascii),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    private func qrThumbnail() -> UIImage? {
        return qrImage(from: inviteURL(), size: 120)?.withRenderingMode(.alwaysOriginal)
    }

    func inviteURL() -> String {
        "http://\(hostIP):\(port)/#\(roomKey)"
    }

    @objc private func showLargeQR() {
        let vc = UIViewController()
        vc.modalPresentationStyle = .pageSheet
        let imageView = UIImageView(image: qrImage(from: inviteURL(), size: 320))
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .white
        imageView.translatesAutoresizingMaskIntoConstraints = false
        vc.view.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: vc.view.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 340),
            imageView.heightAnchor.constraint(equalToConstant: 340),
        ])
        present(vc, animated: true)
    }

    @objc private func copyInviteLink() {
        UIPasteboard.general.string = inviteURL()
        showToast("Invite link copied")
    }

    // MARK: - Server panel

    @objc private func showServerPanel() {
        let panel = ServerPanelViewController(host: self)
        present(panel, animated: true)
    }

    // MARK: - Deep link

    @objc private func handleJoinRoom(_ notification: Notification) {
        guard let info = notification.userInfo,
              let host = info["host"] as? String,
              let port = info["port"] as? Int,
              let code = info["code"] as? String else { return }
        webView.load(URLRequest(url: URL(string: "http://\(host):\(port)/\(code)")!))
    }

    // MARK: - Toast

    private func showToast(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { alert.dismiss(animated: true) }
    }

    // MARK: - IP helpers (mirror Android's getSmartIpAddress)

    static func currentLocalIP() -> String {
        var best: String? = nil
        var wifiIP: String? = nil
        var hotspotIP: String? = nil

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return "192.168.43.1" }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let interface = ptr?.pointee else { continue }
            let name = String(cString: interface.ifa_name).lowercased()
            let flags = Int32(interface.ifa_flags)
            let addr = interface.ifa_addr.pointee
            guard addr.sa_family == UInt8(AF_INET), (flags & IFF_UP) != 0 else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(interface.ifa_addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count),
                        nil, 0, NI_NUMERICHOST)
            let ip = String(cString: hostname)
            if ip == "127.0.0.1" { continue }

            if name.contains("bridge100") || name.contains("ap") {
                hotspotIP = ip
            } else if name.contains("en0") || name.contains("wlan") {
                wifiIP = ip
            }
            if best == nil { best = ip }
        }
        return hotspotIP ?? wifiIP ?? best ?? "192.168.43.1"
    }

    static func isHotspotActive() -> Bool {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return false }
        defer { freeifaddrs(ifaddr) }
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            if let name = ptr?.pointee.ifa_name, String(cString: name).contains("bridge100") {
                return true
            }
        }
        return false
    }
}

// MARK: - LocalServerDelegate

extension ViewController: LocalServerDelegate {
    func server(_ server: LocalServer, didReceiveMessage json: String) {
        meshManager?.sendMessage(json)
        if json.contains("\"type\":\"buzz\"") {
            triggerBuzz()
        }
    }

    func serverDidLoseLastClient(_ server: LocalServer) {
        showToast("Deconectat!")
    }
}

// MARK: - CLLocationManagerDelegate

extension ViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        callJS("if (typeof updateMyLocation === 'function') updateMyLocation(\(loc.coordinate.latitude), \(loc.coordinate.longitude))")
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        var azimuth = newHeading.trueHeading
        if azimuth < 0 { azimuth = newHeading.magneticHeading }
        if azimuth < 0 { return }
        callJS("if (typeof updateMyHeading === 'function') updateMyHeading(\(azimuth))")
    }
}

// MARK: - PHPickerViewControllerDelegate

extension ViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider,
              provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let self = self, let image = object as? UIImage else { return }
            let resized = self.resizeImage(image, maxDimension: 800)
            let dataUrl = resized.jpegData(compressionQuality: 0.7).map { "data:image/jpeg;base64," + $0.base64EncodedString() }
            DispatchQueue.main.async {
                if let dataUrl = dataUrl {
                    self.callJS("__onNativeImage(\(Self.jsString(dataUrl)))")
                }
            }
        }
    }

    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let width = image.size.width
        let height = image.size.height
        guard max(width, height) > maxDimension else { return image }
        let scale = maxDimension / max(width, height)
        let newSize = CGSize(width: width * scale, height: height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}

// MARK: - WKNavigationDelegate / WKUIDelegate

extension ViewController: WKNavigationDelegate, WKUIDelegate {}

// MARK: - NetServiceDelegate (advertise)

extension ViewController: NetServiceDelegate {
    func netServiceDidPublish(_ sender: NetService) {}
    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        NSLog("Bonjour publish failed: %@", errorDict)
    }
}

// MARK: - NetServiceBrowserDelegate + resolution

extension ViewController: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        service.resolve(withTimeout: 5)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        nearbyRooms.removeAll { $0.name == service.name }
    }
}

extension ViewController {
    func netServiceDidResolveAddress(_ sender: NetService) {
        handleResolvedService(sender)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {}
}

// MARK: - Server panel (presented sheet)

extension ViewController {

    final class ServerPanelViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

        private weak var host: ViewController?
        private let tableView = UITableView(frame: .zero, style: .insetGrouped)
        private let backgroundSwitch = UISwitch()
        private let bonjourSwitch = UISwitch()

        init(host: ViewController) {
            self.host = host
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidLoad() {
            super.viewDidLoad()
            title = "AirChat Server"
            view.backgroundColor = .systemBackground

            tableView.dataSource = self
            tableView.delegate = self
            tableView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(tableView)
            NSLayoutConstraint.activate([
                tableView.topAnchor.constraint(equalTo: view.topAnchor),
                tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])

            backgroundSwitch.isOn = host?.keepAlive.isEnabled ?? false
            backgroundSwitch.addTarget(self, action: #selector(toggleBackground), for: .valueChanged)
            bonjourSwitch.isOn = host?.bonjourEnabled ?? true
            bonjourSwitch.addTarget(self, action: #selector(toggleBonjour), for: .valueChanged)
        }

        func reloadRooms() {
            tableView.reloadData()
        }

        @objc private func toggleBackground(_ sender: UISwitch) {
            if sender.isOn { host?.keepAlive.start() } else { host?.keepAlive.stop() }
        }

        @objc private func toggleBonjour(_ sender: UISwitch) {
            guard let host = host else { return }
            host.bonjourEnabled = sender.isOn
            if sender.isOn { host.startBonjourAdvertising() } else { host.stopBonjourAdvertising() }
        }

        func numberOfSections(in tableView: UITableView) -> Int { 3 }

        func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
            switch section {
            case 0: return "Status"
            case 1: return "Background"
            case 2: return "Nearby rooms (Bonjour)"
            default: return nil
            }
        }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            switch section {
            case 0: return 3
            case 1: return 2
            case 2: return max(host?.nearbyRooms.count ?? 0, 1)
            default: return 0
            }
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            guard let host = host else { return cell }
            switch indexPath.section {
            case 0:
                if indexPath.row == 0 {
                    cell.textLabel?.text = host.inviteURL()
                    cell.detailTextLabel?.text = "Invite link (tap to copy)"
                } else if indexPath.row == 1 {
                    cell.textLabel?.text = "Short code: \(host.shortCode) · clients: \(host.server.clientCount)"
                    cell.detailTextLabel?.text = "Platform iOS · up \(host.server.uptimeSeconds)s"
                } else {
                    cell.textLabel?.text = host.isHotspotActive ? "Personal Hotspot: ON" : "Personal Hotspot: OFF"
                    cell.detailTextLabel?.text = "Guests must join your Wi-Fi hotspot"
                }
            case 1:
                if indexPath.row == 0 {
                    cell.textLabel?.text = "Keep serving when locked"
                    cell.detailTextLabel?.text = "Uses a silent audio session; drains battery"
                    cell.accessoryView = backgroundSwitch
                    cell.selectionStyle = .none
                } else {
                    cell.textLabel?.text = "Advertise via Bonjour"
                    cell.detailTextLabel?.text = "Lets nearby iPhones find this room"
                    cell.accessoryView = bonjourSwitch
                    cell.selectionStyle = .none
                }
            case 2:
                if host.nearbyRooms.isEmpty {
                    cell.textLabel?.text = "No rooms found"
                    cell.detailTextLabel?.text = "Make sure the other iPhone has AirChat open"
                    cell.accessoryView = nil
                    cell.selectionStyle = .none
                } else {
                    let room = host.nearbyRooms[indexPath.row]
                    cell.textLabel?.text = room.name
                    cell.detailTextLabel?.text = room.inviteURL
                    cell.accessoryView = nil
                    cell.selectionStyle = .default
                }
            default: break
            }
            return cell
        }

        func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            tableView.deselectRow(at: indexPath, animated: true)
            guard let host = host else { return }
            if indexPath.section == 0, indexPath.row == 0 {
                UIPasteboard.general.string = host.inviteURL()
            } else if indexPath.section == 2, !host.nearbyRooms.isEmpty {
                let room = host.nearbyRooms[indexPath.row]
                host.webView.load(URLRequest(url: URL(string: room.inviteURL)!))
                dismiss(animated: true)
            }
        }
    }
}
