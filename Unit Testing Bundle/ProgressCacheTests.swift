//
//  ProgressCacheTests.swift
//  Unit Testing Bundle
//
//  The cache TD-52's measurements justified — tested for **correctness**, not for speed.
//
//  A cache that is merely fast is a cache that lies. Every claim here is about the moment
//  it must forget: an answer appended, a progress reset, another device changing the store,
//  or the day turning under a retention figure that decays with the clock. `ProgressCostTests`
//  covers the other half — that there was a cost worth paying this complexity for.
//

import Testing
import Foundation
import CoreData
@testable import LearnWords

@Suite(.serialized)
@MainActor
struct ProgressCacheTests {

    private func stocked() throws -> (lexicon: Lexicon, set: WordSet, senses: [Sense]) {
        let lexicon = Lexicon(persistence: LWPersistence(inMemory: true))
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        try lexicon.addSenses(to: set.id, terms: [
            [Term.Draft("bear", in: "en"), Term.Draft("медведь", in: "ru")],
            [Term.Draft("fox", in: "en"), Term.Draft("лиса", in: "ru")],
        ])
        return (lexicon, set, try lexicon.senses(in: set.id))
    }

    private func answer(_ sense: Sense, in set: WordSet, correct: Bool = true) -> ReviewEvent.Draft {
        ReviewEvent.Draft(senseID: sense.id,
                          sessionID: UUID(),
                          wordSetID: set.id,
                          promptTermID: sense.terms[0].id,
                          task: .learning,
                          direction: .receptive,
                          outcome: correct ? .correctVerbatim : .incorrect,
                          prompt: "bear",
                          expected: "медведь",
                          promptLanguage: "en",
                          answerLanguage: "ru")
    }

    // MARK: - What it remembers

    @Test func theSameQuestionTwiceGivesTheSameAnswer() throws {
        let (lexicon, set, senses) = try stocked()
        let cache = ProgressCache()
        try lexicon.record(answer(senses[0], in: set))

        let first = try cache.index(for: senses, in: lexicon)
        let second = try cache.index(for: senses, in: lexicon)

        #expect(first[senses[0].id] == second[senses[0].id])
        #expect(first[senses[0].id].effort > 0, "precondition: the answer was scored")
    }

    /// A meaning asked about for the first time is scored even when its neighbours are
    /// already known — the misses are what a warm screen still has to pay for.
    @Test func aNewMeaningIsScoredWithoutRescoringTheRest() throws {
        let (lexicon, set, senses) = try stocked()
        let cache = ProgressCache()
        try lexicon.record(answer(senses[0], in: set))

        _ = try cache.index(for: [senses[0]], in: lexicon)
        let both = try cache.index(for: senses, in: lexicon)

        #expect(both[senses[0].id].effort > 0)
        #expect(both[senses[1].id] == .unseen, "the second meaning has no history yet")
    }

    // MARK: - What it forgets

    /// The claim that matters: an answer must change the number the learner is shown.
    @Test func answeringDropsThatMeaningsScore() throws {
        let (lexicon, set, senses) = try stocked()
        let cache = ProgressCache()

        let before = try cache.index(for: senses, in: lexicon)
        #expect(before[senses[0].id].effort == 0, "precondition: nothing practised yet")

        try lexicon.record(answer(senses[0], in: set))
        let after = try cache.index(for: senses, in: lexicon)

        #expect(after[senses[0].id].effort > 0, "a stale ring tells the learner something untrue")
    }

    /// One answer invalidates one meaning. The rest of the screen stays warm, which is the
    /// whole reason the notification carries a sense id.
    @Test func answeringLeavesTheOtherMeaningsAlone() throws {
        let (lexicon, set, senses) = try stocked()
        let cache = ProgressCache()
        try lexicon.record(answer(senses[1], in: set))
        let before = try cache.index(for: senses, in: lexicon)

        try lexicon.record(answer(senses[0], in: set))
        let after = try cache.index(for: senses, in: lexicon)

        #expect(after[senses[1].id] == before[senses[1].id], "the untouched meaning is unchanged")
        #expect(after[senses[0].id] != before[senses[0].id], "the answered one is not")
    }

    @Test func resettingProgressDropsThatMeaningsScore() throws {
        let (lexicon, set, senses) = try stocked()
        let cache = ProgressCache()
        try lexicon.record(answer(senses[0], in: set))
        let practised = try cache.index(for: senses, in: lexicon)
        #expect(practised[senses[0].id].effort > 0, "precondition")

        try lexicon.resetProgress(ofSense: senses[0].id, in: set.id)
        let reset = try cache.index(for: senses, in: lexicon)

        #expect(reset[senses[0].id].mastery == 0, "a reset the learner asked for must be visible")
    }

