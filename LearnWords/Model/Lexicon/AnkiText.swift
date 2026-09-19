//
//  AnkiText.swift
//  LearnWords
//
//  Export in the shape Anki's file importer reads, so a word set is usable in the tool
//  most learners already run.
//
//  Separate from `PlainText` on purpose. `PlainText` is *ours* and is symmetric — `parse`
//  and `render` are inverses, which is what makes "the user can always import the
//  dictionary" true (docs/Design.md). This one implements a foreign application's contract.
//
//  It was export-only until 2026-09-18, and that was the bug: the import button accepts any
//  text file, so a learner who exported Anki and imported the file again had it read as
//  `PlainText`, which split every `#key:value` header on its colon and added both halves as
//  words, while every real row was unreadable. `read`, at the bottom, reads the file back —
//  the reader half of the same contract, verified against the same source.
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

// MARK: - Reading it back

extension AnkiText {

    /// Header keys Anki's importer recognises. A file is read as Anki only when it opens with
    /// one of them; anything else is left to `PlainText`.
    private static let directives: Set<String> = [
        "separator", "html", "notetype", "deck", "columns", "if matches",
        "tags column", "guid column", "notetype column", "deck column",
    ]

    /// The directives that name a metadata column. Exactly these four, 1-based, removed
    /// before the remaining fields are mapped (`ankitects/anki`, `csv/metadata.rs`, consulted
    /// 2026-09-18: https://deepwiki.com/search/for-ankis-csvtext-note-importe_13ad9374-44a7-466a-a6c1-b9d547db01e1).
    private static let metadataColumns: [String] = [
        "tags column", "guid column", "notetype column", "deck column",
    ]

    /// The separator names Anki accepts, case-insensitively. A literal character is also
    /// accepted, and is handled before this table is consulted.
    private static let separatorNames: [String: Character] = [
        "tab": "\t", "comma": ",", "semicolon": ";", "space": " ", "pipe": "|", "colon": ":",
    ]

