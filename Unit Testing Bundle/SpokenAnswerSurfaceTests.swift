//
//  SpokenAnswerSurfaceTests.swift
//  Unit Testing Bundle
//
//  The recogniser's best guess is not its only guess: a near-miss can be the right
//  answer when the engine confuses similar-sounding words, so matching considers the
//  ranked alternatives — and only a best-guess match can be verbatim.
//

import Testing
@testable import LearnWords

struct SpokenAnswerMatchingTests {

    private func heard(_ text: String, alternatives: [String] = [],
                       confidence: Float? = nil) -> DictationController.Heard {
        .init(text: text, isFinal: false, confidence: confidence, alternatives: alternatives)
    }

    @Test func theBestGuessWins() {
        let credited = SpokenAnswerSurface.matchedReading(
            in: heard("лисица", alternatives: ["лиса"]),
            answers: ["лиса", "лисица"], language: "ru")
        #expect(credited?.isBest == true)
        #expect(credited?.text == "лисица")
    }

    /// The case the owner reported: "fox" heard as "box" is a wrong answer when only the
    /// first transcription is read, and a right one when the second is.
    @Test func anAlternativeMatchesWhenTheBestMisses() {
        let credited = SpokenAnswerSurface.matchedReading(
            in: heard("box", alternatives: ["fox"]),
            answers: ["fox"], language: "en")
        #expect(credited?.text == "fox")
        #expect(credited?.isBest == false, "an alternative is judged, never verbatim")
    }

    @Test func nothingMatchingReturnsNil() {
        #expect(SpokenAnswerSurface.matchedReading(
            in: heard("wolf", alternatives: ["fox"]),
            answers: ["лиса"], language: "ru") == nil)
    }

    @Test func alternativesAreTriedInConfidenceOrder() {
        let credited = SpokenAnswerSurface.matchedReading(
            in: heard("grr", alternatives: ["bear", "hare"]),
            answers: ["hare", "bear"], language: "en")
        #expect(credited?.text == "bear", "the higher-ranked alternative is credited")
    }

    @Test func aBestGuessMissIsNotRescuedByItself() {
        // The best transcription appearing again among the alternatives changes nothing.
        #expect(SpokenAnswerSurface.matchedReading(
            in: heard("box", alternatives: ["box"]),
            answers: ["fox"], language: "en") == nil)
    }
}
