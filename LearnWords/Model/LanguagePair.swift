//
//  LanguagePair.swift
//  LearnWords
//
//  The two languages a practice round runs in, and which side is being asked.
//
//  **Primary / secondary, not native / foreign** (owner, 2026-07-23): switching practice
//  direction doesn't switch your native language, and once a word set covers more than
//  two languages the session — not the data — decides which language plays which role.
//  A round is always a pair, drawn at practice time from the set's `languageCodes`;
//  the set itself ranks nothing.
//
//  This type remains the seam from the pair-preferences era: `current` still resolves
//  from the app-wide settings while the exercise screens run on `UserDefaultsWordStore`.
//  When the Core Data store lands, the session builds a `LanguagePair` from the chosen
//  set languages instead — same type, different construction site.
//

import Foundation

struct LanguagePair {

    /// The learner's own reference language (usually their native one).
    let primary: String

    /// The language being studied this round.
    let secondary: String

    /// Whether the secondary (study) language is the cue.
    ///
    /// `true` is receptive practice — recognise the study language; `false` is
    /// productive — produce it. `ReviewDirection` records exactly this per event.
    let showsSecondaryAsPrompt: Bool

    /// Today's resolution: the app-wide preferences. (The preference *keys* keep their
    /// historical names — they are persisted data; only the code vocabulary changed.)
    static var current: LanguagePair {
        let defaults = LWUserDefaults.standard
        return LanguagePair(primary: defaults.nativeLanguagePreference ?? "en",
                            secondary: defaults.languageToStudyPreference ?? "en",
                            showsSecondaryAsPrompt: defaults.foreignToNative)
    }

    /// The direction of a question asked this round, in ProgressModel terms.
    var direction: ReviewDirection {
        ReviewDirection(showsSecondaryAsPrompt: showsSecondaryAsPrompt)
    }

    // MARK: - Reading a word

    /// The cue text for `word` — what the learner is shown.
    /// (`WordAndStat.firstWord` is the study-language side in the legacy model.)
    func prompt(for word: WordAndStat) -> String {
        showsSecondaryAsPrompt ? word.firstWord : word.secondWord
    }

    /// The expected answer for `word` — what the learner must produce or recognise.
    func answer(for word: WordAndStat) -> String {
        showsSecondaryAsPrompt ? word.secondWord : word.firstWord
    }

    /// The language the cue is spoken in.
    var promptLanguage: String { showsSecondaryAsPrompt ? secondary : primary }

    /// The language the answer is spoken in.
    var answerLanguage: String { showsSecondaryAsPrompt ? primary : secondary }
}
