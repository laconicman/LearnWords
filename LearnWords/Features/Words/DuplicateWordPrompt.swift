//
//  DuplicateWordPrompt.swift
//  LearnWords
//
//  "You already have this word" — asked once, from both places that can cause it.
//
//  The add-word flow and the meaning editor can each produce a duplicate, and they were
//  going to grow one alert apiece. They ask the *same* question and must offer the same
//  wording, so the question lives here and each caller says only which answers apply.
//
//  **The answers differ because the situations do**, and forcing symmetry would offer a
//  choice that does nothing. Adding a word that already exists may legitimately be a second
//  meaning — "bear" the animal and "bear" the verb. Renaming a word *into* an existing one
//  cannot be: there is one meaning being edited, and the only question is whether it should
//  now use the word that already exists.
//

import UIKit

enum DuplicateWordPrompt {

    /// What the learner chose. `cancel` is absent on purpose — it is the absence of a call.
    enum Choice {
        /// Overwrite what the existing meaning says, keeping its identity and its history.
        case replaceExisting
        /// Keep both: the word genuinely means two things.
        case addAnother
        /// Adopt the word that already exists, dropping the duplicate spelling.
        case useExisting
    }

    /// Asks, and calls back only if the learner chose to proceed.
    ///
    /// - Parameter offering: the answers that make sense here, in the order to show them.
    static func ask(on presenter: UIViewController,
                    word: String,
                    existing: Lexicon.TermUsage,
                    offering choices: [Choice],
                    onChoice: @escaping (Choice) -> Void) {
        let known = existing.translations.joined(separator: ", ")
        let alert = UIAlertController(
            title: String(format: NSLocalizedString("“%@” is already in your words",
                                                    comment: "Alert title; the word"), word),
            message: message(known: known, setNames: existing.setNames),
            preferredStyle: .alert)

        for choice in choices {
            alert.addAction(UIAlertAction(title: choice.title, style: .default) { _ in
                onChoice(choice)
            })
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "AlertAction title"),
                                      style: .cancel))
        presenter.present(alert, animated: true)
    }

    /// Names the set when it is worth naming — a duplicate the learner forgot about is
    /// usually one that lives somewhere else.
    private static func message(known: String, setNames: [String]) -> String {
        let sets = setNames.joined(separator: ", ")
        switch (known.isEmpty, sets.isEmpty) {
        case (true, true):
            return NSLocalizedString("You already have this word.", comment: "Alert message")
        case (true, false):
            return String(format: NSLocalizedString("You already have it in “%@”.",
                                                    comment: "Alert message; set names"), sets)
        case (false, true):
            return String(format: NSLocalizedString("You already have it as “%@”.",
                                                    comment: "Alert message; translations"), known)
        case (false, false):
            return String(format: NSLocalizedString("You already have it as “%@”, in “%@”.",
                                                    comment: "Alert message; translations, then sets"),
                          known, sets)
        }
    }
}

private extension DuplicateWordPrompt.Choice {
    var title: String {
        switch self {
        case .replaceExisting:
            return NSLocalizedString("Replace meaning", comment: "AlertAction title")
        case .addAnother:
            return NSLocalizedString("Add as another meaning", comment: "AlertAction title")
        case .useExisting:
            return NSLocalizedString("Use the existing word", comment: "AlertAction title")
        }
    }
}
