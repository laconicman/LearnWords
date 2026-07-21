//
//  ManagedObjects.swift
//  LearnWords
//
//  The Core Data entities for TD-13, hand-written rather than Xcode-generated so the
//  schema is reviewable in the repository.
//
//  **Every attribute is optional in the model.** That is not sloppiness — it is
//  `NSPersistentCloudKitContainer`'s hard requirement: attributes must be optional or
//  carry a default, relationships must be optional and have an inverse, and unique
//  constraints are unsupported. The typed accessors below put the non-optionality back
//  where the app can rely on it, and uniqueness is enforced in code (see `CoreDataWordStore`
//  when it lands).
//
//  Entities are prefixed `CD` so they never collide with the value types the rest of the
//  app speaks in.
//

import CoreData

// MARK: - Word set

/// A named collection of words, carrying **its own language pair** — the decision recorded
/// in docs/Design.md. Languages belong to the set, not the app.
@objc(CDWordSet)
final class CDWordSet: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var nativeLanguage: String?
    @NSManaged var foreignLanguage: String?
    @NSManaged var createdAt: Date?
    @NSManaged var words: NSSet?
}

extension CDWordSet {
    static func fetchRequest() -> NSFetchRequest<CDWordSet> {
        NSFetchRequest<CDWordSet>(entityName: "WordSet")
    }

    /// The pair this set is practised in.
    var languages: LanguagePair {
        LanguagePair(native: nativeLanguage ?? "en",
                     foreign: foreignLanguage ?? "en",
                     showsForeignAsPrompt: LWUserDefaults.standard.foreignToNative)
    }

    var wordList: [CDWord] {
        (words as? Set<CDWord>).map { Array($0) } ?? []
    }
}

// MARK: - Word

@objc(CDWord)
final class CDWord: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var firstWord: String?
    @NSManaged var secondWord: String?
    @NSManaged var createdAt: Date?
    @NSManaged var set: CDWordSet?
    @NSManaged var events: NSSet?
}

extension CDWord {
    static func fetchRequest() -> NSFetchRequest<CDWord> {
        NSFetchRequest<CDWord>(entityName: "Word")
    }

    /// History, oldest first. The append-only log this word's indexes derive from.
    var reviewHistory: [CDReviewEvent] {
        let all = (events as? Set<CDReviewEvent>).map { Array($0) } ?? []
        return all.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }
}

// MARK: - Review event

/// One immutable record per answer (docs/ProgressModel.md). Append-only: never mutated
/// after insert, except to attach a judgment later.
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
    @NSManaged var latencyMS: NSNumber?
    @NSManaged var judgmentVerdict: NSNumber?
    @NSManaged var judgeID: String?
    @NSManaged var judgedAt: Date?
    @NSManaged var judgmentErrorTags: [String]?
    @NSManaged var schemaVersion: Int16
    @NSManaged var word: CDWord?
}

extension CDReviewEvent {
    static func fetchRequest() -> NSFetchRequest<CDReviewEvent> {
        NSFetchRequest<CDReviewEvent>(entityName: "ReviewEvent")
    }

    /// The format this event was written in. Insurance for a log meant to outlive several
    /// versions of this codebase.
    static let currentSchemaVersion: Int16 = 1

    /// How the answer was judged.
    ///
    /// Returns `nil` for a value this build does not know — the log outlives the code, so
    /// decoding **skips** unknown cases rather than crashing (ProgressModel's rule).
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
