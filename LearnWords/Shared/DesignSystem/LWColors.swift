//
//  LWColors.swift
//  LearnWords
//
//  The app's colour vocabulary, named by meaning rather than by hue.
//
//  Two rules behind these choices:
//
//  * **Semantic, not literal.** The exercise screens used to hard-code
//    `UIColor(red: 0, green: 0.7, blue: 0, alpha: 1)` for a correct answer, repeated in
//    all three controllers. A fixed RGB triple cannot adapt to dark mode, and the three
//    copies were free to drift. The system colours below are adaptive and iOS 7+, so
//    they work at the 12.1 floor where `.label` and friends do not.
//
//  * **One source of truth per meaning.** `answerCorrect` is the same green
//    `LWButton.Purpose.affirmative` paints the "Know" button with, so the button a
//    learner presses and the answer text that follows agree by construction.
//
//  Text colours stay as named asset colours (TD-11) — those carry explicit Any/Dark
//  appearances and predate the semantic UIColors on our deployment target.
//

import UIKit

extension UIColor {

    // MARK: - Answer feedback

    /// A correct answer, and the "Know" button.
    static var lwAnswerCorrect: UIColor { .systemGreen }

    /// A wrong answer, and the "Forgot" button. Not "destructive" — nothing is destroyed.
    static var lwAnswerWrong: UIColor { .systemRed }

    /// An unanswered prompt: the "?" placeholder and the type/pronounce hints.
    static var lwAnswerPending: UIColor { .systemTeal }

    // MARK: - Accent

    /// The app's accent, matching the tab bar and progress views.
    static var lwAccent: UIColor { .systemOrange }

    // MARK: - Text

    static var lwTextPrimary: UIColor { UIColor(named: "TextPrimary") ?? .darkText }
    static var lwTextSecondary: UIColor { UIColor(named: "TextSecondary") ?? .darkGray }
}
