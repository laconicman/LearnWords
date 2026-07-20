//
//  ExerciseSessionTests.swift
//  Unit Testing Bundle
//
//  The round logic the three exercise screens used to each own a copy of (TD-20).
//  These run without a storyboard or a view controller — the point of the extraction.
//
//  Nested under `MaxKnownLevel`: the level-up cases pin the global
//  `maxKnownLevelPreference`, and the serialized parent keeps them from racing
//  `WordAndStatTests`, which pins the same value. See MaxKnownLevel.swift.
//

import Testing
import Foundation
@testable import LearnWords

extension MaxKnownLevel {

@Suite(.serialized)
struct ExerciseSessionTests {

    private func word(_ first: String, correct: [String: Int] = [:]) -> WordAndStat {
        WordAndStat(firstWord: first, secondWord: "\(first)-translated",
                    correct: correct, incorrect: [:], skiped: 0)
    }

    // MARK: - Queue

    @Test func startsWithEveryWordAndNothingFinished() {
        let session = ExerciseSession(exercise: .learning,
                                      words: [word("a"), word("b"), word("c")])
        #expect(session.remaining.count == 3)
        #expect(session.finished.isEmpty)
        #expect(session.isFinished == false)
        #expect(session.currentWord != nil)
    }

    @Test func answeringMovesTheWordFromRemainingToFinished() {
        var session = ExerciseSession(exercise: .learning, words: [word("a"), word("b")])
        let current = session.currentWord!

        let answer = session.answer(isKnown: true)

        #expect(answer?.word.firstWord == current.firstWord)
        #expect(session.remaining.count == 1)
        #expect(session.finished.count == 1)
        #expect(session.remaining.contains { $0.firstWord == current.firstWord } == false)
    }

    @Test func answeringPastTheEndReturnsNil() {
        var session = ExerciseSession(exercise: .learning, words: [word("a")])
        _ = session.answer(isKnown: true)
        #expect(session.isFinished)
        #expect(session.answer(isKnown: true) == nil)
    }

    @Test func skipRecordsASkipWithoutScoring() {
        var session = ExerciseSession(exercise: .dictation, words: [word("a")])

        session.skip()

        #expect(session.finished.count == 1)
        #expect(session.finished[0].skiped == 1)
        // Skipping must not count as an answer either way.
        #expect(session.finished[0].correct.isEmpty)
    }

    @Test func skippingPastTheEndIsHarmless() {
        var session = ExerciseSession(exercise: .learning, words: [])
        session.skip()
        #expect(session.finished.isEmpty)
    }

    // MARK: - Scoring

    @Test func correctAnswerScoresAgainstItsOwnExercise() {
        MaxKnownLevel.pinned(5) {
            var session = ExerciseSession(exercise: .phonetics, words: [word("a")])
            let answer = session.answer(isKnown: true)
            // Phonetics tallies under "P" and must not touch the other exercises.
            #expect(answer?.word.correct["P"] == 1)
            #expect(answer?.word.correct["L"] == nil)
            #expect(answer?.word.correct["D"] == nil)
        }
    }

    @Test func wrongAnswerDecreasesTheSameExercise() {
        MaxKnownLevel.pinned(5) {
            var session = ExerciseSession(exercise: .learning,
                                          words: [word("a", correct: ["L": 3])])
            let answer = session.answer(isKnown: false)
            #expect(answer?.word.correct["L"] == 2)
            #expect(answer?.isKnown == false)
        }
    }

    // MARK: - Level-up

    @Test func reachedKnownLevelIsTrueOnlyOnTheCrossingAnswer() {
        MaxKnownLevel.pinned(2) {
            var session = ExerciseSession(exercise: .learning,
                                          words: [word("a", correct: ["L": 1])])
            let crossing = session.answer(isKnown: true)
            #expect(crossing?.reachedKnownLevel == true)
        }
    }

    @Test func reachedKnownLevelIsFalseWhenAlreadyKnown() {
        MaxKnownLevel.pinned(2) {
            var session = ExerciseSession(exercise: .learning,
                                          words: [word("a", correct: ["L": 2])])
            let answer = session.answer(isKnown: true)
            #expect(answer?.word.known == 2)
            // Already at the level, so this must not re-trigger the celebration.
            #expect(answer?.reachedKnownLevel == false)
        }
    }

    @Test func reachedKnownLevelIsFalseWhenStillShort() {
        MaxKnownLevel.pinned(5) {
            var session = ExerciseSession(exercise: .learning, words: [word("a")])
            #expect(session.answer(isKnown: true)?.reachedKnownLevel == false)
        }
    }

    // MARK: - Progress

    @Test func progressRunsFromZeroToOne() {
        var session = ExerciseSession(exercise: .learning,
                                      words: [word("a"), word("b"), word("c"), word("d")])
        #expect(session.progress == 0)

        session.skip()
        #expect(session.progress == 0.25)

        session.skip()
        session.skip()
        session.skip()
        #expect(session.progress == 1)
        #expect(session.isFinished)
    }

    /// The old screens computed `1.0 / count` up front, so an empty set divided by zero.
    @Test func progressIsZeroForAnEmptySetRatherThanInfinite() {
        let session = ExerciseSession(exercise: .learning, words: [])
        #expect(session.progress == 0)
        #expect(session.isFinished)
    }

    // MARK: - Learned-word skip rule

    @Test func learnedWordIsSkippedUnlessIncluded() {
        MaxKnownLevel.pinned(2) {
            let session = ExerciseSession(exercise: .learning,
                                          words: [word("a", correct: ["L": 2])])
            #expect(session.skipsCurrentWord(includingLearned: false) == true)
            #expect(session.skipsCurrentWord(includingLearned: true) == false)
        }
    }

    @Test func unlearnedWordIsNeverSkipped() {
        MaxKnownLevel.pinned(5) {
            let session = ExerciseSession(exercise: .learning, words: [word("a")])
            #expect(session.skipsCurrentWord(includingLearned: false) == false)
        }
    }

    @Test func finishedSessionSkipsNothing() {
        let session = ExerciseSession(exercise: .learning, words: [])
        #expect(session.skipsCurrentWord(includingLearned: false) == false)
    }
}
}
