//
//  ExerciseChooserTests.swift
//  Unit Testing Bundle
//
//  The Exercises screen's first frame.
//
//  Reported by the owner, 2026-09-18: on first launch "Include learned words" showed on and
//  then animated off. The storyboard draws the switch on, the preference defaults to off, and
//  the value was applied only in `viewDidAppear` — after the screen was visible.
//

import Testing
import UIKit
@testable import LearnWords

@MainActor
struct ExerciseChooserTests {

    private func makeScreen(storing value: Bool) throws -> ExersizeChooserViewController {
        let storyboard = UIStoryboard(name: "Main",
                                      bundle: Bundle(for: ExersizeChooserViewController.self))
        let screen = try #require(
            storyboard.instantiateViewController(withIdentifier: "ExerciseChooser")
                as? ExersizeChooserViewController)
        screen.storedIncludeLearnedWords = { value }
        return screen
    }

    /// The switch must already show the stored value once the view is loaded — before it
    /// has ever appeared. The old code failed this for `false`: it left the storyboard's *on*
    /// in place until `viewDidAppear`, which is the flip the owner saw.
    @Test(arguments: [false, true])
    func theSwitchShowsTheStoredValueBeforeTheScreenAppears(_ stored: Bool) throws {
        let screen = try makeScreen(storing: stored)
        screen.loadViewIfNeeded()
        #expect(screen.includeLeanedWords.isOn == stored)
    }
}
