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
//  **Optionality is a modelling decision, not a blanket.** An attribute is optional only
//  where *absence is meaningful* — an unmeasured latency is not 0 ms, an unjudged answer
//  is not scored 0.0, a word with no recorded transcription is not a word transcribed as
//  "". Everything the creating API always supplies is non-optional with a default, which
//  makes Core Data validate it on save and makes the Swift property non-optional, so no
//  caller unwraps. (CloudKit's rule, enforced by the model compiler because the model is
//  `usedWithCloudKit`: a non-optional attribute must carry a default value. Relationships
//  must always be optional — that one *is* a blanket.)
//
//  **The UUID defaults are a compiler formality, not a runtime one.** `momc` demands a
//  default for every non-optional attribute, but Core Data *ignores* `defaultValueString`
//  on UUID attributes — at runtime the default is nil and a save fails validation. So a
//  non-optional UUID is a promise the code keeps, not the store: `id` is assigned in
//  `awakeFromInsert`, and `ReviewEvent`'s three snapshot IDs are assigned by the call
//  site that logs the answer. (Verified by experiment, not folklore — see the research
//  doc. Date defaults, by contrast, are honoured; `awakeFromInsert` overwrites them
//  anyway so no object keeps the 2001 placeholder.)
//
//  **Nothing cascades into the review log.** Deleting sets, synsets or terms never
//  deletes events — the log is append-only and its text/language snapshots keep orphan
//  events judgeable ("history heals"). The only cascades are a term's own satellites
//  (comments, forms, illustrations), which are meaningless without it.
//
//  Identity: entities the app *references* (`WordSet`, `Synset`, `Term`) carry a `UUID`;
//  entities that are pure lookup rows (`Tag`, `Language`, `ErrorTag`) and owned
//  satellites (`Comment`, `Illustration`, `WordForm`) do not — Core Data's own
//  `objectID` is their identity. See docs/Design.md, "identity: objectID vs UUID".
//

import CoreData

// MARK: - Timestamps

/// `createdAt` / `modifiedAt` on every user-editable entity, maintained by `willSave()`
/// rather than by call sites, so a forgotten assignment cannot make the pair lie.
protocol Timestamped: NSManagedObject {
    var createdAt: Date { get set }
    var modifiedAt: Date { get set }
}

extension Timestamped {
    /// Called from `awakeFromInsert()`. The model's literal date defaults exist only to
    /// satisfy the CloudKit rule; real objects get real times here.
    func startTimestamps() {
        let now = Date()
        createdAt = now
        modifiedAt = now
    }

    /// Called from `willSave()`.
    ///
    /// **Primitive accessors, deliberately.** Assigning through the normal setter inside
    /// `willSave()` dirties the object again, Core Data re-runs `willSave()`, and after
    /// ~100 passes it throws from `_prepareForPushChanges:` — which is exactly what an
    /// earlier "guard on `changedValues()`" version of this did (a fresh `Date()` each
    /// pass always compared unequal, so it never converged). `setPrimitiveValue` writes
    /// without change tracking, which is what Apple's `willSave()` documentation
    /// prescribes for this case.
    func touchModified() {
        setPrimitiveValue(Date(), forKey: "modifiedAt")
    }
}

// MARK: - Word set

/// A named collection of synsets. Declares which languages it covers — deliberately
/// *without* ranking them: which language is primary belongs to the practice session,
/// not the data (see the research doc).
@objc(CDWordSet)
final class CDWordSet: NSManagedObject, Timestamped {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var createdAt: Date
    @NSManaged var modifiedAt: Date
    @NSManaged var languages: Set<CDLanguage>
    /// Named `synsets` in the model (the entity is `Synset`); the app calls them senses.
    @NSManaged var synsets: Set<CDSynset>

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        startTimestamps()
    }

    override func willSave() {
        super.willSave()
        touchModified()
    }
}

extension CDWordSet {
    static func fetchRequest() -> NSFetchRequest<CDWordSet> {
        NSFetchRequest<CDWordSet>(entityName: "WordSet")
    }

    /// The languages this set covers, as codes.
    var languageCodes: Set<String> { Set(languages.map(\.code)) }

    /// The meanings in this set. `Lexicon` and the app speak of *senses*; the entity is
    /// still called `Synset` because that is the lexicographic term for the row.
    var senses: Set<CDSynset> { synsets }

    // To-many writes go through `mutableSetValue` — the hand-written-subclass
    // equivalent of Xcode's generated accessors. Assigning a whole set replaces the
    // relationship and forces Core Data to diff it; these express the actual intent
    // (add or remove one link) and are the conventional safe write path.

    func addLanguage(_ language: CDLanguage) { mutableSetValue(forKey: "languages").add(language) }
    func removeLanguage(_ language: CDLanguage) { mutableSetValue(forKey: "languages").remove(language) }
    func addSense(_ sense: CDSynset) { mutableSetValue(forKey: "synsets").add(sense) }
    func removeSense(_ sense: CDSynset) { mutableSetValue(forKey: "synsets").remove(sense) }
}

