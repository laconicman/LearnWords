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
//  The alias cases are the ones a hand-rolled "take everything before the hyphen" rule got
//  wrong — they are *second rows for languages we already have*, which is worse than the
//  region problem this type was written for. Each expectation below was checked against the
//  live Wiktionary registry, not inferred.
//

import Testing
import Foundation
@testable import LearnWords

@MainActor
struct LanguageCodeTests {

    private func makeLexicon() -> Lexicon {
        Lexicon(persistence: LWPersistence(inMemory: true))
    }

    @Test(arguments: [("en-US", "en"), ("ru_RU", "ru"), ("EN", "en"), ("en", "en"),
                      ("zh-Hans", "zh"), ("zh-TW", "zh"), ("sr-Latn-RS", "sr"),
                      ("ar-001", "ar"), ("haw", "haw"), ("yue-HK", "yue")])
    func canonicalKeepsTheLanguageSubtag(tag: String, expected: String) {
        #expect(LanguageCode.canonical(tag) == expected)
    }

    /// Codes Wiktionary does not use must resolve to the ones it does, or they become a
    /// second row for a language already in the store.
    @Test(arguments: [("iw", "he"), ("in", "id"), ("ji", "yi"), ("jw", "jv"),
                      ("mo", "ro"), ("cmn", "zh"), ("iw-IL", "he")])
    func withdrawnCodesResolveToTheirReplacement(tag: String, expected: String) {
        #expect(LanguageCode.canonical(tag) == expected)
    }

    /// `Locale.canonicalLanguageIdentifier` maps "no" to "nb". Wiktionary lists `no`, `nb`
    /// and `nn` as three languages, so doing the same here would merge two of them.
    @Test(arguments: ["no", "nb", "nn", "sh", "tl", "fil", "hr", "sr", "bs"])
    func distinctWiktionaryLanguagesAreLeftAlone(tag: String) {
        #expect(LanguageCode.canonical(tag) == tag)
    }

    @Test(arguments: [("en-US", "US"), ("en_us", "US"), ("zh-hans", "Hans"),
                      ("sr-latn-rs", "Latn-RS"), ("ar-001", "001"),
                      ("ca-ES-valencia", "ES-valencia")])
    func theStrippedVarietyIsReportedInBcp47Casing(tag: String, expected: String) {
        #expect(LanguageCode.parse(tag).variety == expected)
    }

    @Test func abareTagHasNoVariety() {
        #expect(LanguageCode.parse("en").variety == nil)
        #expect(LanguageCode.parse("haw").variety == nil)
    }

    /// Two spellings of one variety must compare equal, since a `Variety` row will be
    /// keyed on this string once one exists.
    @Test func varietyCasingIsStable() {
        #expect(LanguageCode.parse("EN-us") == LanguageCode.parse("en_US"))
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
            lexicon: lexicon, scope: .everything(includingLearned: true))

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
