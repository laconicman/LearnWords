//
//  LearnedThresholdTests.swift
//  Unit Testing Bundle
//
//  TD-49: what it takes for a meaning to count as learned.
//
//  Two guards and one partition, all of which used to be missing:
//    * a single fast answer must not be enough, whatever the horizon says;
//    * the *preference* has a floor, because a 1-day horizon plus one Easy answer
//      (initial stability 8.3 days) filled the ring outright;
//    * each exercise carries its own memory, so "learned" cannot be claimed by a
//      flashcard on behalf of dictation.
//

import Testing
import Foundation
@testable import LearnWords

struct LearnedThresholdTests {

    // MARK: - Building histories

    private let calendar = Calendar(identifier: .gregorian)
    private let origin = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: origin)!
    }

    /// One graded answer, each in its own sitting (so each is long-term evidence).
    private func answer(_ outcome: ReviewOutcome, _ exercise: Exercise, onDay offset: Int,
                        latencyMS: Int? = nil) -> ReviewEvent {
        ReviewEvent(id: UUID(), senseID: UUID(), date: day(offset), sessionID: UUID(),
                    kind: .answer, outcome: outcome, task: exercise,
                    direction: exercise.isProductive ? .productive : .receptive,
                    prompt: "bear", expected: "медведь", response: "медведь",
                    latencyMS: latencyMS, errorTags: [], schemaVersion: 1)
    }

    /// A generous horizon-1 policy, so only the gate under test can hold mastery back.
    private func policy(minimumSuccessfulDays: Int = ScoringPolicy.defaultMinimumSuccessfulDays)
    -> ScoringPolicy {
        ScoringPolicy(masteryHorizonDays: 1,
                      minimumSuccessfulDays: minimumSuccessfulDays,
                      calendar: calendar)
    }

    // MARK: - The single-answer defect

    @Test func oneAnswerIsNeverEnoughHoweverGenerousTheHorizon() {
        let progress = policy().progress(replaying: [answer(.correctVerbatim, .dictation, onDay: 0)],
                                         now: day(0))
        #expect(!progress.isLearned(requireProduction: false),
                "one sitting carries no spacing evidence — TD-49's whole point")
        #expect(progress[.dictation].mastery < 1)
        #expect(progress[.dictation].successfulDays == 1)
    }

    @Test func successesOnSeparateDaysClearTheGate() {
        let events = [answer(.correctVerbatim, .dictation, onDay: 0),
                      answer(.correctVerbatim, .dictation, onDay: 1)]
        let progress = policy().progress(replaying: events, now: day(1))
        #expect(progress[.dictation].successfulDays == 2)
        #expect(progress.isLearned(requireProduction: false))
    }

    @Test func repeatingTheSameDayDoesNotCountTwice() {
        // Three answers, one calendar day: effort, not spaced evidence.
        let events = [answer(.correctVerbatim, .dictation, onDay: 3),
                      answer(.correctVerbatim, .dictation, onDay: 3),
                      answer(.correctVerbatim, .dictation, onDay: 3)]
        let progress = policy().progress(replaying: events, now: day(3))
        #expect(progress[.dictation].successfulDays == 1)
        #expect(!progress.isLearned(requireProduction: false))
        #expect(progress.effort > 0, "the work still counts")
    }

    @Test func wrongAnswersDoNotCountTowardTheGate() {
        let events = [answer(.correctVerbatim, .dictation, onDay: 0),
                      answer(.incorrect, .dictation, onDay: 1)]
        let progress = policy().progress(replaying: events, now: day(1))
        #expect(progress[.dictation].successfulDays == 1, "only successes are spacing evidence")
    }

    // MARK: - The preference floor

    @Test func thePreferenceCannotAskForLessThanOneEasyAnswerProduces() {
        // w[3] = 8.2956 — a single Easy answer's stability. A horizon at or under it would
        // be filled by that one answer.
        #expect(ScoringPolicy.minimumHorizonDays > 8.2956)
    }

    @Test func anInjectedHorizonIsHonouredExactly() {
        // The floor guards the slider, not a caller who named a number: an initialiser that
        // ignores its argument is the worse bug.
        let generous = ScoringPolicy(masteryHorizonDays: 1, minimumSuccessfulDays: 1,
                                     calendar: calendar)
        let progress = generous.progress(replaying: [answer(.correctVerbatim, .dictation, onDay: 0)],
                                         now: day(0))
        #expect(progress.isLearned(requireProduction: false),
                "horizon 1 was asked for, so horizon 1 is what applies")
    }

    // MARK: - Strands

    @Test func exercisesCarryTheirOwnMemory() {
        let events = [answer(.correctVerbatim, .dictation, onDay: 0),
                      answer(.correctVerbatim, .dictation, onDay: 1)]
        let progress = policy().progress(replaying: events, now: day(1))

        #expect(progress[.dictation].isEngaged)
        #expect(!progress[.learning].isEngaged, "a flashcard was never asked")
        #expect(!progress[.phonetics].isEngaged)
        #expect(progress.engagedExercises == [.dictation])
    }

    @Test func anUntouchedExerciseDoesNotBlockLearned() {
        // Engagement, not "all three": a meaning drilled only as a flashcard is judged on
        // the strand it was actually practised in, so strands did not wipe anyone's progress.
        let events = [answer(.selfAssessedKnown, .learning, onDay: 0),
                      answer(.selfAssessedKnown, .learning, onDay: 1)]
        let progress = policy().progress(replaying: events, now: day(1))
        #expect(progress.isLearned(requireProduction: false))
    }

    @Test func failingANewExerciseUnlearnsTheMeaning() {
        // The hypercorrection moment: dictation proves you cannot produce what you could
        // recognise, and the app should stop calling it learned.
        var events = [answer(.selfAssessedKnown, .learning, onDay: 0),
                      answer(.selfAssessedKnown, .learning, onDay: 1)]
        #expect(policy().progress(replaying: events, now: day(1)).isLearned(requireProduction: false))

        events.append(answer(.incorrect, .dictation, onDay: 2))
        let after = policy().progress(replaying: events, now: day(2))
        #expect(!after.isLearned(requireProduction: false))
        #expect(after.mastery < 1, "the weakest engaged strand is what mastery reports")
    }

    @Test func requireProductionWithholdsLearnedFromRecognitionAlone() {
        let events = [answer(.selfAssessedKnown, .learning, onDay: 0),
                      answer(.selfAssessedKnown, .learning, onDay: 1)]
        let progress = policy().progress(replaying: events, now: day(1))
        #expect(progress.isLearned(requireProduction: false))
        #expect(!progress.isLearned(requireProduction: true),
                "recognising is not producing (Nation's split)")
    }

    @Test func dueIsAskedPerExercise() {
        let events = [answer(.correctVerbatim, .dictation, onDay: 0),
                      answer(.correctVerbatim, .dictation, onDay: 1)]
        let progress = policy().progress(replaying: events, now: day(1))
        #expect(!progress.isDue(.dictation), "just answered")
        #expect(progress.isDue(.phonetics), "never asked — waiting, not resting")
    }

    @Test func directionsAreTalliedForDisplay() {
        let events = [answer(.correctVerbatim, .dictation, onDay: 0),   // productive
                      answer(.selfAssessedKnown, .learning, onDay: 0)]  // receptive
        let progress = policy().progress(replaying: events, now: day(0))
        #expect(progress.answersByDirection[.productive] == 1)
        #expect(progress.answersByDirection[.receptive] == 1)
    }
}

// MARK: - The two readings of "learned"

extension LearnedThresholdTests {

    /// Raised by review (PR #1): the per-exercise overload ignores `requireProduction`,
    /// so practice filtering and the summary count can disagree. They are different
    /// questions, and this pins that rather than letting it drift.
    @Test func perExerciseLearnedIsAboutTheStrandNotTheProductionRule() {
        let events = [answer(.selfAssessedKnown, .learning, onDay: 0),
                      answer(.selfAssessedKnown, .learning, onDay: 1)]
        let progress = policy().progress(replaying: events, now: day(1))

        #expect(progress.isLearned(.learning), "the flashcard strand is learned, and stays so")
        #expect(!progress.isLearned(requireProduction: true),
                "the meaning is not, because nothing productive was proven")
        #expect(!progress.isLearned(.dictation), "an untouched strand is never learned")
    }
}
