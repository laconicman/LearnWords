//
//  ProgressCostTests.swift
//  Unit Testing Bundle
//
//  What replaying the log actually costs (TD-52).
//
//  `ProgressModel` agreed to per-word cached index values "in principle, mechanism
//  negotiable" and deferred the mechanism. The register's discharge is deliberately
//  **measure first**: the word list already replays the log per row, TD-51's summary would
//  replay it for every meaning in a set on every appearance, and a cache that persists must
//  record `ScoringPolicy.version` — which is real complexity to take on without evidence.
//
//  So these are measurements, not assertions about design. Each one prints its numbers and
//  fails only against a **budget far above** what a correct implementation should need, so
//  the suite catches a regression of the kind that matters (an accidental N+1 fetch, a
//  quadratic replay) without becoming a flaky benchmark on a shared CI machine.
//
//  Sizes are chosen to bracket a real library rather than to be impressive: a learner with
//  a few hundred words and a year of practice, and one an order of magnitude past that.
//

import Testing
import Foundation
import CoreData
@testable import LearnWords

@Suite(.serialized)
@MainActor
struct ProgressCostTests {

    /// A library of `senses` meanings, each carrying `eventsPerSense` answers spread over
    /// the past year across all three exercises.
    ///
    /// Seeded in **one** transaction. `Lexicon.record` opens its own write per answer,
    /// which is right for the one-answer-at-a-time thing it is, and would spend the whole
    /// measurement in setup here.
    private func library(senses: Int, eventsPerSense: Int)
    throws -> (lexicon: Lexicon, senses: [Sense]) {
        let persistence = LWPersistence(inMemory: true)
        let lexicon = Lexicon(persistence: persistence)
        let set = try lexicon.addWordSet(named: "Bench", languages: ["en", "ru"])

        let drafts = (0..<senses).map { index in
            [Term.Draft("word\(index)", in: "en"), Term.Draft("слово\(index)", in: "ru")]
        }
        try lexicon.addSenses(to: set.id, terms: drafts)
        let stored = try lexicon.senses(in: set.id)

        let exercises = Exercise.allCases
        try persistence.write { context in
            let request = CDSynset.fetchRequest()
            let synsets = try context.fetch(request)
            for (index, synset) in synsets.enumerated() {
                for answer in 0..<eventsPerSense {
                    let event = CDReviewEvent(context: context)
                    event.synset = synset
                    event.date = Date(timeIntervalSinceNow:
                        -Double((eventsPerSense - answer) * 86_400 * 365 / max(eventsPerSense, 1)))
                    event.sessionID = UUID()
                    event.wordSetID = set.id
                    event.promptTermID = UUID()
                    event.kind = ReviewEventKind.answer.rawValue
                    event.task = exercises[(index + answer) % exercises.count].rawValue
                    event.direction = (answer % 2 == 0
                        ? ReviewDirection.receptive : .productive).rawValue
                    // A realistic log is mostly right with a scattering of wrong, and the
                    // wrong ones are the branch that costs — they reset stability.
                    event.outcome = (answer % 5 == 0
                        ? ReviewOutcome.incorrect : .correctVerbatim).rawValue
                    event.prompt = "word\(index)"
                    event.expected = "слово\(index)"
                    event.promptLanguage = "en"
                    event.answerLanguage = "ru"
                    event.latencyMS = NSNumber(value: 1_800)
                }
            }
        }
        return (lexicon, stored)
    }

    /// One measurement, and what it describes.
    ///
    /// `policyVersion` is not decoration: `ScoringPolicy.version` is the reason the constant
    /// exists, and a CSV from a run under different scoring rules is measuring something
    /// else. A stale number that cannot be told apart from a current one is worse than none.
    private struct Sample: Codable, Attachable {
        let label: String
        let meanings: Int
        let events: Int
        let milliseconds: Double
        let policyVersion: Int
    }

    /// Wall-clock for one run, **attached** to the result bundle.
    ///
    /// Not `print`, which Swift Testing does not forward to the `xcodebuild` log; and not a
    /// deliberate `#expect(false)`, which is the workaround ST-0009 was written to retire —
    /// it lies in CI, cannot be left in the suite, and has to be re-broken for every fresh
    /// reading. `Attachment.record` puts the number in the `.xcresult` without touching
    /// pass/fail, and `xcresulttool export attachments` takes it out again.
    @discardableResult
    private func measure(_ label: String, meanings: Int, events: Int,
                         _ work: () throws -> Void) rethrows -> TimeInterval {
        let started = Date()
        try work()
        let elapsed = Date().timeIntervalSince(started)
        Attachment.record(
            Sample(label: label, meanings: meanings, events: meanings * events,
                   milliseconds: (elapsed * 1000).rounded(),
                   policyVersion: ScoringPolicy.version),
            named: "td52-\(meanings)x\(events).json")
        return elapsed
    }