    /// Reads a file of the shape `render` writes back into lines, or `nil` when the text does
    /// not open with an Anki header — so a plain-text file is never mistaken for one.
    ///
    /// Follows Anki's own reader, so a file means the same here as there: the header is the
    /// contiguous run of `#` lines at the top and nothing later; a later unquoted row starting
    /// with `#` is a comment; fields are RFC 4180; metadata columns are removed before the
    /// first two remaining fields are taken as front and back.
    ///
    /// **Not read: the note, the tags and the GUID.** The note shares the front field on a
    /// line of its own and is split off rather than kept — left in, "bear\nthe animal" would
    /// be added as a new word, and re-importing a set into itself would stop being a no-op.
    /// That matches `PlainText`, which carries no notes either. Deduplication stays by word,
    /// as for `PlainText`; the GUID could make it by meaning, which would be a change to
    /// what an import *means* rather than to how a file is read.
    static func read(_ text: String) -> PlainText.Read? {
        var rest = Substring(text)
        if rest.first == "\u{FEFF}" { rest = rest.dropFirst() }

        // The header is the whole leading run of `#` lines, as Anki reads it: unknown keys are
        // discarded, not fatal, so a file that opens with `#generated:tool` before
        // `#separator:tab` is still Anki. Checking only the first line once sent such a file to
        // `PlainText`, which imported its headers as words. Reported by review, PR #29.
        //
        // **What makes it Anki is compared untrimmed.** `PlainText.render` writes
        // `word : translation` — always a space before the colon — and a directive never has one.
        // So `#deck : колода`, the plain export of a set whose first word is `#deck`, is not read
        // as the `#deck:` directive; trimming that space once swallowed the app's own export.
        // Keys are trimmed only afterwards, for reading values, as Anki reads them.
        var header: [String: Substring] = [:]
        var isAnki = false
        while rest.first == "#" {
            let end = rest.firstIndex(where: \.isNewline) ?? rest.endIndex
            let line = rest[rest.index(after: rest.startIndex)..<end]
            if let colon = line.firstIndex(of: ":") {
                if directives.contains(line[..<colon].lowercased()) { isAnki = true }
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                header[key] = line[line.index(after: colon)...]
            }
            rest = end == rest.endIndex ? rest[end...] : rest[rest.index(after: end)...]
        }
        guard isAnki else { return nil }

        let records = self.records(in: rest, separator: separator(from: header["separator"]))

        // **A directive in the header is necessary, not sufficient.** `#deck:колода` is also a
        // valid plain-text pair — plain text accepts a colon without spaces — so the header alone
        // cannot tell `#topic : тема\n#deck:колода\nfox : лиса` (three plain meanings) from an
        // Anki file. The body can: an Anki body is delimited by its separator and a plain one is
        // not. So a file none of whose rows splits into fields is plain text after all. A file
        // with no rows stays Anki — read as plain text, its header would become words, which is
        // the bug this reader was written for. Third edge of this detector found by review,
        // PR #29; the first two were deciding by the first line alone, and by any line at all.
        guard records.isEmpty || records.contains(where: { $0.count >= 2 }) else { return nil }

        // Markup this reader would have to undo, on the strength of escaping rules nobody here
        // has read from source. Guessing would put `<b>` into words — the same class of fault
        // this reader exists to remove — so every row is reported instead of imported. This
        // app never writes such a file; it takes Anki's own "include HTML" export to make one.
        if header["html"]?.trimmingCharacters(in: .whitespaces).lowercased() == "true" {
            return PlainText.Read(lines: [], unreadable: records.count)
        }

        let excluded = Set(metadataColumns.compactMap { header[$0] }
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
        var lines: [PlainText.Line] = []
        var unreadable = 0
        for record in records {
            let fields = record.enumerated()
                .filter { !excluded.contains($0.offset + 1) }
                .map(\.element)
            guard fields.count >= 2 else { unreadable += 1; continue }
            let words = fields[0].split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            let first = PlainText.synonyms(in: words)
            let second = PlainText.synonyms(
                in: fields[1].split(whereSeparator: \.isNewline).joined(separator: ","))
            guard !first.isEmpty, !second.isEmpty else { unreadable += 1; continue }
            lines.append(PlainText.Line(first: first, second: second))
        }
        return PlainText.Read(lines: lines, unreadable: unreadable)
    }

    /// The separator a `#separator:` value names. Tab when absent or unrecognised: it is what
    /// `render` writes, and the delimiter Anki's own detection tries first.
    private static func separator(from value: Substring?) -> Character {
        guard let value else { return "\t" }
        // A literal, checked before trimming — a literal tab or space *is* whitespace.
        if value.count == 1, let literal = value.first { return literal }
        return separatorNames[value.trimmingCharacters(in: .whitespaces).lowercased()] ?? "\t"
    }

    /// Splits the body into records the way Anki's reader does.
    ///
    /// A quoted field may hold the separator, a doubled quote or a newline; an unquoted record
    /// starting with `#` is a comment; a blank line is nothing at all, not an unreadable row.
    /// Newlines are matched with `isNewline` rather than `"\n"`, because Swift reads `\r\n` as
    /// one `Character` and a file from Windows would otherwise be one enormous record.
    private static func records(in body: Substring, separator: Character) -> [[String]] {
        var records: [[String]] = []
        var fields: [String] = []
        var field = ""
        var started = false     // this field has begun, even if only with an opening quote
        var quoted = false
        var comment = false

        func endRecord() {
            fields.append(field)
            if fields.contains(where: { !$0.isEmpty }) { records.append(fields) }
            fields = []
            field = ""
            started = false
        }

        var index = body.startIndex
        while index < body.endIndex {
            let character = body[index]
            index = body.index(after: index)

            if comment {
                if character.isNewline { comment = false }
                continue
            }
            if quoted {
                if character != "\"" {
                    field.append(character)
                } else if index < body.endIndex, body[index] == "\"" {
                    field.append("\"")
                    index = body.index(after: index)
                } else {
                    quoted = false
                }
                continue
            }
            if character == "#", fields.isEmpty, !started {
                comment = true
            } else if character == "\"", !started {
                quoted = true
                started = true
            } else if character == separator {
                fields.append(field)
                field = ""
                started = false
            } else if character.isNewline {
                endRecord()
            } else {
                field.append(character)
                started = true
            }
        }
        if started || !fields.isEmpty { endRecord() }
        return records
    }
}
