//
//  LexiconTypes.swift
//  LearnWords
//
//  The vocabulary the app speaks in. Everything `Lexicon` returns is one of these — plain
//  value types, never an `NSManagedObject`.
//
//  **Naming.** Value types take the clean names; the Core Data entities behind them keep
//  the `CD` prefix. So `Sense` is the value, `CDSynset` is the row; `Term` is the value,
//  `CDTerm` is the row. Nothing in the app above `Lexicon` should ever mention a `CD`
//  type — if it does, the boundary has leaked.
//
//  **Why value types at all** (docs/Design.md): managed objects are queue-bound and
//  context-bound. Letting them into view controllers couples every screen to Core Data's
//  threading rules and turns a future store change into an app-wide rewrite. Core Data's
//  own guidance is blunt — "don't pass managed object instances between queues."
//
//  These are read *snapshots*: they carry the identity needed to ask the `Lexicon` to
//  change something, but mutating one changes nothing until a store call.
//

import Foundation

// MARK: - Term

/// One word, in one language. The atom of the model: it exists once and is shared by
/// every sense and set that uses it, so editing it edits it everywhere (TD-18).
struct Term: Hashable, Identifiable {
    let id: UUID
    var text: String
    var language: String
    /// Pronunciation — `nil` when not recorded, which is not the same as "".
    var transcription: String?
    var partOfSpeech: String?
}

extension Term {
    /// A term that does not exist yet. A separate type because a draft has no identity —
    /// the store assigns it — so the two cannot be confused at a call site.
    struct Draft: Hashable {
        var text: String
        var language: String
        var transcription: String?
        var partOfSpeech: String?

        init(_ text: String, in language: String,
             transcription: String? = nil, partOfSpeech: String? = nil) {
            self.text = text
            self.language = language
            self.transcription = transcription
            self.partOfSpeech = partOfSpeech
        }
    }
}

// MARK: - Sense

/// One meaning, and every word that expresses it — the owner's "language tuple", and the
/// unit that gets practised and scored.
///
/// Synonyms are simply several terms of the same language: all of them are correct
/// answers, which is the principled replacement for the old comma-separated definitions.
struct Sense: Hashable, Identifiable {
    let id: UUID
    /// Disambiguation shown at practice ("bear — the animal"), when the word alone is
    /// ambiguous. `nil` for most senses.
    var note: String?
    var terms: [Term]
    /// Subject field and register, as a folksonomy ("slang", "domain:medicine").
    var tags: [String]

    /// Every way this meaning is written in one language. Any of them answers correctly.
    ///
    /// Matches on the language subtag, so asking for "en-US" finds words stored as "en".
    func terms(in language: String) -> [Term] {
        let code = LanguageCode.canonical(language)
        return terms.filter { LanguageCode.canonical($0.language) == code }
    }

    /// The languages this meaning covers.
    var languages: Set<String> { Set(terms.map(\.language)) }

    /// Whether this meaning can be practised between two given languages — it needs a
    /// word on both sides.
    func canPractise(from: String, to: String) -> Bool {
        !terms(in: from).isEmpty && !terms(in: to).isEmpty
    }
}

// MARK: - Word set

/// A named, multilingual collection of senses.
///
/// Deliberately a *summary*: the sets screen draws dozens of these and must not fault in
/// every sense to render a subtitle. Ask `Lexicon.senses(in:)` for the contents.
struct WordSet: Hashable, Identifiable {
    let id: UUID
    var name: String
    /// The languages this set covers — sorted for stable display, and **unranked**:
    /// which one is "primary" is the practice session's decision, not the data's.
    var languages: [String]
    var senseCount: Int
    var createdAt: Date
}

// MARK: - Review log

/// One row of the log, as recorded. Immutable by construction — the log is append-only.
struct ReviewEvent: Hashable, Identifiable {
    let id: UUID
    /// The meaning this row is about. `nil` once that meaning has been deleted — the
    /// text snapshots below keep the row judgeable, but it no longer scores anything.
    var senseID: UUID?
    var date: Date
    var sessionID: UUID
    /// Answer or manual reset. On a reset every answer-shaped field below is empty —
    /// there was no question.
    var kind: ReviewEventKind
    var outcome: ReviewOutcome?
    var task: Exercise?
    var direction: ReviewDirection?
    /// Text snapshots, so the row stays interpretable after the words are edited or the
    /// sense is deleted.
    var prompt: String
    var expected: String
    var response: String?
    var latencyMS: Int?
    var errorTags: [String]
    /// The semantic version of this row's contents — `ScoringPolicy` reads it to
    /// interpret old rows under the rules that were true when they were written.
    var schemaVersion: Int16
}

extension ReviewEvent {
    /// An answer about to be logged. Carries everything that cannot be reconstructed
    /// later; the store fills in identity, timestamp and schema version.
    struct Draft {
        var senseID: UUID
        var sessionID: UUID
        var wordSetID: UUID
        /// Which synonym cued the question — the prompt *text* can be edited later.
        var promptTermID: UUID
        var task: Exercise
        var direction: ReviewDirection
        var outcome: ReviewOutcome
        var prompt: String
        var expected: String
        var promptLanguage: String
        var answerLanguage: String
        /// What the learner typed or said; `nil` for self-assessed answers, where there
        /// is nothing to record.
        var response: String?
        /// Prompt→answer time; `nil` when unmeasured, which is not 0 ms.
        var latencyMS: Int?
        /// What a judge said was wrong ("gender", "consonant-voicing").
        var errorTags: [String] = []
    }
}
