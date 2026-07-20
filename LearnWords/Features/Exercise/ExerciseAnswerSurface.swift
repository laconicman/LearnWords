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
//  extensions have no stored properties, and the screen owns real state — session,
//  languages, the container, the buttons. Composition is what fits here.)
//

import UIKit

/// What a surface may ask of the screen hosting it. Deliberately narrow — a surface can
/// read the current question and submit an answer; it cannot drive the round.
protocol ExerciseScreen: AnyObject {

    /// The word being asked, or `nil` once the round is over.
    var currentWord: WordAndStat? { get }

    /// The languages and direction this round runs in.
    var languages: LanguagePair { get }

    /// Submit an answer for the current word. The screen scores it, reveals the answer
    /// and moves on.
    func answer(_ outcome: ReviewOutcome)

    /// Show an alert from the screen (permissions, recognition errors).
    func presentAlert(_ alert: UIAlertController)
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

    /// Called before the screen leaves the current word, by answer or by skip.
    /// Phonetics hands the audio session back to playback here. Default: nothing.
    func willLeaveCurrentWord()
}

// Optional parts of the contract. These are protocol *requirements* with defaults, so a
// surface that implements them still wins — unlike extension-only members, which would be
// dispatched statically and silently ignored.
extension ExerciseAnswerSurface {
    var accessoryButton: LWButton? { nil }
    func willLeaveCurrentWord() {}
}
