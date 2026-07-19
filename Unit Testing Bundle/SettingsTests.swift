//
//  SettingsTests.swift
//  Unit Testing Bundle
//
//  Covers the Settings.bundle replacement (TD-14): code-registered defaults in the
//  App-Group suite, and the in-app settings screen's structure.
//

import Testing
import UIKit
@testable import LearnWords

struct LWUserDefaultsTests {

    @Test func preferenceDefaultsAreRegisteredInGroupSuite() {
        // Touching .standard runs migration + registration; every default must resolve.
        let prefs = LWUserDefaults.standard
        #expect(prefs.languageToStudyPreference != nil)
        #expect(prefs.nativeLanguagePreference != nil)
        #expect(prefs.utteranceRatePreference > 0)
        #expect(prefs.pitchMultiplierPreference > 0)
        #expect(prefs.maxKnownLevelPreference > 0)
        for key in LWUserDefaults.defaultPreferences.keys {
            #expect(userDefaultsGroup.object(forKey: key) != nil, "unregistered key: \(key)")
        }
    }
}

@MainActor
struct SettingsViewControllerTests {

    @Test func screenHasLanguagesSpeechAndStudySections() {
        let vc = SettingsViewController()
        vc.loadViewIfNeeded()
        let table = vc.tableView!
        #expect(vc.numberOfSections(in: table) == 3)
        #expect(vc.tableView(table, numberOfRowsInSection: 0) == 2)  // languages
        #expect(vc.tableView(table, numberOfRowsInSection: 1) == 4)  // pitch, rate, 2 toggles
        #expect(vc.tableView(table, numberOfRowsInSection: 2) == 1)  // known level
    }

    @Test func languageNameResolvesCodesAndFallsBack() {
        #expect(SettingsViewController.languageName(for: "ru-RU") == "Russian")
        #expect(SettingsViewController.languageName(for: "xx-XX") == "xx-XX")
        #expect(SettingsViewController.languageName(for: nil) == "")
    }
}
