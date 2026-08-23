//
//  ScoringSeamsTests.swift
//  Unit Testing Bundle
//
//  The two seams the learning-design batch's screens share, exercised here so they do not
//  land as untested code waiting for a follow-up PR that might slip (reported by review,
//  PR #6).
//
//  Neither is interesting on its own — that is rather the point of a seam. What is worth
//  pinning is that `ProgressIndex(scored:)` hands back exactly what it was given, and that
//  every exercise has a name, since a `switch` gaining a case silently is how the third one
//  would come back empty.
//

import Testing
import Foundation
@testable import LearnWords

struct ScoringSeamsTests {

    @Test func anIndexBuiltFromValuesReportsThoseValues() {
        let id = UUID()
        let scored = SenseProgress(
            strands: [.dictation: StrandProgress(mastery: 0.75, retention: 0.9,
                                                 memory: FSRSMemory(stability: 30, difficulty: 5),
                                                 lastReviewedAt: nil, dueAt: nil, isDue: true,
                                                 successfulDays: 3)],
            effort: 0.4, answersByDirection: [.receptive: 2], isDue: true)

        let index = ProgressIndex(scored: [id: scored])

        #expect(index[id] == scored)
        #expect(index[id][.dictation].mastery == 0.75)
        #expect(index[id][.learning] == .untouched, "an unscored exercise is untouched")
    }

    /// A meaning the index was never told about is unseen, not absent — every caller
    /// subscripts it without checking.
    @Test func anUnknownMeaningIsUnseen() {
        #expect(ProgressIndex(scored: [:])[UUID()] == .unseen)
    }

    @Test func everyExerciseHasAName() {
        for exercise in Exercise.allCases {
            #expect(!exercise.title.isEmpty, "\(exercise) has no display name")
        }
        #expect(Set(Exercise.allCases.map(\.title)).count == Exercise.allCases.count,
                "two exercises share a name, so a section header cannot say which is which")
    }
}