    /// Another device's changes arrive without any local append, so the only safe answer is
    /// to forget everything.
    ///
    /// **The event is inserted behind `record`'s back**, straight through `persistence.write`.
    /// Going through `Lexicon.record` posts `didAppendToLog`, which drops that meaning on its
    /// own — so the assertion passed whether or not the remote observer existed, and the test
    /// proved nothing. Reported by review, PR #4.
    @Test func aRemoteChangeDropsTheWholeCache() throws {
        let persistence = LWPersistence(inMemory: true)
        let lexicon = Lexicon(persistence: persistence)
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        try lexicon.addSenses(to: set.id, terms: [
            [Term.Draft("bear", in: "en"), Term.Draft("медведь", in: "ru")],
        ])
        let senses = try lexicon.senses(in: set.id)
        let cache = ProgressCache()

        let before = try cache.index(for: senses, in: lexicon)
        #expect(before[senses[0].id].effort == 0, "precondition: nothing practised yet")

        try persistence.write { context in
            let event = CDReviewEvent(context: context)
            event.synset = try context.fetch(CDSynset.fetchRequest()).first
            event.kind = ReviewEventKind.answer.rawValue
            event.sessionID = UUID()
            event.wordSetID = set.id
            event.promptTermID = UUID()
            event.task = Exercise.learning.rawValue
            event.direction = ReviewDirection.receptive.rawValue
            event.outcome = ReviewOutcome.correctVerbatim.rawValue
            event.prompt = "bear"
            event.expected = "медведь"
            event.promptLanguage = "en"
            event.answerLanguage = "ru"
        }
        // Still stale: nothing told the cache, which is the situation a remote change is.
        #expect(try cache.index(for: senses, in: lexicon)[senses[0].id].effort == 0,
                "precondition: an unannounced write is invisible to the cache")

        NotificationCenter.default.post(name: LWPersistence.storeDidChangeRemotely, object: nil)

        #expect(try cache.index(for: senses, in: lexicon)[senses[0].id].effort > 0)
    }

    /// The regression the review caught: `ScoringPolicy` reads the horizon slider on every
    /// use so that moving it takes effect at once, and caching the results put it back to
    /// doing nothing.
    @Test func changingTheHorizonPreferenceDropsTheCache() throws {
        let (lexicon, set, senses) = try stocked()
        let cache = ProgressCache()
        try lexicon.record(answer(senses[0], in: set))

        let prefs = LWUserDefaults.standard
        let horizon = prefs.maxKnownLevelPreference
        defer { prefs.maxKnownLevelPreference = horizon }

        prefs.maxKnownLevelPreference = 400
        let atLongHorizon = try cache.index(for: senses, in: lexicon)[senses[0].id].mastery

        prefs.maxKnownLevelPreference = 10
        let atShortHorizon = try cache.index(for: senses, in: lexicon)[senses[0].id].mastery

        #expect(atShortHorizon > atLongHorizon,
                "the same memory is a bigger share of a shorter horizon — the slider must bite")
    }

    /// A write to an unrelated preference is not a reason to re-score the library — the
    /// notification fires for every default in the process. Reported by review, PR #4.
    @Test func anUnrelatedPreferenceDoesNotColdTheCache() throws {
        let (lexicon, set, senses) = try stocked()
        let cache = ProgressCache()
        try lexicon.record(answer(senses[0], in: set))
        let warm = try cache.index(for: senses, in: lexicon)

        let prefs = LWUserDefaults.standard
        let rate = prefs.utteranceRatePreference
        defer { prefs.utteranceRatePreference = rate }
        prefs.utteranceRatePreference = rate + 0.1

        // Same values, and the same *instances* — a re-scored index would rebuild them.
        #expect(try cache.index(for: senses, in: lexicon)[senses[0].id] == warm[senses[0].id])
    }

    /// Retention decays with the clock, so yesterday's answers are yesterday's.
    @Test func theCacheDoesNotSurviveTheDayTurning() throws {
        let (lexicon, set, senses) = try stocked()
        let cache = ProgressCache()
        try lexicon.record(answer(senses[0], in: set))

        let today = try cache.index(for: senses, in: lexicon, now: Date())
        let tomorrow = try cache.index(for: senses, in: lexicon,
                                       now: Date().addingTimeInterval(36 * 3_600))

        #expect(tomorrow[senses[0].id].retention < today[senses[0].id].retention,
                "a day later the learner is likelier to have forgotten it")
    }
}
