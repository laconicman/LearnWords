//
//  AppRootTests.swift
//  Unit Testing Bundle
//
//  Launch smoke test: the composition root builds the home tab bar from Main.storyboard.
//  Exercises AppRoot + the storyboard without full UI automation.
//

import Testing
import UIKit
@testable import LearnWords

@MainActor
struct AppRootTests {

    @Test func makeRootReturnsHomeTabBar() throws {
        let root = AppRoot.makeRoot()
        let tabBar = try #require(root as? UITabBarController)
        #expect(tabBar.viewControllers?.isEmpty == false)
    }
}
