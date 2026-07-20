//
//  WordTestViewController.swift
//  LearnWords
//
//  Created by Paul on 09.10.2017.
//  Copyright © 2017 Paul. All rights reserved.
//
//  The recognition exercise: show the word, let the learner self-grade.
//
//  Everything structural — layout, lifecycle, transitions, scoring, progress — is in
//  `ExerciseViewController` (TD-20). What is left here is the whole of what makes this
//  screen the Learning screen: it reveals the answer in a label, and it has no input of
//  its own, so both outcomes are self-assessed.
//

import UIKit

final class WordTestViewController: ExerciseViewController {

    private let definitionLabel = LWWordLabel()

    override var exercise: ExerciseSession.Exercise { .learning }

    override func makeAnswerView() -> UIView {
        definitionLabel.font = .systemFont(ofSize: 80)
        return definitionLabel
    }

    override func prepareAnswerForQuestion() {
        definitionLabel.attributedText = NSAttributedString(
            string: "?", attributes: [.foregroundColor: UIColor.lwAnswerPending])
    }

    override func showAnswer(_ text: String, isPositive: Bool) {
        definitionLabel.attributedText = NSAttributedString(
            string: text,
            attributes: [.foregroundColor: isPositive ? UIColor.lwAnswerCorrect : UIColor.lwAnswerWrong])
    }
}
