//
//  ReviewOutcome.swift
//  LearnWords
//
//  How an answer was judged — the outcome taxonomy from docs/ProgressModel.md.
//
//  The point is that evidence differs in strength: typing the word exactly is not the
//  same as a matcher deciding you were close enough, which is not the same as tapping
//  "know" after revealing the answer. `ProgressModel` names collapsing these its second
//  hard limit, because the distinction is unrecoverable once discarded — and the screens
//  already *have* it (Dictation's live compare is exact, its submit path runs `match3`).
//
//  Today only `isPositive` is consumed, by the same increase/decrease scoring as before.
//  The taxonomy is here so the exercise screens speak it at the call site; when TD-13
//  lands the `ReviewEvent` log, the information is already flowing and only the sink
//  changes. Raw values are persisted data once that happens — do not rename them.
//

import Foundation

enum ReviewOutcome: String {

    // MARK: Positive

    /// Reproduced exactly. The strongest evidence.
    case correctVerbatim

    /// A judge (today `match3`; later an on-device model) called it close enough.
    /// Between verbatim and self-assessed in weight — owner-confirmed, ProgressModel Q1.
    case correctJudged

    /// The "know" button, tapped after the answer was revealed. Real self-graded
    /// retrieval in the Anki sense, but the weakest positive evidence.
    case selfAssessedKnown

    // MARK: Negative

    /// An answer was given and it was wrong.
    case incorrect

    /// The "forgot" button.
    case selfAssessedForgot

    // MARK: Neutral

    /// Passed over without attempting. Exposure, not retrieval.
    case skipped

    /// Whether this outcome counts toward the word's level under today's scoring.
    ///
    /// Deliberately the *only* thing derived from the taxonomy right now: the weighting
    /// that tells these cases apart belongs to `ScoringPolicy` over the event log, not to
    /// this enum (ProgressModel: weights live in code, recomputed across the whole log).
    var isPositive: Bool {
        switch self {
        case .correctVerbatim, .correctJudged, .selfAssessedKnown:
            return true
        case .incorrect, .selfAssessedForgot, .skipped:
            return false
        }
    }
}

/// Which way the question ran — Nation's receptive/productive split
/// (docs/ProgressResearch.md §1.4). Unrecoverable if not logged, which is why it is
/// written from the first event onward.
///
/// Named for the *skill*, not the languages: with multilingual synsets "foreignToNative"
/// stops meaning anything, and the event's `promptLanguage`/`answerLanguage` snapshots
/// carry the concrete pair. (Naming per owner: primary/secondary, not native/foreign —
/// switching practice direction doesn't switch your native language.)
enum ReviewDirection: String {
    /// The study language was shown; the learner recognised it.
    case receptive
    /// The study language had to be produced — typed or spoken.
    case productive

    init(showsSecondaryAsPrompt: Bool) {
        self = showsSecondaryAsPrompt ? .receptive : .productive
    }
}
