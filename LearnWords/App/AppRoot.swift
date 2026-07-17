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

    /// Handles the share-extension hand-off (`learnWords://shareaction`) by resetting the UI to
    /// the storyboard's initial view controller, mirroring the pre-scene behavior.
    ///
    /// Ported from the old `AppDelegate.application(_:open:)` (flagged unused/FIXME).
    /// TODO(TD-3): verify the intended landing screen against the ImportAsDictAction extension —
    /// the old code hinted at selecting a specific tab (`selectedIndex = 1`) rather than
    /// rebuilding the root, which discards UI state.
    @discardableResult
    static func handle(_ url: URL, on window: UIWindow?) -> Bool {
        debugLog(url.absoluteString)
        guard url.absoluteString.contains("shareaction") else { return false }
        window?.rootViewController = makeRoot()
        return true
    }
}
