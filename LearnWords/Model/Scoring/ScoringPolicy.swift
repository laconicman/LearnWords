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

/// How one meaning stands in **one exercise** — its own memory, its own schedule.
///
/// Memory for recognising a word and memory for producing it are different memories
/// (Nation's receptive/productive split, `docs/ProgressResearch.md` §1.4), and the three
/// exercises probe different aspects of it. Anki reaches the same conclusion from the
/// other direction: its scheduling unit is the *card* (note × template), not the note.
/// So each exercise replays the log on its own and carries its own FSRS state.
struct StrandProgress: Equatable {

    /// How well learned in this exercise, 0…1. Monotone in stability; does not decay.
    let mastery: Float
    /// Probability of recalling it in this exercise right now.
    let retention: Float

    let memory: FSRSMemory?
    let lastReviewedAt: Date?
    let dueAt: Date?
    let isDue: Bool

    /// Distinct calendar days carrying a *successful* answer in this exercise.
    ///
    /// The count-like half of the learned rule. One retrieval, however fast, contains no
    /// spacing evidence at all — spacing is undefined for a single session — so stability
    /// alone must not be allowed to declare a meaning learned (TD-49).
    let successfulDays: Int

    /// Whether this exercise has ever been graded for this meaning.
    var isEngaged: Bool { memory != nil }

    static let untouched = StrandProgress(mastery: 0, retention: 1, memory: nil,
                                          lastReviewedAt: nil, dueAt: nil, isDue: true,
                                          successfulDays: 0)
}

/// How one meaning stands, right now — across every exercise.
struct SenseProgress: Equatable {

    /// Per-exercise state. Missing keys are `.untouched`; read through `self[exercise]`.
    let strands: [Exercise: StrandProgress]

    /// Work invested, 0…1, asymptotic. Never falls. **Whole-meaning, not per strand** —
    /// effort is the one index that should never be divided by how you practised.
    let effort: Float

    /// Answers per direction, for display. Nothing else in the model forks on direction:
    /// it is recorded per event, so a per-direction split of *memory* stays computable
    /// later without backfill (`ProgressResearch` Change 5's deferral, still deferred).
    let answersByDirection: [ReviewDirection: Int]

    subscript(exercise: Exercise) -> StrandProgress {
        strands[exercise] ?? .untouched
    }

    /// The exercises this meaning has actually been practised in.
    var engagedExercises: [Exercise] {
        Exercise.allCases.filter { self[$0].isEngaged }
    }

    /// How well learned overall: **the weakest strand the learner has engaged**.
    ///
    /// Not an average. "Done" should mean usable, not merely recognisable
    /// (`ProgressResearch` Phase 3 #3), and an average lets a strong flashcard strand hide
    /// a failing spoken one.
    var mastery: Float {
        let engaged = engagedExercises
        guard !engaged.isEmpty else { return 0 }
        return engaged.map { self[$0].mastery }.min() ?? 0
    }

    /// The most at-risk engaged strand — what the learner is closest to losing.
    var retention: Float {
        let engaged = engagedExercises
        guard !engaged.isEmpty else { return 1 }
        return engaged.map { self[$0].retention }.min() ?? 1
    }

    var memory: FSRSMemory? { weakestEngaged?.memory }
    var lastReviewedAt: Date? {
        strands.values.compactMap(\.lastReviewedAt).max()
    }
    var dueAt: Date? {
        strands.values.compactMap(\.dueAt).min()
    }

    private var weakestEngaged: StrandProgress? {
        engagedExercises.map { self[$0] }.min { $0.mastery < $1.mastery }
    }

    /// Whether it was worth practising at the moment this was computed — in any exercise.
    ///
    /// Computed at build time rather than on read: a value type that consults the wall
    /// clock answers a different question than the one it was built for, so a caller that
    /// pinned `now` would silently get today's answer instead of the one it asked for.
    let isDue: Bool

    /// Whether this exercise is worth practising.
    func isDue(_ exercise: Exercise) -> Bool { self[exercise].isDue }

