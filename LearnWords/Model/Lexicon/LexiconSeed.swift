//
//  LexiconSeed.swift
//  LearnWords
//
//  The starter vocabulary a fresh install gets.
//
//  Nothing migrates from the old `UserDefaults` store (docs/Design.md — owner's call), so
//  a first launch would otherwise open on an empty list with nothing to press. This is
//  the smallest set that shows what the app is for; anything more belongs in an import.
//
//  Deliberately *not* a fixture in the store: seeding is an app decision, so it lives
//  beside the store rather than inside it, and `Lexicon` stays free of policy.
//

import Foundation

enum LexiconSeed {

    /// Language of the sample words. Chosen to match the app's historic default set
    /// ("Initial Sample Set (En->Ru)"), which is also the owner's own pair.
    static let studyLanguage = "en"
    static let knownLanguage = "ru"

    /// A handful of words, one sense each. Two carry synonyms so the "any of these is
    /// correct" behaviour is visible from the first round rather than needing setup.
    static let words: [(en: String, ru: [String])] = [
        ("bear", ["медведь"]),
        ("camel", ["верблюд"]),
        ("fox", ["лиса", "лисица"]),
        ("monkey", ["обезьяна"]),
        ("pig", ["свинья"]),
        ("polar bear", ["полярный медведь", "белый медведь"]),
        ("rabbit", ["кролик"]),
        ("run", ["бегать", "бежать"]),
        ("sheep", ["овца"]),
    ]

    /// Fills an empty lexicon. Does nothing if anything is already there, so it is safe
    /// to call on every launch.
    @discardableResult
    static func populateIfEmpty(_ lexicon: Lexicon) throws -> WordSet? {
        guard lexicon.isEmpty else { return nil }
        return try populate(lexicon)
    }

    @discardableResult
    static func populate(_ lexicon: Lexicon) throws -> WordSet {
        let set = try lexicon.addWordSet(
            named: NSLocalizedString("Animals", comment: "Name of the starter word set"),
            languages: [studyLanguage, knownLanguage])

        for word in words {
            var drafts = [Term.Draft(word.en, in: studyLanguage)]
            drafts += word.ru.map { Term.Draft($0, in: knownLanguage) }
            try lexicon.addSense(to: set.id, terms: drafts)
        }
        // Re-read: the summary's sense count is stale after the inserts above.
        return try lexicon.wordSet(set.id) ?? set
    }
}
