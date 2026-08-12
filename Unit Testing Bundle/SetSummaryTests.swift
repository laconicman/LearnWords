//
//  SetSummaryTests.swift
//  Unit Testing Bundle
//
//  The set summary (TD-51), and the trap it exists to avoid: a mean of 0.5 is produced both
//  by fifty half-learned words and by twenty-five mastered plus twenty-five untouched, and
//  those two sets need opposite actions. The first test here is that one — everything else
//  is a detail beside it.
//
//  Pure: the summary reads values it is handed, so these build progress directly rather
//  than through a store, and the clock is passed in.
//

import Testing
import Foundation
@testable import LearnWords

struct SetSummaryTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func sense(_ name: String) -> Sense {
        Sense(id: UUID(), note: nil,
              terms: [Term(id: UUID(), text: name, language: "en",
                           transcription: nil, partOfSpeech: nil)],
              tags: [])
    }

    private func strand(mastery: Float, retention: Float = 1,
                        stability: Double = 5, dueIn days: Double? = nil,
                        engaged: Bool = true) -> StrandProgress {
        StrandProgress(mastery: mastery, retention: retention,
                       memory: engaged ? FSRSMemory(stability: stability, difficulty: 5) : nil,
                       lastReviewedAt: engaged ? now : nil,
                       dueAt: days.map { now.addingTimeInterval($0 * 86_400) },
                       isDue: days == nil,
                       successfulDays: engaged ? 2 : 0)
    }

    private func progress(_ pairs: [(Sense, StrandProgress)],
                          effort: Float = 0.5,
                          answers: [ReviewDirection: Int] = [:]) -> ProgressIndex {
        var scored: [UUID: SenseProgress] = [:]
        for (sense, strand) in pairs {
            scored[sense.id] = SenseProgress(strands: [.learning: strand], effort: effort,
                                             answersByDirection: answers, isDue: strand.isDue)
        }
        return ProgressIndex(scored: scored)
    }

    // MARK: - The trap

    /// Two sets with the same mean and opposite needs. The distribution has to tell them
    /// apart; the mean is reported beside it precisely because on its own it cannot.
    @Test func theSameMeanDescribesTwoOppositeSets() {
        let halves = (0..<4).map { sense("half\($0)") }
        let extremes = (0..<4).map { sense("edge\($0)") }

        let halfLearned = SetSummary(
            senses: halves,
            progress: progress(halves.map { ($0, strand(mastery: 0.5)) }),
            histories: [:], now: now)
        let polarised = SetSummary(
            senses: extremes,
            progress: progress(extremes.enumerated().map { index, sense in
                (sense, index < 2 ? strand(mastery: 1) : strand(mastery: 0, engaged: false))
            }),
            histories: [:], now: now)

        let a = halfLearned.distribution(for: .learning)
        let b = polarised.distribution(for: .learning)

        #expect(a.meanMastery == b.meanMastery, "precondition: the means agree")
        #expect(a.learning == 4 && a.learned == 0 && a.untouched == 0)
        #expect(b.learning == 0 && b.learned == 2 && b.untouched == 2,
                "the distribution is what tells the two sets apart")
    }

    /// An exercise never opened is *untouched*, not failing — the same rule the per-term
    /// screen follows, and the reason a fresh set does not read as a set of failures.
    @Test func anExerciseNeverPractisedCountsAsUntouched() {
        let words = (0..<3).map { sense("w\($0)") }
        let summary = SetSummary(senses: words,
                                 progress: progress(words.map { ($0, strand(mastery: 1)) }),
                                 histories: [:], now: now)

        #expect(summary.distribution(for: .learning).learned == 3)
        #expect(summary.distribution(for: .dictation).untouched == 3,
                "dictation was never practised, so it is not three failures")
    }

    // MARK: - The forecast

    @Test func theForecastCountsMeaningsOnTheDayTheyComeDue() {
        let words = (0..<4).map { sense("w\($0)") }
        let due: [Double?] = [0.1, 2.2, 2.4, 30]
        let summary = SetSummary(
            senses: words,
            progress: progress(zip(words, due).map { ($0, strand(mastery: 0.5, dueIn: $1)) }),
            histories: [:], now: now)

        #expect(summary.dueForecast.count == SetSummary.forecastDays)
        #expect(summary.dueForecast[0] == 1)
        #expect(summary.dueForecast[2] == 2, "two meanings land on the same day")
        #expect(summary.dueForecast.reduce(0, +) == 3, "the one 30 days out is beyond the window")
    }

    /// Overdue work is waiting *today*. Filing it under a past day would put it somewhere
    /// the forecast cannot show, which is the same as hiding it.
    @Test func overdueMeaningsCountAsDueToday() {
        let words = [sense("late"), sense("later")]
        let summary = SetSummary(
            senses: words,
            progress: progress(zip(words, [-3.0, -40.0]).map { ($0, strand(mastery: 0.5, dueIn: $1)) }),
            histories: [:], now: now)

        #expect(summary.dueForecast[0] == 2)
        #expect(summary.dueNow == 2)
    }

    /// A meaning never practised has no due date and is due *now*. Reading only `dueAt`
    /// made a brand-new set report "Nothing due" beside a full queue — the same lie PR #1's
    /// review found in the chooser. Found on the device, not by these tests.
    @Test func meaningsNeverPractisedAreDueToday() {
        let words = (0..<3).map { sense("w\($0)") }
        let summary = SetSummary(
            senses: words,
            progress: progress(words.map { ($0, strand(mastery: 0, engaged: false)) }),
            histories: [:], now: now)

        #expect(summary.dueNow == 3, "a new set is all work waiting, not nothing")
        #expect(summary.dueForecast[1] == 0, "and it is waiting today, not tomorrow")
    }

    /// A meaning due in three exercises is one piece of work arriving, not three.
    @Test func theForecastCountsMeaningsNotStrands() {
        let word = sense("bear")
        let everywhere = SenseProgress(
            strands: [.learning: strand(mastery: 0.5, dueIn: 1),
                      .dictation: strand(mastery: 0.5, dueIn: 1),
                      .phonetics: strand(mastery: 0.5, dueIn: 1)],
            effort: 0.5, answersByDirection: [:], isDue: false)
        let summary = SetSummary(senses: [word],
                                 progress: ProgressIndex(scored: [word.id: everywhere]),
                                 histories: [:], now: now)

        #expect(summary.dueForecast[1] == 1)
    }

    // MARK: - Retention

    /// Anki's split, and the reason it is computed from the log rather than from the score:
    /// a word answered wrong ten times and right once today looks, right now, exactly like
    /// one answered right once.
    @Test func retentionIsSplitYoungFromMature() {
        let young = sense("new")
        let mature = sense("old")
        let scored = ProgressIndex(scored: [
            young.id: SenseProgress(strands: [.learning: strand(mastery: 0.4, stability: 3)],
                                    effort: 0.3, answersByDirection: [:], isDue: true),
            mature.id: SenseProgress(strands: [.learning: strand(mastery: 1, stability: 60)],
                                     effort: 0.9, answersByDirection: [:], isDue: false),
        ])
        let summary = SetSummary(
            senses: [young, mature], progress: scored,
            histories: [young.id: [answer(.incorrect), answer(.correctVerbatim)],
                        mature.id: [answer(.correctVerbatim), answer(.correctVerbatim),
                                    answer(.correctVerbatim), answer(.incorrect)]],
            now: now)

        #expect(summary.retention.young == 0.5)
        #expect(summary.retention.mature == 0.75)
    }

    /// Nothing answered is not nought percent remembered — it is nothing to report.
    @Test func retentionIsAbsentRatherThanZeroWhenNothingWasAnswered() {
        let word = sense("bear")
        let summary = SetSummary(senses: [word],
                                 progress: progress([(word, strand(mastery: 0, engaged: false))]),
                                 histories: [:], now: now)

        #expect(summary.retention.young == nil)
        #expect(summary.retention.mature == nil)
    }

    /// A reset marker carries no grade, so it must not be counted as a wrong answer.
    @Test func aProgressResetIsNotAWrongAnswer() {
        let word = sense("bear")
        var reset = answer(.correctVerbatim)
        reset.kind = .progressReset
        reset.outcome = nil
        let summary = SetSummary(
            senses: [word], progress: progress([(word, strand(mastery: 0.5))]),
            histories: [word.id: [answer(.correctVerbatim), reset]], now: now)

        #expect(summary.retention.youngTotal == 1, "the marker is not an answer")
        #expect(summary.retention.young == 1)
    }

    // MARK: - The receptive/productive gap

    @Test func theProductiveShareIsTheGapWorthShowing() {
        let words = [sense("a")]
        let summary = SetSummary(
            senses: words,
            progress: progress(words.map { ($0, strand(mastery: 0.5)) },
                               answers: [.receptive: 9, .productive: 1]),
            histories: [:], now: now)

        #expect(summary.answersByDirection[.receptive] == 9)
        #expect(summary.productiveShare == 0.1)
    }

    @Test func thereIsNoGapBeforeAnythingIsAnswered() {
        let words = [sense("a")]
        let summary = SetSummary(senses: words,
                                 progress: progress(words.map { ($0, strand(mastery: 0)) }),
                                 histories: [:], now: now)

        #expect(summary.productiveShare == nil)
    }

    @Test func anEmptySetSummarisesToNothingRatherThanCrashing() {
        let summary = SetSummary(senses: [], progress: ProgressIndex(scored: [:]),
                                 histories: [:], now: now)

        #expect(summary.total == 0)
        #expect(summary.meanEffort == 0)
        #expect(summary.distribution(for: .learning).total == 0)
        #expect(summary.dueForecast.allSatisfy { $0 == 0 })
    }

    private func answer(_ outcome: ReviewOutcome) -> ReviewEvent {
        ReviewEvent(id: UUID(), senseID: nil, date: now, sessionID: UUID(),
                    kind: ReviewEventKind.answer, outcome: outcome,
                    task: Exercise.learning, direction: ReviewDirection.receptive,
                    prompt: "", expected: "", response: nil, latencyMS: nil,
                    errorTags: [], schemaVersion: 2)
    }
}
