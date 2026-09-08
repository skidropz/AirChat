//
//  HomeViewController.swift
//  AirChat
//
//  iOS equivalent of activity_main.xml + MainActivity's WebView plumbing: a thin
//  native bar (join address + QR + server panel) with the chat UI underneath, served
//  from the app's own HTTP server so the host and the visitors render the exact same
//  page. That is the whole point of the architecture: one code path for everyone.
//

import SwiftUI
import UIKit
import WebKit

final class HomeViewController: UIViewController {

    // MARK: - Views

    private var webView: WKWebView!
    private var bridge: AirChatBridge!

    private let bar = UIView()
    private let statusDot = UIView()
    private let addressLabel = UILabel()
    private let qrButton = UIButton(type: .system)
    private let panelButton = UIButton(type: .system)
    private let banner = UILabel()

    private var webViewBottom: NSLayoutConstraint!
    private var barHeight: NSLayoutConstraint!
    private var bannerHeight: NSLayoutConstraint!
    private var bannerTap: UITapGestureRecognizer?

    private var isLightChrome = false
    private var pendingPeerAlert: MeshPeer?
    private var presentedRemoteURL: URL?
    private lazy var model = RuntimeModel()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        AppRuntime.shared.observer = self
        buildBar()
        buildWebView()
        buildBanner()
        wireNotifications()

