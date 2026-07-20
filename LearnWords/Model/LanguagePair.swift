//
//  LanguagePair.swift
//  LearnWords
//
//  The two languages a round is practised in, and which way round it is being asked.
//
//  **Direction of travel (owner, 2026-07-20): a language pair belongs to a word set, not
//  to the app.** Today it is two global preferences, and the evidence that this is wrong
//  is already in the data — the default set is named `"Initial Sample Set (En->Ru)"`,
//  encoding the pair in a *display string* because the model has nowhere to put it. Two
//  sets with different pairs cannot both be right under one global setting, and
//  `ProgressModel`'s per-event `direction` (receptive vs productive) is only meaningful
//  relative to a pair — so a global one silently reinterprets past events when the user
//  switches sets.
//
//  This type is the seam, not the fix. `current` resolves from the global preferences for
//  now; when TD-13 gives a word set real identity and its own languages, that resolution
//  changes here and nowhere else. Building a `WordSet` entity on `UserDefaults` first is
//  exactly what `ProgressModel` warns against — don't polish a layer Core Data replaces.
//

import Foundation

struct LanguagePair {

    /// The learner's own language.
    let native: String

    /// The language being studied.
    let foreign: String

    /// Which side is being shown as the cue.
    ///
    /// `true` means the foreign word is the prompt and the native word is the answer —
    /// recognition. `false` is production. This is `ProgressModel`'s `direction`, and it
    /// is why the pair has to travel with it.
    let showsForeignAsPrompt: Bool

    /// Today's resolution: the app-wide preferences. The single place TD-13 repoints at
    /// the current word set.
    static var current: LanguagePair {
        let defaults = LWUserDefaults.standard
        return LanguagePair(native: defaults.nativeLanguagePreference ?? "en",
                            foreign: defaults.languageToStudyPreference ?? "en",
                            showsForeignAsPrompt: defaults.foreignToNative)
    }

    // MARK: - Reading a word

    /// The cue text for `word` — what the learner is shown.
    func prompt(for word: WordAndStat) -> String {
        showsForeignAsPrompt ? word.firstWord : word.secondWord
    }

    /// The expected answer for `word` — what the learner must produce or recognise.
    func answer(for word: WordAndStat) -> String {
        showsForeignAsPrompt ? word.secondWord : word.firstWord
    }

    /// The language the cue is spoken in.
    var promptLanguage: String { showsForeignAsPrompt ? foreign : native }

    /// The language the answer is spoken in.
    var answerLanguage: String { showsForeignAsPrompt ? native : foreign }
}
