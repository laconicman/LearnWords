//
//  FSRSMemory.swift
//  LearnWords
//
//  FSRS-6's memory model: the two numbers that describe how well one meaning is known,
//  and how they change when it is reviewed.
//
//  **A port, not an invention.** Every formula here comes from
//  [open-spaced-repetition/swift-fsrs](https://github.com/open-spaced-repetition/swift-fsrs)
//  (`Sources/FSRS/Algorithm/FSRSAlgorithm.swift`), and `FSRSMemoryTests` checks this port
//  against that library's *own* test oracles rather than against my reading of it.
//
//  **Why a port and not the package** — this reverses `ProgressModel.md`'s "adopt the
//  official Swift package". Its `Package.swift` declares `.iOS(.v14)` and builds with
//  `StrictConcurrency=complete`; this app's floor was 12.1 then. What we actually need is the
//  pure state transition (`nextState`), which is ~80 lines of arithmetic. The scheduler
//  around it — learning steps, fuzzing, interval ordering, card lifecycle — is Anki's
//  review-queue problem, not ours.
//
//  **Deliberately stateless.** No dates, no store, no card. Given a memory state, days
//  elapsed, and a grade, it returns the next memory state. That is what lets
//  `ScoringPolicy` recompute everything by replaying the log, which is the shape
//  `ProgressModel.md` requires: weights live in code, so changing them re-derives history
//  instead of migrating it.
//

import Foundation

/// What FSRS remembers about one meaning between reviews.
///
/// Both numbers are *derived* — never stored. `nil` means "never successfully reviewed",
/// which is not the same as zero.
struct FSRSMemory: Equatable {
    /// Days at which the chance of recall has fallen to 90%. Bjork's storage strength.
    var stability: Double
    /// How hard this item is for this learner, 1…10. Higher is harder.
    var difficulty: Double
}

/// The four grades FSRS accepts. Raw values are the algorithm's, and the arithmetic
/// depends on them — `g - 3` appears in two formulas.
enum FSRSGrade: Int {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4
}

/// The fitted weights and the knobs around them.
///
/// `w` is per-user-fittable in principle — FSRS ships an optimiser that learns it from a
/// review log exactly like ours. Until that exists, everyone gets the published defaults.
struct FSRSParameters {

    /// 21 weights: FSRS-6. A 19-element vector would be FSRS-5, which this port does not
    /// implement — the two differ in more than the weights (see `nextShortTermStability`).
    let w: [Double]
    /// The recall probability the schedule aims for.
    let requestRetention: Double
    /// Ceiling on a computed interval, in days. 100 years.
    let maximumInterval: Double
    /// Whether same-day reviews use the short-term stability path.
    let enableShortTerm: Bool

    /// FSRS-6 defaults, verbatim from `FSRSDefaults.defaultWv6`.
    static let fsrs6 = FSRSParameters(
        w: [0.212, 1.2931, 2.3065, 8.2956, 6.4133,
            0.8334, 3.0194, 0.001, 1.8722, 0.1666,
            0.796, 1.4835, 0.0614, 0.2629, 1.6483,
            0.6014, 1.8729, 0.5425, 0.0912, 0.0658,
            0.1542],
        requestRetention: 0.9,
        maximumInterval: 36_500,
        enableShortTerm: true)

    /// Lower bound on stability. FSRS-6 uses 0.001 where FSRS-5 used 0.01.
    static let minimumStability = 0.001
}

/// The state transition. One instance is reusable and holds no mutable state.
struct FSRSAlgorithm {

    let parameters: FSRSParameters

    private let decay: Double
    private let factor: Double
    /// Precomputed once, as in the reference — recomputing it per review invites drift.
    private let intervalModifier: Double

    init(parameters: FSRSParameters = .fsrs6) {
        self.parameters = parameters
        // FSRS-6 learns the decay: it is w[20] rather than the fixed -0.5 of FSRS-5.
        let decay = -parameters.w[20]
        self.decay = decay
        let factor = Self.rounded(exp(log(0.9) / decay) - 1)
        self.factor = factor
        self.intervalModifier = Self.rounded(
            (pow(parameters.requestRetention, 1 / decay) - 1) / factor)
    }

    private var w: [Double] { parameters.w }

    // MARK: - The transition

    /// The memory state after a review.
    ///
    /// - Parameters:
    ///   - memory: the state before, or `nil` for a meaning never reviewed.
    ///   - elapsedDays: whole days since the previous review. **Calendar days**, floored —
    ///     the caller must not divide seconds by 86400, because two reviews either side of
    ///     midnight are one day apart and must take the long-term path, while two in one
    ///     evening are zero days apart and must take the short-term one.
    ///   - grade: how the answer was judged.
    func next(_ memory: FSRSMemory?, elapsedDays: Double, grade: FSRSGrade) -> FSRSMemory {
        // A first review uses the init formulas *only*. Feeding a zeroed state into the
        // recall/forget formulas yields garbage — the reference guards the same way.
        guard let memory else { return initialMemory(grade) }

        let t = max(0, elapsedDays)
        let r = retrievability(elapsedDays: t, stability: memory.stability)

        var stability = recallStability(memory, retrievability: r, grade: grade)

        if grade == .again {
            // A lapse does not fall as far as the forget formula alone would put it: the
            // reference floors it at S / e^(w17·w18) when the short-term model is on.
            let w17 = parameters.enableShortTerm ? w[17] : 0
            let w18 = parameters.enableShortTerm ? w[18] : 0
            let floorS = memory.stability / exp(w17 * w18)
            stability = clamp(floorS,
                              FSRSParameters.minimumStability,
                              forgetStability(memory, retrievability: r))
        }

        // Order matters: a same-day review overrides both branches above.
        if t == 0 && parameters.enableShortTerm {
            stability = shortTermStability(memory.stability, grade: grade)
        }

        return FSRSMemory(stability: stability,
                          difficulty: nextDifficulty(memory.difficulty, grade: grade))
    }

