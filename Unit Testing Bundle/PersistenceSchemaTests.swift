//
//  PersistenceSchemaTests.swift
//  Unit Testing Bundle
//
//  TD-13 iteration 1 (redone): the lexical Core Data model from
//  docs/LexicalModelResearch.md — terms, synsets ("language tuples"), multilingual
//  sets — before anything depends on it.
//
//  In-memory store: no file, no App Group. What these pin down is the part that is
//  expensive to get wrong later — the event log is append-only, so a field that cannot
//  round-trip now can never be backfilled, and a deletion rule that eats history would
//  destroy it silently.
//

import Testing
import CoreData
@testable import LearnWords

// @MainActor: these tests drive `viewContext`, a *main-queue* context, and Swift
// Testing otherwise runs test functions on background tasks — a context-confinement
// violation (the crash was a race inside `-[NSManagedObjectContext save:]`, surfacing
// only once the many-to-many graph made relationship maintenance heavy enough to lose
// the race). Same rule as Apple's "Using Core Data in the background": use a context
// only on its own queue.
@MainActor
struct PersistenceSchemaTests {

    private func makeContext() -> NSManagedObjectContext {
        LWPersistence(inMemory: true).viewContext
    }

    // MARK: - Builders

    @discardableResult
    private func makeTerm(_ context: NSManagedObjectContext,
                          _ text: String, _ language: String) -> CDTerm {
        let term = CDTerm(context: context)
        term.id = UUID()
        term.text = text
        term.languageCode = language
        term.createdAt = Date()
        return term
    }

    @discardableResult
    private func makeSynset(_ context: NSManagedObjectContext,
                            terms: [CDTerm], note: String? = nil) -> CDSynset {
        let synset = CDSynset(context: context)
        synset.id = UUID()
        synset.note = note
        synset.createdAt = Date()
        terms.forEach(synset.addTerm)
        return synset
    }

    @discardableResult
    private func makeSet(_ context: NSManagedObjectContext,
                         name: String, languages: [String],
                         synsets: [CDSynset]) -> CDWordSet {
        let set = CDWordSet(context: context)
        set.id = UUID()
        set.name = name
        set.languageCodes = languages
        set.createdAt = Date()
        synsets.forEach(set.addSynset)
        return set
    }

    // MARK: - Model shape

