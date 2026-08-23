//
//  SenseStatisticsTests.swift
//  Unit Testing Bundle
//
//  The per-term statistics screen (TD-50), and the wording underneath it.
//
//  The claims worth pinning are what the learner is *told*: that an exercise never tried
//  says so rather than reporting zeroes, that the three exercises are reported apart —
//  which is the owner's headline ask and the reason `StrandProgress` exists — and that the
//  receptive/productive split is shown, which is the thing no surveyed competitor does.
//
//  Driven through the table's own data source, and with the clock passed in: a screen whose
//  wording depends on `Date()` cannot be asserted about.
//

import Testing
import UIKit
@testable import LearnWords

@MainActor
struct SenseStatisticsTests {

    private let pair = LanguagePair(primary: "ru", secondary: "en", showsSecondaryAsPrompt: true)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func sense() -> Sense {
        Sense(id: UUID(), note: nil,
              terms: [Term(id: UUID(), text: "bear", language: "en",
                           transcription: nil, partOfSpeech: nil),
                      Term(id: UUID(), text: "медведь", language: "ru",
                           transcription: nil, partOfSpeech: nil)],
              tags: [])
    }

    private func strand(mastery: Float = 0.5,
                        retention: Float = 0.87,
                        stability: Double = 12,
                        successfulDays: Int = 2,
                        dueIn days: Double? = 3) -> StrandProgress {
        StrandProgress(mastery: mastery,
                       retention: retention,
                       memory: FSRSMemory(stability: stability, difficulty: 5),
                       lastReviewedAt: now,
                       dueAt: days.map { now.addingTimeInterval($0 * 86_400) },
                       // Due when there is no date, or when the date has passed. `days == nil`
                       // made a strand five days overdue report "not due" — an impossible
                       // state that would mislead the next test to read it. Reported by
                       // review, PR #3.
                       isDue: days.map { $0 <= 0 } ?? true,
                       successfulDays: successfulDays)
    }

    private func progress(_ strands: [Exercise: StrandProgress],
                          effort: Float = 0.6,
                          receptive: Int = 7,
                          productive: Int = 0) -> SenseProgress {
        SenseProgress(strands: strands, effort: effort,
                      answersByDirection: [.receptive: receptive, .productive: productive],
                      isDue: true)
    }

    private func screen(_ progress: SenseProgress) -> SenseStatisticsViewController {
        let vc = SenseStatisticsViewController(sense: sense(), progress: progress,
                                               languages: pair, now: now)
        vc.loadViewIfNeeded()
        return vc
    }

    private func rows(inSection section: Int, on vc: SenseStatisticsViewController) -> [String] {
        (0..<vc.tableView(vc.tableView, numberOfRowsInSection: section)).map { row in
            let cell = vc.tableView(vc.tableView, cellForRowAt: IndexPath(row: row, section: section))
            let detail = cell.detailTextLabel?.text
            return [cell.textLabel?.text, detail].compactMap { $0 }.joined(separator: " — ")
        }
    }

    private func headers(on vc: SenseStatisticsViewController) -> [String?] {
        (0..<vc.numberOfSections(in: vc.tableView)).map {
            vc.tableView(vc.tableView, titleForHeaderInSection: $0)
        }
    }

    // MARK: - Per exercise

    /// The owner's headline ask, and what TD-49's per-exercise memory made possible: the
    /// three exercises are reported apart, in a fixed order.
    @Test func everyExerciseGetsItsOwnSection() {
        let vc = screen(progress([.learning: strand()]))

        #expect(headers(on: vc).prefix(3) == ["Learning", "Dictation", "Phonetic"])
    }

    /// An exercise never opened says so. Reporting 0% mastery and "due now" for one the
    /// learner has never tried is three numbers about nothing, and it reads as failure
    /// rather than as absence.
    @Test func anExerciseNeverTriedSaysSoRatherThanReportingZeroes() {
        let vc = screen(progress([.learning: strand()]))

        #expect(rows(inSection: 1, on: vc) == ["Not practised yet"])
        #expect(rows(inSection: 2, on: vc) == ["Not practised yet"])
    }

    /// Memory in the unit the horizon slider already uses, and the rest of what one strand
    /// knows.
    @Test func anEngagedExerciseReportsMemoryInPlainWords() {
        let vc = screen(progress([.learning: strand(stability: 12, successfulDays: 4, dueIn: 3)]))

        let learning = rows(inSection: 0, on: vc)
        #expect(learning.count == 4)
        #expect(learning[0] == "Remembered for about 12 days")
        #expect(learning[1] == "Recall right now — 87%")
        #expect(learning[2] == "Due in about 3 days")
        #expect(learning[3] == "Practised on — 4 days")
    }

    /// The two-day gate is the half of the learned rule a single fast answer cannot
    /// satisfy, and it is only worth explaining where it actually applies.
    @Test func theTwoDayGateIsExplainedOnlyWhileItBinds() {
        let short = screen(progress([.learning: strand(successfulDays: 1)]))
        #expect(short.tableView(short.tableView, titleForFooterInSection: 0)
                == "Needs successes on two separate days to count as learned.")

