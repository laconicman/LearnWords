//
//  AppRoot.swift
//  LearnWords
//
//  Shared composition root for both app life cycles. `SceneDelegate` (iOS 13+) and the
//  `AppDelegate` fallback (iOS 12) build the same root UI and handle the same
//  `learnWords://` deep link through here, so the two code paths can't drift.
//

import UIKit

/// The single place that constructs the app's root UI and interprets custom-scheme URLs.
///
/// When the iOS 12 floor is eventually dropped (see `docs/TechDebt.md`, TD-8), the removal is
/// mechanical: delete `AppDelegate`'s `window`/`application(_:open:)` members — `SceneDelegate`
/// keeps calling `makeRoot()` and `handle(_:on:)` unchanged, and this file stays as-is.
enum AppRoot {

    /// The initial view controller from `Main.storyboard` (the home tab bar), with
    /// Settings appended as its last tab.
    ///
    /// **Settings was a `leftBarButtonItem` on the word list**, which took the navigation
    /// bar slot the system reserves for Edit and put an app-wide destination inside one
    /// screen's hierarchy — reachable only from that screen, and pushed onto its stack.
    /// The Human Interface Guidelines put app-level configuration in the tab bar; four tabs
    /// is well inside the five that fit without a More item.
    ///
    /// Added in code rather than in the storyboard because `SettingsViewController` is
    /// code-built and has no scene to point a relationship segue at — and because a
    /// hand-edited relationship segue is the kind of storyboard surgery that breaks quietly.
    static func makeRoot() -> UIViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let root = storyboard.instantiateInitialViewController() else {
            preconditionFailure("Main.storyboard has no initial view controller")
        }
        if let tabs = root as? UITabBarController {
            tabs.viewControllers = (tabs.viewControllers ?? []) + [makeSettingsTab()]
        }
        return root
    }

    private static func makeSettingsTab() -> UIViewController {
        let settings = UINavigationController(rootViewController: SettingsViewController())
        settings.tabBarItem = UITabBarItem(
            title: NSLocalizedString("Settings", comment: "Tab title"),
            image: .systemImage("gearshape"),
            selectedImage: .systemImage("gearshape.fill"))
        return settings
    }

    /// Posted by `handle(_:on:)` when the share-extension deep link arrives; lets an
    /// already-visible screen consume the pending import (no appearance event fires then).
    static let shareActionReceived = Notification.Name("AppRoot.shareActionReceived")

    /// Tab indexes in `Main.storyboard`, named so a routing decision reads as one.
    ///
    /// Not private, so `AppRootTests` can assert that each index still names the tab it
    /// claims to. They are positions in a storyboard file, and nothing in the storyboard
    /// knows they exist.
    enum Tab {
        static let words = 0
        static let manageSets = 1
        static let exercises = 2
        static let settings = 3
    }

    /// Interprets a `learnWords://` URL by selecting a tab. Two arrive today:
    ///
    /// * `shareaction` — the share extension's hand-off. Lands on the Word Set tab;
    ///   `WordTableViewController` consumes the pending `ImportedText` on
    ///   appearance/foreground/this notification (TD-3).
    /// * `practice` — a tapped reminder. Lands on Exercises, where the due count is shown.
    ///
    /// No root rebuild in either case, so UI state survives.
    @discardableResult
    static func handle(_ url: URL, on window: UIWindow?) -> Bool {
        debugLog(url.absoluteString)
        let tabs = window?.rootViewController as? UITabBarController

        if url.absoluteString.contains("shareaction") {
            tabs?.selectedIndex = Tab.words
            NotificationCenter.default.post(name: shareActionReceived, object: nil)
            return true
        }
        if url.absoluteString.contains("practice") {
            // Pop back to the chooser: a reminder tapped while an old exercise is still on
            // the stack should start a new sitting, not resume a stale one.
            tabs?.selectedIndex = Tab.exercises
            (tabs?.selectedViewController as? UINavigationController)?
                .popToRootViewController(animated: false)
            return true
        }
        return false
    }
}
