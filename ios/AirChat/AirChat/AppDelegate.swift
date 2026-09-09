//
//  AppDelegate.swift
//  AirChat
//
//  Minimal app lifecycle (no scene manifest → classic UIApplicationDelegate). Handles the
//  `airchat://join?host=…&port=…&code=…` deep link so an iPhone can hop into a nearby room
//  from a link or the install page, without typing an IP address.
//

import UIKit

extension Notification.Name {
    static let airchatJoinRoom = Notification.Name("airchatJoinRoom")
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let viewController = ViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        guard url.scheme == "airchat",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else { return false }
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
        guard let host = host, let port = port else { return false }
        NotificationCenter.default.post(name: .airchatJoinRoom, object: nil,
                                        userInfo: ["host": host, "port": port, "code": code ?? ""])
        return true
    }
}
