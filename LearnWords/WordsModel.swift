//
//  WordsModel.swift
//  LearnWords
//
//  Created by Paul on 09.10.2017.
//  Copyright © 2017 Paul. All rights reserved.
//

import Foundation
typealias WordAndStat = (pair: String, known: Int, unknow: Int, skiped: Int)
var wordsAndStat = [WordAndStat]() // The whole word pair database
var shownWords = [WordAndStat]() // Word pair shown during last session

let userDefaults = UserDefaults(suiteName: "group.club.laconic.LearnWords")
    //UserDefaults.standard //NSUserDefaults_Log_Nonsensical_Suites (suiteName: Bundle.main.bundleIdentifier)
