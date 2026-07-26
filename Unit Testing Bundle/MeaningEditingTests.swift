//
//  MeaningEditingTests.swift
//  Unit Testing Bundle
//
//  The store operations behind the meaning editor.
//
//  These are what made the lexical redesign reachable: before them a meaning could hold
//  synonyms but nothing outside the seed could create or remove one, because `addTerm`
//  and `removeTerm` were called from no screen and `removeTerm`/`updateSense` did not
//  exist on `Lexicon` at all.
//

import Testing
import Foundation
@testable import LearnWords

@MainActor
struct MeaningEditingTests {

    private func makeLexicon() -> Lexicon {
        Lexicon(persistence: LWPersistence(inMemory: true))
    }

    private func stocked(_ lexicon: Lexicon) throws -> (set: WordSet, sense: Sense) {
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        let sense = try lexicon.addSense(to: set.id, terms: [Term.Draft("fox", in: "en"),
                                                             Term.Draft("лиса", in: "ru")])
        return (set, sense)
    }

    // MARK: - Adding

    @Test func aSynonymJoinsTheMeaningItAlreadyHas() throws {
        let lexicon = makeLexicon()
        let (_, sense) = try stocked(lexicon)

        let updated = try lexicon.addTerm(Term.Draft("лисица", in: "ru"), to: sense.id)

        #expect(Set(updated.terms(in: "ru").map(\.text)) == ["лиса", "лисица"])
        #expect(updated.id == sense.id, "a synonym is not a new meaning")
    }

    /// A third language is another question, not another schema — the payoff of the
    /// language-tuple model.
    @Test func addingAWordInANewLanguageWidensEverySetHoldingTheMeaning() throws {
        let lexicon = makeLexicon()
        let (set, sense) = try stocked(lexicon)

        try lexicon.addTerm(Term.Draft("Fuchs", in: "de"), to: sense.id)

        #expect(try lexicon.wordSet(set.id)?.languages == ["de", "en", "ru"])
        #expect(try lexicon.senses(in: set.id, from: "de", to: "ru").count == 1)
    }

    @Test func addingAWordThatAlreadyExistsLinksItRatherThanTwinningIt() throws {
        let lexicon = makeLexicon()
        let (set, first) = try stocked(lexicon)
        let second = try lexicon.addSense(to: set.id, terms: [Term.Draft("cunning", in: "en"),
                                                              Term.Draft("хитрый", in: "ru")])

        try lexicon.addTerm(Term.Draft("fox", in: "en"), to: second.id)

        // One "fox" row, on two meanings — that is what makes a word atomic (TD-18).
        #expect(try lexicon.findTerms(matching: "fox").count == 1)
        let foxID = try #require(try lexicon.sense(first.id)?
            .terms(in: "en").first { $0.text == "fox" }?.id)
        #expect(try lexicon.sense(second.id)?
            .terms(in: "en").first { $0.text == "fox" }?.id == foxID)
    }

    // MARK: - Removing

    @Test func removingASynonymLeavesTheMeaningAndTheWordAlone() throws {
        let lexicon = makeLexicon()
        let (set, sense) = try stocked(lexicon)
        let other = try lexicon.addSense(to: set.id, terms: [Term.Draft("fox", in: "en"),
                                                             Term.Draft("лис", in: "ru")])
        let fox = try #require(try lexicon.sense(sense.id)?.terms(in: "en").first)

        let updated = try lexicon.removeTerm(fox.id, from: sense.id)

        #expect(updated.terms(in: "en").isEmpty, "off this meaning")
        #expect(try lexicon.sense(other.id)?.terms(in: "en").map(\.text) == ["fox"],
                "still on the other meaning — unlinked, not deleted")
        #expect(try lexicon.findTerms(matching: "fox").count == 1)
    }

    /// A meaning expressed by nothing is not a meaning. Silently deleting the sense
    /// instead would be a surprise, so it refuses and says why.
    @Test func theLastWordCannotBeRemoved() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en"])
        let sense = try lexicon.addSense(to: set.id, terms: [Term.Draft("fox", in: "en")])
        let fox = try #require(sense.terms.first)

        #expect(throws: LexiconError.lastTerm) {
            try lexicon.removeTerm(fox.id, from: sense.id)
        }
        #expect(try lexicon.sense(sense.id)?.terms.count == 1)
    }

    @Test func removingAWordThatIsNotOnTheMeaningThrows() throws {
        let lexicon = makeLexicon()
        let (_, sense) = try stocked(lexicon)

        #expect(throws: LexiconError.notFound) {
            try lexicon.removeTerm(UUID(), from: sense.id)
        }
    }

    // MARK: - Notes

    @Test func aNoteIsSetClearedAndTrimmed() throws {
        let lexicon = makeLexicon()
        let (_, sense) = try stocked(lexicon)

        try lexicon.updateSense(sense.id, note: "  the animal  ")
        #expect(try lexicon.sense(sense.id)?.note == "the animal")

        // Empty means "no note", not a note that is the empty string.
        try lexicon.updateSense(sense.id, note: "   ")
        #expect(try lexicon.sense(sense.id)?.note == nil)
    }

    // MARK: - Renaming

    @Test func renamingASetKeepsItsContents() throws {
        let lexicon = makeLexicon()
        let (set, _) = try stocked(lexicon)

        try lexicon.renameWordSet(set.id, to: "Wildlife")

        #expect(try lexicon.wordSet(set.id)?.name == "Wildlife")
        #expect(try lexicon.senses(in: set.id).count == 1)
    }

    // MARK: - Orphan collection

    /// Explicit, never automatic — same policy as `deleteOrphanedSenses`. Editing must not
    /// quietly delete rows a review event still names.
    @Test func orphanedWordsAreCollectedOnlyWhenAsked() throws {
        let lexicon = makeLexicon()
        let (set, sense) = try stocked(lexicon)
        try lexicon.addTerm(Term.Draft("reynard", in: "en"), to: sense.id)
        let reynard = try #require(try lexicon.sense(sense.id)?
            .terms(in: "en").first { $0.text == "reynard" })

        try lexicon.removeTerm(reynard.id, from: sense.id)
        #expect(try lexicon.findTerms(matching: "reynard").count == 1,
                "still there — removal unlinks, it does not collect")

        #expect(try lexicon.deleteOrphanedTerms() == 1)
        #expect(try lexicon.findTerms(matching: "reynard").isEmpty)
        // The words still in use are untouched.
        #expect(try lexicon.senses(in: set.id).first?.terms.count == 2)
    }

    @Test func collectingOrphansLeavesWordsThatAreStillUsed() throws {
        let lexicon = makeLexicon()
        _ = try stocked(lexicon)

        #expect(try lexicon.deleteOrphanedTerms() == 0)
    }
}

