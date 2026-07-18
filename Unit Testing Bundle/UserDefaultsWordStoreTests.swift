//
//  UserDefaultsWordStoreTests.swift
//  Unit Testing Bundle
//
//  Tests the concrete WordStore against an ephemeral UserDefaults suite with a synchronous
//  save executor — no shared/global state, so cases are deterministic and parallel-safe.
//

import Testing
import Foundation
@testable import LearnWords

struct UserDefaultsWordStoreTests {

    /// A store backed by a throwaway UserDefaults suite that saves synchronously.
    private func makeStore() throws -> UserDefaultsWordStore {
        let suiteName = "test.wordstore.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return UserDefaultsWordStore(defaults: defaults, saveExecutor: { $0() })
    }

    private func word(_ first: String, _ second: String) -> WordAndStat {
        WordAndStat(firstWord: first, secondWord: second, correct: [:], incorrect: [:], skiped: 0)
    }

    @Test func freshStoreHasOneDefaultWordSet() throws {
        let store = try makeStore()
        #expect(store.wordSets.count == 1)
        #expect(store.currentWordSet == store.wordSets.first)
    }

    @Test func insertFlashcardRejectsEmptyInput() throws {
        let store = try makeStore()
        #expect(store.insertFlashcard(foreign: "", native: "x") == nil)
        #expect(store.insertFlashcard(foreign: "x", native: "") == nil)
        #expect(store.wordsAndStat.isEmpty)
    }

    @Test func insertFlashcardCanonicalisesAndAppends() throws {
        let store = try makeStore()
        let index = store.insertFlashcard(foreign: "  Bear ", native: " Медведь ")
        #expect(index == 0)
        #expect(store.wordsAndStat.count == 1)
        #expect(store.wordsAndStat.first?.firstWord == "bear")     // lowercased + trimmed
        #expect(store.wordsAndStat.first?.secondWord == "медведь")
    }

    @Test func insertWordSetAddsAndSwitchesCurrent() throws {
        let store = try makeStore()
        _ = store.insertWordSet(name: "Zebra Set")
        #expect(store.wordSets.contains("Zebra Set"))
        #expect(store.currentWordSet == "Zebra Set")
    }

    @Test func removeWordSetDropsItAndReassignsCurrent() throws {
        let store = try makeStore()
        let original = store.currentWordSet
        _ = store.insertWordSet(name: "B Set")          // becomes current
        let index = try #require(store.wordSets.firstIndex(of: "B Set"))
        store.removeWordSet(at: index)
        #expect(!store.wordSets.contains("B Set"))
        #expect(store.currentWordSet == original)        // fell back to the remaining set
    }

    @Test func saveThenGetWordSetRoundTrips() throws {
        let store = try makeStore()
        store.saveWords([word("bear", "медведь"), word("ant", "муравей")], for: "Animals")
        let loaded = store.getWordSet(name: "Animals")
        #expect(loaded.map(\.firstWord) == ["ant", "bear"])   // persisted sorted by firstWord
    }

    @Test func getWordSetReturnsEmptyForUnknownSet() throws {
        let store = try makeStore()
        #expect(store.getWordSet(name: "does-not-exist").isEmpty)
    }

    @Test func settingCurrentWordSetLoadsItsWords() throws {
        let store = try makeStore()
        store.saveWords([word("cat", "кот")], for: "Pets")
        store.currentWordSet = "Pets"
        #expect(store.wordsAndStat.map(\.firstWord) == ["cat"])
    }
}
