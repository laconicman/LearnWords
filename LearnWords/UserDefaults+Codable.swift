//
//  UserDefaults+Codable.swift
//  LearnWords
//
//  Created by  Paul on 28.05.2021.
//  Copyright © 2021 Paul. All rights reserved.
//
// Not used so far
import Foundation

extension UserDefaults {
    func decodeAndLoad<T: Codable>(_ forKey: String) -> T? {
        
        guard let data = self.data(forKey: forKey) else {
            debugLog("No data for key \(forKey) from UserDefaults.")
            return nil
        }
        
        let decoder = JSONDecoder()
        
        guard  let loaded = try? decoder.decode(T.self, from: data) else {
            debugLog("Failed to decode data for key \(forKey) from UserDefaults.")
            self.removeObject(forKey: forKey) // to overwite with new data format later
            return nil
        }
        return loaded
    }
    func encodeAndSave<T: Codable>(_ codableVar: T, _ forKey: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        if let dataToSave = try? encoder.encode(codableVar) {
            self.set(dataToSave, forKey: forKey) } else {
                debugLog("Failed to save data for key \(forKey).") }
        
    }
}

