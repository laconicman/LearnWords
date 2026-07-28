//
//  ExerciseAnswerSurface.swift
//  LearnWords
//
//  The one thing that actually differs between the three exercises: how the learner
//  gives an answer, and how the answer is shown back.
//
//  This replaces an abstract `ExerciseViewController` whose subclasses had to override
//  members guarded by `fatalError("must override")`. Those were runtime traps for
//  something the compiler can enforce: a screen is now *given* its surface, and a surface
//  cannot exist without implementing this protocol. Nothing is abstract, nothing traps,
//  and a surface is a plain object — testable without a view controller, which a
//  subclass never was.
//
//  (A protocol with default implementations cannot replace the screen itself: protocol
//  extensions have no stored properties, and the screen owns real state — the session,
//  the container, the buttons. Composition is what fits here.)
//

import UIKit

/// What a surface may ask of the screen hosting it. Deliberately narrow — a surface can
/// read the question in flight and submit an answer; it cannot drive the sitting.
protocol ExerciseScreen: AnyObject {

    /// The question on screen, or `nil` between questions and once the sitting is over.
    var question: PracticeSession.Question? { get }

    /// The languages this sitting runs in.
    var languages: LanguagePair { get }

    /// Submit an answer for the current question. The screen records it, reveals the
    /// answer and moves on.
    ///
    /// - Parameter response: what the learner actually typed or said. `nil` for
    ///   self-assessed answers, where there is nothing to record — and *not* `""`,
    ///   which would claim they answered with silence.
    func answer(_ outcome: ReviewOutcome, response: String?)

    /// Show an alert from the screen (permissions, recognition errors).
    func presentAlert(_ alert: UIAlertController)
}

extension ExerciseScreen {
    func answer(_ outcome: ReviewOutcome) { answer(outcome, response: nil) }
}

/// How one exercise takes and displays an answer.
protocol ExerciseAnswerSurface: AnyObject {

    /// The view placed where the answer belongs. Receives the KaPow feedback, so it must
    /// be a child of the animated container, never the container itself (TD-16).
    var answerView: UIView { get }

    /// An extra control below the answer buttons — Phonetics' record button. Default `nil`.
    var accessoryButton: LWButton? { get }

    /// Handed the screen once, before the first question.
    func attach(to screen: ExerciseScreen)

    /// Return the surface to its waiting state for a new question.
    func prepareForQuestion()

    /// Reveal `text` as the answer that was being sought.
    func showAnswer(_ text: String, isPositive: Bool)

    /// Called before the screen leaves the current question, by answer or by skip.
    /// Phonetics hands the audio session back to playback here. Default: nothing.
    func willLeaveCurrentQuestion()

    /// Called once when the screen itself goes away — the sitting finished, or the learner
    /// left. Distinct from `willLeaveCurrentQuestion`, which fires *between* questions and
    /// therefore says nothing about whether another one is coming.
    ///
    /// Anything still running has to stop here. A surface that keeps hardware open past
    /// this point holds it behind an unrelated screen, which is how the microphone stayed
    /// live — orange dot and all — after Phonetics was dismissed. Default: nothing.
    func detach()
}

// Optional parts of the contract. These are protocol *requirements* with defaults, so a
// surface that implements them still wins — unlike extension-only members, which would be
// dispatched statically and silently ignored.
extension ExerciseAnswerSurface {
    var accessoryButton: LWButton? { nil }
    func willLeaveCurrentQuestion() {}
    func detach() {}
}
