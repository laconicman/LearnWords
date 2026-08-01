//
//  TermUsage.swift
//  LearnWords
//
//  Where a word is already used — every meaning that holds it, and the sets those live in.
//
//  **One lookup, two jobs**, which is why it is a store query rather than something either
//  screen works out for itself:
//
//  * the add-word screen shows it as a hint while the learner types, so a word they already
//    have is visible *before* they commit to it;
//  * the commit path uses the same answer to refuse a duplicate meaning and offer the
//    choices that make sense instead.
//
//  Deliberately **not scoped to the current set**. A word already learned in "Animals" is
//  worth knowing about while adding it to "Verbs" — arguably more so, since that is the
//  case where the learner has forgotten they have it.
//
//  **The value type lives here; the query lives in `Lexicon`.** It was briefly the other
//  way round, which forced an `internal fetchTerms` returning `[CDTerm]` — managed objects
//  escaping the one type allowed to hold them, past a rule its own header states. Swift's
//  `private` is file-scoped, so an extension in another file cannot reach `viewContext`;
//  the answer is to put the query where the context is, not to widen the context's reach.
//

import Foundation

extension Lexicon {

    /// One meaning that already contains a given word.
    struct TermUsage: Equatable {
        let senseID: UUID
        /// What that meaning says in the other languages it covers — the useful part of the
        /// hint, since the word itself is what the learner just typed.
        let translations: [String]
        /// The sets holding the meaning, in display order. Empty for an orphan.
        let setNames: [String]
        /// A meaning is the *same* meaning when it already reaches the same words.
        func matches(translations others: [String]) -> Bool {
            let mine = Set(translations.map { $0.lowercased() })
            return others.contains { mine.contains($0.lowercased()) }
        }
    }

}
