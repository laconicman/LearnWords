//
//  PersistenceSchemaTests.swift
//  Unit Testing Bundle
//
//  Iteration 1 of TD-13: the Core Data model itself, before anything depends on it.
//
//  These run against an in-memory store, so they touch no file and no App Group. What
//  they pin down is the part that is expensive to get wrong later: the event log is
//  append-only, so a field that cannot round-trip now can never be backfilled.
//

import Testing
import CoreData
@testable import LearnWords

struct PersistenceSchemaTests {

    private func makeContext() -> NSManagedObjectContext {
        LWPersistence(inMemory: true).viewContext
    }

    private func makeSet(_ context: NSManagedObjectContext,
                         native: String = "ru", foreign: String = "en") -> CDWordSet {
        let set = CDWordSet(context: context)
        set.id = UUID()
        set.name = "Test set"
        set.nativeLanguage = native
        set.foreignLanguage = foreign
        set.createdAt = Date()
        return set
    }

    private func makeWord(_ context: NSManagedObjectContext, in set: CDWordSet) -> CDWord {
        let word = CDWord(context: context)
        word.id = UUID()
        word.firstWord = "bear"
        word.secondWord = "медведь"
        word.createdAt = Date()
        word.set = set
        return word
    }

    // MARK: - Model

    @Test func modelDefinesTheThreeEntities() {
        let names = Set(LWPersistence.model.entities.compactMap(\.name))
        #expect(names == ["WordSet", "Word", "ReviewEvent"])
    }

    /// CloudKit refuses a model with non-optional attributes that lack defaults, and
    /// refuses relationships without an inverse. The model is authored to those rules now
    /// so enabling `NSPersistentCloudKitContainer` later is a container swap, not a
    /// redesign — this test is what keeps it that way.
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
            }
            #expect(entity.uniquenessConstraints.isEmpty,
                    "\(entity.name ?? "?") must not use unique constraints — CloudKit rejects them")
        }
    }

    // MARK: - Identity and structure

    /// TD-18: identity is a UUID born with the object, not the spelling of the word.
    @Test func renamingAWordKeepsItsIdentityAndHistory() throws {
        let context = makeContext()
        let word = makeWord(context, in: makeSet(context))
        let id = word.id

        let event = CDReviewEvent(context: context)
        event.id = UUID()
        event.date = Date()
        event.outcome = ReviewOutcome.correctVerbatim.rawValue
        event.word = word
        try context.save()

        word.firstWord = "polar bear"   // the rename that used to orphan everything
        try context.save()

        #expect(word.id == id)
        #expect(word.reviewHistory.count == 1)
        #expect(word.reviewHistory.first?.reviewOutcome == .correctVerbatim)
    }

    @Test func aSetCarriesItsOwnLanguagePair() {
        let context = makeContext()
        let set = makeSet(context, native: "ru", foreign: "de")
        // The Design decision: languages belong to the set, not the app.
        #expect(set.languages.native == "ru")
        #expect(set.languages.foreign == "de")
    }

    @Test func deletingASetDeletesItsWordsAndTheirEvents() throws {
        let context = makeContext()
        let set = makeSet(context)
        let word = makeWord(context, in: set)
        let event = CDReviewEvent(context: context)
        event.id = UUID()
        event.date = Date()
        event.word = word
        try context.save()

        context.delete(set)
        try context.save()

        #expect(try context.count(for: CDWord.fetchRequest()) == 0)
        #expect(try context.count(for: CDReviewEvent.fetchRequest()) == 0)
    }

    // MARK: - The event log

    /// Every †-marked field from the research audit must round-trip. They cannot be
    /// backfilled into an append-only log, so this is the test that matters most.
    @Test func aReviewEventRoundTripsEveryAuditedField() throws {
        let context = makeContext()
        let word = makeWord(context, in: makeSet(context))

        let session = UUID()
        let event = CDReviewEvent(context: context)
        event.id = UUID()
        event.date = Date(timeIntervalSince1970: 1_000_000)
        event.sessionID = session
        event.task = ExerciseSession.Exercise.dictation.rawValue
        event.direction = ReviewDirection.nativeToForeign.rawValue
        event.outcome = ReviewOutcome.correctJudged.rawValue
        event.response = "медветь"
        event.expected = "медведь"
        event.prompt = "bear"
        event.latencyMS = 2_450
        event.judgmentVerdict = 0.82
        event.judgeID = "match3/v1"
        event.judgedAt = Date(timeIntervalSince1970: 1_000_001)
        event.judgmentErrorTags = ["consonant-voicing"]
        event.schemaVersion = CDReviewEvent.currentSchemaVersion
        event.word = word
        try context.save()

        let fetched = try #require(try context.fetch(CDReviewEvent.fetchRequest()).first)
        #expect(fetched.sessionID == session)
        #expect(fetched.exercise == .dictation)
        #expect(fetched.promptDirection == .nativeToForeign)
        #expect(fetched.reviewOutcome == .correctJudged)
        #expect(fetched.response == "медветь")
        #expect(fetched.expected == "медведь")
        #expect(fetched.prompt == "bear")
        #expect(fetched.latencyMS?.intValue == 2_450)
        #expect(fetched.judgmentVerdict?.doubleValue == 0.82)
        #expect(fetched.judgeID == "match3/v1")
        #expect(fetched.judgmentErrorTags == ["consonant-voicing"])
        #expect(fetched.schemaVersion == 1)
    }

    /// The log outlives the code, so an outcome this build has never heard of must be
    /// skipped rather than crash or be silently coerced into a known case.
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
        let word = makeWord(context, in: makeSet(context))
        for offset in [300.0, 100.0, 200.0] {
            let event = CDReviewEvent(context: context)
            event.id = UUID()
            event.date = Date(timeIntervalSince1970: offset)
            event.word = word
        }
        try context.save()

        let dates = word.reviewHistory.compactMap { $0.date?.timeIntervalSince1970 }
        #expect(dates == [100, 200, 300])
    }

    // MARK: - Writing

    @Test func writeSavesOnABackgroundContextAndSurfacesOnTheViewContext() throws {
        let stack = LWPersistence(inMemory: true)
        try stack.write { context in
            let set = CDWordSet(context: context)
            set.id = UUID()
            set.name = "Written in the background"
        }
        #expect(try stack.viewContext.count(for: CDWordSet.fetchRequest()) == 1)
    }

    @Test func writeRollsBackAndRethrowsWhenTheWorkFails() {
        struct Boom: Error {}
        let stack = LWPersistence(inMemory: true)

        #expect(throws: Boom.self) {
            try stack.write { context in
                let set = CDWordSet(context: context)
                set.id = UUID()
                throw Boom()
            }
        }
        #expect((try? stack.viewContext.count(for: CDWordSet.fetchRequest())) == 0)
    }
}
