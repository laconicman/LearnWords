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
//  **It replaced a `WordStore` protocol over a flat `[WordAndStat]` array mutated by
//  index.** Mapping senses onto that shape would have collapsed synonyms and multilingual
//  tuples back into single pairs — destroying exactly what the schema redesign was for —
//  so the old store was deleted rather than adapted.
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

    /// The context every read runs on. **Main queue only**, which this now checks rather
    /// than merely documents.
    ///
    /// Core Data's rule is that a managed object belongs to the queue of its context, and
    /// the guidance is blunt about the consequence — passing instances between queues "can
    /// result in corruption of the data and termination of the app"
    /// ([Using Core Data in the background](https://developer.apple.com/documentation/coredata/using-core-data-in-the-background#Avoiding-problems),
    /// WWDC 2012 session 214). Nothing in the type system enforces it; a precondition does,
    /// in debug builds, at the one place every read passes through.
    private var viewContext: NSManagedObjectContext {
        dispatchPrecondition(condition: .onQueue(.main))
        return persistence.viewContext
    }

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

    /// One meaning, re-read. A screen editing a meaning needs to see its own change, and
    /// a `Sense` snapshot is stale the moment anything touches the words it holds.
    func sense(_ id: UUID) throws -> Sense? {
        let request = CDSynset.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try viewContext.fetch(request).first.map(Sense.init)
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
            var languages = LanguageCache()
            let sense = try Self.insertSense(drafts, note: note, tags: tags,
                                             into: set, languages: &languages, in: context)
            return Sense(sense)
        }
    }

    /// Adds many meanings in **one** transaction — an imported file of a few thousand
    /// lines is one save, not a few thousand.
    ///
    /// Sharing the write block is not just speed: one `LanguageCache` spans the whole
    /// import, so a thousand English words find the same language row. Per-sense writes
    /// would each start a fresh cache and each pay a fetch.
    @discardableResult
    func addSenses(to setID: UUID, terms drafts: [[Term.Draft]]) throws -> Int {
        guard !drafts.isEmpty else { return 0 }
        return try write { context in
            let set = try Self.set(setID, in: context)
            var languages = LanguageCache()
            var added = 0
            for terms in drafts where !terms.isEmpty {
                _ = try Self.insertSense(terms, note: nil, tags: [],
                                         into: set, languages: &languages, in: context)
                added += 1
            }
            return added
        }
    }

    private static func insertSense(_ drafts: [Term.Draft],
                                    note: String?,
                                    tags: [String],
                                    into set: CDWordSet,
                                    languages: inout LanguageCache,
                                    in context: NSManagedObjectContext) throws -> CDSynset {
        let sense = CDSynset(context: context)
        sense.note = note
        for draft in drafts {
            sense.addTerm(try findOrCreateTerm(draft, languages: &languages, in: context))
            set.addLanguage(try languages.language(draft.language, in: context))
        }
        for name in tags {
            sense.addTag(try findOrCreate(CDTag.self, named: name, in: context))
        }
        set.addSense(sense)
        return sense
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

    /// Takes a word off a meaning — a synonym the learner no longer wants listed.
    ///
    /// **Unlinks, never deletes.** The `Term` row survives because other meanings and
    /// sets may use it; that is what makes a word atomic (TD-18). A term left on no
    /// meaning at all is collected by `deleteOrphanedTerms`, deliberately and separately.
    ///
    /// Refuses to remove the last word: a meaning expressed by nothing is not a meaning,
    /// and silently deleting the sense instead would be a surprise. Delete the meaning if
    /// that is what is wanted.
    @discardableResult
    func removeTerm(_ termID: UUID, from senseID: UUID) throws -> Sense {
        try write { context in
            let sense = try Self.sense(senseID, in: context)
            guard sense.terms.count > 1 else { throw LexiconError.lastTerm }
            guard let term = sense.terms.first(where: { $0.id == termID }) else {
                throw LexiconError.notFound
            }
            sense.removeTerm(term)
            return Sense(sense)
        }
    }

    /// Sets or clears the disambiguation shown at practice ("bear — the animal").
    /// Empty text clears it: a note of "" would claim there is one.
    func updateSense(_ id: UUID, note: String?) throws {
        try write { context in
            let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
            try Self.sense(id, in: context).note = (trimmed?.isEmpty == false) ? trimmed : nil
        }
    }

    /// Swaps every word a meaning has in one language for a new set of them.
    ///
    /// The meaning keeps its identity, so its review history survives — which is the whole
    /// reason this exists rather than the caller deleting and re-adding. Words left with no
    /// meaning are not removed: another meaning may use them, and `deleteOrphanedSenses`
    /// is the deliberate place for collecting what nothing points at.
    @discardableResult
    func replaceTerms(ofSense senseID: UUID,
                      in language: String,
                      with drafts: [Term.Draft]) throws -> Sense {
        try write { context in
            let sense = try Self.sense(senseID, in: context)
            let code = LanguageCode.canonical(language)
            for term in sense.terms where LanguageCode.canonical(term.language?.code ?? "") == code {
                sense.removeTerm(term)
            }
            var languages = LanguageCache()
            for draft in drafts {
                sense.addTerm(try Self.findOrCreateTerm(draft, languages: &languages, in: context))
            }
            return Sense(sense)
        }
    }

    /// Swaps one word of a meaning for another, find-or-creating the replacement.
    ///
    /// This is what a rename must go through when the new spelling already exists.
    /// `updateTerm` edits the row in place and so cannot merge: renaming "bruin" to "bear"
    /// where "bear" is already a row leaves **two rows spelled the same**, which is the one
    /// thing `findOrCreateTerm` exists to prevent. Here the meaning drops the old word and
    /// links the canonical one, so the vocabulary keeps one row per spelling.
    ///
    /// The old word survives if anything else uses it; `deleteOrphanedSenses` is the
    /// deliberate place for collecting what nothing points at.
    @discardableResult
    func replaceTerm(_ termID: UUID, with draft: Term.Draft, inSense senseID: UUID) throws -> Sense {
        try write { context in
            let sense = try Self.sense(senseID, in: context)
            var languages = LanguageCache()
            let replacement = try Self.findOrCreateTerm(draft, languages: &languages, in: context)
            for term in sense.terms where term.id == termID {
                sense.removeTerm(term)
            }
            sense.addTerm(replacement)
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

    /// Every meaning that already holds `text` in `language`, across every set.
    ///
    /// Matches the way the store stores words: case-insensitively, on the canonical
    /// language subtag, so "Bear" typed against an `en-US` preference finds the `en` row.
    func usages(ofTerm text: String, in language: String) throws -> [Lexicon.TermUsage] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let request = CDTerm.fetchRequest()
        request.predicate = NSPredicate(format: "text ==[c] %@", trimmed)
        let code = LanguageCode.canonical(language)

        let matching: [CDTerm] = try viewContext.fetch(request).filter {
            LanguageCode.canonical($0.language?.code ?? "") == code
        }

        var usages: [TermUsage] = []
        for term in matching {
            for synset in term.synsets {
                let others: [CDTerm] = synset.terms.filter {
                    LanguageCode.canonical($0.language?.code ?? "") != code
                }
                let names: [String] = synset.sets.map { $0.name }
                usages.append(Lexicon.TermUsage(senseID: synset.id,
                                        translations: others.map { $0.text }.sorted(),
                                        setNames: names.sorted()))
            }
        }
        return usages
    }

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

    /// Records a manual "start this meaning over".
    ///
    /// **Appends, never deletes.** The rows before the marker stay in the log: they are
    /// the record of work actually done, and the effort index must not fall because the
    /// learner chose to revisit a word. `ScoringPolicy` reads the marker as a truncation
    /// point and scores only what came after — the pattern Anki's `revlog` and
    /// swift-fsrs' `Rating.manual` both settled on.
    ///
    /// The answer-shaped fields are left empty on purpose. Nothing was asked, so there is
    /// no prompt, no exercise and no outcome to invent.
    func resetProgress(ofSense senseID: UUID, in wordSetID: UUID) throws {
        try write { context in
            let event = CDReviewEvent(context: context)
            event.kind = ReviewEventKind.progressReset.rawValue
            event.synset = try Self.sense(senseID, in: context)
            event.sessionID = UUID()
            event.wordSetID = wordSetID
            event.promptTermID = UUID()
        }
    }

    /// Appends one answer. The only way an *answer* enters the log, which is otherwise
    /// append-only: nothing here updates or deletes a row.
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

    /// Every meaning's history in **one** fetch, keyed by meaning.
    ///
    /// Scoring reads a whole screen's worth at a time, and asking per row turns a list of
    /// 500 words into 500 round trips. Meanings with no history are absent from the result
    /// rather than present-and-empty — the caller treats a miss as "never reviewed".
    func history(ofSenses ids: [UUID]) throws -> [UUID: [ReviewEvent]] {
        guard !ids.isEmpty else { return [:] }
        let rows = try events(matching: NSPredicate(format: "synset.id IN %@", ids))
        return Dictionary(grouping: rows.filter { $0.senseID != nil }, by: { $0.senseID! })
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

    /// Deletes words that belong to no meaning at all.
    ///
    /// Same policy as `deleteOrphanedSenses`, and separate from it for the same reason:
    /// explicit, never automatic. A word is cheap to keep and its `id` is referenced by
    /// `ReviewEvent.promptTermID`, so collecting one is a decision, not a side effect of
    /// editing.
    @discardableResult
    func deleteOrphanedTerms() throws -> Int {
        try write { context in
            let request = CDTerm.fetchRequest()
            request.predicate = NSPredicate(format: "synsets.@count == 0")
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

    /// Canonicalises before looking up, so `en-US` and `en` are one row (`LanguageCode`).
    mutating func language(_ tag: String,
                          in context: NSManagedObjectContext) throws -> CDLanguage {
        let code = LanguageCode.canonical(tag)
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
    /// Refused to remove a meaning's only word. Delete the meaning instead.
    case lastTerm
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
                  senseID: event.synset?.id,
                  date: event.date,
                  sessionID: event.sessionID,
                  kind: event.eventKind,
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
