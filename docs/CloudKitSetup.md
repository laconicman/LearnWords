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

> **The two teams, named — and no longer split (2026-09-10).**
>
> | Team ID | Name |
> |---|---|
> | `WEJF495R4D` | **Paul Buktab** — this project's team |
> | `MW2YXY2465` | RENTEL — a different organisation |
>
> Read out of the signing certificates on the development Mac (`OU=` is the team ID:
> `security find-identity -v -p codesigning`, then `openssl x509 -noout -subject`), so this
> is measured rather than remembered.
>
> The app, both widgets and the share extension always signed with `WEJF495R4D`. The
> **project-level default and the test bundle** used `MW2YXY2465` — and the project-level
> team is what Xcode's Signing & Capabilities pane shows when the *project* rather than a
> *target* is selected, which is where an iCloud container gets created. A container made
> from that screen lands under RENTEL, is invisible to an app signed as Paul Buktab, and
> produces exactly the `BadContainer` error below. The log cannot tell you this: it reports
> only that the container could not be configured, never that it exists somewhere else.
>
> **All twelve build configurations now use `WEJF495R4D`.** If `BadContainer` persists after
> that, the container itself is under the wrong team and must be recreated — containers
> cannot be moved between teams.

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

### 2. Background Modes → Remote notifications, and the Push capability

> **The capability was the missing half; no code is.** `UIBackgroundModes` has carried
> `remote-notification` for a long time. What was missing is the **Push Notifications
> capability on the App ID**, which is what puts `aps-environment` in the entitlements —
> Apple's setup guide has ticking CloudKit add it, and this project's entitlements are
> maintained by hand, so it never arrived. Added 2026-09-10.
>
> **Corrected the same day.** An earlier version of this section said the app must also call
> `registerForRemoteNotifications()` and implement the delegate handler, and that without
> them sync was never prompt. Apple says otherwise: "You don't need to add any code to your
> project to synchronize records across devices" (*Syncing a Core Data Store with
> CloudKit*) — CloudKit pushes, and the system creates the background task that downloads
> and imports. The paragraph at the end of this step was right all along. The handler that
> briefly existed completed at once with `.newData`, which could only end that background
> time early. Reported by review, PR #14.
>
> Enable **Push Notifications** on the App ID in the portal before building to a device.
> `aps-environment` is now in `LearnWords.entitlements`, and a device build fails to sign
> without the matching capability — that failure is the check that this step was done.



**Already done in code** — `UIBackgroundModes` contains `remote-notification` in
`LearnWords/Info.plist`. Xcode's Background Modes capability writes the same key; adding it
through the UI is equivalent and will show the existing value ticked.

No app code is needed to receive these pushes. `NSPersistentCloudKitContainer` owns the
subscription and the system routes the notification to it — you do not call
`registerForRemoteNotifications()` and do not implement
`application(_:didReceiveRemoteNotification:)`. Source: Apple, *Syncing a Core Data Store
with CloudKit* — verified 2026-09-10, after this project briefly did both.

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

Step 2, fixed in the repo; `aps-environment` was added on 2026-09-10. If this line still
appears, the App ID is missing the Push Notifications capability.

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

## Noise that is not a permission problem

CloudKit's private database needs no permission beyond the user being signed into iCloud —
there is no prompt to present and nothing to request. A device log full of red herrings
does not change that. From a real iOS 26 run, all harmless:

| Line | What it is |
|---|---|
| `RBSServiceErrorDomain Code=1 "Client not entitled"`, `elapsedCPUTimeForFrontBoard couldn't generate a task port` | RunningBoard chatter while the debugger is attached |
| `personaAttributesForPersonaType … connection … invalidated` | `usermanagerd` XPC teardown |
| `RTIInputSystemClient … requires a valid sessionID`, `variant selector cell index could not be found`, `Could not find cached accumulator` | keyboard internals |
| `CFPrefsPlistSource … kCFPreferencesAnyUser` | reading an App Group's `UserDefaults` |
| `IPCAUClient: bundle display name is nil`, `AVAudioBuffer … mDataByteSize (0)` | speech synthesis internals |

Two are worth a second look but were still not the cause of anything so far:

- `updateTaskRequest failed … BGSystemTaskSchedulerErrorDomain Code=3` — CloudKit failing to
  register its background export activity. Seen on every iOS 26 launch, and that device
  still exported successfully (the other device imported its seed), so it is not fatal.
  Worth revisiting only if background sync stops happening while the app is backgrounded.
- `Unable to simultaneously satisfy constraints … ButtonBarButtonVisualProvider` — a
  navigation-bar button being squeezed under iOS 26's floating bar. Cosmetic, self-healing
  (UIKit breaks the weaker constraint), and ours rather than the system's.

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

## The deployed schema, kept here so drift is visible

`docs/CloudKitSchema-Production.ckdb` is the **Production** schema exported from the CloudKit
Console (Console → the container → Export Schema), snapshotted 2026-09-14, straight after the
deploy below. It lives in the repo for one reason: a schema in a console is invisible to review,
and a file in git diffs.

