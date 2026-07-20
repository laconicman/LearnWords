//
//  ExerciseScreenAppearanceTests.swift
//  Unit Testing Bundle
//
//  Regression for the TD-16 adoption bug: the exercise screen starts hidden (viewDidLoad
//  sets the container's alpha 0 / scale 0.8) and relies on askQuestion ending in
//  ExerciseTransition.show — when that entry spring was removed, every exercise screen
//  appeared as an empty view (nav bar + tab bar only).
//
//  Since TD-20 there is one screen, built in code and given its answer surface, so the
//  test constructs it directly instead of instantiating a storyboard scene — and covers
//  all three exercises rather than just Learning.
//

import Testing
import UIKit
@testable import LearnWords

// Serialized: each case drives a real appearance cycle in its own `UIWindow` and shares
// `Storage.wordsAndStat`; running those concurrently is asking for trouble.
@Suite(.serialized)
@MainActor
struct ExerciseScreenAppearanceTests {

    @Test(arguments: [ExerciseSession.Exercise.learning, .dictation, .phonetics])
    func exerciseScreenBecomesVisibleAfterAppearing(_ exercise: ExerciseSession.Exercise) async throws {
        let prefs = LWUserDefaults.standard
        let pronounce = prefs.pronounceQuestionsPreference
        prefs.pronounceQuestionsPreference = false  // keep the test silent
        defer { prefs.pronounceQuestionsPreference = pronounce }

        if Storage.wordsAndStat.isEmpty {  // askQuestion leaves (skips show) on an empty set
            Storage.wordsAndStat = [WordAndStat(firstWord: "bear", secondWord: "медведь",
                                                correct: [:], incorrect: [:], skiped: 0)]
        }

        let vc = ExerciseViewController.make(exercise)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UINavigationController(rootViewController: vc)
        window.isHidden = false  // drives the full appearance cycle incl. viewDidAppear
        defer { window.isHidden = true }
        window.layoutIfNeeded()  // the root's view must be loaded before we read its state

        #expect(vc.isViewLoaded, "precondition: the screen loaded")
        #expect(vc.contentStack.alpha == 0, "precondition: the screen starts hidden")
        #expect(Storage.wordsAndStat.isEmpty == false, "precondition: the round has words")
        try await Task.sleep(nanoseconds: 1_500_000_000)  // viewDidAppear + 0.5 s spring
        #expect(vc.contentStack.alpha == 1,
                "\(exercise) must spring in on appearance — askQuestion must end in ExerciseTransition.show")
    }

    /// Surfaces are plain objects now, so this needs no view controller at all — something
    /// the abstract-subclass design could not offer.
    @Test func onlyPhoneticsContributesAnAccessoryControl() {
        #expect(SelfAssessedAnswerSurface().accessoryButton == nil)
        #expect(TypedAnswerSurface().accessoryButton == nil)
        #expect(SpokenAnswerSurface().accessoryButton != nil)
    }
}
