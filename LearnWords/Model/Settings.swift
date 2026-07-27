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

final class LWUserDefaults {

    static let standard = LWUserDefaults()

    /// Single source of truth for preference defaults. Replaces the deleted
    /// Settings.bundle/Root.plist (TD-14): preferences are edited in-app
    /// (`SettingsViewController`) and live in the App-Group suite so the app and its
    /// extensions agree.
    static let defaultPreferences: [String: Any] = [
        "languageToStudyPreference": "en-US",
        "nativeLanguagePreference": "ru-RU",
        "pitchMultiplierPreference": 1.1,
        "utteranceRatePreference": 0.4,
        "pronounceAnswersPreference": true,
        "pronounceQuestionsPreference": true,
        "maxKnownLevelPreference": 20.0,
        // 19:00 — after the working day, before the evening is over. Reminders are off
        // until the learner asks for them; the time only matters once they do.
        "reminderHour": 19.0,
        "reminderMinute": 0.0,
    ]

    private init() {
        migrateStandardPreferencesToGroupIfNeeded()
        // register(defaults:) is non-persistent, so it must run every launch.
        userDefaultsGroup.register(defaults: Self.defaultPreferences)

        // TO_DO: if first launch set native and dictionary langs
        // nativeLanguagePreference = UITextInputMode.activeInputModes.first?.primaryLanguage
        // languageToStudyPreference.UITextInputMode.activeInputModes.filter{ $0.contains("emoji") }.last?.primaryLanguage
    }

    /// Preferences historically lived in per-process *standard* defaults (the system
    /// Settings pane wrote there). One-time copy of values the user had actually set
    /// (the persistent domain excludes registered defaults) into the group suite.
    private func migrateStandardPreferencesToGroupIfNeeded() {
        let migratedKey = "preferencesMigratedToAppGroup"
        guard !userDefaultsGroup.bool(forKey: migratedKey) else { return }
        let domain = userDefaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
        let migratableKeys = Array(Self.defaultPreferences.keys) + [includeLearnedWordsKey, directionOfExersisesKey]
        for key in migratableKeys {
            if let value = domain[key] { userDefaultsGroup.set(value, forKey: key) }
        }
        userDefaultsGroup.set(true, forKey: migratedKey)
    }
    
    let userDefaultsGroup = AppGroup.userDefaults ?? UserDefaults.standard
    let userDefaults = UserDefaults.standard
    
    var utteranceRatePreference: Double {
        get {
            userDefaultsGroup.double(forKey: "utteranceRatePreference")
        }
        set {
            userDefaultsGroup.set(newValue, forKey: "utteranceRatePreference")
        }
    }
    
    var pitchMultiplierPreference: Double {
        get {
            userDefaultsGroup.double(forKey: "pitchMultiplierPreference")
        }
        set {
            userDefaultsGroup.set(newValue, forKey: "pitchMultiplierPreference")
        }
    }
    
    var pronounceAnswersPreference: Bool {
        get {
            userDefaultsGroup.bool(forKey: "pronounceAnswersPreference")
        }
        set {
            userDefaultsGroup.set(newValue, forKey: "pronounceAnswersPreference")
        }
    }
    
    var pronounceQuestionsPreference: Bool {
        get {
            userDefaultsGroup.bool(forKey: "pronounceQuestionsPreference")
        }
        set {
userDefaultsGroup.set(newValue, forKey: "pronounceQuestionsPreference")
        }
    }
    
    var languageToStudyPreference: String? {
        get {
            userDefaultsGroup.string(forKey: "languageToStudyPreference")
        }
        set {
            userDefaultsGroup.set(newValue, forKey: "languageToStudyPreference")
        }
    }
    
    var nativeLanguagePreference: String? {
        get {
            userDefaultsGroup.string(forKey: "nativeLanguagePreference")
        }
        set {
            userDefaultsGroup.set(newValue, forKey: "nativeLanguagePreference")
        }
    }
    
    var maxKnownLevelPreference: Int {
        get {
            Int(userDefaultsGroup.double(forKey: "maxKnownLevelPreference").rounded())
        }
        set {
            userDefaultsGroup.set(Double(newValue), forKey: "maxKnownLevelPreference")
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
            userDefaultsGroup.bool(forKey: includeLearnedWordsKey)
        }
        set {
            userDefaultsGroup.set(newValue, forKey: includeLearnedWordsKey)
        }
    }
    
    /// Whether the learner wants to be reminded. Off until they say otherwise — the
    /// permission sheet is asked for at the switch, not at launch.
    var remindersEnabled: Bool {
        get { userDefaultsGroup.bool(forKey: "remindersEnabled") }
        set { userDefaultsGroup.set(newValue, forKey: "remindersEnabled") }
    }

    var reminderHour: Int {
        get { Int(userDefaultsGroup.double(forKey: "reminderHour").rounded()) }
        set { userDefaultsGroup.set(Double(newValue), forKey: "reminderHour") }
    }

    var reminderMinute: Int {
        get { Int(userDefaultsGroup.double(forKey: "reminderMinute").rounded()) }
        set { userDefaultsGroup.set(Double(newValue), forKey: "reminderMinute") }
    }

    private let directionOfExersisesKey = "directionOfExersises"
    var foreignToNative: Bool {
        get {
            userDefaultsGroup.bool(forKey: directionOfExersisesKey)
        }
        set {
            userDefaultsGroup.set(newValue, forKey: directionOfExersisesKey)
        }
    }
    
//    private let swapLanguageOrderKey = "swapLanguageOrder"
//    var swapLanguageOrder: Bool {
//        get {
//            userDefaultsGroup.bool(forKey: swapLanguageOrderKey)
//        }
//        set {
//            userDefaultsGroup.set(newValue, forKey: swapLanguageOrderKey)
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

