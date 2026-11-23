//
//  ExerciseRevealTests.swift
//  Unit Testing Bundle
//
//  TD-36: below the revealed answer the screen shows the meaning's remaining
//  synonyms in a secondary/footnote style, and — behind a Settings switch — the
//  revealed answer's transcription. Both follow the noteLabel rule: absent means
//  the view is not there at all, never an empty row holding a gap.
//

import Testing
import UIKit
@testable import LearnWords

@Suite(.serialized)
@MainActor
struct ExerciseRevealTests {

    /// Pins the speech preferences off for the test's duration: the reveal speaks
    /// the answer when `pronounceAnswersPreference` is on, and real TTS is the
    /// SpeechSuite's problem, not this one's.
    private func silenceSpeech() -> () -> Void {
        let prefs = LWUserDefaults.standard
        let answers = prefs.pronounceAnswersPreference
        let questions = prefs.pronounceQuestionsPreference
        prefs.pronounceAnswersPreference = false
        prefs.pronounceQuestionsPreference = false
        return {
            prefs.pronounceAnswersPreference = answers
            prefs.pronounceQuestionsPreference = questions
        }
    }

    /// A screen over a one-meaning set — plus any `extraSenses` — brought up through a
    /// real appearance cycle to the first question. The language prefs are pinned so
    /// the answer side is the study language — "en" for the en/ru fixtures — making
    /// `expected` the alphabetically first English term regardless of what the suite
    /// last ran with.
    private func screen(_ exercise: Exercise = .dictation,
                        terms: [Term.Draft],
                        extraSenses: [[Term.Draft]] = []) async throws -> (ExerciseViewController, UIWindow) {
        let prefs = LWUserDefaults.standard
        let direction = prefs.foreignToNative
        let native = prefs.nativeLanguagePreference
        let study = prefs.languageToStudyPreference
        prefs.foreignToNative = false
        prefs.nativeLanguagePreference = "ru"
        prefs.languageToStudyPreference = "en"
        defer {
            prefs.foreignToNative = direction
            prefs.nativeLanguagePreference = native
            prefs.languageToStudyPreference = study
        }

        let lexicon = Lexicon(persistence: LWPersistence(inMemory: true))
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        try lexicon.addSense(to: set.id, terms: terms)
        for sense in extraSenses {
            try lexicon.addSense(to: set.id, terms: sense)
        }

        let vc = try ExerciseViewController.make(exercise, in: set, lexicon: lexicon)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UINavigationController(rootViewController: vc)
        window.isHidden = false
        window.layoutIfNeeded()
        try await waitUntil { vc.session.current != nil }
        return (vc, window)
    }

