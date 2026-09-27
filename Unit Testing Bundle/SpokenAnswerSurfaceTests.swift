//
//  SpokenAnswerSurfaceTests.swift
//  Unit Testing Bundle
//
//  The recogniser's best guess is not its only guess: a near-miss can be the right
//  answer when the engine confuses similar-sounding words, so matching considers the
//  ranked alternatives — on retries only; the first attempt wants the best reading —
//  and only a best-guess match can be verbatim.
//

import Testing
import UIKit
@testable import LearnWords

struct SpokenAnswerMatchingTests {

    private func heard(_ text: String, alternatives: [String] = [],
                       confidence: Float? = nil) -> DictationController.Heard {
        .init(text: text, isFinal: false, confidence: confidence, alternatives: alternatives)
    }

    @Test func theBestGuessWins() {
        let credited = SpokenAnswerSurface.matchedReading(
            in: heard("лисица", alternatives: ["лиса"]),
            answers: ["лиса", "лисица"], language: "ru", allowAlternatives: true)
        #expect(credited?.isBest == true)
        #expect(credited?.text == "лисица")
    }

    /// The case the owner reported: "fox" heard as "box" is a wrong answer when only the
    /// first transcription is read, and a right one when the second is.
    @Test func anAlternativeMatchesWhenTheBestMisses() {
        let credited = SpokenAnswerSurface.matchedReading(
            in: heard("box", alternatives: ["fox"]),
            answers: ["fox"], language: "en", allowAlternatives: true)
        #expect(credited?.text == "fox")
        #expect(credited?.isBest == false, "an alternative is judged, never verbatim")
    }

    @Test func nothingMatchingReturnsNil() {
        #expect(SpokenAnswerSurface.matchedReading(
            in: heard("wolf", alternatives: ["fox"]),
            answers: ["лиса"], language: "ru", allowAlternatives: true) == nil)
    }

    @Test func alternativesAreTriedInConfidenceOrder() {
        let credited = SpokenAnswerSurface.matchedReading(
            in: heard("grr", alternatives: ["bear", "hare"]),
            answers: ["hare", "bear"], language: "en", allowAlternatives: true)
        #expect(credited?.text == "bear", "the higher-ranked alternative is credited")
    }

    @Test func aBestGuessMissIsNotRescuedByItself() {
        // The best transcription appearing again among the alternatives changes nothing.
        #expect(SpokenAnswerSurface.matchedReading(
            in: heard("box", alternatives: ["box"]),
            answers: ["fox"], language: "en", allowAlternatives: true) == nil)
    }
    @Test func aFirstAttemptIgnoresTheAlternatives() {
        // The same utterance that retries would credit is a miss on the first attempt.
        #expect(SpokenAnswerSurface.matchedReading(
            in: heard("box", alternatives: ["fox"]),
            answers: ["fox"], language: "en", allowAlternatives: false) == nil)
        // …while the best guess itself is still matched.
        #expect(SpokenAnswerSurface.matchedReading(
            in: heard("fox", alternatives: ["box"]),
            answers: ["fox"], language: "en", allowAlternatives: false)?.isBest == true)
    }
}

/// The gate end to end: which `Heard`s count as attempts, and that a miss on the first
/// becomes a credit on the retry. A stub screen stands in for the view controller —
/// `consider` only reads `question`/`languages` and calls `answer`.
struct SpokenAnswerAttemptGateTests {

    private final class StubScreen: ExerciseScreen {
        var question: PracticeSession.Question?
        let languages = LanguagePair(primary: "en", secondary: "en",
                                     showsSecondaryAsPrompt: false)
        var answered: [(ReviewOutcome, String?)] = []
        func answer(_ outcome: ReviewOutcome, response: String?) {
            answered.append((outcome, response))
        }
        func presentAlert(_ alert: UIAlertController) {}
    }

    private func makeSurface() -> (SpokenAnswerSurface, StubScreen) {
        let fox = Term(id: UUID(), text: "fox", language: "en",
                       transcription: nil, partOfSpeech: nil)
        let sense = Sense(id: UUID(), note: nil, terms: [fox], tags: [])
        let screen = StubScreen()
        screen.question = PracticeSession.Question(sense: sense, promptTerm: fox,
                                                 answers: [fox])
        let surface = SpokenAnswerSurface()
        surface.attach(to: screen)
        surface.prepareForQuestion()
        return (surface, screen)
    }

