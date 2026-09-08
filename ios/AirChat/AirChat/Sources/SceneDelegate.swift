//
//  SceneDelegate.swift
//  AirChat
//

import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private var didActivateRuntime = false

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        let root = HomeViewController()
        let nav = UINavigationController(rootViewController: root)
        nav.setNavigationBarHidden(true, animated: false)
        nav.modalPresentationStyle = .fullScreen
        window.rootViewController = nav
        window.overrideUserInterfaceStyle = .automatic
        window.tintColor = UIColor(red: 0/255, green: 132/255, blue: 255/255, alpha: 1)   // #0084ff, the app's accent
        self.window = window
        window.makeKeyAndVisible()

        // airchat://join?host=… opened the app from a QR scan or the install guide.
        if let context = connectionOptions.urlContexts.first {
            AppRuntime.shared.handleDeepLink(context.url)
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        if !didActivateRuntime {
            didActivateRuntime = true
            AppRuntime.shared.activate()
        } else {
            AppRuntime.shared.location.start()
        }
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Stop pushing sensor data to a WebView that is not on screen; iOS also uses
        // this moment to decide whether to suspend us.
        AppRuntime.shared.location.stop()
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        AppRuntime.shared.handleDeepLink(url)
    }

    func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
        nil
    }
}
