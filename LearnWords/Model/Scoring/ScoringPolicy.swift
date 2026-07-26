//
//  ScoringPolicy.swift
//  LearnWords
//
//  What the review log *means*: how far along a meaning is, how much work went into it,
//  and how likely it is to be recalled right now.
//
//  This replaces `InterimMastery`, which counted consecutive right answers against an
//  arbitrary threshold. That number was a placeholder and said so; this one is derived
//  from the evidence.
//
//  **Nothing here is stored.** Indexes are recomputed by replaying the log, exactly as
//  `docs/ProgressModel.md` requires: weights live in code, so revising them re-derives
//  every word's history instead of migrating it. That is also what makes the log
//  CloudKit-friendly — devices append rows and merge trivially, and each derives the same
//  answer from the merged result.
//
//  **Three indexes, deliberately separate** (ProgressModel R3):
//
//  * **Mastery** — a monotone function of FSRS *stability*. It grows with successful
//    spaced retrieval and is unaffected by mere elapsed time. Decay belongs to retention
//    alone; letting it into mastery would show forgetting twice.
//  * **Retention** — FSRS *retrievability* right now. This is the one that falls while you
//    sleep.
//  * **Effort** — work done: attempts, sittings, time spent. **Ours, with no FSRS
//    counterpart, and it never decreases.** A wrong answer is effort spent. So is a
//    meaning you have restarted three times.
//

import Foundation

/// How one meaning stands, right now.
struct SenseProgress: Equatable {

    /// How well learned, 0…1. Monotone in stability; does not fall with time.
    let mastery: Float
    /// Work invested, 0…1, asymptotic. Never falls.
    let effort: Float
    /// Probability of recalling it at this moment, 0…1. `1` when never reviewed —
    /// there is nothing to have forgotten yet.
    let retention: Float

    /// FSRS memory state, or `nil` when the meaning has never been graded.
    let memory: FSRSMemory?
    let lastReviewedAt: Date?
    /// When this should next be practised. `nil` when never reviewed — a new meaning is
    /// not overdue, it is simply new.
    let dueAt: Date?

    /// Whether it has passed the "learned" bar, which is what the *include learned words*
    /// switch filters on.
    var isLearned: Bool { mastery >= 1 }

    /// Whether it was worth practising at the moment this was computed.
    ///
    /// Stored rather than computed on read: a value type that consults the wall clock
    /// answers a different question than the one it was built for, so a caller that pinned
    /// `now` would silently get today's answer instead of the one it asked for.
    let isDue: Bool

    static let unseen = SenseProgress(mastery: 0, effort: 0, retention: 1,
                                      memory: nil, lastReviewedAt: nil, dueAt: nil,
                                      isDue: true)
}

/// Turns a meaning's review history into its indexes.
struct ScoringPolicy {

    /// Bumped whenever the mapping below changes, so a stored index (should one ever be
    /// cached) can be told apart from one computed under different rules. The rules
    /// themselves are never migrated — they are re-run.
    static let version = 1

    static let `default` = ScoringPolicy()

    private let algorithm: FSRSAlgorithm
    private let calendar: Calendar

    /// A fixed horizon, when one is injected. `nil` means "follow the preference".
    private let fixedHorizonDays: Double?

    /// Stability, in days, at which a meaning counts as fully learned.
    ///
    /// Taken from the user's "Known level" preference, reinterpreted: the old number was
    /// "how many correct answers in a row", the new one is "how many days it should stay
    /// remembered". Both mean "how much is enough", both default to 20, and the slider's
    /// 1…100 range reads sensibly as days. **The settings label still says "Known level"
    /// and wants to become something like "Remembered for (days)"** — that screen belongs
    /// to another workstream, so it is flagged rather than changed here.
    ///
    /// Read on every use rather than captured in `init`: `ScoringPolicy.default` is a
    /// `static let`, so capturing would freeze whatever the preference happened to be at
    /// first use and leave the slider doing nothing until the next launch.
    private var masteryHorizonDays: Double {
        fixedHorizonDays ?? Double(max(1, LWUserDefaults.standard.maxKnownLevelPreference))
    }