    @Test func modelDefinesTheLexicalEntities() {
        let names = Set(LWPersistence.model.entities.compactMap(\.name))
        #expect(names == ["WordSet", "Synset", "Term", "Comment", "Illustration",
                          "WordForm", "Tag", "ReviewEvent"])
    }

    /// CloudKit refuses non-optional attributes without defaults, relationships without
    /// inverses, and unique constraints. The model is authored to those rules now so
    /// enabling `NSPersistentCloudKitContainer` later is a container swap, not a
    /// redesign — this test keeps it that way as entities grow.
    @Test func modelObeysCloudKitRules() {
        for entity in LWPersistence.model.entities {
            for (name, attribute) in entity.attributesByName {
                #expect(attribute.isOptional || attribute.defaultValue != nil,
                        "\(entity.name ?? "?").\(name) must be optional or have a default")
            }
            for (name, relationship) in entity.relationshipsByName {
                #expect(relationship.isOptional,
                        "\(entity.name ?? "?").\(name) must be optional")
                #expect(relationship.inverseRelationship != nil,
                        "\(entity.name ?? "?").\(name) must have an inverse")
                #expect(relationship.isOrdered == false,
                        "\(entity.name ?? "?").\(name) must be unordered — CloudKit rejects ordered relationships")
            }
            #expect(entity.uniquenessConstraints.isEmpty,
                    "\(entity.name ?? "?") must not use unique constraints — CloudKit rejects them")
        }
    }

    // MARK: - Atomic terms

    /// The core of the redesign: a word exists once and is shared — across senses and,
    /// through them, across sets. Editing it edits it everywhere; identity is the UUID,
    /// not the spelling (TD-18).
    @Test func aTermIsSharedAcrossSynsetsAndSurvivesRenaming() throws {
        let context = makeContext()
        let bear = makeTerm(context, "bear", "en")
        // Two senses of one word: the animal, and "to carry".
        let animal = makeSynset(context, terms: [bear, makeTerm(context, "медведь", "ru")],
                                note: "the animal")
        let carry = makeSynset(context, terms: [bear, makeTerm(context, "нести", "ru")],
                               note: "to carry")
        try context.save()

        let id = bear.id
        bear.text = "bear (n)"   // the rename that used to orphan everything
        try context.save()

        #expect(bear.id == id)
        #expect(bear.synsetList.count == 2)
        #expect(animal.termList.contains(bear))
        #expect(carry.termList.contains(bear))
        // One stored term, two senses — not two copies.
        #expect(try context.count(for: CDTerm.fetchRequest()) == 3)
    }

    /// «бегать» and «бежать» in one synset: several same-language terms, every one of
    /// them a valid answer — the principled version of the old "бегать, бежать" string.
    @Test func aSynsetHoldsSynonymsAndAllAreAnswers() throws {
        let context = makeContext()
        let run = makeTerm(context, "run", "en")
        let begat = makeTerm(context, "бегать", "ru")
        let bezhat = makeTerm(context, "бежать", "ru")
        let synset = makeSynset(context, terms: [run, begat, bezhat])
        try context.save()

        let answers = synset.terms(in: "ru").compactMap(\.text)
        #expect(Set(answers) == ["бегать", "бежать"])
        #expect(synset.terms(in: "en").compactMap(\.text) == ["run"])
        #expect(synset.languageCodes == ["en", "ru"])
    }

    /// Tuples, not pairs: one sense spanning three languages, in a set that declares all
    /// three. The session later picks which pair to practise.
    @Test func aSynsetAndASetSpanMoreThanTwoLanguages() throws {
        let context = makeContext()
        let synset = makeSynset(context, terms: [makeTerm(context, "bear", "en"),
                                                 makeTerm(context, "медведь", "ru"),
                                                 makeTerm(context, "Bär", "de")])
        let set = makeSet(context, name: "Animals", languages: ["en", "ru", "de"],
                          synsets: [synset])
        try context.save()

        #expect(synset.languageCodes == ["en", "ru", "de"])
        #expect(set.languageCodes == ["en", "ru", "de"])
        #expect(set.synsetList.first?.terms(in: "de").first?.text == "Bär")
    }

    /// Domain and register ride on the sense as tag *rows* — "bread = money" is slang
    /// in that *sense*, not as a word. Rows, because tags are a query dimension: this
    /// test proves the thing a `[String]` transformable blob could never do — a SQLite
    /// predicate straight into the store, and rename-in-one-place.
    @Test func tagsAreQueryableRowsSharedAcrossSenses() throws {
        let context = makeContext()
        let slang = CDTag(context: context)
        slang.id = UUID()
        slang.name = "slang"

        let bread = makeSynset(context, terms: [makeTerm(context, "bread", "en"),
                                                makeTerm(context, "деньги", "ru")],
                               note: "money, not the food")
        bread.addTag(slang)
        let grand = makeSynset(context, terms: [makeTerm(context, "grand", "en"),
                                                makeTerm(context, "штука", "ru")])
        grand.addTag(slang)
        makeSynset(context, terms: [makeTerm(context, "bear", "en")])   // untagged
        try context.save()

        // The WHERE clause the blob design made impossible.
        let request = CDSynset.fetchRequest()
        request.predicate = NSPredicate(format: "ANY tags.name == %@", "slang")
        #expect(try context.count(for: request) == 2)

        // One row per tag: rename once, both senses see it — no update anomaly.
        slang.name = "register:slang"
        try context.save()
        #expect(bread.tagList.first?.name == "register:slang")
        #expect(grand.tagList.first?.name == "register:slang")
        #expect(try context.count(for: CDTag.fetchRequest()) == 1)
    }

    @Test func aSynsetIsSharedAcrossSetsAndSurvivesSetDeletion() throws {
        let context = makeContext()
        let synset = makeSynset(context, terms: [makeTerm(context, "bear", "en"),
                                                 makeTerm(context, "медведь", "ru")])
        let animals = makeSet(context, name: "Animals", languages: ["en", "ru"], synsets: [synset])
        makeSet(context, name: "Forest", languages: ["en", "ru"], synsets: [synset])
        try context.save()

        context.delete(animals)
        try context.save()

        // Shared content is never cascaded — the other set still owns it.
        #expect(try context.count(for: CDSynset.fetchRequest()) == 1)
        #expect(try context.count(for: CDTerm.fetchRequest()) == 2)
        #expect(synset.sets?.count == 1)
    }

    // MARK: - Lexical attributes

    @Test func lexicalAttributesAndSatellitesRoundTrip() throws {
        let context = makeContext()
        let term = makeTerm(context, "make", "en")
        term.transcription = "māk"
        term.partOfSpeech = "verb"

        // Apple's d:index rows: variant forms that should reach the same entry.
        for (kind, text) in [("past", "made"), ("gerund", "making")] {
            let form = CDWordForm(context: context)
            form.id = UUID()
            form.formType = kind
            form.text = text
            form.term = term
        }
        let comment = CDComment(context: context)
        comment.id = UUID()
        comment.text = "irregular verb"
        comment.createdAt = Date()
        comment.term = term

        let illustration = CDIllustration(context: context)
        illustration.id = UUID()
        illustration.urlString = "https://example.com/make.png"
        illustration.term = term
        try context.save()

        let fetched = try #require(try context.fetch(CDTerm.fetchRequest()).first)
        #expect(fetched.transcription == "māk")
        #expect(fetched.partOfSpeech == "verb")
        #expect(Set(fetched.formList.compactMap(\.text)) == ["made", "making"])
        #expect(fetched.commentList.first?.text == "irregular verb")
        #expect(fetched.illustrationList.first?.url?.host == "example.com")
    }

    /// A term's satellites are meaningless without it — they go with it. Its synsets do
    /// not: they are shared.
    @Test func deletingATermCascadesSatellitesButNotSynsets() throws {
        let context = makeContext()
        let term = makeTerm(context, "make", "en")
        let form = CDWordForm(context: context)
        form.id = UUID()
        form.formType = "past"
        form.text = "made"
        form.term = term
        let synset = makeSynset(context, terms: [term, makeTerm(context, "делать", "ru")])
        try context.save()

        context.delete(term)
        try context.save()

        #expect(try context.count(for: CDWordForm.fetchRequest()) == 0)
        #expect(try context.count(for: CDSynset.fetchRequest()) == 1)
        #expect(synset.termList.compactMap(\.text) == ["делать"])
    }

    // MARK: - The event log

    /// Every audited field must round-trip — including the multilingual snapshots
    /// (`promptLanguage`/`answerLanguage`/`promptTermID`/`wordSetID`) that direction
    /// alone cannot carry once a synset spans more than two languages. Append-only:
    /// this is the test that matters most.
    @Test func aReviewEventRoundTripsEveryAuditedField() throws {
        let context = makeContext()
        let bear = makeTerm(context, "bear", "en")
        let synset = makeSynset(context, terms: [bear, makeTerm(context, "медведь", "ru")])
        let set = makeSet(context, name: "Animals", languages: ["en", "ru"], synsets: [synset])

        let session = UUID()
        let event = CDReviewEvent(context: context)
        event.id = UUID()
        event.date = Date(timeIntervalSince1970: 1_000_000)
        event.sessionID = session
        event.task = ExerciseSession.Exercise.dictation.rawValue
        event.direction = ReviewDirection.productive.rawValue
        event.outcome = ReviewOutcome.correctJudged.rawValue
        event.response = "медветь"
        event.expected = "медведь"
        event.prompt = "bear"
        event.promptLanguage = "en"
        event.answerLanguage = "ru"
        event.promptTermID = bear.id
        event.wordSetID = set.id
        event.latencyMS = 2_450
        event.judgmentVerdict = 0.82
        event.judgeID = "match3/v1"
        event.judgedAt = Date(timeIntervalSince1970: 1_000_001)
        event.judgmentErrorTags = ["consonant-voicing"]
        event.schemaVersion = CDReviewEvent.currentSchemaVersion
        event.synset = synset
        try context.save()

        let fetched = try #require(try context.fetch(CDReviewEvent.fetchRequest()).first)
        #expect(fetched.sessionID == session)
        #expect(fetched.exercise == .dictation)
        #expect(fetched.promptDirection == .productive)
        #expect(fetched.reviewOutcome == .correctJudged)
        #expect(fetched.response == "медветь")
        #expect(fetched.expected == "медведь")
        #expect(fetched.prompt == "bear")
        #expect(fetched.promptLanguage == "en")
        #expect(fetched.answerLanguage == "ru")
        #expect(fetched.promptTermID == bear.id)
        #expect(fetched.wordSetID == set.id)
        #expect(fetched.latencyMS?.intValue == 2_450)
        #expect(fetched.judgmentVerdict?.doubleValue == 0.82)
        #expect(fetched.judgeID == "match3/v1")
        #expect(fetched.judgmentErrorTags == ["consonant-voicing"])
        #expect(fetched.schemaVersion == 1)
        #expect(fetched.synset == synset)
    }

    /// The log outlives every edit. Deleting the synset — even the whole set — must
    /// leave events in place, judgeable from their snapshots.
    @Test func deletingASynsetLeavesItsEventsWithSnapshotsIntact() throws {
        let context = makeContext()
        let synset = makeSynset(context, terms: [makeTerm(context, "bear", "en"),
                                                 makeTerm(context, "медведь", "ru")])
        let event = CDReviewEvent(context: context)
        event.id = UUID()
        event.date = Date()
        event.outcome = ReviewOutcome.correctVerbatim.rawValue
        event.prompt = "bear"
        event.expected = "медведь"
        event.promptLanguage = "en"
        event.answerLanguage = "ru"
        event.synset = synset
        try context.save()

        context.delete(synset)
        try context.save()

        let survivor = try #require(try context.fetch(CDReviewEvent.fetchRequest()).first)
        #expect(survivor.synset == nil)
        #expect(survivor.expected == "медведь")
        #expect(survivor.promptLanguage == "en")
    }

    /// An outcome this build has never heard of must decode to `nil` — skipped, never a
    /// crash, never coerced — with the raw value preserved for a newer build.
    @Test func anUnknownOutcomeDecodesToNilInsteadOfCrashing() throws {
        let context = makeContext()
        let event = CDReviewEvent(context: context)
        event.id = UUID()
        event.outcome = "correctByTelepathy"   // a case from some future version
        try context.save()

        #expect(event.reviewOutcome == nil)
        #expect(event.outcome == "correctByTelepathy", "the raw value must survive untouched")
    }

    @Test func historyIsOrderedOldestFirst() throws {
        let context = makeContext()
        let synset = makeSynset(context, terms: [makeTerm(context, "bear", "en")])
        for offset in [300.0, 100.0, 200.0] {
            let event = CDReviewEvent(context: context)
            event.id = UUID()
            event.date = Date(timeIntervalSince1970: offset)
            event.synset = synset
        }
        try context.save()

        let dates = synset.reviewHistory.compactMap { $0.date?.timeIntervalSince1970 }
        #expect(dates == [100, 200, 300])
    }

    // MARK: - Writing

    @Test func writeSavesOnABackgroundContextAndSurfacesOnTheViewContext() throws {
        let stack = LWPersistence(inMemory: true)
        try stack.write { context in
            let term = CDTerm(context: context)
            term.id = UUID()
            term.text = "written in the background"
            term.languageCode = "en"
        }
        #expect(try stack.viewContext.count(for: CDTerm.fetchRequest()) == 1)
    }

    @Test func writeRollsBackAndRethrowsWhenTheWorkFails() {
        struct Boom: Error {}
        let stack = LWPersistence(inMemory: true)

        #expect(throws: Boom.self) {
            try stack.write { context in
                let term = CDTerm(context: context)
                term.id = UUID()
                throw Boom()
            }
        }
        #expect((try? stack.viewContext.count(for: CDTerm.fetchRequest())) == 0)
    }
}
