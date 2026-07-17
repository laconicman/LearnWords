//
//  Settings.swift
//  LearnWords
//
//  Created by Paul on 15.11.2018.
//  Copyright © 2018 Paul. All rights reserved.
//

import Foundation

private let kRecentSearchesKey = "RecentSearches"
private let kLastSearchKey = "LastSearch"
private let dictionaryPromptDisplayed = "firstUseDictionaryPromptDisplayed"

// TODO: make common settings for app and extensions
let userDefaultsGroup = LWUserDefaults.standard.userDefaultsGroup
let userDefaults = LWUserDefaults.standard.userDefaults

// Useful links
// parsing the whole settings bundle structure:
// https://stackoverflow.com/questions/46453789/swift-4-settings-bundle-get-defaults
// with Decodable:
// https://stackoverflow.com/questions/24045570/how-do-i-get-a-plist-as-a-dictionary-in-swift
// Unfortunately it is not recommended to write root.plist directly
// register while init, easy get/set wrapper:
// https://forums.developer.apple.com/thread/73266

//Keep in sync with Root.plist in Settings.bundle

final class LWUserDefaults {
    
    static let standard = LWUserDefaults()
    
    func registerDefaultsFromSettingsBundle() {
        // This seems to do the same thing as user defaults
//        CFPreferencesSetAppValue("languageToStudyPreference" as CFString, ["a", "b", "c"] as CFArray, kCFPreferencesCurrentApplication)
//        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        let settingsUrl = Bundle.main.url(forResource: "Settings", withExtension: "bundle")!.appendingPathComponent("Root.plist")
        let settingsPlist = NSDictionary(contentsOf:settingsUrl)!
        let preferences = settingsPlist["PreferenceSpecifiers"] as! [NSDictionary]
        
        var defaultsToRegister = Dictionary<String, Any>()
        
        for preference in preferences {
            guard let key = preference["Key"] as? String else {
                debugLog("Key not found in preferences \(preference)")
                continue
            }
            defaultsToRegister[key] = preference["DefaultValue"]
            debugLog(key + " " + preference["DefaultValue"].debugDescription)
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
    
    let userDefaultsGroup = AppGroup.userDefaults ?? UserDefaults.standard
    let userDefaults = UserDefaults.standard
    
    var utteranceRatePreference: Double {
        get {
            userDefaults.double(forKey: "utteranceRatePreference")
        }
        set {
            userDefaults.set(newValue, forKey: "utteranceRatePreference")
        }
    }
    
    var pitchMultiplierPreference: Double {
        get {
            userDefaults.double(forKey: "pitchMultiplierPreference")
        }
        set {
            userDefaults.set(newValue, forKey: "pitchMultiplierPreference")
        }
    }
    
    var pronounceAnswersPreference: Bool {
        get {
            userDefaults.bool(forKey: "pronounceAnswersPreference")
        }
        set {
            userDefaults.set(newValue, forKey: "pronounceAnswersPreference")
        }
    }
    
    var pronounceQuestionsPreference: Bool {
        get {
            userDefaults.bool(forKey: "pronounceQuestionsPreference")
        }
        set {
userDefaults.set(newValue, forKey: "pronounceQuestionsPreference")
        }
    }
    
    var languageToStudyPreference: String? {
        get {
            userDefaults.string(forKey: "languageToStudyPreference")
        }
        set {
            userDefaults.set(newValue, forKey: "languageToStudyPreference")
        }
    }
    
    var nativeLanguagePreference: String? {
        get {
            userDefaults.string(forKey: "nativeLanguagePreference")
        }
        set {
            userDefaults.set(newValue, forKey: "nativeLanguagePreference")
        }
    }
    
    var maxKnownLevelPreference: Int {
        get {
            Int(userDefaults.double(forKey: "maxKnownLevelPreference").rounded())
        }
        set {
            userDefaults.set(Double(newValue), forKey: "maxKnownLevelPreference")
        }
    }
    
    var shouldDisplayFirstUseDictionaryPrompt: Bool {
        get {
            !userDefaultsGroup.bool(forKey: dictionaryPromptDisplayed)
        }
    }

    func didDisplayFirstUseDictionaryPrompt()
    {
        userDefaultsGroup.set(true, forKey: dictionaryPromptDisplayed)
    }
    
    private let includeLearnedWordsKey = "includeLearnedWords"
    var includeLearnedWords: Bool {
        get {
            userDefaults.bool(forKey: includeLearnedWordsKey)
        }
        set {
            userDefaults.set(newValue, forKey: includeLearnedWordsKey)
        }
    }
    
    private let directionOfExersisesKey = "directionOfExersises"
    var foreignToNative: Bool {
        get {
            userDefaults.bool(forKey: directionOfExersisesKey)
        }
        set {
            userDefaults.set(newValue, forKey: directionOfExersisesKey)
        }
    }
    
//    private let swapLanguageOrderKey = "swapLanguageOrder"
//    var swapLanguageOrder: Bool {
//        get {
//            userDefaults.bool(forKey: swapLanguageOrderKey)
//        }
//        set {
//            userDefaults.set(newValue, forKey: swapLanguageOrderKey)
//        }
//    }
    
//    private let currentSetKey = "currentSetKey"
//    var currentWordSet: String? {
//        get {
//            return userDefaultsGroup.string(forKey: currentSetKey)
//        }
//        set {
//            userDefaultsGroup.set(newValue, forKey: currentSetKey)
//        }
//    }
    
}

