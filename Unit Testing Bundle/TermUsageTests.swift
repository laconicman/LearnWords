//
//  TermUsageTests.swift
//  Unit Testing Bundle
//
//  "Do I already have this word?" — the lookup behind both the add-word hint and the
//  duplicate guard.
//
//  It exists because the store deduplicates *words* but not *meanings*: adding
//  bear/медведь twice linked the same two words into two separate meanings, so one word
//  appeared twice in the list with its review history split between them.
//

import Testing
import Foundation
@testable import LearnWords

@MainActor
struct TermUsageTests {

    private func makeLexicon() -> Lexicon {
        Lexicon(persistence: LWPersistence(inMemory: true))
    }

    @discardableResult
    private func add(_ en: String, _ ru: String, to set: WordSet,
                     in lexicon: Lexicon) throws -> Sense {
        try lexicon.addSense(to: set.id, terms: [Term.Draft(en, in: "en"),
                                                 Term.Draft(ru, in: "ru")])
    }

    private func makeSet(_ lexicon: Lexicon, named name: String) throws -> WordSet {
        try lexicon.addWordSet(named: name, languages: ["en", "ru"])
    }

    // MARK: - Finding

    @Test func anUnknownWordHasNoUsages() throws {
        let lexicon = makeLexicon()
        _ = try makeSet(lexicon, named: "Animals")
        #expect(try lexicon.usages(ofTerm: "bear", in: "en").isEmpty)
    }

    @Test func aKnownWordReportsItsMeaningAndSet() throws {
        let lexicon = makeLexicon()
        let set = try makeSet(lexicon, named: "Animals")
        try add("bear", "медведь", to: set, in: lexicon)

        let usage = try #require(try lexicon.usages(ofTerm: "bear", in: "en").first)
        #expect(usage.translations == ["медведь"])
        #expect(usage.setNames == ["Animals"])
    }

    /// The hint has to reach across sets: a word already learned in one set is most worth
    /// knowing about while adding it to another.
    @Test func usagesAreFoundInEverySetNotJustTheCurrentOne() throws {
        let lexicon = makeLexicon()
        let animals = try makeSet(lexicon, named: "Animals")
        _ = try makeSet(lexicon, named: "Verbs")
        try add("bear", "медведь", to: animals, in: lexicon)

        #expect(try lexicon.usages(ofTerm: "bear", in: "en").first?.setNames == ["Animals"])
    }

    @Test func matchingIgnoresCaseAndSurroundingSpace() throws {
        let lexicon = makeLexicon()
        let set = try makeSet(lexicon, named: "Animals")
        try add("bear", "медведь", to: set, in: lexicon)

        #expect(try !lexicon.usages(ofTerm: "BEAR", in: "en").isEmpty)
        #expect(try !lexicon.usages(ofTerm: "  bear ", in: "en").isEmpty)
    }

    /// The store keeps language subtags, the caller may hold a regioned preference.
    @Test func aRegionedTagFindsTheSameWord() throws {
        let lexicon = makeLexicon()
        let set = try makeSet(lexicon, named: "Animals")
        try add("bear", "медведь", to: set, in: lexicon)

        #expect(try !lexicon.usages(ofTerm: "bear", in: "en-US").isEmpty)
    }

    /// A word spelled the same in two languages is two different words.
    @Test func theLanguageIsPartOfTheQuestion() throws {
        let lexicon = makeLexicon()
        let set = try makeSet(lexicon, named: "Animals")
        try add("bear", "медведь", to: set, in: lexicon)

        #expect(try lexicon.usages(ofTerm: "bear", in: "ru").isEmpty)
    }

    @Test func aWordInTwoMeaningsReportsBoth() throws {
        let lexicon = makeLexicon()
        let set = try makeSet(lexicon, named: "Animals")
        try add("bear", "медведь", to: set, in: lexicon)
        try add("bear", "нести", to: set, in: lexicon)

        let usages = try lexicon.usages(ofTerm: "bear", in: "en")
        #expect(usages.count == 2)
        #expect(Set(usages.flatMap(\.translations)) == ["медведь", "нести"])
    }

    // MARK: - Deciding

    @Test func aUsageRecognisesTheMeaningItAlreadyHolds() throws {
        let lexicon = makeLexicon()
        let set = try makeSet(lexicon, named: "Animals")
        try add("bear", "медведь", to: set, in: lexicon)

        let usage = try #require(try lexicon.usages(ofTerm: "bear", in: "en").first)
        #expect(usage.matches(translations: ["медведь"]))
        #expect(usage.matches(translations: ["МЕДВЕДЬ"]), "case is not a different meaning")
        #expect(!usage.matches(translations: ["нести"]))
    }

