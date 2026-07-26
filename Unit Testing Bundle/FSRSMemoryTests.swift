//
//  FSRSMemoryTests.swift
//  Unit Testing Bundle
//
//  Parity for the FSRS-6 port.
//
//  These are not my expectations of what the formulas should produce — they are
//  **oracles taken from the reference library's own test suite**
//  (open-spaced-repetition/swift-fsrs, `Tests/FSRSTests/FSRSV6Tests.swift`). A port that
//  reproduces someone else's published numbers is verified; one that agrees with the
//  porter's reading of the paper is not.
//
//  The reference's own tolerance is used: 1e-7 for single-step values, 1e-4 for the
//  multi-review sequences where its intermediate rounding compounds.
//

import Testing
import Foundation
@testable import LearnWords

struct FSRSMemoryTests {

    private let fsrs = FSRSAlgorithm()

    private func expectClose(_ actual: Double, _ expected: Double, _ tolerance: Double,
                             _ note: Comment? = nil,
                             sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(abs(actual - expected) <= tolerance,
                note ?? "\(actual) is not within \(tolerance) of \(expected)",
                sourceLocation: sourceLocation)
    }

    // MARK: - First review (oracle: FSRSV6Tests.firstReview)

    @Test func initialStabilityIsTheWeightForTheGrade() {
        let stabilities = [FSRSGrade.again, .hard, .good, .easy]
            .map { fsrs.initialMemory($0).stability }
        #expect(stabilities == [0.212, 1.2931, 2.3065, 8.2956])
    }

    @Test(arguments: [(FSRSGrade.again, 6.4133), (.hard, 5.11217071),
                      (.good, 2.11810397), (.easy, 1.0)])
    func initialDifficultyMatchesTheReference(grade: FSRSGrade, expected: Double) {
        expectClose(fsrs.initialMemory(grade).difficulty, expected, 1e-7)
    }

    /// The Easy case is clamped: its raw value is below 1.
    @Test func initialDifficultyIsClampedToTheLegalRange() {
        for grade in [FSRSGrade.again, .hard, .good, .easy] {
            let d = fsrs.initialMemory(grade).difficulty
            #expect(d >= 1 && d <= 10)
        }
    }

    // MARK: - A whole sequence (oracle: FSRSV6Tests.memoryState*)

    /// Again, then five Goods, at 0, 0, 1, 3, 8 and 21 days — the reference's own fixture.
    private func replayReferenceSequence(shortTerm: Bool) -> FSRSMemory {
        let algorithm = FSRSAlgorithm(parameters: FSRSParameters(
            w: FSRSParameters.fsrs6.w,
            requestRetention: 0.9,
            maximumInterval: 36_500,
            enableShortTerm: shortTerm))

        let grades: [FSRSGrade] = [.again, .good, .good, .good, .good, .good]
        let gaps: [Double] = [0, 0, 1, 3, 8, 21]

        var memory: FSRSMemory?
        for (grade, gap) in zip(grades, gaps) {
            memory = algorithm.next(memory, elapsedDays: gap, grade: grade)
        }
        return memory!
    }

    @Test func aSequenceOfReviewsReproducesTheReferenceState() {
        let memory = replayReferenceSequence(shortTerm: true)
        expectClose(memory.stability, 53.62691, 1e-4)
        expectClose(memory.difficulty, 6.3574867, 1e-4)
    }

    @Test func theSameSequenceWithoutShortTermMatchesToo() {
        let memory = replayReferenceSequence(shortTerm: false)
        expectClose(memory.stability, 53.335106, 1e-4)
        expectClose(memory.difficulty, 6.3574867, 1e-4)
    }

    // MARK: - Forgetting curve (oracle: FSRSV6Tests.forgettingCurve)

    /// Stability *is* the interval at which recall has decayed to 90% — that is its
    /// definition, and it is the one number a reader has to trust.
    @Test func recallIs90PercentAfterExactlyOneStability() {
        expectClose(fsrs.retrievability(elapsedDays: 1, stability: 1), 0.9, 1e-4)
        expectClose(fsrs.retrievability(elapsedDays: 10, stability: 10), 0.9, 1e-4)
    }

