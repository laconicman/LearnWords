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
        #expect(lines.map(\.first) == [["bear"], ["fox"]])
        #expect(lines.map(\.second) == [["медведь"], ["лиса"]])
    }

    /// The defect this closes: `render` writes "fox : лиса, лисица" and `parse` used to
    /// read the whole right side as one term, so a round trip produced a word literally
    /// named "лиса, лисица".
    @Test func commasSeparateSynonymsWithinASide() {
        let lines = PlainText.parse("fox, reynard | лиса, лисица")
        #expect(lines == [PlainText.Line(first: ["fox", "reynard"],
                                         second: ["лиса", "лисица"])])
    }

    @Test func emptySynonymEntriesAreDropped() {
        // A trailing comma is a typo, not a blank word.
        #expect(PlainText.parse("fox, | лиса,,") == [PlainText.Line(first: ["fox"],
                                                                    second: ["лиса"])])
    }

    @Test(arguments: ["bear : медведь", "bear-медведь", "bear – медведь"])
    func supportsColonDashAndEnDashSeparators(line: String) {
        #expect(PlainText.parse(line) == [PlainText.Line(first: ["bear"], second: ["медведь"])])
    }

    @Test func trimsWhitespaceAroundParts() {
        #expect(PlainText.parse("  bear  |  медведь  ")
                == [PlainText.Line(first: ["bear"], second: ["медведь"])])
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
        #expect(PlainText.parse(text).map(\.first) == [["bear"]])
    }

    @Test func preservesCase() {
        // Import intentionally does NOT canonicalise (unlike manual flashcard entry).
        #expect(PlainText.parse("Bear|Медведь").first?.first == ["Bear"])
    }

    @Test func multiWordPhrasesSurvive() {
        // Spaces are not synonym separators — only commas are.
        #expect(PlainText.parse("polar bear|полярный медведь")
                == [PlainText.Line(first: ["polar bear"], second: ["полярный медведь"])])
    }

    /// The defect this closes, found by importing into the running app rather than by
    /// reading the parser: `-` is both a pair separator and a character inside ordinary
    /// words, so every hyphenated word split into three parts and the line vanished with
    /// nothing said to the learner. Six lines went in, two came out.
    @Test(arguments: ["well-known|известный",
                      "well-known : известный",
                      "well-known - известный",
                      "well-known — известный"])
    func aHyphenatedWordSurvivesWhenTheLineSaysHowItIsSeparated(line: String) {
        #expect(PlainText.parse(line)
                == [PlainText.Line(first: ["well-known"], second: ["известный"])])
    }

    /// `—` is what iOS and macOS autocorrect make of `--`, and what most pasted prose
    /// carries. It was not a separator, so a line written on the phone could not be read
    /// back by it.
    @Test func anEmDashSeparatesLikeTheOtherDashes() {
        #expect(PlainText.parse("badger — барсук")
                == [PlainText.Line(first: ["badger"], second: ["барсук"])])
    }

    /// The ordering is not free: a bare dash must keep working, because it is the one
    /// case that cannot be told apart from a hyphen except by trying it last.
    @Test func aBareDashStillSeparatesWhenNothingElseDoes() {
        #expect(PlainText.parse("bear-медведь")
                == [PlainText.Line(first: ["bear"], second: ["медведь"])])
    }

    /// The round trip the design leans on: **anything the app can write, it must read.**
    /// A hyphenated word can always be *typed* even when it could not be imported, so
    /// export followed by import silently deleted it — from the app's own file.
    @Test func aHyphenatedWordSurvivesTheAppsOwnRoundTrip() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Round trip", languages: ["en", "ru"])
        // Typed, not imported — a word that could never get in through the importer can
        // always be entered by hand, which is exactly how one came to be exported and
        // then lost.
        _ = try lexicon.addSenses(to: set.id, terms: [[Term.Draft("well-known", in: "en"),
                                                       Term.Draft("известный", in: "ru")]])

        let exported = PlainText.render(try lexicon.senses(in: set.id), from: "en", to: "ru")
        #expect(exported.contains("well-known"), "precondition: export writes it")

        let empty = try lexicon.addWordSet(named: "Reimported", languages: ["en", "ru"])
        try lexicon.importPlainText(exported, into: empty.id, first: "en", second: "ru")
        let words = try lexicon.senses(in: empty.id).flatMap { $0.terms(in: "en") }.map(\.text)
        #expect(words.contains("well-known"), "the app must be able to read its own file")
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

    @Test func importCreatesSynonyms() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])

        #expect(try lexicon.importPlainText("fox, reynard | лиса, лисица",
                                            into: set.id, first: "en", second: "ru") == 1)

        let sense = try #require(try lexicon.senses(in: set.id).first)
        #expect(Set(sense.terms(in: "en").map(\.text)) == ["fox", "reynard"])
        #expect(Set(sense.terms(in: "ru").map(\.text)) == ["лиса", "лисица"])
    }

    @Test func importSkipsALineWhenAnyOfItsWordsIsAlreadyPresent() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        try lexicon.addSense(to: set.id, terms: [Term.Draft("reynard", in: "en"),
                                                 Term.Draft("лис", in: "ru")])

        // "fox" is new but "reynard" is not — merging would be a guess.
        #expect(try lexicon.importPlainText("fox, reynard | лиса, лисица",
                                            into: set.id, first: "en", second: "ru") == 0)
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

    /// The real round trip, into an **empty** set — where the old dedup could not mask
    /// the loss. This is the case that was broken: it produced one term named
    /// "лиса, лисица" instead of two synonyms.
    @Test func synonymsSurviveExportAndReimportIntoAnEmptySet() throws {
        let source = makeLexicon()
        let set = try source.addWordSet(named: "Animals", languages: ["en", "ru"])
        try source.addSense(to: set.id, terms: [Term.Draft("fox", in: "en"),
                                                Term.Draft("лиса", in: "ru"),
                                                Term.Draft("лисица", in: "ru")])
        let text = PlainText.render(try source.senses(in: set.id), from: "en", to: "ru")

        let destination = makeLexicon()
        let copy = try destination.addWordSet(named: "Animals", languages: ["en", "ru"])
        #expect(try destination.importPlainText(text, into: copy.id,
                                                first: "en", second: "ru") == 1)

        let sense = try #require(try destination.senses(in: copy.id).first)
        #expect(sense.terms(in: "en").map(\.text) == ["fox"])
        #expect(Set(sense.terms(in: "ru").map(\.text)) == ["лиса", "лисица"],
                "two synonyms, not one term named \"лиса, лисица\"")
    }
}