        let spaced = screen(progress([.learning: strand(successfulDays: 2)]))
        #expect(spaced.tableView(spaced.tableView, titleForFooterInSection: 0) == nil)
    }

    @Test func aDueDateInThePastReadsAsDueNow() {
        let vc = screen(progress([.learning: strand(dueIn: -5)]))

        #expect(rows(inSection: 0, on: vc).contains("Due now"))
    }

    // MARK: - Overall

    /// The reason this screen exists: no surveyed competitor shows the split, and
    /// `ReviewDirection` has been recorded per event since TD-13 so that it could.
    @Test func theReceptiveProductiveSplitIsShown() {
        let vc = screen(progress([.learning: strand()], effort: 0.62,
                                 receptive: 7, productive: 3))

        let overall = rows(inSection: 3, on: vc)
        #expect(overall == ["Effort — 62%", "Recognised — 7 answers", "Produced — 3 answers"])
    }

    /// Recognition running ahead of production is the expected asymmetry, worth naming and
    /// not worth alarming about — so it is said once, and only while it is true.
    @Test func productionBeingUntouchedIsNamedButOnlyThen() {
        let lopsided = screen(progress([.learning: strand()], receptive: 7, productive: 0))
        #expect(lopsided.tableView(lopsided.tableView, titleForFooterInSection: 3)
                == "Only recognised so far — producing it is the harder half.")

        let balanced = screen(progress([.learning: strand()], receptive: 7, productive: 3))
        #expect(balanced.tableView(balanced.tableView, titleForFooterInSection: 3) == nil)

        // Nothing practised at all is not a lopsided learner, it is a new word.
        let untouched = screen(progress([:], receptive: 0, productive: 0))
        #expect(untouched.tableView(untouched.tableView, titleForFooterInSection: 3) == nil)
    }

    // MARK: - Looking the word up

    /// The context menu took the long press that used to look a word up, and at the iOS 12
    /// floor there is no menu to hang it on — so the screen carries it.
    @Test func theWordCanBeLookedUpFromHere() throws {
        let vc = SenseStatisticsViewController(sense: sense(), progress: progress([:]),
                                               languages: pair, now: now, offersLookUp: true)
        vc.loadViewIfNeeded()

        let last = vc.numberOfSections(in: vc.tableView) - 1
        #expect(rows(inSection: last, on: vc) == ["Look up bear"])
    }

    /// Off for a context-menu preview, which is not interactive: the row would be pure extra
    /// height, and height is the clipping problem on that path.
    @Test func aPreviewOffersNoLookupRow() {
        let vc = screen(progress([.learning: strand()]))

        #expect(vc.numberOfSections(in: vc.tableView) == 4, "three exercises and the overall section")
    }

    /// A meaning with no history gets three "Not practised yet" lines and nothing else —
    /// Effort 0% beside "none / none" is the same three numbers about nothing the
    /// per-exercise sections already refuse to show. Reported by review, PR #3.
    @Test func anUnpractisedMeaningGetsNoOverallSection() {
        let vc = screen(progress([:], effort: 0, receptive: 0, productive: 0))

        #expect(vc.numberOfSections(in: vc.tableView) == 3)
        #expect(headers(on: vc) == ["Learning", "Dictation", "Phonetic"])
    }

    /// A reset clears every strand's memory but **keeps** effort and the answer counts, as the
    /// record of work actually done. Keying the section on engagement hid exactly those totals
    /// on exactly the meanings whose history was just set aside. Reported by review, PR #3.
    @Test func aResetMeaningStillShowsTheWorkAlreadyDone() {
        let vc = screen(progress([:], effort: 0.62, receptive: 7, productive: 3))

        #expect(vc.numberOfSections(in: vc.tableView) == 4)
        #expect(rows(inSection: 3, on: vc) == ["Effort — 62%", "Recognised — 7 answers",
                                               "Produced — 3 answers"])
    }
}

// MARK: - Wording

struct MemoryWordingTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// Approximate on purpose: stability is a fitted parameter of a model of a person, and
    /// "12.4 days" claims a precision it does not have.
    ///
    /// **Days while the horizon slider is in days.** Left to itself the formatter says
    /// "2 weeks" for twelve, which overstates by 17% and cannot be compared with a
    /// preference denominated in days and floored at ten. Above a month the reverse holds
    /// and the unit grows.
    @Test func memoryIsSaidInOneUnitChosenByMagnitude() {
        #expect(MemoryWording.horizon(days: 12) == "Remembered for about 12 days")
        #expect(MemoryWording.horizon(days: 21) == "Remembered for about 21 days")
        #expect(MemoryWording.horizon(days: 45) == "Remembered for about 6 weeks")
        #expect(MemoryWording.horizon(days: 200) == "Remembered for about 6 months")
        #expect(MemoryWording.horizon(days: 400) == "Remembered for about 1 year")
    }

    /// Below a day it is not worth a unit at all — the learner is being told it is fragile,
    /// which "less than a day" says and "0 days" does not.
    @Test func aMemoryShorterThanADayIsNotRoundedToZero() {
        #expect(MemoryWording.horizon(days: 0.4) == "Remembered for less than a day")
        #expect(MemoryWording.horizon(days: 0) == "Remembered for less than a day")
    }

    /// Rounding a two-hour wait up to "about 1 day" overstated it for exactly the items
    /// closest to being forgotten. Reported by review, PR #3.
    @Test func aWaitShorterThanADayIsNotRoundedUpToOne() {
        #expect(MemoryWording.due(now.addingTimeInterval(2 * 3_600), now: now) == "Due later today")
        #expect(MemoryWording.due(now.addingTimeInterval(23 * 3_600), now: now) == "Due later today")
        #expect(MemoryWording.due(now.addingTimeInterval(25 * 3_600), now: now) == "Due in about 1 day")
    }

    @Test func aDueDateReadsAsAWaitOrAsNow() {
        #expect(MemoryWording.due(now.addingTimeInterval(3 * 86_400), now: now)
                == "Due in about 3 days")
        #expect(MemoryWording.due(now.addingTimeInterval(-86_400), now: now) == "Due now")
        #expect(MemoryWording.due(nil, now: now) == "Due now")
    }
}
