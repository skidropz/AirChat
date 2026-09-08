//
//  AppDelegate.swift
//  AirChat
//

import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Haptics.prepare()
        // Battery percentage for everyone in the room (Android reads it from
        // BatteryManager through the JS bridge; here the bridge reads UIDevice).
        UIDevice.current.isBatteryMonitoringEnabled = true
        application.beginReceivingRemoteControlEvents()
        return true
    }

    // MARK: - UISceneSessionLifecycle

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default Configuration",
                                                  sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    // Legacy (non-scene) entry point kept so the deep link works if scenes are ever off.
    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        AppRuntime.shared.handleDeepLink(url)
    }

    /// Sideloading tools sometimes terminate the app instead of backgrounding it; flush
    /// the room state so the key/code survive.
    func applicationWillTerminate(_ application: UIApplication) {
        AppRuntime.shared.stopHosting()
    }
}