    private func heard(_ text: String, alternatives: [String] = [],
                       isFinal: Bool = true) -> DictationController.Heard {
        .init(text: text, isFinal: isFinal, confidence: nil, alternatives: alternatives)
    }

    @MainActor @Test func aRetryCreditsAnAlternativeTheFirstAttemptRefused() {
        let (surface, screen) = makeSurface()
        surface.consider(heard("box", alternatives: ["fox"]), session: surface.questionGeneration)
        #expect(screen.answered.isEmpty, "the first attempt wants the best reading")
        surface.consider(heard("box", alternatives: ["fox"]), session: surface.questionGeneration)
        #expect(screen.answered.count == 1)
        #expect(screen.answered.first?.0 == .correctJudged)
        #expect(screen.answered.first?.1 == "box",
                "the log keeps the recogniser's best reading, not the credited alternative")
    }

    @MainActor @Test func aPartialDoesNotSpendTheStrictAttempt() {
        let (surface, screen) = makeSurface()
        // A partial mid-utterance is still part of the first attempt, not a new one.
        surface.consider(heard("box", alternatives: ["fox"], isFinal: false), session: surface.questionGeneration)
        surface.consider(heard("box", alternatives: ["fox"], isFinal: true), session: surface.questionGeneration)
        #expect(screen.answered.isEmpty, "the first *final* is still the first attempt")
        surface.consider(heard("box", alternatives: ["fox"], isFinal: true), session: surface.questionGeneration)
        #expect(screen.answered.count == 1)
    }

    @MainActor @Test func aNewQuestionStartsStrictAgain() {
        let (surface, screen) = makeSurface()
        surface.consider(heard("box", alternatives: ["fox"]), session: surface.questionGeneration)
        #expect(screen.answered.isEmpty)
        // The sitting moves on; the next question's first attempt is strict again.
        surface.prepareForQuestion()
        screen.answered.removeAll()
        surface.consider(heard("box", alternatives: ["fox"]), session: surface.questionGeneration)
        #expect(screen.answered.isEmpty)
    }

    @MainActor @Test func theBestGuessIsCreditedOnTheFirstAttempt() {
        let (surface, screen) = makeSurface()
        surface.consider(heard("fox"), session: surface.questionGeneration)
        #expect(screen.answered.count == 1)
    }

    /// Devin Review #37: the recognition callback stops the session on `isFinal`,
    /// so a missed final must hand the record button back — leaving `.listening`
    /// showed "Stop" over a dead recording and the retry took two taps.
    @MainActor @Test func aMissedFinalFreesTheRecordButton() {
        let (surface, screen) = makeSurface()
        surface.dictation = .listening
        surface.consider(heard("box", alternatives: ["fox"], isFinal: false),
                         session: surface.questionGeneration)
        #expect(surface.dictation == .listening, "a partial leaves the session open")
        surface.consider(heard("box", alternatives: ["fox"], isFinal: true),
                         session: surface.questionGeneration)
        #expect(screen.answered.isEmpty)
        #expect(surface.dictation == .idle,
                "the session is over; the button must read record, not stop")
    }

    /// Devin Review #37 + DeepWiki: a cancelled task can still deliver one late
    /// final. It belongs to the question that was open when its session started —
    /// it must not grade the new question nor spend its strict first attempt.
    @MainActor @Test func aStragglerFromAnOlderSessionIsIgnored() {
        let (surface, screen) = makeSurface()
        // A session opened at generation N-1 reporting into generation N.
        surface.consider(heard("fox"), session: surface.questionGeneration - 1)
        #expect(screen.answered.isEmpty, "a stale result cannot answer the question")
        surface.consider(heard("box", alternatives: ["fox"]),
                         session: surface.questionGeneration - 1)
        surface.consider(heard("box", alternatives: ["fox"]),
                         session: surface.questionGeneration)
        #expect(screen.answered.isEmpty,
                "the straggler must not spend the strict attempt either")
    }
}

