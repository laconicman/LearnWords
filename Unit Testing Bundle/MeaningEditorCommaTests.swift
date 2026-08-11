//
//  MeaningEditorCommaTests.swift
//  Unit Testing Bundle
//
//  The other half of the comma rule (TD-53), and the one with history at stake.
//
//  On the way *in*, a comma proposes separate meanings. In the meaning editor it cannot:
//  the meaning already exists and owns its `ReviewEvent` log, so splitting it would leave
//  the record of every answer on one half and none on the other. A comma there adds
//  synonyms to the meaning being edited — the only reading that cannot lose anything.
//
//  Driven through the real screens, because the rule lives in what the editor does with
//  what the input screen hands it: the store call it makes is the whole claim.
//

import Testing
import UIKit
@testable import LearnWords

@MainActor
struct MeaningEditorCommaTests {

    private let pair = LanguagePair(primary: "ru", secondary: "en", showsSecondaryAsPrompt: true)

    /// Sections are `[secondary, primary]`, so Russian is section 1 and its "Add word" row
    /// is the one past its words.
    private let russianSection = 1

    private func firstTextField(in view: UIView) -> UITextField? {
        if let field = view as? UITextField { return field }
        for subview in view.subviews {
            if let found = firstTextField(in: subview) { return found }
        }
        return nil
    }

    /// Taps "Add word" in the Russian section, types `typed` into the screen that pushes,
    /// and saves — the path a learner actually takes.
    private func addWord(_ typed: String,
                         to sense: Sense,
                         in lexicon: Lexicon) throws {
        let editor = MeaningEditorViewController(sense: sense, languages: pair, lexicon: lexicon)
        let navigation = UINavigationController(rootViewController: editor)
        editor.loadViewIfNeeded()

        let addRow = editor.tableView(editor.tableView, numberOfRowsInSection: russianSection) - 1
        editor.tableView(editor.tableView,
                         didSelectRowAt: IndexPath(row: addRow, section: russianSection))

        let input = try #require(navigation.topViewController as? WordInputViewController,
                                 "tapping the empty row must push the word input screen")
        input.view.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        input.view.layoutIfNeeded()
        try #require(firstTextField(in: input.view)).text = typed

        let save = try #require(input.navigationItem.rightBarButtonItem)
        _ = save.target?.perform(save.action, with: save)
    }

    private func stocked() throws -> (lexicon: Lexicon, set: WordSet, sense: Sense) {
        let lexicon = Lexicon(persistence: LWPersistence(inMemory: true))
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        let sense = try lexicon.addSense(to: set.id, terms: [Term.Draft("fox", in: "en"),
                                                             Term.Draft("лиса", in: "ru")])
        return (lexicon, set, sense)
    }

    /// The regression this replaces: a comma used to make one word literally spelled
    /// "лисица, кума" — the flattening `PlainText` warns about, reached from the keyboard.
    @Test func aCommaInTheEditorAddsSynonyms() throws {
        let (lexicon, _, sense) = try stocked()

        try addWord("лисица, кума", to: sense, in: lexicon)

        // Alphabetical, not typed order: `Sense` sorts its terms by (language, text), so
        // "кума" leads. Both words arriving is the claim; where they sit is the store's.
        let words = try #require(try lexicon.sense(sense.id)).terms(in: "ru").map(\.text)
        #expect(words == ["кума", "лиса", "лисица"])
    }

    /// The history guard: editing a stored meaning must never split it, however the comma
    /// is read on the way in.
    @Test func aCommaInTheEditorCreatesNoSecondMeaning() throws {
        let (lexicon, set, sense) = try stocked()

        try addWord("лисица, кума", to: sense, in: lexicon)

        #expect(try lexicon.senses(in: set.id).count == 1,
                "splitting here would strand the meaning's ReviewEvent log")
    }

    @Test func aWordWithoutCommasIsStillJustOneWord() throws {
        let (lexicon, _, sense) = try stocked()

        try addWord("лисица", to: sense, in: lexicon)

        let words = try #require(try lexicon.sense(sense.id)).terms(in: "ru").map(\.text)
        #expect(words == ["лиса", "лисица"])
    }
}
