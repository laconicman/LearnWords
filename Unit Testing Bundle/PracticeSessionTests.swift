//
//  PracticeSessionTests.swift
//  Unit Testing Bundle
//
//  The sitting: what gets asked, in which direction, and what reaches the review log.
//
//  These replace `ExerciseSessionTests`, which tested capped counters on `WordAndStat`.
//  The behaviour under test is different in kind now — answering *appends evidence*
//  rather than incrementing a number — so the old cases were retired with the type.
//
//  Store-injected and UIKit-free: the whole practice flow runs without a screen.
//

import Testing
import Foundation
@testable import LearnWords

// `.serialized` because a few cases pin the global preferences the practice flow reads
// (`maxKnownLevelPreference`, the language pair) — those are process-wide, so the cases
// that set them must not run alongside each other.
@MainActor
@Suite(.serialized)
struct PracticeSessionTests {

    /// Runs `body` with the "learned" bar pinned, then puts the user's setting back.
    /// The preference is real, process-wide state; a test must neither depend on what
    /// the machine happens to hold nor leave its own value behind.
    private func withKnownLevel(_ level: Int, _ body: () throws -> Void) rethrows {
        let prefs = LWUserDefaults.standard
        let saved = prefs.maxKnownLevelPreference
        defer { prefs.maxKnownLevelPreference = saved }
        prefs.maxKnownLevelPreference = level
        try body()
    }

    private func makeLexicon() -> Lexicon {
        Lexicon(persistence: LWPersistence(inMemory: true))
    }

    /// A set of `count` meanings, en↔ru, plus one with two Russian synonyms.
    @discardableResult
    private func stock(_ lexicon: Lexicon, count: Int = 3) throws -> WordSet {
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        let words = [("bear", ["медведь"]), ("camel", ["верблюд"]), ("fox", ["лиса", "лисица"])]
        for (en, ru) in words.prefix(count) {
            try lexicon.addSense(to: set.id,
                                 terms: [Term.Draft(en, in: "en")]
                                     + ru.map { Term.Draft($0, in: "ru") })
        }
        return set
    }

    private func pair(_ showsSecondaryAsPrompt: Bool = true) -> LanguagePair {
        LanguagePair(primary: "ru", secondary: "en",
                     showsSecondaryAsPrompt: showsSecondaryAsPrompt)
    }

    private func start(_ lexicon: Lexicon, _ set: WordSet,
                       _ exercise: Exercise = .dictation,
                       reversed: Bool = false,
                       includingLearned: Bool = true) throws -> PracticeSession {
        try PracticeSession.start(exercise, in: set.id,
                                  languages: pair(!reversed),
                                  lexicon: lexicon,
                                  includingLearned: includingLearned)
    }

    // MARK: - Asking

    @Test func aSittingAsksEveryMeaningOnce() throws {
        let lexicon = makeLexicon()
        let set = try stock(lexicon)
        let session = try start(lexicon, set)

        var asked: [UUID] = []
        while let question = session.nextQuestion() {
            asked.append(question.sense.id)
            try session.record(.correctVerbatim)
        }

        #expect(asked.count == 3)
        #expect(Set(asked).count == 3, "no meaning is asked twice")
        #expect(session.isFinished)
        #expect(session.progress == 1)
    }

    @Test func theQuestionIsCuedInThePromptLanguageAndAnsweredInTheOther() throws {
        let lexicon = makeLexicon()
        let set = try stock(lexicon, count: 1)
        let session = try start(lexicon, set)

        let question = try #require(session.nextQuestion())
        #expect(question.promptTerm.language == "en")
        #expect(question.prompt == "bear")
        #expect(question.answers.allSatisfy { $0.language == "ru" })
        #expect(question.expected == "медведь")
    }

    @Test func reversingTheDirectionSwapsPromptAndAnswer() throws {
        let lexicon = makeLexicon()
        let set = try stock(lexicon, count: 1)
        let session = try start(lexicon, set, reversed: true)

        let question = try #require(session.nextQuestion())
        #expect(question.promptTerm.language == "ru")
        #expect(question.answers.map(\.text) == ["bear"])
    }