**Refresh it whenever you deploy**, under the same name, so the commit shows exactly which
record types and fields production gained. Deployment is additive and one-way — record types
and fields already in production cannot be deleted or renamed (Apple, *Deploying an iCloud
Container's Schema*) — which is why seeing the change before it happens is worth a file.

**Export with Production selected.** The `.ckdb` is a bare `DEFINE SCHEMA` block with no
environment marker anywhere in it, so an export taken with Development selected reads exactly like
a deploy that has already happened. The environment lives in the Console's selector at the moment
of export and nowhere else — nothing downstream can catch the mistake.

### The deploy of 2026-09-14

Production had been deployed from the model as it stood before `f833280` (2026-08-09), and so
lagged `LearnWords.xcdatamodeld` by two record types and two fields. That gap is closed.

| Deployed 2026-09-14 | Kind |
|---|---|
| `CD_Pronunciation` | record type |
| `CD_Variety` | record type |
| `CD_Language.CD_wiktionaryCode` | field |
| `CD_Tag.CD_category` | field |

**How it was done, and the one step that needs hardware.** A *device* build was launched once with
`-LWInitializeCloudKitSchema 1` — the simulator cannot do this step: it reaches
`initializeCloudKitSchemaWithOptions` and fails with `CKAccountStatusNoAccount`, because no
simulator carries an iCloud account. The device logged `CloudKit schema initialized`, which leaves
*Development* matching the model; the launch argument was then removed. **Deploy Schema Changes…**
in the Console offered exactly those four additions and nothing else — no deletions, no type
changes, no index or permission changes — which is the only shape a deploy should ever have,
because none of it can be taken back.

**Why the gap was harmless while it lasted.** Nothing in the app writes any of the four — they
exist only as `@NSManaged` declarations — so no export ever named them and sync was unaffected. It
would not have stayed harmless: the first feature that *did* write one would have failed in
production only, and silently, because a released app cannot add to the production schema.

Every snapshot stays in history, so `git log -p -- docs/CloudKitSchema-Production.ckdb` is the
deploy log — which is the whole reason the file is here.

## Entitlements: what is here, and what is deliberately not

| Entitlement | State |
|---|---|
| `com.apple.developer.icloud-container-identifiers` | present |
| `com.apple.developer.icloud-services` (CloudKit) | present |
| `com.apple.security.application-groups` | present |
| `aps-environment` | present since 2026-09-10 — silent CloudKit pushes |

`aps-environment` reads `development`, in the one entitlements file both configurations point at
(`CODE_SIGN_ENTITLEMENTS` is the same path for Debug and Release). Automatic signing is expected to
substitute `production` when an archive is signed against a distribution profile — **unverified
here, and worth one check before the first upload**: export the archive and read it back with
`codesign -d --entitlements :- Payload/LearnWords.app`. A `development` value shipped to the App
Store is silent pushes that never arrive, with nothing in the app to show for it.

**Nothing else is added speculatively, and that is a rule rather than laziness.** Every
entitlement must also exist as a capability on the App ID: a device build signs against the
provisioning profile, and an entitlement the profile does not grant fails the build
outright. "Add everything we might need" would therefore break signing for everyone until
each one was also ticked in the portal.

Considered and left out:

* **`com.apple.developer.usernotifications.time-sensitive`** — only if reminders should be
  able to break through Focus. That is a product decision about interruption, not a sync
  one, and provisional authorization (below) points the other way.
* **`com.apple.developer.icloud-container-environment`** — pins Development or Production
  explicitly. Needed only for ad-hoc or enterprise builds; App Store and development builds
  infer it, and setting it wrongly is a way to have a shipped app talk to a schema nobody
  deployed.

### Background modes are not entitlements

They are listed here because this is where everyone looks for them, and finding nothing reads as a
missing step. `UIBackgroundModes` is an **Info.plist array**: Xcode's Background Modes capability
edits `LearnWords/Info.plist` and touches no `.entitlements` file, and no App ID capability
corresponds to it. An entitlements file with nothing background-shaped in it is what a correctly
configured app looks like here. (An earlier revision of this page had `fetch` and `processing` in
the entitlements list above — wrong category, and removed.)

| Mode | State |
|---|---|
| `remote-notification` | declared in `LearnWords/Info.plist` — the mode CloudKit's silent pushes need |
| `fetch` | not declared, deliberately |
| `processing` | not declared, deliberately |

The reasoning, and the two changes that would each earn a second mode, are in
[Design](Design.md) § *one background mode, and it is the one CloudKit needs*.

**Provisional authorization** (`.provisional`, iOS 12+) is requested alongside
`.alert/.sound/.badge`, so turning reminders on never opens a permission prompt: iOS grants
quietly and delivers to Notification Center, and the learner promotes or refuses from the
first reminder itself. This is not an entitlement — it is a runtime option — and it is
listed here because it is the other half of "leverage push properly".
