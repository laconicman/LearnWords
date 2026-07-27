//
//  AnkiText.swift
//  LearnWords
//
//  Export in the shape Anki's file importer reads, so a word set is usable in the tool
//  most learners already run.
//
//  Separate from `PlainText` on purpose. `PlainText` is *ours* and is symmetric — `parse`
//  and `render` are inverses, which is what makes "the user can always import the
//  dictionary" true (docs/Design.md). This one is **export only**: it implements a foreign
//  application's contract, and nothing here reads it back.
//
//  ## The contract
//
//  Verified against `ankitects/anki` rather than the manual — the manual describes the
//  import *dialog*, and what matters is what the parser does:
//  https://deepwiki.com/search/i-want-to-generate-a-text-file_0d3f96ff-c839-45e0-a6ab-4d09401cba0c
//
//  * `#`-prefixed header lines are consumed until the first non-`#` line. Unrecognised
//    keys are silently discarded — never imported as a note.
//  * Fields are RFC 4180: wrap in `"…"` to carry the separator, a quote or a newline, and
//    double an interior quote. That holds for a tab separator too.
//  * The record reader sets `#` as its comment character, so a *row* whose first byte is
//    `#` is dropped entirely. A word like "#hashtag" therefore has to be quoted.
//  * `#html:false` makes Anki escape `<`, `>` and `&` itself and turn each newline into
//    `<br>`. We take that deal: this file writes **no markup at all**, so there is no
//    escaping of ours to get wrong and no way for a word to inject markup into a card.
//  * Columns named by `#tags column:` / `#guid column:` are excluded from field mapping,
//    so a four-column row still fills a two-field notetype correctly.
//
//  ## Column order is a compatibility decision
//
//  `front, back, tags, guid` — metadata last. The directives only exist in Anki 2.1.54
//  (Nov 2022) and later; older versions drop every `#` line. With the metadata trailing,
//  an old importer that ignores columns beyond the notetype's field count still gets
//  front and back in the right places. Metadata first would put a UUID on the front of
//  every card.
//
//  ## Why a GUID column
//
//  It makes the export *re-importable*. Anki otherwise identifies a note by its first
//  field, so re-exporting after an edit would either duplicate or overwrite by accident —
//  and two meanings of one word ("bear" the animal, "bear" the verb) would collide into a
//  single note. A GUID bypasses first-field matching completely. `Sense.id` is already a
//  stable UUID that survives edits and deletion of the words themselves (TD-18), so it is
//  the right key, and Anki accepts any non-empty string as a GUID.
//
//  ## What cannot be done here
//
//  A text import **cannot carry a notetype or its card templates**. `#notetype:` only
//  selects one that already exists and silently falls back to the user's last-used
//  notetype when the name is unknown. So a generated file cannot make cards that speak
//  (`{{tts en_US:Front}}`); that is the user's job in the template editor, after which
//  they can point the file at it by editing one header line. An earlier roadmap note
//  claimed the exporter had to emit the learner's locale for TTS to work — it was wrong,
//  and there is nothing the exporter can do about TTS at all.
//

import Foundation

enum AnkiText {

    /// Tab: the least likely character to appear in a word, and the delimiter Anki's own
    /// detection tries first. Our synonym separator is the comma, so a comma-delimited
    /// file would be ambiguous on every row that has one.
    private static let separator = "\t"

    /// The notetype every Anki installation ships with — two fields, Front and Back.
    ///
    /// Chosen so the export imports with no setup. A file naming a notetype the user has
    /// not built is *silently* mapped onto whichever one they used last, which fails in a
    /// much more confusing way than a plain card.
    private static let notetype = "Basic"

    /// Renders one word set as an Anki-importable file.
    ///
    /// - Parameters:
    ///   - deck: the deck to import into. Anki creates it if absent, and reads `::` as
    ///     hierarchy, so a set named "Travel::Food" nests.
    ///   - from: the language on the front — the one being studied.
    ///   - to: the language on the back.
    static func render(_ senses: [Sense], from: String, to: String, deck: String) -> String {
        let rows = senses.compactMap { row(for: $0, from: from, to: to) }
        return (header(deck: deck) + rows).joined(separator: "\n")
    }

    private static func header(deck: String) -> [String] {
        [
            "#separator:tab",
            "#html:false",
            "#notetype:\(notetype)",
            "#deck:\(headerValue(deck))",
            "#tags column:3",
            "#guid column:4",
            // Not "keep both": a GUID match is an identity match, and Anki skips the row
            // outright under that setting rather than adding a second copy.
            "#if matches:update current",
        ]
    }

    /// One meaning: front, back, tags, guid.
    ///
    /// The disambiguation note goes on the **front**, where the app itself shows it — a
    /// question that does not say which "bear" it means cannot be answered. `#html:false`
    /// turns the newline before it into a `<br>`, so no markup is written here.
    private static func row(for sense: Sense, from: String, to: String) -> String? {
        let front = sense.terms(in: from).map(\.text)
        let back = sense.terms(in: to).map(\.text)
        guard !front.isEmpty, !back.isEmpty else { return nil }

        var question = front.joined(separator: ", ")
        if let note = sense.note, !note.isEmpty {
            question += "\n" + note
        }
        return [question,
                back.joined(separator: ", "),
                tags(sense.tags),
                sense.id.uuidString]
            .map(field)
            .joined(separator: separator)
    }

    /// Anki splits tags on whitespace, so a tag containing a space would arrive as two.
    /// `::` is left alone — it is Anki's hierarchy separator, and a folksonomy that already
    /// reads "domain:medicine" loses nothing by nesting.
    private static func tags(_ tags: [String]) -> String {
        tags.map { $0.split(whereSeparator: \.isWhitespace).joined(separator: "_") }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// RFC 4180 quoting, applied only where it is needed.
    ///
    /// The leading-`#` case is the one that is easy to miss: the reader treats `#` as a
    /// comment character, so an unquoted row beginning with one is dropped in silence.
    private static func field(_ value: String) -> String {
        let needsQuoting = value.contains(separator) || value.contains("\"")
            || value.contains("\n") || value.contains("\r") || value.hasPrefix("#")
        guard needsQuoting else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// A header value cannot be quoted — the header is read line by line, not as CSV — so
    /// anything that would break the line is flattened instead.
    private static func headerValue(_ value: String) -> String {
        value.split(whereSeparator: { $0.isNewline || $0 == "\t" })
            .joined(separator: " ")
    }
}
