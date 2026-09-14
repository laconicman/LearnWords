//
//  LWPersistence.swift
//  LearnWords
//
//  The Core Data stack (TD-13).
//
//  Deliberately **synchronous**. Swift Concurrency back-deploys only to iOS 13, so at the
//  12.1 floor this was written for `async`/`await` could not be used at all — which settled
//  the "does the store go async" question in docs/TASK-TD13-schema.md. At 15 the question is
//  open again, as TD-56; docs/Design.md § "a write is visible to the next read" says what an
//  asynchronous store would have to keep.
//  Reads happen on the view context; writes go through `performAndWait` on a background
//  context so the UI never blocks on disk.
//
//  No migration from `UserDefaults` (owner, 2026-07-20): the model is designed for the new
//  requirements rather than bent to fit the old one, and users re-import their dictionary.
//  See docs/Design.md.
//
//  **CloudKit (host app only).** Every attribute must be optional *or* have a
//  runtime default, every relationship optional with an inverse, and no unique constraints.
//  The model was believed to satisfy that from the start; it did not — every UUID was
//  non-optional with a `defaultValueString` Core Data ignores, and the store refused to
//  open. `PersistenceSchemaTests.modelObeysCloudKitRules` now runs the rule verbatim, with
//  no exemptions, because an exemption is a hole with a comment in it.
//
//  A device whose iCloud container is missing or unprovisioned keeps a purely local store,
//  which is the correct degradation and not a bug — see docs/CloudKitSetup.md for the
//  account-side steps, which no amount of code can substitute for.
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

    /// Whether this store mirrors to CloudKit. `false` in extensions, and when the CloudKit
    /// store failed to open.
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
        if Self.shouldSync {
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
                Self.initializeCloudKitSchemaIfRequested(cloud)
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

    /// Uploads the record types the model implies, so the CloudKit schema exists.
    ///
    /// CloudKit will not accept records of a type it has never heard of, and the types are
    /// not created by syncing — they are created by this call, which writes one temporary
    /// instance of each and deletes it again. Until it runs against the Development
    /// environment, a fresh container has no schema and sync does nothing.
    ///
    /// **Deliberate, not automatic.** DEBUG-only *and* behind a launch argument, for two
    /// reasons: it is slow and uploads on every launch it runs, and it must never touch
    /// Production, where record types are immutable once deployed. Run it from Xcode with
    /// `-LWInitializeCloudKitSchema 1` in the scheme's arguments after any model change,
    /// then deploy the schema in the CloudKit Console. See docs/CloudKitSetup.md.
    private static func initializeCloudKitSchemaIfRequested(_ container: NSPersistentCloudKitContainer) {
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: "LWInitializeCloudKitSchema") else { return }
        do {
            try container.initializeCloudKitSchema(options: [])
            debugLog("CloudKit schema initialized. Deploy it to Production in the CloudKit Console.")
        } catch {
            debugLog("CloudKit schema initialization failed: \(error)")
        }
        #endif
    }

    /// Calls `settled` once CloudKit has had its first chance to deliver existing data —
    /// or straight away when there is no sync to wait for.
    ///
    /// **Why anything has to wait.** A second device installs the app, finds an empty
    /// store, and seeds — and a minute later the first device's word set arrives on top.
    /// The learner ends up with two "Animals" sets holding the same words, which is
    /// exactly what happened on the first two-device run. Seeding is a decision about a
    /// *new user*; a new *device* is not one.
    ///
    /// The signal is `NSPersistentCloudKitContainer.eventChangedNotification`, which
    /// reports when an import finishes. The timeout is not a fallback for slow networks but
    /// for the cases where that event never comes at all — no iCloud account, airplane
    /// mode — where waiting forever would leave a genuinely new user staring at an empty app.
    func whenInitialSyncSettled(_ settled: @escaping () -> Void) {
        guard isSyncing else { return DispatchQueue.main.async(execute: settled) }

        var hasRun = false
        let runOnce = { [weak self] in
            guard !hasRun else { return }
            hasRun = true
            if let token = self?.importObserver {
                NotificationCenter.default.removeObserver(token)
                self?.importObserver = nil
            }
            settled()
        }

        importObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container, queue: .main
        ) { note in
            let key = NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            guard let event = note.userInfo?[key]
                    as? NSPersistentCloudKitContainer.Event,
                  event.type == .import, event.endDate != nil else { return }
            runOnce()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.initialSyncTimeout, execute: runOnce)
    }

    /// Long enough for a first import over a slow connection, short enough that a user
    /// with no iCloud account is not left looking at nothing.
    private static let initialSyncTimeout: TimeInterval = 8

    private var importObserver: NSObjectProtocol?

    /// Sync belongs to the host app. `.appex` is how a bundle says it is an extension.
    private static var shouldSync: Bool {
        !Bundle.main.bundlePath.hasSuffix(".appex")
    }

    private static func localDescription() -> NSPersistentStoreDescription {
        groupStoreURL.map(NSPersistentStoreDescription.init(url:))
            ?? NSPersistentStoreDescription()
    }

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
        if let importObserver {
            NotificationCenter.default.removeObserver(importObserver)
        }
    }

    /// Posted on the main queue after changes from another device have landed **and been
    /// deduplicated** — the point at which the store is worth re-reading.
    ///
    /// Screens need this because they hold snapshots, not live results: `Lexicon` returns
    /// value types by design, so nothing tells a table its array is stale. Before this
    /// existed, a word added on one device reached the other's *store* but not its
    /// *screen* until the tab was left and re-entered, which looks exactly like sync being
    /// broken.
    ///
    /// Posted after deduplication rather than on the raw store notification, so the UI
    /// never renders the duplicate rows that are about to be merged away.
    static let storeDidChangeRemotely = Notification.Name("LWPersistenceStoreDidChangeRemotely")

    /// Posted whenever the library changed, **whichever device changed it**.
    ///
    /// `storeDidChangeRemotely` fires only for another device's edits, which made anything
    /// reacting to it subtly wrong: adding a word here is the same event as receiving one
    /// from an iPad, and a schedule that rebuilds for the second and not the first is
    /// rebuilt from stale data half the time. Local saves post this too.
    ///
    /// Screens that redraw on a *remote* change deliberately keep using the narrower
    /// notification — they already reload after their own edits, and reloading twice is
    /// visible.
    static let storeDidChange = Notification.Name("LWPersistenceStoreDidChange")

    /// Repairs duplicate rows after each batch of changes arriving from another device.
    ///
    /// Uniqueness is enforced in `Lexicon`, in code, because CloudKit forbids constraints.
    /// That holds within one store and cannot hold across two, so the repair has to happen
    /// after the merge — see `StoreDeduplicator`.
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
                // Whether or not anything was merged, the store changed — that is what the
                // screens are waiting to hear.
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Self.storeDidChangeRemotely, object: self)
                    NotificationCenter.default.post(name: Self.storeDidChange, object: self)
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
            $0.setOption(true as NSNumber,
                         forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
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
    /// Synchronous (see the note at the top) — `performAndWait` is the pre-concurrency way
    /// to stay on the right queue, and what lets every call site read and write without an
    /// `await`.
    func write(_ work: (NSManagedObjectContext) throws -> Void) throws {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Captured here and merged below, **synchronously**, so that when this method
        // returns the view context already sees the change.
        //
        // `automaticallyMergesChangesFromParent` alone is not enough: it merges when the
        // did-save notification is delivered, which for a main-queue view context means
        // the next turn of the run loop. A caller that writes and immediately re-reads —
        // every editor screen does, and so does every test — got the *stale* values back,
        // because a fetch returns already-registered objects without refreshing them
        // (`shouldRefreshRefetchedObjects` is false by default). Setting an attribute
        // twice in a row appeared to do nothing the second time.
        //
        // Merged after `performAndWait` returns rather than inside the notification, which
        // fires on the background queue: hopping to the main queue from there while the
        // main thread is blocked waiting on that same `performAndWait` would deadlock.
        var saved: Notification?
        let token = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave, object: context, queue: nil) { saved = $0 }
        defer { NotificationCenter.default.removeObserver(token) }

        var thrown: Error?
        context.performAndWait {
            do {
                try work(context)
                if context.hasChanges {
                    try context.save()
                    // A local edit is the same event as one arriving from another device:
                    // the library changed. Anything derived from it — the reminder
                    // schedule above all — has to hear about both or it rebuilds from
                    // stale data half the time.
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: Self.storeDidChange, object: self)
                    }
                }
            } catch {
                thrown = error
                context.rollback()
            }
        }
        if let thrown { throw thrown }

        if let saved {
            // Re-entrant when already on the main queue, so this is safe from either side.
            let viewContext = container.viewContext
            viewContext.performAndWait { viewContext.mergeChanges(fromContextDidSave: saved) }
        }
    }
}
