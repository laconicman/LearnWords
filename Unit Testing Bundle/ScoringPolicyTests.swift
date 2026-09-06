//
//  ScoringPolicyTests.swift
//  Unit Testing Bundle
//
//  What the log means. `FSRSMemoryTests` proves the arithmetic matches the reference;
//  these prove this app's rules on top of it — the outcome→grade mapping, the three
//  indexes, and the interactions the owner asked for by name:
//
//  * a mistake never erases effort (R1/R3),
//  * a reset restarts mastery but not effort,
//  * only the first answer in a sitting is long-term evidence,
//  * a skip is exposure, not retrieval.
//

import Testing
import Foundation
@testable import LearnWords

@MainActor
@Suite(.serialized)
struct ScoringPolicyTests {

    /// A fixed horizon, so a case does not depend on the machine's stored preference.
    /// Both inputs named, for the same reason: these tests are about mastery arithmetic,
    /// and a policy that read either preference would make them depend on the owner's
    /// current settings — and on whatever a parallel test had just written.
    private let policy = ScoringPolicy(masteryHorizonDays: 20, minimumSuccessfulDays: 2)

    private let day: TimeInterval = 86_400
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// One graded answer. Defaults to a fresh sitting, since separate sittings are the
    /// normal case and same-sitting retries are the exception under test.
    private func answer(_ outcome: ReviewOutcome,
                        dayOffset: Double = 0,
                        session: UUID = UUID(),
                        latencyMS: Int? = nil,
                        expected: String = "медведь") -> ReviewEvent {
        ReviewEvent(id: UUID(), senseID: nil,
                    date: start.addingTimeInterval(dayOffset * day),
                    sessionID: session, kind: .answer, outcome: outcome,
                    task: .dictation, direction: .productive,
                    prompt: "bear", expected: expected, response: nil,
                    latencyMS: latencyMS, errorTags: [], schemaVersion: 1)
    }

    private func reset(dayOffset: Double) -> ReviewEvent {
        ReviewEvent(id: UUID(), senseID: nil,
                    date: start.addingTimeInterval(dayOffset * day),
                    sessionID: UUID(), kind: .progressReset, outcome: nil,
                    task: nil, direction: nil, prompt: "", expected: "",
                    response: nil, latencyMS: nil, errorTags: [], schemaVersion: 1)
    }

    /// A plausible study history: right answers at widening intervals.
    private func studied(days: [Double]) -> [ReviewEvent] {
        days.map { answer(.correctVerbatim, dayOffset: $0) }
    }

    private func progress(_ events: [ReviewEvent], onDay offset: Double) -> SenseProgress {
        policy.progress(replaying: events, now: start.addingTimeInterval(offset * day))
    }

    // MARK: - Nothing yet

    @Test func anUnseenMeaningHasNoMasteryAndNothingToForget() {
        let p = progress([], onDay: 0)
        #expect(p.mastery == 0)
        #expect(p.effort == 0)
        #expect(p.retention == 1, "there is nothing to have forgotten yet")
        #expect(p.memory == nil)
        #expect(p.dueAt == nil)
        #expect(p.isDue, "a new meaning is always worth asking")
        #expect(!p.isLearned)
    }

    // MARK: - Mastery

    @Test func masteryGrowsWithSuccessfulSpacedReview() {
        let one = progress(studied(days: [0]), onDay: 0).mastery
        let three = progress(studied(days: [0, 1, 4]), onDay: 4).mastery
        let five = progress(studied(days: [0, 1, 4, 12, 30]), onDay: 30).mastery
        #expect(one < three)
        #expect(three < five)
    }

    /// Mastery is a function of stability alone. Letting time into it would show
    /// forgetting twice — once in mastery and again in retention.
    @Test func masteryDoesNotFallWhileTimePasses() {
        let events = studied(days: [0, 1, 4, 12])
        let fresh = progress(events, onDay: 12)
        let stale = progress(events, onDay: 400)
        #expect(stale.mastery == fresh.mastery)
        #expect(stale.retention < fresh.retention, "retention is where decay shows")
    }

    @Test func aWellStudiedMeaningEventuallyCountsAsLearned() {
        #expect(!progress(studied(days: [0]), onDay: 0).isLearned)
        let long = progress(studied(days: [0, 1, 3, 8, 21, 60]), onDay: 60)
        #expect(long.isLearned, "past the 20-day horizon")
        #expect(long.mastery == 1)
    }

    @Test func aMistakeSetsMasteryBackWithoutErasingIt() {
        let studiedEvents = studied(days: [0, 1, 4, 12])
        let before = progress(studiedEvents, onDay: 12)
        let after = progress(studiedEvents + [answer(.incorrect, dayOffset: 20)], onDay: 20)
        #expect(after.mastery < before.mastery)
        #expect(after.mastery > 0, "a lapse is a setback, not a wipe")
    }

