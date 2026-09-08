//
//  AirChatBridge.swift
//  AirChat
//
//  The iOS twin of Android's `WebAppInterface` (JS bridge) +
//  `WebChromeClient` (mic grant, file chooser, geolocation grant).
//
//  One difference shapes the whole file: WKScriptMessageHandler cannot return a value
//  synchronously, so where Android does `var b = AndroidInterface.getBatteryLevel()`
//  iOS uses WKScriptMessageHandlerWithReply (iOS 14+) and the page awaits.
//  Everything the page can do natively (mic, photo picker, haptics, share, settings)
//  goes through here; see WebApp/airchat-bridge.js for the JavaScript half.
//

import Foundation
import Photos
import UIKit
import WebKit

final class AirChatBridge: NSObject {

    static let handlerName = "airchat"

    /// Injected before any page script runs, so app.js can feature-detect the host.
    static let bootstrapScript = """
    (function () {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.airchat) {
        window.AirChatHost = {
          platform: 'ios',
          appVersion: '\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.0")',
          canRecord: true, canPickImage: true, canHaptic: true, canBattery: true
        };
        window.__airchatCall = function (payload) {
          return window.webkit.messageHandlers.airchat.postMessage(payload);
        };
        // Callbacks the native side invokes with evaluateJavaScript.
        window.__onNativeAudio = function (dataUrl) {
          if (window.AirChatNative && window.AirChatNative.onAudio) window.AirChatNative.onAudio(dataUrl);
        };
        window.__onNativeImage = function (dataUrl) {
          if (window.AirChatNative && window.AirChatNative.onImage) window.AirChatNative.onImage(dataUrl);
        };
      } else {
        window.__airchatCall = null;
      }
    })();
    """

    weak var host: HomeViewController?
    let recorder = NativeRecorder()
    private let images = ImagePickerCoordinator()
    private weak var webView: WKWebView?

    init(host: HomeViewController) {
        self.host = host
        super.init()
    }

    /// The WebView is created after the bridge (it needs the bridge as its message
    /// handler), so it is attached in a second step.
    func attach(webView: WKWebView) {
        self.webView = webView
    }

    // MARK: - Outbound