    init(algorithm: FSRSAlgorithm = FSRSAlgorithm(),
         masteryHorizonDays: Double? = nil,
         calendar: Calendar = .current) {
        self.algorithm = algorithm
        self.calendar = calendar
        self.fixedHorizonDays = masteryHorizonDays
    }

    // MARK: - Replaying a history

    /// Replays one meaning's whole log. `events` must be in date order, oldest first —
    /// which is what `Lexicon.history` returns.
    func progress(replaying events: [ReviewEvent], now: Date = Date()) -> SenseProgress {
        var memory: FSRSMemory?
        var lastReviewedAt: Date?
        var effort: Double = 0
        var sittings: Set<UUID> = []
        /// Sittings whose *first* graded answer has already been fed to the scheduler.
        var scheduled: Set<UUID> = []

        for event in events {
            // A manual reset restarts the memory — the same thing the reference does for
            // a `.manual` entry recorded in the `.new` state. Effort is untouched: the
            // answers before it are still work the learner did (ProgressModel R1/R3).
            guard event.kind == .answer else {
                memory = nil
                lastReviewedAt = nil
                scheduled.removeAll()
                continue
            }

            effort += effortWeight(of: event)
            sittings.insert(event.sessionID)

            guard let grade = grade(for: event) else { continue }   // skips are not graded

            // Only the first graded answer in a sitting is long-term evidence; retries
            // within it are effort. `sessionID` makes that exact.
            guard scheduled.insert(event.sessionID).inserted else { continue }

            let elapsed = lastReviewedAt.map {
                FSRSAlgorithm.elapsedDays(from: $0, to: event.date, calendar: calendar)
            } ?? 0
            memory = algorithm.next(memory, elapsedDays: elapsed, grade: grade)
            lastReviewedAt = event.date
        }

        effort += Self.sittingWeight * Double(sittings.count)

        return makeProgress(memory: memory, lastReviewedAt: lastReviewedAt,
                            effort: effort, now: now)
    }

    private func makeProgress(memory: FSRSMemory?, lastReviewedAt: Date?,
                              effort: Double, now: Date) -> SenseProgress {
        guard let memory, let lastReviewedAt else {
            // Never reviewed is not overdue — it is simply new, and always worth asking.
            return SenseProgress(mastery: 0, effort: display(effort: effort), retention: 1,
                                 memory: nil, lastReviewedAt: nil, dueAt: nil, isDue: true)
        }
        let elapsed = FSRSAlgorithm.elapsedDays(from: lastReviewedAt, to: now,
                                                calendar: calendar)
        let interval = algorithm.interval(stability: memory.stability)
        let dueAt = calendar.date(byAdding: .day, value: Int(interval), to: lastReviewedAt)
        return SenseProgress(
            mastery: mastery(forStability: memory.stability),
            effort: display(effort: effort),
            retention: Float(algorithm.retrievability(elapsedDays: elapsed,
                                                      stability: memory.stability)),
            memory: memory,
            lastReviewedAt: lastReviewedAt,
            dueAt: dueAt,
            isDue: dueAt.map { $0 <= now } ?? true)
    }

    // MARK: - Outcome → grade

    /// The mapping from this app's evidence taxonomy to FSRS's four grades
    /// (`docs/ProgressModel.md`). Returns `nil` for anything that is not retrieval — a
    /// skip is exposure, and must not move the schedule.
    func grade(for event: ReviewEvent) -> FSRSGrade? {
        switch event.outcome {
        case .incorrect, .selfAssessedForgot:
            return .again

        case .correctJudged:
            // A matcher said "close enough". Weaker evidence than reproducing the word,
            // so it is Hard. When the near-miss judge (R5) starts recording a graded
            // verdict, a confident one should promote this to Good — that branch waits on
            // the verdict reaching `ReviewEvent`.
            return .hard

        case .correctVerbatim:
            // Exact, and quick enough to look like recall rather than reconstruction.
            return wasFluent(event) ? .easy : .good

        case .selfAssessedKnown:
            // Reveal-then-grade, so it is real self-graded retrieval in the Anki sense —
            // but self-assessment is the weakest positive evidence, so it never earns Easy.
            return .good

        case .skipped, .none:
            return nil
        }
    }

