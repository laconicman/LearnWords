//
//  SelfAssessedAnswerSurface.swift
//  LearnWords
//
//  The Learning exercise: show the word, hide the answer behind a "?", let the learner
//  reveal and self-grade with the Know / Forgot buttons.
//
//  It takes no input of its own, so it never submits an answer — both outcomes come from
//  the screen's buttons and are `.selfAssessedKnown` / `.selfAssessedForgot`: real
//  self-graded retrieval, but the weakest positive evidence (ProgressModel R2).
//
//  Was `WordTestViewController`, a subclass of an abstract screen.
//

import UIKit

final class SelfAssessedAnswerSurface: ExerciseAnswerSurface {

    private let label = LWWordLabel()

    var answerView: UIView { label }

    func attach(to screen: ExerciseScreen) {
        label.font = .systemFont(ofSize: 80)
    }

    func prepareForQuestion() {
        label.attributedText = NSAttributedString(
            string: "?", attributes: [.foregroundColor: UIColor.lwAnswerPending])
    }

    func showAnswer(_ text: String, isPositive: Bool) {
        label.attributedText = NSAttributedString(
            string: text,
            attributes: [.foregroundColor: isPositive ? UIColor.lwAnswerCorrect : UIColor.lwAnswerWrong])
    }
}
