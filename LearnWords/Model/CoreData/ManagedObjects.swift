//
//  ManagedObjects.swift
//  LearnWords
//
//  The Core Data entities for TD-13 — the lexical model from
//  docs/LexicalModelResearch.md, hand-written rather than Xcode-generated so the schema
//  is reviewable in the repository.
//
//  Shape: `Term` (an atomic word in one language) ↔ `Synset` (one shared meaning — the
//  owner's "language tuple") ↔ `WordSet` (a named, multilingual collection). All three
//  links are many-to-many: a term participates in several senses, a sense in several
//  sets. Translation connects *senses*, never words — the shape every lexical standard
//  converged on (OntoLex-Lemon, LMF, BabelNet; see the research doc).
//
//  **Optionality is CloudKit's price, not a design choice.**
//  `NSPersistentCloudKitContainer` requires every attribute to be optional or carry a
//  default, and every relationship to be optional with an inverse. The store therefore
//  cannot express "this is always present" — so the *typed accessors* below do it
//  instead: each entity exposes non-optional Swift properties with the store-level
//  optional as the private truth. Callers never unwrap; the mapping layer
//  (`CoreDataWordStore`, iteration 2) converts to value types at the boundary and this
//  is the only file that sees an `Optional` from the store.
//
//  **Nothing cascades into the review log.** Deleting sets, synsets or terms never
//  deletes events — the log is append-only and its text/language snapshots keep orphan
//  events judgeable ("history heals"). The only cascades are a term's own satellites
//  (comments, forms, illustrations), which are meaningless without it.
//
//  Identity: entities the app *references* (`WordSet`, `Synset`, `Term`) carry a `UUID`;
//  entities that are pure lookup rows (`Tag`, `Language`, `ErrorTag`) and owned
//  satellites (`Comment`, `Illustration`, `WordForm`) do not — Core Data's own
//  `objectID` is their identity, and a second identifier would be a second source of
//  truth to keep in sync. See docs/Design.md, "identity: objectID vs UUID".
//

import CoreData

// MARK: - Timestamps

/// `createdAt` / `modifiedAt` on every user-editable entity. Both are maintained by
/// `willSave()` rather than by call sites, so a forgotten assignment cannot make the
/// pair lie (owner: "those two usually come in pairs").
protocol Timestamped: NSManagedObject {
    var createdAt: Date? { get set }
    var modifiedAt: Date? { get set }
}

extension Timestamped {
    /// Called from `willSave()`.
    ///
    /// **Primitive accessors, deliberately.** Assigning through the normal setter inside
    /// `willSave()` dirties the object again, Core Data re-runs `willSave()`, and after
    /// ~100 passes it throws from `_prepareForPushChanges:` — which is exactly what an
    /// earlier "guard on `changedValues()`" version of this did (a fresh `Date()` each
    /// pass always compared unequal, so it never converged). `setPrimitiveValue` writes
    /// without change tracking, which is what Apple's `willSave()` documentation
    /// prescribes for this case.
    func touchTimestamps() {
        let now = Date()
        if primitiveValue(forKey: "createdAt") == nil {
            setPrimitiveValue(now, forKey: "createdAt")
        }
        setPrimitiveValue(now, forKey: "modifiedAt")
    }
}

// MARK: - Word set

/// A named collection of synsets. Declares which languages it covers — deliberately
/// *without* ranking them: which language is primary belongs to the practice session,
/// not the data (see the research doc).
@objc(CDWordSet)
final class CDWordSet: NSManagedObject, Timestamped {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var createdAt: Date?
    @NSManaged var modifiedAt: Date?
    @NSManaged var languages: NSSet?
    @NSManaged var synsets: NSSet?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        createdAt = Date()
    }

    override func willSave() {
        super.willSave()
        touchTimestamps()
    }
}

extension CDWordSet {
    static func fetchRequest() -> NSFetchRequest<CDWordSet> {
        NSFetchRequest<CDWordSet>(entityName: "WordSet")
    }

    /// Non-optional face of the store's optional. `id` is assigned in `awakeFromInsert`,
    /// so the fallback is unreachable for objects this app creates.
    var identifier: UUID { id ?? UUID() }

    var title: String { name ?? "" }

    var synsetList: [CDSynset] {
        (synsets as? Set<CDSynset>).map { Array($0) } ?? []
    }

    /// The languages this set covers, as codes.
    var languageCodes: Set<String> {
        Set((languages as? Set<CDLanguage>)?.compactMap(\.code) ?? [])
    }

