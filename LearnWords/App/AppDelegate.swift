//
//  AppDelegate.swift
//  LearnWords
//
//  Created by Paul on 08.10.2017.
//  Copyright © 2017 Paul. All rights reserved.
//

import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    /// iOS 12 only: UIKit loads `Main` via `UIMainStoryboardFile`, creates this window, and
    /// assigns it here. On iOS 13+ the window lives in `SceneDelegate` and this stays `nil`.
    /// (See the dual-life-cycle decision in `docs/Design.md`.)
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // App-wide appearance. The proxies apply on every OS; `window?.tintColor` is the
        // iOS 12 path (no-op on iOS 13+, where `SceneDelegate` sets it on its own window).
        UINavigationBar.appearance().tintColor = .orange
        UITabBar.appearance().tintColor = .orange
        window?.tintColor = .orange

        // Opens the store and seeds it on a fresh install, so no screen has to cope with
        // an empty library. Runs for both lifecycles — `SceneDelegate` builds the UI
        // after this, on iOS 13+.
        Library.shared.prepareForLaunch()
        return true
    }

    // MARK: UIScene life cycle (iOS 13+)

    @available(iOS 13.0, *)
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    // MARK: Custom URL scheme (iOS 12 fallback)

    /// Handles `learnWords://` on iOS 12. On iOS 13+ UIKit routes URLs to
    /// `SceneDelegate.scene(_:openURLContexts:)` instead and never calls this.
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        AppRoot.handle(url, on: window)
    }
}