    /// Whether it has passed the "learned" bar, which is what the *include learned words*
    /// switch filters on.
    ///
    /// **The rule (TD-49):** every exercise the learner has *engaged* must be learned, and
    /// at least one must be. Engagement rather than "all three" is what keeps this from
    /// wiping progress the moment strands appeared: a meaning drilled only as a flashcard
    /// is judged on its flashcard strand. Try it in dictation and fail, and it stops being
    /// learned — which is true, and is exactly the hypercorrection moment worth surfacing.
    ///
    /// With `requireProduction`, a productive exercise must also be among them: production
    /// lags recognition and only improves when practised productively (Laufer, via
    /// `ProgressResearch` §1.4). Off by default — it is a real increase in work.
    func isLearned(requireProduction: Bool = LWUserDefaults.standard.requireProductionForLearned) -> Bool {
        let engaged = engagedExercises
        guard !engaged.isEmpty else { return false }
        guard engaged.allSatisfy({ self[$0].mastery >= 1 }) else { return false }
        guard !requireProduction || engaged.contains(where: \.isProductive) else { return false }
        return true
    }

    /// Whether this one exercise has passed the bar.
    ///
    /// Deliberately blind to `requireProductionForLearned`: that preference is a statement
    /// about the *meaning* ("do not call it learned until it can be produced"), and asking
    /// it of a single strand would be a category error — a flashcard strand cannot become
    /// productive. So a meaning can be excluded from a flashcard drill as "learned there"
    /// while the summary still counts it unlearned overall, and both are true of different
    /// questions. Raised by review, PR #1; pinned by
    /// `LearnedThresholdTests.perExerciseLearnedIsAboutTheStrandNotTheProductionRule`.
    func isLearned(_ exercise: Exercise) -> Bool { self[exercise].mastery >= 1 }

    /// Non-parameterised form, for call sites that just want the current rule.
    var isLearned: Bool { isLearned() }

    static let unseen = SenseProgress(strands: [:], effort: 0,
                                      answersByDirection: [:], isDue: true)
}

/// Turns a meaning's review history into its indexes.
struct ScoringPolicy {

    /// Bumped whenever the mapping below changes, so a stored index (should one ever be
    /// cached) can be told apart from one computed under different rules. The rules
    /// themselves are never migrated — they are re-run.
    /// 2 since TD-49: replay is partitioned per exercise, mastery carries a distinct-day
    /// ceiling and the preference has a floor. Any cache written under 1 means something
    /// else (TD-52). Reported by review, PR #1.
    static let version = 2

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
    /// The horizon in force.
    ///
    /// The floor is applied to the **preference only**, never to an injected value: a
    /// caller that names a horizon has made a deliberate choice, and an initialiser that
    /// quietly ignores its argument is a worse bug than the one the floor prevents.
    /// The slider is what needs protecting from itself.
    private var masteryHorizonDays: Double {
        if let fixedHorizonDays { return fixedHorizonDays }
        return max(Double(LWUserDefaults.standard.maxKnownLevelPreference),
                   Self.minimumHorizonDays)
    }

    /// No *preference* may sit at or below the stability a single Easy answer produces
    /// (`w[3]` = 8.2956 days under the shipped FSRS-6 weights), or one fast correct answer
    /// would fill the ring outright. The distinct-day gate is the other half of the guard;
    /// this half keeps the arithmetic honest even if the gate is relaxed.
    static let minimumHorizonDays = 10.0

    /// Successful recalls on separate days before an exercise may be called learned.
    ///
    /// **Five, raised from two (owner, 2026-09-02).** Two is the smallest number for which
    /// the word "spaced" means anything at all, which is why it was the first floor — but
    /// it is a floor, not a considered default. Five separate successful days is a real
    /// spacing history, and the gate only ever *delays* the claim "learned": it caps
    /// mastery at `gatedMasteryCeiling` while stability keeps accruing underneath.
    ///
    /// Raising it re-opens words that were called learned under the old default. That is
    /// the intended effect rather than a migration problem — nothing is lost, because
    /// `successfulDays` is replayed from the log and was always being counted.
    static let defaultMinimumSuccessfulDays = 5

    /// The range the settings slider offers. Below two the gate is not a spacing rule at
    /// all; above ten it outlives most learners' patience with a single word.
    static let minimumSuccessfulDaysRange = 2...10