    /// The state a meaning is in after its very first review.
    func initialMemory(_ grade: FSRSGrade) -> FSRSMemory {
        FSRSMemory(stability: max(w[grade.rawValue - 1], 0.1),
                   difficulty: constrainDifficulty(initialDifficultyRaw(grade)))
    }

    // MARK: - Reading the state

    /// Probability of recalling this meaning right now, 0…1 — FSRS's forgetting curve.
    ///
    /// `R(t, S) = (1 + FACTOR · t / S)^DECAY`
    func retrievability(elapsedDays: Double, stability: Double) -> Double {
        guard stability > 0 else { return 0 }
        return Self.rounded(pow(1 + (factor * max(0, elapsedDays)) / stability, decay))
    }

    /// Days until this meaning should be reviewed again, for the requested retention.
    func interval(stability: Double) -> Double {
        min(max(1, (stability * intervalModifier).rounded()), parameters.maximumInterval)
    }

    // MARK: - Stability

    private func recallStability(_ memory: FSRSMemory,
                                 retrievability r: Double,
                                 grade: FSRSGrade) -> Double {
        let hardPenalty = grade == .hard ? w[15] : 1
        let easyBonus = grade == .easy ? w[16] : 1
        let growth = exp(w[8])
            * (11 - memory.difficulty)
            * pow(memory.stability, -w[9])
            * (exp((1 - r) * w[10]) - 1)
            * hardPenalty * easyBonus
        return Self.rounded(clamp(memory.stability * (1 + growth),
                                  FSRSParameters.minimumStability, 36_500))
    }

    private func forgetStability(_ memory: FSRSMemory, retrievability r: Double) -> Double {
        let value = w[11]
            * pow(memory.difficulty, -w[12])
            * (pow(memory.stability + 1, w[13]) - 1)
            * exp((1 - r) * w[14])
        return Self.rounded(clamp(value, FSRSParameters.minimumStability, 36_500))
    }

    /// Same-day reviews. FSRS-6 adds an `S^-w19` term and a floor that stops any grade
    /// above Again from *shrinking* stability.
    private func shortTermStability(_ stability: Double, grade: FSRSGrade) -> Double {
        let increase = pow(stability, -w[19])
            * exp(w[17] * (Double(grade.rawValue) - 3 + w[18]))
        let masked = grade.rawValue >= FSRSGrade.hard.rawValue ? max(increase, 1) : increase
        return Self.rounded(clamp(stability * masked,
                                  FSRSParameters.minimumStability, 36_500))
    }

    // MARK: - Difficulty

    private func nextDifficulty(_ difficulty: Double, grade: FSRSGrade) -> Double {
        let delta = -(w[6] * Double(grade.rawValue - 3))
        // Linear damping: a change matters less the harder the item already is.
        let damped = difficulty + Self.rounded(delta * (10 - difficulty) / 9)
        // Mean-reverts toward the *Easy* initial difficulty, not the Good one — and in
        // FSRS-6 toward its raw, unclamped value.
        let target = initialDifficultyRaw(.easy)
        return constrainDifficulty(Self.rounded(w[7] * target + (1 - w[7]) * damped))
    }

    private func initialDifficultyRaw(_ grade: FSRSGrade) -> Double {
        Self.rounded(w[4] - exp(Double(grade.rawValue - 1) * w[5]) + 1)
    }

    private func constrainDifficulty(_ value: Double) -> Double {
        min(max(Self.rounded(value), 1), 10)
    }

    // MARK: - Arithmetic

    private func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(max(value, low), high)
    }

    /// The reference rounds to 8 decimal places after most steps, and the rounding is
    /// load-bearing: without it, drift accumulates across a long history and replayed
    /// values diverge from the library's. It does this by formatting to a string; this
    /// does it arithmetically, which agrees everywhere except at exact half-ulp ties.
    private static func rounded(_ value: Double) -> Double {
        guard value.isFinite else { return value }
        return (value * 1e8).rounded() / 1e8
    }
}

// MARK: - Elapsed days

extension FSRSAlgorithm {

    /// Whole days between two reviews, by **calendar** boundary.
    ///
    /// Not `seconds / 86400`: the two disagree whenever reviews straddle midnight, and the
    /// short-term path fires exactly when this returns zero — so the wrong one silently
    /// applies the wrong formula. The reference makes the same distinction
    /// (`dateDiffInDays` vs `dateDiff(unit:.days)`).
    static func elapsedDays(from earlier: Date, to later: Date,
                            calendar: Calendar = .current) -> Double {
        let start = calendar.startOfDay(for: earlier)
        let end = calendar.startOfDay(for: later)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return Double(max(0, days))
    }
}
