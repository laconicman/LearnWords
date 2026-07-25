//
//  LWPersistence.swift
//  LearnWords
//
//  The Core Data stack (TD-13).
//
//  Deliberately **synchronous**. Swift Concurrency back-deploys only to iOS 13, so at this
//  app's 12.1 floor `async`/`await` cannot be used at all — which settles the "does
//  `WordStore` go async" question in docs/TASK-TD13-schema.md: it cannot, while Legacy
//  exists. Reads happen on the view context; writes go through `performAndWait` on a
//  background context so the UI never blocks on disk.
//
//  No migration from `UserDefaults` (owner, 2026-07-20): the model is designed for the new
//  requirements rather than bent to fit the old one, and users re-import their dictionary.
//  See docs/Design.md.
//
//  CloudKit is *not* enabled yet — the model is authored to CloudKit's rules (all
//  attributes optional, every relationship optional with an inverse, no unique
//  constraints) so switching the container type later is a one-line change, not a
//  redesign.
//

import CoreData

final class LWPersistence {

    static let modelName = "LearnWords"

    /// One model instance for the whole process. Loading the same model twice makes Core
    /// Data fail to match entity descriptions ("Failed to find a unique match for an
    /// NSEntityDescription") — the classic test-suite crash.
    static let model: NSManagedObjectModel = {
        guard let url = Bundle(for: LWPersistence.self).url(forResource: modelName, withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url) else {
            fatalError("\(modelName).momd is missing from the bundle")
        }
        return model
    }()

    let container: NSPersistentContainer

    /// The app's store, in the App Group so extensions can read it.
    static let shared = LWPersistence()

    private init() {
        container = NSPersistentContainer(name: Self.modelName, managedObjectModel: Self.model)
        if let url = Self.groupStoreURL {
            container.persistentStoreDescriptions = [NSPersistentStoreDescription(url: url)]
        }
        Self.configure(container)
        startSpotlightIndexing()
    }

    /// A throwaway in-memory stack. Tests use this; it touches no file and no App Group.
    init(inMemory: Bool) {
        container = NSPersistentContainer(name: Self.modelName, managedObjectModel: Self.model)
        if inMemory {
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
        }
        Self.configure(container)
    }

    /// A SQLite stack at an explicit location, outside the App Group.
    ///
    /// For tests that must exercise the *real* store type — indexes, predicates and
    /// persistence-across-launches behave differently in memory, so a suite that only
    /// ever ran in memory would not be testing what ships.
    init(storeAt url: URL) {
        container = NSPersistentContainer(name: Self.modelName, managedObjectModel: Self.model)
        container.persistentStoreDescriptions = [NSPersistentStoreDescription(url: url)]
        Self.configure(container)
    }

    /// Keeps the Spotlight index alive for the lifetime of the stack. Only set for the
    /// on-disk store — Core Spotlight integration requires a SQLite store with history
    /// tracking, so the in-memory test stack never has one.
    private var spotlightIndexer: NSCoreDataCoreSpotlightDelegate?

    private static func configure(_ container: NSPersistentContainer) {
        container.persistentStoreDescriptions.forEach {
            // Required by both CloudKit and Core Spotlight indexing.
            $0.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            // Remote-change notifications are iOS 13+, as is NSPersistentCloudKitContainer
            // itself — so on iOS 12 this store is simply local. That is the correct
            // degradation: Legacy keeps working, sync is a modern-OS feature.
            if #available(iOS 13.0, *) {
                $0.setOption(true as NSNumber,
                             forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            }
        }
        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Failed to load the LearnWords store: \(error)")
            }
        }
        container.viewContext.name = "viewContext"
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    /// Publishes words to Spotlight, so a learner searching their phone for a word they
    /// half-remember lands in the app.
    ///
    /// Core Data does the indexing itself from the attributes marked "Index in Spotlight"
    /// in the model; the delegate only has to exist and be started. It reads the
    /// persistent-history stream, which is why history tracking is switched on above —
    /// and why this is confined to the SQLite store (the only kind it supports).
    private func startSpotlightIndexing() {
        guard let description = container.persistentStoreDescriptions.first,
              description.type == NSSQLiteStoreType else { return }

        // `init(forStoreWith:coordinator:)` is iOS 15+; below that the delegate exists
        // but takes the model. iOS 12–14 therefore simply has no Spotlight entries —
        // the same graceful degradation as the widgets and sync (TD-11 tier).
        guard #available(iOS 15.0, *) else { return }
        let indexer = NSCoreDataCoreSpotlightDelegate(
            forStoreWith: description, coordinator: container.persistentStoreCoordinator)
        indexer.startSpotlightIndexing()
        spotlightIndexer = indexer
    }

    /// Where the app and its extensions share one store.
    private static var groupStoreURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
            .appendingPathComponent("\(modelName).sqlite")
    }

    // MARK: - Access

    /// The context the UI reads from. Main queue only.
    var viewContext: NSManagedObjectContext { container.viewContext }

    /// Runs `work` on a private-queue context and saves if it made changes.
    ///
    /// Synchronous by necessity (see the note at the top) — `performAndWait` is the
    /// pre-concurrency way to stay on the right queue, and it is what lets the existing
    /// synchronous `WordStore` call sites keep working unchanged.
    func write(_ work: (NSManagedObjectContext) throws -> Void) throws {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        var thrown: Error?
        context.performAndWait {
            do {
                try work(context)
                if context.hasChanges {
                    try context.save()
                }
            } catch {
                thrown = error
                context.rollback()
            }
        }
        if let thrown { throw thrown }
    }
}
