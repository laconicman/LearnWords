//
//  Exercise+Title.swift
//  LearnWords
//
//  What each exercise is called on screen.
//
//  **Deliberately not in `Exercise.swift`.** That file is a model type, and it is compiled
//  into the `Widget` and `WordWidgetExtension` targets as well as the app — its
//  `membershipExceptions` name it. `NSLocalizedString` resolves against `Bundle.main`, which
//  in an extension is the *extension's* bundle, and neither widget bundle carries
//  `Localizable.xcstrings`. A display name put there would silently fall back to its English
//  key in any extension that ever called it.
//
//  This file is in no target's exception list, so the synchronized folder gives it to the app
//  alone. Keeping the lookup out of the shared model layer is the fix; the extension is where
//  wording belongs anyway.
//
//  Lifted out of `ExerciseViewController.make`, which was the only place naming the three,
//  because the per-term statistics screen (TD-50) and the set summary (TD-51) both label
//  per-exercise sections. Two switches would have been two chances to disagree about what
//  "Phonetic" is called. Reported by review, PR #6.
//

import Foundation

extension Exercise {
    var title: String {
        switch self {
        case .learning: return NSLocalizedString("Learning", comment: "Exercise screen title")
        case .dictation: return NSLocalizedString("Dictation", comment: "Exercise screen title")
        case .phonetics: return NSLocalizedString("Phonetic", comment: "Exercise screen title")
        }
    }
}
