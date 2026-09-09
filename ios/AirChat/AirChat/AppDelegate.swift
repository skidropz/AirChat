//
//  AppDelegate.swift
//  AirChat
//
//  Application delegate, wired into the SwiftUI App lifecycle via @UIApplicationDelegateAdaptor.
//  It owns only app-level concerns: forwarding the `airchat://join?host=…&port=…&code=…` deep
//  link so an iPhone can hop into a nearby room from a link or the install page.
//

import UIKit

extension Notification.Name {
    static let airchatJoinRoom = Notification.Name("airchatJoinRoom")
}

final class AppDelegate: NSObject, UIApplicationDelegate {

    /// A join link that arrived before the chat view was ready to receive it.
    static var pendingJoinURL: URL?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Cold start via a URL.
        if let url = launchOptions?[.url] as? URL {
            Self.handle(url: url)
        }
        return true
    }

    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        Self.handle(url: url)
        return true
    }

    // MARK: - Deep link parsing

    /// Parses an `airchat://join…` URL into a host/port/code payload, or nil if it isn't one.
    static func joinInfo(from url: URL) -> [String: Any]? {
        guard url.scheme == "airchat",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else { return nil }
        var host = url.host
        var port: Int?
        var code: String?
        for item in queryItems {
            switch item.name {
            case "host": host = item.value
            case "port": port = item.value.flatMap { Int($0) }
            case "code": code = item.value
            default: break
            }
        }
        guard let host = host, let port = port else { return nil }
        return ["host": host, "port": port, "code": code ?? ""]
    }

    /// Forwards the join link to the chat view, stashing it if the view isn't ready yet.
    static func handle(url: URL) {
        guard let info = joinInfo(from: url) else { return }
        pendingJoinURL = url
        NotificationCenter.default.post(name: .airchatJoinRoom, object: nil, userInfo: info)
    }
}
