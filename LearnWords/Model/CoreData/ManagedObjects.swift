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
//  **Every attribute is optional in the model.** That is `NSPersistentCloudKitContainer`'s
//  hard requirement: attributes optional or defaulted, relationships optional with an
//  inverse, no unique constraints. The typed accessors below put non-optionality back
//  where the app can rely on it; uniqueness (term dedup) is store logic.
//
//  **Nothing cascades into the review log.** Deleting sets, synsets or terms never
//  deletes events — the log is append-only and its text/language snapshots keep orphan
//  events judgeable ("history heals"). The only cascades are a term's own satellites
//  (comments, forms, illustrations), which are meaningless without it.
//

import CoreData

// MARK: - Word set

/// A named collection of synsets. Declares which languages it covers
/// (`languageCodes`) — deliberately *without* ranking them: which language is primary
/// belongs to the practice session, not the data (see the research doc).
@objc(CDWordSet)
final class CDWordSet: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var languageCodes: [String]?
    @NSManaged var createdAt: Date?
    @NSManaged var synsets: NSSet?
}

extension CDWordSet {
    static func fetchRequest() -> NSFetchRequest<CDWordSet> {
        NSFetchRequest<CDWordSet>(entityName: "WordSet")
    }

    var synsetList: [CDSynset] {
        (synsets as? Set<CDSynset>).map { Array($0) } ?? []
    }

    /// See the note on `CDSynset`'s helpers: to-many writes only via `mutableSetValue`.
    func addSynset(_ synset: CDSynset) { mutableSetValue(forKey: "synsets").add(synset) }
    func removeSynset(_ synset: CDSynset) { mutableSetValue(forKey: "synsets").remove(synset) }
}

// MARK: - Synset

/// One shared meaning — the owner's "language tuple", WordNet's synset. Links any
/// number of terms in any languages; every linked term of the answer language is a
/// correct answer, which is the principled version of the old comma-separated
/// definitions.
@objc(CDSynset)
final class CDSynset: NSManagedObject {
    @NSManaged var id: UUID?
    /// Sense disambiguation shown at practice ("bear — the animal"). Lives here, not on
    /// the term: a term-level comment cannot tell two senses of one word apart.
    @NSManaged var note: String?
    @NSManaged var createdAt: Date?
    @NSManaged var terms: NSSet?
    @NSManaged var sets: NSSet?
    @NSManaged var tags: NSSet?
    @NSManaged var events: NSSet?
}

extension CDSynset {
    static func fetchRequest() -> NSFetchRequest<CDSynset> {
        NSFetchRequest<CDSynset>(entityName: "Synset")
    }

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
        Set(termList.compactMap(\.languageCode))
    }

    /// History, oldest first — the slice of the append-only log for this sense.
    var reviewHistory: [CDReviewEvent] {
        let all = (events as? Set<CDReviewEvent>).map { Array($0) } ?? []
        return all.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    var tagList: [CDTag] {
        let all = (tags as? Set<CDTag>).map { Array($0) } ?? []
        return all.sorted { ($0.name ?? "") < ($1.name ?? "") }
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

// MARK: - Tag

/// A facet of a sense: subject field ("domain:medicine") or usage register ("slang",
/// "dated"). A row, not a string-array blob on the synset — tags are a *query
/// dimension* ("all slang senses"), and a transformable array is invisible to SQLite:
/// no predicate can look inside it, nothing can index it, and renaming a tag would
/// mean rewriting every blob (Codd's information rule / 1NF, applied to the one place
/// it pays: things that appear in a WHERE clause are rows). One `Tag` row per name —
/// dedup by name is store logic, since CloudKit forbids unique constraints.
///
/// A folksonomy, not an enum: lexicography keeps register and domain as open label
/// sets, and the register-vs-domain split is a naming convention ("slang" vs
/// "domain:medicine"), promotable to a `facet` attribute later — an additive change.
@objc(CDTag)
final class CDTag: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var createdAt: Date?
    @NSManaged var synsets: NSSet?
}

extension CDTag {
    static func fetchRequest() -> NSFetchRequest<CDTag> {
        NSFetchRequest<CDTag>(entityName: "Tag")
    }
}

// MARK: - Term

/// An atomic word in one language. Exists once; senses and sets reference it.
/// Modelled on Apple's dictionary entry (owner's PDFs): one entry, searchable variant
/// forms, transcription and part of speech as entry-level data.
@objc(CDTerm)
final class CDTerm: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var text: String?
    /// BCP-47 code ("en", "ru", "de").
    @NSManaged var languageCode: String?
    /// Pronunciation — Apple's `d:pr` / Japanese yomi. Single value for now; the format
    /// allows several notations, an additive change if ever wanted.
    @NSManaged var transcription: String?
    @NSManaged var partOfSpeech: String?
    @NSManaged var createdAt: Date?
    @NSManaged var synsets: NSSet?
    @NSManaged var comments: NSSet?
    @NSManaged var illustrations: NSSet?
    @NSManaged var forms: NSSet?
}

extension CDTerm {
    static func fetchRequest() -> NSFetchRequest<CDTerm> {
        NSFetchRequest<CDTerm>(entityName: "Term")
    }

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
}

// MARK: - Term satellites

/// A study note on a term — usage, register, mnemonic. Sense disambiguation belongs on
/// `CDSynset.note` instead.
@objc(CDComment)
final class CDComment: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var text: String?
    @NSManaged var createdAt: Date?
    @NSManaged var term: CDTerm?
}

/// A picture for a term. `urlString` holds a local file URL or a remote one; local
/// files do not travel across devices — the CloudKit-era answer is a binary asset,
/// an additive change recorded in the research doc.
@objc(CDIllustration)
final class CDIllustration: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var urlString: String?
    @NSManaged var createdAt: Date?
    @NSManaged var term: CDTerm?
}

extension CDIllustration {
    var url: URL? { urlString.flatMap(URL.init(string:)) }
}

/// An inflected or variant form ("made", "making") — Apple's `d:index` rows: alternate
/// representations that should find, and be judged against, the same term.
@objc(CDWordForm)
final class CDWordForm: NSManagedObject {
    @NSManaged var id: UUID?
    /// Free-form kind ("plural", "past", "yomi") — a vocabulary, not an enum, so new
    /// kinds are data rather than schema.
    @NSManaged var formType: String?
    @NSManaged var text: String?
    @NSManaged var term: CDTerm?
}

// MARK: - Review event

/// One immutable record per answer (docs/ProgressModel.md). Append-only: never mutated
/// after insert, except to attach a judgment later. Linked to the *synset* — the fact
/// practised — with text/language snapshots that keep it meaningful even if the synset
/// is later edited or deleted.
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
    @NSManaged var judgmentErrorTags: [String]?
    @NSManaged var schemaVersion: Int16
    @NSManaged var synset: CDSynset?
}

extension CDReviewEvent {
    static func fetchRequest() -> NSFetchRequest<CDReviewEvent> {
        NSFetchRequest<CDReviewEvent>(entityName: "ReviewEvent")
    }

    /// The format this event was written in. Insurance for a log meant to outlive
    /// several versions of this codebase.
    static let currentSchemaVersion: Int16 = 1

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
}
