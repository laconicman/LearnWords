//
//  WordAndStatTests.swift
//  Unit Testing Bundle
//
//  Pure-logic tests for the WordAndStat model.
//
//  Nested under `MaxKnownLevel`: several cases pin the global `maxKnownLevelPreference`,
//  and the serialized parent keeps them from racing the other suites that do the same.
//  See MaxKnownLevel.swift.
//

import Testing
import Foundation
@testable import LearnWords

extension MaxKnownLevel {

    @Suite(.serialized)
    struct WordAndStatTests {

        @Test func decreaseCorrectNeverGoesBelowZero() {
            var word = WordAndStat(firstWord: "a", secondWord: "b", correct: [:], incorrect: [:], skiped: 0)
            word.decreaseCorrect(exercize: "spelling")
            #expect(word.correct["spelling"] == 0)
        }

        @Test func increaseThenDecreaseMovesByOne() {
            MaxKnownLevel.pinned(5) {
                var word = WordAndStat(firstWord: "a", secondWord: "b", correct: [:], incorrect: [:], skiped: 0)
                word.increaseCorrect(exercize: "spelling")
                word.increaseCorrect(exercize: "spelling")
                #expect(word.correct["spelling"] == 2)
                word.decreaseCorrect(exercize: "spelling")
                #expect(word.correct["spelling"] == 1)
            }
        }

        @Test func increaseCorrectCapsAtMaxKnownLevel() {
            MaxKnownLevel.pinned(3) {
                var word = WordAndStat(firstWord: "a", secondWord: "b", correct: [:], incorrect: [:], skiped: 0)
                for _ in 0..<10 { word.increaseCorrect(exercize: "spelling") }
                #expect(word.correct["spelling"] == 3)
                #expect(word.known == 3)
            }
        }

        @Test func knownSumsCorrectAcrossExercises() {
            MaxKnownLevel.pinned(5) {
                var word = WordAndStat(firstWord: "a", secondWord: "b", correct: [:], incorrect: [:], skiped: 0)
                word.increaseCorrect(exercize: "spelling")
                word.increaseCorrect(exercize: "listening")
                #expect(word.known == 2)
            }
        }

        @Test func knownIsCappedEvenWhenSumExceedsMax() {
            MaxKnownLevel.pinned(2) {
                var word = WordAndStat(firstWord: "a", secondWord: "b", correct: [:], incorrect: [:], skiped: 0)
                // Two exercises each at the per-exercise cap of 2 would sum to 4, but `known` caps at 2.
                for _ in 0..<5 { word.increaseCorrect(exercize: "spelling") }
                for _ in 0..<5 { word.increaseCorrect(exercize: "listening") }
                #expect(word.known == 2)
            }
        }

        @Test func resetAnswerStatClearsProgress() {
            MaxKnownLevel.pinned(5) {
                var word = WordAndStat(firstWord: "a", secondWord: "b", correct: [:], incorrect: [:], skiped: 0)
                word.increaseCorrect(exercize: "spelling")
                word.resetAnswerStat()
                #expect(word.correct.isEmpty)
                #expect(word.incorrect.isEmpty)
                #expect(word.known == 0)
            }
        }

        @Test func codableRoundTripPreservesFields() throws {
            let word = WordAndStat(firstWord: "bear", secondWord: "медведь",
                                   correct: ["spelling": 3], incorrect: ["listening": 1], skiped: 2)
            let data = try JSONEncoder().encode(word)
            let decoded = try JSONDecoder().decode(WordAndStat.self, from: data)
            #expect(decoded.firstWord == "bear")
            #expect(decoded.secondWord == "медведь")
            #expect(decoded.correct == ["spelling": 3])
            #expect(decoded.incorrect == ["listening": 1])
            #expect(decoded.skiped == 2)
        }
    }
}
