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

    @Test(arguments: [("tab", "\t"), ("Tab", "\t"), ("comma", ","), ("semicolon", ";"),
                      (";", ";"), ("space", " ")])
    func theSeparatorDirective(_ value: String, _ separator: String) throws {
        let file = "#separator:\(value)\nfox\(separator)лиса\n"
        #expect(try read(file).lines == [.init(first: ["fox"], second: ["лиса"])])
    }

    /// The spellings plain text also uses need a second directive before they decide the format
    /// — on their own they are as likely to be a plain pair. Reported by review, PR #29.
    @Test(arguments: [("PIPE", "|"), (" Colon ", ":"), ("-", "-")])
    func theSeparatorDirectiveNamingAPlainSpelling(_ value: String, _ separator: String) throws {
        #expect(AnkiText.read("#separator:\(value)\nfox\(separator)лиса\n") == nil,
                "a lone \(value) directive should not settle the format")
        let corroborated = "#separator:\(value)\n#html:false\nfox\(separator)лиса\n"
        #expect(try read(corroborated).lines == [.init(first: ["fox"], second: ["лиса"])])
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

    /// An Anki file whose rows carry a single field is still Anki: it opens with a directive.
    /// Read as plain text its header would become words — the bug this reader exists for — so
    /// the rows are reported unreadable instead. Reported by review, PR #29.
    @Test func anAnkiFileWithSingleFieldRowsReportsThemRatherThanImportingItsHeader() throws {
        let file = "#separator:tab\n#notetype:Basic\nfox\nbear\n"
        #expect(try read(file) == .init(lines: [], unreadable: 2))

        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        let summary = try lexicon.importText(file, into: set.id, first: "en", second: "ru")
        #expect(summary == .init(added: 0, duplicates: 0, unreadable: 2))
        #expect(try lexicon.senses(in: set.id).isEmpty, "the header must not become words")
    }

    /// `#separator:` declares the delimiter wherever it sits, so a header line before it cannot
    /// cost the file its format — even when every row is malformed. Reported by review, PR #29.
    @Test func aSeparatorAfterAnotherHeaderStillProtectsTheHeaderFromBeingImported() throws {
        let file = "#html:false\n#separator:tab\nfox\n"
        #expect(try read(file) == .init(lines: [], unreadable: 1))

        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        let summary = try lexicon.importText(file, into: set.id, first: "en", second: "ru")
        #expect(summary == .init(added: 0, duplicates: 0, unreadable: 1))
        #expect(try lexicon.senses(in: set.id).isEmpty, "the header must not become words")
    }

    /// Only `#separator:` says how to read the body, so only it is conclusive. `#deck:Animals`
    /// is equally a plain-text pair, and this file is two meanings. Reported by review, PR #29.
    @Test func anOpeningDirectiveThatDeclaresNoDelimiterDoesNotMakeItAnki() throws {
        let text = "#deck:Animals\nfox:лиса\n"
        #expect(AnkiText.read(text) == nil)

        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Plain", languages: ["en", "ru"])
        let summary = try lexicon.importText(text, into: set.id, first: "en", second: "ru")
        #expect(summary == .init(added: 2, duplicates: 0, unreadable: 0))
    }

    /// A `#` line with no colon at all is still part of the header run — a comment some
    /// exporters put first. The file is Anki on the strength of the directive below it and a
    /// tab-delimited body, not of its first line.
    @Test func aCommentedFirstHeaderLineDoesNotDecideTheFormat() throws {
        let file = "# exported by a tool\n#separator:tab\n#html:false\nfox\tлиса\n"
        #expect(try read(file).lines == [.init(first: ["fox"], second: ["лиса"])])
    }

    /// A space is *not* one of plain text's separators — `sides(of:)` needs `|`, `:` or a dash,
    /// so whitespace alone never divides a line and `fox лиса` is dropped. That premise is
    /// asserted here, because it is what makes a declared space conclusive. Reported by review,
    /// PR #29, after listing the space as shared broke space-delimited Anki files.
    @Test func aSpaceNeverDividesAPlainTextLine() {
        #expect(PlainText.parse("fox лиса").isEmpty)
        #expect(PlainText.parse("fox - лиса").count == 1, "a dash with spaces still divides")
    }

    /// `colon`, `pipe` and the dashes are plain text's own separators, so a body splitting on one
    /// is no evidence at all. A lone such directive is a plain-text pair: this file is two
    /// meanings, not an Anki file that loses one. Reported by review, PR #29.
    @Test(arguments: ["colon", "pipe"])
    func aLoneSeparatorDirectiveNamingAPlainSeparatorIsPlainText(_ value: String) throws {
        let text = "#separator:\(value)\nfox : лиса\n"
        #expect(AnkiText.read(text) == nil)

        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Plain", languages: ["en", "ru"])
        let summary = try lexicon.importText(text, into: set.id, first: "en", second: "ru")
        #expect(summary == .init(added: 2, duplicates: 0, unreadable: 0))
    }

    /// The trade this makes, stated so it is a decision and not a surprise: because a declared
    /// space is conclusive, a *plain* file that declares one — which needs the word `#separator`
    /// as its first term — has its rows split on every space, so `fox : лиса` yields `fox` and
    /// `:`. No exporter here writes such a file, and the alternative broke every genuine
    /// space-delimited Anki file. Reported by review, PR #29.
    @Test func aDeclaredSpaceIsConclusiveEvenWhereThatCosts() throws {
        #expect(try read("#separator:space\nfox лиса\n").lines
                == [.init(first: ["fox"], second: ["лиса"])])
        #expect(try read("#separator:space\nfox : лиса\n").lines
                == [.init(first: ["fox"], second: [":"])], "the accepted cost")
    }

    /// A real Anki file delimited that way carries a header block, and a second directive is
    /// enough to corroborate the first.
    @Test func aCorroboratedNonTabSeparatorIsAnki() throws {
        let read = try read("#separator:colon\n#html:false\nfox:лиса\nbear:медведь\n")
        #expect(read.lines == [.init(first: ["fox"], second: ["лиса"]),
                               .init(first: ["bear"], second: ["медведь"])])
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
