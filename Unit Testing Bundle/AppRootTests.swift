//
//  AppRootTests.swift
//  Unit Testing Bundle
//
//  Launch smoke test: the composition root builds the home tab bar from Main.storyboard.
//  Exercises AppRoot + the storyboard without full UI automation.
//
//  These grew after the tab bar was found to differ between the two life cycles — three
//  tabs on iOS 12, four on iOS 13+, with the second one titled "Item". Neither fault was
//  in code a test could reach: one lived in `Info.plist`, the other in the storyboard.
//  What is checkable is the shape they produced, so that is what is pinned here.
//

import Testing
import UIKit
@testable import LearnWords

@MainActor
struct AppRootTests {

    private func makeTabBar() throws -> UITabBarController {
        try #require(AppRoot.makeRoot() as? UITabBarController)
    }

    @Test func makeRootReturnsHomeTabBar() throws {
        #expect(try makeTabBar().viewControllers?.isEmpty == false)
    }

    /// The tab bar has every tab, in the order `AppRoot.Tab` routes on.
    ///
    /// `Tab`'s constants are positions in a storyboard, and reordering the scenes there
    /// would send a tapped reminder to the wrong screen with nothing to complain.
    ///
    /// It does **not** catch the fault that prompted it. Manage Sets used to declare a
    /// `UITabBarItem` on its navigation controller's *child* as well, leaving Xcode's "Item"
    /// placeholder on the controller itself; iOS 12 showed the placeholder. This test was
    /// run against that storyboard and passed, because on iOS 13+ a navigation controller
    /// forwards `tabBarItem` to its root view controller and the placeholder is invisible.
    /// The defect is only observable on an OS no simulator here can run — recorded in TD-47.
    @Test func everyTabIsWhereTheRoutingConstantsSayItIs() throws {
        let tabs = try makeTabBar()
        let titles = try #require(tabs.viewControllers).map(\.tabBarItem.title)

        #expect(titles.count == 4)
        #expect(titles[AppRoot.Tab.words] == "Word Set")
        #expect(titles[AppRoot.Tab.manageSets] == "Manage Sets")
        #expect(titles[AppRoot.Tab.exercises] == "Exercises")
        #expect(titles[AppRoot.Tab.settings] == "Settings")
    }

    /// `UIMainStoryboardFile` must stay out of `Info.plist`.
    ///
    /// With it present, UIKit built the window from the storyboard before any of our code
    /// ran, so iOS 12 never reached `makeRoot()` and never got the Settings tab appended.
    /// It is the kind of key Xcode is happy to put back.
    @Test func theStoryboardDoesNotBuildTheWindowBehindOurBack() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "UIMainStoryboardFile") == nil)
    }

    // MARK: - Notification taps

    // `UNNotificationResponse` has no public initializer, so the tap-handling decision is
    // pinned through `handleTap`'s plain values. Each test uses its own identifier: the
    // dedup key is process-wide, and a shared one would make later cases depend on order.

    private func makeWindowedTabBar() throws -> (UITabBarController, UIWindow) {
        let tabs = try makeTabBar()
        let window = UIWindow(frame: .zero)
        window.rootViewController = tabs
        return (tabs, window)
    }

    private var reminderUserInfo: [AnyHashable: Any] {
        ["url": ReminderScheduler.practiceURL.absoluteString]
    }

    /// The whole contract between `ReminderScheduler` and both delivery paths is
    /// `userInfo["url"]`; a drifted key routes nowhere.
    @Test func aReminderTapLandsOnTheExercisesTab() throws {
        let (tabs, window) = try makeWindowedTabBar()

        #expect(AppRoot.handleTap(identifier: "test-reminder-a", date: Date(),
                                  userInfo: reminderUserInfo, on: window))
        #expect(tabs.selectedIndex == AppRoot.Tab.exercises)
    }

    /// A cold-launch tap reaches both `connectionOptions.notificationResponse` and
    /// `didReceive`; the second delivery of the same firing must be a no-op, while a
    /// later firing of the same reminder routes again.
    @Test func theSameTapIsNotRoutedTwice() throws {
        let (tabs, window) = try makeWindowedTabBar()
        let fired = Date()

        #expect(AppRoot.handleTap(identifier: "test-reminder-b", date: fired,
                                  userInfo: reminderUserInfo, on: window))
        #expect(AppRoot.handleTap(identifier: "test-reminder-b", date: fired,
                                  userInfo: reminderUserInfo, on: window) == false)
        #expect(AppRoot.handleTap(identifier: "test-reminder-b",
                                  date: fired.addingTimeInterval(86_400),
                                  userInfo: reminderUserInfo, on: window))
        #expect(tabs.selectedIndex == AppRoot.Tab.exercises)
    }

    /// `didReceive` can fire before the scene's window exists on a cold launch. That
    /// delivery must not consume the tap, or the scene path — which always has a
    /// window — would find it already routed and the launch would land on the
    /// default tab: the bug this routing exists to fix.
    @Test func aTapThatFindsNoWindowIsLeftForTheScenePath() throws {
        let fired = Date()

        #expect(AppRoot.handleTap(identifier: "test-reminder-c", date: fired,
                                  userInfo: reminderUserInfo, on: nil) == false)

        let (tabs, window) = try makeWindowedTabBar()
        #expect(AppRoot.handleTap(identifier: "test-reminder-c", date: fired,
                                  userInfo: reminderUserInfo, on: window))
        #expect(tabs.selectedIndex == AppRoot.Tab.exercises)
    }

    /// Notifications that carry no routable `url` — including non-string and
    /// unparseable values — are ignored rather than routed somewhere arbitrary.
    @Test func aNotificationWithoutARoutableURLIsIgnored() {
        let window = UIWindow(frame: .zero)

        #expect(AppRoot.handleTap(identifier: "test-reminder-d", date: Date(),
                                  userInfo: [:], on: window) == false)
        #expect(AppRoot.handleTap(identifier: "test-reminder-e", date: Date(),
                                  userInfo: ["url": 42], on: window) == false)
        #expect(AppRoot.handleTap(identifier: "test-reminder-f", date: Date(),
                                  userInfo: ["url": "not a url at all"],
                                  on: window) == false)
    }
}
