//
//  SenseEntryScreenTests.swift
//  Unit Testing Bundle
//
//  The confirm screen for TD-53: the proposed split laid out one section per meaning, the
//  empty row that follows each language's words, and the merge control that turns two
//  meanings back into synonyms of one.
//
//  Driven through the table's own data source rather than by reading private state — the
//  claim is what the learner is shown and what tapping does, and a snapshot the table never
//  consulted would prove neither. The screen is store-free, so it needs no persistence.
//

import Testing
import UIKit
@testable import LearnWords

@MainActor
struct SenseEntryScreenTests {

    private let pair = LanguagePair(primary: "ru", secondary: "en", showsSecondaryAsPrompt: true)

    /// `bank` with two Russian meanings — the case the owner's rule is right about.
    private var polysemous: [SenseEntry] {
        SenseEntry.proposals(.init("bank", in: "en"), .init("берег, банк", in: "ru"))
    }

    private func screen(_ proposals: [SenseEntry],
                        onCommit: @escaping ([SenseEntry]) -> Void = { _ in }) -> SenseEntryViewController {
        let vc = SenseEntryViewController(proposals: proposals, languages: pair, onCommit: onCommit)
        vc.loadViewIfNeeded()
        return vc
    }

    private func labels(ofSection section: Int, on vc: SenseEntryViewController) -> [String] {
        (0..<vc.tableView(vc.tableView, numberOfRowsInSection: section)).map {
            vc.tableView(vc.tableView, cellForRowAt: IndexPath(row: $0, section: section))
                .textLabel?.text ?? ""
        }
    }

    private func tapRow(_ row: Int, inSection section: Int, on vc: SenseEntryViewController) {
        vc.tableView(vc.tableView, didSelectRowAt: IndexPath(row: row, section: section))
    }

    private func save(_ vc: SenseEntryViewController) throws {
        let item = try #require(vc.navigationItem.rightBarButtonItem)
        #expect(item.isEnabled, "precondition: the proposal is storable")
        _ = item.target?.perform(item.action, with: item)
    }

    // MARK: - Layout

    /// A section per meaning, plus the empty one that adds another — which is what makes
    /// the comma optional rather than the only way to say "two meanings".
    @Test func eachMeaningGetsItsOwnSection() {
        let vc = screen(polysemous)

        #expect(vc.numberOfSections(in: vc.tableView) == 3)
        #expect(vc.tableView(vc.tableView, titleForHeaderInSection: 0) == "Meaning 1")
        #expect(vc.tableView(vc.tableView, titleForHeaderInSection: 1) == "Meaning 2")
        #expect(vc.tableView(vc.tableView, titleForHeaderInSection: 2) == nil,
                "the trailing section adds a meaning; it is not one")
    }

    /// The owner's ask, as geometry: every filled row is followed by an empty one, per
    /// language, so another synonym never needs a comma.
    @Test func everyLanguageGroupEndsInAnEmptyRow() {
        let vc = screen(polysemous)

        #expect(labels(ofSection: 0, on: vc) ==
                ["bank", "Add a word in English", "берег", "Add a word in Russian"])
    }

    /// Nothing above the first meaning to fold into, so it is not offered there.
    @Test func onlyLaterMeaningsOfferTheMerge() {
        let vc = screen(polysemous)

        #expect(!labels(ofSection: 0, on: vc).contains("Merge into the meaning above"))
        #expect(labels(ofSection: 1, on: vc).last == "Merge into the meaning above")
    }

    @Test func theLastSectionSaysWhatSaveWillDo() {
        let vc = screen(polysemous)

        #expect(vc.tableView(vc.tableView, titleForFooterInSection: 2) == "2 meanings will be created")
    }

    // MARK: - Merging

    /// The case the split gets wrong — `лиса, лисица` is one meaning — and the single tap
    /// that fixes it, in front of the learner rather than months later in practice.
    @Test func tappingMergeFoldsTheMeaningIntoTheOneAbove() throws {
        var committed: [SenseEntry] = []
        let proposed = SenseEntry.proposals(.init("fox", in: "en"), .init("лиса, лисица", in: "ru"))
        let vc = screen(proposed) { committed = $0 }
        #expect(vc.numberOfSections(in: vc.tableView) == 3, "precondition: the default splits")

        let merge = try #require(labels(ofSection: 1, on: vc).firstIndex(of: "Merge into the meaning above"))
        tapRow(merge, inSection: 1, on: vc)

        #expect(vc.numberOfSections(in: vc.tableView) == 2, "one meaning, plus the empty section")
        #expect(labels(ofSection: 0, on: vc) ==
                ["fox", "Add a word in English", "лиса", "лисица", "Add a word in Russian"],
                "the two meanings became synonyms of one, and the shared word arrived once")

        try save(vc)
        #expect(committed.count == 1)
        #expect(committed[0].words(in: "ru") == ["лиса", "лисица"])
        #expect(committed[0].words(in: "en") == ["fox"])
    }

    // MARK: - Deleting

    /// A meaning with nothing left in it is one being taken back, not one being edited.
    @Test func removingAMeaningsLastWordRemovesTheMeaning() {
        let vc = screen(polysemous)

        // Meaning 2 is `bank` / `банк`: delete both of its words.
        vc.tableView(vc.tableView, commit: .delete, forRowAt: IndexPath(row: 0, section: 1))
        #expect(vc.numberOfSections(in: vc.tableView) == 3, "still two meanings; one is now short")
        vc.tableView(vc.tableView, commit: .delete, forRowAt: IndexPath(row: 1, section: 1))

        #expect(vc.numberOfSections(in: vc.tableView) == 2)
        #expect(labels(ofSection: 0, on: vc).contains("берег"), "the meaning kept is the first")
    }

    /// Only words are swipeable — not the empty rows, and not the merge control.
    @Test func onlyWordsCanBeSwipedAway() {
        let vc = screen(polysemous)

        #expect(vc.tableView(vc.tableView, canEditRowAt: IndexPath(row: 0, section: 0)))
        #expect(!vc.tableView(vc.tableView, canEditRowAt: IndexPath(row: 1, section: 0)),
                "the empty row adds a synonym; there is nothing there to delete")
        #expect(!vc.tableView(vc.tableView, canEditRowAt: IndexPath(row: 0, section: 2)))
    }

    // MARK: - Saving

    /// A meaning needs a word on both practised languages or it can be asked in neither
    /// direction, so Save does not promise to store one that cannot be.
    @Test func saveIsOffWhileAMeaningIsIncomplete() {
        let vc = screen([SenseEntry(terms: [Term.Draft("bank", in: "en")])])

        #expect(vc.navigationItem.rightBarButtonItem?.isEnabled == false)
        #expect(vc.tableView(vc.tableView, titleForFooterInSection: 0) == "Needs a word in Russian.",
                "and it says which side is missing")
    }

    @Test func saveHandsBackEveryConfirmedMeaning() throws {
        var committed: [SenseEntry] = []
        let vc = screen(polysemous) { committed = $0 }

        try save(vc)

        #expect(committed.count == 2)
        #expect(committed.map { $0.words(in: "ru") } == [["берег"], ["банк"]])
        #expect(committed.allSatisfy { $0.words(in: "en") == ["bank"] })
    }
}
