//
//  ExerciseScreenAppearanceTests.swift
//  Unit Testing Bundle
//
//  Regression for the TD-16 adoption bug: the exercise screens start hidden
//  (viewDidLoad sets the container's alpha 0 / scale 0.8) and rely on askQuestion ending
//  in ExerciseTransition.show — when that entry spring was removed, every exercise screen
//  appeared as an empty view (nav bar + tab bar only).
//
//  Since TD-20 the container is `ExerciseViewController.contentStack`, built in code
//  rather than wired from the storyboard, and this test now also covers that the scene
//  still instantiates and lays itself out at all.
//

import Testing
import UIKit
@testable import LearnWords

@MainActor
struct ExerciseScreenAppearanceTests {

    @Test func exerciseScreenBecomesVisibleAfterAppearing() async throws {
        let prefs = LWUserDefaults.standard
        let pronounce = prefs.pronounceQuestionsPreference
        prefs.pronounceQuestionsPreference = false  // keep the test silent
        defer { prefs.pronounceQuestionsPreference = pronounce }

        if Storage.wordsAndStat.isEmpty {  // askQuestion pops (skips show) on an empty set
            Storage.wordsAndStat = [WordAndStat(firstWord: "bear", secondWord: "медведь",
                                                correct: [:], incorrect: [:], skiped: 0)]
        }

        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let vc = try #require(storyboard.instantiateViewController(withIdentifier: "WordTest")
                              as? WordTestViewController)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = vc
        window.isHidden = false  // drives the full appearance cycle incl. viewDidAppear
        defer { window.isHidden = true }

        #expect(vc.contentStack.alpha == 0, "precondition: the screen starts hidden")
        try await Task.sleep(nanoseconds: 1_500_000_000)  // viewDidAppear + 0.5 s spring
        #expect(vc.contentStack.alpha == 1,
                "exercise UI must spring in on appearance — askQuestion must end in ExerciseTransition.show")
    }
}