    /// Whether the answer came fast enough to count as fluent recall.
    ///
    /// The allowance scales with the length of the expected answer, because a flat
    /// threshold would be a *bias* rather than merely imprecise: typing "полярный медведь"
    /// takes seconds that tapping "Know" does not, so a fixed cutoff would hand Easy to
    /// the button exercises and deny it to Dictation. Calibrate against real latencies
    /// once there are some.
    private func wasFluent(_ event: ReviewEvent) -> Bool {
        guard let latency = event.latencyMS else { return false }  // unmeasured ≠ fast
        let allowance = Self.fluentBaseMS
            + Self.fluentPerCharacterMS * Double(event.expected.count)
        return Double(latency) <= allowance
    }

    // MARK: - Index curves

    /// Mastery from stability. Logarithmic, so the first few successful reviews are
    /// visible: linear in stability, a word would sit near zero for weeks.
    private func mastery(forStability stability: Double) -> Float {
        guard stability > 0, masteryHorizonDays > 0 else { return 0 }
        let value = log1p(stability) / log1p(masteryHorizonDays)
        return Float(min(max(value, 0), 1))
    }

    /// Effort's display curve: approaches 1 without reaching it, because effort keeps
    /// accumulating and a full ring would have to mean "done".
    private func display(effort: Double) -> Float {
        Float(1 - exp(-effort / Self.effortScale))
    }

    private func effortWeight(of event: ReviewEvent) -> Double {
        event.outcome == .skipped ? Self.skipWeight : Self.attemptWeight
    }

    // MARK: - Weights
    //
    // In code, not data (ProgressModel): changing these re-derives every index on the next
    // launch, with no migration and no stored value to invalidate.

    /// One answer, right or wrong. A mistake is effort spent.
    private static let attemptWeight = 1.0
    /// A skip is exposure — real, but slight (owner, 2026-07-20).
    private static let skipWeight = 0.1
    /// Coming back for another sitting is persistence, and worth more than one more
    /// answer inside the sitting you were already in.
    private static let sittingWeight = 0.5
    /// Weighted effort at which the ring is ~63% full.
    private static let effortScale = 12.0

    private static let fluentBaseMS = 1_200.0
    private static let fluentPerCharacterMS = 120.0
}

// MARK: - A screen's worth of progress

/// SenseProgress for many meanings, computed once.
///
/// `ProgressModel.md` requires index values not be recomputed per cell. This is that
/// cache: built once per screen load from a single fetch, then read by every row. It is
/// deliberately a plain value with no invalidation protocol — the screens already reload
/// after anything that appends an event, so a rebuilt index *is* the invalidation.
struct ProgressIndex {

    private let progress: [UUID: SenseProgress]

    init(lexicon: Lexicon, senses: [Sense],
         policy: ScoringPolicy = .default, now: Date = Date()) throws {
        let histories = try lexicon.history(ofSenses: senses.map(\.id))
        var progress: [UUID: SenseProgress] = [:]
        progress.reserveCapacity(senses.count)
        for sense in senses {
            progress[sense.id] = policy.progress(replaying: histories[sense.id] ?? [],
                                                 now: now)
        }
        self.progress = progress
    }

    subscript(senseID: UUID) -> SenseProgress {
        progress[senseID] ?? .unseen
    }

    var learnedCount: Int {
        progress.values.filter(\.isLearned).count
    }

    func senses(_ senses: [Sense], matching predicate: (SenseProgress) -> Bool) -> [Sense] {
        senses.filter { predicate(self[$0.id]) }
    }
}
