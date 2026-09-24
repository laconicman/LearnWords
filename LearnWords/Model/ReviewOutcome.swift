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

    /// Correct, but the learner heard the answer first (the Listen button). Cued recall —
    /// real evidence, weaker than free retrieval; ProgressModel's rule is that a path like
    /// this is a distinct outcome, not a silent downgrade of another one.
    case correctAided

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
        case .correctVerbatim, .correctJudged, .correctAided, .selfAssessedKnown:
            return true
        case .incorrect, .selfAssessedForgot, .skipped:
            return false
        }
    }
}

/// What kind of row this is. The log holds more than answers.
///
/// Anki's `revlog.type` and swift-fsrs' `Rating.manual` are the same idea, and both
/// establish the rule this app follows: a manual "reset progress" is **appended as a
/// non-answer row**, never a deletion of what came before. Replay then treats the marker
/// as a truncation point — everything earlier is ignored — while the pre-reset rows stay
/// in the log as the record of work actually done.
///
/// It is a separate axis from `ReviewOutcome` on purpose: a reset carries no grade, and
/// putting it in the outcome taxonomy would make every `isPositive` switch answer a
/// question about something that was never answered.
/// (Verified against open-spaced-repetition/swift-fsrs and ankitects/anki, 2026-07-26.)
enum ReviewEventKind: String {
    /// A question was asked and graded. Every field of the row is meaningful.
    case answer
    /// The learner declared a fresh start on this meaning. Carries no outcome, no
    /// exercise and no prompt — there was no question.
    case progressReset
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
