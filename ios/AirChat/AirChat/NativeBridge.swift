//
//  NativeBridge.swift
//  AirChat
//
//  WKScriptMessageHandlerWithReply for the `airchat` message handler. The shared web bundle
//  (`airchat-bridge.js`) detects `window.webkit.messageHandlers.airchat`, rebuilds
//  `window.AndroidInterface` (battery + theme) on top of it and exposes `window.AirChatNative`
//  as the transport for mic recording, photo picking and haptics — the three things WKWebView
//  refuses to do for a plain http:// origin.
//

import WebKit
import Foundation

final class NativeBridge: NSObject, WKScriptMessageHandlerWithReply {

    weak var viewController: ViewController?

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String,
              let vc = viewController else {
            replyHandler(nil, nil)
            return
        }

        switch action {
        case "battery":
            replyHandler(vc.batteryLevel(), nil)

        case "theme":
            vc.applyNativeTheme(body["value"] as? String ?? "dark")
            replyHandler(nil, nil)

        case "buzz":
            vc.triggerBuzz()
            replyHandler(nil, nil)

        case "pickImage":
            vc.pickImage()
            replyHandler(nil, nil)

        case "recordingStart":
            // The reply is async: microphone permission may still be pending on first use.
            vc.startRecording { ok in replyHandler(ok ? true : NSNull(), nil) }

        case "recordingStop":
            vc.stopRecording()
            replyHandler(nil, nil)

        case "recordingCancel":
            vc.cancelRecording()
            replyHandler(nil, nil)

        default:
            replyHandler(nil, nil)
        }
    }
}
