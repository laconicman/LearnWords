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

    /// One `Language` row per code, as `Lexicon` does (dedup is store
    /// logic — CloudKit forbids unique constraints).
    @discardableResult
    private func language(_ context: NSManagedObjectContext, _ code: String) -> CDLanguage {
        let request = CDLanguage.fetchRequest()
        request.predicate = NSPredicate(format: "code == %@", code)
        request.fetchLimit = 1
        if let existing = try? context.fetch(request).first { return existing }
        let language = CDLanguage(context: context)
        language.code = code
        return language
    }

    @discardableResult
    private func makeTerm(_ context: NSManagedObjectContext,
                          _ text: String, _ code: String) -> CDTerm {
        let term = CDTerm(context: context)
        term.text = text
        term.language = language(context, code)
        return term
    }

    @discardableResult
    private func makeSynset(_ context: NSManagedObjectContext,
                            terms: [CDTerm], note: String? = nil) -> CDSynset {
        let synset = CDSynset(context: context)
        synset.note = note
        terms.forEach(synset.addTerm)
        return synset
    }

    @discardableResult
    private func makeSet(_ context: NSManagedObjectContext,
                         name: String, languages: [String],
                         synsets: [CDSynset]) -> CDWordSet {
        let set = CDWordSet(context: context)
        set.name = name
        languages.forEach { set.addLanguage(language(context, $0)) }
        synsets.forEach(set.addSense)
        return set
    }

    /// Every review event carries the snapshots that make it interpretable later. The
    /// model requires them, so this mirrors what the practice session always supplies.
    @discardableResult
    private func makeEvent(_ context: NSManagedObjectContext,
                           synset: CDSynset? = nil,
                           date: Date = Date(),
                           outcome: ReviewOutcome? = .correctVerbatim) -> CDReviewEvent {
        let event = CDReviewEvent(context: context)
        event.date = date
        event.sessionID = UUID()
        event.promptTermID = UUID()
        event.wordSetID = UUID()
        if let outcome { event.outcome = outcome.rawValue }
        event.synset = synset
        return event
    }

    // MARK: - Model shape

    @Test func modelDefinesTheLexicalEntities() {
        let names = Set(LWPersistence.model.entities.compactMap(\.name))
        #expect(names == ["WordSet", "Synset", "Term", "Comment", "Illustration",
                          "WordForm", "Pronunciation", "Variety", "Tag", "Language",
                          "ErrorTag", "ReviewEvent"])
    }

    /// CloudKit refuses non-optional attributes without defaults, relationships without
    /// inverses, and unique constraints. The model is authored to those rules now so
    /// enabling `NSPersistentCloudKitContainer` later is a container swap, not a
    /// redesign — this test keeps it that way as entities grow.
    /// Exactly the check `NSPersistentCloudKitContainer` runs when it opens the store.
    ///
    /// This test used to carry a UUID exemption, reasoning that `momc` accepts
    /// `defaultValueString` on a UUID so the attribute was "defaulted". It is not: Core
    /// Data ignores that string, `defaultValue` stays nil, and CloudKit rejected all ten
    /// UUIDs at load — which is how the exemption was found to be wrong rather than
    /// merely unverified. The rule below has no exceptions, because CloudKit has none.
    @Test func modelObeysCloudKitRules() {
        for entity in LWPersistence.model.entities {
            for (name, attribute) in entity.attributesByName {
                #expect(attribute.isOptional || attribute.defaultValue != nil,
                        """
                        \(entity.name ?? "?").\(name) must be optional or have a default. \
                        CloudKit refuses to open a store otherwise — and a UUID can only \
                        satisfy this by being optional, since Core Data ignores \
                        defaultValueString on UUID attributes.
                        """)
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

    /// Indexes are invisible until a fetch is slow, so they are asserted rather than
    /// hoped for. Each one backs a predicate the app will actually run: term lookup by
    /// spelling (search, import dedup), tag and language rows by name (dedup on every
    /// insert), event history by date and by sitting (`ScoringPolicy`).
    @Test func indexesExistForEveryQueriedAttribute() {
        let expected = [
            "Term": ["text"],
            "WordForm": ["text"],
            "Tag": ["name"],
            "ErrorTag": ["name"],
            "Language": ["code"],
            "Variety": ["subtag"],
            "ReviewEvent": ["date", "sessionID"],
        ]
        for (entityName, properties) in expected {
            let entity = LWPersistence.model.entitiesByName[entityName]
            let indexed = Set((entity?.indexes ?? []).flatMap { index in
                index.elements.compactMap { ($0.property as? NSAttributeDescription)?.name }
            })
            for property in properties {
                #expect(indexed.contains(property), "\(entityName).\(property) must be indexed")
            }
        }
    }

    /// Optionality is a *modelling* decision here, not a blanket: an attribute is
    /// optional only where absence is meaningful. This test states which is which, so a
    /// future edit that makes `latencyMS` non-optional (erasing "unmeasured" into 0 ms)
    /// fails loudly rather than silently corrupting the scoring inputs.
    @Test func optionalityIsDeliberatePerAttribute() {
        func isOptional(_ entity: String, _ attribute: String) -> Bool? {
            LWPersistence.model.entitiesByName[entity]?.attributesByName[attribute]?.isOptional
        }

        // Absence is meaningful — these must stay optional.
        #expect(isOptional("ReviewEvent", "latencyMS") == true, "unmeasured is not 0 ms")
        #expect(isOptional("ReviewEvent", "judgmentVerdict") == true, "unjudged is not 0.0")
        #expect(isOptional("ReviewEvent", "response") == true, "self-assessed answers have none")
        #expect(isOptional("Term", "transcription") == true, "not recorded is not empty")
        #expect(isOptional("Term", "partOfSpeech") == true)
        #expect(isOptional("Synset", "note") == true, "most senses need no disambiguation")
        // A sound entry upstream carries an IPA string *or* an audio file, never both, so
        // requiring either would make half the source unrepresentable.
        #expect(isOptional("Pronunciation", "ipa") == true, "an audio-only entry has none")
        #expect(isOptional("Pronunciation", "audioURLString") == true, "an IPA-only entry has none")
        #expect(isOptional("Tag", "category") == true, "a tag a learner invents belongs to neither list")
        #expect(isOptional("Language", "wiktionaryCode") == true, "nil means it agrees with code")

        // The creating API always supplies these — the store enforces it.
        for (entity, attribute) in [("WordSet", "name"), ("Term", "text"), ("Tag", "name"),
                                    ("Language", "code"), ("ErrorTag", "name"),
                                    ("Variety", "subtag"),
                                    ("ReviewEvent", "outcome"), ("ReviewEvent", "promptLanguage"),
                                    ("ReviewEvent", "answerLanguage"), ("Comment", "text")] {
            #expect(isOptional(entity, attribute) == false, "\(entity).\(attribute) is always known")
        }
    }

    /// Words a learner half-remembers should be findable from the phone's own search.
    /// Core Data indexes the attributes flagged here; `LWPersistence` starts the
    /// delegate for the SQLite store.
    @Test func searchableTextIsIndexedInSpotlight() {
        func spotlit(_ entity: String, _ attribute: String) -> Bool? {
            LWPersistence.model.entitiesByName[entity]?
                .attributesByName[attribute]?.isIndexedBySpotlight
        }
        #expect(spotlit("Term", "text") == true)
        #expect(spotlit("WordForm", "text") == true, "an inflected form is how people remember a word")
        #expect(spotlit("WordSet", "name") == true)
        #expect(spotlit("Synset", "note") == true)
        #expect(spotlit("Comment", "text") == true)
        #expect(spotlit("Tag", "name") == true)

        // Not indexed: the review log is private practice history, not content the user
        // searches for, and indexing it would leak answers into system search.
        #expect(spotlit("ReviewEvent", "response") == false)
        #expect(spotlit("ReviewEvent", "expected") == false)
        #expect(spotlit("ReviewEvent", "prompt") == false)
    }

    // MARK: - Timestamps

    /// `createdAt`/`modifiedAt` are maintained by `willSave()`, not by call sites, so a
    /// forgotten assignment cannot make the pair lie.
    @Test func timestampsAreMaintainedAutomatically() throws {
        let context = makeContext()
        let term = makeTerm(context, "bear", "en")
        try context.save()

        let created = term.createdAt
        let firstModified = term.modifiedAt
        #expect(firstModified >= created)

        // A later save must move `modifiedAt` and never `createdAt`.
        Thread.sleep(forTimeInterval: 0.01)
        term.transcription = "bɛə"
        try context.save()

        #expect(term.createdAt == created, "createdAt must never move")
        #expect(term.modifiedAt > firstModified)
    }

    /// Events are never edited, so they carry no `modifiedAt` — the one post-hoc write
    /// is a judgment, which has its own `judgedAt`.
    @Test func reviewEventsHaveNoModifiedTimestamp() {
        let attributes = LWPersistence.model.entitiesByName["ReviewEvent"]?.attributesByName ?? [:]
        #expect(attributes["modifiedAt"] == nil)
        #expect(attributes["judgedAt"] != nil)
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
        #expect(bear.synsets.count == 2)
        #expect(animal.terms.contains(bear))
        #expect(carry.terms.contains(bear))
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

        let answers = synset.terms(in: "ru").map(\.text)
        #expect(Set(answers) == ["бегать", "бежать"])
        #expect(synset.terms(in: "en").map(\.text) == ["run"])
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
        #expect(set.synsets.first?.terms(in: "de").first?.text == "Bär")
    }

    /// Domain and register ride on the sense as tag *rows* — "bread = money" is slang
    /// in that *sense*, not as a word. Rows, because tags are a query dimension: this
    /// test proves the thing a `[String]` transformable blob could never do — a SQLite
    /// predicate straight into the store, and rename-in-one-place.
    @Test func tagsAreQueryableRowsSharedAcrossSenses() throws {
        let context = makeContext()
        let slang = CDTag(context: context)
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
        #expect(bread.sortedTags.first?.name == "register:slang")
        #expect(grand.sortedTags.first?.name == "register:slang")
        #expect(try context.count(for: CDTag.fetchRequest()) == 1)
    }

    /// Languages are rows for the same reason tags are: "every set that covers German"
    /// and "every term in German" are predicates, and predicates want rows. This is the
    /// query the `languageCodes: [String]` transformable could not serve.
    @Test func languagesAreQueryableRowsSharedAcrossTermsAndSets() throws {
        let context = makeContext()
        let synset = makeSynset(context, terms: [makeTerm(context, "bear", "en"),
                                                 makeTerm(context, "Bär", "de")])
        makeSet(context, name: "Animals", languages: ["en", "de"], synsets: [synset])
        makeSynset(context, terms: [makeTerm(context, "run", "en"),
                                    makeTerm(context, "бегать", "ru")])
        try context.save()

        // One row per code, reused by every term and set that names it.
        #expect(try context.count(for: CDLanguage.fetchRequest()) == 3)

        let german = CDTerm.fetchRequest()
        german.predicate = NSPredicate(format: "language.code == %@", "de")
        #expect(try context.count(for: german) == 1)

        let coversGerman = CDWordSet.fetchRequest()
        coversGerman.predicate = NSPredicate(format: "ANY languages.code == %@", "de")
        #expect(try context.count(for: coversGerman) == 1)
    }

    /// The whole reason `Pronunciation` is a row: one string cannot hold two accents.
    /// Also pins the cascade — a pronunciation is meaningless without its term, so it goes
    /// with it, exactly like the other term satellites.
    @Test func aTermHoldsSeveralPronunciationsEachWithItsOwnVariety() throws {
        let context = makeContext()
        let schedule = makeTerm(context, "schedule", "en")

        for (ipa, subtag) in [("ˈskɛdʒuːl", "US"), ("ˈʃɛdjuːl", "GB")] {
            let variety = CDVariety(context: context)
            variety.subtag = subtag
            let sound = CDPronunciation(context: context)
            sound.ipa = ipa
            sound.term = schedule
            sound.variety = variety
        }
        try context.save()

        #expect(schedule.pronunciations.count == 2, "both accents survive; a string could hold one")
        #expect(Set(schedule.pronunciations.compactMap { $0.variety?.subtag }) == ["US", "GB"])

        // An audio-only entry is representable — upstream never carries both at once.
        let audioOnly = CDPronunciation(context: context)
        audioOnly.audioURLString = "https://upload.wikimedia.org/en-us-schedule.ogg"
        audioOnly.term = schedule
        try context.save()
        #expect(audioOnly.ipa == nil)
        #expect(audioOnly.audioURL != nil)

        context.delete(schedule)
        try context.save()
        #expect(try context.count(for: CDPronunciation.fetchRequest()) == 0, "satellites cascade")
        #expect(try context.count(for: CDVariety.fetchRequest()) == 2,
                "a variety is a shared lookup row, not a satellite — it outlives the term")
    }

    /// A variety is find-or-create like `Tag` and `Language`, and is shared by the two
    /// owners that have one: the spelling and the accent. It never reaches a `Synset` —
    /// that is the whole reason it is not a `Tag`.
    @Test func varietiesAreQueryableRowsSharedByTermsAndPronunciations() throws {
        let context = makeContext()
        let us = CDVariety(context: context)
        us.subtag = "US"

        let color = makeTerm(context, "color", "en")
        color.mutableSetValue(forKey: "varieties").add(us)
        let sound = CDPronunciation(context: context)
        sound.ipa = "ˈkʌlɚ"
        sound.term = color
        sound.variety = us
        try context.save()

        #expect(try context.count(for: CDVariety.fetchRequest()) == 1, "one row, two owners")
        #expect(us.terms.count == 1)
        #expect(us.pronunciations.count == 1)

        let american = CDTerm.fetchRequest()
        american.predicate = NSPredicate(format: "ANY varieties.subtag == %@", "US")
        #expect(try context.count(for: american) == 1, "a predicate, which is why it is a row")

        #expect(LWPersistence.model.entitiesByName["Variety"]?
            .relationshipsByName.keys.contains("synsets") == false,
                "variety belongs to the term and the accent, never to a meaning")
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
        #expect(synset.sets.count == 1)
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
            form.formType = kind
            form.text = text
            form.term = term
        }
        let comment = CDComment(context: context)
        comment.text = "irregular verb"
        comment.term = term

        let illustration = CDIllustration(context: context)
        illustration.urlString = "https://example.com/make.png"
        illustration.term = term
        try context.save()

        let fetched = try #require(try context.fetch(CDTerm.fetchRequest()).first)
        #expect(fetched.transcription == "māk")
        #expect(fetched.partOfSpeech == "verb")
        #expect(Set(fetched.forms.map(\.text)) == ["made", "making"])
        #expect(fetched.sortedComments.first?.text == "irregular verb")
        #expect(fetched.illustrations.first?.url?.host == "example.com")
    }

    /// A term's satellites are meaningless without it — they go with it. Its synsets do
    /// not: they are shared.
    @Test func deletingATermCascadesSatellitesButNotSynsets() throws {
        let context = makeContext()
        let term = makeTerm(context, "make", "en")
        let form = CDWordForm(context: context)
        form.formType = "past"
        form.text = "made"
        form.term = term
        let synset = makeSynset(context, terms: [term, makeTerm(context, "делать", "ru")])
        try context.save()

        context.delete(term)
        try context.save()

        #expect(try context.count(for: CDWordForm.fetchRequest()) == 0)
        #expect(try context.count(for: CDSynset.fetchRequest()) == 1)
        #expect(synset.terms.map(\.text) == ["делать"])
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
        event.date = Date(timeIntervalSince1970: 1_000_000)
        event.sessionID = session
        event.task = Exercise.dictation.rawValue
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
        let voicing = CDErrorTag(context: context)
        voicing.name = "consonant-voicing"
        event.addErrorTag(voicing)
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
        #expect(fetched.sortedErrorTags.map(\.name) == ["consonant-voicing"])
        #expect(fetched.schemaVersion == 1)
        #expect(fetched.synset == synset)
    }

    /// The log outlives every edit. Deleting the synset — even the whole set — must
    /// leave events in place, judgeable from their snapshots.
    @Test func deletingASynsetLeavesItsEventsWithSnapshotsIntact() throws {
        let context = makeContext()
        let synset = makeSynset(context, terms: [makeTerm(context, "bear", "en"),
                                                 makeTerm(context, "медведь", "ru")])
        let event = makeEvent(context, synset: synset)
        event.prompt = "bear"
        event.expected = "медведь"
        event.promptLanguage = "en"
        event.answerLanguage = "ru"
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
    /// The event's `schemaVersion` is the *semantic* version of its contents, distinct
    /// from the Core Data model version the store tracks in its own metadata. Rows are
    /// stamped on insert so a future `ScoringPolicy` can interpret each one under the
    /// rules that were true when it was written — old rows can never be rewritten
    /// (append-only, and CloudKit production records are immutable).
    @Test func everyEventIsStampedWithTheSchemaVersionOnInsert() throws {
        let context = makeContext()
        let event = makeEvent(context)
        #expect(event.schemaVersion == CDReviewEvent.currentSchemaVersion)
        // Identity and time are assigned on insert, not by call sites.
        #expect(event.date.timeIntervalSinceReferenceDate > 0)
    }

    @Test func anUnknownOutcomeDecodesToNilInsteadOfCrashing() throws {
        let context = makeContext()
        let event = makeEvent(context, outcome: nil)
        event.outcome = "correctByTelepathy"   // a case from some future version
        try context.save()

        #expect(event.reviewOutcome == nil)
        #expect(event.outcome == "correctByTelepathy", "the raw value must survive untouched")
    }

    @Test func historyIsOrderedOldestFirst() throws {
        let context = makeContext()
        let synset = makeSynset(context, terms: [makeTerm(context, "bear", "en")])
        for offset in [300.0, 100.0, 200.0] {
            makeEvent(context, synset: synset, date: Date(timeIntervalSince1970: offset))
        }
        try context.save()

        let dates = synset.reviewHistory.map { $0.date.timeIntervalSince1970 }
        #expect(dates == [100, 200, 300])
    }

    // MARK: - Writing

    @Test func writeSavesOnABackgroundContextAndSurfacesOnTheViewContext() throws {
        let stack = LWPersistence(inMemory: true)
        try stack.write { context in
            let term = CDTerm(context: context)
            term.text = "written in the background"
        }
        #expect(try stack.viewContext.count(for: CDTerm.fetchRequest()) == 1)
    }

    @Test func writeRollsBackAndRethrowsWhenTheWorkFails() {
        struct Boom: Error {}
        let stack = LWPersistence(inMemory: true)

        #expect(throws: Boom.self) {
            try stack.write { context in
                _ = CDTerm(context: context)
                throw Boom()
            }
        }
        #expect((try? stack.viewContext.count(for: CDTerm.fetchRequest())) == 0)
    }
}
