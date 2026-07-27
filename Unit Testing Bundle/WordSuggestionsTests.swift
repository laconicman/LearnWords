//
//  WordSuggestionsTests.swift
//  Unit Testing Bundle
//
//  Completions and recents — the part of the old search screen that was worth keeping and
//  impossible to test while it lived inside a 600-line view controller (TD-28).
//

import Testing
import UIKit
@testable import LearnWords

@MainActor
@Suite(.serialized)
struct WordSuggestionsTests {

    /// A throwaway suite so a test never reads or writes the learner's real recents.
    private func makeSuggestions(_ language: String) -> WordSuggestions {
        let defaults = UserDefaults(suiteName: "WordSuggestionsTests-\(UUID().uuidString)")!
        return WordSuggestions(language: language, defaults: defaults)
    }

    // MARK: - Completions

    @Test func completionsExtendWhatWasTyped() {
        let found = makeSuggestions("en").completions(for: "bea")
        #expect(!found.isEmpty)
        #expect(found.allSatisfy { $0.lowercased().hasPrefix("bea") })
    }

    @Test func nothingTypedYieldsNothing() {
        #expect(makeSuggestions("en").completions(for: "").isEmpty)
        #expect(makeSuggestions("en").completions(for: "   ").isEmpty)
    }

    /// The checker offers "bear'" and "bear's" for almost every English noun and neither is
    /// a word anyone is learning.
    @Test func englishDropsApostropheForms() {
        let found = makeSuggestions("en").completions(for: "bea")
        #expect(!found.contains { $0.hasSuffix("'") || $0.hasSuffix("'s") })
    }

    /// The rule is English-only: elsewhere an apostrophe is part of the spelling.
    @Test func otherLanguagesKeepEverythingTheCheckerOffers() {
        let french = makeSuggestions("fr")
        // Whatever French offers for "l", none of it may be filtered by an English rule.
        let unfiltered = UITextChecker().completions(
            forPartialWordRange: "aujourd".fullNSRange(), in: "aujourd", language: "fr") ?? []
        #expect(french.completions(for: "aujourd").count == unfiltered.count)
    }

    /// Region must not decide the rule — "en-US" is English.
    @Test func theEnglishRuleFollowsTheLanguageNotTheTag() {
        #expect(!makeSuggestions("en-US").completions(for: "bea")
            .contains { $0.hasSuffix("'s") })
    }

    // MARK: - Recents

    @Test func recentsAreMostRecentFirst() {
        let suggestions = makeSuggestions("en")
        suggestions.remember("bear")
        suggestions.remember("fox")
        #expect(suggestions.recents == ["fox", "bear"])
    }

    @Test func rememberingAWordAgainMovesItUpRatherThanDuplicating() {
        let suggestions = makeSuggestions("en")
        ["bear", "fox", "BEAR"].forEach(suggestions.remember)
        #expect(suggestions.recents == ["BEAR", "fox"])
    }

    @Test func blankWordsAreNotRemembered() {
        let suggestions = makeSuggestions("en")
        suggestions.remember("   ")
        #expect(suggestions.recents.isEmpty)
    }

    /// A shortcut longer than a screen has stopped being one.
    @Test func recentsAreCapped() {
        let suggestions = makeSuggestions("en")
        (1...25).forEach { suggestions.remember("word\($0)") }
        #expect(suggestions.recents.count == 10)
        #expect(suggestions.recents.first == "word25")
    }

    /// "The last words you typed" means nothing across two languages.
    @Test func recentsAreSeparatePerLanguage() {
        let defaults = UserDefaults(suiteName: "WordSuggestionsTests-\(UUID().uuidString)")!
        let english = WordSuggestions(language: "en", defaults: defaults)
        let russian = WordSuggestions(language: "ru", defaults: defaults)

        english.remember("bear")
        #expect(russian.recents.isEmpty)
        #expect(english.recents == ["bear"])
    }

    /// …but a regioned tag is the same language, so it shares them.
    @Test func regionedTagsShareOneLanguagesRecents() {
        let defaults = UserDefaults(suiteName: "WordSuggestionsTests-\(UUID().uuidString)")!
        WordSuggestions(language: "en-US", defaults: defaults).remember("bear")
        #expect(WordSuggestions(language: "en-GB", defaults: defaults).recents == ["bear"])
    }
}
