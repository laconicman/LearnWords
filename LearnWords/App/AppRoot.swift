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

    /// The initial view controller from `Main.storyboard` (the home tab bar).
    static func makeRoot() -> UIViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let root = storyboard.instantiateInitialViewController() else {
            preconditionFailure("Main.storyboard has no initial view controller")
        }
        return root
    }

    /// Posted by `handle(_:on:)` when the share-extension deep link arrives; lets an
    /// already-visible screen consume the pending import (no appearance event fires then).
    static let shareActionReceived = Notification.Name("AppRoot.shareActionReceived")

    /// Handles the share-extension hand-off (`learnWords://shareaction`) by landing on the
    /// Word Set tab; `WordTableViewController` consumes the pending `ImportedText` on
    /// appearance/foreground/this notification (TD-3). No root rebuild — UI state survives.
    @discardableResult
    static func handle(_ url: URL, on window: UIWindow?) -> Bool {
        debugLog(url.absoluteString)
        guard url.absoluteString.contains("shareaction") else { return false }
        (window?.rootViewController as? UITabBarController)?.selectedIndex = 0
        NotificationCenter.default.post(name: shareActionReceived, object: nil)
        return true
    }
}
