//
//  StoreDeduplicatorTests.swift
//  Unit Testing Bundle
//
//  What happens when two devices independently create the same row.
//
//  CloudKit forbids unique constraints, so `Lexicon` enforces uniqueness in code — which
//  holds inside one store and cannot hold across two. These tests build the situation
//  directly (insert the duplicates a merge would have produced) rather than waiting for a
//  real sync, so the repair is verifiable without an iCloud account or a second device.
//
//  The property that matters most is `theSameWinnerIsChosenEverywhere`: if two devices
//  disagree about which row survives, each deletes the row the other kept, both deletions
//  sync, and the data is gone.
//

import Testing
import CoreData
@testable import LearnWords

@MainActor
struct StoreDeduplicatorTests {

    private func makeStack() -> (LWPersistence, Lexicon) {
        let persistence = LWPersistence(inMemory: true)
        return (persistence, Lexicon(persistence: persistence))
    }

    private func count(_ entity: String, in persistence: LWPersistence) throws -> Int {
        try persistence.viewContext.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: entity))
    }

    /// Inserts a row directly, bypassing `Lexicon`'s find-or-create — which is exactly what
    /// the *other* device did before the merge.
    private func insertLanguage(_ code: String, in persistence: LWPersistence) throws -> UUID {
        var id = UUID()
        try persistence.write { context in
            let language = CDLanguage(context: context)
            language.code = code
            id = language.id
        }
        return id
    }

    // MARK: - Languages

    @Test func twoDevicesCreatingOneLanguageEndWithOneRow() throws {
        let (persistence, lexicon) = makeStack()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        try lexicon.addSense(to: set.id, terms: [Term.Draft("bear", in: "en"),
                                                 Term.Draft("медведь", in: "ru")])
        _ = try insertLanguage("en", in: persistence)
        #expect(try count("Language", in: persistence) == 3, "precondition: the merge duplicated en")

        #expect(try StoreDeduplicator.run(in: persistence.container) == 1)
        #expect(try count("Language", in: persistence) == 2)
    }

    /// The damage this prevents: words attached to the losing `en` row would vanish from
    /// practice, because a sitting asks for terms in one language row's worth of words.
    @Test func wordsSurviveTheirLanguageBeingMerged() throws {
        let (persistence, lexicon) = makeStack()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        try lexicon.addSense(to: set.id, terms: [Term.Draft("bear", in: "en"),
                                                 Term.Draft("медведь", in: "ru")])

        // A second "en", with a word of its own — the state a merge produces.
        try persistence.write { context in
            let language = CDLanguage(context: context)
            language.code = "en"
            let term = CDTerm(context: context)
            term.text = "camel"
            term.language = language
        }

        try StoreDeduplicator.run(in: persistence.container)

        let terms = try lexicon.findTerms(matching: "")
            + lexicon.findTerms(matching: "camel") + lexicon.findTerms(matching: "bear")
        let english = Set(terms.filter { $0.language == "en" }.map(\.text))
        #expect(english == ["bear", "camel"], "both words hang off the surviving row")
        #expect(try count("Language", in: persistence) == 2)
    }

    @Test func theSetStillCoversItsLanguagesAfterAMerge() throws {
        let (persistence, lexicon) = makeStack()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        _ = try insertLanguage("en", in: persistence)

        try StoreDeduplicator.run(in: persistence.container)
        #expect(try lexicon.wordSet(set.id)?.languages == ["en", "ru"])
    }

    /// **The convergence property.** Two devices must pick the same survivor, or each
    /// deletes what the other kept and the row disappears from both.
    @Test func theSameWinnerIsChosenEverywhere() throws {
        let (persistence, _) = makeStack()
        var ids: [UUID] = []
        for _ in 0..<5 { ids.append(try insertLanguage("de", in: persistence)) }

        try StoreDeduplicator.run(in: persistence.container)

        let request = CDLanguage.fetchRequest()
        request.predicate = NSPredicate(format: "code ==[c] %@", "de")
        let survivors = try persistence.viewContext.fetch(request)
        #expect(survivors.count == 1)
        #expect(survivors.first?.id == ids.min(by: { $0.uuidString < $1.uuidString }),
                "lowest id wins — the one rule every device can apply without coordinating")
    }

    // MARK: - Terms

    @Test func theSameWordInTheSameLanguageCollapsesToOneTerm() throws {
        let (persistence, lexicon) = makeStack()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        let sense = try lexicon.addSense(to: set.id, terms: [Term.Draft("bear", in: "en"),
                                                             Term.Draft("медведь", in: "ru")])

        // The other device's "bear", on its own duplicate "en".
        try persistence.write { context in
            let language = CDLanguage(context: context)
            language.code = "en"
            let term = CDTerm(context: context)
            term.text = "bear"
            term.language = language
            let request = CDSynset.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", sense.id as CVarArg)
            try context.fetch(request).first?.addTerm(term)
        }

        try StoreDeduplicator.run(in: persistence.container)

        #expect(try count("Term", in: persistence) == 2, "bear and медведь, once each")
        let terms = try lexicon.senses(in: set.id).first?.terms(in: "en") ?? []
        #expect(terms.map(\.text) == ["bear"], "the meaning is not answered by two identical words")
    }

    /// Language is merged before Term, because a term's identity includes its language —
    /// comparing against un-merged language rows would call two "bear"s distinct.
    @Test func aTermIsJudgedAgainstTheMergedLanguage() throws {
        let (persistence, lexicon) = makeStack()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en"])
        try lexicon.addSense(to: set.id, terms: [Term.Draft("bear", in: "en")])
        try persistence.write { context in
            let language = CDLanguage(context: context)
            language.code = "en"
            let term = CDTerm(context: context)
            term.text = "bear"
            term.language = language
        }

        try StoreDeduplicator.run(in: persistence.container)
        #expect(try count("Term", in: persistence) == 1)
    }

    @Test func wordsThatOnlyLookAlikeAreLeftAlone() throws {
        let (persistence, lexicon) = makeStack()
        let set = try lexicon.addWordSet(named: "Mixed", languages: ["en", "de"])
        // Same spelling, different languages: two words, and they must stay two.
        try lexicon.addSense(to: set.id, terms: [Term.Draft("Rat", in: "en"),
                                                 Term.Draft("Rat", in: "de")])

        #expect(try StoreDeduplicator.run(in: persistence.container) == 0)
        #expect(try count("Term", in: persistence) == 2)
    }

    // MARK: - Tags and error tags

    @Test func tagsAndErrorTagsMergeToo() throws {
        let (persistence, _) = makeStack()
        try persistence.write { context in
            for _ in 0..<2 {
                let tag = CDTag(context: context)
                tag.name = "slang"
                let errorTag = CDErrorTag(context: context)
                errorTag.name = "gender"
            }
        }

        #expect(try StoreDeduplicator.run(in: persistence.container) == 2)
        #expect(try count("Tag", in: persistence) == 1)
        #expect(try count("ErrorTag", in: persistence) == 1)
    }

    @Test func anEventKeepsItsErrorTagAcrossAMerge() throws {
        let (persistence, _) = makeStack()
        try persistence.write { context in
            let keep = CDErrorTag(context: context)
            keep.name = "gender"
            let duplicate = CDErrorTag(context: context)
            duplicate.name = "gender"
            let event = CDReviewEvent(context: context)
            // The three non-optional UUIDs Core Data cannot default (it ignores
            // `defaultValueString` on UUID attributes) and the call site must supply.
            event.sessionID = UUID()
            event.wordSetID = UUID()
            event.promptTermID = UUID()
            event.addErrorTag(duplicate)
        }

        try StoreDeduplicator.run(in: persistence.container)

        #expect(try count("ErrorTag", in: persistence) == 1)
        let events = try persistence.viewContext.fetch(CDReviewEvent.fetchRequest())
        #expect(events.first?.sortedErrorTags.map(\.name) == ["gender"],
                "the event follows its tag to the surviving row")
    }

    // MARK: - Doing nothing, safely

    @Test func aCleanStoreIsLeftUntouched() throws {
        let (persistence, lexicon) = makeStack()
        let set = try LexiconSeed.populate(lexicon)

        #expect(try StoreDeduplicator.run(in: persistence.container) == 0)
        #expect(try lexicon.senses(in: set.id).count == 9)
    }

    @Test func mergingTwiceChangesNothingTheSecondTime() throws {
        let (persistence, lexicon) = makeStack()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        try lexicon.addSense(to: set.id, terms: [Term.Draft("bear", in: "en"),
                                                 Term.Draft("медведь", in: "ru")])
        _ = try insertLanguage("en", in: persistence)

        #expect(try StoreDeduplicator.run(in: persistence.container) == 1)
        #expect(try StoreDeduplicator.run(in: persistence.container) == 0, "idempotent")
    }
}
