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
    
    static func saveInitialValues () {
        wordsAndStat.append(WordAndStat(pair: "медведь::bear",known: 0,unknown: 0,skiped: 0)) // TODO: Change format to somethig like "медведь - bear, bear2"
        wordsAndStat.append(WordAndStat(pair: "верблюд::camel",known: 0,unknown: 0,skiped: 0))
        wordsAndStat.append(WordAndStat(pair: "корова::cow",known: 0,unknown: 0,skiped: 0))
        wordsAndStat.append(WordAndStat(pair: "лиса::fox",known: 0,unknown: 0,skiped: 0))
        wordsAndStat.append(WordAndStat(pair: "коза::goat",known: 0,unknown: 0,skiped: 0))
        wordsAndStat.append(WordAndStat(pair: "обезьяна::monkey",known: 0,unknown: 0,skiped: 0))
        wordsAndStat.append(WordAndStat(pair: "свинья::pig",known: 0,unknown: 0,skiped: 0))
        wordsAndStat.append(WordAndStat(pair: "кролик::rabbit",known: 0,unknown: 0,skiped: 0))
        wordsAndStat.append(WordAndStat(pair: "овца::sheep",known: 0,unknown: 0,skiped: 0))
        
        saveWords(wordsAndStat)
    }
    
//    static func saveWordsOnly(_ wordsAndStat: [WordAndStat]) {
//        userDefaultsGroup.set(wordsAndStat.map{$0.pair}, forKey: "Words")
//        //            defaults.set(knownWords, forKey: "knownWords")
//
//    }
    
    static func saveWords(_ wordsAndStat: [WordAndStat]) {
        userDefaultsGroup.encodeAndSave(wordsAndStat, "WordsAndStat")
        //            defaults.set(knownWords, forKey: "knownWords")
        
    }
    
    static func insertFlashcard(first: String, second: String) ->  Int? {
        guard first.count > 0 && second.count > 0 else { return nil}
        let rowPosition = wordsAndStat.count //TODO: change it - sort somehow
        // wordsAndStat.append(("\(first)::\(second)",0,0,0))
        wordsAndStat.append(WordAndStat(pair: "\(first)::\(second)", known: 0, unknown: 0, skiped: 0))
        saveWords(wordsAndStat)
        return rowPosition
    }
}


