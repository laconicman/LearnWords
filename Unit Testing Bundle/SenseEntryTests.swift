//
//  SenseEntryTests.swift
//  Unit Testing Bundle
//
//  The comma rule (TD-53), as the two cases the research turns on: `берег, банк` is two
//  meanings and `лиса, лисица` is one meaning with two synonyms, and nothing in the text
//  distinguishes them.
//
//  **The default is synonyms** (owner, 2026-08-11): one meaning, however many words. It was
//  the opposite first — both readings are wrong half the time, and the owner's call is that
//  synonyms are the commoner entry, so the wrong guess should be the one `splitting` undoes.
//
//  Pure — no store and no screen, which is the whole reason the rule lives in a value type.
//

import Testing
import Foundation
@testable import LearnWords

struct SenseEntryTests {

    private func english(_ text: String) -> SenseEntry.Side { .init(text, in: "en") }
    private func russian(_ text: String) -> SenseEntry.Side { .init(text, in: "ru") }

    // MARK: - The default: one meaning, synonyms

    /// The owner's rule since 2026-08-11, and the case it is right about: `лиса, лисица` is
    /// one meaning said two ways.
    @Test func aCommaProposesSynonymsOfOneMeaning() {
        let proposed = SenseEntry.proposals(english("fox"), russian("лиса, лисица"))

        #expect(proposed.count == 1)
        #expect(proposed[0].words(in: "ru") == ["лиса", "лисица"])
        #expect(proposed[0].words(in: "en") == ["fox"])
    }

    /// The same on the studied side — nothing about the rule depends on which side was typed
    /// with a comma.
    @Test func aCommaOnTheWordSideAlsoMeansSynonyms() {
        let proposed = SenseEntry.proposals(english("lorry, truck"), russian("грузовик"))

        #expect(proposed.count == 1)
        #expect(proposed[0].words(in: "en") == ["lorry", "truck"])
        #expect(proposed[0].words(in: "ru") == ["грузовик"])
    }

    @Test func noCommaProposesOneMeaning() {
        let proposed = SenseEntry.proposals(english("fox"), russian("лиса"))

        #expect(proposed.count == 1)
        #expect(proposed[0].terms == [Term.Draft("fox", in: "en"), Term.Draft("лиса", in: "ru")])
    }

    @Test func spacingAndTrailingCommasAreTypos() {
        let proposed = SenseEntry.proposals(english("bank"), russian("  берег ,,  банк , "))

        #expect(proposed.count == 1)
        #expect(proposed[0].words(in: "ru") == ["берег", "банк"])
    }

    /// What decides whether the learner is shown the choice at all: a comma that did
    /// nothing needs no confirming.
    @Test func onlyAnEntryWithSynonymsNeedsConfirming() {
        #expect(SenseEntry.proposals(english("fox"), russian("лиса, лисица"))[0].hasSynonyms)
        #expect(SenseEntry.proposals(english("lorry, truck"), russian("грузовик"))[0].hasSynonyms)
        #expect(!SenseEntry.proposals(english("fox"), russian("лиса"))[0].hasSynonyms)
        #expect(!SenseEntry.proposals(english("fox"), russian("лиса,"))[0].hasSynonyms)
    }

    // MARK: - Splitting, the undo for the default

    /// The case the default gets wrong, and the one control that fixes it.
    @Test func splittingTurnsSynonymsIntoSeparateMeanings() {
        let proposed = SenseEntry.proposals(english("bank"), russian("берег, банк"))
        #expect(proposed.count == 1, "precondition: the default keeps one meaning")

        let split = SenseEntry.splitting(proposed, at: 0)

        #expect(split.count == 2)
        #expect(split[0].words(in: "ru") == ["берег"])
        #expect(split[1].words(in: "ru") == ["банк"])
        // The word being defined belongs to both meanings — that is what makes it one word
        // with two senses rather than two unrelated rows.
        #expect(split.allSatisfy { $0.words(in: "en") == ["bank"] })
    }

    /// Two lists of the same length are two parallel meanings, not one crowd of four words.
    @Test func splittingPairsEqualListsInOrder() {
        let proposed = SenseEntry.proposals(english("bank, shore"), russian("банк, берег"))

        let split = SenseEntry.splitting(proposed, at: 0)

        #expect(split.count == 2)
        #expect(split[0].words(in: "en") == ["bank"])
        #expect(split[0].words(in: "ru") == ["банк"])
        #expect(split[1].words(in: "en") == ["shore"])
        #expect(split[1].words(in: "ru") == ["берег"])
    }

