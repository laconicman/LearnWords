//
//  ProgressCache.swift
//  LearnWords
//
//  Scoring each meaning once per change rather than once per appearance (TD-52).
//
//  **Measured before built.** `ProgressCostTests` times what a replay costs, and the answer
//  is that a 500-meaning library takes about 180 ms to score and a 2,000-meaning one about
//  two seconds — paid on *every* appearance of the word list, because `viewDidAppear`
//  reloads. Release is barely faster than Debug, so the cost is not arithmetic waiting for
//  an optimiser: the fetch is roughly 1.4× the replay and both are real.
//
//  **In memory, not in the store.** A cache that persists would have to record
//  `ScoringPolicy.version` and live in the CloudKit schema, which is a migration and a sync
//  surface for a number that is always re-derivable. What actually hurts is *repetition*
//  within a session, and repetition is exactly what a process-lifetime cache removes: a
//  cold start still pays once. `ProgressModel` deferred the mechanism and said "not a schema
//  commitment"; this keeps that promise.
//
//  **Correctness before speed.** Every entry is dropped the moment anything appends to the
//  log, and the whole cache is dropped when another device changes the store. A stale
//  progress ring is worse than a slow one — it tells the learner something untrue about
//  their own memory.
//

import Foundation

/// Per-meaning progress, remembered until the log that produced it changes.
///
/// **`@MainActor`, because every writer already is.** `scored` is a plain dictionary mutated
/// from `index(for:in:)` and from three notification selectors; today that is safe only by
/// convention — `storeDidChangeRemotely` is posted on the main queue, and the only writers of
/// review events run on the main thread. A future background path (a batch import, a
/// sync-side replay) would mutate it concurrently with a read, so the assumption is pinned by
/// the compiler rather than left in a comment. Reported by review, PR #4.
@MainActor
final class ProgressCache {

    /// One cache for the app, matching the other shared controllers (`Library`,
    /// `SpeechManager`).
    ///
    /// **Not a property of `Library`**, which is where it belongs by subject: `Library.swift`
    /// is compiled into the widget extension too, and the widget has no scoring layer — no
    /// `ScoringPolicy`, no `SenseProgress`. Putting it there drags the whole of scoring into
    /// an extension that only wants a word count. When TD-5 lands proper injection, this
    /// becomes a dependency like the rest.
    static let shared = ProgressCache()

    private var scored: [UUID: SenseProgress] = [:]
    private let policy: ScoringPolicy

    /// The day the cached values describe. Retention decays with the clock, so an index
    /// computed yesterday answers a question nobody asked today.
    private var scoredOn: Date?

    private let calendar = Calendar.current

    init(policy: ScoringPolicy = .default) {
        self.policy = policy
        NotificationCenter.default.addObserver(
            self, selector: #selector(invalidateAll),
            name: LWPersistence.storeDidChangeRemotely, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(logDidGrow(_:)),
            name: Lexicon.didAppendToLog, object: nil)
        // **A preference is an input to every score.** `ScoringPolicy.masteryHorizonDays`
        // reads the horizon slider on *every use*, precisely so that moving it takes effect
        // without a relaunch, and `isLearned` reads `requireProductionForLearned` the same
        // way. Caching the results put the slider back to doing nothing until the day
        // turned — the exact bug that comment was written to prevent. Reported by review,
        // PR #4.
        NotificationCenter.default.addObserver(
            self, selector: #selector(scoringPreferencesMayHaveChanged),
            name: UserDefaults.didChangeNotification, object: nil)
    }

    /// The two preferences that are inputs to a score, as they were when it was computed.
    ///
    /// `UserDefaults.didChangeNotification` fires for *any* write anywhere in the process —
    /// the direction toggle, the speech-rate slider, a reminder time — none of which change a
    /// single number here. Dropping everything on all of them was correctness-safe but meant
    /// a trip through Settings cost a full replay on the way back. Comparing first keeps the
    /// invalidation honest and rare. Reported by review, PR #4.
    private struct ScoringPreferences: Equatable {
        let horizonDays: Int
        let requiresProduction: Bool

        init() {
            let defaults = LWUserDefaults.standard
            horizonDays = defaults.maxKnownLevelPreference
            requiresProduction = defaults.requireProductionForLearned
        }
    }

    private var preferences = ScoringPreferences()

    @objc private func scoringPreferencesMayHaveChanged() {
        let current = ScoringPreferences()
        guard current != preferences else { return }
        preferences = current
        invalidateAll()
    }

    /// Scores `senses`, replaying only the ones not already known.
    ///
    /// The misses are fetched in **one** pass, so a cold screen costs what it always did
    /// and a warm one costs nothing. Meanings the caller did not ask about are left alone:
    /// this is a cache, not the set of everything ever scored.
    func index(for senses: [Sense], in lexicon: Lexicon, now: Date = Date()) throws -> ProgressIndex {
        expireIfTheDayTurned(now)

        let missing = senses.filter { scored[$0.id] == nil }
        if !missing.isEmpty {
            let histories = try lexicon.history(ofSenses: missing.map(\.id))
            for sense in missing {
                scored[sense.id] = policy.progress(replaying: histories[sense.id] ?? [], now: now)
            }
            scoredOn = now
        }

        return ProgressIndex(scored: senses.reduce(into: [:]) { result, sense in
            result[sense.id] = scored[sense.id]
        })
    }

    /// Retention is a function of elapsed time, so yesterday's answers are yesterday's.
    ///
    /// A day is the right granularity: `dueAt` and the two-distinct-day gate are both
    /// counted in days, and re-scoring a whole library on a timer would spend more than it
    /// saves.
    private func expireIfTheDayTurned(_ now: Date) {
        guard let scoredOn, !calendar.isDate(scoredOn, inSameDayAs: now) else { return }
        scored.removeAll()
    }

    @objc private func invalidateAll() {
        scored.removeAll()
        // Cleared with the entries it describes. Harmless while the next call re-stamps it,
        // but a stamp outliving everything it stamped is a trap for the next reader.
        scoredOn = nil
    }

    /// One meaning changed, so one entry goes — the rest of the screen stays warm.
    @objc private func logDidGrow(_ note: Notification) {
        guard let senseID = note.userInfo?[Lexicon.senseIDKey] as? UUID else {
            return invalidateAll()
        }
        scored.removeValue(forKey: senseID)
    }
}