        // The room must be serving before the WebView asks for index.html, otherwise
        // the first load fails on a cold start (Android has the same ordering, done
        // synchronously).
        if !AppRuntime.shared.isHosting { AppRuntime.shared.startHosting() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.loadRoom()
            self?.checkLocalNetworkAccess()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override var prefersStatusBarHidden: Bool { false }
    override var preferredStatusBarStyle: UIStatusBarStyle { isLightChrome ? .darkContent : .lightContent }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Construction

    private func buildBar() {
        bar.backgroundColor = .black
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)

        statusDot.backgroundColor = UIColor.systemRed
        statusDot.layer.cornerRadius = 4
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(statusDot)

        addressLabel.numberOfLines = 2
        addressLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        addressLabel.textColor = .white
        addressLabel.lineBreakMode = .byTruncatingMiddle
        addressLabel.adjustsFontSizeToFitWidth = true
        addressLabel.minimumScaleFactor = 0.7
        addressLabel.isUserInteractionEnabled = true
        addressLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(copyAddress)))
        addressLabel.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(addressLabel)

        qrButton.setImage(UIImage(systemName: "qrcode.viewfinder"), for: .normal)
        qrButton.tintColor = .white
        qrButton.addTarget(self, action: #selector(showQR), for: .touchUpInside)
        qrButton.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(qrButton)

        panelButton.setImage(UIImage(systemName: "dot.radiowaves.left.and.right"), for: .normal)
        panelButton.tintColor = .white
        panelButton.addTarget(self, action: #selector(showPanel), for: .touchUpInside)
        panelButton.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(panelButton)

        barHeight = bar.heightAnchor.constraint(equalToConstant: 52)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            barHeight!,

            statusDot.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14),
            statusDot.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8),

            addressLabel.leadingAnchor.constraint(equalTo: statusDot.trailingAnchor, constant: 8),
            addressLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            panelButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -10),
            panelButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            panelButton.widthAnchor.constraint(equalToConstant: 40),
            panelButton.heightAnchor.constraint(equalToConstant: 40),

            qrButton.trailingAnchor.constraint(equalTo: panelButton.leadingAnchor, constant: -2),
            qrButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            qrButton.widthAnchor.constraint(equalToConstant: 40),
            qrButton.heightAnchor.constraint(equalToConstant: 40),

            addressLabel.trailingAnchor.constraint(lessThanOrEqualTo: qrButton.leadingAnchor, constant: -8)
        ])
    }

    private func buildWebView() {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()

        let bridge = AirChatBridge(host: self)
        controller.addScriptMessageHandler(bridge, contentWorld: .page, name: AirChatBridge.handlerName)
        controller.addUserScript(WKUserScript(source: AirChatBridge.bootstrapScript,
                                               injectionTime: .atDocumentStart,
                                               forMainFrameOnly: false))
        configuration.userContentController = controller
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        self.bridge = bridge
        bridge.attach(webView: webView)

        webView.navigationDelegate = bridge
        webView.uiDelegate = bridge
        webView.isOpaque = true
        webView.backgroundColor = .black
        webView.underPageBackgroundColor = .black
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        webView.scrollView.backgroundColor = .black
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.keyboardDismissMode = .interactive
        webView.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 16.4, *) {
            webView.isInspectable = true                 // debug builds only, harmless
        }
        view.addSubview(webView)
        self.webView = webView

        webViewBottom = webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: bar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webViewBottom!
        ])
    }

    private func buildBanner() {
        banner.numberOfLines = 0
        banner.font = .systemFont(ofSize: 12, weight: .medium)
        banner.textColor = .white
        banner.backgroundColor = UIColor.systemOrange
        banner.textAlignment = .center
        banner.isHidden = true
        banner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(banner)
        bannerHeight = banner.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: bar.bottomAnchor),
            banner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bannerHeight!
        ])
        let tap = UITapGestureRecognizer(target: self, action: #selector(bannerTapped))
        banner.addGestureRecognizer(tap)
        banner.isUserInteractionEnabled = true
        bannerTap = tap
    }

    private func wireNotifications() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(keyboardChanged(_:)),
                           name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        center.addObserver(self, selector: #selector(keyboardChanged(_:)),
                           name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
        center.addObserver(self, selector: #selector(joinRequested(_:)),
                           name: .airChatJoinRequested, object: nil)
        center.addObserver(self, selector: #selector(refreshBar),
                           name: .airChatStateChanged, object: nil)
    }

    // MARK: - Room loading

    private func loadRoom() {
        guard let url = localRoomURL else { return }
        presentedRemoteURL = nil
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        refreshBar()
    }

    /// The host renders the very page its guests get, but over loopback so the chat
    /// keeps working even with no interface up at all (identical trick to Android's
    /// `http://127.0.0.1:8080/#key`).
    private var localRoomURL: URL? {
        let runtime = AppRuntime.shared
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(runtime.port)
        components.path = "/"
        components.fragment = runtime.room.keyBase64URL
        return components.url
    }

    @objc private func joinRequested(_ note: Notification) {
        guard let url = note.object as? URL else { return }
        presentedRemoteURL = url
        webView.load(URLRequest(url: url))
        show(bannerText: "Joined \(url.host ?? "remote host") — this phone is now a client. Tap to go back.",
             color: .systemBlue, autoHide: 4.0)
    }

    @objc private func refreshBar() {
        let runtime = AppRuntime.shared
        model.reload()
        let serving = runtime.isServing
        statusDot.backgroundColor = serving ? UIColor.systemGreen : UIColor.systemRed
        if let remote = presentedRemoteURL {
            addressLabel.text = "Client of \(remote.host ?? "")"
        } else {
            addressLabel.text = "\(runtime.currentHostIP):\(runtime.port)/\(runtime.room.shortCode)\n"
                + "\(runtime.clientCount) client(s) · \(runtime.meshPeers.count) mesh"
        }
    }

    // MARK: - Banner

    private func show(bannerText: String, color: UIColor, autoHide: TimeInterval?) {
        banner.text = "  " + bannerText + "  "
        banner.backgroundColor = color
        banner.isHidden = false
        // Measure the label at the real width, otherwise a wrapped message gets clipped.
        let width = max(1, view.bounds.width - 8)
        let measured = banner.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        bannerHeight.constant = ceil(measured) + 14
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
        if let autoHide = autoHide {
            DispatchQueue.main.asyncAfter(deadline: .now() + autoHide) { [weak self] in
                self?.hideBanner()
            }
        }
    }

    private func hideBanner() {
        banner.isHidden = true
        bannerHeight.constant = 0
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }

    @objc private func bannerTapped() {
        if let action = bannerAction {
            bannerAction = nil
            action()
            if presentedRemoteURL == nil { hideBanner() }
            return
        }
        if presentedRemoteURL != nil {
            presentedRemoteURL = nil
            loadRoom()
        }
        hideBanner()
    }

    /// iOS 14+ requires an explicit user grant for "Local Network". Without it,
    /// Network.framework accepts loopback connections only, which looks exactly like a
    /// broken app from the user's side — so we detect it and explain it.
    private func checkLocalNetworkAccess() {
        let runtime = AppRuntime.shared
        guard !runtime.isServing else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, !runtime.isServing else { return }
            self.show(bannerText: "Waiting for the “Local Network” permission — allow it so other devices can reach this iPhone. Tap to open Settings.",
                      color: .systemRed, autoHide: nil)
            self.bannerAction = {
                if let settings = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settings)
                }
            }
        }
    }

    private var bannerAction: (() -> Void)?

    // MARK: - Actions

    @objc private func copyAddress() {
        UIPasteboard.general.string = AppRuntime.shared.browserAddress
        Haptics.success()
        show(bannerText: "Address copied: \(AppRuntime.shared.browserAddress)", color: .systemGreen, autoHide: 2.0)
    }

    @objc private func showQR() {
        let sheet = UIHostingControllerCompat.rootView(QRSheet(address: AppRuntime.shared.browserAddress),
                                                       in: self)
        present(sheet, animated: true)
    }

    @objc private func showPanel() {
        let panel = HostPanelView(model: model)
        let hosted = UIHostingControllerCompat.rootView(panel, in: self)
        hosted.modalPresentationStyle = .formSheet
        hosted.isModalInPopover = false
        present(hosted, animated: true)
    }

    // MARK: - Keyboard

    @objc private func keyboardChanged(_ note: Notification) {
        guard let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else { return }
        let endFrame = end.cgRectValue
        let overlap = max(0, view.bounds.height - endFrame.origin.y)
        let target = overlap > 1 ? -overlap : 0
        UIView.animate(withDuration: 0.25) {
            self.webViewBottom.constant = target
            self.view.layoutIfNeeded()
        }
        // app.js re-measures window.innerHeight on resize, which keeps the composer
        // above the keyboard exactly like Android's adjustResize.
        webView.evaluateJavaScript("window.dispatchEvent(new Event('resize'));", completionHandler: nil)
    }

    // MARK: - Theme handoff (JS → native chrome)

    func applyChromeTheme(_ theme: String) {
        let light = theme == "light"
        guard light != isLightChrome else { return }
        isLightChrome = light
        let background = light ? UIColor.white : UIColor.black
        let foreground = light ? UIColor.black : UIColor.white
        UIView.animate(withDuration: 0.25) {
            self.view.backgroundColor = background
            self.bar.backgroundColor = background
            self.webView.backgroundColor = background
            self.webView.scrollView.backgroundColor = background
            self.addressLabel.textColor = foreground
            self.qrButton.tintColor = foreground
            self.panelButton.tintColor = foreground
        }
        setNeedsStatusBarAppearanceUpdate()
    }

    func evaluate(_ javascript: String) {
        DispatchQueue.main.async { [weak self] in
            self?.webView.evaluateJavaScript(javascript, completionHandler: nil)
        }
    }

    func showLoadError(_ error: Error) {
        NSLog("AirChat: navigation failed \(error.localizedDescription)")
        guard !(error as NSError).code.isKnownCancellation else { return }
        show(bannerText: "Could not load the room: \(error.localizedDescription). Tap to retry.",
             color: .systemRed, autoHide: nil)
        bannerAction = { [weak self] in self?.webView.reloadFromOrigin() }
    }
}

