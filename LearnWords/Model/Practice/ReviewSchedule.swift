//
//  ReviewSchedule.swift
//  LearnWords
//
//  What is due to be practised, and when the next thing falls due.
//
//  `ScoringPolicy` answers that for one meaning. This answers it for the library: the
//  question a chooser screen asks ("how much is waiting in this set?") and the one a
//  reminder asks ("is there any point notifying, and when?").
//
//  **Derived, never stored** — the same rule as every other index (ProgressModel). A
//  schedule is a snapshot taken `asOf` a moment; recomputing it is cheap enough that
//  caching it would only create a staleness problem the app does not otherwise have.
//
//  **One fetch for the whole library.** Building a `ProgressIndex` per set would issue a
//  fetch per set; the meanings are gathered first and scored together, because reminders
//  need every set at once and the chooser needs one — the same code should not be quadratic
//  in the first case to look tidy in the second.
//
//  A meaning that has never been answered counts as due: `SenseProgress.unseen.isDue` is
//  `true`, because a new word is not "not yet due", it is waiting.
//

import Foundation

struct ReviewSchedule {

    /// One set's standing.
    struct SetDigest: Equatable {
        let setID: UUID
        let name: String
        /// Meanings practisable right now, in the direction this set is studied in.
        let dueCount: Int
        /// Meanings that are askable at all, whether due or not.
        let askableCount: Int
        /// When each not-yet-due meaning comes up, earliest first.
        ///
        /// The dates themselves rather than a count of them, because a reminder has to ask
        /// "how much will be waiting *on Thursday*" — a question no single summary number
        /// can answer.
        let upcomingDueAt: [Date]

        /// When the earliest not-yet-due meaning comes up. `nil` when nothing is waiting —
        /// either everything is already due, or the set has nothing to ask.
        var nextDueAt: Date? { upcomingDueAt.first }
    }

    /// The moment this was computed. Everything below is relative to it.
    let asOf: Date
    let sets: [SetDigest]

    var dueCount: Int { sets.reduce(0) { $0 + $1.dueCount } }

    /// Every not-yet-due meaning's date across the whole library, earliest first.
    var upcomingDueAt: [Date] { sets.flatMap(\.upcomingDueAt).sorted() }

    /// The earliest moment any set has something new to offer, ignoring what is already
    /// due. `nil` when nothing is scheduled — a library with no future work.
    var nextDueAt: Date? { upcomingDueAt.first }

    /// How much will be waiting by `date`: what is due now, plus everything falling due
    /// before then.
    ///
    /// Cumulative on purpose — a meaning due on Tuesday is still waiting on Wednesday if
    /// nobody answered it. Overdue work does not evaporate overnight.
    func dueCount(by date: Date) -> Int {
        dueCount + upcomingDueAt.prefix { $0 < date }.count
    }

    /// Sets with something to practise now, busiest first — the order a reminder would
    /// name them in.
    var setsWithWork: [SetDigest] {
        sets.filter { $0.dueCount > 0 }.sorted { $0.dueCount > $1.dueCount }
    }

    // MARK: - Building

    /// Reads the whole library. Used by the reminder scheduler, which must consider sets
    /// the learner is not currently looking at.
    init(lexicon: Lexicon,
         policy: ScoringPolicy = .default,
         now: Date = Date()) throws {
        try self.init(sets: lexicon.wordSets(), lexicon: lexicon, policy: policy, now: now)
    }

    init(sets: [WordSet],
         lexicon: Lexicon,
         policy: ScoringPolicy = .default,
         now: Date = Date()) throws {
        self.asOf = now

        // Gather first, score once: one history fetch covers every set.
        var askable: [UUID: [Sense]] = [:]
        for set in sets {
            let pair = LanguagePair.forSet(set)
            askable[set.id] = try lexicon.senses(in: set.id,
                                                 from: pair.promptLanguage,
                                                 to: pair.answerLanguage)
        }
        let index = try ProgressIndex(lexicon: lexicon,
                                      senses: askable.values.flatMap { $0 },
                                      policy: policy, now: now)

        self.sets = sets.map { set in
            let senses = askable[set.id] ?? []
            let due = senses.filter { index[$0.id].isDue }
            // Only meanings that are *not* due have a future date worth waiting for.
            let upcoming = senses.filter { !index[$0.id].isDue }
                .compactMap { index[$0.id].dueAt }
                .sorted()
            return SetDigest(setID: set.id, name: set.name,
                             dueCount: due.count, askableCount: senses.count,
                             upcomingDueAt: upcoming)
        }
    }
}
