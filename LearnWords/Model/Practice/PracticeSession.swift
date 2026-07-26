//
//  PracticeSession.swift
//  LearnWords
//
//  One sitting: a queue of meanings drawn from a set, asked one at a time in a chosen
//  direction, with every answer appended to the review log.
//
//  Replaces `ExerciseSession`, which shuffled `[WordAndStat]` and mutated capped counters
//  in place. The differences are the point of the whole redesign:
//
//  * it asks about a **`Sense`**, so synonyms are all correct and a third language is
//    just another question rather than a new schema;
//  * answering **appends** a `ReviewEvent` instead of incrementing a counter, so negative
//    evidence never erases positive (ProgressModel R1);
//  * `id` is the sitting — the `sessionID` on every event it writes — which is what lets
//    a same-session retry count as effort but not as fresh long-term evidence.
//
//  A class, not a struct: it owns a store dependency and is mutated from view callbacks,
//  and copying a half-finished sitting has no meaning.
//
//  UIKit-free and store-injected, so the whole flow is testable without a screen.
//

import Foundation

final class PracticeSession {

    /// One question, ready to ask.
    struct Question {
        let sense: Sense
        /// The word that cued the question. Recorded per event, because a sense may have
        /// several synonyms on the prompt side and the text can be edited later.
        let promptTerm: Term
        /// Every word that answers correctly — synonyms included.
        let answers: [Term]

        var prompt: String { promptTerm.text }

        /// The answer to reveal. The first alternative; the others still count as
        /// correct, they simply are not the one shown.
        var expected: String { answers.first?.text ?? "" }

        /// Disambiguation to show when the prompt alone is ambiguous ("bear — the animal").
        var note: String? { sense.note }
    }

    // MARK: - Identity and configuration

    /// This sitting. Becomes `ReviewEvent.sessionID` on everything recorded here.
    let id = UUID()
    let exercise: Exercise
    let languages: LanguagePair
    let wordSetID: UUID

    private let lexicon: Lexicon
    private var queue: [Sense]
    private let total: Int

    /// When the current question was put on screen — the start of the latency clock.
    private var askedAt: Date?

    private(set) var current: Question?
    private(set) var completed = 0

    // MARK: - Starting

    private init(exercise: Exercise,
                 languages: LanguagePair,
                 wordSetID: UUID,
                 senses: [Sense],
                 lexicon: Lexicon) {
        self.exercise = exercise
        self.languages = languages
        self.wordSetID = wordSetID
        self.lexicon = lexicon
        self.queue = senses.shuffled()
        self.total = senses.count
    }

    /// Opens a sitting over one set.
    ///
    /// Only meanings that can actually be asked in this direction are queued — a sense
    /// with no word on the answer side is not a question. `includingLearned` keeps the
    /// user's existing setting working; what "learned" means is `InterimMastery`'s
    /// stand-in until `ScoringPolicy` lands (Phase D).
    static func start(_ exercise: Exercise,
                      in wordSetID: UUID,
                      languages: LanguagePair,
                      lexicon: Lexicon,
                      includingLearned: Bool) throws -> PracticeSession {
        let askable = try lexicon.senses(in: wordSetID,
                                         from: languages.promptLanguage,
                                         to: languages.answerLanguage)
        let senses: [Sense]
        if includingLearned {
            senses = askable
        } else {
            let mastery = try InterimMastery(lexicon: lexicon, senses: askable)
            senses = askable.filter { !mastery.isLearned($0.id) }
        }
        return PracticeSession(exercise: exercise,
                               languages: languages,
                               wordSetID: wordSetID,
                               senses: senses,
                               lexicon: lexicon)
    }

    // MARK: - State

    var isFinished: Bool { queue.isEmpty && current == nil }

    /// How much of the sitting is behind us, 0...1.
    var progress: Float {
        guard total > 0 else { return 0 }
        return Float(completed) / Float(total)
    }

    /// Every word that answers the current question — what a matcher checks against.
    var acceptedAnswers: [String] { current?.answers.map(\.text) ?? [] }

    // MARK: - Asking

    /// Puts the next question up, or returns `nil` when the sitting is over.
    ///
    /// Starts the latency clock, so nothing above has to remember to.
    @discardableResult
    func nextQuestion() -> Question? {
        guard !queue.isEmpty else {
            current = nil
            askedAt = nil
            return nil
        }
        let sense = queue.removeFirst()
        let prompts = sense.terms(in: languages.promptLanguage)
        let answers = sense.terms(in: languages.answerLanguage)
        guard let promptTerm = prompts.randomElement(), !answers.isEmpty else {
            // Filtered out at `start`, but a sense can lose a side while a sitting is
            // open (edited on another device). Skip it rather than ask an empty question.
            completed += 1
            return nextQuestion()
        }
        let question = Question(sense: sense, promptTerm: promptTerm, answers: answers)
        current = question
        askedAt = Date()
        return question
    }

    // MARK: - Answering

    /// Records an answer to the current question and moves past it.
    ///
    /// The event carries the text and language snapshots that keep it interpretable after
    /// the words are edited or deleted, plus the measured latency. Returns `nil` if there
    /// is no question in flight.
    @discardableResult
    func record(_ outcome: ReviewOutcome, response: String? = nil) throws -> Question? {
        guard let question = current else { return nil }

        try lexicon.record(ReviewEvent.Draft(
            senseID: question.sense.id,
            sessionID: id,
            wordSetID: wordSetID,
            promptTermID: question.promptTerm.id,
            task: exercise,
            direction: exercise.isProductive ? .productive : .receptive,
            outcome: outcome,
            prompt: question.prompt,
            expected: question.expected,
            promptLanguage: languages.promptLanguage,
            answerLanguage: languages.answerLanguage,
            response: response,
            latencyMS: elapsedMS()))

        completed += 1
        current = nil
        askedAt = nil
        return question
    }

    /// Passes over the current question. Recorded as `.skipped` — exposure, not
    /// retrieval — so the log shows it happened without it counting as evidence.
    func skip() throws {
        try record(.skipped)
    }

    /// Prompt→answer time. `nil` rather than 0 when the clock never started: an
    /// unmeasured latency is not an instant answer.
    private func elapsedMS() -> Int? {
        guard let askedAt else { return nil }
        return Int(Date().timeIntervalSince(askedAt) * 1000)
    }
}

// MARK: - Interim mastery

/// A stand-in for "has this been learned?" until `ScoringPolicy` exists (TD-13 Phase D).
///
/// The real answer is FSRS stability over the event log (docs/ProgressModel.md). This is
/// deliberately the crudest thing that preserves the user's existing "include learned
/// words" switch: a meaning counts as learned once it has as many positive answers as the
/// known-level preference, and a wrong answer since then un-learns it.
///
/// Isolated in its own type, with this comment, so it is impossible to mistake for the
/// scoring model — and so replacing it is a deletion, not an excavation.
struct InterimMastery {

    private let learned: Set<UUID>

    init(lexicon: Lexicon, senses: [Sense]) throws {
        let threshold = LWUserDefaults.standard.maxKnownLevelPreference
        var learned: Set<UUID> = []
        for sense in senses {
            let history = try lexicon.history(ofSense: sense.id)
            var positives = 0
            for event in history {
                guard let outcome = event.outcome else { continue }
                if outcome.isPositive {
                    positives += 1
                } else if outcome != .skipped {
                    positives = 0   // a mistake sends it back to the queue
                }
            }
            if positives >= threshold { learned.insert(sense.id) }
        }
        self.learned = learned
    }

    func isLearned(_ senseID: UUID) -> Bool { learned.contains(senseID) }
}
