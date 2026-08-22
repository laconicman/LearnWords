//
//  SetSummary.swift
//  LearnWords
//
//  How a whole set stands (TD-51) — as a *distribution*, not as a mean.
//
//  **The trap this type exists to avoid.** A mean mastery of 0.5 is produced both by fifty
//  half-learned words and by twenty-five mastered plus twenty-five untouched, and those two
//  sets need opposite actions (docs/MasteryAndProgressUI.md §3.1). Averages also hide the
//  thing an SRS learner most needs to see: *when the work is coming*. So the headline is a
//  distribution and a forecast; the averages the owner asked for are computed too, and shown
//  beside them rather than instead of them.
//
//  Anki's statistics screen is the reference — Card Counts, Future Due and True Retention,
//  the last being the number its community adopted precisely because it is harder to fool
//  than any average.
//
//  **Pivoted by exercise**, because since TD-49 memory is kept per exercise: a set can be
//  solid as flashcards and failing in dictation, and one bar for the set would say neither.
//
//  Pure. Everything here is a reading of `SenseProgress` and the event log; nothing fetches,
//  and the clock is a parameter.
//

import Foundation

struct SetSummary: Equatable {

    /// Where each meaning stands in one exercise. Three buckets, because the question the
    /// learner asks is "how much have I not started, how much is in flight, how much is
    /// done" — and a bar with more segments than that is read as decoration.
    struct Distribution: Equatable {
        var untouched = 0
        var learning = 0
        var learned = 0

        var total: Int { untouched + learning + learned }

        /// The requested averages, kept **beside** the distribution that qualifies them.
        var meanMastery: Float = 0
        /// Mean chance of recall right now — what colours this exercise's ring. The owner's
        /// call on TD-51's open question: rings always fill one way and colour carries the
        /// bad news, because a reversed arc reads as an animation bug.
        var meanRetention: Float = 1
    }

    /// Answers already given, bucketed by how well the meaning is known **now**.
    ///
    /// **An approximation of Anki's young/mature split, not the thing itself.** Confirmed
    /// against `ankitects/anki`: it buckets each review by `revlog.last_interval` — the
    /// interval the card held *before that specific review*, stored in the row — so the split
    /// is fully historical, and a card that has since matured or been reset does not
    /// retroactively change how its old reviews are counted. This buckets every answer for a
    /// meaning by the meaning's *current* stability, so once a word passes 21 days its early
    /// struggles are counted as mature and the young bucket empties. Recoverable here by
    /// replaying the log and reading stability per answer, which is more machinery than a
    /// first cut needs — recorded rather than glossed. Reported by review, PR #5.
    ///
    /// The *exclusions* do line up: Anki drops entries with no rating (manual reschedules,
    /// set-due-date, reset) and no-reschedule cram reviews, counting only real graded
    /// retrievals. Our equivalents are `.progressReset`, which `kind == .answer` filters, and
    /// `.skipped`, excluded below for the same reason.
    struct Retention: Equatable {
        var youngCorrect = 0
        var youngTotal = 0
        var matureCorrect = 0
        var matureTotal = 0

        var young: Float? { youngTotal == 0 ? nil : Float(youngCorrect) / Float(youngTotal) }
        var mature: Float? { matureTotal == 0 ? nil : Float(matureCorrect) / Float(matureTotal) }
    }

    /// One distribution per exercise, in `Exercise.allCases` order.
    let byExercise: [Exercise: Distribution]

    /// How many meanings come due on each of the next `forecastDays` days, today first.
    ///
    /// Counts, not dates: the question is "how much work is coming on Thursday", and a list
    /// of timestamps cannot be read as a shape.
    let dueForecast: [Int]

    let retention: Retention

    /// Work invested across the set, 0…1 per meaning, summed and averaged. Never falls —
    /// the one number a bad week cannot take away.
    let meanEffort: Float

    /// Graded answers by direction. The gap between them is the receptive/productive story
    /// that no surveyed competitor shows.
    let answersByDirection: [ReviewDirection: Int]

    /// Meanings in the set, however they stand.
    let total: Int

    /// The window `dueForecast` covers. Two weeks: long enough to show the shape of a
    /// backlog, short enough that every bar is a day the learner can picture.
    static let forecastDays = 14

    /// Below this many days of stability an answer counts as *young*.
    ///
    /// Anki's own boundary — `MATURE_IVL` in `rslib/src/stats/graphs/retention.rs`, verified
    /// against the source rather than from memory — so a learner who has met the number
    /// elsewhere reads this one the same way.
    static let matureAfterDays: Double = 21
}

extension SetSummary {

