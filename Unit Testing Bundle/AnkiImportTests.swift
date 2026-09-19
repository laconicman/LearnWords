//
//  AnkiImportTests.swift
//  Unit Testing Bundle
//
//  Importing an Anki export back into the app that wrote it.
//
//  Reported by the owner, 2026-09-18: exporting "Animals" as Anki and importing the file
//  into the same set added words named `#separator`, `#html` and `#notetype` — and not the
//  words themselves, because the file was read as `PlainText`: every `#key:value` header
//  split on its colon into a "pair", and every tab-separated row was unreadable.
//
//  The contract clauses below were checked against `ankitects/anki`'s own reader, so a file
//  means the same thing here as in Anki.
//

import Testing
import Foundation
@testable import LearnWords

@MainActor
struct AnkiImportTests {

    private func makeLexicon() -> Lexicon {
        Lexicon(persistence: LWPersistence(inMemory: true))
    }

    /// A small "Animals" set: a synonym pair, a plain pair, and a hyphenated word.
    private func animals(_ lexicon: Lexicon) throws -> WordSet {
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        _ = try lexicon.addSense(to: set.id, terms: [Term.Draft("fox", in: "en"),
                                                     Term.Draft("лиса", in: "ru"),
                                                     Term.Draft("лисица", in: "ru")])
        _ = try lexicon.addSense(to: set.id, terms: [Term.Draft("bear", in: "en"),
                                                     Term.Draft("медведь", in: "ru")])
        _ = try lexicon.addSense(to: set.id, terms: [Term.Draft("well-known", in: "en"),
                                                     Term.Draft("известный", in: "ru")])
        return set
    }

    private func export(_ lexicon: Lexicon, _ set: WordSet) throws -> String {
        AnkiText.render(try lexicon.senses(in: set.id), from: "en", to: "ru", deck: set.name)
    }

    /// The first-language words of a set and their translations, order-free.
    private func pairs(_ lexicon: Lexicon, _ set: WordSet) throws -> Set<String> {
        Set(try lexicon.senses(in: set.id).map { sense in
            sense.terms(in: "en").map(\.text).sorted().joined(separator: ",") + " = "
                + sense.terms(in: "ru").map(\.text).sorted().joined(separator: ",")
        })
    }

    // MARK: - The report

    /// The owner's steps exactly: export as Anki, import into the same set. Every meaning is
    /// already there, so nothing may be added — and nothing from the header may appear.
    @Test func reimportingAnAnkiExportIntoItsOwnSetAddsNothing() throws {
        let lexicon = makeLexicon()
        let set = try animals(lexicon)
        let before = try pairs(lexicon, set)

        let summary = try lexicon.importText(try export(lexicon, set), into: set.id,
                                             first: "en", second: "ru")

        let after = try pairs(lexicon, set)
        #expect(after == before, "the set changed: \(after.sorted())")
        #expect(summary == .init(added: 0, duplicates: 3, unreadable: 0))
    }

    /// The other half of "the user can always import the dictionary": into an empty set,
    /// every meaning arrives with its synonyms, and a hyphenated word survives.
    @Test func anAnkiExportRestoresItsWordsIntoAnEmptySet() throws {
        let lexicon = makeLexicon()
        let original = try animals(lexicon)
        let copy = try lexicon.addWordSet(named: "Copy", languages: ["en", "ru"])

        let summary = try lexicon.importText(try export(lexicon, original), into: copy.id,
                                             first: "en", second: "ru")

        #expect(summary == .init(added: 3, duplicates: 0, unreadable: 0))
        #expect(try pairs(lexicon, copy) == pairs(lexicon, original))
    }

    // MARK: - What the exporter writes that a naive reader would get wrong

    /// The note shares the front field on a line of its own. Read as part of the word,
    /// "bear\nthe animal" would be a new word, and re-importing would stop being a no-op.
    @Test func aDisambiguationNoteIsNotReadAsPartOfTheWord() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        let bear = try lexicon.addSense(to: set.id, terms: [Term.Draft("bear", in: "en"),
                                                            Term.Draft("медведь", in: "ru")])
        try lexicon.updateSense(bear.id, note: "the animal")
        let file = try export(lexicon, set)
        #expect(file.contains("the animal"), "precondition: the note is in the export")

