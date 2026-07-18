//
//  WordStore.swift
//  LearnWords
//
//  The app's persistence seam. `Storage` (the static facade) forwards to a `WordStore`;
//  today that's `UserDefaultsWordStore`. This is the interface a future
//  Core Data / NSPersistentCloudKitContainer store will conform to, so switching the
//  backing store (and adding cross-device sync) is a new conformer + a one-line swap of
//  `Storage.backend`, not an app-wide change. See docs/Design.md and docs/TechDebt.md (TD-12).
//

import Foundation

/// Everything the app needs from persistence. Reference type: `wordsAndStat` / `shownWords`
/// are shared session state, so all call sites must see one instance.
protocol WordStore: AnyObject {
    /// The current set's word/stat pairs, held in memory for the session.
    var wordsAndStat: [WordAndStat] { get set }
    /// Word pairs shown during the last session.
    var shownWords: [WordAndStat] { get set }
    /// The names of all word sets (persisted).
    var wordSets: [String] { get set }
    /// The active word set's name (persisted); setting it loads that set into `wordsAndStat`.
    var currentWordSet: String { get set }

    func saveInitialValues()
    func saveWords(_ words: [WordAndStat], for wordSet: String)
    func insertFlashcard(foreign: String, native: String) -> Int?
    func insertWordSet(name: String) -> Int?
    func removeWordSet(at index: Int)
    func getWordSet(name: String) -> [WordAndStat]
    func resetAnswerStat(at index: Int)
}
