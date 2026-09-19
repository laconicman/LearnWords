//
//  AnkiTextTests.swift
//  Unit Testing Bundle
//
//  The Anki export. Every expectation here is a clause of a foreign application's parser
//  contract, checked against `ankitects/anki` source rather than its manual — so each test
//  says which clause it protects. Getting one wrong produces a file that imports *quietly*
//  wrong, which is the failure mode worth testing against.
//
//  These read the file the way Anki's reader would, independently of `AnkiText.read` — so an
//  exporter bug and a matching reader bug cannot cancel out. Reading the export back into the
//  app is `AnkiImportTests`.
//

import Testing
import Foundation
@testable import LearnWords

@MainActor
struct AnkiTextTests {

    private func makeLexicon() -> Lexicon {
        Lexicon(persistence: LWPersistence(inMemory: true))
    }

    /// Splits a rendered file into records the way an RFC 4180 reader does — a newline
    /// inside a quoted field does **not** end the record.
    ///
    /// Worth the ten lines: splitting naively on "\n" passes every test here except the
    /// one about disambiguation notes, and then reports the exporter as broken when it is
    /// the test that cannot read the format.
    private func records(_ text: String) -> [String] {
        var records: [String] = []
        var current = ""
        var inQuotes = false
        for character in text {
            if character == "\"" { inQuotes.toggle() }
            if character == "\n" && !inQuotes {
                records.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { records.append(current) }
        return records
    }

    /// The data rows, with the `#` header stripped the way Anki does.
    private func rows(_ text: String) -> [String] {
        records(text).filter { !$0.hasPrefix("#") }
    }

    private func headers(_ text: String) -> [String] {
        records(text).filter { $0.hasPrefix("#") }
    }

    private func render(_ lexicon: Lexicon, _ set: WordSet) throws -> String {
        AnkiText.render(try lexicon.senses(in: set.id), from: "en", to: "ru", deck: set.name)
    }

    @discardableResult
    private func stocked(_ lexicon: Lexicon) throws -> WordSet {
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        try lexicon.addSense(to: set.id, terms: [Term.Draft("fox", in: "en"),
                                                 Term.Draft("лиса", in: "ru"),
                                                 Term.Draft("лисица", in: "ru")])
        return set
    }

    // MARK: - Header

    @Test func theHeaderDeclaresEverythingTheParserLocks() throws {
        let lexicon = makeLexicon()
        let set = try stocked(lexicon)

        let declared = headers(try render(lexicon, set))
        #expect(declared.contains("#separator:tab"))
        #expect(declared.contains("#html:false"))
        #expect(declared.contains("#notetype:Basic"))
        #expect(declared.contains("#deck:Animals"))
        #expect(declared.contains("#tags column:3"))
        #expect(declared.contains("#guid column:4"))
        // A GUID match is an identity match; "keep both" makes Anki *skip* the row.
        #expect(declared.contains("#if matches:update current"))
    }

    /// The header is read line by line, not as CSV, so a value cannot be quoted out of
    /// trouble — a newline in a set name would end the header early and turn the rest into
    /// a data row.
    @Test func aSetNameCannotBreakTheHeaderLine() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Two\nLines\tHere", languages: ["en", "ru"])
        try lexicon.addSense(to: set.id, terms: [Term.Draft("fox", in: "en"),
                                                 Term.Draft("лиса", in: "ru")])

        let text = try render(lexicon, set)
        #expect(headers(text).contains("#deck:Two Lines Here"))
        #expect(rows(text).count == 1, "the name did not spill into the rows")
    }

    // MARK: - Rows

    @Test func aRowIsFrontBackTagsAndGuid() throws {
        let lexicon = makeLexicon()
        let set = try stocked(lexicon)
        let sense = try #require(try lexicon.senses(in: set.id).first)

        let columns = try #require(rows(try render(lexicon, set)).first)
            .components(separatedBy: "\t")
        #expect(columns.count == 4)
        #expect(columns[0] == "fox")
        #expect(columns[1] == "лиса, лисица", "synonyms stay on one card, comma-joined")
        #expect(columns[2] == "")
        #expect(columns[3] == sense.id.uuidString)
    }

    /// The GUID is what makes a re-export update the same notes instead of duplicating
    /// them, and what keeps two meanings of one word apart.
    @Test func eachMeaningCarriesItsOwnStableIdentity() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        try lexicon.addSense(to: set.id, terms: [Term.Draft("bear", in: "en"),
                                                 Term.Draft("медведь", in: "ru")])
        try lexicon.addSense(to: set.id, terms: [Term.Draft("bear", in: "en"),
                                                 Term.Draft("нести", in: "ru")])

        let guids = rows(try render(lexicon, set)).map { $0.components(separatedBy: "\t")[3] }
        #expect(guids.count == 2)
        #expect(Set(guids).count == 2, "same front word, two identities")
        #expect(try render(lexicon, set) == (try render(lexicon, set)),
                "re-export is stable, so re-import updates rather than duplicates")
    }

    @Test func meaningsMissingASideAreLeftOut() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        try lexicon.addSense(to: set.id, terms: [Term.Draft("fox", in: "en"),
                                                 Term.Draft("лиса", in: "ru")])
        try lexicon.addSense(to: set.id, terms: [Term.Draft("camel", in: "en")])

        #expect(rows(try render(lexicon, set)).count == 1)
    }

    // MARK: - The note

    /// It goes on the front because that is where the app shows it: a question that does
    /// not say which "bear" it means cannot be answered.
    @Test func theDisambiguationNoteJoinsTheQuestion() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        try lexicon.addSense(to: set.id, terms: [Term.Draft("bear", in: "en"),
                                                 Term.Draft("медведь", in: "ru")],
                             note: "the animal")

        let front = try #require(rows(try render(lexicon, set)).first)
            .components(separatedBy: "\t")[0]
        // Quoted because it carries a newline, which `#html:false` turns into <br>.
        #expect(front == "\"bear\nthe animal\"")
    }

    @Test func aMeaningWithoutANoteGetsNoExtraLine() throws {
        let lexicon = makeLexicon()
        let set = try stocked(lexicon)
        #expect(try #require(rows(try render(lexicon, set)).first).hasPrefix("fox\t"))
    }

    // MARK: - Tags

    @Test func tagsAreSpaceSeparatedAndCannotContainSpaces() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        try lexicon.addSense(to: set.id, terms: [Term.Draft("fox", in: "en"),
                                                 Term.Draft("лиса", in: "ru")],
                             tags: ["slang", "domain:medicine", "old fashioned"])

        let column = try #require(rows(try render(lexicon, set)).first)
            .components(separatedBy: "\t")[2]
        // Anki splits tags on whitespace, so "old fashioned" would arrive as two tags.
        #expect(column.components(separatedBy: " ").sorted()
                == ["domain:medicine", "old_fashioned", "slang"])
    }

    // MARK: - Escaping

    /// Anki's record reader treats `#` as a comment character, so an unquoted row that
    /// starts with one is dropped without a word of complaint.
    @Test func aWordStartingWithAHashIsQuotedSoTheRowSurvives() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Tags", languages: ["en", "ru"])
        try lexicon.addSense(to: set.id, terms: [Term.Draft("#hashtag", in: "en"),
                                                 Term.Draft("хештег", in: "ru")])

        let row = try #require(rows(try render(lexicon, set)).first)
        #expect(row.hasPrefix("\"#hashtag\""))
        #expect(!row.hasPrefix("#"), "otherwise the whole row is read as a comment")
    }

    @Test(arguments: [("say \"hi\"", "\"say \"\"hi\"\"\""),
                      ("a\tb", "\"a\tb\"")])
    func quotesAndSeparatorsAreEscapedRFC4180(text: String, expected: String) throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Odd", languages: ["en", "ru"])
        try lexicon.addSense(to: set.id, terms: [Term.Draft(text, in: "en"),
                                                 Term.Draft("что-то", in: "ru")])

        #expect(try #require(rows(try render(lexicon, set)).first).hasPrefix(expected))
    }

    /// `#html:false` means Anki escapes `<`, `>` and `&` itself. Writing our own escape
    /// here would double it — the card would read `&lt;b&gt;`.
    @Test func markupInAWordIsLeftForAnkiToEscape() throws {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Odd", languages: ["en", "ru"])
        try lexicon.addSense(to: set.id, terms: [Term.Draft("<b> & <i>", in: "en"),
                                                 Term.Draft("теги", in: "ru")])

        let front = try #require(rows(try render(lexicon, set)).first)
            .components(separatedBy: "\t")[0]
        #expect(front == "<b> & <i>", "verbatim — no markup is written by us")
    }

    @Test func anEmptySetRendersTheHeaderAndNoRows() {
        let text = AnkiText.render([], from: "en", to: "ru", deck: "Empty")
        #expect(rows(text).isEmpty)
        #expect(headers(text).count == 7)
    }
}
