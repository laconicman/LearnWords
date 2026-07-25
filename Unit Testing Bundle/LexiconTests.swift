//
//  LexiconTests.swift
//  Unit Testing Bundle
//
//  TD-13 iteration 2: the store. Where iteration 1 tested the *schema*, these test the
//  behaviour built on it — dedup, sharing, deletion policy, and the append-only log.
//
//  Every case runs against a throwaway in-memory stack, so they are fast and isolated.
//

import Testing
import CoreData
@testable import LearnWords

// @MainActor for the same reason as the schema tests: `Lexicon` reads on the view
// context, which is main-queue-confined.
@MainActor
struct LexiconTests {

    private func makeLexicon() -> Lexicon {
        Lexicon(persistence: LWPersistence(inMemory: true))
    }

    /// A set with one meaning in it, the arrangement most tests need.
    private func makeStocked(_ lexicon: Lexicon) throws -> (set: WordSet, sense: Sense) {
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        let sense = try lexicon.addSense(to: set.id,
                                         terms: [Term.Draft("bear", in: "en"),
                                                 Term.Draft("медведь", in: "ru")])
        return (set, sense)
    }

    // MARK: - Word sets

    @Test func aNewLexiconIsEmpty() throws {
        let lexicon = makeLexicon()
        #expect(lexicon.isEmpty)
        #expect(try lexicon.wordSets().isEmpty)
    }

