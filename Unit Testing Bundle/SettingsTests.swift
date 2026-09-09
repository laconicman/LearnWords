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

    @Test func screenHasLanguagesSpeechStudyAndReminderSections() {
        let prefs = LWUserDefaults.standard
        let saved = prefs.remindersEnabled
        defer { prefs.remindersEnabled = saved }
        prefs.remindersEnabled = false

        let vc = SettingsViewController()
        vc.loadViewIfNeeded()
        let table = vc.tableView!
        #expect(vc.numberOfSections(in: table) == 4)
        #expect(vc.tableView(table, numberOfRowsInSection: 0) == 2)  // languages
        #expect(vc.tableView(table, numberOfRowsInSection: 1) == 4)  // pitch, rate, 2 toggles
        #expect(vc.tableView(table, numberOfRowsInSection: 2) == 2)  // horizon, successful days
        #expect(vc.tableView(table, numberOfRowsInSection: 3) == 2)  // switch + time
    }

    /// The row count must not depend on the preference.
    ///
    /// It used to: the time row was added and removed as reminders were switched on and
    /// off, while the same cell *instances* were handed back each time. UIKit was left
    /// holding a hidden cell with no index path — "Unable to obtain index path for
    /// accessory: <UISwitch…>" on a real device. The row is disabled now, not removed.
    @Test func theReminderSectionKeepsBothRowsWhicheverWayTheSwitchIsSet() {
        let prefs = LWUserDefaults.standard
        let saved = prefs.remindersEnabled
        defer { prefs.remindersEnabled = saved }

        let vc = SettingsViewController()
        vc.loadViewIfNeeded()
        let table = vc.tableView!

        prefs.remindersEnabled = true
        #expect(vc.tableView(table, numberOfRowsInSection: 3) == 2)
        prefs.remindersEnabled = false
        #expect(vc.tableView(table, numberOfRowsInSection: 3) == 2)
    }

    @Test func languageNameResolvesCodesAndFallsBack() {
        #expect(SettingsViewController.languageName(for: "ru-RU") == "Russian")
        #expect(SettingsViewController.languageName(for: "xx-XX") == "xx-XX")
        #expect(SettingsViewController.languageName(for: nil) == "")
    }
}
