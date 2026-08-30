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

@MainActor
struct SetSummaryTests {

    /// Midday GMT, deliberately. The forecast buckets by calendar day, so a `now` near
    /// midnight lets a fractional offset land either side of it — 1_700_000_000 is 22:13 UTC,
    /// and the day-index expectations below silently encoded a UTC+3 machine.
    private let now = Date(timeIntervalSince1970: 1_699_963_200)

    /// **Pinned to GMT, like `FSRSMemoryTests`.** The forecast buckets by calendar *day*, and
    /// `now` here is 22:13 UTC — so with a machine calendar the fractional offsets below fall
    /// on different days either side of midnight, and the suite passed in UTC+3 while failing
    /// in UTC. A test about day arithmetic must not read the machine's clock settings.
    /// Reported by review, PR #5.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

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
                       // Due when there is no date, or when the date has passed. The earlier
                       // fixture said `days == nil`, which made a strand overdue by five days
                       // report "not due" — an impossible state that would mislead the next
                       // test to read it. Reported by review, PR #3.
                       isDue: days.map { $0 <= 0 } ?? true,
                       successfulDays: engaged ? 2 : 0)
    }

    /// - Parameter everyExercise: give the same strand to all three, so nothing is untouched.
    ///   The forecast counts a meaning with *any* untried exercise as due today, which is
    ///   correct and would otherwise swamp a test about due *dates*.
    private func progress(_ pairs: [(Sense, StrandProgress)],
                          effort: Float = 0.5,
                          answers: [ReviewDirection: Int] = [:],
                          everyExercise: Bool = false) -> ProgressIndex {
        var scored: [UUID: SenseProgress] = [:]
        for (sense, strand) in pairs {
            let strands = everyExercise
                ? Dictionary(uniqueKeysWithValues: Exercise.allCases.map { ($0, strand) })
                : [Exercise.learning: strand]
            scored[sense.id] = SenseProgress(strands: strands, effort: effort,
                                             answersByDirection: answers,
                                             isDue: strands.values.contains { $0.isDue })
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
            histories: [:], now: now, calendar: calendar)
        let polarised = SetSummary(
            senses: extremes,
            progress: progress(extremes.enumerated().map { index, sense in
                (sense, index < 2 ? strand(mastery: 1) : strand(mastery: 0, engaged: false))
            }),
            histories: [:], now: now, calendar: calendar)

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
                                 histories: [:], now: now, calendar: calendar)

        #expect(summary.distribution(for: .learning).learned == 3)
        #expect(summary.distribution(for: .dictation).untouched == 3,
                "dictation was never practised, so it is not three failures")
    }

    /// Untouched words report retention 1, so averaging them in let a mostly-new set paint a
    /// healthy ring over an overdue practised half — the warning colour arriving only once few
    /// words were left untouched, which is backwards. Anki excludes unseen cards from its
    /// retrievability average for the same reason. Reported by review, PR #5.
    @Test func untouchedWordsDoNotDiluteTheWarningColour() {
        let practised = sense("practised")
        let untouched = (0..<9).map { sense("new\($0)") }
        var scored: [UUID: SenseProgress] = [
            practised.id: SenseProgress(
                strands: [.learning: strand(mastery: 0.5, retention: 0.2, dueIn: -1)],
                effort: 0.5, answersByDirection: [:], isDue: true),
        ]
        for word in untouched {
            scored[word.id] = SenseProgress(strands: [:], effort: 0,
                                            answersByDirection: [:], isDue: true)
        }
        let summary = SetSummary(senses: [practised] + untouched,
                                 progress: ProgressIndex(scored: scored),
                                 histories: [:], now: now, calendar: calendar)

        #expect(summary.distribution(for: .learning).meanRetention == 0.2,
                "the one word anyone could forget is the one that colours the ring")
    }

    /// Nothing engaged is nothing at risk — an untouched exercise must not read as failing.
    @Test func anExerciseWithNothingEngagedIsNotAtRisk() {
        let words = (0..<3).map { sense("w\($0)") }
        let summary = SetSummary(
            senses: words,
            progress: progress(words.map { ($0, strand(mastery: 0, engaged: false)) }),
            histories: [:], now: now, calendar: calendar)

        #expect(summary.distribution(for: .dictation).meanRetention == 1)
    }

    // MARK: - The forecast

    @Test func theForecastCountsMeaningsOnTheDayTheyComeDue() {
        let words = (0..<4).map { sense("w\($0)") }
        let due: [Double?] = [0.1, 2.2, 2.4, 30]
        let summary = SetSummary(
            senses: words,
            progress: progress(zip(words, due).map { ($0, strand(mastery: 0.5, dueIn: $1)) },
                               everyExercise: true),
            histories: [:], now: now, calendar: calendar)

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
            progress: progress(zip(words, [-3.0, -40.0]).map { ($0, strand(mastery: 0.5, dueIn: $1)) },
                               everyExercise: true),
            histories: [:], now: now, calendar: calendar)

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
            histories: [:], now: now, calendar: calendar)

        #expect(summary.dueNow == 3, "a new set is all work waiting, not nothing")
        #expect(summary.dueForecast[1] == 0, "and it is waiting today, not tomorrow")
    }

    /// A meaning answered once in one exercise still has two untried, and those are asked
    /// immediately — so it is work waiting today, not work waiting on its Learning date.
    /// Otherwise the same screen showed those exercises as untouched while the forecast filed
    /// the meaning a week out. Reported by review, PR #5.
    @Test func aPartlyPractisedMeaningIsDueToday() {
        let word = sense("bear")
        // Engaged and not-yet-due in Learning; dictation and phonetics never tried.
        //
        // **`isDue: false`, which is what the real replay produces** — it is
        // `strands.isEmpty || strands.values.contains(where: \.isDue)` over *engaged* strands
        // only, so the two untried exercises are not in the dictionary to be asked. The first
        // version of this test set `isDue: true` by hand and so passed against a fix that did
        // nothing in production. Reported by review, PR #5.
        let partly = SenseProgress(
            strands: [.learning: strand(mastery: 0.5, dueIn: 7)],
            effort: 0.4, answersByDirection: [.receptive: 1], isDue: false)
        let summary = SetSummary(senses: [word],
                                 progress: ProgressIndex(scored: [word.id: partly]),
                                 histories: [:], now: now, calendar: calendar)

        #expect(summary.dueNow == 1, "dictation and phonetics were never tried, so it is asked now")
        #expect(summary.dueForecast[7] == 0, "not filed on the one date it happens to have")
    }

    /// The same claim end to end, through `ScoringPolicy` rather than a hand-built fixture —
    /// which is the only way to know the production path agrees. Reported by review, PR #5.
    @Test func aPartlyPractisedMeaningIsDueTodayThroughTheRealReplay() throws {
        let lexicon = Lexicon(persistence: LWPersistence(inMemory: true))
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        try lexicon.addSenses(to: set.id, terms: [
            [Term.Draft("bear", in: "en"), Term.Draft("медведь", in: "ru")],
        ])
        let senses = try lexicon.senses(in: set.id)

        // One correct Learning answer: that strand is scheduled forward, the other two have
        // never been asked.
        try lexicon.record(ReviewEvent.Draft(
            senseID: senses[0].id, sessionID: UUID(), wordSetID: set.id,
            promptTermID: senses[0].terms[0].id, task: .learning, direction: .receptive,
            outcome: .correctVerbatim, prompt: "bear", expected: "медведь",
            promptLanguage: "en", answerLanguage: "ru"))

        let histories = try lexicon.history(ofSenses: senses.map(\.id))
        let policy = ScoringPolicy.default
        let scored = senses.reduce(into: [UUID: SenseProgress]()) { result, sense in
            result[sense.id] = policy.progress(replaying: histories[sense.id] ?? [], now: now)
        }
        #expect(scored[senses[0].id]?.isDue == false,
                "precondition: the engaged-only reading says 'not due', which is the trap")

        let summary = SetSummary(senses: senses, progress: ProgressIndex(scored: scored),
                                 histories: histories, now: now, calendar: calendar)

        #expect(summary.dueNow == 1)
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
                                 histories: [:], now: now, calendar: calendar)

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
            now: now, calendar: calendar)

        #expect(summary.retention.young == 0.5)
        #expect(summary.retention.mature == 0.75)
    }

    /// Nothing answered is not nought percent remembered — it is nothing to report.
    @Test func retentionIsAbsentRatherThanZeroWhenNothingWasAnswered() {
        let word = sense("bear")
        let summary = SetSummary(senses: [word],
                                 progress: progress([(word, strand(mastery: 0, engaged: false))]),
                                 histories: [:], now: now, calendar: calendar)

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
            histories: [word.id: [answer(.correctVerbatim), reset]], now: now, calendar: calendar)

        #expect(summary.retention.youngTotal == 1, "the marker is not an answer")
        #expect(summary.retention.young == 1)
    }

    /// A skip is exposure, not retrieval — the learner never claimed anything. Counting it
    /// as a miss showed a worse record than the learner had. Reported by review, PR #5.
    @Test func aSkippedQuestionIsNotAWrongAnswer() {
        let word = sense("bear")
        let summary = SetSummary(
            senses: [word], progress: progress([(word, strand(mastery: 0.5))]),
            histories: [word.id: [answer(.correctVerbatim), answer(.skipped)]], now: now, calendar: calendar)

        #expect(summary.retention.youngTotal == 1, "the skip is not an answer to grade")
        #expect(summary.retention.young == 1, "one attempt, one success")
    }

    // MARK: - The receptive/productive gap

    @Test func theProductiveShareIsTheGapWorthShowing() {
        let words = [sense("a")]
        let summary = SetSummary(
            senses: words,
            progress: progress(words.map { ($0, strand(mastery: 0.5)) },
                               answers: [.receptive: 9, .productive: 1]),
            histories: [:], now: now, calendar: calendar)

        #expect(summary.answersByDirection[.receptive] == 9)
        #expect(summary.productiveShare == 0.1)
    }

    @Test func thereIsNoGapBeforeAnythingIsAnswered() {
        let words = [sense("a")]
        let summary = SetSummary(senses: words,
                                 progress: progress(words.map { ($0, strand(mastery: 0)) }),
                                 histories: [:], now: now, calendar: calendar)

        #expect(summary.productiveShare == nil)
    }

    @Test func anEmptySetSummarisesToNothingRatherThanCrashing() {
        let summary = SetSummary(senses: [], progress: ProgressIndex(scored: [:]),
                                 histories: [:], now: now, calendar: calendar)

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
