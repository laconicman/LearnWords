//
//  File.swift
//  LearnWords
//
//  Created by Paul on 15.11.2018.
//  Copyright © 2018 Paul. All rights reserved.
//

import Foundation

let kRecentSearchesKey = "RecentSearches"
let kLastSearchKey = "LastSearch"

let userDefaultsGroup = UserDefaults(suiteName: "group.club.laconic.LearnWords")
//let userDefaults: UserDefaults? = LWUserDefaults.standard.userDefaults

// Usefull links
// parsing the whole settings bundle stucture:
// https://stackoverflow.com/questions/46453789/swift-4-settings-bundle-get-defaults
// with Decodable:
//https://stackoverflow.com/questions/24045570/how-do-i-get-a-plist-as-a-dictionary-in-swift
// Unfortunatery it is not recommended to write root.plist directly
// register while init, easy get/set wrapper:
// https://forums.developer.apple.com/thread/73266

//Make use of it in future
/*
class LWUserDefaults {
    
    static var standard = LWUserDefaults()
    
    func registerDefaultsFromSettingsBundle()
    {
        let settingsUrl = Bundle.main.url(forResource: "Settings", withExtension: "bundle")!.appendingPathComponent("Root.plist")
        let settingsPlist = NSDictionary(contentsOf:settingsUrl)!
        let preferences = settingsPlist["PreferenceSpecifiers"] as! [NSDictionary]
        
        var defaultsToRegister = Dictionary<String, Any>()
        
        for preference in preferences {
            guard let key = preference["Key"] as? String else {
                print("Key not fount")
                continue
            }
            defaultsToRegister[key] = preference["DefaultValue"]
            debugPrint(key, " ", preference["DefaultValue"])
        }
        //userDefaults.register(defaults: defaultsToRegister) //This is done automatically for standart
        userDefaultsGroup.register(defaults: defaultsToRegister) //This is what you probably want!

    }
    
    private init() {
        let urlData = NSKeyedArchiver.archivedData(withRootObject: URL(string: "https://www.google.co.uk")!)
       //self.userDefaults.register(defaults: ["SearchEngine": urlData, "WJW": 10])
        registerDefaultsFromSettingsBundle()
        
    }
    
    let userDefaultsGroup = UserDefaults(suiteName: "group.club.laconic.LearnWords")
    let userDefaults = UserDefaults.standard
    
    var searchEngine: URL? {
        get {
            return self.userDefaults.url(forKey: "SearchEngine")
        }
        set {
            self.userDefaults.set(newValue, forKey: "SearchEngine")
        }
    }
    var utteranceRatePreference: Double {
        get {
            return self.userDefaults.double(forKey: "utteranceRatePreference")
        }
        set {
            self.userDefaults.set(newValue, forKey: "utteranceRatePreference")
        }
    }
    
    var pitchMultiplierPreference: Double {
        get {
            return self.userDefaults.double(forKey: "pitchMultiplierPreference")
        }
        set {
            self.userDefaults.set(newValue, forKey: "pitchMultiplierPreferencee")
        }
    }
}
*/
