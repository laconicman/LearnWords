//
//  Lexicon.swift
//  LearnWords
//
//  The app's vocabulary: word sets, the senses in them, the words that express those
//  senses, and the append-only log of every answer given.
//
//  This is the **only** type that talks to Core Data. Reads return value types, writes
//  take value types, and no `NSManagedObject` crosses the boundary — the rule from
//  docs/Design.md, which is what keeps a future store change confined to this file.
//
//  **No protocol.** There is one implementation and no second in sight, and it is already
//  testable because `LWPersistence(inMemory:)` injects a throwaway stack. A protocol here
//  would be speculative generality — a second name to keep in sync for no gain. Extract
//  one when a real second conformer appears (Rule of Three).
//
//  **Not a `WordStore`.** That protocol is shaped around a flat `[WordAndStat]` array
//  mutated by index. Mapping senses onto it would collapse synonyms and multilingual
//  tuples back into single pairs — destroying exactly what the schema redesign was for.
//  The old store stays untouched until the screens move over; then it goes.
//
//  **Threading.** Reads run on the view context (main queue); writes run on a
//  private-queue context via `LWPersistence.write`, which the view context merges
//  automatically. Synchronous throughout: Swift Concurrency back-deploys only to iOS 13
//  and this app's floor is 12.1.
//

import CoreData

final class Lexicon {

    private let persistence: LWPersistence

    init(persistence: LWPersistence = .shared) {
        self.persistence = persistence
    }

    private var viewContext: NSManagedObjectContext { persistence.viewContext }

    // MARK: - Word sets

    /// Every set, newest first.
    func wordSets() throws -> [WordSet] {
        let request = CDWordSet.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return try viewContext.fetch(request).map(WordSet.init)
    }

    func wordSet(_ id: UUID) throws -> WordSet? {
        try viewContext.fetch(Self.request(set: id)).first.map(WordSet.init)
    }

    @discardableResult
    func addWordSet(named name: String, languages: [String] = []) throws -> WordSet {
        try write { context in
            let set = CDWordSet(context: context)
            set.name = name
            var cache = LanguageCache()
            for code in languages {
                set.addLanguage(try cache.language(code, in: context))
            }
            // Snapshot inside the block: once it returns, this object's context is gone.
            return WordSet(set)
        }
    }

    func renameWordSet(_ id: UUID, to name: String) throws {
        try write { context in
            try Self.set(id, in: context).name = name
        }
    }

    /// Deletes the set. Its senses survive — they may belong to other sets, and even an
    /// orphan keeps a review history that is evidence of work done. Collecting orphans is
    /// a separate, deliberate call, never a side effect.
    func deleteWordSet(_ id: UUID) throws {
        try write { context in
            context.delete(try Self.set(id, in: context))
        }
    }

    // MARK: - Senses

    /// The senses in a set, in the order they were added.
    func senses(in setID: UUID) throws -> [Sense] {
        try Self.set(setID, in: viewContext).senses
            .sorted { $0.createdAt < $1.createdAt }
            .map(Sense.init)
    }

    /// The senses in a set that can actually be practised between two languages — a
    /// meaning with no German word cannot be asked in German.
    func senses(in setID: UUID, from: String, to: String) throws -> [Sense] {
        try senses(in: setID).filter { $0.canPractise(from: from, to: to) }
    }

    /// Adds one meaning to a set: the words that express it, in any languages.
    ///
    /// Words are **deduplicated by (text, language)** — adding "bear/медведь" when "bear"
    /// already exists links the existing word instead of making a twin. That is what
    /// makes a word shareable across senses and sets. Uniqueness lives here rather than
    /// in the model because CloudKit forbids unique constraints.
    ///
    /// The set grows to cover whatever languages the new words are in.
    @discardableResult
    func addSense(to setID: UUID,
                  terms drafts: [Term.Draft],
                  note: String? = nil,
                  tags: [String] = []) throws -> Sense {
        try write { context in
            let set = try Self.set(setID, in: context)
            let sense = CDSynset(context: context)
            sense.note = note

            var languages = LanguageCache()
            for draft in drafts {
                sense.addTerm(try Self.findOrCreateTerm(draft, languages: &languages, in: context))
                set.addLanguage(try languages.language(draft.language, in: context))
            }
            for name in tags {
                sense.addTag(try Self.findOrCreate(CDTag.self, named: name, in: context))
            }
            set.addSense(sense)
            return Sense(sense)
        }
    }

    /// Adds a word to an existing meaning — a synonym, or the same meaning in one more
    /// language.
    @discardableResult
    func addTerm(_ draft: Term.Draft, to senseID: UUID) throws -> Sense {
        try write { context in
            let sense = try Self.sense(senseID, in: context)
            var languages = LanguageCache()
            sense.addTerm(try Self.findOrCreateTerm(draft, languages: &languages, in: context))
            // Every set holding this meaning now covers the new language too.
            for set in sense.sets {
                set.addLanguage(try languages.language(draft.language, in: context))
            }
            return Sense(sense)
        }
    }