        let again = try lexicon.importText(file, into: set.id, first: "en", second: "ru")
        #expect(again == .init(added: 0, duplicates: 1, unreadable: 0))

        let copy = try lexicon.addWordSet(named: "Copy", languages: ["en", "ru"])
        try lexicon.importText(file, into: copy.id, first: "en", second: "ru")
        #expect(try pairs(lexicon, copy) == ["bear = медведь"])
    }

    /// Anki's reader treats `#` as a comment character, so the exporter quotes a word that
    /// starts with one. Read back, the quoting must protect it here too.
    @Test func aWordStartingWithAHashSurvives() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Tags", languages: ["en", "ru"])
        _ = try lexicon.addSense(to: set.id, terms: [Term.Draft("#hashtag", in: "en"),
                                                     Term.Draft("хештег", in: "ru")])
        let copy = try lexicon.addWordSet(named: "Copy", languages: ["en", "ru"])

        try lexicon.importText(try export(lexicon, set), into: copy.id, first: "en", second: "ru")

        #expect(try pairs(lexicon, copy) == ["#hashtag = хештег"])
    }

    // MARK: - The format, clause by clause

    private func read(_ text: String) throws -> PlainText.Read {
        try #require(AnkiText.read(text), "not recognised as Anki:\n\(text)")
    }

    /// RFC 4180: a quoted field carries the separator, a doubled quote, and a newline.
    @Test func quotedFieldsCarryTheSeparatorQuotesAndNewlines() throws {
        let file = "#separator:tab\n" + "\"say \"\"hi\"\"\"\t\"привет\tвсем\"\n"
        #expect(try read(file).lines == [.init(first: ["say \"hi\""], second: ["привет\tвсем"])])
    }

    @Test(arguments: [("tab", "\t"), ("Tab", "\t"), ("comma", ","), ("PIPE", "|"),
                      ("semicolon", ";"), (";", ";"), (" Colon ", ":")])
    func theSeparatorDirective(_ value: String, _ separator: String) throws {
        let file = "#separator:\(value)\nfox\(separator)лиса\n"
        #expect(try read(file).lines == [.init(first: ["fox"], second: ["лиса"])])
    }

    /// Metadata columns are removed before fields are mapped, wherever they sit — here the
    /// tags come first, which is the layout Anki's own export can produce.
    @Test func metadataColumnsAreExcludedWhereverTheyAre() throws {
        let file = "#separator:tab\n#tags column:1\n#guid column:4\nanimal\tfox\tлиса\tabc-123\n"
        #expect(try read(file).lines == [.init(first: ["fox"], second: ["лиса"])])
    }

    /// Headers are only the run at the top. A `#` row later is a comment: neither read nor
    /// counted as unreadable, because it was never meant as a word.
    @Test func aLaterHashRowIsACommentNotAnUnreadableRow() throws {
        let file = "#separator:tab\nfox\tлиса\n#separator:comma\nbear\tмедведь\n"
        let read = try read(file)
        #expect(read.lines.map(\.first) == [["fox"], ["bear"]])
        #expect(read.unreadable == 0)
    }

    /// A file from Windows: a byte-order mark, and `\r\n`, which Swift reads as one character.
    @Test func aByteOrderMarkAndWindowsLineEndingsAreRead() throws {
        let file = "\u{FEFF}#separator:tab\r\n#html:false\r\nfox\tлиса\r\nbear\tмедведь\r\n"
        #expect(try read(file).lines.count == 2)
    }

    /// Markup is not guessed at: every row of an HTML file is reported, none imported.
    @Test func anHTMLFileIsReportedRatherThanImported() throws {
        let file = "#separator:tab\n#html:true\n<b>fox</b>\tлиса\nbear\tмедведь\n"
        #expect(try read(file) == .init(lines: [], unreadable: 2))
    }

    /// Only a file that opens with a directive Anki knows is read as Anki.
    @Test(arguments: ["fox : лиса", "#hello world\nfox : лиса", "#to do: learn\nfox : лиса"])
    func textWithoutAnAnkiHeaderIsLeftToPlainText(_ text: String) {
        #expect(AnkiText.read(text) == nil)
    }

    /// Anki discards unknown header keys rather than stopping at them, so a directive later in
    /// the leading run still makes the file Anki. Reported by review, PR #29, with this file.
    @Test func anUnknownHeaderBeforeARecognisedOneIsStillAnki() throws {
        let read = try read("#generated:tool\n#separator:tab\nfox\tлиса\n")
        #expect(read == .init(lines: [.init(first: ["fox"], second: ["лиса"])], unreadable: 0))
    }

    /// `#deck:колода` is a valid plain-text pair *and* a valid directive. The body settles it:
    /// these rows do not split on a tab, so this is plain text with three meanings. Reported by
    /// review, PR #29, with this file.
    @Test func aDirectiveShapedPairIsPlainTextWhenTheBodyIsNotDelimited() throws {
        let text = "#topic : тема\n#deck:колода\nfox : лиса\n"
        #expect(AnkiText.read(text) == nil)

        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Plain", languages: ["en", "ru"])
        let summary = try lexicon.importText(text, into: set.id, first: "en", second: "ru")
        #expect(summary == .init(added: 3, duplicates: 0, unreadable: 0))
    }

    /// An export of an empty set is a header and nothing else. It must stay Anki: read as plain
    /// text, `#separator:tab` and the rest would each become a word — the original bug.
    @Test func anExportOfAnEmptySetImportsNothingRatherThanItsHeader() throws {
        let lexicon = makeLexicon()
        let empty = try lexicon.addWordSet(named: "Empty", languages: ["en", "ru"])
        let file = AnkiText.render([], from: "en", to: "ru", deck: empty.name)
        #expect(try read(file) == .init(lines: [], unreadable: 0))

        let summary = try lexicon.importText(file, into: empty.id, first: "en", second: "ru")
        #expect(summary.isEmpty, "summary: \(summary)")
        #expect(try lexicon.senses(in: empty.id).isEmpty)
    }

    /// Two directive-shaped words in a row — the whole leading run is `#` lines, and none of
    /// them is a directive, because `render` put a space before every colon.
    @Test func aPlainTextExportOpeningWithSeveralDirectiveShapedWordsRestores() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Odd", languages: ["en", "ru"])
        for word in ["#deck", "#html", "#separator"] {
            _ = try lexicon.addSense(to: set.id, terms: [Term.Draft(word, in: "en"),
                                                         Term.Draft("слово", in: "ru")])
        }
        let file = PlainText.render(try lexicon.senses(in: set.id), from: "en", to: "ru")
        #expect(AnkiText.read(file) == nil, "read as Anki: \(file)")

        let copy = try lexicon.addWordSet(named: "Copy", languages: ["en", "ru"])
        let summary = try lexicon.importText(file, into: copy.id, first: "en", second: "ru")
        #expect(summary == .init(added: 3, duplicates: 0, unreadable: 0))
    }

    /// The app's *own* plain-text export must still restore when its first word is spelled
    /// like a directive. `render` writes `#deck : колода` — a space before the colon, which a
    /// directive never has. Reported by review, PR #29: the detector once trimmed that space,
    /// read the line as a header, and restored nothing.
    @Test(arguments: ["#separator", "#html", "#notetype", "#deck", "#columns", "#if matches",
                      "#tags column", "#guid column", "#notetype column", "#deck column"])
    func aPlainTextExportStartingWithADirectiveShapedWordRestores(_ word: String) throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Odd", languages: ["en", "ru"])
        _ = try lexicon.addSense(to: set.id, terms: [Term.Draft(word, in: "en"),
                                                     Term.Draft("слово", in: "ru")])
        let file = PlainText.render(try lexicon.senses(in: set.id), from: "en", to: "ru")
        #expect(AnkiText.read(file) == nil, "read as Anki: \(file)")

        let copy = try lexicon.addWordSet(named: "Copy", languages: ["en", "ru"])
        let summary = try lexicon.importText(file, into: copy.id, first: "en", second: "ru")
        #expect(summary == .init(added: 1, duplicates: 0, unreadable: 0))
        #expect(try pairs(lexicon, copy) == ["\(word) = слово"])
    }
}
