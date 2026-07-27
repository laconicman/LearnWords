//
//  WordSuggestions.swift
//  LearnWords
//
//  Completions for a partly-typed word, and the words recently looked up in a language.
//
//  Lifted out of `SearchWordViewController` (TD-28), where it was four responsibilities
//  tangled into one 600-line screen. It is a plain value: text in, candidates out, no view
//  controller and no store — which is what lets word entry and the add-word flow share it
//  instead of growing a second copy, and what makes the English apostrophe rule below
//  testable at all.
//
//  Recents are per language, because "the last five words you typed" means nothing across
//  two of them.
//

import UIKit

struct WordSuggestions {

    /// `UITextChecker` is the autocorrect word list, not a dictionary, so some completions
    /// have no definition. That is acceptable here — the learner is choosing a spelling,
    /// not looking one up.
    private let checker = UITextChecker()
    private let defaults: UserDefaults
    let language: String

    init(language: String, defaults: UserDefaults = userDefaultsGroup) {
        self.language = language
        self.defaults = defaults
    }

    // MARK: - Completions

    /// Words beginning with `fragment`, in this suggestion set's language.
    ///
    /// English drops completions ending in `'` or `'s`: the checker offers them for almost
    /// every noun and none of them is a word anybody is trying to learn. The rule is
    /// English-only because the apostrophe means something else elsewhere.
    func completions(for fragment: String) -> [String] {
        let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let found = checker.completions(forPartialWordRange: trimmed.fullNSRange(),
                                        in: trimmed,
                                        language: language) ?? []
        guard LanguageCode.canonical(language) == "en" else { return found }
        return found.filter { !$0.hasSuffix("'") && !$0.hasSuffix("'s") }
    }

    // MARK: - Recents

    private var key: String { "RecentSearchesFor_" + LanguageCode.canonical(language) }

    /// Most recent first.
    var recents: [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    /// Records a word as recently used, most recent first, without duplicates.
    ///
    /// Capped at ten: this is a shortcut, and a list longer than a screen stops being one.
    func remember(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = recents.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        updated.insert(trimmed, at: 0)
        defaults.set(Array(updated.prefix(10)), forKey: key)
    }

    func forgetAll() {
        defaults.removeObject(forKey: key)
    }
}
