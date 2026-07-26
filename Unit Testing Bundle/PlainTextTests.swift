//
//  PlainTextTests.swift
//  Unit Testing Bundle
//
//  The interchange format: text the user picks from a file or shares into the app.
//
//  Replaces `WordImportTests`. The parsing cases are the same behaviour under a new name;
//  the import and round-trip cases are new, because the destination changed from a flat
//  array to a set of meanings.
//

import Testing
import Foundation
@testable import LearnWords

@MainActor
struct PlainTextTests {

    private func makeLexicon() -> Lexicon {
        Lexicon(persistence: LWPersistence(inMemory: true))
    }

    // MARK: - Parsing

    @Test func parsesPipeSeparatedLines() {
        let lines = PlainText.parse("bear|медведь\nfox|лиса")
        #expect(lines.map(\.first) == ["bear", "fox"])
        #expect(lines.map(\.second) == ["медведь", "лиса"])
    }

    @Test(arguments: ["bear : медведь", "bear-медведь", "bear – медведь"])
    func supportsColonDashAndEnDashSeparators(line: String) {
        #expect(PlainText.parse(line) == [PlainText.Line(first: "bear", second: "медведь")])
    }

    @Test func trimsWhitespaceAroundParts() {
        #expect(PlainText.parse("  bear  |  медведь  ")
                == [PlainText.Line(first: "bear", second: "медведь")])
    }

    @Test func acceptsUnicodeLineSeparator() {
        // U+2028 LINE SEPARATOR appears in text copied from some apps.
        #expect(PlainText.parse("bear|медведь\u{2028}fox|лиса").count == 2)
    }

    @Test func skipsMalformedLines() {
        let text = """
        no separator here at all all all
        |missing first
        missing second|
        bear|медведь
        """
        #expect(PlainText.parse(text).map(\.first) == ["bear"])
    }

    @Test func preservesCase() {
        // Import intentionally does NOT canonicalise (unlike manual flashcard entry).
        #expect(PlainText.parse("Bear|Медведь").first?.first == "Bear")
    }

    @Test func multiWordPhrasesSurvive() {
        #expect(PlainText.parse("polar bear|полярный медведь")
                == [PlainText.Line(first: "polar bear", second: "полярный медведь")])
    }

    @Test func hyphenatedWordIsSkippedKnownLimitation() {
        // FIXME parity: '-' is also a pair separator, so hyphenated words split into
        // 3 parts and the line is skipped. Documents the known limitation.
        #expect(PlainText.parse("well-known|известный").isEmpty)
    }

    // MARK: - Importing

    @Test func importAddsOneMeaningPerLine() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])

        let added = try lexicon.importPlainText("bear|медведь\nfox|лиса",
                                                into: set.id, first: "en", second: "ru")

        #expect(added == 2)
        let senses = try lexicon.senses(in: set.id)
        #expect(senses.count == 2)
        #expect(Set(senses.flatMap { $0.terms(in: "en") }.map(\.text)) == ["bear", "fox"])
        #expect(Set(senses.flatMap { $0.terms(in: "ru") }.map(\.text)) == ["медведь", "лиса"])
    }

    @Test func importSkipsWordsTheSetAlreadyHas() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        try lexicon.addSense(to: set.id, terms: [Term.Draft("bear", in: "en"),
                                                 Term.Draft("медведь", in: "ru")])

        // Same word, a different translation — two meanings would be a guess, so it is
        // left alone rather than merged.
        let added = try lexicon.importPlainText("bear|мишка\nfox|лиса",
                                                into: set.id, first: "en", second: "ru")

        #expect(added == 1)
        #expect(try lexicon.senses(in: set.id).count == 2)
    }

    @Test func importAddsARepeatedWordOnlyOnce() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])

        let added = try lexicon.importPlainText("bear|медведь\nBEAR|мишка",
                                                into: set.id, first: "en", second: "ru")

        #expect(added == 1, "the same word twice in one file is one meaning")
    }

    /// The whole file lands in one transaction, and one language row serves all of it —
    /// the reason `addSenses` exists.
    @Test func aWholeImportSharesOneLanguageRow() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        let text = (1...50).map { "word\($0)|слово\($0)" }.joined(separator: "\n")

        #expect(try lexicon.importPlainText(text, into: set.id, first: "en", second: "ru") == 50)
        #expect(try lexicon.wordSet(set.id)?.languages == ["en", "ru"])
    }

    @Test func importIntoAMissingSetThrows() throws {
        let lexicon = makeLexicon()
        #expect(throws: (any Error).self) {
            try lexicon.importPlainText("bear|медведь", into: UUID(), first: "en", second: "ru")
        }
    }

    // MARK: - Rendering

    @Test func renderJoinsSynonymsRatherThanDroppingThem() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        try lexicon.addSense(to: set.id, terms: [Term.Draft("fox", in: "en"),
                                                 Term.Draft("лиса", in: "ru"),
                                                 Term.Draft("лисица", in: "ru")])

        let text = PlainText.render(try lexicon.senses(in: set.id), from: "en", to: "ru")
        #expect(text == "fox : лиса, лисица")
    }

    @Test func renderLeavesOutMeaningsMissingASide() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        try lexicon.addSense(to: set.id, terms: [Term.Draft("bear", in: "en"),
                                                 Term.Draft("медведь", in: "ru")])
        try lexicon.addSense(to: set.id, terms: [Term.Draft("camel", in: "en")])

        let text = PlainText.render(try lexicon.senses(in: set.id), from: "en", to: "ru")
        #expect(text == "bear : медведь")
    }

    /// Export then import must be a no-op on the same set — the file the user shares is
    /// the file the app can read back.
    @Test func aRoundTripAddsNothingNew() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        try lexicon.addSense(to: set.id, terms: [Term.Draft("bear", in: "en"),
                                                 Term.Draft("медведь", in: "ru")])
        try lexicon.addSense(to: set.id, terms: [Term.Draft("fox", in: "en"),
                                                 Term.Draft("лиса", in: "ru")])

        let text = PlainText.render(try lexicon.senses(in: set.id), from: "en", to: "ru")
        #expect(try lexicon.importPlainText(text, into: set.id, first: "en", second: "ru") == 0)
        #expect(try lexicon.senses(in: set.id).count == 2)
    }
}
