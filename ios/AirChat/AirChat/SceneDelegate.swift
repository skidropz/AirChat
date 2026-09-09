//
//  SceneDelegate.swift
//  AirChat
//
//  Owns the window and root view controller under the UIScene life cycle, and forwards the
//  `airchat://join?host=…&port=…&code=…` deep link so an iPhone can hop into a nearby room
//  from a link or the install page, without typing an IP address.
//

import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = ViewController()
        window.makeKeyAndVisible()
        self.window = window

        // A deep link that launched the app from cold start.
        if let urlContext = connectionOptions.urlContexts.first {
            handle(url: urlContext.url)
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let urlContext = URLContexts.first else { return }
        handle(url: urlContext.url)
    }

    private func handle(url: URL) {
        guard url.scheme == "airchat",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else { return }
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
        guard let host = host, let port = port else { return }
        NotificationCenter.default.post(name: .airchatJoinRoom, object: nil,
                                        userInfo: ["host": host, "port": port, "code": code ?? ""])
    }
}