    func addLanguage(_ language: CDLanguage) { mutableSetValue(forKey: "languages").add(language) }
    func removeLanguage(_ language: CDLanguage) { mutableSetValue(forKey: "languages").remove(language) }
    func addSynset(_ synset: CDSynset) { mutableSetValue(forKey: "synsets").add(synset) }
    func removeSynset(_ synset: CDSynset) { mutableSetValue(forKey: "synsets").remove(synset) }
}

// MARK: - Synset

/// One shared meaning — the owner's "language tuple", WordNet's synset. Links any
/// number of terms in any languages; every linked term of the answer language is a
/// correct answer, which is the principled version of the old comma-separated
/// definitions.
@objc(CDSynset)
final class CDSynset: NSManagedObject, Timestamped {
    @NSManaged var id: UUID?
    /// Sense disambiguation shown at practice ("bear — the animal"). Lives here, not on
    /// the term: a term-level comment cannot tell two senses of one word apart.
    @NSManaged var note: String?
    @NSManaged var createdAt: Date?
    @NSManaged var modifiedAt: Date?
    @NSManaged var terms: NSSet?
    @NSManaged var sets: NSSet?
    @NSManaged var tags: NSSet?
    @NSManaged var events: NSSet?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        createdAt = Date()
    }

    override func willSave() {
        super.willSave()
        touchTimestamps()
    }
}

extension CDSynset {
    static func fetchRequest() -> NSFetchRequest<CDSynset> {
        NSFetchRequest<CDSynset>(entityName: "Synset")
    }

    var identifier: UUID { id ?? UUID() }

    var termList: [CDTerm] {
        (terms as? Set<CDTerm>).map { Array($0) } ?? []
    }

    /// The terms of this sense in one language — all of them valid answers when that
    /// language is the answer side.
    func terms(in languageCode: String) -> [CDTerm] {
        termList.filter { $0.languageCode == languageCode }
    }

    /// The distinct languages this sense covers.
    var languageCodes: Set<String> {
        Set(termList.map(\.languageCode))
    }

    /// History, oldest first — the slice of the append-only log for this sense.
    var reviewHistory: [CDReviewEvent] {
        let all = (events as? Set<CDReviewEvent>).map { Array($0) } ?? []
        return all.sorted { $0.reviewedAt < $1.reviewedAt }
    }

    var tagList: [CDTag] {
        let all = (tags as? Set<CDTag>).map { Array($0) } ?? []
        return all.sorted { $0.label < $1.label }
    }

    // To-many writes go through `mutableSetValue` — the hand-written-subclass
    // equivalent of Xcode's generated accessors. Assignment of a whole `NSSet` replaces
    // the relationship and forces Core Data to diff it; these express the actual
    // intent (add/remove one link) and are the conventional safe write path.

    func addTerm(_ term: CDTerm) { mutableSetValue(forKey: "terms").add(term) }
    func removeTerm(_ term: CDTerm) { mutableSetValue(forKey: "terms").remove(term) }
    func addTag(_ tag: CDTag) { mutableSetValue(forKey: "tags").add(tag) }
    func removeTag(_ tag: CDTag) { mutableSetValue(forKey: "tags").remove(tag) }
}

// MARK: - Term

/// An atomic word in one language. Exists once; senses and sets reference it.
/// Modelled on Apple's dictionary entry (owner's PDFs): one entry, searchable variant
/// forms, transcription and part of speech as entry-level data.
@objc(CDTerm)
final class CDTerm: NSManagedObject, Timestamped {
    @NSManaged var id: UUID?
    @NSManaged var text: String?
    /// Pronunciation — Apple's `d:pr` / Japanese yomi. Single value for now; the format
    /// allows several notations, an additive change if ever wanted.
    @NSManaged var transcription: String?
    @NSManaged var partOfSpeech: String?
    @NSManaged var createdAt: Date?
    @NSManaged var modifiedAt: Date?
    @NSManaged var language: CDLanguage?
    @NSManaged var synsets: NSSet?
    @NSManaged var comments: NSSet?
    @NSManaged var illustrations: NSSet?
    @NSManaged var forms: NSSet?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        createdAt = Date()
    }

    override func willSave() {
        super.willSave()
        touchTimestamps()
    }
}

extension CDTerm {
    static func fetchRequest() -> NSFetchRequest<CDTerm> {
        NSFetchRequest<CDTerm>(entityName: "Term")
    }

    var identifier: UUID { id ?? UUID() }

    /// The word itself.
    var spelling: String { text ?? "" }

    /// BCP-47 code ("en", "ru", "de") of this term's language.
    var languageCode: String { language?.code ?? "" }

    var synsetList: [CDSynset] {
        (synsets as? Set<CDSynset>).map { Array($0) } ?? []
    }

