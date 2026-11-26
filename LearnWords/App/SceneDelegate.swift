//
//  SceneDelegate.swift
//  LearnWords
//
//  Adopts the UIScene life cycle. Owns the window and the app's root view
//  controller — the app's composition root, per the uikit-app-structure skill.
//

import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.tintColor = .orange
        window.rootViewController = AppRoot.makeRoot()
        self.window = window
        window.makeKeyAndVisible()

        // A scene may be created already carrying a URL to open (cold launch).
        if let url = connectionOptions.urlContexts.first?.url {
            AppRoot.handle(url, on: window)
        }

        // A cold launch from a tapped reminder arrives here, not reliably through
        // `AppDelegate`'s `didReceive` — which can fire before this window is key.
        // `AppRoot` routes the response once; the `didReceive` copy is then a no-op.
        if let response = connectionOptions.notificationResponse {
            AppRoot.handle(response, on: window)
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        AppRoot.handle(url, on: window)
    }
}