    /// The redesign's payoff at the point of use: every synonym is an accepted answer.
    @Test func allSynonymsCountAsAnswers() throws {
        let lexicon = makeLexicon()
        let set = try stock(lexicon)
        let session = try start(lexicon, set)

        var foxAnswers: [String] = []
        while let question = session.nextQuestion() {
            if question.prompt == "fox" { foxAnswers = question.answers.map(\.text) }
            try session.record(.correctVerbatim)
        }
        #expect(Set(foxAnswers) == ["лиса", "лисица"])
    }

    @Test func anEmptySetFinishesImmediately() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Empty", languages: ["en", "ru"])
        let session = try start(lexicon, set)

        #expect(session.nextQuestion() == nil)
        #expect(session.isFinished)
        #expect(session.progress == 0, "no division by zero")
    }

    /// A half-entered word is not a question — it has nothing to answer with.
    @Test func meaningsMissingTheAnswerSideAreNotAsked() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        try lexicon.addSense(to: set.id, terms: [Term.Draft("bear", in: "en"),
                                                 Term.Draft("медведь", in: "ru")])
        try lexicon.addSense(to: set.id, terms: [Term.Draft("camel", in: "en")])

        let session = try start(lexicon, set)
        var prompts: [String] = []
        while let question = session.nextQuestion() {
            prompts.append(question.prompt)
            try session.record(.correctVerbatim)
        }
        #expect(prompts == ["bear"])
    }

    // MARK: - Recording

    @Test func answeringAppendsAnEventCarryingTheWholeContext() throws {
        let lexicon = makeLexicon()
        let set = try stock(lexicon, count: 1)
        let session = try start(lexicon, set, .dictation)

        let question = try #require(session.nextQuestion())
        try session.record(.correctJudged, response: "медветь")

        let history = try lexicon.history(ofSense: question.sense.id)
        let event = try #require(history.first)
        #expect(event.outcome == .correctJudged)
        #expect(event.task == .dictation)
        #expect(event.direction == .productive, "typing is production")
        #expect(event.prompt == "bear")
        #expect(event.expected == "медведь")
        #expect(event.response == "медветь")
        #expect(event.sessionID == session.id)
    }

    /// The whole sitting shares one `sessionID` — the unit that separates a same-session
    /// retry (effort) from fresh long-term evidence.
    @Test func everyAnswerInASittingSharesOneSessionID() throws {
        let lexicon = makeLexicon()
        let set = try stock(lexicon)
        let session = try start(lexicon, set)

        while session.nextQuestion() != nil {
            try session.record(.correctVerbatim)
        }

        #expect(try lexicon.history(ofSession: session.id).count == 3)
    }

    @Test func aFlashcardIsRecordedAsRecognitionAndCarriesNoResponse() throws {
        let lexicon = makeLexicon()
        let set = try stock(lexicon, count: 1)
        let session = try start(lexicon, set, .learning)

        let question = try #require(session.nextQuestion())
        try session.record(.selfAssessedKnown)

        let event = try #require(try lexicon.history(ofSense: question.sense.id).first)
        #expect(event.direction == .receptive, "grading a flashcard is recognition")
        #expect(event.response == nil, "there is nothing the learner typed")
    }

    @Test func skippingIsRecordedAsExposureNotEvidence() throws {
        let lexicon = makeLexicon()
        let set = try stock(lexicon, count: 1)
        let session = try start(lexicon, set)

        let question = try #require(session.nextQuestion())
        try session.skip()

        let event = try #require(try lexicon.history(ofSense: question.sense.id).first)
        #expect(event.outcome == .skipped)
        #expect(event.outcome?.isPositive == false)
        #expect(session.progress > 0, "a skip still advances the sitting")
    }

    @Test func latencyIsMeasuredFromWhenTheQuestionWasAsked() throws {
        let lexicon = makeLexicon()
        let set = try stock(lexicon, count: 1)
        let session = try start(lexicon, set)

        let question = try #require(session.nextQuestion())
        Thread.sleep(forTimeInterval: 0.05)
        try session.record(.correctVerbatim)

        let event = try #require(try lexicon.history(ofSense: question.sense.id).first)
        let latency = try #require(event.latencyMS)
        #expect(latency >= 40, "measured, not invented")
        #expect(latency < 5_000)
    }

    @Test func recordingWithNoQuestionInFlightDoesNothing() throws {
        let lexicon = makeLexicon()
        let set = try stock(lexicon, count: 1)
        let session = try start(lexicon, set)

        #expect(try session.record(.correctVerbatim) == nil, "nothing was asked yet")
        #expect(try lexicon.history(ofSession: session.id).isEmpty)
    }

    // MARK: - Negative evidence never erases positive

    /// ProgressModel R1, now structural rather than a scoring rule: a wrong answer
    /// *appends* to the log, so the earlier right answers are still there.
    @Test func aWrongAnswerAddsToHistoryRatherThanUndoingIt() throws {
        let lexicon = makeLexicon()
        let set = try stock(lexicon, count: 1)

        let first = try start(lexicon, set)
        let question = try #require(first.nextQuestion())
        try first.record(.correctVerbatim)

        let second = try start(lexicon, set)
        _ = second.nextQuestion()
        try second.record(.incorrect, response: "wrong")

        let history = try lexicon.history(ofSense: question.sense.id)
        #expect(history.count == 2)
        #expect(history.map(\.outcome) == [.correctVerbatim, .incorrect])
    }

    // MARK: - Learned filtering

    @Test func learnedMeaningsAreLeftOutUnlessAskedFor() throws {
        try withKnownLevel(3) {
            let lexicon = makeLexicon()
            let set = try stock(lexicon, count: 2)

            // Drive one meaning past the interim "learned" bar, leaving the other alone.
            let target = try #require(try lexicon.senses(in: set.id).first)
            for _ in 0..<3 {
                let session = try start(lexicon, set)
                while let question = session.nextQuestion() {
                    try session.record(question.sense.id == target.id ? .correctVerbatim : .skipped)
                }
            }

            #expect(try !asked(in: start(lexicon, set, includingLearned: false)).contains(target.id),
                    "a learned meaning is not asked again")
            #expect(try asked(in: start(lexicon, set, includingLearned: true)).contains(target.id),
                    "unless the learner asks for it")
        }
    }

    @Test func aMistakeSendsALearnedMeaningBackIntoRotation() throws {
        try withKnownLevel(3) {
            let lexicon = makeLexicon()
            let set = try stock(lexicon, count: 1)

            for _ in 0..<3 {
                let session = try start(lexicon, set)
                _ = session.nextQuestion()
                try session.record(.correctVerbatim)
            }
            let learned = try start(lexicon, set, includingLearned: false)
            #expect(learned.nextQuestion() == nil, "precondition: it counts as learned")

            let slip = try start(lexicon, set)
            _ = slip.nextQuestion()
            try slip.record(.incorrect, response: "no")

            let again = try start(lexicon, set, includingLearned: false)
            #expect(again.nextQuestion() != nil, "a mistake puts it back in the queue")
        }
    }

    /// Drains a sitting, reporting which meanings it put up.
    private func asked(in session: PracticeSession) throws -> Set<UUID> {
        var asked: Set<UUID> = []
        while let question = session.nextQuestion() {
            asked.insert(question.sense.id)
            try session.record(.skipped)
        }
        return asked
    }

    // MARK: - Language pair

    /// A set of German words is practised in German even when settings say otherwise —
    /// the data the user is looking at wins over a stale global preference.
    @Test func theLanguagePairFallsBackToWhatTheSetActuallyCovers() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Deutsch", languages: ["de", "ru"])
        try lexicon.addSense(to: set.id, terms: [Term.Draft("Bär", in: "de"),
                                                 Term.Draft("медведь", in: "ru")])

        // Compared by subtag: the side the set covers keeps the *preference's* tag
        // ("ru-RU"), because a voice has a region even though a word does not.
        let resolved = LanguagePair.forSet(set)
        #expect(Set([resolved.primary, resolved.secondary].map(LanguageCode.canonical))
                == ["de", "ru"])

        let session = try PracticeSession.start(.dictation, in: set.id, languages: resolved,
                                                lexicon: lexicon, includingLearned: true)
        #expect(session.nextQuestion() != nil, "the sitting has something to ask")
    }
}