    @Test func recallDecaysWithTimeAndRisesWithStability() {
        let early = fsrs.retrievability(elapsedDays: 1, stability: 10)
        let late = fsrs.retrievability(elapsedDays: 30, stability: 10)
        #expect(early > late, "recall decays as time passes")
        #expect(fsrs.retrievability(elapsedDays: 30, stability: 100) > late,
                "at the same age, a more stable meaning is better recalled")
        #expect(fsrs.retrievability(elapsedDays: 0, stability: 10) == 1)
    }

    /// The curve is a function of `t / S` alone. That scale invariance is what makes
    /// "stability is the interval at which recall is 90%" a definition rather than a
    /// coincidence — and it is why a bigger stability cannot be read as better recall
    /// unless the elapsed time is held fixed.
    @Test func recallDependsOnlyOnTheRatioOfTimeToStability() {
        expectClose(fsrs.retrievability(elapsedDays: 10, stability: 100),
                    fsrs.retrievability(elapsedDays: 1, stability: 10), 1e-8)
    }

    @Test func anUnreviewedMeaningHasNoRetention() {
        #expect(fsrs.retrievability(elapsedDays: 1, stability: 0) == 0)
    }

    // MARK: - Behaviour a reader should be able to assume

    @Test func successGrowsStabilityAndFailureCutsIt() {
        let learned = FSRSMemory(stability: 10, difficulty: 5)
        let after = fsrs.next(learned, elapsedDays: 10, grade: .good)
        let lapsed = fsrs.next(learned, elapsedDays: 10, grade: .again)
        #expect(after.stability > learned.stability)
        #expect(lapsed.stability < learned.stability)
    }

    @Test func easyGrowsStabilityMoreThanGoodAndGoodMoreThanHard() {
        let learned = FSRSMemory(stability: 10, difficulty: 5)
        let hard = fsrs.next(learned, elapsedDays: 10, grade: .hard).stability
        let good = fsrs.next(learned, elapsedDays: 10, grade: .good).stability
        let easy = fsrs.next(learned, elapsedDays: 10, grade: .easy).stability
        #expect(hard < good)
        #expect(good < easy)
    }

    @Test func failingRaisesDifficultyAndSucceedingLowersIt() {
        let learned = FSRSMemory(stability: 10, difficulty: 5)
        #expect(fsrs.next(learned, elapsedDays: 10, grade: .again).difficulty > 5)
        #expect(fsrs.next(learned, elapsedDays: 10, grade: .easy).difficulty < 5)
    }

    @Test func difficultyNeverLeavesItsRange() {
        var memory = FSRSMemory(stability: 1, difficulty: 5)
        for _ in 0..<50 { memory = fsrs.next(memory, elapsedDays: 1, grade: .again) }
        #expect(memory.difficulty <= 10)
        for _ in 0..<50 { memory = fsrs.next(memory, elapsedDays: 1, grade: .easy) }
        #expect(memory.difficulty >= 1)
    }

    /// A lapse must not send stability below the floor, however deep the fall.
    @Test func stabilityStaysPositiveAfterRepeatedFailure() {
        var memory = FSRSMemory(stability: 100, difficulty: 5)
        for _ in 0..<20 { memory = fsrs.next(memory, elapsedDays: 365, grade: .again) }
        #expect(memory.stability >= FSRSParameters.minimumStability)
    }

    /// Same-day review takes the short-term path, which is a different formula — the
    /// distinction the calendar-day rule exists to preserve.
    @Test func aSameDayReviewIsScoredDifferentlyFromANextDayOne() {
        let learned = FSRSMemory(stability: 10, difficulty: 5)
        let sameDay = fsrs.next(learned, elapsedDays: 0, grade: .good).stability
        let nextDay = fsrs.next(learned, elapsedDays: 1, grade: .good).stability
        #expect(sameDay != nextDay)
    }

    // MARK: - Intervals

    @Test func theIntervalIsAboutOneStabilityAtNinetyPercentRetention() {
        // With requestRetention == 0.9 the modifier is 1, so the interval is round(S).
        expectClose(fsrs.interval(stability: 21), 21, 0.5)
        #expect(fsrs.interval(stability: 0.01) == 1, "never schedules zero days out")
        #expect(fsrs.interval(stability: 1e9) == 36_500, "capped at the maximum")
    }

    @Test func wantingBetterRetentionShortensTheInterval() {
        let strict = FSRSAlgorithm(parameters: FSRSParameters(
            w: FSRSParameters.fsrs6.w, requestRetention: 0.97,
            maximumInterval: 36_500, enableShortTerm: true))
        #expect(strict.interval(stability: 100) < fsrs.interval(stability: 100))
    }

    // MARK: - Elapsed days

    @Test func elapsedDaysCountsCalendarBoundariesNotDurations() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func date(_ day: Int, _ hour: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 7, day: day, hour: hour))!
        }

        // 23:00 → 01:00 is two hours, but it is one day: the long-term path must apply.
        #expect(FSRSAlgorithm.elapsedDays(from: date(1, 23), to: date(2, 1),
                                          calendar: calendar) == 1)
        // 09:00 → 21:00 is twelve hours and zero days: the short-term path.
        #expect(FSRSAlgorithm.elapsedDays(from: date(1, 9), to: date(1, 21),
                                          calendar: calendar) == 0)
        #expect(FSRSAlgorithm.elapsedDays(from: date(1, 12), to: date(9, 12),
                                          calendar: calendar) == 8)
    }

    @Test func aClockGoingBackwardsIsNotNegativeTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let later = calendar.date(from: DateComponents(year: 2026, month: 7, day: 9))!
        let earlier = calendar.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        #expect(FSRSAlgorithm.elapsedDays(from: later, to: earlier, calendar: calendar) == 0)
    }
}
