//
//  WordsModel.swift
//  LearnWords
//
//  Created by Paul on 09.10.2017.
//  Copyright © 2017 Paul. All rights reserved.
//

import Foundation
import UIKit
struct WordAndStat: Codable {
    var firstWord: String
    var secondWord: String
    var known : Int {
        min(correct.values.reduce(0, +), Self.maxKnownLevel)
    }
    private(set) var correct: [String : Int] = [:]
    private(set) var incorrect: [String : Int] = [:]
    var skiped: Int = 0
    // var lastShown: Date?
    static var maxKnownLevel: Int {
        print(LWUserDefaults.standard.maxKnownLevelPreference)
        return LWUserDefaults.standard.maxKnownLevelPreference
    }
    
    // MARK: - Setters
    // TODO: Refactor naming to `increaseCorrect(for exercise: String)` for example.
    /// Increases the level in 1, with a maximum of 5.
    mutating func increaseCorrect(exercize: String) {
        let currVal = correct[exercize] ?? 0
        correct[exercize] = min(currVal + 1, Self.maxKnownLevel)
    }
    
    /// Decreases the level in 1, with a minimum of 0.
    mutating func decreaseCorrect(exercize: String) {
        let currValCorr = correct[exercize] ?? 0
        correct[exercize] = max(currValCorr - 1, 0)
    }
    
    mutating func resetAnswerStat() {
        correct.removeAll(keepingCapacity: true)
        incorrect.removeAll(keepingCapacity: true)
    }

}
// TODO: Make codable to become capable of storing sets of words in files (Another option - move to CoreData)
struct Storage {
    static var wordsAndStat = [WordAndStat]() // The whole word pair database
    static var shownWords = [WordAndStat]() // Word pair shown during last session
    private static var initialSet = "Initial Sample Set (En->Ru)"
    private static let setsKey = "setsKeyForWordsIdentifier"
    static var wordSets: [String] {
        get {
            return userDefaultsGroup.stringArray(forKey: setsKey) ?? [initialSet]
        }
        set {
            userDefaultsGroup.set(newValue, forKey: setsKey)
//            let nvs = Set(newValue) // newValue = wordSets? WTF
//            if nvs.isStrictSubset(of: wordSets) { // new is less - delete object
//                for ws in nvs.intersection(wordSets) {
//                    userDefaultsGroup.removeObject(forKey: ws)
//                }
//            }
        }
    }
    
    private static let currentSetKey = "currentSetKeyForWordsIdentifier"
    static var currentWordSet: String {
        get {
            return userDefaultsGroup.string(forKey: currentSetKey) ?? initialSet
        }
        set {
            userDefaultsGroup.set(newValue, forKey: currentSetKey)
            Storage.wordsAndStat = getWordSet(name: newValue)
//            if let savedWords: [WordAndStat] = userDefaultsGroup.decodeAndLoad(newValue) {
//                Storage.wordsAndStat = savedWords
//            } else {
//                Storage.wordsAndStat = []
//            }
        }
    }
    
    static func saveInitialValues () {
        wordsAndStat.append(WordAndStat(firstWord: "bear", secondWord: "медведь", correct: [:],incorrect: [:],skiped: 0))
        wordsAndStat.append(WordAndStat(firstWord: "camel", secondWord: "верблюд", correct: [:], incorrect: [:],skiped: 0))
        wordsAndStat.append(WordAndStat(firstWord: "run", secondWord: "бегать, бежать", correct: [:], incorrect: [:], skiped: 0))
        wordsAndStat.append(WordAndStat(firstWord: "fox", secondWord: "лиса", correct: [:], incorrect: [:], skiped: 0))
        wordsAndStat.append(WordAndStat(firstWord: "polar bear", secondWord: "полярный медведь", correct: [:], incorrect: [:], skiped: 0))
        wordsAndStat.append(WordAndStat(firstWord: "monkey", secondWord: "обезьяна", correct: [:], incorrect: [:], skiped: 0))
        wordsAndStat.append(WordAndStat(firstWord: "pig", secondWord: "свинья", correct: [:], incorrect: [:], skiped: 0))
        wordsAndStat.append(WordAndStat(firstWord: "rabbit", secondWord: "кролик", correct: [:], incorrect: [:], skiped: 0))
        wordsAndStat.append(WordAndStat(firstWord: "sheep", secondWord: "овца", correct: [:], incorrect: [:], skiped: 0))
        
        saveWords(wordsAndStat)
        // wordSets = [initialSet] Not sure if its needed
    }
    
//    static func saveWordsOnly(_ wordsAndStat: [WordAndStat]) {
//        userDefaultsGroup.set(wordsAndStat.map{$0.pair}, forKey: "Words")
//        //            defaults.set(knownWords, forKey: "knownWords")
//
//    }
    
    static func saveWords(_ wordsAndStat: [WordAndStat] = Self.wordsAndStat, for wordSet: String = currentWordSet) {
        backgroundSaveQueue.async {
            userDefaultsGroup.encodeAndSave(wordsAndStat.sorted(by: { $0.firstWord < $1.firstWord }), wordSet)
            //            defaults.set(knownWords, forKey: "knownWords")
        }
    }
    
    static func insertFlashcard(foreign: String, native: String) ->  Int? {
        // TODO: Check for duplicates before inserting
        guard foreign.count > 0 && native.count > 0 else { return nil}
        let rowPosition = wordsAndStat.count //TODO: change it - sort somehow
        // wordsAndStat.append(("\(first)::\(second)",0,0,0))
        wordsAndStat.append(WordAndStat(firstWord: foreign.canonicalise(), secondWord: native.canonicalise(), correct: [:], incorrect: [:], skiped: 0))
        saveWords(wordsAndStat)
        return rowPosition
    }
    
    static func insertWordSet(name: String) -> Int? {
        var wsa = wordSets
        wsa.append(name)
        let wsaSet = Set(wsa)
        wordSets = Array(wsaSet).sorted()
        Storage.saveWords([], for: name)
        // TODO:
        Storage.currentWordSet = name
        return wordSets.firstIndex(of: name)
    }
    
    static func removeWordSet(at index: Int) {
        let removed = wordSets.remove(at: index)
        if currentWordSet == removed, let wsf = wordSets.first {
            currentWordSet = wsf
        }
        userDefaultsGroup.removeObject(forKey: removed)
    }
    
    static func getWordSet(name: String) -> [WordAndStat] {
        if let savedWords: [WordAndStat] = userDefaultsGroup.decodeAndLoad(name) {
            return savedWords
        } else {
            return []
        }
    }
    
    static func resetAnswerStat(at index: Int) {
        wordsAndStat[index].resetAnswerStat()
    }
    
    static private let backgroundSaveQueue = DispatchQueue(label: "com.storage.backgroundSaveQueue", qos: .background)
}