    /// The heavy sizes are a benchmark, not a regression guard, and seeding tens of
    /// thousands of Core Data rows costs more than the thing being measured. They run when
    /// asked for — `LW_BENCH=1` — so the ordinary suite stays quick.
    nonisolated static var runsBenchmarks: Bool {
        ProcessInfo.processInfo.environment["LW_BENCH"] != nil
    }

    // MARK: - The cost as it stands

    /// The shape TD-51's summary would pay on every appearance: one fetch, then a replay
    /// per meaning in the set.
    /// The one that runs on every change. Deliberately small: its job is to catch a
    /// per-row fetch sneaking back in, not to produce a number, and a benchmark left in the
    /// default suite is a benchmark that makes timing-sensitive neighbours flaky.
    @Test func aWholeSetScoresInOnePass() throws {
        let (lexicon, senses) = try library(senses: 300, eventsPerSense: 8)

        let elapsed = try measure("whole set, one pass", meanings: 300, events: 8) {
            let index = try ProgressIndex(lexicon: lexicon, senses: senses)
            #expect(index[senses[0].id].effort > 0, "precondition: the seed actually scored")
        }

        #expect(elapsed < 3, "300 meanings must not take seconds to score")
    }

    /// An order of magnitude past a realistic library, to show the shape of the curve
    /// rather than to pass a bar.
    @Test(.enabled(if: ProgressCostTests.runsBenchmarks))
    func theCostGrowsWithTheLibraryNotWithItsSquare() throws {
        let (smallLexicon, small) = try library(senses: 250, eventsPerSense: 12)
        let (largeLexicon, large) = try library(senses: 1_000, eventsPerSense: 12)

        let smallElapsed = try measure("scaling, small", meanings: 250, events: 12) {
            _ = try ProgressIndex(lexicon: smallLexicon, senses: small)
        }
        let largeElapsed = try measure("scaling, large", meanings: 1_000, events: 12) {
            _ = try ProgressIndex(lexicon: largeLexicon, senses: large)
        }

        // Four times the meanings must not cost sixteen times the work. Generous, because
        // this runs on whatever machine happens to be free; the failure it is here to catch
        // is a per-row fetch sneaking back in, which is far worse than this bound.
        #expect(largeElapsed < smallElapsed * 8 + 0.5,
                "scoring 4× the meanings took \(largeElapsed / max(smallElapsed, 0.0001))× the time")
    }

    /// A long history on few words — the other axis, and the one a committed learner grows
    /// along for years.
    @Test(.enabled(if: ProgressCostTests.runsBenchmarks))
    func aLongHistoryOnFewWordsStaysCheap() throws {
        let (lexicon, senses) = try library(senses: 100, eventsPerSense: 100)

        let elapsed = try measure("long history, few words", meanings: 100, events: 100) {
            _ = try ProgressIndex(lexicon: lexicon, senses: senses)
        }

        #expect(elapsed < 4)
    }

    /// **Which half is the cost.** `ProgressIndex` is one fetch and then a replay per
    /// meaning; a cache built on the wrong half saves nothing. Timed apart because Release
    /// turned out barely faster than Debug, which already suggested the arithmetic is not
    /// where the time goes.
    @Test(.enabled(if: ProgressCostTests.runsBenchmarks))
    func theFetchCostsMoreThanTheReplay() throws {
        let (lexicon, senses) = try library(senses: 1_000, eventsPerSense: 12)

        var histories: [UUID: [ReviewEvent]] = [:]
        let fetching = try measure("fetch only", meanings: 1_000, events: 12) {
            histories = try lexicon.history(ofSenses: senses.map(\.id))
        }
        let policy = ScoringPolicy.default
        let replaying = measure("replay only", meanings: 1_000, events: 12) {
            for sense in senses {
                _ = policy.progress(replaying: histories[sense.id] ?? [], now: Date())
            }
        }

        // A ratio a human should glance at, recorded as a warning rather than asserted:
        // which half dominates decides what a cache should avoid, and it is not a contract
        // worth failing CI over.
        Issue.record("fetch is \(String(format: "%.1f", fetching / max(replaying, 0.0001)))× the replay",
                     severity: .warning)
        #expect(fetching > 0 && replaying > 0)
    }

    /// What the word list pays per appearance today, at a size the owner might plausibly
    /// reach. This is the number that decides whether TD-52 needs a cache at all.
    @Test(.enabled(if: ProgressCostTests.runsBenchmarks))
    func aRealisticLibraryScoresFastEnoughToDrawAScreen() throws {
        let (lexicon, senses) = try library(senses: 2_000, eventsPerSense: 20)

        let elapsed = try measure("realistic library", meanings: 2_000, events: 20) {
            _ = try ProgressIndex(lexicon: lexicon, senses: senses)
        }

        #expect(elapsed < 10, "a library this size must still be scoreable in one pass")
    }
}
