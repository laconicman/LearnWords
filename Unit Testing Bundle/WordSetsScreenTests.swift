//
//  WordSetsScreenTests.swift
//  Unit Testing Bundle
//
//  Wiring checks for the sets screen — the parts a compile check cannot see.
//

import Testing
import UIKit
@testable import LearnWords

@MainActor
struct WordSetsScreenTests {

    private func freshLibrary() -> Library {
        Library(persistence: LWPersistence(inMemory: true),
                defaults: UserDefaults(suiteName: "WordSetsScreenTests-\(UUID())")!)
    }

    /// The screen in a window, so `present` has somewhere to go. The storyboard normally
    /// registers the row prototype; built in code, the table needs one or dequeueing traps.
    private func onScreen(_ vc: WordSetsTableViewController) -> UIWindow {
        vc.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "wordSetsCell")
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = vc
        window.makeKeyAndVisible()
        return window
    }

    private func saveFailureAlert(on vc: UIViewController) -> UIAlertController? {
        let alert = vc.presentedViewController as? UIAlertController
        return alert?.title == NSLocalizedString("SAVE_FAIL_TITLE", comment: "") ? alert : nil
    }

    // The store failure that actually reaches a `catch`: the set is gone by the time the
    // tap lands — deleted on another device, say — and the write throws
    // `LexiconError.notFound`. (A store that has physically vanished raises an
    // Objective-C exception from `save()` that no Swift `catch` can see; that case cannot
    // be reported by anyone, so it is not what these pin.)

    @Test func aRefusedDeleteIsReportedAndTheListResyncs() async throws {
        let library = freshLibrary()
        let set = try library.lexicon.addWordSet(named: "Birds")
        let vc = WordSetsTableViewController(style: .plain)
        vc.library = library
        let window = onScreen(vc)
        defer { window.isHidden = true }
        try await waitUntil { vc.tableView.numberOfRows(inSection: 0) == 1 }

        try library.lexicon.deleteWordSet(set.id)        // gone underneath the snapshot
        vc.deleteSet(at: IndexPath(row: 0, section: 0))

        try await waitUntil { vc.presentedViewController != nil }
        let alert = saveFailureAlert(on: vc)
        #expect(alert != nil, "a write the store refused must say so")
        #expect(alert?.message == NSLocalizedString("LEXICON_NOT_FOUND", comment: ""),
                "the alert carries the store's account, not a generic failure")
        #expect(vc.tableView.numberOfRows(inSection: 0) == 0,
                "the list shows what the store holds, not what the tap assumed")
    }

    @Test func aRefusedRenameIsReported() async throws {
        let library = freshLibrary()
        let set = try library.lexicon.addWordSet(named: "Birds")
        let vc = WordSetsTableViewController(style: .plain)
        vc.library = library
        let window = onScreen(vc)
        defer { window.isHidden = true }
        try await waitUntil { vc.tableView.numberOfRows(inSection: 0) == 1 }

        try library.lexicon.deleteWordSet(set.id)
        vc.renameSet(set, to: "Waterfowl")

        try await waitUntil { vc.presentedViewController != nil }
        #expect(saveFailureAlert(on: vc) != nil)
    }

    @Test func aCleanAddSaysNothing() async throws {
        let vc = WordSetsTableViewController(style: .plain)
        vc.library = freshLibrary()
        let window = onScreen(vc)
        defer { window.isHidden = true }

        vc.addSet(named: "Birds")

        try await waitUntil { vc.tableView.numberOfRows(inSection: 0) == 1 }
        #expect(vc.tableView.numberOfRows(inSection: 0) == 1)
        #expect(vc.presentedViewController == nil, "the list growing is the confirmation")
    }

    @Test func aCleanDeleteRemovesTheRow() async throws {
        let library = freshLibrary()
        try library.lexicon.addWordSet(named: "Birds")
        let vc = WordSetsTableViewController(style: .plain)
        vc.library = library
        let window = onScreen(vc)
        defer { window.isHidden = true }
        try await waitUntil { vc.tableView.numberOfRows(inSection: 0) == 1 }

        vc.deleteSet(at: IndexPath(row: 0, section: 0))

        try await waitUntil { vc.tableView.numberOfRows(inSection: 0) == 0 }
        #expect(vc.tableView.numberOfRows(inSection: 0) == 0)
        #expect(vc.presentedViewController == nil)
    }

    // The picker must be built on the non-deprecated initializer with the view
    // controller as its delegate. Presenting it is a device concern: a test host
    // has no document-browser service and aborts where a real app would not.
    @Test func importButtonBuildsAConfiguredPicker() {
        let vc = WordSetsTableViewController(style: .plain)

        let picker = vc.makeImportPicker()

        #expect(picker.delegate === vc)
        #expect(!picker.allowsMultipleSelection)
    }
}