private extension Int {
    var isKnownCancellation: Bool { self == -999 || self == NSURLErrorCancelled }
}

// MARK: - AppRuntimeObserver

extension HomeViewController: AppRuntimeObserver {
    func runtimeDidUpdateHeading(_ degrees: Double) {
        evaluate("if (typeof updateMyHeading === 'function') updateMyHeading(\(degrees));")
    }

    func runtimeDidUpdateLocation(latitude: Double, longitude: Double) {
        evaluate("if (typeof updateMyLocation === 'function') updateMyLocation(\(latitude), \(longitude));")
    }

    func runtimeDidFindMeshPeer(_ peer: MeshPeer) {
        evaluate("if (typeof startPulsing === 'function') startPulsing();")
        guard presentedViewController == nil, pendingPeerAlert == nil else { return }
        pendingPeerAlert = peer
        let alert = UIAlertController(
            title: Localization.t("MESH_FOUND_TITLE", "AirChat detected"),
            message: Localization.f("MESH_FOUND_BODY", "Found mesh node “%@”. Connect and let your phone relay messages for others?",
                                    [peer.displayName] as [CVarArg]),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Localization.t("CONNECT", "Connect"), style: .default) { [weak self] _ in
            guard let self = self, let peer = self.pendingPeerAlert else { return }
            AppRuntime.shared.connectMeshPeer(peer)
            self.pendingPeerAlert = nil
            self.evaluate("if (typeof stopPulsing === 'function') stopPulsing();")
        })
        alert.addAction(UIAlertAction(title: Localization.t("IGNORE", "Not now"), style: .cancel) { [weak self] _ in
            self?.pendingPeerAlert = nil
            self?.evaluate("if (typeof stopPulsing === 'function') stopPulsing();")
        })
        present(alert, animated: true)
    }

    func runtimeDidUpdateState() {
        refreshBar()
    }

    func runtimeDidFail(_ message: String) {
        show(bannerText: message, color: .systemRed, autoHide: 5.0)
    }
}

/// Small shim so the UIKit host can present SwiftUI without an `if #available`
/// everywhere (UIHostingController itself is iOS 13+, so this is mostly about a
/// consistent presentation style on iPhone).
enum UIHostingControllerCompat {
    static func rootView<V: View>(_ view: V, in presenter: UIViewController) -> UIViewController {
        let hosted = UIHostingController(rootView: view)
        hosted.modalPresentationStyle = .pageSheet
        if #available(iOS 16.0, *), let sheet = hosted.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        return hosted
    }
}