    // MARK: - Replacing

    /// The point of `replaceTerms` over delete-and-re-add: the meaning keeps its identity,
    /// so everything hanging off it — above all the review log — survives.
    @Test func replacingAMeaningKeepsItsHistory() throws {
        let lexicon = makeLexicon()
        let set = try makeSet(lexicon, named: "Animals")
        let sense = try add("bear", "медведь", to: set, in: lexicon)

        let session = try PracticeSession.start(
            .dictation, in: set.id,
            languages: LanguagePair(primary: "ru", secondary: "en", showsSecondaryAsPrompt: true),
            lexicon: lexicon, scope: .everything(includingLearned: true))
        _ = session.nextQuestion()
        try session.record(.correctVerbatim)

        try lexicon.replaceTerms(ofSense: sense.id, in: "ru",
                                 with: [Term.Draft("мишка", in: "ru")])

        let updated = try #require(try lexicon.sense(sense.id))
        #expect(updated.terms(in: "ru").map(\.text) == ["мишка"])
        #expect(updated.terms(in: "en").map(\.text) == ["bear"], "the other side is untouched")
        #expect(try lexicon.history(ofSense: sense.id).count == 1, "the history is still there")
    }

    @Test func replacingLeavesOtherMeaningsAlone() throws {
        let lexicon = makeLexicon()
        let set = try makeSet(lexicon, named: "Animals")
        let first = try add("bear", "медведь", to: set, in: lexicon)
        let second = try add("fox", "лиса", to: set, in: lexicon)

        try lexicon.replaceTerms(ofSense: first.id, in: "ru",
                                 with: [Term.Draft("мишка", in: "ru")])

        #expect(try lexicon.sense(second.id)?.terms(in: "ru").map(\.text) == ["лиса"])
    }

    // MARK: - Renaming into an existing word

    /// The defect this closes: `updateTerm` edits a row in place, so renaming one word into
    /// another that already exists left **two rows spelled the same** — the one thing
    /// find-or-create prevents everywhere else.
    @Test func replacingATermMergesOntoTheExistingRow() throws {
        let lexicon = makeLexicon()
        let set = try makeSet(lexicon, named: "Animals")
        let bruin = try lexicon.addSense(to: set.id, terms: [Term.Draft("bruin", in: "en"),
                                                             Term.Draft("медведь", in: "ru")])
        try add("bear", "мишка", to: set, in: lexicon)

        let old = try #require(bruin.terms(in: "en").first)
        try lexicon.replaceTerm(old.id, with: Term.Draft("bear", in: "en"), inSense: bruin.id)

        // One row for "bear", now reached by both meanings.
        let usages = try lexicon.usages(ofTerm: "bear", in: "en")
        #expect(usages.count == 2)
        #expect(try lexicon.findTerms(matching: "bear").count == 1,
                "a rename must not create a second row for the same spelling")
    }

    @Test func replacingATermLeavesTheOtherLanguageAlone() throws {
        let lexicon = makeLexicon()
        let set = try makeSet(lexicon, named: "Animals")
        let sense = try add("bruin", "медведь", to: set, in: lexicon)
        let old = try #require(sense.terms(in: "en").first)

        let updated = try lexicon.replaceTerm(old.id, with: Term.Draft("bear", in: "en"),
                                              inSense: sense.id)
        #expect(updated.terms(in: "en").map(\.text) == ["bear"])
        #expect(updated.terms(in: "ru").map(\.text) == ["медведь"])
    }

    /// A synonym list is not replaced wholesale: only the named word changes.
    @Test func replacingOneSynonymKeepsTheOthers() throws {
        let lexicon = makeLexicon()
        let set = try makeSet(lexicon, named: "Animals")
        let sense = try lexicon.addSense(to: set.id, terms: [Term.Draft("fox", in: "en"),
                                                             Term.Draft("reynard", in: "en"),
                                                             Term.Draft("лиса", in: "ru")])
        let reynard = try #require(sense.terms(in: "en").first { $0.text == "reynard" })

        let updated = try lexicon.replaceTerm(reynard.id, with: Term.Draft("tod", in: "en"),
                                              inSense: sense.id)
        #expect(Set(updated.terms(in: "en").map(\.text)) == ["fox", "tod"])
    }
}
