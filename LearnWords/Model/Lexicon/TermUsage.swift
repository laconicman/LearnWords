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

import CoreData

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

    /// Every meaning that already holds `text` in `language`, across every set.
    ///
    /// Matches the way the store stores words: case-insensitively, on the canonical
    /// language subtag, so "Bear" typed against an `en-US` preference finds the `en` row.
    func usages(ofTerm text: String, in language: String) throws -> [TermUsage] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let request = CDTerm.fetchRequest()
        request.predicate = NSPredicate(format: "text ==[c] %@", trimmed)
        let code = LanguageCode.canonical(language)

        let matching: [CDTerm] = try fetchTerms(request).filter {
            LanguageCode.canonical($0.language?.code ?? "") == code
        }

        var usages: [TermUsage] = []
        for term in matching {
            for synset in term.synsets {
                let others: [CDTerm] = synset.terms.filter {
                    LanguageCode.canonical($0.language?.code ?? "") != code
                }
                let names: [String] = synset.sets.map { $0.name }
                usages.append(TermUsage(senseID: synset.id,
                                        translations: others.map { $0.text }.sorted(),
                                        setNames: names.sorted()))
            }
        }
        return usages
    }
}
