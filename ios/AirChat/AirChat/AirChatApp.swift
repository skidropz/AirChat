//
//  AirChatApp.swift
//  AirChat
//
//  Entry point. AirChat adopts the SwiftUI App life cycle (the modern, SDK-mandated
//  lifecycle — which also guarantees the SwiftUI AppGraph exists). The actual UI is still
//  the UIKit ViewController, hosted edge-to-edge via UIViewControllerRepresentable, so the
//  chat server, mesh, WebView shell and all native hardware stay exactly where they are.
//

import SwiftUI

@main
struct AirChatApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            AirChatViewController()
                .ignoresSafeArea()
        }
    }
}

/// Bridges the UIKit ViewController into the SwiftUI App lifecycle.
private struct AirChatViewController: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ViewController {
        ViewController()
    }

    func updateUIViewController(_ uiViewController: ViewController, context: Context) {}
}
