//
//  File.swift
//  LearnWords
//
//  Created by Paul on 15.11.2018.
//  Copyright © 2018 Paul. All rights reserved.
//

import Foundation
import UIKit

private let kRecentSearchesKey = "RecentSearches"
private let kLastSearchKey = "LastSearch"
private let dictionaryPromptDisplayed = "firstUseDictionaryPromptDisplayed"

// TODO: make common settings for app and extensions
// let userDefaultsGroup = UserDefaults(suiteName: "group.club.laconic.LearnWords")
let userDefaultsGroup = LWUserDefaults.standard.userDefaultsGroup
let userDefaults = LWUserDefaults.standard.userDefaults

// Usefull links
// parsing the whole settings bundle stucture:
// https://stackoverflow.com/questions/46453789/swift-4-settings-bundle-get-defaults
// with Decodable:
// https://stackoverflow.com/questions/24045570/how-do-i-get-a-plist-as-a-dictionary-in-swift
// Unfortunatery it is not recommended to write root.plist directly
// register while init, easy get/set wrapper:
// https://forums.developer.apple.com/thread/73266

//Keep in sync with Root.plist in Settings.bundle

final class LWUserDefaults {
    
    static var standard = LWUserDefaults()
    
    func registerDefaultsFromSettingsBundle()
    {
        // This seems to do the same thing as user defaults
//        CFPreferencesSetAppValue("languageToStudyPreference" as CFString, ["a", "b", "c"] as CFArray, kCFPreferencesCurrentApplication)
//        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        let settingsUrl = Bundle.main.url(forResource: "Settings", withExtension: "bundle")!.appendingPathComponent("Root.plist")
        let settingsPlist = NSDictionary(contentsOf:settingsUrl)!
        let preferences = settingsPlist["PreferenceSpecifiers"] as! [NSDictionary]
        
        var defaultsToRegister = Dictionary<String, Any>()
        
        for preference in preferences {
            guard let key = preference["Key"] as? String else {
                debugPrint("Key not found in preferences")
                continue
            }
            defaultsToRegister[key] = preference["DefaultValue"]
            debugPrint(key, " ", preference["DefaultValue"] ?? "Undefined value in preference")
        }
        //userDefaultsGroup.register(defaults: defaultsToRegister) //This is NOT done automatically for the first launch
        userDefaults.register(defaults: defaultsToRegister)

        //userDefaultsGroup?.register(defaults: defaultsToRegister) //This is what you probably want!

    }
    
    private init() {
        // TODO: register only if first launch
        registerDefaultsFromSettingsBundle()
        
        
        // TO_DO: if first launch set native and dictionary langs
        // nativeLanguagePreference = UITextInputMode.activeInputModes.first?.primaryLanguage
        // languageToStudyPreference.UITextInputMode.activeInputModes.filter{ $0.contains("emoji") }.last?.primaryLanguage
    }
    
    let userDefaultsGroup = UserDefaults(suiteName: "group.club.laconic.LearnWords") ?? UserDefaults.standard
    let userDefaults = UserDefaults.standard
    
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
            self.userDefaults.set(newValue, forKey: "pitchMultiplierPreference")
        }
    }
    
    var pronounceAnswersPreference: Bool {
        get {
            return self.userDefaults.bool(forKey: "pronounceAnswersPreference")
        }
        set {
            self.userDefaults.set(newValue, forKey: "pronounceAnswersPreference")
        }
    }
    
    var pronounceQuestionsPreference: Bool {
        get {
            return self.userDefaults.bool(forKey: "pronounceQuestionsPreference")
        }
        set {
            self.userDefaults.set(newValue, forKey: "pronounceQuestionsPreference")
        }
    }
    
    var languageToStudyPreference: String? {
        get {
            return self.userDefaults.string(forKey: "languageToStudyPreference")
        }
        set {
            self.userDefaults.set(newValue, forKey: "languageToStudyPreference")
        }
    }
    
    var nativeLanguagePreference: String? {
        get {
            return self.userDefaults.string(forKey: "nativeLanguagePreference")
        }
        set {
            self.userDefaults.set(newValue, forKey: "nativeLanguagePreference")
        }
    }
    
    var shouldDisplayFirstUseDictionaryPrompt: Bool {
        get {
            !self.userDefaultsGroup.bool(forKey: dictionaryPromptDisplayed)
        }
    }

    func didDisplayFirstUseDictionaryPrompt()
    {
        self.userDefaultsGroup.set(true, forKey: dictionaryPromptDisplayed)
    }
    
//    private let swapLanguageOrderKey = "swapLanguageOrder"
//    var swapLanguageOrder: Bool {
//        get {
//            return self.userDefaults.bool(forKey: swapLanguageOrderKey)
//        }
//        set {
//            self.userDefaults.set(newValue, forKey: swapLanguageOrderKey)
//        }
//    }
    
//    private let currentSetKey = "currentSetKey"
//    var currentWordSet: String? {
//        get {
//            return self.userDefaultsGroup.string(forKey: currentSetKey)
//        }
//        set {
//            self.userDefaultsGroup.set(newValue, forKey: currentSetKey)
//        }
//    }
    
}

func gotoAppSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) { //+ "root=General&path=Network"
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}
