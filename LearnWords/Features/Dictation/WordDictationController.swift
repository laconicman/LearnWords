//
//  WordDictation.swift
//  LearnWords
//
//  Created by  Paul on 26.05.2021.
//  Copyright © 2021 Paul. All rights reserved.
//
//  The typed-production exercise.
//
//  Structure lives in `ExerciseViewController` (TD-20). What is genuinely this screen:
//  a text field, and the only place in the app that can tell `.correctVerbatim` from
//  `.correctJudged` — typing the word exactly is stronger evidence than `match3` deciding
//  the attempt was close enough, and `ProgressModel` wants that distinction kept.
//

// TODO: Add segmented control "Text|Sound|Both" (можно в виде иконок)

import UIKit
import AVFoundation

final class WordDictationController: ExerciseViewController, UITextFieldDelegate {

    private let translationInput = UITextField()
    private let underKeyboardLayoutConstraint = UnderKeyboardLayoutConstraint()

    override var exercise: ExerciseSession.Exercise { .dictation }

    override func makeAnswerView() -> UIView {
        translationInput.borderStyle = .roundedRect
        translationInput.font = .systemFont(ofSize: 40)
        translationInput.textAlignment = .center
        translationInput.adjustsFontSizeToFitWidth = true
        translationInput.minimumFontSize = 17
        translationInput.clearsOnBeginEditing = true
        translationInput.delegate = self
        return translationInput
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if let bottom = scrollBottomConstraint {
            underKeyboardLayoutConstraint.setup(bottom, view: view, minMargin: 0)
        }
    }

    // MARK: - Answer surface

    override func prepareAnswerForQuestion() {
        translationInput.isUserInteractionEnabled = true
        translationInput.text = ""
        translationInput.textColor = .lwTextPrimary
        translationInput.attributedPlaceholder = NSAttributedString(
            string: NSLocalizedString("type in the translation", comment: "Placeholder promt"),
            attributes: [.foregroundColor: UIColor.lwAnswerPending])
    }

    override func showAnswer(_ text: String, isPositive: Bool) {
        let colour = isPositive ? UIColor.lwAnswerCorrect : UIColor.lwAnswerWrong
        translationInput.attributedText = NSAttributedString(
            string: text, attributes: [.foregroundColor: colour])
        translationInput.textColor = colour
    }

    // MARK: - UITextFieldDelegate

    /// Exact match while typing — the strongest evidence the app can collect, and the
    /// reason this screen distinguishes verbatim from judged.
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange,
                   replacementString string: String) -> Bool {
        guard let word = session.currentWord, let current = textField.text,
              let replaced = Range(range, in: current) else { return true }

        let typed = current.replacingCharacters(in: replaced, with: string)
            .lowercased().trimmingCharacters(in: .whitespaces)

        if typed == languages.answer(for: word) {
            textField.isUserInteractionEnabled = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.answer(.correctVerbatim)
            }
        }
        return true
    }

    /// Submitting runs the near-miss matcher, so a close attempt is `.correctJudged`
    /// rather than either a plain success or a plain failure.
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard let typed = textField.text?.trimmingCharacters(in: .whitespaces),
              let word = session.currentWord else {
            answer(.incorrect)
            return true
        }

        let matched = match3(pattern: languages.answer(for: word),
                             answer: typed,
                             language: languages.answerLanguage)
        answer(matched ? .correctJudged : .incorrect)
        return true
    }
}