    /// The register's point: the learner is graded correct for any synonym and was
    /// shown only one — the rest now appear under the answer, on every exercise.
    @Test(arguments: [Exercise.learning, .dictation, .phonetics])
    func theOtherCorrectAnswersShowUnderTheReveal(_ exercise: Exercise) async throws {
        let restore = silenceSpeech()
        defer { restore() }

        let (vc, window) = try await screen(exercise, terms: [
            Term.Draft("fox", in: "en"),
            Term.Draft("tod", in: "en"),
            Term.Draft("vixen", in: "en"),
            Term.Draft("лиса", in: "ru"),
        ])
        defer { window.isHidden = true }

        vc.forgotButton.sendActions(for: .touchUpInside)

        #expect(vc.synonymsLabel.isHidden == false)
        #expect(vc.synonymsLabel.text == "tod, vixen",
                "every correct answer but the revealed one — answer-language words only")
    }

    /// One correct answer means there is nothing to footnote: the label stays
    /// absent rather than holding an empty gap (the noteLabel rule).
    @Test func aSingleAnswerLeavesNoSynonymFootnote() async throws {
        let restore = silenceSpeech()
        defer { restore() }

        let (vc, window) = try await screen(.dictation, terms: [
            Term.Draft("bear", in: "en"),
            Term.Draft("медведь", in: "ru"),
        ])
        defer { window.isHidden = true }

        vc.forgotButton.sendActions(for: .touchUpInside)

        #expect(vc.synonymsLabel.isHidden)
        #expect(vc.synonymsLabel.text == nil)
    }

    /// The transcription is opt-in: it stays absent until the Settings switch
    /// says otherwise, even when the revealed term carries one. The screen's
    /// `showsTranscription` seam is pinned rather than the shared preference
    /// (REVIEW.md).
    @Test func theTranscriptionWaitsForItsSwitch() async throws {
        let restore = silenceSpeech()
        defer { restore() }

        let (vc, window) = try await screen(.dictation, terms: [
            Term.Draft("bear", in: "en", transcription: "bɛə"),
            Term.Draft("медведь", in: "ru", transcription: "MEE-dvee-d"),
        ])
        defer { window.isHidden = true }
        vc.showsTranscription = { false }

        vc.forgotButton.sendActions(for: .touchUpInside)

        #expect(vc.transcriptionLabel.isHidden)
        #expect(vc.transcriptionLabel.text == nil)
    }

    /// With the switch on, the footnote carries the *answer's* transcription —
    /// "bɛə" for English "bear", not the prompt side's "MEE-dvee-d".
    @Test func theTranscriptionShowsWhenTheSwitchIsOn() async throws {
        let restore = silenceSpeech()
        defer { restore() }

        let (vc, window) = try await screen(.dictation, terms: [
            Term.Draft("bear", in: "en", transcription: "bɛə"),
            Term.Draft("медведь", in: "ru", transcription: "MEE-dvee-d"),
        ])
        defer { window.isHidden = true }
        vc.showsTranscription = { true }

        vc.forgotButton.sendActions(for: .touchUpInside)

        #expect(vc.transcriptionLabel.isHidden == false)
        #expect(vc.transcriptionLabel.text == "bɛə")
    }

    /// Nothing to show means nothing on screen: no note, a single answer and no
    /// transcription leaves every footnote absent — before and after the reveal.
    @Test func anEmptyRevealLeavesEveryFootnoteAbsent() async throws {
        let restore = silenceSpeech()
        defer { restore() }

        let (vc, window) = try await screen(.dictation, terms: [
            Term.Draft("bear", in: "en"),
            Term.Draft("медведь", in: "ru"),
        ])
        defer { window.isHidden = true }

        #expect(vc.noteLabel.isHidden)
        #expect(vc.noteLabel.text == nil)
        #expect(vc.synonymsLabel.isHidden)
        #expect(vc.transcriptionLabel.isHidden)

        vc.forgotButton.sendActions(for: .touchUpInside)

        #expect(vc.noteLabel.isHidden)
        #expect(vc.synonymsLabel.isHidden)
        #expect(vc.transcriptionLabel.isHidden)
    }

    /// The reveal's data contract on `Question` itself: the shown answer is the
    /// first, the footnote candidates are the rest, and the transcription is the
    /// shown term's — the prompt side contributes neither.
    @Test func questionExposesTheRevealedAnswerAndItsCompany() throws {
        let lexicon = Lexicon(persistence: LWPersistence(inMemory: true))
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        try lexicon.addSense(to: set.id, terms: [
            Term.Draft("fox", in: "en", transcription: "fɒks"),
            Term.Draft("tod", in: "en"),
            Term.Draft("vixen", in: "en"),
            Term.Draft("лиса", in: "ru", transcription: "LEE-suh"),
        ])
        let session = try PracticeSession.start(
            .dictation, in: set.id,
            languages: LanguagePair(primary: "ru", secondary: "en",
                                     showsSecondaryAsPrompt: false),
            lexicon: lexicon,
            scope: .everything(includingLearned: true))

        let question = try #require(session.nextQuestion())
        #expect(question.expected == "fox")
        #expect(question.otherAnswers.map(\.text) == ["tod", "vixen"])
        #expect(question.expectedTranscription == "fɒks")
    }

    /// The footnotes belong to the answer that was just revealed: when the sitting
    /// moves on, the next question must not inherit them. Both senses carry a
    /// synonym so whichever the shuffle deals first populates the footnote.
    @Test func footnotesClearWhenTheNextQuestionArrives() async throws {
        let restore = silenceSpeech()
        defer { restore() }

        let (vc, window) = try await screen(.dictation,
            terms: [Term.Draft("fox", in: "en"), Term.Draft("tod", in: "en"),
                    Term.Draft("лиса", in: "ru")],
            extraSenses: [[Term.Draft("bear", in: "en"), Term.Draft("bruin", in: "en"),
                           Term.Draft("медведь", in: "ru")]])
        defer { window.isHidden = true }

        let firstSense = try #require(vc.session.current?.sense.id)
        vc.knowButton.sendActions(for: .touchUpInside)

        #expect(vc.synonymsLabel.isHidden == false,
                "precondition: the reveal populated the footnote")
        try await waitUntil { vc.synonymsLabel.isHidden }
        #expect(vc.session.current?.sense.id != firstSense,
                "precondition: the sitting advanced to the second question")
        #expect(vc.synonymsLabel.text == nil)
        #expect(vc.transcriptionLabel.isHidden)
    }
}
