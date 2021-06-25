//
//  WordsModel.swift
//  LearnWords
//
//  Created by Paul on 09.10.2017.
//  Copyright © 2017 Paul. All rights reserved.
//

import Foundation
struct WordAndStat: Codable {
    var pair: String
    private(set) var known: Int
    var unknown: Int
    var skiped: Int
    
    // MARK: - Setters

    /// Increases the level in 1, with a maximum of 5.
    mutating func increaseKnown() {
        known = min(known + 1, 5)
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
    private static var initialSet = "WordsAndStat"
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
            if let savedWords: [WordAndStat] = userDefaultsGroup.decodeAndLoad(newValue) {
                    Storage.wordsAndStat = savedWords
                } else {
                    Storage.wordsAndStat = []
                }
        }
    }
    
    static func saveInitialValues () {
        wordsAndStat.append(WordAndStat(pair: "bear::медведь",known: 0,unknown: 0,skiped: 0)) // TODO: Change format to somethig like "медведь - bear, bear2"
        wordsAndStat.append(WordAndStat(pair: "camel::верблюд", known: 0,unknown: 0,skiped: 0))
        wordsAndStat.append(WordAndStat(pair: "cow::корова", known: 0,unknown: 0,skiped: 0))
        wordsAndStat.append(WordAndStat(pair: "fox::лиса", known: 0,unknown: 0,skiped: 0))
        wordsAndStat.append(WordAndStat(pair: "goat::коза", known: 0,unknown: 0,skiped: 0))
        wordsAndStat.append(WordAndStat(pair: "monkey::обезьяна", known: 0,unknown: 0,skiped: 0))
        wordsAndStat.append(WordAndStat(pair: "pig::свинья", known: 0,unknown: 0,skiped: 0))
        wordsAndStat.append(WordAndStat(pair: "rabbit::кролик", known: 0,unknown: 0,skiped: 0))
        wordsAndStat.append(WordAndStat(pair: "sheep::овца", known: 0,unknown: 0,skiped: 0))
        
        saveWords(wordsAndStat)
        // wordSets = [initialSet] Not sure if its needed
    }
    
//    static func saveWordsOnly(_ wordsAndStat: [WordAndStat]) {
//        userDefaultsGroup.set(wordsAndStat.map{$0.pair}, forKey: "Words")
//        //            defaults.set(knownWords, forKey: "knownWords")
//
//    }
    
    static func saveWords(_ wordsAndStat: [WordAndStat]) {
        userDefaultsGroup.encodeAndSave(wordsAndStat, currentWordSet)
        //            defaults.set(knownWords, forKey: "knownWords")
        
    }
    
    static func insertFlashcard(foreign: String, native: String) ->  Int? {
        // TODO: Check for duplicates before inserting
        guard foreign.count > 0 && native.count > 0 else { return nil}
        let rowPosition = wordsAndStat.count //TODO: change it - sort somehow
        // wordsAndStat.append(("\(first)::\(second)",0,0,0))
        wordsAndStat.append(WordAndStat(pair: "\(foreign)::\(native)".lowercased(), known: 0, unknown: 0, skiped: 0))
        saveWords(wordsAndStat)
        return rowPosition
    }
    
    static func insertWordSet(name: String) -> Int? {
        var wsa = wordSets
        wsa.append(name)
        let wsaSet = Set(wsa)
        wordSets = Array(wsaSet).sorted()
        return wordSets.index(of: name)
    }
    static func removeWordSet(at index: Int) {
        let removed = wordSets.remove(at: index)
        if currentWordSet == removed, let wsf = wordSets.first {
            currentWordSet = wsf
        }
        userDefaultsGroup.removeObject(forKey: removed)
    }
}


