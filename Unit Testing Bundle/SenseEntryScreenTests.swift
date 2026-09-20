//
//  SenseEntryScreenTests.swift
//  Unit Testing Bundle
//
//  The confirm screen for TD-53: the proposal laid out one section per meaning, the empty
//  row that follows each language's words, and the two controls that reshape it — "These
//  are separate meanings" to split synonyms apart, and merge to fold them back.
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

    /// `bank` with two Russian words, separated — the case the *default* is wrong about, so
    /// the screen is exercised in the shape a learner reaches by tapping "These are separate
    /// meanings".
    private var polysemous: [SenseEntry] {
        SenseEntry.splitting(
            SenseEntry.proposals(.init("bank", in: "en"), .init("берег, банк", in: "ru")), at: 0)
    }

    /// What the comma actually proposes now: one meaning, two synonyms.
    private var synonymous: [SenseEntry] {
        SenseEntry.proposals(.init("fox", in: "en"), .init("лиса, лисица", in: "ru"))
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

    // MARK: - Splitting

    /// What a comma now proposes, and the one tap that undoes it for `берег, банк`.
    @Test func synonymsArriveAsOneMeaningWithASplitControl() throws {
        var committed: [SenseEntry] = []
        let vc = screen(synonymous) { committed = $0 }

        #expect(vc.numberOfSections(in: vc.tableView) == 2, "one meaning, plus the empty section")
        #expect(labels(ofSection: 0, on: vc) ==
                ["fox", "Add a word in English", "лиса", "лисица", "Add a word in Russian",
                 "These are separate meanings"])
        #expect(vc.tableView(vc.tableView, titleForFooterInSection: 1) == "1 meaning will be created")

        let split = try #require(labels(ofSection: 0, on: vc).firstIndex(of: "These are separate meanings"))
        tapRow(split, inSection: 0, on: vc)

        #expect(vc.numberOfSections(in: vc.tableView) == 3)
        #expect(labels(ofSection: 0, on: vc) == ["fox", "Add a word in English", "лиса", "Add a word in Russian"])
        #expect(labels(ofSection: 1, on: vc) ==
                ["fox", "Add a word in English", "лисица", "Add a word in Russian",
                 "Merge into the meaning above"])

        try save(vc)
        #expect(committed.count == 2)
        #expect(committed.map { $0.words(in: "ru") } == [["лиса"], ["лисица"]])
    }

    /// Offered only where it would do something — a meaning said once has nothing to split.
    @Test func aMeaningSaidOnceOffersNoSplit() {
        let vc = screen(polysemous)

        #expect(!labels(ofSection: 0, on: vc).contains("These are separate meanings"))
    }

    // MARK: - Merging

    /// Merge is the undo for a split the learner asked for, in front of them rather than
    /// months later in practice.
    @Test func tappingMergeFoldsTheMeaningIntoTheOneAbove() throws {
        var committed: [SenseEntry] = []
        let separated = SenseEntry.splitting(synonymous, at: 0)
        let vc = screen(separated) { committed = $0 }
        #expect(vc.numberOfSections(in: vc.tableView) == 3, "precondition: two meanings")

        let merge = try #require(labels(ofSection: 1, on: vc).firstIndex(of: "Merge into the meaning above"))
        tapRow(merge, inSection: 1, on: vc)

        #expect(vc.numberOfSections(in: vc.tableView) == 2, "one meaning, plus the empty section")
        #expect(labels(ofSection: 0, on: vc) ==
                ["fox", "Add a word in English", "лиса", "лисица", "Add a word in Russian",
                 "These are separate meanings"],
                "the two became synonyms of one, and the result offers to separate them again")

        // The footer has to survive the merge it exists for: a single format string ends
        // this screen saying "1 meanings will be created".
        #expect(vc.tableView(vc.tableView, titleForFooterInSection: 1) == "1 meaning will be created")

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

    /// Two rows of one meaning can say the same word — nothing stops adding one twice — and
    /// deleting the second must not take the first.
    @Test func deletingActsOnTheRowTappedEvenWhenTwoRowsAgree() throws {
        var committed: [SenseEntry] = []
        let twins = SenseEntry(terms: [Term.Draft("bank", in: "en"),
                                       Term.Draft("банк", in: "ru"),
                                       Term.Draft("банк", in: "ru")])
        let vc = screen([twins]) { committed = $0 }
        #expect(labels(ofSection: 0, on: vc) ==
                ["bank", "Add a word in English", "банк", "банк", "Add a word in Russian",
                 "These are separate meanings"],
                "precondition: both rows are shown")

        // The second "банк" — row 3 of the section.
        vc.tableView(vc.tableView, commit: .delete, forRowAt: IndexPath(row: 3, section: 0))

        try save(vc)
        #expect(committed.count == 1)
        #expect(committed[0].words(in: "ru") == ["банк"], "one of the two, not both and not neither")
    }

    /// Only words are swipeable — not the empty rows, and not the merge control.
    @Test func onlyWordsCanBeSwipedAway() {
        let vc = screen(polysemous)

        #expect(vc.tableView(vc.tableView, canEditRowAt: IndexPath(row: 0, section: 0)))
        #expect(!vc.tableView(vc.tableView, canEditRowAt: IndexPath(row: 1, section: 0)),
                "the empty row adds a synonym; there is nothing there to delete")
        #expect(!vc.tableView(vc.tableView, canEditRowAt: IndexPath(row: 0, section: 2)))
    }

    /// `commit` hands the proposal back whole, so anything the rows do not cover would be
    /// stored having never been shown. A third language gets rows like any other; only
    /// *completeness* is judged on the practised pair.
    @Test func aLanguageOutsideThePractisedPairIsStillShown() {
        let trilingual = SenseEntry(terms: [Term.Draft("bank", in: "en"),
                                            Term.Draft("берег", in: "ru"),
                                            Term.Draft("Ufer", in: "de")])
        let vc = screen([trilingual])

        #expect(labels(ofSection: 0, on: vc) ==
                ["bank", "Add a word in English", "берег", "Add a word in Russian",
                 "Ufer", "Add a word in German"])
        #expect(vc.navigationItem.rightBarButtonItem?.isEnabled == true,
                "the practised pair is filled, so the meaning is storable")
    }

    // MARK: - The word being defined

    /// Every accessibility label in a view tree, which is how the pinned slab announces itself:
    /// its inner stack is one element labelled "caption: term".
    private func accessibilityLabels(in view: UIView) -> [String] {
        (view.accessibilityLabel.map { [$0] } ?? [])
            + view.subviews.flatMap { accessibilityLabels(in: $0) }
    }

    private func pushedInput(afterTapping row: Int, inSection section: Int,
                             of proposals: [SenseEntry]) throws -> WordInputViewController {
        let vc = screen(proposals)
        let navigation = UINavigationController(rootViewController: vc)
        tapRow(row, inSection: section, on: vc)
        let input = try #require(navigation.topViewController as? WordInputViewController,
                                 "the row has to push the word input screen")
        input.view.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        input.view.layoutIfNeeded()
        return input
    }

    /// Editing a word must pin the word being defined — the meaning's word in the other
    /// practised language — with its dictionary ⓘ beside it.
    ///
    /// It did not: this screen pushed `WordInputViewController` without a context, so every
    /// second screen reached through "Confirm meanings" lost the lookup TD-44 had added to the
    /// word list's own second step. Reported by the owner, 2026-09-20.
    @Test func editingAWordPinsTheWordBeingDefined() throws {
        // Section 0 rows: fox, Add a word in English, лиса, лисица, Add a word in Russian.
        let input = try pushedInput(afterTapping: 2, inSection: 0, of: synonymous)
        let labels = accessibilityLabels(in: input.view)

        #expect(labels.contains("Word in English: fox"), "the slab is missing: \(labels)")
        #expect(labels.contains("Look up fox"), "no lookup beside it: \(labels)")
    }

    /// Adding a word to a meaning pins it too — the same screen, reached the other way.
    @Test func addingAWordToAMeaningPinsTheWordBeingDefined() throws {
        let input = try pushedInput(afterTapping: 4, inSection: 0, of: synonymous)
        let labels = accessibilityLabels(in: input.view)

        #expect(labels.contains("Word in English: fox"), "the slab is missing: \(labels)")
    }

    /// A brand-new meaning defines nothing yet, so there is nothing to pin and no ⓘ to offer.
    @Test func addingAMeaningPinsNothing() throws {
        let vc = screen(synonymous)
        let trailing = vc.numberOfSections(in: vc.tableView) - 1
        let input = try pushedInput(afterTapping: 0, inSection: trailing, of: synonymous)

        #expect(!accessibilityLabels(in: input.view).contains { $0.hasPrefix("Word in ") },
                "a new meaning has no word to pin")
    }

    // MARK: - Adding without a comma

    /// The owner's *"make commas less necessary"*, end to end: a third meaning arrives from
    /// the empty section, with no comma typed anywhere.
    @Test func anotherMeaningCanBeAddedWithoutTypingAComma() throws {
        let vc = screen(polysemous)
        let navigation = UINavigationController(rootViewController: vc)
        let trailing = vc.numberOfSections(in: vc.tableView) - 1
        #expect(labels(ofSection: trailing, on: vc) == ["Add another meaning"], "precondition")

        tapRow(0, inSection: trailing, on: vc)
        let input = try #require(navigation.topViewController as? WordInputViewController,
                                 "the empty section has to push the word input screen")
        input.view.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        input.view.layoutIfNeeded()
        try #require(firstTextField(in: input.view)).text = "cat"
        let save = try #require(input.navigationItem.rightBarButtonItem)
        _ = save.target?.perform(save.action, with: save)

        #expect(vc.numberOfSections(in: vc.tableView) == 4, "three meanings, plus the empty section")
        // Merge is offered here too: it is a later meaning like any other.
        #expect(labels(ofSection: 2, on: vc) ==
                ["cat", "Add a word in English", "Add a word in Russian",
                 "Merge into the meaning above"])
        // Half a meaning cannot be practised in either direction, so Save does not promise to
        // store it — and the footer says which side is missing rather than just going grey.
        #expect(vc.navigationItem.rightBarButtonItem?.isEnabled == false)
        #expect(vc.tableView(vc.tableView, titleForFooterInSection: 2) == "Needs a word in Russian.")
        // The two footers must not contradict each other: counting sections said "3 meanings
        // will be created" while Save sat greyed out because one of them was half-filled.
        #expect(vc.tableView(vc.tableView, titleForFooterInSection: 3) == "2 meanings will be created")
    }

    private func firstTextField(in view: UIView) -> UITextField? {
        if let field = view as? UITextField { return field }
        for subview in view.subviews {
            if let found = firstTextField(in: subview) { return found }
        }
        return nil
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
