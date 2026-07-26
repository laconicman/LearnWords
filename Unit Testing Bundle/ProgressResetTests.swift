//
//  ProgressResetTests.swift
//  Unit Testing Bundle
//
//  "Reset progress" on one meaning.
//
//  The rule under test is that a reset **appends** rather than deletes — the pattern both
//  Anki's `revlog` (a `Manual` row with `ease_factor == 0`) and swift-fsrs (`Rating.manual`)
//  settled on, and the one that keeps the effort index honest: the answers already given
//  are work the learner actually did.
//

import Testing
import Foundation
@testable import LearnWords

@MainActor
@Suite(.serialized)
struct ProgressResetTests {

    private func makeLexicon() -> Lexicon {
        Lexicon(persistence: LWPersistence(inMemory: true))
    }

    private func stocked(_ lexicon: Lexicon) throws -> (set: WordSet, sense: Sense) {
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        let sense = try lexicon.addSense(to: set.id, terms: [Term.Draft("bear", in: "en"),
                                                             Term.Draft("медведь", in: "ru")])
        return (set, sense)
    }

    /// Answers `count` times correctly, each in its own sitting.
    private func practise(_ lexicon: Lexicon, _ set: WordSet, times count: Int) throws {
        for _ in 0..<count {
            let session = try PracticeSession.start(
                .dictation, in: set.id,
                languages: LanguagePair(primary: "ru", secondary: "en",
                                        showsSecondaryAsPrompt: true),
                lexicon: lexicon, includingLearned: true)
            _ = session.nextQuestion()
            try session.record(.correctVerbatim)
        }
    }

    @Test func aResetKeepsEveryAnswerAlreadyGiven() throws {
        let lexicon = makeLexicon()
        let (set, sense) = try stocked(lexicon)
        try practise(lexicon, set, times: 3)

        try lexicon.resetProgress(ofSense: sense.id, in: set.id)

        let history = try lexicon.history(ofSense: sense.id)
        #expect(history.count == 4, "three answers plus the marker — nothing was deleted")
        #expect(history.prefix(3).allSatisfy { $0.kind == .answer })
        #expect(history.last?.kind == .progressReset)
    }

    @Test func theMarkerCarriesNoAnswerFields() throws {
        let lexicon = makeLexicon()
        let (set, sense) = try stocked(lexicon)

        try lexicon.resetProgress(ofSense: sense.id, in: set.id)

        let marker = try #require(try lexicon.history(ofSense: sense.id).first)
        #expect(marker.outcome == nil, "nothing was answered, so nothing was graded")
        #expect(marker.task == nil)
        #expect(marker.direction == nil)
        #expect(marker.prompt.isEmpty)
        #expect(marker.expected.isEmpty)
        #expect(marker.response == nil)
    }

    @Test func aResetSendsTheMeaningBackToTheStartOfTheLevel() throws {
        let lexicon = makeLexicon()
        let (set, sense) = try stocked(lexicon)
        let prefs = LWUserDefaults.standard
        let saved = prefs.maxKnownLevelPreference
        defer { prefs.maxKnownLevelPreference = saved }
        prefs.maxKnownLevelPreference = 4

        try practise(lexicon, set, times: 4)
        let senses = try lexicon.senses(in: set.id)
        #expect(try InterimMastery(lexicon: lexicon, senses: senses).isLearned(sense.id),
                "precondition: it counts as learned")

        try lexicon.resetProgress(ofSense: sense.id, in: set.id)

        let after = try InterimMastery(lexicon: lexicon, senses: senses)
        #expect(!after.isLearned(sense.id))
        #expect(after.level(of: sense.id) == 0, "the ring goes back to empty")
    }

    /// Answers *after* the marker count again — the reset is a boundary, not a mute.
    @Test func answersAfterAResetCountNormally() throws {
        let lexicon = makeLexicon()
        let (set, sense) = try stocked(lexicon)
        let prefs = LWUserDefaults.standard
        let saved = prefs.maxKnownLevelPreference
        defer { prefs.maxKnownLevelPreference = saved }
        prefs.maxKnownLevelPreference = 2

        try practise(lexicon, set, times: 2)
        try lexicon.resetProgress(ofSense: sense.id, in: set.id)
        try practise(lexicon, set, times: 2)

        let senses = try lexicon.senses(in: set.id)
        #expect(try InterimMastery(lexicon: lexicon, senses: senses).isLearned(sense.id))
        #expect(try lexicon.history(ofSense: sense.id).count == 5)
    }

    @Test func resettingAMissingMeaningThrows() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        #expect(throws: (any Error).self) {
            try lexicon.resetProgress(ofSense: UUID(), in: set.id)
        }
    }
}
