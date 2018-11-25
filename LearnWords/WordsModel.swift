//
//  WordsModel.swift
//  LearnWords
//
//  Created by Paul on 09.10.2017.
//  Copyright © 2017 Paul. All rights reserved.
//

import Foundation
typealias WordAndStat = (pair: String, known: Int, unknow: Int, skiped: Int)
struct Storage {
    static var wordsAndStat = [WordAndStat]() // The whole word pair database
    static var shownWords = [WordAndStat]() // Word pair shown during last session
    
    static func saveInitialValues () {
        wordsAndStat.append(("медведь::bear",0,0,0))
        wordsAndStat.append(("верблюд::camel",0,0,0))
        wordsAndStat.append(("корова::cow",0,0,0))
        wordsAndStat.append(("лиса::fox",0,0,0))
        wordsAndStat.append(("коза::goat",0,0,0))
        wordsAndStat.append(("обезьяна::monkey",0,0,0))
        wordsAndStat.append(("свинья::pig",0,0,0))
        wordsAndStat.append(("кролик::rabbit",0,0,0))
        wordsAndStat.append(("овца::sheep",0,0,0))
        
        saveWordsOnly(wordsAndStat)
    }
    
    static func saveWordsOnly(_ wordsAndStat: [WordAndStat]) {
        userDefaultsGroup?.set(wordsAndStat.map{$0.pair}, forKey: "Words")
        //            defaults.set(knownWords, forKey: "knownWords")
        
    }
    
    static func insertFlashcard(first: String, second: String) ->  Int? {
        guard first.count > 0 && second.count > 0 else { return nil}
        let rowPosition = wordsAndStat.count //TODO: change it - sort somehow
        wordsAndStat.append(("\(first)::\(second)",0,0,0))
        saveWordsOnly(wordsAndStat)
        return rowPosition
    }
}