    /// The most mastery an exercise may show while the distinct-day gate still holds it.
    ///
    /// Not 0.99: the ring would read as full for a meaning the app explicitly refuses to
    /// call learned, and a progress indicator that disagrees with the word beside it is
    /// worse than a coarse one. Three quarters says "nearly there, not there".
    /// Reported by review, PR #1.
    static let gatedMasteryCeiling = 0.75

    /// Set only when a caller named one; `nil` means "follow the preference".
    private let fixedMinimumSuccessfulDays: Int?

    /// Distinct successful days an exercise needs before it may be called learned.
    ///
    /// Read on every use, for the same reason `masteryHorizonDays` is: `ScoringPolicy`
    /// `.default` is a `static let`, so capturing the preference in `init` would freeze
    /// whatever it happened to be at first use and leave the slider doing nothing until
    /// the next launch. An injected value still wins — a caller that names a gate has
    /// made a deliberate choice.
    var minimumSuccessfulDays: Int {
        if let fixedMinimumSuccessfulDays { return fixedMinimumSuccessfulDays }
        // Clamped here rather than in `LWUserDefaults`, which the widgets compile and
        // this type they do not. A value from an older build, or synced from a device
        // whose range differs, must not put the gate outside what the slider can express.
        return min(max(LWUserDefaults.standard.minimumSuccessfulDaysPreference,
                       Self.minimumSuccessfulDaysRange.lowerBound),
                   Self.minimumSuccessfulDaysRange.upperBound)
    }

    init(algorithm: FSRSAlgorithm = FSRSAlgorithm(),
         masteryHorizonDays: Double? = nil,
         minimumSuccessfulDays: Int? = nil,
         calendar: Calendar = .current) {
        self.algorithm = algorithm
        self.calendar = calendar
        self.fixedHorizonDays = masteryHorizonDays
        self.fixedMinimumSuccessfulDays = minimumSuccessfulDays
    }

    // MARK: - Replaying a history

    /// Replays one meaning's whole log. `events` must be in date order, oldest first —
    /// which is what `Lexicon.history` returns.
    func progress(replaying events: [ReviewEvent], now: Date = Date()) -> SenseProgress {
        /// One exercise's running replay state.
        struct Replay {
            var memory: FSRSMemory?
            var lastReviewedAt: Date?
            /// Sittings whose *first* graded answer has already been fed to the scheduler.
            var scheduled: Set<UUID> = []
            var successfulDays: Set<Date> = []
        }

        var replays: [Exercise: Replay] = [:]
        var effort: Double = 0
        var sittings: Set<UUID> = []
        var answersByDirection: [ReviewDirection: Int] = [:]

        for event in events {
            // A manual reset restarts every strand — it is a declaration about the
            // meaning, not about one exercise. The same thing the reference does for a
            // `.manual` entry recorded in the `.new` state. Effort is untouched: the
            // answers before it are still work the learner did (ProgressModel R1/R3).
            guard event.kind == .answer else {
                replays.removeAll()
                // `answersByDirection` is *not* cleared, deliberately and for the same
                // reason effort is not: a reset restarts the schedule, it does not unsay
                // the answers already given (ProgressModel R1/R3). The tally describes
                // work done, not standing. Raised by review, PR #1.
                continue
            }

            effort += effortWeight(of: event)
            sittings.insert(event.sessionID)
            // Graded answers only: a skip is exposure, and "you answered 12 productively"
            // must not count the ones passed over. Reported by review, PR #1.
            if let direction = event.direction, event.outcome?.isPositive != nil,
               event.outcome != .skipped {
                answersByDirection[direction, default: 0] += 1
            }

            // An answer whose exercise does not decode belongs to no strand — a row from a
            // future build, which `schemaVersion` exists to let us skip rather than crash.
            // It still counts as effort: the learner did answer something.
            guard let exercise = event.task else { continue }
            guard let grade = grade(for: event) else { continue }   // skips are not graded

            var replay = replays[exercise] ?? Replay()

            // Only the first graded answer in a sitting is long-term evidence; retries
            // within it are effort. `sessionID` makes that exact.
            guard replay.scheduled.insert(event.sessionID).inserted else {
                replays[exercise] = replay
                continue
            }

            if event.outcome?.isPositive == true {
                replay.successfulDays.insert(calendar.startOfDay(for: event.date))
            }
            let elapsed = replay.lastReviewedAt.map {
                FSRSAlgorithm.elapsedDays(from: $0, to: event.date, calendar: calendar)
            } ?? 0
            replay.memory = algorithm.next(replay.memory, elapsedDays: elapsed, grade: grade)
            replay.lastReviewedAt = event.date
            replays[exercise] = replay
        }

        effort += Self.sittingWeight * Double(sittings.count)

        let strands = replays.mapValues {
            makeStrand(memory: $0.memory, lastReviewedAt: $0.lastReviewedAt,
                       successfulDays: $0.successfulDays.count, now: now)
        }
        let progress = SenseProgress(
            strands: strands,
            effort: display(effort: effort),
            answersByDirection: answersByDirection,
            // **Engaged strands only** — deliberately, and symmetrically with `isLearned`.
            //
            // Review (PR #1) proposed counting every exercise, engaged or not, so that the
            // aggregate matched what a sitting asks. That direction was tried and rejected:
            // an untouched strand is always due, so every meaning would be due forever
            // until all three exercises were learned, reminders could never fall silent,
            // and "nothing due" would become unreachable — the streak-nagging the whole
            // design avoids. The app must not demand exercises the learner does not use.
            //
            // The genuine half of that report — a set reporting "nothing due" while
            // dictation has never been tried — is answered where it belongs, in the UI:
            // `SetDigest.dueByExercise` gives the chooser a per-exercise count, so the
            // number shown is the number that exercise will ask.
            isDue: strands.isEmpty || strands.values.contains(where: \.isDue))
        return progress
    }