// MARK: - Read-after-write

/// A write must be visible to the very next read on the same thread.
///
/// It was not. `automaticallyMergesChangesFromParent` merges when the did-save
/// notification is delivered — the next run-loop turn for a main-queue view context —
/// and a fetch returns already-registered objects without refreshing them. So an editor
/// that writes and immediately re-reads saw the *previous* values, and a second edit to
/// the same field appeared to do nothing at all. `LWPersistence.write` now merges into
/// the view context synchronously before it returns.
@MainActor
struct ReadAfterWriteTests {

    private func makeLexicon() -> Lexicon {
        Lexicon(persistence: LWPersistence(inMemory: true))
    }

    @Test func repeatedEditsToTheSameFieldAllLand() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        let sense = try lexicon.addSense(to: set.id, terms: [Term.Draft("fox", in: "en"),
                                                             Term.Draft("лиса", in: "ru")])

        try lexicon.updateSense(sense.id, note: "the animal")
        #expect(try lexicon.sense(sense.id)?.note == "the animal")

        try lexicon.updateSense(sense.id, note: "the cunning one")
        #expect(try lexicon.sense(sense.id)?.note == "the cunning one",
                "the second edit must land, not silently keep the first")

        try lexicon.updateSense(sense.id, note: nil)
        #expect(try lexicon.sense(sense.id)?.note == nil, "and clearing must land too")
    }

    @Test func aRenameIsVisibleImmediately() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en"])

        #expect(try lexicon.wordSet(set.id)?.name == "Animals")
        try lexicon.renameWordSet(set.id, to: "Wildlife")
        #expect(try lexicon.wordSet(set.id)?.name == "Wildlife")
        try lexicon.renameWordSet(set.id, to: "Fauna")
        #expect(try lexicon.wordSet(set.id)?.name == "Fauna")
    }

    @Test func anEditedWordReadsBackChangedEveryTime() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        let sense = try lexicon.addSense(to: set.id, terms: [Term.Draft("fox", in: "en"),
                                                             Term.Draft("лиса", in: "ru")])
        let fox = try #require(sense.terms.first { $0.language == "en" })

        try lexicon.updateTerm(fox.id, text: "reynard")
        #expect(try lexicon.sense(sense.id)?.terms(in: "en").map(\.text) == ["reynard"])
        try lexicon.updateTerm(fox.id, text: "vixen")
        #expect(try lexicon.sense(sense.id)?.terms(in: "en").map(\.text) == ["vixen"])
    }

    /// Adding a word must show up in the set's list, not just in the returned snapshot.
    @Test func anAddedMeaningAppearsInTheNextListing() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])

        #expect(try lexicon.senses(in: set.id).isEmpty)
        try lexicon.addSense(to: set.id, terms: [Term.Draft("fox", in: "en"),
                                                 Term.Draft("лиса", in: "ru")])
        #expect(try lexicon.senses(in: set.id).count == 1)
        try lexicon.addSense(to: set.id, terms: [Term.Draft("bear", in: "en"),
                                                 Term.Draft("медведь", in: "ru")])
        #expect(try lexicon.senses(in: set.id).count == 2)
    }
}