    var commentList: [CDComment] {
        let all = (comments as? Set<CDComment>).map { Array($0) } ?? []
        return all.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    var formList: [CDWordForm] {
        (forms as? Set<CDWordForm>).map { Array($0) } ?? []
    }

    var illustrationList: [CDIllustration] {
        (illustrations as? Set<CDIllustration>).map { Array($0) } ?? []
    }

    /// See the note on `CDSynset`'s helpers: to-many writes only via `mutableSetValue`.
    func addSynset(_ synset: CDSynset) { mutableSetValue(forKey: "synsets").add(synset) }
    func removeSynset(_ synset: CDSynset) { mutableSetValue(forKey: "synsets").remove(synset) }
}

// MARK: - Lookup rows

/// A language, by BCP-47 code. A row rather than a string on `Term` and a string array
/// on `WordSet`: "every set that covers German" and "every term in German" are
/// predicates, and predicates want rows (Codd's information rule — see the research
/// doc's WHERE-clause rule). Also the natural home for a display name or script
/// direction later, additively.
///
/// Identity is `objectID`; dedup by `code` is store logic, since CloudKit forbids
/// unique constraints.
@objc(CDLanguage)
final class CDLanguage: NSManagedObject {
    @NSManaged var code: String?
    @NSManaged var terms: NSSet?
    @NSManaged var sets: NSSet?
}

extension CDLanguage {
    static func fetchRequest() -> NSFetchRequest<CDLanguage> {
        NSFetchRequest<CDLanguage>(entityName: "Language")
    }

    var identifier: String { code ?? "" }
}

/// A facet of a sense: subject field ("domain:medicine") or usage register ("slang",
/// "dated"). A row, not a string-array blob on the synset — tags are a *query
/// dimension* ("all slang senses"), and a transformable array is invisible to SQLite:
/// no predicate can look inside it, nothing can index it, and renaming a tag would
/// mean rewriting every blob (1NF, applied where it pays).
///
/// A folksonomy, not an enum: lexicography keeps register and domain as open label
/// sets, and the register-vs-domain split is a naming convention ("slang" vs
/// "domain:medicine"), promotable to a `facet` attribute later — an additive change.
@objc(CDTag)
final class CDTag: NSManagedObject {
    @NSManaged var name: String?
    @NSManaged var createdAt: Date?
    @NSManaged var synsets: NSSet?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        createdAt = Date()
    }
}

extension CDTag {
    static func fetchRequest() -> NSFetchRequest<CDTag> {
        NSFetchRequest<CDTag>(entityName: "Tag")
    }

    var label: String { name ?? "" }
}

/// What a judge said was wrong with an answer ("gender", "consonant-voicing"). Rows for
/// the same reason as `Tag`: "show me every event where I got the gender wrong" is the
/// whole point of recording them, and that is a predicate.
@objc(CDErrorTag)
final class CDErrorTag: NSManagedObject {
    @NSManaged var name: String?
    @NSManaged var events: NSSet?
}

extension CDErrorTag {
    static func fetchRequest() -> NSFetchRequest<CDErrorTag> {
        NSFetchRequest<CDErrorTag>(entityName: "ErrorTag")
    }

    var label: String { name ?? "" }
}

// MARK: - Term satellites

/// A study note on a term — usage, register, mnemonic. Sense disambiguation belongs on
/// `CDSynset.note` instead.
@objc(CDComment)
final class CDComment: NSManagedObject, Timestamped {
    @NSManaged var text: String?
    @NSManaged var createdAt: Date?
    @NSManaged var modifiedAt: Date?
    @NSManaged var term: CDTerm?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        createdAt = Date()
    }

    override func willSave() {
        super.willSave()
        touchTimestamps()
    }
}

extension CDComment {
    static func fetchRequest() -> NSFetchRequest<CDComment> {
        NSFetchRequest<CDComment>(entityName: "Comment")
    }

    var body: String { text ?? "" }
}

/// A picture for a term. `urlString` holds a local file URL or a remote one; local
/// files do not travel across devices — the CloudKit-era answer is a binary asset,
/// an additive change recorded in the research doc.
@objc(CDIllustration)
final class CDIllustration: NSManagedObject, Timestamped {
    @NSManaged var urlString: String?
    @NSManaged var createdAt: Date?
    @NSManaged var modifiedAt: Date?
    @NSManaged var term: CDTerm?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        createdAt = Date()
    }

    override func willSave() {
        super.willSave()
        touchTimestamps()
    }
}

extension CDIllustration {
    var url: URL? { urlString.flatMap(URL.init(string:)) }