    /// Reads a whole set.
    ///
    /// - Parameter histories: the event log per meaning. Needed for retention, which is a
    ///   statement about answers *already given* and cannot be recovered from the current
    ///   score — a word answered wrong ten times and right once today looks identical to
    ///   one answered right once, and they are not the same learner.
    init(senses: [Sense],
         progress: ProgressIndex,
         histories: [UUID: [ReviewEvent]],
         now: Date = Date(),
         calendar: Calendar = .current) {
        var byExercise: [Exercise: Distribution] = [:]
        var forecast = [Int](repeating: 0, count: Self.forecastDays)
        var retention = Retention()
        var effort: Float = 0
        var answers: [ReviewDirection: Int] = [:]

        let today = calendar.startOfDay(for: now)

        for exercise in Exercise.allCases {
            var distribution = Distribution()
            var masterySum: Float = 0
            var retentionSum: Float = 0
            for sense in senses {
                let strand = progress[sense.id][exercise]
                masterySum += strand.mastery
                retentionSum += strand.retention
                if !strand.isEngaged {
                    distribution.untouched += 1
                } else if strand.mastery >= 1 {
                    distribution.learned += 1
                } else {
                    distribution.learning += 1
                }
            }
            distribution.meanMastery = senses.isEmpty ? 0 : masterySum / Float(senses.count)
            distribution.meanRetention = senses.isEmpty ? 1 : retentionSum / Float(senses.count)
            byExercise[exercise] = distribution
        }

        for sense in senses {
            let senseProgress = progress[sense.id]
            effort += senseProgress.effort
            for (direction, count) in senseProgress.answersByDirection {
                answers[direction, default: 0] += count
            }

            // The forecast asks *the meaning*, not each strand: a word coming up in any
            // exercise is work arriving that day, and counting it three times would make a
            // thoroughly practised set look overwhelming.
            // **Asked "is it due" before "when is it due"** — and asked of *every* exercise,
            // not of `SenseProgress.isDue`.
            //
            // `isDue` is `strands.isEmpty || strands.values.contains(where: \.isDue)`, and
            // `strands` holds only exercises that have been graded, so a meaning answered once
            // in Learning and never in dictation reports `false`: its one engaged strand is
            // not due yet, and the two untried ones are not in the dictionary to be asked.
            // Subscripting instead returns `.untouched` for a missing strand, which *is* due —
            // the same "any exercise" reading `ReviewSchedule.anyExerciseDueCount` uses, and
            // the one the buttons on the practice screen act on. Reported twice by review,
            // PR #5: the first fix read `isDue` and did nothing.
            let isDueInAnyExercise = Exercise.allCases.contains { senseProgress[$0].isDue }
            if isDueInAnyExercise {
                forecast[0] += 1
            } else if let dueAt = senseProgress.dueAt {
                let day = calendar.dateComponents([.day], from: today,
                                                  to: calendar.startOfDay(for: dueAt)).day ?? 0
                if day >= 0 && day < Self.forecastDays {
                    forecast[day] += 1
                } else if day < 0 {
                    // Overdue is work waiting today, not work that happened in the past.
                    forecast[0] += 1
                }
            }

            let isMature = (senseProgress.memory?.stability ?? 0) >= Self.matureAfterDays
            for event in histories[sense.id] ?? [] where event.kind == .answer {
                // **A skip is not a wrong answer.** It is exposure, not retrieval — the
                // learner never claimed anything — and `ReviewOutcome.skipped.isPositive`
                // being `false` would have counted every skipped question as a miss, showing
                // a worse record than the learner has. Everywhere else in the model a skip
                // is excluded rather than penalised. Reported by review, PR #5.
                guard let outcome = event.outcome, outcome != .skipped else { continue }
                if isMature {
                    retention.matureTotal += 1
                    if outcome.isPositive { retention.matureCorrect += 1 }
                } else {
                    retention.youngTotal += 1
                    if outcome.isPositive { retention.youngCorrect += 1 }
                }
            }
        }

        self.byExercise = byExercise
        self.dueForecast = forecast
        self.retention = retention
        self.meanEffort = senses.isEmpty ? 0 : effort / Float(senses.count)
        self.answersByDirection = answers
        self.total = senses.count
    }

    func distribution(for exercise: Exercise) -> Distribution {
        byExercise[exercise] ?? Distribution()
    }

    /// Meanings due today or already overdue — the first bar of the forecast, named because
    /// it is the one number the learner acts on.
    var dueNow: Int { dueForecast.first ?? 0 }

    /// The gap the receptive/productive split is for: how far production lags recognition.
    /// `nil` when nothing has been answered either way.
    var productiveShare: Float? {
        let receptive = answersByDirection[.receptive] ?? 0
        let productive = answersByDirection[.productive] ?? 0
        guard receptive + productive > 0 else { return nil }
        return Float(productive) / Float(receptive + productive)
    }
}
