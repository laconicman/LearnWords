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

    /// One line of the format: two words for one meaning.
    struct Line: Equatable {
        var first: String
        var second: String
    }

    /// Splits text into pairs. Lines that do not yield exactly two non-empty parts are
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
            guard parts.count == 2,
                  let first = parts.first?.trimmingCharacters(in: .whitespaces), !first.isEmpty,
                  let second = parts.last?.trimmingCharacters(in: .whitespaces), !second.isEmpty
            else { return nil }
            return Line(first: first, second: second)
        }
    }

    /// Renders meanings back out, one line each.
    ///
    /// Synonyms are joined with commas on their own side, so a round trip through the
    /// format does not silently drop them — it flattens them, which is the most the
    /// format can carry and is visible to anyone reading the file.
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
    /// A line whose first word is already in the set is skipped rather than merged: the
    /// two might be different meanings of the same word, and guessing wrong would fuse
    /// them permanently. Reviewing and merging duplicates is a screen this app does not
    /// have yet — the TODO the old importer carried, now stated where it belongs.
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
            guard seen.insert(line.first.lowercased()).inserted else { return nil }
            return [Term.Draft(line.first, in: first), Term.Draft(line.second, in: second)]
        }

        return try addSenses(to: setID, terms: drafts)
    }
}
