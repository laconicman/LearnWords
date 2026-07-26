//
//  LWPersistence.swift
//  LearnWords
//
//  The Core Data stack (TD-13).
//
//  Deliberately **synchronous**. Swift Concurrency back-deploys only to iOS 13, so at this
//  app's 12.1 floor `async`/`await` cannot be used at all — which settles the "does the
//  store go async" question in docs/TASK-TD13-schema.md: it cannot, while Legacy exists.
//  Reads happen on the view context; writes go through `performAndWait` on a background
//  context so the UI never blocks on disk.
//
//  No migration from `UserDefaults` (owner, 2026-07-20): the model is designed for the new
//  requirements rather than bent to fit the old one, and users re-import their dictionary.
//  See docs/Design.md.
//
//  **CloudKit (iOS 13+, host app only).** The model was authored to CloudKit's rules from
//  the start — every attribute optional *or* defaulted, every relationship optional with an
//  inverse, no unique constraints — so enabling mirroring is a container swap rather than a
//  redesign. iOS 12 keeps a purely local store, which is the correct degradation and not a
//  bug: Legacy keeps working, sync is a modern-OS feature.
//
//  The **extensions do not sync**. A widget reads what the app has already pulled down;
//  giving an extension its own mirroring engine would have it compete with the app for the
//  same store to no purpose.
//
//  Mirroring introduces the one problem uniqueness-in-code cannot solve on its own —
//  duplicate rows created independently on two devices — which `StoreDeduplicator` repairs.
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

    /// Whether this store mirrors to CloudKit. `false` in extensions and below iOS 13.
    private(set) var isSyncing = false

    /// The app's store, in the App Group so extensions can read it.
    static let shared = LWPersistence()

    /// The iCloud container backing the private database.
    ///
    /// Derived from the bundle identifier by Apple's own convention, so it stays correct
    /// for the extensions (whose bundle IDs differ) without a second constant to keep in
    /// step with `AppGroup.identifier`.
    static let cloudKitContainerIdentifier = "iCloud.club.laconic.LearnWords"

    private init() {
        // A store that will not open is fatal; a store that will not *sync* is not. So
        // CloudKit is attempted, and a failure falls back to the same local store the app
        // has always used rather than refusing to launch. A provisioning mistake should
        // cost the user sync, not their vocabulary.
        if Self.shouldSync, #available(iOS 13.0, *) {
            let cloud = NSPersistentCloudKitContainer(name: Self.modelName,
                                                      managedObjectModel: Self.model)
            cloud.persistentStoreDescriptions = [Self.cloudKitDescription()]
            do {
                try Self.load(cloud)
                container = cloud
                isSyncing = true
                Self.finishConfiguring(container)
                startSpotlightIndexing()
                observeRemoteChanges()
                return
            } catch {
                // Logged in full rather than swallowed: "no iCloud container in this
                // environment" and "the model is not CloudKit-compatible" both land here
                // and mean very different things.
                debugLog("CloudKit store failed to open, falling back to a local store: \(error)")
            }
        }

        container = NSPersistentContainer(name: Self.modelName, managedObjectModel: Self.model)
        container.persistentStoreDescriptions = [Self.localDescription()]
        Self.configure(container)
        startSpotlightIndexing()
    }

    /// Sync belongs to the host app. `.appex` is how a bundle says it is an extension.
    private static var shouldSync: Bool {
        !Bundle.main.bundlePath.hasSuffix(".appex")
    }

    private static func localDescription() -> NSPersistentStoreDescription {
        groupStoreURL.map(NSPersistentStoreDescription.init(url:))
            ?? NSPersistentStoreDescription()
    }

    @available(iOS 13.0, *)
    private static func cloudKitDescription() -> NSPersistentStoreDescription {
        let description = localDescription()
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: cloudKitContainerIdentifier)
        return description
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

    // MARK: - Repairing what sync duplicates

    private var remoteChangeObserver: NSObjectProtocol?
    private let dedupQueue = DispatchQueue(label: "club.laconic.LearnWords.dedup")
    private var pendingDedup: DispatchWorkItem?

    deinit {
        if let remoteChangeObserver {
            NotificationCenter.default.removeObserver(remoteChangeObserver)
        }
    }

    /// Repairs duplicate rows after each batch of changes arriving from another device.
    ///
    /// Uniqueness is enforced in `Lexicon`, in code, because CloudKit forbids constraints.
    /// That holds within one store and cannot hold across two, so the repair has to happen
    /// after the merge — see `StoreDeduplicator`.
    @available(iOS 13.0, *)
    private func observeRemoteChanges() {
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: nil
        ) { [weak self] _ in
            self?.deduplicateSoon()
        }
    }

    /// Coalesces a burst of incoming changes into one merge.
    ///
    /// An initial sync posts many notifications in quick succession; merging after each
    /// would re-scan the store for nothing. Deduplication is idempotent, so the only cost
    /// of waiting is a couple of seconds during which a duplicate may be visible.
    private func deduplicateSoon() {
        dedupQueue.async { [weak self] in
            guard let self else { return }
            self.pendingDedup?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                do {
                    let removed = try StoreDeduplicator.run(in: self.container)
                    if removed > 0 { debugLog("Merged \(removed) duplicate rows after sync.") }
                } catch {
                    debugLog("Deduplication failed: \(error)")
                }
            }
            self.pendingDedup = work
            self.dedupQueue.asyncAfter(deadline: .now() + 2, execute: work)
        }
    }

    /// Keeps the Spotlight index alive for the lifetime of the stack. Only set for the
    /// on-disk store — Core Spotlight integration requires a SQLite store with history
    /// tracking, so the in-memory test stack never has one.
    private var spotlightIndexer: NSCoreDataCoreSpotlightDelegate?

    private static func configure(_ container: NSPersistentContainer) {
        prepare(container)
        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Failed to load the LearnWords store: \(error)")
            }
        }
        finishConfiguring(container)
    }

    /// Loads the stores, throwing rather than trapping — the CloudKit path needs to be
    /// able to fail and retry locally.
    private static func load(_ container: NSPersistentContainer) throws {
        prepare(container)
        var thrown: Error?
        container.loadPersistentStores { _, error in thrown = error }
        if let thrown { throw thrown }
    }

    private static func prepare(_ container: NSPersistentContainer) {
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
    }

    private static func finishConfiguring(_ container: NSPersistentContainer) {
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
    /// pre-concurrency way to stay on the right queue, and what lets every call site read
    /// and write without an `await` the 12.1 floor cannot express.
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
