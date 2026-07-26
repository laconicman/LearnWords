//
//  Library.swift
//  LearnWords
//
//  The app's shared controller for "what am I studying right now" — the `Lexicon` plus
//  the set currently selected.
//
//  Which set is selected is **app state, not lexical data**: it belongs to this device
//  and this user's session, not to the vocabulary, so it lives in preferences rather
//  than in the store. Keeping it out of `Lexicon` is what lets the store stay a pure
//  question-and-answer interface over the words.
//
//  A shared instance, matching the app's existing controller pattern (`SpeechManager`,
//  `PermissionManager`). Not because a singleton is ideal — per-screen injection is —
//  but because the screens are still storyboard-instantiated, and proper injection needs
//  the storyboard work in TD-5. The seam is here: every screen asks `Library.shared`, so
//  when TD-5 lands there is one place to inject from.
//

import Foundation

final class Library {

    static let shared = Library()

    let lexicon: Lexicon

    private let defaults: UserDefaults
    private static let selectedSetKey = "selectedWordSetID"

    init(lexicon: Lexicon = Lexicon(), defaults: UserDefaults = userDefaultsGroup) {
        self.lexicon = lexicon
        self.defaults = defaults
    }

    // MARK: - Selection

    /// The set being studied. `nil` only before the first set exists.
    private(set) var selectedSetID: UUID? {
        get { defaults.string(forKey: Self.selectedSetKey).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: Self.selectedSetKey) }
    }

    func select(_ set: WordSet) {
        selectedSetID = set.id
    }

    /// The selected set, re-read so counts are current.
    ///
    /// Falls back to the newest set when the selection is missing or points at something
    /// deleted — on another device, say. A silent, correct recovery beats an empty screen.
    var selectedSet: WordSet? {
        if let id = selectedSetID, let set = try? lexicon.wordSet(id) {
            return set
        }
        guard let fallback = try? lexicon.wordSets().first else { return nil }
        selectedSetID = fallback.id
        return fallback
    }

    /// The meanings in the selected set, in the order they were added.
    func selectedSenses() throws -> [Sense] {
        guard let set = selectedSet else { return [] }
        return try lexicon.senses(in: set.id)
    }

    // MARK: - Launch

    /// Gives a fresh install something to open on. Safe on every launch.
    func prepareForLaunch() {
        do {
            if let seeded = try LexiconSeed.populateIfEmpty(lexicon) {
                select(seeded)
            } else if selectedSet == nil, let first = try lexicon.wordSets().first {
                select(first)
            }
        } catch {
            debugLog("Library could not prepare the lexicon: \(error)")
        }
    }
}