    // MARK: - Effort (R1/R3 — the index that is ours)

    @Test func effortOnlyEverGrows() {
        var events: [ReviewEvent] = []
        var last: Float = -1
        for day in stride(from: 0.0, to: 10.0, by: 1) {
            // Alternating right and wrong: mastery will lurch, effort must not.
            events.append(answer(day.truncatingRemainder(dividingBy: 2) == 0
                                 ? .correctVerbatim : .incorrect, dayOffset: day))
            let effort = progress(events, onDay: day).effort
            #expect(effort > last, "effort fell on day \(day)")
            last = effort
        }
    }

    /// The owner's headline requirement: much effort with little progress must be visible.
    @Test func aWordFoughtWithShowsHighEffortAndLowMastery() {
        let struggle = (0..<12).map { answer(.incorrect, dayOffset: Double($0)) }
        let p = progress(struggle, onDay: 12)
        #expect(p.effort > 0.7, "twelve sittings is real work")
        #expect(p.mastery < 0.3, "and it has not stuck")
    }

    @Test func aSkipIsWorthLessEffortThanAnAnswer() {
        let skipped = progress([answer(.skipped)], onDay: 0).effort
        let attempted = progress([answer(.incorrect)], onDay: 0).effort
        #expect(skipped > 0, "a skip is exposure, so it is not nothing")
        #expect(skipped < attempted)
    }

    @Test func aSkipMovesNoMemoryState() {
        let p = progress([answer(.skipped), answer(.skipped, dayOffset: 1)], onDay: 1)
        #expect(p.memory == nil, "exposure is not retrieval")
        #expect(p.mastery == 0)
        #expect(p.effort > 0)
    }

    @Test func comingBackAnotherDayCountsForMoreThanOneMoreAnswer() {
        let sitting = UUID()
        let inOneSitting = progress([answer(.correctVerbatim, session: sitting),
                                     answer(.incorrect, dayOffset: 0.1, session: sitting)],
                                    onDay: 1).effort
        let acrossTwo = progress([answer(.correctVerbatim),
                                  answer(.incorrect, dayOffset: 1)], onDay: 1).effort
        #expect(acrossTwo > inOneSitting, "persistence is worth something")
    }

    /// Spacing beats massing — the reason the app schedules at all.
    ///
    /// Note what this does *not* say: FSRS-6 does credit same-day repetition (its
    /// short-term model is exactly that), so cramming is not worthless. It is worth less.
    /// The old counter could not tell the two apart at all, because it had no clock.
    @Test func spacedAnswersBuildMoreStabilityThanCrammedOnes() {
        let crammed = progress((0..<5).map { answer(.correctVerbatim,
                                                    dayOffset: Double($0) * 0.01) },
                               onDay: 1)
        let spaced = progress(studied(days: [0, 1, 3, 7, 15]), onDay: 15)
        let massed = try! #require(crammed.memory).stability
        let distributed = try! #require(spaced.memory).stability
        #expect(distributed > massed, "five answers over two weeks beat five in an hour")
    }

    // MARK: - Sittings

    /// ProgressModel: only the first attempt per sitting is long-term evidence; retries
    /// inside it are effort. `sessionID` makes that exact.
    @Test func onlyTheFirstAnswerInASittingMovesTheSchedule() {
        let sitting = UUID()
        let once = progress([answer(.correctVerbatim, session: sitting)], onDay: 0)
        let retried = progress([answer(.correctVerbatim, session: sitting),
                                answer(.correctVerbatim, dayOffset: 0.01, session: sitting),
                                answer(.correctVerbatim, dayOffset: 0.02, session: sitting)],
                               onDay: 0)
        #expect(retried.memory == once.memory, "drilling does not multiply evidence")
        #expect(retried.effort > once.effort, "but it is effort")
    }

    // MARK: - Reset

    @Test func aResetRestartsMasteryButKeepsEffort() {
        let studiedEvents = studied(days: [0, 1, 4, 12])
        let before = progress(studiedEvents, onDay: 12)
        let after = progress(studiedEvents + [reset(dayOffset: 13)], onDay: 13)

        #expect(after.mastery == 0)
        #expect(after.memory == nil)
        #expect(after.dueAt == nil)
        #expect(after.effort == before.effort, "the work was still done")
    }

    @Test func answersAfterAResetBuildFromScratch() {
        let events = studied(days: [0, 1, 4, 12]) + [reset(dayOffset: 13)]
            + [answer(.correctVerbatim, dayOffset: 14)]
        let after = progress(events, onDay: 14)
        let fresh = progress(studied(days: [14]), onDay: 14)
        #expect(after.mastery == fresh.mastery, "as if the meaning were new")
        #expect(after.effort > fresh.effort, "except in effort")
    }

