//
//  StoreDeduplicator.swift
//  LearnWords
//
//  Merges the duplicate rows that CloudKit sync inevitably creates.
//
//  **Why this has to exist.** Four entities are found-or-created by a natural key —
//  `Language.code`, `Tag.name`, `ErrorTag.name`, and `Term` by (text, language). Uniqueness
//  is enforced in `Lexicon`, in code, because **CloudKit forbids unique constraints**
//  (docs/Design.md). That works within one store. It cannot work across two: a phone and an
//  iPad both offline, each adding "bear", each correctly finding no existing row, produce two
//  `Term` rows that meet for the first time after the merge. Nothing prevents it, so
//  something has to repair it.
//
//  Left unrepaired the damage is not cosmetic: `terms(in: "en")` would return the words
//  attached to *one* of the two `en` rows, so half a set's vocabulary would silently vanish
//  from practice.
//
//  **The winner must be chosen identically on every device.** If the phone merges into row A
//  while the iPad merges into row B, each deletes the row the other kept, both deletions
//  sync, and the language disappears along with every word pointing at it. That is why the
//  lookup entities carry a `UUID` they otherwise have no use for: `objectID` is device-local
//  under CloudKit and cannot order anything. Lowest `id` wins, everywhere, always.
//
//  **Order matters.** `Language` is deduplicated before `Term`, because a term's natural key
//  includes its language — comparing against un-merged language rows would classify two
//  identical words as distinct.
//
//  Runs on a private-queue context off the remote-change notification, never on the view
//  context, and is safe to run when there is nothing to do (the common case).
//

import CoreData

enum StoreDeduplicator {

    /// One entity's merge rule: how to fetch it, and what makes two rows the same row.
    private struct Rule {
        let entityName: String
        /// Sort keys that group duplicates together and put the winner first. The last key
        /// is always `id`, so the winner is deterministic across devices.
        let sortKeys: [String]
        /// The natural key, as text. Rows sharing it are the same thing.
        let key: (NSManagedObject) -> String?
    }

    private static let rules: [Rule] = [
        // Language first: Term's key depends on it.
        Rule(entityName: "Language", sortKeys: ["code", "id"]) {
            ($0 as? CDLanguage).map { $0.code.lowercased() }
        },
        Rule(entityName: "Tag", sortKeys: ["name", "id"]) {
            ($0 as? CDTag).map { $0.name.lowercased() }
        },
        Rule(entityName: "ErrorTag", sortKeys: ["name", "id"]) {
            ($0 as? CDErrorTag).map { $0.name.lowercased() }
        },
        Rule(entityName: "Term", sortKeys: ["text", "id"]) { object in
            guard let term = object as? CDTerm else { return nil }
            // Matches `Lexicon.findOrCreateTerm`: case-insensitive text, within a language.
            return "\(term.text.lowercased())\u{1F}\(term.language?.code.lowercased() ?? "")"
        },
    ]

    /// Collapses every duplicate in the store, and reports how many rows it removed.
    ///
    /// Synchronous and self-contained: it opens its own background context, so a caller on
    /// any queue is safe and nothing it touches escapes.
    @discardableResult
    static func run(in container: NSPersistentContainer) throws -> Int {
        var removed = 0
        var thrown: Error?
        let context = container.newBackgroundContext()
        // Ours is the authoritative copy of a merge; last write wins on conflict.
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.performAndWait {
            do {
                for rule in rules {
                    removed += try merge(rule, in: context)
                }
                if context.hasChanges { try context.save() }
            } catch {
                thrown = error
                context.rollback()
            }
        }
        if let thrown { throw thrown }
        return removed
    }

    /// Folds every group of same-key rows into its lowest-`id` member.
    private static func merge(_ rule: Rule, in context: NSManagedObjectContext) throws -> Int {
        let request = NSFetchRequest<NSManagedObject>(entityName: rule.entityName)
        request.sortDescriptors = rule.sortKeys.map {
            NSSortDescriptor(key: $0, ascending: true)
        }
        let rows = try context.fetch(request)

        var winners: [String: NSManagedObject] = [:]
        var losers: [(loser: NSManagedObject, winner: NSManagedObject)] = []
        for row in rows {
            guard let key = rule.key(row) else { continue }
            if let winner = winners[key] {
                losers.append((row, winner))
            } else {
                winners[key] = row      // first in sort order — lowest id for this key
            }
        }

        for (loser, winner) in losers {
            adopt(loser, into: winner)
            context.delete(loser)
        }
        return losers.count
    }

    /// Moves everything pointing at `loser` onto `winner`, so deleting the loser costs
    /// nothing.
    ///
    /// Driven by the entity description rather than written out per entity: a relationship
    /// added later is carried automatically, and there is no fifth hand-written merge to
    /// forget to update.
    private static func adopt(_ loser: NSManagedObject, into winner: NSManagedObject) {
        for (name, relationship) in loser.entity.relationshipsByName {
            if relationship.isToMany {
                guard let related = loser.value(forKey: name) as? Set<NSManagedObject>,
                      !related.isEmpty else { continue }
                // Core Data maintains the inverse, so re-pointing this side is enough.
                winner.mutableSetValue(forKey: name).union(related)
                loser.mutableSetValue(forKey: name).removeAllObjects()
            } else if winner.value(forKey: name) == nil {
                // Only if the winner has nothing there: a loser must never overwrite a
                // value the surviving row already holds.
                winner.setValue(loser.value(forKey: name), forKey: name)
            }
        }
    }
}