    private func makeStrand(memory: FSRSMemory?, lastReviewedAt: Date?,
                            successfulDays: Int, now: Date) -> StrandProgress {
        guard let memory, let lastReviewedAt else { return .untouched }
        let elapsed = FSRSAlgorithm.elapsedDays(from: lastReviewedAt, to: now,
                                                calendar: calendar)
        let interval = algorithm.interval(stability: memory.stability)
        let dueAt = calendar.date(byAdding: .day, value: Int(interval), to: lastReviewedAt)
        return StrandProgress(
            mastery: mastery(forStability: memory.stability, successfulDays: successfulDays),
            retention: Float(algorithm.retrievability(elapsedDays: elapsed,
                                                      stability: memory.stability)),
            memory: memory,
            lastReviewedAt: lastReviewedAt,
            dueAt: dueAt,
            isDue: dueAt.map { $0 <= now } ?? true,
            successfulDays: successfulDays)
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

        case .correctAided:
            // The answer was heard before it was produced — cued, not free, recall.
            // Positive, but the weakest that still counts: never Good or Easy.
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
    ///
    /// Capped below 1 until the meaning has been recalled successfully on
    /// `minimumSuccessfulDays` **separate days** in this exercise. Bahrick et al. 1993
    /// showed spacing and session count trade against each other (13 sessions at 56 days
    /// ≈ 26 at 14) — but a single sitting is not a spaced anything, and without this gate
    /// one fast answer sets stability to 8.3 days and any horizon under that reads as
    /// fully learned, permanently, on a word seen once (TD-49).
    private func mastery(forStability stability: Double, successfulDays: Int) -> Float {
        guard stability > 0, masteryHorizonDays > 0 else { return 0 }
        let value = log1p(stability) / log1p(masteryHorizonDays)
        let ceiling = successfulDays >= minimumSuccessfulDays ? 1 : Self.gatedMasteryCeiling
        return Float(min(max(value, 0), ceiling))
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

    /// A view over values scored elsewhere — what a cache returns (TD-52), and what the set
    /// summary is handed (TD-51). Kept next to the fetching initialiser so both shapes of
    /// "where did these numbers come from" are visible in one place.
    init(scored: [UUID: SenseProgress]) {
        self.progress = scored
    }

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
        // Read once for the whole index rather than once per meaning: `isLearned`'s default
        // argument reaches into UserDefaults, and a large library would pay for that on
        // every row of a summary. Reported by review, PR #1.
        let requireProduction = LWUserDefaults.standard.requireProductionForLearned
        return progress.values.filter { $0.isLearned(requireProduction: requireProduction) }.count
    }

    func senses(_ senses: [Sense], matching predicate: (SenseProgress) -> Bool) -> [Sense] {
        senses.filter { predicate(self[$0.id]) }
    }
}