    /// Takes a meaning out of one set without deleting it — it may live in others.
    func removeSense(_ senseID: UUID, from setID: UUID) throws {
        try write { context in
            try Self.set(setID, in: context).removeSense(try Self.sense(senseID, in: context))
        }
    }

    /// Deletes the meaning everywhere. Its review events survive, holding the text
    /// snapshots that keep them judgeable — deleting content must never erase history.
    func deleteSense(_ id: UUID) throws {
        try write { context in
            context.delete(try Self.sense(id, in: context))
        }
    }

    // MARK: - Terms

    /// Edits a word. Every sense and set that uses it sees the change — the point of an
    /// atomic term — and its identity and history survive the rename (TD-18).
    func updateTerm(_ id: UUID,
                    text: String? = nil,
                    transcription: String? = nil,
                    partOfSpeech: String? = nil) throws {
        try write { context in
            let request = CDTerm.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            guard let term = try context.fetch(request).first else { throw LexiconError.notFound }
            if let text { term.text = text }
            if let transcription { term.transcription = transcription }
            if let partOfSpeech { term.partOfSpeech = partOfSpeech }
        }
    }

    /// Words matching `query` in any language, for search-as-you-type. Matches inflected
    /// forms too, so typing "made" finds "make" — the reason `WordForm` rows exist.
    func findTerms(matching query: String, limit: Int = 50) throws -> [Term] {
        guard !query.isEmpty else { return [] }
        let request = CDTerm.fetchRequest()
        request.predicate = NSPredicate(
            format: "text BEGINSWITH[cd] %@ OR ANY forms.text BEGINSWITH[cd] %@", query, query)
        request.sortDescriptors = [NSSortDescriptor(key: "text", ascending: true)]
        request.fetchLimit = limit
        return try viewContext.fetch(request).map(Term.init)
    }

    // MARK: - Review log

    /// Appends one answer. The only way into the log, which is otherwise append-only:
    /// nothing here updates or deletes a row.
    func record(_ draft: ReviewEvent.Draft) throws {
        try write { context in
            let event = CDReviewEvent(context: context)
            event.synset = try Self.sense(draft.senseID, in: context)
            event.sessionID = draft.sessionID
            event.wordSetID = draft.wordSetID
            event.promptTermID = draft.promptTermID
            event.task = draft.task.rawValue
            event.direction = draft.direction.rawValue
            event.outcome = draft.outcome.rawValue
            event.prompt = draft.prompt
            event.expected = draft.expected
            event.promptLanguage = draft.promptLanguage
            event.answerLanguage = draft.answerLanguage
            event.response = draft.response
            event.latencyMS = draft.latencyMS.map(NSNumber.init(value:))
            for name in draft.errorTags {
                event.addErrorTag(try Self.findOrCreate(CDErrorTag.self, named: name, in: context))
            }
        }
    }

    /// One meaning's history, oldest first.
    func history(ofSense id: UUID) throws -> [ReviewEvent] {
        try events(matching: NSPredicate(format: "synset.id == %@", id as CVarArg))
    }

    /// Everything answered in one sitting — the unit `ScoringPolicy` uses to tell a
    /// same-session retry (effort) from fresh long-term evidence.
    func history(ofSession id: UUID) throws -> [ReviewEvent] {
        try events(matching: NSPredicate(format: "sessionID == %@", id as CVarArg))
    }

    /// Everything answered since `date` — the window the retention and effort indexes
    /// are computed over.
    func history(since date: Date) throws -> [ReviewEvent] {
        try events(matching: NSPredicate(format: "date >= %@", date as NSDate))
    }

    private func events(matching predicate: NSPredicate) throws -> [ReviewEvent] {
        let request = CDReviewEvent.fetchRequest()
        request.predicate = predicate
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        return try viewContext.fetch(request).map(ReviewEvent.init)
    }

    // MARK: - Housekeeping

    /// Deletes meanings that belong to no set **and** carry no history.
    ///
    /// Explicit, never automatic: a sense with events is evidence of work done, and the
    /// effort index must not fall because a set was reorganised.
    @discardableResult
    func deleteOrphanedSenses() throws -> Int {
        try write { context in
            let request = CDSynset.fetchRequest()
            request.predicate = NSPredicate(format: "sets.@count == 0 AND events.@count == 0")
            let orphans = try context.fetch(request)
            orphans.forEach(context.delete)
            return orphans.count
        }
    }

    var isEmpty: Bool {
        ((try? viewContext.count(for: CDWordSet.fetchRequest())) ?? 0) == 0
    }

    // MARK: - Writing

    /// Runs `work` on a background context and returns whatever it produced.
    ///
    /// The result is built *inside* the block, while the objects are still valid — which
    /// is what stops a managed object from escaping by accident.
    private func write<T>(_ work: (NSManagedObjectContext) throws -> T) throws -> T {
        var result: Result<T, Error> = .failure(LexiconError.notFound)
        try persistence.write { context in
            result = .success(try work(context))
        }
        return try result.get()
    }

    // MARK: - Lookups

    private static func request(set id: UUID) -> NSFetchRequest<CDWordSet> {
        let request = CDWordSet.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return request
    }

