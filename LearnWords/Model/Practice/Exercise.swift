//
//  Exercise.swift
//  LearnWords
//
//  The three ways the app asks a question.
//
//  Top-level rather than nested in a session type: an exercise is a stable fact about
//  the app, referenced by the review log, the chooser screen and the practice session
//  alike. Raw values are **persisted data** — they are what `ReviewEvent.task` stores —
//  so they are never renamed.
//

import Foundation

enum Exercise: String, CaseIterable {
    /// Show the word, reveal the answer, let the learner grade themselves.
    case learning = "L"
    /// Type the answer.
    case dictation = "D"
    /// Say the answer.
    case phonetics = "P"
}

extension Exercise {
    /// Which way round this exercise asks by default.
    ///
    /// Typing and speaking are *production*; a flashcard the learner grades is
    /// *recognition* (Nation's split — docs/ProgressResearch.md §1.4). The practice
    /// session records this per answer so the two strands can be scored apart.
    var isProductive: Bool {
        switch self {
        case .learning: return false
        case .dictation, .phonetics: return true
        }
    }
}
