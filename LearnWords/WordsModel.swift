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
        LWUserDefaults.standard.maxKnownLevelPreference
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