    private static func set(_ id: UUID, in context: NSManagedObjectContext) throws -> CDWordSet {
        guard let set = try context.fetch(request(set: id)).first else {
            throw LexiconError.notFound
        }
        return set
    }

    private static func sense(_ id: UUID, in context: NSManagedObjectContext) throws -> CDSynset {
        let request = CDSynset.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        guard let sense = try context.fetch(request).first else {
            throw LexiconError.notFound
        }
        return sense
    }

    // MARK: - Find or create
    //
    // CloudKit forbids unique constraints, so "one row per natural key" is enforced here.

    private static func findOrCreateTerm(_ draft: Term.Draft,
                                        languages: inout LanguageCache,
                                        in context: NSManagedObjectContext) throws -> CDTerm {
        let language = try languages.language(draft.language, in: context)
        let request = CDTerm.fetchRequest()
        request.predicate = NSPredicate(format: "text ==[c] %@ AND language == %@",
                                        draft.text, language)
        request.fetchLimit = 1
        if let existing = try context.fetch(request).first {
            // Enrich in passing: a word re-added with a transcription should keep it.
            if existing.transcription == nil { existing.transcription = draft.transcription }
            if existing.partOfSpeech == nil { existing.partOfSpeech = draft.partOfSpeech }
            return existing
        }
        let term = CDTerm(context: context)
        term.text = draft.text
        term.language = language
        term.transcription = draft.transcription
        term.partOfSpeech = draft.partOfSpeech
        return term
    }

    /// Shared by `Tag` and `ErrorTag`: both are a `name` and nothing else.
    private static func findOrCreate<T: NSManagedObject & NamedRow>(
        _ type: T.Type, named name: String, in context: NSManagedObjectContext) throws -> T {
        let request = NSFetchRequest<T>(entityName: T.entityName)
        request.predicate = NSPredicate(format: "name ==[c] %@", name)
        request.fetchLimit = 1
        if let existing = try context.fetch(request).first { return existing }
        let row = T(context: context)
        row.name = name
        return row
    }
}

// MARK: - Named lookup rows

/// The shape `findOrCreate` needs: a row identified by its name. A protocol rather than a
/// Core Data parent entity, because inheritance would put tags and error tags in one
/// table and make every find-or-create scan both kinds (see the research doc).
protocol NamedRow: AnyObject {
    static var entityName: String { get }
    var name: String { get set }
}

extension CDTag: NamedRow {
    static var entityName: String { "Tag" }
}

extension CDErrorTag: NamedRow {
    static var entityName: String { "ErrorTag" }
}

// MARK: - Language cache

/// Find-or-create for languages, remembering what it made **within one write block**.
///
/// Without it, adding a sense with two English words fetches "en" twice, and the second
/// fetch does not see the first insert — unsaved inserts are invisible to a fetch. Two
/// rows for one language would silently break "every word in German".
private struct LanguageCache {
    private var known: [String: CDLanguage] = [:]

    mutating func language(_ code: String,
                          in context: NSManagedObjectContext) throws -> CDLanguage {
        if let cached = known[code] { return cached }
        let request = CDLanguage.fetchRequest()
        request.predicate = NSPredicate(format: "code ==[c] %@", code)
        request.fetchLimit = 1
        let language = try context.fetch(request).first ?? {
            let new = CDLanguage(context: context)
            new.code = code
            return new
        }()
        known[code] = language
        return language
    }
}

// MARK: - Errors

enum LexiconError: Error {
    /// No set, sense or word with that identity.
    case notFound
}

// MARK: - Snapshots
//
// Managed object → value type, in one place, so no caller is tempted to reach through a
// relationship and hold on to a row.

private extension WordSet {
    init(_ set: CDWordSet) {
        self.init(id: set.id,
                  name: set.name,
                  languages: set.languageCodes.sorted(),
                  senseCount: set.senses.count,
                  createdAt: set.createdAt)
    }
}

private extension Term {
    init(_ term: CDTerm) {
        self.init(id: term.id,
                  text: term.text,
                  language: term.languageCode,
                  transcription: term.transcription,
                  partOfSpeech: term.partOfSpeech)
    }
}

private extension Sense {
    init(_ sense: CDSynset) {
        self.init(id: sense.id,
                  note: sense.note,
                  terms: sense.terms
                      .sorted { ($0.languageCode, $0.text) < ($1.languageCode, $1.text) }
                      .map(Term.init),
                  tags: sense.sortedTags.map(\.name))
    }
}

private extension ReviewEvent {
    init(_ event: CDReviewEvent) {
        self.init(id: event.id,
                  date: event.date,
                  sessionID: event.sessionID,
                  outcome: event.reviewOutcome,
                  task: event.exercise,
                  direction: event.promptDirection,
                  prompt: event.prompt,
                  expected: event.expected,
                  response: event.response,
                  latencyMS: event.latencyMS?.intValue,
                  errorTags: event.sortedErrorTags.map(\.name),
                  schemaVersion: event.schemaVersion)
    }
}
