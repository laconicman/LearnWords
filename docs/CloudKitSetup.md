# CloudKit setup

Everything the code cannot do for itself. The app is already written against
`NSPersistentCloudKitContainer` ([Design](Design.md)); what remains lives in your developer
account, in Xcode's Signing & Capabilities tab, and in the CloudKit Console.

If any of it is missing the app **does not fail** — `LWPersistence` falls back to the same
local store it has always used and logs why. Sync is the thing you lose, not the
vocabulary.

## The identifiers this project uses

| | |
|---|---|
| App bundle ID | `club.laconic.LearnWords` |
| iCloud container | `iCloud.club.laconic.LearnWords` |
| App Group | `group.club.laconic.LearnWords` |
| Team (app target) | `WEJF495R4D` |

> **Watch the team.** The app, widget and share extension are signed with `WEJF495R4D`,
> but the project-level default and the test bundle use `MW2YXY2465`. A container created
> while the wrong team is selected produces exactly the `BadContainer` error below, and the
> mistake is invisible in the log — it reports only that the container could not be
> configured, not that it exists somewhere else.

## Steps

### 1. iCloud capability and the container

Xcode is the right place for this — it registers the App ID, creates the container and
regenerates the provisioning profile in one step. Doing it by hand in the portal means
keeping three things in sync yourself.

1. Select the **LearnWords** target → **Signing & Capabilities**.
2. Confirm **Automatically manage signing** is on and **Team** is `WEJF495R4D`.
3. **+ Capability** → **iCloud**.
4. Tick **CloudKit**.
5. Under **Containers**, click **+** and enter `iCloud.club.laconic.LearnWords`.

Ticking CloudKit also adds the Push Notifications capability, which is what puts
`aps-environment` in the entitlements. That entitlement is why this step cannot be done by
editing `LearnWords.entitlements` by hand: the App ID has to be updated at the same time,
or signing breaks.

### 2. Background Modes → Remote notifications

**Already done in code** — `UIBackgroundModes` contains `remote-notification` in
`LearnWords/Info.plist`. Xcode's Background Modes capability writes the same key; adding it
through the UI is equivalent and will show the existing value ticked.

No app code is needed to receive these pushes. `NSPersistentCloudKitContainer` owns the
subscription and the system routes the notification to it — you do not call
`registerForRemoteNotifications()` and do not implement
`application(_:didReceiveRemoteNotification:)`.

### 3. App Group

Should already exist, since the widgets read the shared store. Verify
`group.club.laconic.LearnWords` is listed under **App Groups** for this target and in the
same team.

### 4. Initialize the development schema

**CloudKit will not accept records of a type it has never heard of**, and syncing does not
create those types. Until this runs, a fresh container has an empty schema and sync
silently does nothing.

1. **Product → Scheme → Edit Scheme → Run → Arguments**.
2. Under *Arguments Passed On Launch*, add `-LWInitializeCloudKitSchema 1`.
3. Run once on a device signed into iCloud. The log should end with
   `CloudKit schema initialized.`
4. **Remove the argument again.** It uploads on every launch it runs.

It is `#if DEBUG` and behind that argument on purpose: it must never run against
Production, where record types are immutable forever.

Re-run it after **any** model change, and reset the Development environment in the CloudKit
Console first if the change was not purely additive.

> **The schema is not created by syncing.** CloudKit auto-creates a record type in the
> *Development* environment the first time a record of that type is written — so a schema
> built by ordinary use only contains the entities that happen to have rows, with only the
> fields that happen to be non-nil. On the first two-device run this produced five record
> types out of ten, and `CD_Synset` had no `CD_note` because no meaning had one yet.
> Production has no such auto-creation: deploying a partial schema means the first review
> event, tag or transcription a user creates **fails to export, permanently**. Run step 4
> before step 7, every time.

### 5. Verify in the CloudKit Console

