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

// Serialized: each case drives a real appearance cycle in its own `UIWindow` and pins the
// speech preference; running those concurrently is asking for trouble.
@Suite(.serialized)
@MainActor
struct ExerciseScreenAppearanceTests {

    @Test(arguments: [Exercise.learning, .dictation, .phonetics])
    func exerciseScreenBecomesVisibleAfterAppearing(_ exercise: Exercise) async throws {
        let prefs = LWUserDefaults.standard
        let pronounce = prefs.pronounceQuestionsPreference
        prefs.pronounceQuestionsPreference = false  // keep the test silent
        defer { prefs.pronounceQuestionsPreference = pronounce }

        // A throwaway lexicon with one meaning: `askQuestion` leaves immediately — and so
        // never springs the screen in — when the sitting has nothing to ask.
        let lexicon = Lexicon(persistence: LWPersistence(inMemory: true))
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        try lexicon.addSense(to: set.id, terms: [Term.Draft("bear", in: "en"),
                                                 Term.Draft("медведь", in: "ru")])

        let vc = try ExerciseViewController.make(exercise, in: set, lexicon: lexicon)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UINavigationController(rootViewController: vc)
        window.isHidden = false  // drives the full appearance cycle incl. viewDidAppear
        defer { window.isHidden = true }
        window.layoutIfNeeded()  // the root's view must be loaded before we read its state

        #expect(vc.isViewLoaded, "precondition: the screen loaded")
        #expect(vc.contentStack.alpha == 0, "precondition: the screen starts hidden")
        try await waitUntil { vc.contentStack.alpha == 1 }  // viewDidAppear → askQuestion → show
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

    /// The button-to-session half of "Listen marks the answer aided": the real button,
    /// its real target-action, and the screen's own sitting — only the synthesiser's
    /// output is not asserted.
    @Test func listenButtonMarksItsQuestionAided() async throws {
        let prefs = LWUserDefaults.standard
        let pronounce = prefs.pronounceQuestionsPreference
        prefs.pronounceQuestionsPreference = false  // keep the test silent
        defer { prefs.pronounceQuestionsPreference = pronounce }

        let lexicon = Lexicon(persistence: LWPersistence(inMemory: true))
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        try lexicon.addSense(to: set.id, terms: [Term.Draft("bear", in: "en"),
                                                 Term.Draft("медведь", in: "ru")])

        let vc = try ExerciseViewController.make(.dictation, in: set, lexicon: lexicon)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UINavigationController(rootViewController: vc)
        window.isHidden = false  // viewDidAppear → askQuestion deals the first question
        defer { window.isHidden = true }
        window.layoutIfNeeded()

        try await waitUntil { vc.session.current != nil }
        #expect(vc.session.current != nil, "precondition: a question is in flight")
        #expect(vc.session.currentWasAided == false, "precondition: nothing aided yet")

        // A tap only marks when the synthesiser accepts the utterance — a debounced one
        // plays nothing and marks nothing, which is what a real learner's second tap is
        // for. Another suite's speech can sit inside the window, so retry past it.
        var attempts = 0
        while !vc.session.currentWasAided, attempts < 5 {
            vc.listenButton.sendActions(for: .touchUpInside)
            attempts += 1
            if !vc.session.currentWasAided {
                try await Task.sleep(nanoseconds: 900_000_000)
            }
        }
        #expect(vc.session.currentWasAided)
    }
}