    // MARK: - Outcome → grade

    @Test func theGradeMappingFollowsTheEvidenceTiers() {
        #expect(policy.grade(for: answer(.incorrect)) == .again)
        #expect(policy.grade(for: answer(.selfAssessedForgot)) == .again)
        #expect(policy.grade(for: answer(.correctJudged)) == .hard)
        #expect(policy.grade(for: answer(.selfAssessedKnown)) == .good)
        #expect(policy.grade(for: answer(.skipped)) == nil)
    }

    @Test func aQuickExactAnswerRatesEasyAndASlowOneGood() {
        #expect(policy.grade(for: answer(.correctVerbatim, latencyMS: 800)) == .easy)
        #expect(policy.grade(for: answer(.correctVerbatim, latencyMS: 9_000)) == .good)
        #expect(policy.grade(for: answer(.correctVerbatim, latencyMS: nil)) == .good,
                "unmeasured is not fast")
    }

    /// A flat threshold would hand Easy to the button exercises and deny it to Dictation,
    /// which is a bias rather than mere imprecision.
    @Test func theFluencyAllowanceScalesWithTheLengthOfTheAnswer() {
        let short = answer(.correctVerbatim, latencyMS: 2_500, expected: "cat")
        let long = answer(.correctVerbatim, latencyMS: 2_500, expected: "полярный медведь")
        #expect(policy.grade(for: short) == .good)
        #expect(policy.grade(for: long) == .easy, "the same speed, over more characters")
    }

    /// Verbatim is stronger evidence than a matcher saying "close enough", which is
    /// stronger than nothing — and the schedule must reflect the order.
    @Test func strongerEvidenceEarnsMoreStability() {
        func stability(_ outcome: ReviewOutcome) -> Double {
            progress([answer(.correctVerbatim, dayOffset: 0),
                      answer(outcome, dayOffset: 10)], onDay: 10).memory?.stability ?? 0
        }
        #expect(stability(.correctJudged) < stability(.selfAssessedKnown))
        #expect(stability(.selfAssessedKnown) <= stability(.correctVerbatim))
    }

    // MARK: - Scheduling

    @Test func aReviewedMeaningIsNotDueUntilItsIntervalPasses() {
        let events = studied(days: [0, 1, 4, 12])
        let justReviewed = progress(events, onDay: 12)
        let due = try! #require(justReviewed.dueAt)
        #expect(due > start.addingTimeInterval(12 * day))
        #expect(!justReviewed.isDue)
        #expect(progress(events, onDay: 400).isDue)
    }

    /// FSRS-6 *learns* its decay exponent (w[20] ≈ 0.154) where FSRS-5 fixed it at 0.5, so
    /// the tail is far flatter: at eight times stability recall is still ~0.71, not ~0.35.
    /// Asserted as a shape rather than a threshold, so the case records that property
    /// instead of pinning a number I would only have guessed.
    @Test func retentionFallsSteadilyButSlowly() {
        let events = studied(days: [0, 1, 4, 12])
        let atReview = progress(events, onDay: 12).retention
        let later = progress(events, onDay: 60).retention
        let muchLater = progress(events, onDay: 400).retention
        #expect(atReview > 0.99)
        #expect(later < atReview)
        #expect(muchLater < later)
        #expect(muchLater > 0.5, "the long tail is the model, not a bug")
    }

    // MARK: - The index over many meanings

    @Test func theIndexScoresAWholeSetInOnePass() throws {
        let lexicon = Lexicon(persistence: LWPersistence(inMemory: true))
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        for word in ["bear", "camel", "fox"] {
            try lexicon.addSense(to: set.id, terms: [Term.Draft(word, in: "en"),
                                                     Term.Draft(word + "!", in: "ru")])
        }
        let senses = try lexicon.senses(in: set.id)
        let target = try #require(senses.first)

        let session = try PracticeSession.start(
            .dictation, in: set.id,
            languages: LanguagePair(primary: "ru", secondary: "en",
                                    showsSecondaryAsPrompt: true),
            lexicon: lexicon, scope: .everything(includingLearned: true))
        while let question = session.nextQuestion() {
            try session.record(question.sense.id == target.id ? .correctVerbatim : .skipped)
        }

        let index = try ProgressIndex(lexicon: lexicon, senses: senses)
        #expect(index[target.id].mastery > 0)
        #expect(index[target.id].effort > 0)
        for other in senses where other.id != target.id {
            #expect(index[other.id].mastery == 0, "a skip moved nothing")
            #expect(index[other.id].effort > 0, "but it was still exposure")
        }
        #expect(index[UUID()] == .unseen, "an unknown meaning reads as unseen")
    }
}
