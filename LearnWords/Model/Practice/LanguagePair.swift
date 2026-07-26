//
//  LanguagePair.swift
//  LearnWords
//
//  The two languages one sitting runs in, and which side is being asked.
//
//  **Primary / secondary, not native / foreign** (owner): switching practice direction
//  doesn't switch your native language. And once a word set covers more than two
//  languages, the *session* decides which pair to practise — the set ranks nothing, so
//  this type is the place the choice is made concrete.
//
//  A plain value: `PracticeSession` holds one for its whole run, so a settings change
//  mid-sitting cannot split a question from its answer.
//

import Foundation

struct LanguagePair: Hashable {

    /// The learner's reference language — usually, but not necessarily, their native one.
    let primary: String

    /// The language being studied this sitting.
    let secondary: String

    /// Whether the study language is the *cue*.
    ///
    /// `true` is recognition (see the word, recall the meaning); `false` is production
    /// (see the meaning, produce the word). `ReviewDirection` records the skill per event.
    let showsSecondaryAsPrompt: Bool

    init(primary: String, secondary: String, showsSecondaryAsPrompt: Bool) {
        self.primary = primary
        self.secondary = secondary
        self.showsSecondaryAsPrompt = showsSecondaryAsPrompt
    }

    /// The pair the user has chosen in settings.
    ///
    /// The preference *keys* keep their historic names — they are persisted data — while
    /// the code vocabulary moved on.
    static var current: LanguagePair {
        let defaults = LWUserDefaults.standard
        return LanguagePair(primary: defaults.nativeLanguagePreference ?? "en",
                            secondary: defaults.languageToStudyPreference ?? "en",
                            showsSecondaryAsPrompt: defaults.foreignToNative)
    }

    /// The pair to practise a given set in, honouring the user's choice where the set
    /// covers it and falling back to the set's own languages where it does not — a set
    /// of German words is practised in German even if settings still say Spanish.
    static func forSet(_ set: WordSet) -> LanguagePair {
        let chosen = current
        guard set.languages.count >= 2,
              !set.languages.contains(chosen.secondary) || !set.languages.contains(chosen.primary)
        else { return chosen }

        // Keep whichever side the set does cover; take the other from the set.
        let secondary = set.languages.contains(chosen.secondary)
            ? chosen.secondary
            : (set.languages.first { $0 != chosen.primary } ?? chosen.secondary)
        let primary = set.languages.contains(chosen.primary)
            ? chosen.primary
            : (set.languages.first { $0 != secondary } ?? chosen.primary)
        return LanguagePair(primary: primary, secondary: secondary,
                            showsSecondaryAsPrompt: chosen.showsSecondaryAsPrompt)
    }

    /// The language a question is asked in.
    var promptLanguage: String { showsSecondaryAsPrompt ? secondary : primary }

    /// The language the answer is expected in.
    var answerLanguage: String { showsSecondaryAsPrompt ? primary : secondary }

    /// The same pair, asked the other way round.
    var reversed: LanguagePair {
        LanguagePair(primary: primary, secondary: secondary,
                     showsSecondaryAsPrompt: !showsSecondaryAsPrompt)
    }
}
