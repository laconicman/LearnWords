//
//  UserDefaultsWordStore.swift
//  LearnWords
//
//  The current `WordStore`: word sets and progress in App-Group `UserDefaults` (Codable).
//  Logic moved verbatim from the old static `Storage`; the only changes are that the
//  defaults instance and the save executor are injected, so the store is unit-testable
//  against an ephemeral `UserDefaults(suiteName:)`.
//

import Foundation

final class UserDefaultsWordStore: WordStore {

    private let defaults: UserDefaults
    /// Runs the (potentially slow) encode+write off the caller's thread. Injected so tests
    /// can run it synchronously.
    private let saveExecutor: (@escaping () -> Void) -> Void

    private static let backgroundSaveQueue = DispatchQueue(label: "com.learnwords.wordstore.save", qos: .background)

    private let initialSet = "Initial Sample Set (En->Ru)"
    private let setsKey = "setsKeyForWordsIdentifier"
    private let currentSetKey = "currentSetKeyForWordsIdentifier"

    // In-memory session state (see WordStore).
    var wordsAndStat: [WordAndStat] = []
    var shownWords: [WordAndStat] = []

    init(defaults: UserDefaults = userDefaultsGroup,
         saveExecutor: @escaping (@escaping () -> Void) -> Void = { UserDefaultsWordStore.backgroundSaveQueue.async(execute: $0) }) {
        self.defaults = defaults
        self.saveExecutor = saveExecutor
    }

    var wordSets: [String] {
        get { defaults.stringArray(forKey: setsKey) ?? [initialSet] }
        set { defaults.set(newValue, forKey: setsKey) }
    }

    var currentWordSet: String {
        get { defaults.string(forKey: currentSetKey) ?? initialSet }
        set {
            defaults.set(newValue, forKey: currentSetKey)
            wordsAndStat = getWordSet(name: newValue)
        }
    }

    func saveInitialValues() {
        wordsAndStat.append(WordAndStat(firstWord: "bear", secondWord: "медведь", correct: [:], incorrect: [:], skiped: 0))
        wordsAndStat.append(WordAndStat(firstWord: "camel", secondWord: "верблюд", correct: [:], incorrect: [:], skiped: 0))
        wordsAndStat.append(WordAndStat(firstWord: "run", secondWord: "бегать, бежать", correct: [:], incorrect: [:], skiped: 0))
        wordsAndStat.append(WordAndStat(firstWord: "fox", secondWord: "лиса", correct: [:], incorrect: [:], skiped: 0))
        wordsAndStat.append(WordAndStat(firstWord: "polar bear", secondWord: "полярный медведь", correct: [:], incorrect: [:], skiped: 0))
        wordsAndStat.append(WordAndStat(firstWord: "monkey", secondWord: "обезьяна", correct: [:], incorrect: [:], skiped: 0))
        wordsAndStat.append(WordAndStat(firstWord: "pig", secondWord: "свинья", correct: [:], incorrect: [:], skiped: 0))
        wordsAndStat.append(WordAndStat(firstWord: "rabbit", secondWord: "кролик", correct: [:], incorrect: [:], skiped: 0))
        wordsAndStat.append(WordAndStat(firstWord: "sheep", secondWord: "овца", correct: [:], incorrect: [:], skiped: 0))

        saveWords(wordsAndStat, for: currentWordSet)
    }

    func saveWords(_ words: [WordAndStat], for wordSet: String) {
        saveExecutor { [defaults] in
            defaults.encodeAndSave(words.sorted(by: { $0.firstWord < $1.firstWord }), wordSet)
        }
    }

    func insertFlashcard(foreign: String, native: String) -> Int? {
        // TODO: Check for duplicates before inserting
        guard foreign.count > 0 && native.count > 0 else { return nil }
        let rowPosition = wordsAndStat.count // TODO: change it - sort somehow
        wordsAndStat.append(WordAndStat(firstWord: foreign.canonicalise(), secondWord: native.canonicalise(), correct: [:], incorrect: [:], skiped: 0))
        saveWords(wordsAndStat, for: currentWordSet)
        return rowPosition
    }

    func insertWordSet(name: String) -> Int? {
        var wsa = wordSets
        wsa.append(name)
        let wsaSet = Set(wsa)
        wordSets = Array(wsaSet).sorted()
        saveWords([], for: name)
        currentWordSet = name
        return wordSets.firstIndex(of: name)
    }

    func removeWordSet(at index: Int) {
        let removed = wordSets.remove(at: index)
        if currentWordSet == removed, let wsf = wordSets.first {
            currentWordSet = wsf
        }
        defaults.removeObject(forKey: removed)
    }

    func getWordSet(name: String) -> [WordAndStat] {
        if let savedWords: [WordAndStat] = defaults.decodeAndLoad(name) {
            return savedWords
        } else {
            return []
        }
    }

    func resetAnswerStat(at index: Int) {
        wordsAndStat[index].resetAnswerStat()
    }
}
