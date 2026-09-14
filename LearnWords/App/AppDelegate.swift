//
//  AppDelegate.swift
//  LearnWords
//
//  Created by Paul on 08.10.2017.
//  Copyright © 2017 Paul. All rights reserved.
//

import UIKit
import UserNotifications
// Weak-linked (`-weak_framework WidgetKit`): an import autolinks as a plain load, and
// iOS 12–13 would refuse to launch — TD-46, where Core Haptics did exactly that.
import WidgetKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // App-wide appearance. The proxies must be set before any bar is created.
        // A horizon stored below `ScoringPolicy.minimumHorizonDays` is raised to it once,
        // here: values from before the floor existed would otherwise sit in the defaults
        // forever while the slider drew the floor and the policy enforced it — three
        // numbers disagreeing. This is the app's own launch path, which matters because
        // `LWUserDefaults` and `Library` are both compiled into the extensions, where
        // `ScoringPolicy` does not exist. Reported by review, PR #1.
        let prefs = LWUserDefaults.standard
        prefs.maxKnownLevelPreference = max(prefs.maxKnownLevelPreference,
                                            Int(ScoringPolicy.minimumHorizonDays))

        UINavigationBar.appearance().tintColor = .orange
        UITabBar.appearance().tintColor = .orange

        // Opens the store and seeds it on a fresh install, so no screen has to cope with
        // an empty library. Runs before `SceneDelegate` builds the UI.
        Library.shared.prepareForLaunch()

        // Must be set before launch finishes, or a notification that *started* the app is
        // delivered before anything is listening and the tap goes nowhere.
        UNUserNotificationCenter.current().delegate = self

        // **No APNs code, deliberately.** CloudKit's pushes are Core Data's to handle: Apple's
        // guide to syncing a Core Data store with CloudKit states that no app code is needed,
        // and the system creates the background task that imports. What sync does need is the
        // entitlement (`aps-environment`, from the Push capability) and the
        // `remote-notification` background mode — both present. An earlier version registered
        // here and completed the push handler at once with `.newData`, which could only end
        // that background time early. Reported by review, PR #14.

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
        // The widgets read the same store, but WidgetKit only asks them again on their own
        // timeline — so a word added here, or an import a silent push just woke, waited out
        // the widget's 30-minute hint and whatever WidgetKit stretched that to.
        //
        // **Here, not in `SceneDelegate`.** Launch and these store observers are app-level. A
        // CloudKit push can wake the app in the background with no scene connected, and UIKit
        // may disconnect a background scene at any time — so an observer that must hear a
        // push-driven import cannot live on a scene.
        notifications.addObserver(self, selector: #selector(reloadWidgets),
                                  name: LWPersistence.storeDidChange, object: nil)
        rebuildReminders()
        return true
    }

    @objc private func rebuildReminders() {
        ReminderScheduler.shared.rebuild(from: Library.shared.lexicon)
    }

    /// Tells WidgetKit the library changed. `storeDidChange` covers both halves — a local
    /// save and a CloudKit import — because both post it, on the main queue.
    ///
    /// **Not debounced, deliberately.** Apple: reloads requested while the containing app is
    /// in the foreground don't count against the widget's daily budget, and that is when
    /// local saves happen; remote imports arrive already coalesced by `deduplicateSoon`'s
    /// two-second window, and WidgetKit coalesces across widgets besides.
    /// (developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)
    ///
    /// `reloadAllTimelines` rather than `reloadTimelines(ofKind:)`: the kind string lives in
    /// the widget target, which the app cannot import, so naming it here would be a copy free
    /// to drift — and every widget in the bundle reads the same store anyway.
    @objc private func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: UIScene life cycle

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}

// MARK: - Reminders

extension AppDelegate: UNUserNotificationCenterDelegate {

    /// A tapped reminder lands on the Exercises tab, in the connected scene's window.
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
        completionHandler([.banner, .list, .sound])
    }

    private var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first { $0.isKeyWindow } }
            .first
    }
}
