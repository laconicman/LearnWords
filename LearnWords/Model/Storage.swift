//
//  Storage.swift
//  LearnWords
//
//  Created by Paul Buktab on 9/21/25.
//  Copyright © 2025 Paul. All rights reserved.
//
//  Thin static facade over an injectable `WordStore` (`backend`). Call sites keep using
//  `Storage.…`; swap `Storage.backend` to change the backing store (tests inject an
//  ephemeral `UserDefaultsWordStore`; a future Core Data / CloudKit store swaps here too).
//  See docs/TechDebt.md (TD-12).
//

import Foundation

enum Storage {

    /// The backing store. Injection point: replace in tests or at the composition root.
    static var backend: WordStore = UserDefaultsWordStore()

    static var wordsAndStat: [WordAndStat] {
        get { backend.wordsAndStat }
        set { backend.wordsAndStat = newValue }
    }

    static var wordSets: [String] {
        get { backend.wordSets }
        set { backend.wordSets = newValue }
    }

    static var currentWordSet: String {
        get { backend.currentWordSet }
        set { backend.currentWordSet = newValue }
    }

    static func saveInitialValues() { backend.saveInitialValues() }

    static func saveWords(_ words: [WordAndStat] = wordsAndStat, for wordSet: String = currentWordSet) {
        backend.saveWords(words, for: wordSet)
    }

    static func insertFlashcard(foreign: String, native: String) -> Int? {
        backend.insertFlashcard(foreign: foreign, native: native)
    }

    static func insertWordSet(name: String) -> Int? {
        backend.insertWordSet(name: name)
    }

    static func removeWordSet(at index: Int) { backend.removeWordSet(at: index) }

    static func getWordSet(name: String) -> [WordAndStat] { backend.getWordSet(name: name) }

    static func resetAnswerStat(at index: Int) { backend.resetAnswerStat(at: index) }
}