    private func evaluate(_ expression: String) {
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(expression, completionHandler: nil)
        }
    }

    /// Safe JS string literal for arbitrary text (quotes, newlines, non-ASCII).
    static func jsString(_ value: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
           let text = String(data: data, encoding: .utf8) {
            // JSONSerialization emits `["..."]`; strip the brackets to get a literal.
            return String(text.dropFirst().dropLast())
        }
        return "\"\""
    }

    // MARK: - WKScriptMessageHandlerWithReply

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else {
            replyHandler(nil, "Expected a dictionary with an 'action' key")
            return
        }

        switch action {
        case "battery":
            replyHandler(Self.batteryLevel(), nil)

        case "powerInfo":
            replyHandler(Self.powerInfo(), nil)

        case "theme":
            let theme = (body["value"] as? String) ?? "dark"
            DispatchQueue.main.async { [weak self] in self?.host?.applyChromeTheme(theme) }
            replyHandler(true, nil)

        case "buzz":
            Haptics.buzz()
            replyHandler(true, nil)

        case "haptic":
            switch body["style"] as? String {
            case "success": Haptics.success()
            default: Haptics.tap()
            }
            replyHandler(true, nil)

        case "copy":
            if let text = body["text"] as? String {
                UIPasteboard.general.string = text
                replyHandler(true, nil)
            } else {
                replyHandler(nil, "nothing to copy")
            }

        case "share":
            share(text: body["text"] as? String, url: body["url"] as? String, reply: replyHandler)

        case "recordingStart":
            func begin() {
                do {
                    try recorder.start()
                    replyHandler(true, nil)
                } catch {
                    replyHandler(nil, (error as? NativeRecorder.RecorderError)?.errorDescription
                                    ?? error.localizedDescription)
                }
            }
            if NativeRecorder.permissionStatus {
                begin()
            } else {
                // First tap on the mic button: show the system prompt, then retry.
                NativeRecorder.requestPermission { granted in
                    guard granted else {
                        replyHandler(nil, Localization.t("MIC_DENIED", "Microphone access was denied."))
                        return
                    }
                    begin()
                }
            }

        case "recordingStop":
            if let dataUrl = recorder.stop() {
                replyHandler(true, nil)
                evaluate("window.__onNativeAudio && window.__onNativeAudio(\(Self.jsString(dataUrl)));")
            } else {
                replyHandler(false, nil)
            }

        case "recordingCancel":
            recorder.cancel()
            replyHandler(true, nil)

        case "recordingLevel":
            replyHandler(["recording": recorder.isRecording,
                          "duration": recorder.duration,
                          "db": recorder.averagePower], nil)

        case "pickImage":
            guard let host = host else { replyHandler(nil, "no presenter"); return }
            replyHandler(true, nil)             // the result arrives via __onNativeImage
            images.present(from: host) { [weak self] payload in
                guard let self = self, let payload = payload else { return }
                self.evaluate("window.__onNativeImage && window.__onNativeImage(\(Self.jsString(payload)));")
            }

        case "hostStatus":
            let runtime = AppRuntime.shared
            replyHandler([
                "ip": runtime.currentHostIP,
                "port": Int(runtime.port),
                "clients": runtime.clientCount,
                "code": runtime.room.shortCode,
                "serving": runtime.isServing,
                "hotspot": NetworkInfo.isPersonalHotspotUp,
                "meshPeers": runtime.meshPeers.map { $0.displayName },
                "meshEnabled": runtime.isMeshEnabled,
                "keepAlive": runtime.keepAliveEnabled,
                "uptime": runtime.uptimeText,
                "browserAddress": runtime.browserAddress
            ], nil)

        case "rotateRoom":
            AppRuntime.shared.rotateRoom()
            replyHandler(true, nil)

        case "restartServer":
            AppRuntime.shared.restartServer()
            replyHandler(true, nil)

        case "openHotspotSettings":
            // App-prefs: is the only way to reach the Personal Hotspot pane, because
            // iOS has no API to toggle tethering programmatically at all. Fine for a
            // sideloaded/TestFlight build; would never pass App Store review.
            open(URL(string: "App-prefs:WI-Fi&tethering"), reply: replyHandler)

        case "openSettings":
            open(URL(string: UIApplication.openSettingsURLString), reply: replyHandler)

        case "openURL":
            if let string = body["url"] as? String, let url = URL(string: string) {
                open(url, reply: replyHandler)
            } else {
                replyHandler(nil, "bad url")
            }

        case "reload":
            DispatchQueue.main.async { [weak self] in self?.webView?.reloadFromOrigin() }
            replyHandler(true, nil)

        default:
            replyHandler(nil, "unknown action '\(action)'")
        }
    }

    private func open(_ url: URL?, reply: @escaping (Any?, String?) -> Void) {
        guard let url = url else { reply(nil, "unavailable"); return }
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:]) { ok in
                reply(ok, ok ? nil : "could not open \(url.absoluteString)")
            }
        }
    }

    private func share(text: String?, url: String?, reply: @escaping (Any?, String?) -> Void) {
        guard let host = host else { reply(nil, "no presenter"); return }
        var items: [Any] = []
        if let text = text, !text.isEmpty { items.append(text) }
        if let url = url, let parsed = URL(string: url) { items.append(parsed) }
        if items.isEmpty { items.append(AppRuntime.shared.browserAddress) }
        DispatchQueue.main.async {
            let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
            sheet.popoverPresentationController?.sourceView = host.view
            sheet.popoverPresentationController?.sourceRect = CGRect(x: host.view.bounds.midX,
                                                                    y: host.view.bounds.minY,
                                                                    width: 1, height: 1)
            host.present(sheet, animated: true)
            reply(true, nil)
        }
    }

    // MARK: - Power

    private static func batteryLevel() -> Int {
        let device = UIDevice.current
        if !device.isBatteryMonitoringEnabled { device.isBatteryMonitoringEnabled = true }
        let level = device.batteryLevel
        if level < 0 { return 0 }               // simulator / monitoring off
        return Int((level * 100).rounded())
    }

    private static func powerInfo() -> [String: Any] {
        let device = UIDevice.current
        if !device.isBatteryMonitoringEnabled { device.isBatteryMonitoringEnabled = true }
        return [
            "level": batteryLevel(),
            "state": device.batteryState.rawValue,
            "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled
        ]
    }
}

// MARK: - WebKit delegates

extension AirChatBridge: WKNavigationDelegate, WKUIDelegate {

    /// Let the page's own getUserMedia() work for our local origins. Android grants
    /// RESOURCE_AUDIO_CAPTURE in WebChromeClient.onPermissionRequest; this is the
    /// iOS 15+ equivalent, and the reason voice notes also work for pages that are
    /// *not* using the native recorder.
    @available(iOS 15.0, *)
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let allowed = ["127.0.0.1", "localhost", "::1"]
            .contains(origin.host.lowercased())
            || AppRuntime.shared.currentHostIP == origin.host
        decisionHandler(allowed ? .grant : .prompt)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.allow); return }

        switch url.scheme?.lowercased() {
        case "http", "https", "file", "about", "data", nil:
            decisionHandler(.allow)
        default:
            // airchat://, mailto:, tel:, itms-apps:… leave the app instead of
            // replacing the chat page inside our own WebView.
            decisionHandler(.cancel)
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        host?.showLoadError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        host?.showLoadError(error)
    }
}
