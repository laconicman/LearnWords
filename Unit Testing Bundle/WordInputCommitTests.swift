//
//  WordInputCommitTests.swift
//  Unit Testing Bundle
//
//  Regression for the hole TD-53's back-button fix opened, and a green suite hid.
//
//  `hasCommitted` was set once and never cleared — safe while a committed word screen was
//  always taken *off* the stack by the step that followed it. Now that Back returns to the
//  word step, that screen comes back with Save permanently greyed out: the word cannot be
//  corrected, only abandoned. Caught by driving the simulator, not by the unit tests, which
//  is exactly the trap `docs/TASK-TD53-batch.md` warns about — so it is pinned here.
//
//  **Appearance is driven with `beginAppearanceTransition`, not by a window.** A pushed and
//  popped `UINavigationController` inside the test host does not run its appearance
//  transitions, so a window-based version of this test passes whether or not the fix is
//  there — it never re-appears the screen at all. This is UIKit's own API for delivering
//  those callbacks, and the behaviour it stands in for was checked by hand on iPhone 17 Pro:
//  Back from "Add meaning" returns to "Add word" with the word intact and Save live again.
//

import Testing
import UIKit
@testable import LearnWords

@Suite(.serialized)
@MainActor
struct WordInputCommitTests {

    private func tapSave(_ vc: UIViewController) throws {
        let item = try #require(vc.navigationItem.rightBarButtonItem)
        _ = item.target?.perform(item.action, with: item)
    }

    @Test func aScreenReturnedToCanBeAnsweredAgain() throws {
        var committed: [String] = []
        // What the add-word flow does after step one answers: push step two, which leaves
        // the word screen on the stack rather than replacing it.
        var onward: (() -> Void)?
        let word = WordInputViewController(.add(language: "en"), initialText: "bank") {
            committed.append($0)
            onward?()
        }

        let navigation = UINavigationController(rootViewController: UIViewController())
        let meaning = UIViewController()
        onward = { navigation.pushViewController(meaning, animated: false) }
        navigation.pushViewController(word, animated: false)
        word.loadViewIfNeeded()
        appear(word)

        try tapSave(word)
        #expect(committed == ["bank"], "precondition: the word screen answered once")
        #expect(navigation.topViewController === meaning, "precondition: step two was pushed")

        // Back, the way the owner asked for it: to the word, not out of the flow.
        navigation.popViewController(animated: false)
        #expect(navigation.topViewController === word, "precondition: Back returns to the word")
        appear(word)

        #expect(word.navigationItem.rightBarButtonItem?.isEnabled == true,
                "a screen you can return to must be a screen you can answer")
        try tapSave(word)
        #expect(committed == ["bank", "bank"],
                "the second answer has to reach the flow, or the word can only be abandoned")
    }

    /// Runs the appearance transition UIKit runs when a screen comes back to the top.
    private func appear(_ vc: UIViewController) {
        vc.beginAppearanceTransition(true, animated: false)
        vc.endAppearanceTransition()
    }

    /// Punctuation is not an answer.
    ///
    /// "," passed the old non-empty check, so the screen committed and called back — and
    /// every reader of that callback parses it into no words and stores nothing, which left
    /// the learner bounced back a step with the other half of the entry gone and nothing
    /// said. Refused here, so Save simply does not act, exactly as on an empty field.
    @Test func punctuationAloneIsNotAnAnswer() throws {
        var committed: [String] = []
        for typed in [",", ", ,", "  "] {
            let word = WordInputViewController(.add(language: "en"), initialText: typed) {
                committed.append($0)
            }
            let navigation = UINavigationController(rootViewController: UIViewController())
            navigation.pushViewController(word, animated: false)
            word.loadViewIfNeeded()

            try tapSave(word)

            #expect(committed.isEmpty, "\(typed.debugDescription) must not answer")
            #expect(navigation.topViewController === word,
                    "\(typed.debugDescription) must leave the screen up, not unwind it")
        }
    }

    /// A note is exempt: nothing splits it, and it may be cleared.
    @Test func aNoteMayStillBeCleared() throws {
        var committed: [String] = []
        let note = WordInputViewController(.note, initialText: "") { committed.append($0) }
        note.loadViewIfNeeded()

        try tapSave(note)

        #expect(committed == [""])
    }

    /// The hole the guard was put there to close, which must stay closed: between a commit
    /// and the push that follows it, Return or a second tap must not answer twice.
    @Test func oneAppearanceStillCommitsOnlyOnce() throws {
        var committed: [String] = []
        let word = WordInputViewController(.add(language: "en"), initialText: "bank") {
            committed.append($0)
        }
        let navigation = UINavigationController(rootViewController: UIViewController())
        navigation.pushViewController(word, animated: false)
        word.loadViewIfNeeded()

        try tapSave(word)
        try tapSave(word)

        #expect(committed == ["bank"])
    }
}
