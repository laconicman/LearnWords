//
//  WordImport.swift
//  LearnWords
//
//  Parsing for text shared via the ImportAsDictAction extension (TD-3).
//  Model layer: pure text → [WordAndStat]; consumption/UI routing stays in
//  WordTableViewController.
//

import Foundation

enum WordImport {

    /// Parses shared "dictionary" text into word pairs: one entry per line
    /// (newlines incl. U+2028), foreign and native separated by `|`, `:`, `-`, or `–`.
    /// Lines that don't yield exactly two non-empty parts are skipped.
    ///
    /// Values are whitespace-trimmed but otherwise kept as shared (no canonicalisation) —
    /// matches the historical import behavior.
    // FIXME: remove dash or mind it elsewhere — a hyphenated word ("well-known") splits
    // into 3 parts and is skipped. Pre-existing behavior, kept for parity.
    static func parseDictionary(_ text: String) -> [WordAndStat] {
        let entries = split(text, by: "\n" + "\u{2028}", union: .newlines)
        return entries.compactMap { entry in
            let parts = split(entry, by: "|:-–")
            if parts.first?.isEmpty ?? true || parts.last?.isEmpty ?? true || parts.count != 2 { return nil }
            return WordAndStat(firstWord: parts[0].trimmingCharacters(in: .whitespaces),
                               secondWord: parts[1].trimmingCharacters(in: .whitespaces),
                               correct: [:], incorrect: [:], skiped: 0)
        }
    }
}
