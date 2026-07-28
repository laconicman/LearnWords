//
//  AppDelegate.swift
//  LearnWords
//
//  Created by Paul on 08.10.2017.
//  Copyright © 2017 Paul. All rights reserved.
//

import UIKit
import UserNotifications

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

        // Must be set before launch finishes, or a notification that *started* the app is
        // delivered before anything is listening and the tap goes nowhere.
        UNUserNotificationCenter.current().delegate = self

        // Reminders are rebuilt whenever the app can see fresh state: on the way to the
        // background (the freshest moment before the learner is away), on return, and when
        // another device's changes land — that last one is the only case where a predicted
        // count can be an over-estimate.
        let rebuild = #selector(rebuildReminders)
        let notifications = NotificationCenter.default
        notifications.addObserver(self, selector: rebuild,
                                  name: UIApplication.didEnterBackgroundNotification, object: nil)
        notifications.addObserver(self, selector: rebuild,
                                  name: UIApplication.willEnterForegroundNotification, object: nil)
        // `storeDidChange`, not `…Remotely`: adding a word here changes what is due just
        // as much as receiving one from another device, and the schedule must not be
        // rebuilt from stale data in the local case (owner, DRY).
        notifications.addObserver(self, selector: rebuild,
                                  name: LWPersistence.storeDidChange, object: nil)
        rebuildReminders()
        return true
    }

    @objc private func rebuildReminders() {
        ReminderScheduler.shared.rebuild(from: Library.shared.lexicon)
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

// MARK: - Reminders

extension AppDelegate: UNUserNotificationCenterDelegate {

    /// A tapped reminder lands on the Exercises tab.
    ///
    /// The window is found from the connected scene on iOS 13+, and from `window` on 12 —
    /// the same dual-lifecycle split as everywhere else, kept to this one expression.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        guard let string = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: string) else { return }
        AppRoot.handle(url, on: keyWindow)
    }

    /// Reminders are shown even while the app is open.
    ///
    /// This used to return `[]` — "you are already here, a banner would be noise". That was
    /// second-guessing a request the learner had explicitly made, and it made the whole
    /// feature unfalsifiable: set a reminder for a minute from now, stay in the app to
    /// watch for it, and nothing happens. Silently dropping a notification is never the
    /// friendlier reading of "remind me".
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                    @escaping (UNNotificationPresentationOptions) -> Void) {
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .list, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }

    private var keyWindow: UIWindow? {
        if #available(iOS 13.0, *) {
            return UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.windows.first { $0.isKeyWindow } }
                .first
        }
        return window
    }
}
