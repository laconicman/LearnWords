//
//  PlainText.swift
//  LearnWords
//
//  The line-per-word text format the app reads and writes: one meaning per line, the two
//  words separated by `|`, `:`, `-` or `–`.
//
//  It is the app's only interchange format, and it is the reason "the user can always
//  import the dictionary" is a satisfying answer to dropping migration (docs/Design.md).
//  It arrives from two places — a file the user picks, and text shared through the
//  ImportAsDictAction extension (TD-3) — so parsing lives here rather than in either
//  screen, which is how the two paths stay one behaviour.
//
//  Parsing and rendering are pure functions over text: no store, no UIKit, directly
//  testable. Putting words *into* the store is `Lexicon.importPlainText`, below, because
//  deduplication needs to see what is already there.
//

import Foundation

enum PlainText {

    /// The synonym separator *within* one side of a line. Commas, because that is what
    /// `render` writes — parse and render must be inverses or a round trip loses words.
    private static let synonymSeparator: Character = ","

    /// One line of the format: the words for one meaning, on each side.
    ///
    /// Arrays rather than strings because a meaning may have synonyms — that is the whole
    /// point of the lexical model, and a format that could not carry them would quietly
    /// flatten "fox / лиса, лисица" into a term literally named "лиса, лисица".
    struct Line: Equatable {
        var first: [String]
        var second: [String]
    }

    /// Splits text into meanings. Lines that do not yield exactly two non-empty sides are
    /// skipped — a heading or a blank line should not become a word.
    ///
    /// Values are whitespace-trimmed but otherwise kept verbatim: an import records what
    /// the source said. Canonicalisation, if it ever happens, belongs where words are
    /// typed, not where they are read in bulk.
    // FIXME: remove the dash separator or handle it — a hyphenated word ("well-known")
    // splits into three parts and is skipped. Pre-existing behaviour, kept for parity.
    static func parse(_ text: String) -> [Line] {
        split(text, by: "\n" + "\u{2028}", union: .newlines).compactMap { entry in
            let parts = split(entry, by: "|:-–")
            guard parts.count == 2 else { return nil }
            let first = synonyms(in: parts[0])
            let second = synonyms(in: parts[1])
            guard !first.isEmpty, !second.isEmpty else { return nil }
            return Line(first: first, second: second)
        }
    }

    /// One side of a line, split into its synonyms. Empty entries are dropped, so a
    /// trailing comma is a typo rather than a blank word.
    private static func synonyms(in side: String) -> [String] {
        side.split(separator: synonymSeparator)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Renders meanings back out, one line each.
    ///
    /// Synonyms are joined with commas on their own side, and `parse` splits them back —
    /// a round trip is lossless, which is what makes export/import a real answer to
    /// "the user can always import the dictionary" (docs/Design.md).
    static func render(_ senses: [Sense], from: String, to: String) -> String {
        senses.compactMap { sense in
            let left = sense.terms(in: from).map(\.text)
            let right = sense.terms(in: to).map(\.text)
            guard !left.isEmpty, !right.isEmpty else { return nil }
            return left.joined(separator: ", ") + " : " + right.joined(separator: ", ")
        }
        .joined(separator: "\n")
    }
}

// MARK: - Importing into the store

extension Lexicon {

    /// Reads plain text into a set and reports how many meanings it added.
    ///
    /// A line is skipped when **any** of its first-side words is already in the set,
    /// rather than merged: the two might be different meanings of the same word, and
    /// guessing wrong would fuse them permanently. Reviewing and merging duplicates is a
    /// screen this app does not have yet — the TODO the old importer carried, now stated
    /// where it belongs.
    @discardableResult
    func importPlainText(_ text: String,
                         into setID: UUID,
                         first: String,
                         second: String) throws -> Int {
        let lines = PlainText.parse(text)
        guard !lines.isEmpty else { return 0 }

        // Grows as the file is read, so a word repeated *within* the text is added once.
        var seen = Set(try senses(in: setID)
            .flatMap { $0.terms(in: first) }
            .map { $0.text.lowercased() })

        let drafts = lines.compactMap { line -> [Term.Draft]? in
            let words = line.first.map { $0.lowercased() }
            guard words.allSatisfy({ !seen.contains($0) }) else { return nil }
            seen.formUnion(words)
            return line.first.map { Term.Draft($0, in: first) }
                 + line.second.map { Term.Draft($0, in: second) }
        }

        return try addSenses(to: setID, terms: drafts)
    }
}
