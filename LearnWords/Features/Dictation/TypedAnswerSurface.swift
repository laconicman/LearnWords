//
//  TypedAnswerSurface.swift
//  LearnWords
//
//  The Dictation exercise: type the translation.
//
//  The only place in the app that can tell `.correctVerbatim` from `.correctJudged` —
//  the live comparison while typing is exact, while submitting runs `match3`, which only
//  decides the attempt was close enough. `ProgressModel` wants that distinction kept
//  rather than collapsed into "correct".
//
//  Was `WordDictationController`, a subclass of an abstract screen.
//

import UIKit

final class TypedAnswerSurface: NSObject, ExerciseAnswerSurface, UITextFieldDelegate {

    private let input = UITextField()
    private weak var screen: ExerciseScreen?

    var answerView: UIView { input }

    func attach(to screen: ExerciseScreen) {
        self.screen = screen
        input.borderStyle = .roundedRect
        input.font = .systemFont(ofSize: 40)
        input.textAlignment = .center
        input.adjustsFontSizeToFitWidth = true
        input.minimumFontSize = 17
        input.clearsOnBeginEditing = true
        input.delegate = self
    }

    func prepareForQuestion() {
        input.isUserInteractionEnabled = true
        input.text = ""
        input.textColor = .lwTextPrimary
        input.attributedPlaceholder = NSAttributedString(
            string: NSLocalizedString("type in the translation", comment: "Placeholder promt"),
            attributes: [.foregroundColor: UIColor.lwAnswerPending])
    }

    func showAnswer(_ text: String, isPositive: Bool) {
        let colour = isPositive ? UIColor.lwAnswerCorrect : UIColor.lwAnswerWrong
        input.attributedText = NSAttributedString(string: text, attributes: [.foregroundColor: colour])
        input.textColor = colour
    }

    // MARK: - UITextFieldDelegate

    /// Exact match as the learner types — the strongest evidence the app can collect.
    ///
    /// Checked against **every** synonym: with the lexical model a meaning may have
    /// several words in the answer language, and typing any of them is verbatim-correct.
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange,
                   replacementString string: String) -> Bool {
        guard let screen, let question = screen.question,
              let current = textField.text, let replaced = Range(range, in: current) else { return true }

        let typed = current.replacingCharacters(in: replaced, with: string)
            .trimmingCharacters(in: .whitespaces)
        let isExact = question.answers.contains {
            $0.text.compare(typed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }

        if isExact {
            textField.isUserInteractionEnabled = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak screen] in
                screen?.answer(.correctVerbatim, response: typed)
            }
        }
        return true
    }

    /// Submitting runs the near-miss matcher against each accepted answer, so a close
    /// attempt is judged rather than simply wrong.
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard let screen else { return true }
        guard let typed = textField.text?.trimmingCharacters(in: .whitespaces),
              !typed.isEmpty, let question = screen.question else {
            screen.answer(.incorrect, response: textField.text)
            return true
        }

        let matched = question.answers.contains {
            match3(pattern: $0.text, answer: typed, language: screen.languages.answerLanguage)
        }
        screen.answer(matched ? .correctJudged : .incorrect, response: typed)
        return true
    }
}
