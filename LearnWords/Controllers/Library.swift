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

    private let persistence: LWPersistence

    init(persistence: LWPersistence = .shared,
         defaults: UserDefaults = userDefaultsGroup) {
        self.persistence = persistence
        self.lexicon = Lexicon(persistence: persistence)
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
    ///
    /// **Seeding waits for CloudKit's first import.** A new *device* is not a new *user*:
    /// on the first two-device run both devices found an empty store, both seeded, and the
    /// learner ended up with two "Animals" sets holding the same words. `StoreDeduplicator`
    /// could not repair that — a word set has no natural key, and merging two sets by name
    /// would fuse sets a user deliberately named alike. The fix is not to create the second
    /// one.
    ///
    /// Nothing blocks: the app opens on whatever is already local, and the set appears when
    /// it arrives. That is what syncing is supposed to look like.
    func prepareForLaunch() {
        if selectExistingSet() { return }
        persistence.whenInitialSyncSettled { [weak self] in
            guard let self, !self.selectExistingSet() else { return }
            self.seed()
        }
    }

    /// Points at a set if there is one. `false` means the library is genuinely empty.
    @discardableResult
    private func selectExistingSet() -> Bool {
        guard let first = try? lexicon.wordSets().first else { return false }
        if selectedSet == nil { select(first) }
        return true
    }

    private func seed() {
        do {
            if let seeded = try LexiconSeed.populateIfEmpty(lexicon) {
                select(seeded)
            }
        } catch {
            debugLog("Library could not seed the lexicon: \(error)")
        }
    }
}