    /// Lists that cannot be paired are not paired *by guesswork*: the shorter side goes
    /// into every meaning, where the learner can see it and edit it, rather than inventing
    /// a correspondence the text does not carry.
    @Test func splittingSharesTheShorterSideRatherThanGuessing() {
        let proposed = SenseEntry.proposals(english("bank, shore, coast"), russian("банк, берег"))

        let split = SenseEntry.splitting(proposed, at: 0)

        #expect(split.count == 3)
        #expect(split.map { $0.words(in: "en") } == [["bank"], ["shore"], ["coast"]])
        #expect(split.allSatisfy { $0.words(in: "ru") == ["банк", "берег"] })
    }

    @Test func thereIsNothingToSplitInAMeaningSaidOnce() {
        let proposed = SenseEntry.proposals(english("fox"), russian("лиса"))

        #expect(SenseEntry.splitting(proposed, at: 0) == proposed)
        #expect(SenseEntry.splitting(proposed, at: 7) == proposed)
    }

    /// Splitting one meaning leaves its neighbours alone and in place.
    @Test func splittingReplacesOnlyTheMeaningItIsGiven() {
        let proposals = [
            SenseEntry(terms: [Term.Draft("cat", in: "en"), Term.Draft("кот", in: "ru")]),
            SenseEntry(terms: [Term.Draft("bank", in: "en"),
                               Term.Draft("берег", in: "ru"), Term.Draft("банк", in: "ru")]),
        ]

        let split = SenseEntry.splitting(proposals, at: 1)

        #expect(split.count == 3)
        #expect(split[0].words(in: "ru") == ["кот"], "the meaning above is untouched")
        #expect(split[1].words(in: "ru") == ["берег"])
        #expect(split[2].words(in: "ru") == ["банк"])
    }

    /// Split then merge is a round trip — the two controls are each other's undo.
    @Test func mergingUndoesSplitting() {
        let proposed = SenseEntry.proposals(english("fox"), russian("лиса, лисица"))

        let split = SenseEntry.splitting(proposed, at: 0)
        let merged = SenseEntry.merging(split, at: 1)

        #expect(merged == proposed)
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
        let separate = SenseEntry.splitting(
            SenseEntry.proposals(english("fox"), russian("лиса, лисица")), at: 0)
        #expect(separate.count == 2, "precondition: they were separated first")

        let merged = SenseEntry.merging(separate, at: 1)

        #expect(merged.count == 1)
        #expect(merged[0].words(in: "ru") == ["лиса", "лисица"])
        // The shared word must not arrive twice just because both halves carried it.
        #expect(merged[0].words(in: "en") == ["fox"])
    }

    /// The de-duplication has to hold on the language *subtag*, or a proposal assembled from
    /// "en" and "en-US" drafts keeps two rows spelled the same inside one meaning — the very
    /// thing it is there to stop.
    @Test func mergingDropsADuplicateWrittenInAVarietyOfTheSameLanguage() {
        let proposals = [
            SenseEntry(terms: [Term.Draft("bank", in: "en"), Term.Draft("берег", in: "ru")]),
            SenseEntry(terms: [Term.Draft("bank", in: "en-US"), Term.Draft("банк", in: "ru")]),
        ]

        let merged = SenseEntry.merging(proposals, at: 1)

        #expect(merged.count == 1)
        #expect(merged[0].words(in: "en") == ["bank"])
        #expect(merged[0].words(in: "ru") == ["берег", "банк"])
    }

    /// Rows are addressed by position, because two rows of one meaning can say the same
    /// word and "the first one spelled like that" is then the wrong row.
    @Test func aWordIsFoundByItsPlaceInItsLanguage() {
        let entry = SenseEntry(terms: [Term.Draft("bank", in: "en"),
                                       Term.Draft("берег", in: "ru"),
                                       Term.Draft("банк", in: "ru")])

        #expect(entry.position(ofWordAt: 0, in: "ru") == 1)
        #expect(entry.position(ofWordAt: 1, in: "ru") == 2)
        #expect(entry.position(ofWordAt: 0, in: "en") == 0)
        #expect(entry.position(ofWordAt: 2, in: "ru") == nil)
    }

    @Test func mergingTheFirstMeaningDoesNothing() {
        let separate = SenseEntry.splitting(
            SenseEntry.proposals(english("bank"), russian("берег, банк")), at: 0)

        #expect(SenseEntry.merging(separate, at: 0) == separate)
        #expect(SenseEntry.merging(separate, at: 7) == separate)
    }

    // MARK: - The word split, used where meanings must not be created

    /// The meaning editor adds words to a meaning that already exists, so a comma there can
    /// only mean synonyms — splitting a stored meaning would strand its `ReviewEvent` log.
    @Test func typedTextSplitsIntoWords() {
        #expect(SenseEntry.words(in: "лиса, лисица") == ["лиса", "лисица"])
        #expect(SenseEntry.words(in: "лиса") == ["лиса"])
        #expect(SenseEntry.words(in: "  ,  ").isEmpty)
    }
}
