//
//  SceneDelegate.swift
//  LearnWords
//
//  Adopts the UIScene life cycle (iOS 13+). Owns the window and the app's root view
//  controller — the app's composition root, per the uikit-app-structure skill.
//
//  This whole type is gated to iOS 13+. On iOS 12 the scene manifest is ignored and
//  `AppDelegate` owns the window instead (see `docs/Design.md`).
//

import UIKit

@available(iOS 13.0, *)
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
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        AppRoot.handle(url, on: window)
    }
}