// MARK: - Synset

/// One shared meaning — the owner's "language tuple", WordNet's synset. Links any
/// number of terms in any languages; every linked term of the answer language is a
/// correct answer, which is the principled version of the old comma-separated
/// definitions.
@objc(CDSynset)
final class CDSynset: NSManagedObject, Timestamped {
    @NSManaged var id: UUID
    /// Sense disambiguation shown at practice ("bear — the animal"). Optional: most
    /// senses need none. Lives here, not on the term — a term-level comment cannot tell
    /// two senses of one word apart.
    @NSManaged var note: String?
    @NSManaged var createdAt: Date
    @NSManaged var modifiedAt: Date
    @NSManaged var terms: Set<CDTerm>
    @NSManaged var sets: Set<CDWordSet>
    @NSManaged var tags: Set<CDTag>
    @NSManaged var events: Set<CDReviewEvent>

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        startTimestamps()
    }

    override func willSave() {
        super.willSave()
        touchModified()
    }
}

extension CDSynset {
    static func fetchRequest() -> NSFetchRequest<CDSynset> {
        NSFetchRequest<CDSynset>(entityName: "Synset")
    }

    /// The terms of this sense in one language — all of them valid answers when that
    /// language is the answer side.
    func terms(in languageCode: String) -> [CDTerm] {
        terms.filter { $0.languageCode == languageCode }
    }

    /// The distinct languages this sense covers.
    var languageCodes: Set<String> { Set(terms.map(\.languageCode)) }

    /// History, oldest first — the slice of the append-only log for this sense.
    var reviewHistory: [CDReviewEvent] {
        events.sorted { $0.date < $1.date }
    }

    var sortedTags: [CDTag] {
        tags.sorted { $0.name < $1.name }
    }

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
    @NSManaged var id: UUID
    @NSManaged var text: String
    /// Pronunciation — Apple's `d:pr` / Japanese yomi. Optional because "not recorded"
    /// is a real state, distinct from "transcribed as empty".
    @NSManaged var transcription: String?
    /// Also optional: unknown until someone (or an enrichment source) supplies it.
    @NSManaged var partOfSpeech: String?
    @NSManaged var createdAt: Date
    @NSManaged var modifiedAt: Date
    @NSManaged var language: CDLanguage?
    @NSManaged var synsets: Set<CDSynset>
    @NSManaged var comments: Set<CDComment>
    @NSManaged var illustrations: Set<CDIllustration>
    @NSManaged var forms: Set<CDWordForm>

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        startTimestamps()
    }

    override func willSave() {
        super.willSave()
        touchModified()
    }
}

extension CDTerm {
    static func fetchRequest() -> NSFetchRequest<CDTerm> {
        NSFetchRequest<CDTerm>(entityName: "Term")
    }

    /// BCP-47 code ("en", "ru", "de") of this term's language. Empty only for a term
    /// whose language row has not been attached yet — relationships must stay optional
    /// for CloudKit, so this is the one place the model cannot enforce presence.
    var languageCode: String { language?.code ?? "" }

    var sortedComments: [CDComment] {
        comments.sorted { $0.createdAt < $1.createdAt }
    }

    func addSense(_ sense: CDSynset) { mutableSetValue(forKey: "synsets").add(sense) }
    func removeSense(_ sense: CDSynset) { mutableSetValue(forKey: "synsets").remove(sense) }
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
    @NSManaged var code: String
    @NSManaged var terms: Set<CDTerm>
    @NSManaged var sets: Set<CDWordSet>
}

extension CDLanguage {
    static func fetchRequest() -> NSFetchRequest<CDLanguage> {
        NSFetchRequest<CDLanguage>(entityName: "Language")
    }
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
    @NSManaged var name: String
    @NSManaged var createdAt: Date
    @NSManaged var synsets: Set<CDSynset>

    override func awakeFromInsert() {
        super.awakeFromInsert()
        createdAt = Date()
    }
}

extension CDTag {
    static func fetchRequest() -> NSFetchRequest<CDTag> {
        NSFetchRequest<CDTag>(entityName: "Tag")
    }
}

/// What a judge said was wrong with an answer ("gender", "consonant-voicing"). Rows for
/// the same reason as `Tag`: "show me every event where I got the gender wrong" is the
/// whole point of recording them, and that is a predicate.
@objc(CDErrorTag)
final class CDErrorTag: NSManagedObject {
    @NSManaged var name: String
    @NSManaged var events: Set<CDReviewEvent>
}

extension CDErrorTag {
    static func fetchRequest() -> NSFetchRequest<CDErrorTag> {
        NSFetchRequest<CDErrorTag>(entityName: "ErrorTag")
    }
}

