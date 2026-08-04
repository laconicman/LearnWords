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
}
