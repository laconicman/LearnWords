//
//  LanguageCodeTests.swift
//  Unit Testing Bundle
//
//  One row per language, whatever spelling it arrives in.
//
//  The trap this closes: settings hold "en-US" (a voice has a region) while the seed and
//  every import write "en". Without canonicalising, the two would be separate `Language`
//  rows and "every word in English" would return half of them.
//

import Testing
import Foundation
@testable import LearnWords

@MainActor
struct LanguageCodeTests {

    private func makeLexicon() -> Lexicon {
        Lexicon(persistence: LWPersistence(inMemory: true))
    }

    @Test(arguments: [("en-US", "en"), ("ru_RU", "ru"), ("EN", "en"),
                      ("en", "en"), ("zh-Hans", "zh")])
    func canonicalKeepsTheLanguageSubtag(tag: String, expected: String) {
        #expect(LanguageCode.canonical(tag) == expected)
    }

    @Test func aRegionedTagAndItsSubtagAreOneLanguage() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en-US", "ru-RU"])
        try lexicon.addSense(to: set.id, terms: [Term.Draft("bear", in: "en"),
                                                 Term.Draft("медведь", in: "ru-RU")])

        #expect(try lexicon.wordSet(set.id)?.languages == ["en", "ru"],
                "the set covers two languages, not four")
    }

    @Test func aMeaningIsFoundByEitherSpelling() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        try lexicon.addSense(to: set.id, terms: [Term.Draft("bear", in: "en"),
                                                 Term.Draft("медведь", in: "ru")])

        #expect(try lexicon.senses(in: set.id, from: "en-US", to: "ru-RU").count == 1)
        #expect(try lexicon.senses(in: set.id, from: "en", to: "ru").count == 1)
    }

    /// The bug this would have been: a set seeded as "en"/"ru" practised with the default
    /// "en-US"/"ru-RU" preference must still have questions to ask.
    @Test func aSeededSetIsPractisableWithRegionedPreferences() throws {
        let lexicon = makeLexicon()
        let set = try LexiconSeed.populate(lexicon)

        let session = try PracticeSession.start(
            .dictation, in: set.id,
            languages: LanguagePair(primary: "ru-RU", secondary: "en-US",
                                    showsSecondaryAsPrompt: true),
            lexicon: lexicon, includingLearned: true)

        #expect(session.nextQuestion() != nil)
    }

    @Test func theSameWordAddedUnderBothSpellingsIsOneTerm() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        try lexicon.addSense(to: set.id, terms: [Term.Draft("bear", in: "en"),
                                                 Term.Draft("медведь", in: "ru")])
        try lexicon.addSense(to: set.id, terms: [Term.Draft("bear", in: "en-GB"),
                                                 Term.Draft("мишка", in: "ru")])

        // Two meanings, but "bear" is one word shared by both — the point of an atomic
        // term, and it must not depend on which spelling the caller used.
        #expect(try lexicon.findTerms(matching: "bear").count == 1)
    }
}
