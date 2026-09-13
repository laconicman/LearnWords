//
//  SetSummaryScreenTests.swift
//  Unit Testing Bundle
//
//  The set summary as a *screen* — until TD-58 it had no tests at all, which is how it came
//  to be the one preview that never set a preferred size and silently lost two of its four
//  sections behind the edge of a context menu.
//

import Testing
import Foundation
import UIKit
@testable import LearnWords

@MainActor
struct SetSummaryScreenTests {

    private func summary(total: Int = 4, dueNow: Bool = true) -> SetSummary {
        let senses = (0..<total).map { index in
            Sense(id: UUID(), note: nil,
                  terms: [Term(id: UUID(), text: "w\(index)", language: "en",
                               transcription: nil, partOfSpeech: nil)],
                  tags: [])
        }
        let strand = StrandProgress(mastery: 0.5, retention: 0.8,
                                    memory: FSRSMemory(stability: 5, difficulty: 5),
                                    lastReviewedAt: Date(), dueAt: Date(),
                                    isDue: dueNow, successfulDays: 2)
        let scored = Dictionary(uniqueKeysWithValues: senses.map { sense in
            (sense.id, SenseProgress(strands: [.learning: strand], effort: 0.4,
                                     answersByDirection: [.receptive: 3], isDue: dueNow))
        })
        return SetSummary(senses: senses, progress: ProgressIndex(scored: scored),
                          histories: [:], now: Date())
    }

    private func screen(_ presentation: SetSummaryViewController.Presentation)
    -> SetSummaryViewController {
        let vc = SetSummaryViewController(summary: summary(), setName: "Animals",
                                          presentation: presentation)
        vc.loadViewIfNeeded()
        vc.view.frame = CGRect(x: 0, y: 0, width: 320, height: 1_000)
        vc.view.layoutIfNeeded()
        return vc
    }

    /// The full screen keeps every section; the glance keeps the one that reads as a picture.
    @Test func thePreviewShowsTheDistributionAndNothingElse() {
        let full = screen(.full)
        let preview = screen(.preview)

        #expect(full.numberOfSections(in: full.tableView) == 4,
                "exercises, forecast, retention, effort")
        #expect(preview.numberOfSections(in: preview.tableView) == 1)
        #expect(preview.tableView(preview.tableView, numberOfRowsInSection: 0)
                == Exercise.allCases.count)
    }

    /// Dropping the forecast would drop the only number anyone acts on, so it moves.
    @Test func theDueNowCountSurvivesTheForecastBeingDropped() {
        let preview = screen(.preview)
        let footer = preview.tableView(preview.tableView, titleForFooterInSection: 0)

        #expect(footer?.isEmpty == false)
        #expect(footer?.contains("4") == true, "four meanings are due")
    }

    /// This screen never set a preferred size, so its preview took a default height and cut
    /// off *Answers so far* and *Effort* entirely.
    @Test func thePreviewAsksForASizeAndStaysUnderTheCap() {
        let preview = screen(.preview)
        let cap = SenseStatisticsViewController.previewHeightCap(for: preview.view)

        #expect(preview.preferredContentSize.height > 0)
        #expect(preview.preferredContentSize.height <= cap)
    }
}
