//
//  SenseEntry.swift
//  LearnWords
//
//  What the learner typed, turned into the meanings it proposes — before anything reaches
//  the store.
//
//  **A comma is genuinely ambiguous, so this type proposes rather than decides.** `берег,
//  банк` for *bank* is two meanings; `лиса, лисица` for *fox* is one meaning with two
//  synonyms; no parser can tell them apart, because both were typed with the same key
//  (docs/LexicalModelResearch.md § *Commas at entry*). The default is the owner's rule —
//  comma → separate meanings — and the misparse costs one tap to merge, in front of the
//  learner, rather than being discovered months later in practice.
//
//  Pure: no store, no UIKit. `SenseEntryViewController` shows the proposal and
//  `Lexicon.addSenses(to:terms:)` takes the confirmed result, which already accepts the
//  `[[Term.Draft]]` shape this produces.
//
//  **Entry-time only.** A `Synset` owns its `ReviewEvent` log, so splitting an *existing*
//  meaning would strand its history. Nothing here may be pointed at a stored `Sense`.
//

import Foundation

/// One meaning being entered: the words that will express it, in whichever languages they
/// were typed.
struct SenseEntry: Equatable {

    var terms: [Term.Draft]

    /// The words this meaning would hold in one language, in typed order.
    ///
    /// Matched on the language subtag, the same way `Sense.terms(in:)` matches, so asking
    /// a set that covers "en-US" for its English words finds drafts made in "en".
    func words(in language: String) -> [String] {
        let code = LanguageCode.canonical(language)
        return terms.filter { LanguageCode.canonical($0.language) == code }.map(\.text)
    }

    var isEmpty: Bool { terms.isEmpty }

    /// Whether this meaning already says the same word in the same language — spelling and
    /// canonical subtag, ignoring whatever else a draft happens to carry.
    func holds(_ draft: Term.Draft) -> Bool {
        position(of: draft.text, in: draft.language) != nil
    }

    /// Where a word sits in `terms`, found by spelling and language.
    func position(of text: String, in language: String) -> Int? {
        let code = LanguageCode.canonical(language)
        return terms.firstIndex { $0.text == text && LanguageCode.canonical($0.language) == code }
    }

    /// Where the *n*th word of one language sits in `terms`.
    ///
    /// The screen shows a language's words as its own list, so row 2 of Russian has to mean
    /// the second Russian draft — not "the first draft spelled like that". Two rows can be
    /// spelled the same (nothing stops adding one word twice), and matching by text made
    /// editing or deleting the second silently act on the first.
    func position(ofWordAt index: Int, in language: String) -> Int? {
        let code = LanguageCode.canonical(language)
        var seen = 0
        for (position, term) in terms.enumerated()
        where LanguageCode.canonical(term.language) == code {
            if seen == index { return position }
            seen += 1
        }
        return nil
    }
}

extension SenseEntry {

    /// One side of an entry: the text as typed, and the language it was typed in.
    struct Side: Equatable {
        var text: String
        var language: String

        init(_ text: String, in language: String) {
            self.text = text
            self.language = language
        }
    }

    /// The meanings two typed sides propose.
    ///
    /// **One rule decides the shape:** each side is split on commas, and the side with more
    /// parts says how many meanings there are. A side split into exactly that many parts is
    /// paired in order — two parallel lists are two meanings, not one crowd. Any other side
    /// goes into *every* meaning, which is what makes `bank` the word being defined whether
    /// its meaning is `берег` or `банк`.
    ///
    /// Empty on either side yields nothing: a meaning needs a word on both sides to be
    /// worth proposing, and an empty proposal is the caller's cue to stay where it is.
    static func proposals(_ first: Side, _ second: Side) -> [SenseEntry] {
        let left = words(in: first.text)
        let right = words(in: second.text)
        guard !left.isEmpty, !right.isEmpty else { return [] }

        let count = max(left.count, right.count)
        return (0..<count).map { index in
            SenseEntry(terms:
                share(left, forMeaning: index, of: count).map { Term.Draft($0, in: first.language) }
                + share(right, forMeaning: index, of: count).map { Term.Draft($0, in: second.language) })
        }
    }

    /// Which of a side's words belong to one of the proposed meanings — the whole of the
    /// rule above, in the one place it is applied.
    private static func share(_ side: [String], forMeaning index: Int, of count: Int) -> [String] {
        side.count == count ? [side[index]] : side
    }

    /// Typed text split into the words it names. Empty parts are dropped, so a trailing
    /// comma is a typo rather than a blank word.
    ///
    /// **Deliberately not `PlainText`'s splitter, which looks identical.** There a comma
    /// separates *synonyms* within one line, because `render` writes it that way and a
    /// round trip has to be lossless; here it separates *meanings*, because that is what
    /// the owner asked typing one to do. Two rules that agree on mechanics today and are
    /// free to disagree tomorrow — sharing the code would tie the file format to the
    /// keyboard.
    static func words(in typed: String) -> [String] {
        typed.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Folds a meaning into the one before it: the two become synonyms of a single meaning.
    ///
    /// The merge control the research asked for, as an operation on the proposal rather
    /// than a rearrangement the screen does to itself. Out-of-range or a first-row merge
    /// leaves the proposal alone — there is nothing above row 0 to merge into.
    static func merging(_ proposals: [SenseEntry], at index: Int) -> [SenseEntry] {
        guard proposals.indices.contains(index), index > 0 else { return proposals }
        var merged = proposals
        let absorbed = merged.remove(at: index)
        // Duplicates would become two rows spelled the same inside one meaning, which is
        // what `findOrCreateTerm` prevents everywhere below this. Compared on the canonical
        // subtag, like `words(in:)` — matching the raw tag would let a draft made in "en"
        // and one made in "en-US" both through, which is exactly the pair this drops.
        for term in absorbed.terms where !merged[index - 1].holds(term) {
            merged[index - 1].terms.append(term)
        }
        return merged
    }
}