[icloud.developer.apple.com](https://icloud.developer.apple.com) → your container →
**Schema → Record Types**, or **Export Schema…** for a diffable text version.

**All ten entities must be present**, plus `CDMR` (the many-to-many join records Core Data
synthesises) and the built-in `Users`:

```
CD_WordSet  CD_Synset  CD_Term  CD_Language  CD_Tag  CD_ErrorTag
CD_ReviewEvent  CD_Comment  CD_Illustration  CD_WordForm      + CDMR
```

Anything missing means step 4 has not run since that entity was added. The `CD_` prefix is
Core Data's mirroring convention.

### 6. Two devices

The test that actually matters. Two devices, both unlocked, both signed into the **same**
iCloud account, both on a good connection. Add a word on one; it should appear on the other
within about a minute. Apple's own guidance is not to rely on push for testing — pushes get
dropped and deferred — so watch the logs rather than the clock.

### 7. Deploy to Production — last, and once

**Only when the model is final.** After deployment the record types and their fields are
immutable for all time: you may add new types and new fields, never rename or delete one.
CloudKit Console → **Deploy Schema Changes**.

## Reading your log

```
BUG IN CLIENT OF CLOUDKIT: CloudKit push notifications require the
'remote-notification' background mode in your info plist.
```

Step 2, now fixed in the repo. Until step 1 also adds `aps-environment`, the key is
declared but nothing is delivered — sync then happens at launch, on foregrounding and on
CloudKit's own schedule, just not promptly.

```
"BadContainer" (1014); "Couldn't get container configuration from the server
for container "iCloud.club.laconic.LearnWords""
```

**The container does not exist, as far as the server is concerned.** Step 1. In order of
likelihood: it was never created; it was created under `MW2YXY2465` instead of
`WEJF495R4D`; or the provisioning profile predates it and needs regenerating (toggle
Automatically manage signing off and on).

```
Couldn't read values in CFPrefsPlistSource ... Using kCFPreferencesAnyUser with a
container is only allowed for System Containers, detaching from cfprefsd
```

Ordinary noise from reading an App Group's `UserDefaults`; it appears in apps whose groups
are perfectly configured. Worth a glance at step 3 only because that is cheap.

```
IPCAUClient: bundle display name is nil
AVAudioBuffer.mm:281 mBuffers[0].mDataByteSize (0) should be non-zero
```

Speech synthesis, unrelated to any of this. Both are AVFoundation internals and both are
harmless — don't chase them.

## "It synced, but the other device still shows the old words"

Two different causes, and the log looks healthy in both.

**The screen never re-read.** Screens hold snapshots — `Lexicon` returns value types, so
nothing tells a table its array is stale. Fixed: `LWPersistence.storeDidChangeRemotely` is
posted after an import is merged and deduplicated, and the word list, the sets list and the
exercise chooser reload on it while they are on screen.

**The two devices are looking at different sets.** Which set is selected is *device-local*
state, deliberately ([Design](Design.md)) — you may want a different set open on iPad than
on iPhone. But if the devices ended up with **two sets of the same name** (the double-seed
bug, fixed), each device selects its own, and a word added to one is invisible on the
other. It is working exactly as designed on data that should not exist.

The repair is to delete the duplicate set on either device: the other device's selection
then points at nothing and falls back to the surviving set on its own.

## Debugging sync itself

Raise Core Data's own logging — **Edit Scheme → Run → Arguments**:

```
-com.apple.CoreData.CloudKitDebug 3
```

Start at `1`; higher is more detail. From the Mac, watch both sides at once:

```bash
log stream --info --debug --predicate '(process = "LearnWords" and (subsystem = "com.apple.coredata" or subsystem = "com.apple.cloudkit")) or (process = "cloudd" and message contains[cd] "iCloud.club.laconic.LearnWords")'
```

Most CloudKit errors are transient — no network, not signed in — and recover by
themselves. `BadContainer` is not one of those; it means configuration.

## Reading

Apple documentation:

- [Setting Up Core Data with CloudKit](https://developer.apple.com/documentation/coredata/setting-up-core-data-with-cloudkit) — steps 1–3 above, with screenshots.
- [Creating a Core Data Model for CloudKit](https://developer.apple.com/documentation/coredata/creating-a-core-data-model-for-cloudkit) — the model limitations, `initializeCloudKitSchema`, and promoting to Production.
- [Syncing a Core Data Store with CloudKit](https://developer.apple.com/documentation/coredata/syncing-a-core-data-store-with-cloudkit) — what the sync cycle actually does, and the log-stream recipes.
- [`NSPersistentCloudKitContainer`](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer)

WWDC:

- [Using Core Data With CloudKit (WWDC19, 202)](https://developer.apple.com/videos/play/wwdc2019/202/) — the one to watch first; it is the introduction of `NSPersistentCloudKitContainer` and explains the model constraints by way of *why*.
- [Sync a Core Data store with the CloudKit public database (WWDC20, 10650)](https://developer.apple.com/videos/play/wwdc2020/10650/) — public database; we use the private one, but the schema and setup discussion carries over.
- [Optimize your use of Core Data and CloudKit (WWDC22, 10119)](https://developer.apple.com/videos/play/wwdc2022/10119/) — profiling and debugging sync, i.e. what to do when step 6 disappoints.