// MARK: - Term satellites

/// A study note on a term — usage, register, mnemonic. Sense disambiguation belongs on
/// `CDSynset.note` instead.
@objc(CDComment)
final class CDComment: NSManagedObject, Timestamped {
    @NSManaged var text: String
    @NSManaged var createdAt: Date
    @NSManaged var modifiedAt: Date
    @NSManaged var term: CDTerm?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        startTimestamps()
    }

    override func willSave() {
        super.willSave()
        touchModified()
    }
}

extension CDComment {
    static func fetchRequest() -> NSFetchRequest<CDComment> {
        NSFetchRequest<CDComment>(entityName: "Comment")
    }
}

/// A picture for a term. `urlString` holds a local file URL or a remote one; local
/// files do not travel across devices — the CloudKit-era answer is a binary asset,
/// an additive change recorded in the research doc.
@objc(CDIllustration)
final class CDIllustration: NSManagedObject, Timestamped {
    @NSManaged var urlString: String
    @NSManaged var createdAt: Date
    @NSManaged var modifiedAt: Date
    @NSManaged var term: CDTerm?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        startTimestamps()
    }

    override func willSave() {
        super.willSave()
        touchModified()
    }
}

extension CDIllustration {
    static func fetchRequest() -> NSFetchRequest<CDIllustration> {
        NSFetchRequest<CDIllustration>(entityName: "Illustration")
    }

    var url: URL? { URL(string: urlString) }
}

/// An inflected or variant form ("made", "making") — Apple's `d:index` rows: alternate
/// representations that should find, and be judged against, the same term.
@objc(CDWordForm)
final class CDWordForm: NSManagedObject, Timestamped {
    /// Free-form kind ("plural", "past", "yomi") — a vocabulary, not an enum, so new
    /// kinds are data rather than schema.
    @NSManaged var formType: String
    @NSManaged var text: String
    @NSManaged var createdAt: Date
    @NSManaged var modifiedAt: Date
    @NSManaged var term: CDTerm?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        startTimestamps()
    }

    override func willSave() {
        super.willSave()
        touchModified()
    }
}

extension CDWordForm {
    static func fetchRequest() -> NSFetchRequest<CDWordForm> {
        NSFetchRequest<CDWordForm>(entityName: "WordForm")
    }
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
    // Non-optional UUIDs. Core Data ignores `defaultValueString` on UUID attributes —
    // momc accepts one, but the runtime default is nil and the save fails validation —
    // so a non-optional UUID is a promise the *code* keeps: `id` in `awakeFromInsert`,
    // the three snapshots at the call site that logs the answer.
    @NSManaged var id: UUID
    @NSManaged var date: Date
    @NSManaged var sessionID: UUID
    @NSManaged var task: String
    @NSManaged var direction: String
    @NSManaged var outcome: String
    @NSManaged var expected: String
    @NSManaged var prompt: String
    /// Language snapshots — with multilingual synsets, direction alone cannot identify
    /// the pair practised. Append-only: impossible to backfill, so written from day one.
    @NSManaged var promptLanguage: String
    @NSManaged var answerLanguage: String
    /// Which synonym cued the question — prompt *text* can be edited later.
    @NSManaged var promptTermID: UUID
    /// Which thematic set framed the question — the different-set answer coefficient
    /// (research doc) is unjudgeable without it.
    @NSManaged var wordSetID: UUID
    /// The format this event was written in — see `currentSchemaVersion`.
    @NSManaged var schemaVersion: Int16

    // Genuinely optional: absence carries meaning and must not be confused with a value.

    /// What the learner typed or said. `nil` for self-assessed answers, where there is
    /// no response to record — distinct from an empty answer.
    @NSManaged var response: String?
    /// Prompt→answer time. `nil` when unmeasured, which is not the same as 0 ms.
    @NSManaged var latencyMS: NSNumber?
    /// Judgment, attached later and possibly re-attached by a better judge. `nil` means
    /// unjudged — not "scored zero".
    @NSManaged var judgmentVerdict: NSNumber?
    @NSManaged var judgeID: String?
    @NSManaged var judgedAt: Date?

    @NSManaged var errorTags: Set<CDErrorTag>
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

    /// How the answer was judged.
    ///
    /// Returns `nil` for a value this build does not know — the log outlives the code,
    /// so decoding **skips** unknown cases rather than crashing (ProgressModel's rule).
    var reviewOutcome: ReviewOutcome? { ReviewOutcome(rawValue: outcome) }

    var exercise: Exercise? { Exercise(rawValue: task) }

    var promptDirection: ReviewDirection? { ReviewDirection(rawValue: direction) }

    var sortedErrorTags: [CDErrorTag] {
        errorTags.sorted { $0.name < $1.name }
    }

    func addErrorTag(_ tag: CDErrorTag) { mutableSetValue(forKey: "errorTags").add(tag) }
}
