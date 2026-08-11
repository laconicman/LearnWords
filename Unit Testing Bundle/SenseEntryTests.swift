//
//  SenseEntryTests.swift
//  Unit Testing Bundle
//
//  The comma rule (TD-53), as the two cases the research turns on: `берег, банк` is two
//  meanings and `лиса, лисица` is one meaning with two synonyms, and nothing in the text
//  distinguishes them. The default splits; the merge undoes it.
//
//  Pure — no store and no screen, which is the whole reason the rule lives in a value type.
//

import Testing
import Foundation
@testable import LearnWords

struct SenseEntryTests {

    private func english(_ text: String) -> SenseEntry.Side { .init(text, in: "en") }
    private func russian(_ text: String) -> SenseEntry.Side { .init(text, in: "ru") }

    // MARK: - Splitting

    /// The owner's rule, and the case it is right about.
    @Test func aCommaOnTheMeaningSideProposesTwoMeanings() {
        let proposed = SenseEntry.proposals(english("bank"), russian("берег, банк"))

        #expect(proposed.count == 2)
        #expect(proposed[0].words(in: "ru") == ["берег"])
        #expect(proposed[1].words(in: "ru") == ["банк"])
        // The word being defined belongs to both meanings — that is what makes it one word
        // with two senses rather than two unrelated rows.
        #expect(proposed.allSatisfy { $0.words(in: "en") == ["bank"] })
    }

    /// The same rule, from the other side: two studied words sharing one translation are
    /// still two meanings.
    @Test func aCommaOnTheWordSideSplitsTheSameWay() {
        let proposed = SenseEntry.proposals(russian("берег, банк"), english("bank"))

        #expect(proposed.count == 2)
        #expect(proposed[0].words(in: "ru") == ["берег"])
        #expect(proposed[1].words(in: "ru") == ["банк"])
        #expect(proposed.allSatisfy { $0.words(in: "en") == ["bank"] })
    }

    @Test func noCommaProposesOneMeaning() {
        let proposed = SenseEntry.proposals(english("fox"), russian("лиса"))

        #expect(proposed.count == 1)
        #expect(proposed[0].terms == [Term.Draft("fox", in: "en"), Term.Draft("лиса", in: "ru")])
    }

    /// Two lists of the same length are two parallel meanings, not one crowd of four words.
    @Test func equalListsArePairedInOrder() {
        let proposed = SenseEntry.proposals(english("bank, shore"), russian("банк, берег"))

        #expect(proposed.count == 2)
        #expect(proposed[0].words(in: "en") == ["bank"])
        #expect(proposed[0].words(in: "ru") == ["банк"])
        #expect(proposed[1].words(in: "en") == ["shore"])
        #expect(proposed[1].words(in: "ru") == ["берег"])
    }

    /// Lists that cannot be paired are not paired *by guesswork*: the shorter side goes
    /// into every meaning, where the learner can see it and edit it, rather than inventing
    /// a correspondence the text does not carry.
    @Test func unequalListsShareTheShorterSideRatherThanGuessing() {
        let proposed = SenseEntry.proposals(english("bank, shore, coast"), russian("банк, берег"))

        #expect(proposed.count == 3)
        #expect(proposed.map { $0.words(in: "en") } == [["bank"], ["shore"], ["coast"]])
        #expect(proposed.allSatisfy { $0.words(in: "ru") == ["банк", "берег"] })
    }

    @Test func spacingAndTrailingCommasAreTypos() {
        let proposed = SenseEntry.proposals(english("bank"), russian("  берег ,,  банк , "))

        #expect(proposed.count == 2)
        #expect(proposed[0].words(in: "ru") == ["берег"])
        #expect(proposed[1].words(in: "ru") == ["банк"])
    }

    /// A meaning needs a word on both sides, so a half-filled entry proposes nothing at all
    /// — which is what tells the flow to stay where it is instead of storing a fragment.
    @Test func anEmptySideProposesNothing() {
        #expect(SenseEntry.proposals(english("bank"), russian("")).isEmpty)
        #expect(SenseEntry.proposals(english(" "), russian("банк")).isEmpty)
        #expect(SenseEntry.proposals(english(","), russian("банк")).isEmpty)
    }

    // MARK: - Merging

    /// The case the split gets wrong, and the one control that fixes it.
    @Test func mergingTurnsTwoMeaningsBackIntoSynonyms() {
        let proposed = SenseEntry.proposals(english("fox"), russian("лиса, лисица"))
        #expect(proposed.count == 2, "precondition: the default splits")

        let merged = SenseEntry.merging(proposed, at: 1)

        #expect(merged.count == 1)
        #expect(merged[0].words(in: "ru") == ["лиса", "лисица"])
        // The shared word must not arrive twice just because both halves carried it.
        #expect(merged[0].words(in: "en") == ["fox"])
    }

    @Test func mergingTheFirstMeaningDoesNothing() {
        let proposed = SenseEntry.proposals(english("bank"), russian("берег, банк"))

        #expect(SenseEntry.merging(proposed, at: 0) == proposed)
        #expect(SenseEntry.merging(proposed, at: 7) == proposed)
    }

    // MARK: - The synonym split, used where meanings must not be created

    /// The meaning editor adds words to a meaning that already exists, so a comma there can
    /// only mean synonyms — splitting a stored meaning would strand its `ReviewEvent` log.
    @Test func typedTextSplitsIntoWords() {
        #expect(SenseEntry.words(in: "лиса, лисица") == ["лиса", "лисица"])
        #expect(SenseEntry.words(in: "лиса") == ["лиса"])
        #expect(SenseEntry.words(in: "  ,  ").isEmpty)
    }
}
