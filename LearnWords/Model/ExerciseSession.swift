//
//  ExerciseSession.swift
//  LearnWords
//
//  One pass through the current word set for a single exercise: the queue, the
//  scoring, the progress and the skip rule.
//
//  This is the logic `WordTestViewController`, `WordDictationController` and
//  `WordPhoneticsViewController` each kept a near-identical copy of — `startRound`,
//  `nextTapped`, the scoring half of `afterAnswer`, and the round-end save in
//  `askQuestion`. None of it is view logic, and having it three times is what let the
//  three screens drift apart (TD-20). It lives here once, and it is testable without a
//  storyboard.
//
//  It is also where the ProgressModel's `ReviewEvent` log will be appended when TD-13
//  lands — one place instead of three, which is why this extraction is sequenced first.
//
//  Deliberately UIKit-free. `start(_:)` and `commit()` are the only members that touch
//  `Storage`, and that facade is swappable (`Storage.backend`), so even they are testable.
//

import Foundation

struct ExerciseSession {

    /// Which exercise an answer came from. `WordAndStat` keys its per-exercise tallies
    /// by these raw values, so they are persisted data — do not renumber them.
    enum Exercise: String {
        case learning = "L"
        case dictation = "D"
        case phonetics = "P"
    }

    /// What answering the current word produced.
    struct Answer {
        /// The word, with this answer already scored into it.
        let word: WordAndStat
        /// How the answer was judged. Carried verbatim to the `ReviewEvent` log at TD-13.
        let outcome: ReviewOutcome
        /// `true` only on the answer that first takes the word to the known level, so a
        /// screen can celebrate once rather than on every correct answer thereafter.
        let reachedKnownLevel: Bool

        /// Whether the screen should present this as a success.
        var isPositive: Bool { outcome.isPositive }
    }

    let exercise: Exercise

    /// Words not yet answered or skipped, current one first.
    private(set) var remaining: [WordAndStat]

    /// Words already answered or skipped this round, with their updated stats.
    private(set) var finished: [WordAndStat] = []

    private let total: Int

    /// Shuffles `words` into a round. Order is decided once, here.
    init(exercise: Exercise, words: [WordAndStat]) {
        self.exercise = exercise
        self.remaining = words.shuffled()
        self.total = words.count
    }

    /// A round over the word set currently in the store.
    static func start(_ exercise: Exercise) -> ExerciseSession {
        ExerciseSession(exercise: exercise, words: Storage.wordsAndStat)
    }

    // MARK: - State

    var currentWord: WordAndStat? { remaining.first }

    var isFinished: Bool { remaining.isEmpty }

    /// Share of the set already dealt with, 0...1.
    var progress: Float {
        guard total > 0 else { return 0 }
        return Float(finished.count) / Float(total)
    }

    /// Whether the current word should be passed over as already learned.
    /// Mirrors the guard the three screens ran at the top of `askQuestion`.
    func skipsCurrentWord(includingLearned: Bool) -> Bool {
        guard let current = currentWord else { return false }
        return current.known >= WordAndStat.maxKnownLevel && !includingLearned
    }

    // MARK: - Advancing

    /// Scores the current word and moves past it. `nil` once the round is over.
    ///
    /// Only `outcome.isPositive` reaches today's scoring; the finer distinctions are
    /// recorded so they survive to the event log rather than being decided here.
    @discardableResult
    mutating func answer(_ outcome: ReviewOutcome) -> Answer? {
        guard !remaining.isEmpty else { return nil }

        var word = remaining.removeFirst()
        let wasKnown = word.known >= WordAndStat.maxKnownLevel

        if outcome.isPositive {
            word.increaseCorrect(exercize: exercise.rawValue)
        } else {
            word.decreaseCorrect(exercize: exercise.rawValue)
        }
        finished.append(word)

        return Answer(word: word,
                      outcome: outcome,
                      reachedKnownLevel: !wasKnown && word.known >= WordAndStat.maxKnownLevel)
    }

    /// Moves past the current word without attempting it — a `.skipped` outcome, which
    /// neither scores nor counts against the word.
    mutating func skip() {
        guard !remaining.isEmpty else { return }
        var word = remaining.removeFirst()
        word.skiped += 1
        finished.append(word)
    }

    // MARK: - Persistence

    /// Writes the round's results back to the store. The screens call this when the
    /// round runs out, before leaving.
    func commit() {
        Storage.saveWords(finished)
        Storage.wordsAndStat = finished
    }
}