    @Test func addingASetMakesItReadableBack() throws {
        let lexicon = makeLexicon()
        let created = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])

        let sets = try lexicon.wordSets()
        #expect(sets.count == 1)
        #expect(sets.first?.name == "Animals")
        #expect(sets.first?.languages == ["en", "ru"], "sorted for stable display")
        #expect(sets.first?.senseCount == 0)
        #expect(sets.first?.id == created.id)
        #expect(lexicon.isEmpty == false)
    }

    @Test func renamingASetKeepsItsIdentityAndContents() throws {
        let lexicon = makeLexicon()
        let (set, _) = try makeStocked(lexicon)

        try lexicon.renameWordSet(set.id, to: "Fauna")

        #expect(try lexicon.wordSet(set.id)?.name == "Fauna")
        #expect(try lexicon.senses(in: set.id).count == 1, "renaming is not a rebuild")
    }

    @Test func setsComeBackNewestFirst() throws {
        let lexicon = makeLexicon()
        _ = try lexicon.addWordSet(named: "First")
        _ = try lexicon.addWordSet(named: "Second")
        #expect(try lexicon.wordSets().map(\.name) == ["Second", "First"])
    }

    @Test func askingForAMissingSetThrows() throws {
        let lexicon = makeLexicon()
        #expect(try lexicon.wordSet(UUID()) == nil)
        #expect(throws: LexiconError.self) { try lexicon.senses(in: UUID()) }
    }

    // MARK: - Senses and terms

    @Test func aSenseCarriesEveryWordThatExpressesIt() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals")
        let sense = try lexicon.addSense(to: set.id,
                                         terms: [Term.Draft("fox", in: "en"),
                                                 Term.Draft("лиса", in: "ru"),
                                                 Term.Draft("лисица", in: "ru")],
                                         note: "the animal",
                                         tags: ["domain:nature"])

        #expect(sense.note == "the animal")
        #expect(sense.tags == ["domain:nature"])
        #expect(sense.terms(in: "en").map(\.text) == ["fox"])
        // Synonyms: both are correct answers — the point of the redesign.
        #expect(sense.terms(in: "ru").map(\.text) == ["лиса", "лисица"])
        #expect(sense.languages == ["en", "ru"])
    }

    /// The set learns its languages from the words put into it, so a set created without
    /// any still ends up covering what it holds.
    @Test func addingWordsWidensTheSetsLanguages() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals")
        #expect(try lexicon.wordSet(set.id)?.languages == [])

        try lexicon.addSense(to: set.id, terms: [Term.Draft("bear", in: "en"),
                                                 Term.Draft("Bär", in: "de")])

        #expect(try lexicon.wordSet(set.id)?.languages == ["de", "en"])
    }

    /// The heart of the atomic-term design: the same word used twice is one row, so
    /// editing it edits it everywhere.
    @Test func theSameWordIsStoredOnceAndShared() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals")
        let animal = try lexicon.addSense(to: set.id, terms: [Term.Draft("bear", in: "en"),
                                                              Term.Draft("медведь", in: "ru")])
        let carry = try lexicon.addSense(to: set.id, terms: [Term.Draft("bear", in: "en"),
                                                             Term.Draft("нести", in: "ru")])

        let bearInAnimal = try #require(animal.terms(in: "en").first)
        let bearInCarry = try #require(carry.terms(in: "en").first)
        #expect(bearInAnimal.id == bearInCarry.id, "one word, two meanings — not two rows")

        try lexicon.updateTerm(bearInAnimal.id, text: "bear (n)")

        let senses = try lexicon.senses(in: set.id)
        #expect(senses.allSatisfy { $0.terms(in: "en").first?.text == "bear (n)" },
                "editing the shared word updates every meaning that uses it")
    }

    /// Same spelling, different language, is a different word — "sale" is not French for
    /// "sale". Dedup must be by (text, language), not text alone.
    @Test func sameSpellingInAnotherLanguageIsADifferentWord() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Faux amis")
        let sense = try lexicon.addSense(to: set.id, terms: [Term.Draft("sale", in: "en"),
                                                             Term.Draft("sale", in: "fr")])
        #expect(sense.terms.count == 2)
        #expect(Set(sense.terms.map(\.id)).count == 2)
    }

    @Test func aWordCanBeAddedToAnExistingMeaningLater() throws {
        let lexicon = makeLexicon()
        let (set, sense) = try makeStocked(lexicon)

        let widened = try lexicon.addTerm(Term.Draft("Bär", in: "de"), to: sense.id)

        #expect(widened.languages == ["de", "en", "ru"])
        #expect(try lexicon.wordSet(set.id)?.languages == ["de", "en", "ru"],
                "the holding set covers the new language too")
    }

    @Test func aMissingTranscriptionIsFilledInByALaterAdd() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals")
        try lexicon.addSense(to: set.id, terms: [Term.Draft("bear", in: "en")])
        try lexicon.addSense(to: set.id,
                             terms: [Term.Draft("bear", in: "en", transcription: "bɛə")])

        let terms = try lexicon.findTerms(matching: "bear")
        #expect(terms.count == 1, "still one word")
        #expect(terms.first?.transcription == "bɛə")
    }

    // MARK: - Practice selection

    @Test func onlyMeaningsWithBothSidesArePractisable() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals")
        try lexicon.addSense(to: set.id, terms: [Term.Draft("bear", in: "en"),
                                                 Term.Draft("медведь", in: "ru")])
        // Half-entered: no Russian side yet, so it cannot be asked en→ru.
        try lexicon.addSense(to: set.id, terms: [Term.Draft("camel", in: "en")])

        let practisable = try lexicon.senses(in: set.id, from: "en", to: "ru")
        #expect(practisable.count == 1)
        #expect(practisable.first?.terms(in: "en").first?.text == "bear")
        #expect(try lexicon.senses(in: set.id).count == 2, "both are still in the set")
    }

    // MARK: - Sharing and deletion

    @Test func aMeaningCanLiveInSeveralSetsAndSurvivesOneBeingDeleted() throws {
        let lexicon = makeLexicon()
        let animals = try lexicon.addWordSet(named: "Animals")
        let forest = try lexicon.addWordSet(named: "Forest")
        let sense = try lexicon.addSense(to: animals.id, terms: [Term.Draft("bear", in: "en"),
                                                                 Term.Draft("медведь", in: "ru")])
        try lexicon.addSense(to: forest.id, terms: [Term.Draft("bear", in: "en"),
                                                    Term.Draft("медведь", in: "ru")])

        try lexicon.deleteWordSet(animals.id)

        #expect(try lexicon.wordSets().map(\.name) == ["Forest"])
        #expect(try lexicon.senses(in: forest.id).count == 1, "the other set keeps its content")
        _ = sense
    }

    @Test func removingFromASetLeavesTheMeaningElsewhere() throws {
        let lexicon = makeLexicon()
        let (set, sense) = try makeStocked(lexicon)
        let other = try lexicon.addWordSet(named: "Forest")
        // Same words → same terms; a second sense row, deliberately.
        let shared = try lexicon.addSense(to: other.id, terms: [Term.Draft("bear", in: "en"),
                                                                Term.Draft("медведь", in: "ru")])

        try lexicon.removeSense(sense.id, from: set.id)

        #expect(try lexicon.senses(in: set.id).isEmpty)
        #expect(try lexicon.senses(in: other.id).map(\.id) == [shared.id])
    }

    /// Orphan collection is explicit and refuses to touch anything with history — the
    /// effort index must not fall because a set was reorganised.
    @Test func orphanCollectionSparesMeaningsThatCarryHistory() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals")
        let plain = try lexicon.addSense(to: set.id, terms: [Term.Draft("camel", in: "en"),
                                                             Term.Draft("верблюд", in: "ru")])
        let practised = try lexicon.addSense(to: set.id, terms: [Term.Draft("bear", in: "en"),
                                                                 Term.Draft("медведь", in: "ru")])
        try lexicon.record(draft(sense: practised, set: set))

        try lexicon.deleteWordSet(set.id)
        let collected = try lexicon.deleteOrphanedSenses()

        #expect(collected == 1, "only the one with no history")
        #expect(try lexicon.history(ofSense: practised.id).count == 1)
        _ = plain
    }

    // MARK: - Review log

    private func draft(sense: Sense, set: WordSet,
                       session: UUID = UUID(),
                       outcome: ReviewOutcome = .correctVerbatim,
                       response: String? = nil,
                       latencyMS: Int? = nil,
                       errorTags: [String] = []) -> ReviewEvent.Draft {
        ReviewEvent.Draft(senseID: sense.id,
                          sessionID: session,
                          wordSetID: set.id,
                          promptTermID: sense.terms(in: "en").first?.id ?? UUID(),
                          task: .dictation,
                          direction: .productive,
                          outcome: outcome,
                          prompt: "bear",
                          expected: "медведь",
                          promptLanguage: "en",
                          answerLanguage: "ru",
                          response: response,
                          latencyMS: latencyMS,
                          errorTags: errorTags)
    }

    @Test func anAnswerIsRecordedWithEverythingNeededToScoreItLater() throws {
        let lexicon = makeLexicon()
        let (set, sense) = try makeStocked(lexicon)
        let session = UUID()

        try lexicon.record(draft(sense: sense, set: set, session: session,
                                 outcome: .correctJudged, response: "медветь",
                                 latencyMS: 2_450, errorTags: ["consonant-voicing"]))

        let history = try lexicon.history(ofSense: sense.id)
        let event = try #require(history.first)
        #expect(event.outcome == .correctJudged)
        #expect(event.task == .dictation)
        #expect(event.direction == .productive)
        #expect(event.response == "медветь")
        #expect(event.expected == "медведь")
        #expect(event.latencyMS == 2_450)
        #expect(event.errorTags == ["consonant-voicing"])
        #expect(event.sessionID == session)
        #expect(event.schemaVersion == CDReviewEvent.currentSchemaVersion)
    }

    /// Absence stays absence: a self-assessed answer has no response and no latency, and
    /// those must not read back as "" and 0.
    @Test func unrecordedResponseAndLatencyStayNil() throws {
        let lexicon = makeLexicon()
        let (set, sense) = try makeStocked(lexicon)

        try lexicon.record(draft(sense: sense, set: set, outcome: .selfAssessedKnown))

        let event = try #require(try lexicon.history(ofSense: sense.id).first)
        #expect(event.response == nil)
        #expect(event.latencyMS == nil)
    }

    @Test func historyReadsBackOldestFirstAndPerSitting() throws {
        let lexicon = makeLexicon()
        let (set, sense) = try makeStocked(lexicon)
        let morning = UUID(), evening = UUID()

        try lexicon.record(draft(sense: sense, set: set, session: morning, outcome: .incorrect))
        try lexicon.record(draft(sense: sense, set: set, session: morning, outcome: .correctVerbatim))
        try lexicon.record(draft(sense: sense, set: set, session: evening, outcome: .correctVerbatim))

        #expect(try lexicon.history(ofSense: sense.id).count == 3)
        #expect(try lexicon.history(ofSession: morning).count == 2,
                "the sitting is the unit that separates a retry from fresh evidence")
        #expect(try lexicon.history(ofSession: evening).count == 1)

        let dates = try lexicon.history(ofSense: sense.id).map(\.date)
        #expect(dates == dates.sorted(), "oldest first")
    }

    /// Deleting the words must not delete the evidence that they were practised.
    @Test func deletingAMeaningKeepsItsHistoryReadable() throws {
        let lexicon = makeLexicon()
        let (set, sense) = try makeStocked(lexicon)
        let session = UUID()
        try lexicon.record(draft(sense: sense, set: set, session: session))

        try lexicon.deleteSense(sense.id)

        #expect(try lexicon.senses(in: set.id).isEmpty)
        let survivors = try lexicon.history(ofSession: session)
        #expect(survivors.count == 1)
        #expect(survivors.first?.expected == "медведь", "the snapshot keeps it judgeable")
    }

    @Test func recordingAgainstAMissingMeaningThrows() throws {
        let lexicon = makeLexicon()
        let (set, sense) = try makeStocked(lexicon)
        try lexicon.deleteSense(sense.id)

        #expect(throws: LexiconError.self) {
            try lexicon.record(draft(sense: sense, set: set))
        }
    }

    // MARK: - Search

    @Test func searchFindsWordsByPrefixInAnyLanguage() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals")
        try lexicon.addSense(to: set.id, terms: [Term.Draft("bear", in: "en"),
                                                 Term.Draft("медведь", in: "ru")])
        try lexicon.addSense(to: set.id, terms: [Term.Draft("beaver", in: "en"),
                                                 Term.Draft("бобр", in: "ru")])

        #expect(try lexicon.findTerms(matching: "bea").map(\.text) == ["bear", "beaver"])
        #expect(try lexicon.findTerms(matching: "мед").map(\.text) == ["медведь"])
        #expect(try lexicon.findTerms(matching: "").isEmpty, "an empty query is not a wildcard")
    }

    // MARK: - Seed

    @Test func seedingFillsAnEmptyLexiconOnceOnly() throws {
        let lexicon = makeLexicon()

        let seeded = try #require(try LexiconSeed.populateIfEmpty(lexicon))
        #expect(seeded.senseCount == LexiconSeed.words.count)
        #expect(seeded.languages == ["en", "ru"])

        // Safe to call on every launch.
        #expect(try LexiconSeed.populateIfEmpty(lexicon) == nil)
        #expect(try lexicon.wordSets().count == 1)
    }

    /// Everything else here runs in memory, which never exercises the SQLite store the
    /// app actually ships — the store where indexes, Spotlight and (later) CloudKit live.
    /// This one writes a real file, reads it back through a *fresh* stack, and deletes it.
    @Test func aRealSQLiteStorePersistsAcrossStacks() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LexiconTest-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: url.deletingPathExtension()
                        .appendingPathExtension("sqlite\(suffix)"))
            }
        }

        let setID: UUID
        do {
            let lexicon = Lexicon(persistence: LWPersistence(storeAt: url))
            let set = try LexiconSeed.populate(lexicon)
            setID = set.id
        }

        // A brand-new stack over the same file: proves the write reached disk, not just
        // a context.
        let reopened = Lexicon(persistence: LWPersistence(storeAt: url))
        let set = try #require(try reopened.wordSet(setID))
        #expect(set.senseCount == LexiconSeed.words.count)
        #expect(try reopened.senses(in: setID, from: "en", to: "ru").count
                == LexiconSeed.words.count)
    }

    @Test func theSeedIncludesSynonymsSoThePayoffIsVisibleImmediately() throws {
        let lexicon = makeLexicon()
        let set = try LexiconSeed.populate(lexicon)

        let senses = try lexicon.senses(in: set.id)
        let run = try #require(senses.first { $0.terms(in: "en").first?.text == "run" })
        #expect(run.terms(in: "ru").map(\.text) == ["бегать", "бежать"])
        #expect(senses.allSatisfy { $0.canPractise(from: "en", to: "ru") })
    }
}
