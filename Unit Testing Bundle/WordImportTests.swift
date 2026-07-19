//
//  WordImportTests.swift
//  Unit Testing Bundle
//
//  Parser for text shared via the ImportAsDictAction extension (TD-3).
//

import Testing
@testable import LearnWords

struct WordImportTests {

    @Test func parsesPipeSeparatedLines() {
        let words = WordImport.parseDictionary("bear|медведь\nfox|лиса")
        #expect(words.map(\.firstWord) == ["bear", "fox"])
        #expect(words.map(\.secondWord) == ["медведь", "лиса"])
    }

    @Test(arguments: ["bear : медведь", "bear-медведь", "bear – медведь"])
    func supportsColonDashAndEnDashSeparators(line: String) {
        let words = WordImport.parseDictionary(line)
        #expect(words.map(\.firstWord) == ["bear"])
        #expect(words.map(\.secondWord) == ["медведь"])
    }

    @Test func trimsWhitespaceAroundParts() {
        let words = WordImport.parseDictionary("  bear  |  медведь  ")
        #expect(words.first?.firstWord == "bear")
        #expect(words.first?.secondWord == "медведь")
    }

    @Test func acceptsUnicodeLineSeparator() {
        // U+2028 LINE SEPARATOR appears in text copied from some apps.
        let words = WordImport.parseDictionary("bear|медведь\u{2028}fox|лиса")
        #expect(words.count == 2)
    }

    @Test func skipsMalformedLines() {
        let text = """
        no separator here at all all all
        |missing first
        missing second|
        bear|медведь
        """
        let words = WordImport.parseDictionary(text)
        #expect(words.map(\.firstWord) == ["bear"])
    }

    @Test func preservesCase() {
        // Import intentionally does NOT canonicalise (unlike manual flashcard entry).
        let words = WordImport.parseDictionary("Bear|Медведь")
        #expect(words.first?.firstWord == "Bear")
    }

    @Test func multiWordPhrasesSurvive() {
        let words = WordImport.parseDictionary("polar bear|полярный медведь")
        #expect(words.first?.firstWord == "polar bear")
        #expect(words.first?.secondWord == "полярный медведь")
    }

    @Test func hyphenatedWordIsSkippedKnownLimitation() {
        // FIXME parity: '-' is also a pair separator, so hyphenated words split into
        // 3 parts and the line is skipped. Documents the known limitation.
        let words = WordImport.parseDictionary("well-known|известный")
        #expect(words.isEmpty)
    }
}