    static func fetchRequest() -> NSFetchRequest<CDIllustration> {
        NSFetchRequest<CDIllustration>(entityName: "Illustration")
    }
}

/// An inflected or variant form ("made", "making") — Apple's `d:index` rows: alternate
/// representations that should find, and be judged against, the same term.
@objc(CDWordForm)
final class CDWordForm: NSManagedObject, Timestamped {
    /// Free-form kind ("plural", "past", "yomi") — a vocabulary, not an enum, so new
    /// kinds are data rather than schema.
    @NSManaged var formType: String?
    @NSManaged var text: String?
    @NSManaged var createdAt: Date?
    @NSManaged var modifiedAt: Date?
    @NSManaged var term: CDTerm?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        createdAt = Date()
    }

    override func willSave() {
        super.willSave()
        touchTimestamps()
    }
}

extension CDWordForm {
    static func fetchRequest() -> NSFetchRequest<CDWordForm> {
        NSFetchRequest<CDWordForm>(entityName: "WordForm")
    }

    var spelling: String { text ?? "" }
    var kind: String { formType ?? "" }
}

// MARK: - Review event

/// One immutable record per answer (docs/ProgressModel.md). Append-only: never mutated
/// after insert, except to attach a judgment later. Linked to the *synset* — the fact
/// practised — with text/language snapshots that keep it meaningful even if the synset
/// is later edited or deleted.
///
/// No `modifiedAt`: events are not edited. The one post-hoc write is a judgment, and it
/// carries its own `judgedAt`.
@objc(CDReviewEvent)
final class CDReviewEvent: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var date: Date?
    @NSManaged var sessionID: UUID?
    @NSManaged var task: String?
    @NSManaged var direction: String?
    @NSManaged var outcome: String?
    @NSManaged var response: String?
    @NSManaged var expected: String?
    @NSManaged var prompt: String?
    /// Language snapshots — with multilingual synsets, direction alone cannot identify
    /// the pair practised. Append-only: impossible to backfill, so written from day one.
    @NSManaged var promptLanguage: String?
    @NSManaged var answerLanguage: String?
    /// Which synonym cued the question — prompt *text* can be edited later.
    @NSManaged var promptTermID: UUID?
    /// Which thematic set framed the question — the different-set answer coefficient
    /// (research doc) is unjudgeable without it.
    @NSManaged var wordSetID: UUID?
    @NSManaged var latencyMS: NSNumber?
    @NSManaged var judgmentVerdict: NSNumber?
    @NSManaged var judgeID: String?
    @NSManaged var judgedAt: Date?
    /// The format this event was written in — see `currentSchemaVersion`.
    @NSManaged var schemaVersion: Int16
    @NSManaged var errorTags: NSSet?
    @NSManaged var synset: CDSynset?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        date = Date()
        schemaVersion = Self.currentSchemaVersion
    }
}

extension CDReviewEvent {
    static func fetchRequest() -> NSFetchRequest<CDReviewEvent> {
        NSFetchRequest<CDReviewEvent>(entityName: "ReviewEvent")
    }

    /// The **semantic** version of an event's contents — not the Core Data model
    /// version, which the store already tracks in its metadata.
    ///
    /// It exists because the log is append-only and outlives the code: if the *meaning*
    /// of a field ever changes (latency measured to a different anchor, an outcome
    /// redefined), old rows cannot be rewritten — CloudKit records are immutable in
    /// production and other devices hold copies. `ScoringPolicy` reads this to interpret
    /// each row under the rules that were true when it was written.
    static let currentSchemaVersion: Int16 = 1

    var identifier: UUID { id ?? UUID() }

    /// When the answer was given. Every event has one (`awakeFromInsert`).
    var reviewedAt: Date { date ?? .distantPast }

    /// How the answer was judged.
    ///
    /// Returns `nil` for a value this build does not know — the log outlives the code,
    /// so decoding **skips** unknown cases rather than crashing (ProgressModel's rule).
    var reviewOutcome: ReviewOutcome? {
        outcome.flatMap(ReviewOutcome.init(rawValue:))
    }

    var exercise: ExerciseSession.Exercise? {
        task.flatMap(ExerciseSession.Exercise.init(rawValue:))
    }

    var promptDirection: ReviewDirection? {
        direction.flatMap(ReviewDirection.init(rawValue:))
    }

    var errorTagList: [CDErrorTag] {
        let all = (errorTags as? Set<CDErrorTag>).map { Array($0) } ?? []
        return all.sorted { $0.label < $1.label }
    }

    func addErrorTag(_ tag: CDErrorTag) { mutableSetValue(forKey: "errorTags").add(tag) }
}
