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
    private(set) var known: Int
    var unknown: Int
    var skiped: Int
    static let maxKnownLevel = 5
    
    // MARK: - Setters
    
    /// Increases the level in 1, with a maximum of 5.
    mutating func increaseKnown() {
        known = min(known + 1, Self.maxKnownLevel)
    }
    
    /// Decreases the level in 1, with a minimum of 0.
    mutating func decreaseKnown() {
        known = max(known - 1, 0)
    }
}
// TODO: Make codable to become capable of storing sets of words in files (Another option - move to CoreData)
struct Storage {
    static var wordsAndStat = [WordAndStat]() // The whole word pair database
    static var shownWords = [WordAndStat]() // Word pair shown during last session
    private static var initialSet = "Initial Sample Set (En->Ru)"
    private static let setsKey = "setsKey"
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
    
    private static let currentSetKey = "currentSetKey"
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
        wordsAndStat.append(WordAndStat(firstWord: "bear", secondWord: "медведь",known: 0,unknown: 0,skiped: 0))
        wordsAndStat.append(WordAndStat(firstWord: "camel", secondWord: "верблюд", known: 0,unknown: 0,skiped: 0))
        wordsAndStat.append(WordAndStat(firstWord: "run", secondWord: "бегать, бежать", known: 0,unknown: 0,skiped: 0))
        wordsAndStat.append(WordAndStat(firstWord: "fox", secondWord: "лиса", known: 0,unknown: 0,skiped: 0))
        wordsAndStat.append(WordAndStat(firstWord: "polar bear", secondWord: "полярный медведь", known: 0,unknown: 0,skiped: 0))
        wordsAndStat.append(WordAndStat(firstWord: "monkey", secondWord: "обезьяна", known: 0,unknown: 0,skiped: 0))
        wordsAndStat.append(WordAndStat(firstWord: "pig", secondWord: "свинья", known: 0,unknown: 0,skiped: 0))
        wordsAndStat.append(WordAndStat(firstWord: "rabbit", secondWord: "кролик", known: 0,unknown: 0,skiped: 0))
        wordsAndStat.append(WordAndStat(firstWord: "sheep", secondWord: "овца", known: 0,unknown: 0,skiped: 0))
        
        saveWords(wordsAndStat)
        // wordSets = [initialSet] Not sure if its needed
    }
    
//    static func saveWordsOnly(_ wordsAndStat: [WordAndStat]) {
//        userDefaultsGroup.set(wordsAndStat.map{$0.pair}, forKey: "Words")
//        //            defaults.set(knownWords, forKey: "knownWords")
//
//    }
    
    static func saveWords(_ wordsAndStat: [WordAndStat], for wordset: String = currentWordSet) {
        userDefaultsGroup.encodeAndSave(wordsAndStat.sorted(by: { $0.firstWord < $1.firstWord }), wordset)
        //            defaults.set(knownWords, forKey: "knownWords")
        
    }
    
    static func insertFlashcard(foreign: String, native: String) ->  Int? {
        // TODO: Check for duplicates before inserting
        guard foreign.count > 0 && native.count > 0 else { return nil}
        let rowPosition = wordsAndStat.count //TODO: change it - sort somehow
        // wordsAndStat.append(("\(first)::\(second)",0,0,0))
        wordsAndStat.append(WordAndStat(firstWord: foreign.canonicalise(), secondWord: native.canonicalise(), known: 0, unknown: 0, skiped: 0))
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
}


