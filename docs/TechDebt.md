# Tech-debt register

Each item has a **Cost** (what it hurts) and a **Discharge** (the change that retires
it). Reference an item from code with `// TODO(TD-n): …`.

Status: `open` unless noted.

## TD-1 — Flat file layout — **resolved for source (2026-07-17)**

Was: ~30 source files flat in `LearnWords/`. The 30 `.swift` files are now in the
feature-first layout (`App/`, `Model/`, `Controllers/`, `Shared/…`, `Features/*` — see
the [mapping](#appendix-feature-first-mapping)); a clean build of all three targets is
green and the app launches. **Remaining:** *resources* (storyboards, `.xcstrings`,
asset catalogs, `Settings.bundle`, `.lproj`, `PrivacyInfo.xcprivacy`, entitlements,
`Info.plist`) deliberately stayed at the folder root — they are path-referenced by build
settings and/or need the `Main.storyboard` split first (TD-5). Move them once TD-5 lands.

## TD-2 — Shared files coupled to sibling targets via pbxproj exceptions

These files are compiled into the **Widget** and/or **ImportAsDictAction** targets via
`membershipExceptions` (paths relative to the synchronized root `LearnWords/`), now at
their post-reorg paths. Since TD-13 iteration 3 the widget list is the store rather than
the old model: `Controllers/Library.swift`, `Model/CoreData/LearnWords.xcdatamodeld`,
`Model/CoreData/LWPersistence.swift`, `Model/CoreData/ManagedObjects.swift`,
`Model/Lexicon/LanguageCode.swift`, `Model/Lexicon/Lexicon.swift`,
`Model/Lexicon/LexiconSeed.swift`,
`Model/Lexicon/LexiconTypes.swift`, `Model/Practice/Exercise.swift`,
`Model/Practice/LanguagePair.swift`, `Model/ReviewOutcome.swift`, `Model/Settings.swift`,
`Shared/AppConstants.swift`, `Shared/Debug.swift`, `Shared/Extensions/String+.swift`,
`Shared/Extensions/UserDefaults+Codable.swift` (both widget targets);
`Shared/AppConstants.swift` (ImportAsDictAction). Note `PlainText.swift` is deliberately
**not** in that list — it needs `Shared/General.swift`, and the widgets neither import nor
export. **Cost:** moving any of them silently drops them from those targets
unless the exception path is updated — the TD-1 reorg had to update all of these in
lockstep. **Discharge:** when relocating a shared file, update its `membershipExceptions`
entry and build all three targets. Longer term, extract the shared core into a local
Swift package with explicit membership so the coupling is compiler-enforced, not
path-string-enforced.

## TD-3 — Share-import deep link — **resolved (2026-07-18)**

Was: the ported `learnWords://shareaction` handler rebuilt the root VC (discarding UI
state), and the import itself only ran in `WordTableViewController.viewDidLoad` — so a
share made while the app ran warm silently waited for an app *relaunch*. The old
commented-out `selectedIndex` hinted the intent was tab selection, not a root rebuild
(the rebuild existed purely to re-trigger `viewDidLoad`).

Now:
- **`WordImport.parseDictionary`** (`Model/WordImport.swift`) — the parsing extracted from
  the VC into the model layer; **10 unit tests** (separators `| : - –`, U+2028 lines,
  malformed-line skips, case preservation, and the known hyphenated-word limitation, kept
  for parity with its FIXME).
- **`consumePendingImport()`** in `WordTableViewController` — idempotent (reads + clears the
  App-Group key), triggered from `viewWillAppear`, `willEnterForegroundNotification`, and
  `AppRoot.shareActionReceived`; visible-only guard for the foreground/notification paths
  because the single-word flow segues.
- **`AppRoot.handle`** — selects the Word Set tab and posts `shareActionReceived`; no root
  rebuild, UI state survives.

**Verified:** cold launch with pending `ImportedText` imports, dedups, saves, clears the key,
and shows the words (owl/wolf) in the UI — confirmed on the iOS 26 sim by injecting the key
into the app's suite plist. **Caveats:** (a) the warm-foreground and notification triggers
are code-identical but weren't exercised — `simctl openurl` stalls on the system "Open in
LearnWords?" dialog, which CLI can't tap; one manual run of the real share flow covers it.
(b) The unsigned CLI build has no App-Group entitlement, so its suite is app-container-local —
a signing artifact only; Xcode-signed builds use the real group container.

## TD-4 — Widgets: WidgetKit (iOS 14+) + legacy Today (iOS 12–13) — **implemented (2026-07-18)**

Decision (owner): migrate to WidgetKit **and** keep a working Today extension for the iOS
versions WidgetKit doesn't reach. The version math: WidgetKit is iOS 14+; Today extensions
(`NCWidgetProviding`, pre-14) still *display* on iOS 12–17 but **iOS 18 removed** legacy
Today-view widgets entirely. So the split is exact and permanent:

| iOS | Widget shown |
|---|---|
| 12–13 | Today extension (`Widget` target — deployment 12.1, inherited) |
| 14–17 | WidgetKit (`WordWidgetExtension`); the Today one also still appears (harmless) |
| 18+ | WidgetKit only (system dropped Today widgets) |

Implemented: `WordWidgetExtension` (owner-created target; floor lowered 26.5 → **14.0**) with
a `TimelineProvider` reading the current word set through the shared `Storage`/`WordStore`
stack and App-Group defaults (`group.club.laconic.LearnWords` — entitlements added; the
`AppGroup` helper derives the group from the extension bundle id via its `NSExtension` key).
Small + medium families; iOS 17 `containerBackground` gated with `#available`; template's
Control-widget scaffolding (iOS 18) removed; shared files wired via a new
`membershipExceptions` set (mirrors the Widget target's list — `Settings.bundle` included
because `Settings.swift` force-unwraps it at init). Builds green; `.appex` embeds.

**Remaining:** (a) visual check — add the widget from the simulator/device home screen;
(b) the app never calls `WidgetCenter.shared.reloadAllTimelines()` after saves, so the
widget lags edits by up to its 30-min refresh — add an availability-gated nudge app-side
when convenient; (c) the old Today extension stays deprecated-but-working for 12–13
(verification only possible per TD-8); App Store still accepts Today extensions — recheck
at submission.

## TD-4 (historical) — Deprecated Today extension (`Widget/`)

`TodayViewController` uses `NCWidgetProviding`, deprecated since iOS 14 and unsupported
on modern iOS. **Cost:** dead/again-un-shippable extension; App Store review risk.
**Discharge:** migrate to WidgetKit, or remove the target.

## TD-5 — Storyboard-centric UI

A single `Main.storyboard` drives navigation. **Cost:** merge conflicts, slow loads, no
clean dependency injection into view controllers. **Discharge:** split per feature or go
programmatic; inject via `UIStoryboard.instantiateViewController(identifier:creator:)`.

## TD-6 — Automated tests — **seeded (2026-07-17)**

Was: no test target. Owner added a hosted Swift Testing "Unit Testing Bundle"
(`@testable import LearnWords`); it now holds **13 passing cases**:
- `WordAndStatTests` — the model's pure logic (increase caps at `maxKnownLevel`, decrease
  floors at 0, `known` sums-and-caps, reset clears, Codable round-trip). The
  `maxKnownLevel`-dependent cases run in a `@Suite(.serialized)` because that value is read
  from a global `UserDefaults`.
- `StringCanonicaliseTests` — parameterized cases for `String.canonicalise()`.
- `AppRootTests` — launch smoke test: `AppRoot.makeRoot()` builds the home tab bar from
  `Main.storyboard`.

**Remaining:** `Storage` is uncovered (TD-12). **Note:** the test target's deployment target
is iOS 26.5 (Xcode default), so tests need a 26.x simulator; lower it if you want them
runnable on older sims/CI.

## TD-12 — `Storage` testability / persistence seam — **resolved (2026-07-17)**

Was: `Storage` was all-`static` over the global App-Group `UserDefaults`, untestable. Now:
- **`WordStore`** (`Model/WordStore.swift`) — the persistence-seam protocol.
- **`UserDefaultsWordStore`** (`Model/UserDefaultsWordStore.swift`) — today's logic with an
  injected `UserDefaults` + save executor → **8 unit tests** against an ephemeral suite.
- **`Storage`** — now a thin static facade forwarding to a swappable `backend: WordStore`;
  all 73 call sites unchanged. (Both new files added to the Widget target's membership.)
- Verified: all targets build; 21 tests pass; app launches and the word list still loads.

**Interim:** `Storage.backend` remains a global swap-point (service-locator smell), *not*
per-VC injection — deliberately, because Core Data (TD-13) will replace this layer, making
per-VC injection of the UserDefaults store throwaway. Full injection lands with that migration.

## TD-13 — Core Data + CloudKit — **iteration 1 landed (2026-07-20)**

Implementation runs from [`TASK-TD13-schema.md`](TASK-TD13-schema.md). Two of its four
"decide before coding" questions are now answered, in [Design](Design.md): `WordStore`
stays **synchronous** (Swift Concurrency back-deploys only to iOS 13, so `async` is
unavailable at the 12.1 floor), and **nothing migrates** — TD-18's identity is born with
the Core Data model instead of being retrofitted onto `UserDefaults`, so Phase A folds into
Phase B. The other two are deferred with reasons: the FSRS dependency is a Phase-D concern
(the log is FSRS-independent; FSRS *consumes* it), and the per-word index cache is *derived*
data whose columns depend on a `ScoringPolicy` that does not exist yet — guessing its shape
now would be worse than adding it later, and derived data carries no backfill risk.

**Iteration 1 — REDONE (owner review, 2026-07-23).** The first cut replicated the
word-pair model in Core Data. The owner rejected that as "a very naive and limited
solution" and commissioned research ([LexicalModelResearch](LexicalModelResearch.md));
the schema is now the lexical model: **`Term`** (atomic word in one language —
transcription, part of speech, variant forms, comments, illustrations) ↔ **`Synset`**
(one shared meaning, the owner's "language tuple"; synonyms are same-language terms and
all are valid answers; sense note lives here) ↔ **`WordSet`** (multilingual: declares
`languageCodes`, ranks nothing). All links many-to-many; nothing cascades into the
event log — snapshots keep orphan events judgeable. Events gained `promptLanguage` /
`answerLanguage` / `promptTermID` / `wordSetID`; `ReviewDirection` renamed to
receptive/productive and `LanguagePair` to primary/secondary (owner naming). 14 schema
tests (73 total green). Original iteration-1 notes below for the parts that survive
(stack, CloudKit rules, decisions).

**Iteration 1 (original) — the schema, nothing wired to it yet:**
- `Model/CoreData/LearnWords.xcdatamodeld` — `WordSet` (id, name, **nativeLanguage /
  foreignLanguage**, createdAt) → `Word` (id, firstWord, secondWord, createdAt) →
  `ReviewEvent` with **every †-marked field** from the research audit (sessionID, direction,
  expected, prompt, latencyMS, judgment verdict/judge/judgedAt/errorTags, schemaVersion).
- `ManagedObjects.swift` — hand-written subclasses (manual codegen) so the schema is
  reviewable in the repo rather than generated invisibly at build time.
- `LWPersistence.swift` — the stack: one shared `NSManagedObjectModel` (loading it twice is
  the classic "failed to find a unique match for an NSEntityDescription" crash), App-Group
  store URL, an in-memory initialiser for tests, and a `write` that saves on a background
  context and rolls back on error.
- **Authored to CloudKit's rules from the start** — *mostly true, and the gap was
  expensive*: every UUID was non-optional carrying a `defaultValueString` that Core Data
  ignores, so `defaultValue` was nil and `NSPersistentCloudKitContainer` refused to open
  the store (TD-13 iteration 4). `momc` accepts the string; CloudKit reads the runtime
  default. The schema test carried this as a documented *exemption*, which is why nothing
  caught it — an exemption is a hole with a comment in it. The rule now runs verbatim.
  Original intent, otherwise upheld: all attributes optional or defaulted,
  every relationship optional with an inverse, no unique constraints (CloudKit rejects
  them). A test enforces this, so enabling `NSPersistentCloudKitContainer` later is a
  container swap rather than a redesign.
- **10 tests** against an in-memory store, including the two that are expensive to get
  wrong later: every audited event field round-trips (append-only — a missing field can
  never be backfilled), and an unknown future `outcome` decodes to `nil` with its raw value
  intact instead of crashing.
- Noted for iteration 4: `NSPersistentCloudKitContainer` and remote-change notifications
  are **iOS 13+**, so on iOS 12 this store is simply local. Correct degradation — Legacy
  keeps working, sync is a modern-OS feature.

**Normalization + metadata pass (owner review, 2026-07-25).** Applying the schema's own
WHERE-clause rule everywhere it belongs: `Synset.tags`, `ReviewEvent.judgmentErrorTags`
and the language strings became **`Tag`, `ErrorTag` and `Language` rows** — no
transformable attributes remain. Added `fetchIndex` entries for every attribute a
predicate actually touches (asserted by a test, since a missing index is invisible until
something is slow), `createdAt`/`modifiedAt` pairs on all user-editable entities
(maintained in `willSave()` via **primitive accessors** — the first cut re-dirtied the
object each pass and Core Data aborted the save after ~100 iterations), and
`awakeFromInsert` to assign identity and timestamps so call sites cannot forget.
Non-optional typed accessors were added to every managed-object class so CloudKit's
mandatory optionality is paid once here rather than at every call site. Decisions
recorded in [Design](Design.md) (identity: `objectID` for lookup rows vs `UUID` for
referenced entities; optionality at the boundary) and the research doc (indexes;
fetched properties, scalar types and transients considered and declined with reasons;
schema versioning under lightweight-migration rules and CloudKit's immutable production
schema). 79 tests green.

**Optionality, Spotlight, inheritance (owner review, 2026-07-25).** The claim that
CloudKit forces blanket optionality was **wrong** — `momc` enforces *optional or
defaulted*, so everything the creating API always supplies is now non-optional with a
default (validated on save, non-optional in Swift, intent stated in the schema), and only
attributes where **absence is meaningful** stay optional (`latencyMS`, `judgmentVerdict`,
`response`, `transcription`, `partOfSpeech`, `Synset.note`). A test pins the split. Found
by experiment: Core Data *ignores* `defaultValueString` on UUID attributes while `momc`
requires one — so non-optional UUIDs are a guarantee the code makes, documented and
exempted in the CloudKit test. Spotlight indexing enabled on the searchable text
(`Term.text`, `WordForm.text`, `WordSet.name`, `Synset.note`, `Comment.text`, `Tag.name`)
with `NSCoreDataCoreSpotlightDelegate` started for the SQLite store; the review log is
deliberately **excluded** so practice answers never leak into system search. Parent
entities were measured (a throwaway model proved Core Data stores a whole hierarchy in one
table) and declined, with the one future case where they would pay recorded. 81 tests green.

**Iteration 2 — the store (2026-07-25).** `Model/Lexicon/`: **`Lexicon`** is the only
type that talks to Core Data. Reads return value types, writes take value types, and no
managed object crosses the boundary — the rule that keeps a future store change confined
to one file. Naming: **value types take the clean names** (`WordSet`, `Sense`, `Term`,
`ReviewEvent`, each with a `Draft` where creation differs from reading) and the entities
keep the `CD` prefix; nothing above `Lexicon` mentions a `CD` type.

- **No protocol** (YAGNI): one implementation, and `LWPersistence(inMemory:)` already
  makes it testable, so a protocol would be a second name to keep in sync for no gain.
- **Not a `WordStore` conformer** (owner: "care not about compatibility"): that protocol
  is a flat `[WordAndStat]` mutated by index, and mapping senses onto it would collapse
  synonyms and multilingual tuples back into pairs — destroying what the redesign was
  for. The old store is untouched and still serves the screens; it goes when they move.
- Behaviour worth naming: words dedup by **(text, language)** so the same word is one
  shared row (`sale` en ≠ `sale` fr); adding words **widens the set's languages**;
  `senses(in:from:to:)` filters to what can actually be asked; deleting a set or a sense
  **never** deletes review events, and orphan collection is explicit and refuses anything
  carrying history. A `LanguageCache` prevents duplicate language rows inside one write
  block, where an unsaved insert is invisible to a fetch.
- **`LexiconSeed`** gives a fresh install a starter set (nothing migrates), including
  synonyms so the payoff is visible in the first round.
- **23 tests**, including one that writes a **real SQLite file** and reads it back through
  a fresh stack — everything else runs in memory, which never exercises the store type
  that ships. 104 green overall.

**Remaining:** ③ the screens still read the old `Storage`; moving them over (and deleting
`WordStore`/`UserDefaultsWordStore`/`WordAndStat`) is the next iteration, together with
`ExerciseSession` recording real events. Then ④ CloudKit + App Group + widget, ⑤ indexes
and the TD-17 ring. Also open: handling `CSSearchableItemActionType` to open the right screen from a
Spotlight result (UI, after the store); ② `CoreDataWordStore: WordStore` + swap `Storage.backend` + seed the sample
set · ③ screens append events (Phase C) · ④ CloudKit + App Group + widget · ⑤ indexes and
the TD-17 ring (Phase D).

## TD-13 (original note) — Core Data + CloudKit migration (planned direction)

Owner intends to move persistence to Core Data with `NSPersistentCloudKitContainer` so word
sets and learning progress sync across a user's devices. The `WordStore` seam (TD-12) is built
for exactly this: write `CoreDataWordStore: WordStore`, swap `Storage.backend`, and inject the
store/context at the composition root (finishing the DI that TD-12 deferred). Use the
`core-data-expert` / `axiom-data` skills.

**The object model is designed: [ProgressModel](ProgressModel.md)** (2026-07-20) — `Word`
(UUID identity, TD-18) → append-only `ReviewEvent` log (outcome taxonomy, response text,
attachable AI judgments) + derived index caches. Event-sourcing is also the CloudKit-friendly
shape (append-only records merge without counter conflicts). Remaining considerations:
CloudKit entitlements + App-Group sharing with the extensions, and whether `WordStore`
goes async. Words/sets migrate from `UserDefaults`; **legacy progress aggregates do not**
(owner, 2026-07-20 — progress starts fresh from the event log; compatibility isn't worth
the code). Apply the `ProgressResearch.md` audit (pending) before implementing the schema.

## TD-7 — iOS 12 availability audit

**Swift code: clean.** A clean build at the 12.1 floor succeeds, and Swift treats any
unguarded newer API as a hard *error* — so a green build proves there are no unguarded
iOS 13+ API uses. (Spot-checked: `.label`, `systemIndigo`, `UIImage(systemName:)` are all
inside `#available`; `systemOrange` is iOS 7+.) No action needed here.

## TD-11 — Storyboard has iOS 13+ UI dependencies that break on iOS 12

The compiler can't see inside `Main.storyboard`, and it hard-codes iOS 13+ features with
**no fallbacks**, so the app *launches* on iOS 12 (dual lifecycle works) but its UI is
broken there:

- **Semantic colors without fallback** — ~40 refs to `labelColor`, `secondaryLabelColor`,
  `systemBackgroundColor` as `systemColor="…"` with **no `cocoaTouchSystemColor`** sibling.
  On iOS 12 these **crash or render transparent** (confirmed: noahgilmore.com, xamarin-macios
  #7086) — e.g. invisible text on a broken background.
- **SF Symbols** — tab-bar/cell images via `catalog="system"` (`house`, `folder`,
  `graduationcap`, `mic`, `keyboard.badge.ellipsis`, …). SF Symbols don't exist on iOS 12, so
  they render **blank**. `UIImage+backport.systemImage(_:)` already returns `nil` on iOS 12
  with a `// TODO: look up in assets` — no fallback assets exist yet.

**Cost:** the app's *reason to exist* (working on iOS 12) is unmet at the UI layer; crash
risk. **Cannot be fully verified on Xcode 26** (no iOS 12 sim — TD-8).

**Colors — resolved (2026-07-17).** All 32 semantic-color refs in `Main.storyboard`
(`labelColor`, `secondaryLabelColor`, `systemBackgroundColor`, `systemGray4Color`) migrated
to named asset-catalog colors — `TextPrimary`, `TextSecondary`, `Background`, `Gray4` (in
`Assets.xcassets`, each with Any + Dark appearances). Named colors are iOS 11+, so no iOS 12
crash; dark mode preserved on iOS 13+. Verified on a modern sim in **both** light and dark;
iOS 12 itself still needs an Xcode-15 pass (TD-8). `LaunchScreen` used only `systemOrange`
(iOS 7+) — untouched. These four are the seed of a real design system (see `axiom-design`).

**Icons — deferred (owner's call, 2026-07-17).** SF Symbols stay `catalog="system"`; they
render on iOS 13+ and degrade to **text-only tabs on iOS 12**. Adding PNG fallback art +
programmatic tab images (completing `UIImage+backport`) is future work if iOS-12 icon
fidelity is wanted.

## TD-8 — iOS 12 path is unverifiable on Xcode 26

Xcode 26 ships no simulator below iOS 15 and won't connect sub-15 devices, so the iOS 12
branch (`AppDelegate` window + `application(_:open:)`, `UIMainStoryboardFile`) **cannot be
run or tested** on the current toolchain. **Cost:** the legacy path can regress silently;
"supports iOS 12" is an unverified claim. **Discharge:** keep an **Xcode 15** install; before
releases that touch launch/lifecycle/URL handling, smoke-test launch + the
`learnWords://shareaction` deep link on an iOS 12 simulator or device there. The modern-SDK
App-Store build (Xcode 26+) and the iOS-12 verification build are two separate steps.

## TD-9 — Divergent doc copies — **resolved (2026-07-17)**

Was: `docs/*.md` (current) and `LearnWords/Documentation.docc/*.md` (older, unfilled
TEMPLATE scaffold from 1880e5d) had diverged. The obsolete `Documentation.docc` catalog
was deleted; **`docs/*.md` is the single source of truth.** If a rendered DocC catalog is
wanted later, regenerate it from `docs/` (per `repo-init`) rather than hand-maintaining two.

## TD-10 — ImportAsDictAction targets iOS 14, not 12

*(Corrected 2026-07-18: an earlier version claimed the Widget target was also at 14 — wrong.
The Widget (Today) target sets no explicit deployment target and inherits the project-level
**12.1**; only **ImportAsDictAction** pins `IPHONEOS_DEPLOYMENT_TARGET = 14`.)*

ImportAsDictAction was set to iOS 14 as a deliberate quick fix (owner: no workaround found in
reasonable time), so on iOS 12–13 the share-import flow is unavailable — and with it the
`learnWords://shareaction` deep link (TD-3) below iOS 14. **Cost:** the import feature is
missing on the oldest devices. **Discharge (deferred by owner):** revisit once structure
settles — either find the workaround and lower to 12.1, raise consciously, or accept as-is.

---

## TD-14 — Settings.bundle pane — **replaced with in-app settings (2026-07-19)**

Found while testing: the system-Settings pane (`Settings.bundle`) had three defects —
(1) benign-but-alarming "Key not found" logs for `PSGroupSpecifier` headers, (2) blind
`PSTitleValueSpecifier` rows ("Pitch"/"Rate"/"Study" never written by the app, shown blank
next to unlabeled sliders), (3) **per-process registration**: defaults registered into
*standard* `UserDefaults` (the group call was commented out with "This is what you probably
want!"), so pane changes reached the app but not the Widget (which kept its own registered
`maxKnownLevelPreference` = 20).

**Resolution (owner's call: replace, not repair):**
- `Settings.bundle` **deleted** (with its localizations and the registration parser — all
  three defects gone at the root). Removed from Widget/WordWidgetExtension memberships;
  the force-unwrap crash risk in extensions is gone too.
- `LWUserDefaults`: defaults now defined in code (`defaultPreferences`) and registered into
  the **App-Group suite** every launch; all preference accessors repointed to the group, so
  app + Widget + extensions agree. One-time migration copies user-set values from the old
  standard domain (via `persistentDomain`, which excludes registered defaults).
- New `Features/Settings/`: programmatic `SettingsViewController` (grouped table; language
  pickers, sliders **with live value labels** — the un-blind version of the old rows,
  pronounce toggles, known-level slider) + `LanguagePickerViewController`. Pushed from the
  Words tab's Settings button (`goToSettings:` no longer jumps to system Settings; the
  permission-prompt `gotoAppSettings()` calls remain, correctly, system jumps).
- New strings use `NSLocalizedString` — RU translations to be added in `Localizable.xcstrings`.

**Verification state:** full build green (app + all extensions + test bundle). The three new
tests (`LWUserDefaultsTests`, `SettingsViewControllerTests`) and a re-run of the suite were
**blocked by a wedged CoreSimulator** on the dev machine (hangs before "Testing started";
pre-change suite was 32/32). Run ⌘U and eyeball the new screen after a CoreSimulator restart.

## TD-15 — Speech silent until Phonetics visited — **resolved (2026-07-19)**

`SpeechManager` sets `usesApplicationAudioSession = true`, so synthesis depends on the app
configuring/activating the shared `AVAudioSession` — but only `WordPhoneticsViewController`
ever did (its `viewDidLoad`). On every other screen (Dictation, Test, Words) the synthesizer
rendered empty buffers — the console's `mBuffers[0].mDataByteSize (0)` — until Phonetics
ran once and left the session active app-wide. Not settings-related; the settings log was a
red herring (see TD-14).

**Fix:** `SpeechManager.ensureAudioSession()` — on each `speak()`, if the session category
is neither `.playback` nor `.playAndRecord`, set `.playback` and activate. Leaves the
Phonetics mic flow's `.playAndRecord` untouched; lazy (no session grab at app launch — the
warm-up `_ = SpeechManager.shared` stays side-effect-free). Regression-tested:
`SpeechManagerTests.speakConfiguresPlaybackAudioSession` (hosted test asserts the category).

**Owner-confirmed (2026-07-19): pronunciation now works everywhere.** Two console lines
remain and are **benign** — `IPCAUClient: bundle display name is nil` is well-known
system/audio-unit host noise, and `mBuffers[0].mDataByteSize (0)` accompanying *audible*
synthesis is the synthesizer flushing a leading empty buffer. Cosmetic; not actionable from
app code.

## TD-16 — Animation system: duplicated, fragile, and joyless

Surfaced by a crash at `WordTestViewController` (2026-07-19): a `UIViewPropertyAnimator`
started with `afterDelay: 2.0` captured `[unowned self]`; leaving the screen during the
delay deallocated the VC and the completion crashed. **Hotfixed** — all six animation
blocks across Test/Dictation/Phonetics now use `[weak self]` (build green).

The underlying debt: the exercise screens **copy-pasted the same two animations** (spring-in,
shrink-fade-out + `askQuestion()` completion), and the app had no feedback/delight effects.

**Adoption executed (2026-07-19, per `TASK-TD16-adoption.md`):**
- **`ExerciseTransition`** (`Shared/DesignSystem/ExerciseTransition.swift`) — `show` (the
  entry spring-in from the hidden state each screen's `viewDidLoad` sets) + `advance`
  (fade-out → window-guarded `refresh`); the six copied blocks are now six one-line calls
  of two shared methods. Lifetime-safe by construction: the container is held weakly and
  `refresh` is skipped once it leaves its window — **proven by
  `ExerciseTransitionTests.refreshSkippedWhenScreenIsLeftDuringDelay`** (the exact crash
  scenario). *Correction (2026-07-20):* the first adoption folded `show` into `advance`,
  which blanked every exercise screen — the standalone spring-in is the load-bearing
  **entry** animation because the screens start at alpha 0. Caught by the owner; now locked
  in by `ExerciseScreenAppearanceTests.exerciseScreenBecomesVisibleAfterAppearing`, which
  drives the storyboard's `WordTest` scene through a real appearance cycle.
- **KaPow** (the Pow→UIKit port, local SPM package at
  `../Documents/Code/Animations/KaPow`, iOS 12 floor) linked into the app target.
- **Product mapping wired** in all three `afterAnswer(isKnown:)`: wrong → `.kapow.shake()`
  on the answer view; correct → `.kapow.shine()`; first time a word reaches the known
  level → `ExerciseFeedback.levelUp(on:)` (SF-symbol spray; no-op below iOS 13, same
  degradation tier as TD-11). Effects fire on child views; the transition animates the
  container — per KaPow's coexistence rule.
- 36/36 tests green; app launches with the package linked.

**Remaining:** the manual pass from the task's verification section (transitions + all three
effects on each exercise screen, on a device for feel); Spray's haptic burst is not ported
yet (KaPow TD-4).

## TD-17 — Word-cell progress ring: modernize/replace KDCircularProgress — **resolved (2026-07-26)**

Context (2026-07-20): the words list logged an unsatisfiable-constraint break per row —
the cell's stack was pinned top = 4 **and** bottom = 4 **and** centerY while the 44-pt
`KDCircularProgress` ring drove the stack height; at the 53-pt row that's 1 pt
over-constrained. **Fixed**: both pins relaxed to ≥ 4 (centerY positions; the ring stays
square). Verified: zero constraint messages in the app console; cells render unchanged.

**Discharged with TD-13 iteration 5.** The 556-line vendored 2015-era control
(`Shared/DesignSystem/KDCircularProgress.swift`, matching
[kaandedeoglu/KDCircularProgress](https://github.com/kaandedeoglu/KDCircularProgress), MIT)
is deleted, replaced by `ProgressRing`: two arcs — outer mastery, inner effort — tinted by
retention and sized from `UIFontMetrics` per ProgressModel R6. Two arcs because a word
fought with for a month reads differently from one never touched, and one arc cannot say
that. Attribution question closed by removal.

**Research (2026-07-20) — the UIKit ring-library shelf is EOL, like the animation shelf:**
- [UICircularProgressRing](https://github.com/luispadron/UICircularProgressRing) — explicit
  EOL; author's own advice is "use the system ProgressView on iOS 14+" (i.e. SwiftUI).
- [MKRingProgressView](https://github.com/maxkonovalov/MKRingProgressView) — the richest
  visual (Apple-Watch activity ring: gradient sweep, shadowed rounded cap), MIT, small —
  but dormant (~2020). Viable as a vendor-swap if that look is wanted as-is.
- SFProgressCircle / KYCircularProgress / MBCircularProgressBar — dead.
- Native: UIKit has no ring; SwiftUI `Gauge` (iOS 16+) is the modern answer — right for the
  TD-13 rewrite, wrong for the 12.1 floor (hosting-per-cell, gated).

**Discharge options:** (a) keep as-is — it works and just got layout-fixed; (b) vendor-swap
to MKRingProgressView for instant activity-ring looks; (c) **recommended**: a small
in-house `ProgressRing` (~80 lines, CAShapeLayer + CAGradientLayer mask, rounded caps,
iOS 12-safe, tint/dark-aware) in the design system — retires 556 vendored lines, and its
progress can later be driven by KaPow's spring physics so level-ups *settle* instead of
jump (pairs with the TD-16 Shine/Spray moments).

**Blocked on [ProgressModel](ProgressModel.md) (owner decision, 2026-07-20):** the ring is a
*view* of the progress indexes; what it displays (mastery/effort/retention) is defined
there. When implemented, apply the R6 layout rule: ring size =
`UIFontMetrics.scaledValue(for: 44)` (follows Dynamic Type), labels at natural size (no
autoshrink), rows stay self-sizing — the indicator must never drive row height against the
font. The fixed-44 constraint is interim.

## TD-18 — Words have no stable identity — **resolved (2026-07-26)**

Words were identified by their `firstWord` string (dedup on import, history keying, cell
lookup). Renaming a word orphaned its history; duplicates across sets collided; CloudKit
(TD-13) requires stable record identity.

**Discharged by the TD-13 redesign rather than by a migration.** There is no `Word` any
more: `Term` is an atomic row with a `UUID`, shared by every sense and set that uses it,
so editing it edits it everywhere and the rename survives. History keys on the *sense*
(`CDReviewEvent.synset`) and carries the `promptTermID` plus text snapshots, so an event
stays interpretable after the word is edited or the meaning deleted. Set membership is a
relationship, not a string match.

No identity migration was written, per the owner's "start fresh" call
([Design](Design.md)) — identity is born with the model.

## TD-19 — Buttons frozen in 2017 — **resolved (2026-07-20)**

`GradientButton` drew the same chrome (gradient fill, 1pt `lightGray` border, 5pt corners,
Title1) on **every** iOS version. Nothing about it adapted, so as iOS 26 modernized the
surfaces around it — nav bar, tab bar, segmented control and alerts are all system-drawn
Liquid Glass — the buttons alone stayed put and the mismatch became the app's most visible
cosmetic defect. Three further faults were found while fixing it:

- **Inverted hierarchy.** `Look Up` (a utility) was the widest control on the Test screen,
  louder than `Know`/`Forgot`. The HIG asks for a prominent style on the *likely* action and
  at most one or two prominent buttons per view; the exercise screens had four or five.
- **No two screens agreed.** Button heights were 83 (Test), 100 (Dictation) and 71.5/72
  (Phonetics); Test was also the only screen with a full-width utility button.
- **Layout drifted per word.** The exercise stacks used `distribution="fillProportionally"`,
  so every arranged view was sized from its content — a long translation resized *and moved*
  the buttons between questions.

**Resolution.**
- **`LWButton`** (`Shared/DesignSystem/LWButton.swift`) replaces `GradientButton`. A button
  declares a **`Purpose`** (`utility` / `affirmative` / `negative` / `prominent`) and the
  control decides how that looks per OS. All 15 buttons already funnelled through one class,
  so the whole version story is **one `#available` check in one file**:
  `UIButton.Configuration` + `.capsule` on **iOS 15+** (both 15.0+; the system keeps drawing
  them correctly as the platform moves), a 5pt radius on **12–14** — capsules are a later
  epoch and aping them on iOS 12 would look more wrong than the flat rectangle. `.glass()`
  is *not* adopted: it is opt-in on iOS 26, and tinted/filled remain correct there.
  `cornerStyle` is set explicitly rather than relying on an SDK-linked default.
- **Gradients and borders survive as a seam, off by default** (`startColor`/`endColor`/
  `borderColor`/`borderWidth`). Setting either colour opts a button back into the old chrome
  on any OS. This costs nothing because the 12–14 renderer has to exist regardless — it is a
  seam for a future theme feature, deliberately **not** a theme system (YAGNI).
- **`LWWordLabel`** (same folder) makes the word display the elastic part of the layout:
  autoshrink (`minimumScaleFactor` 0.3, 2 lines) plus low vertical hugging. With the stacks
  moved to `distribution="fill"` and `LWButton` pinning its own height
  (`UIFontMetrics.scaledValue(for: 56)` — the TD-17 rule), buttons **keep size and position
  between questions** and verbose text scales itself down instead.
- **Geometry equalized.** All exercise buttons are half-width pairs at the same height; the
  Test screen gained a `Listen` button (`listenAction`, mirroring `askQuestion`'s language
  choice) so all three screens are a 2×2 grid.
- **Accessibility.** `Know`/`Forgot` carry checkmark/xmark symbols, so the answer pair no
  longer depends on red/green alone. `nil` below iOS 13 — text-only, the same degradation
  tier as the tab icons (TD-11).
- **Direction control** (`ExersizeChooserViewController`): the two-segment control had to fit
  both directions side by side, and its titles are built from *localized language names*, so
  ~170pt per segment shrank "Russian>English" to near-illegible (worse for longer pairs).
  Replaced by a single `LWButton` row naming the current direction with a swap icon; the
  names get the full width whatever languages are chosen.

**Semantic colours and Dynamic Type (2026-07-20, owner review).** Follow-up pass:
- **`LWColors`** (`Shared/DesignSystem/LWColors.swift`) names colours by meaning —
  `lwAnswerCorrect` / `lwAnswerWrong` / `lwAnswerPending` / `lwAccent`. The exercise screens
  had `UIColor(red: 0, green: 0.7, blue: 0, alpha: 1)` repeated across all three
  controllers: a fixed triple can't adapt to dark mode, and three copies were free to drift.
  Now the answer text and the button a learner presses share one definition. 14 literals
  replaced; commented-out code left alone. Dictation's `#available(iOS 13)`
  `.label`/`.black` branch collapsed to `lwTextPrimary`, deleting an availability check.
  Phonetics' record button signalled recording with `tintColor`, which a button
  configuration ignores — it now switches `purpose` (`.prominent` ⇄ `.negative`).
- **Dynamic Type.** Titles use `.headline` and re-resolve on
  `traitCollectionDidChange`; height is a `greaterThanOrEqual` **floor** of
  `scaledValue(for: 56)`, so buttons still hold position with fixed titles but can grow
  when a title wraps. Two real bugs surfaced and were fixed at accessibility sizes:
  (a) half-width buttons truncated Russian titles to "В сло…" / "Зн…" — **`LWButtonRow`**
  now stacks a button pair vertically when `isAccessibilityCategory`, the same thing
  `UIAlertController` does, and titles wrap instead of truncating; (b) the chooser's
  content overflowed off-screen leaving **"Фонетика" untappable** — its scene pins the
  content stack's bottom at priority 250, which was harmless while buttons were a fixed
  77pt but not once they scale, so `makeContentScrollable()` re-parents the stack into a
  scroll view at load. The word labels stay at their scene point size (80/70/60) and only
  scale *down*: they are already far larger than any Dynamic Type size, and `LWWordLabel`
  autoshrink is what keeps them in their slot.
- **Localization.** The new Test-screen `Listen` button carried only `en`; its `es`/`ru`
  units were copied from the Dictation button in `mul.lproj/Main.xcstrings`
  ("Слушать"), and the removed segmented control's two stale `segmentTitles` entries
  deleted. Verified by running the app under `-AppleLanguages "(ru)"`.

**Overflow, fixed once instead of three times (2026-07-20, owner review).** The owner's
on-device screenshots showed each exercise screen failing *differently*: Phonetics
overlapped its answer buttons, Test and Dictation pushed them under the tab bar, and
Phonetics clipped "главный докладчик" even at the **default** text size. That divergence
is the tell for TD-20 — the same layout lives in three storyboard scenes, so nothing
forces the three to fail the same way, and a per-scene fix diverges too. Two root causes,
each now fixed in one place:

- **Labels clipped instead of shrinking.** `UILabel` only honours
  `adjustsFontSizeToFitWidth` when `numberOfLines == 1`; at two lines it wraps and then
  *clips*. `LWWordLabel` is now single-line, so it always scales down to fit and nothing
  is ever cut off.
- **No overflow strategy.** A pinned `UIStackView` has no answer when content outgrows the
  screen — it compresses arranged views past their constraints until they overlap.
  **`ScrollableContent.wrap`** (`Shared/DesignSystem/ScrollableContent.swift`) is the single
  implementation: it re-parents a content stack into a scroll view pinned to the safe area,
  with a `defaultHigh` "at least one screenful" constraint so short content still fills the
  view and only taller content scrolls. Used by **all four** screens — the three exercise
  scenes and the chooser, which replaced the one-off version written for it earlier.
  Dictation keeps keyboard avoidance by handing the returned bottom constraint to
  `UnderKeyboardLayoutConstraint` instead of the stack's own.
- Also removed: three leftover `height ≤ 100` caps on the answer rows (`TKy-er-IOr`,
  `fG9-GM-efN`, `c2Y-n1-Bdl`). They existed to rein in the old slabs and fought
  `LWButtonRow`'s vertical mode, forcing the overlap. `LWButton` owns its height now.

**Second overflow round (2026-07-20, owner review).** Three more defects, two root causes:

- **The word vanished at extra-large text**, and the chooser drew its direction button over
  the "include learned words" row. Cause: `ScrollableContent` pinned content height *equal*
  to one screenful at `defaultHigh` (intended to make short content fill the view) **as well
  as** `greaterThanOrEqual`. The `greaterThanOrEqual` alone already does that job; the
  equality actively pulled tall content back down to one screen, and the arranged subviews
  compressed until they overlapped — the word label first, because it had the lowest
  compression resistance. The equality is gone: **never constrain scrolling content to fit.**
  `LWWordLabel` also moved to `.defaultHigh` compression resistance — expanding is welcome,
  disappearing is not, least of all for the word being studied.
- **"В словаре" was shorter than its neighbours on Phonetics only.** Test's utility row was
  `fillEqually`, while Dictation's and Phonetics' were plain `fill` with hand-drawn equal-
  *width* constraints — which say nothing about height once `LWButtonRow` stacks a pair
  vertically. `LWButtonRow` now sets `distribution = .fillEqually` itself, so the row decides
  rather than three scenes. (Another TD-20 symptom: the same row, three different settings.)
- **Bar appearance is now consistent as a side effect.** The app configures only bar
  `tintColor`; backgrounds are system default, and UIKit picks `scrollEdgeAppearance`
  (transparent) when it tracks a scroll view. That is why the Words tab's bars were
  transparent with content flowing under while the exercise screens' were not — the others
  had no scroll view. Now that every screen does, all of them get the iOS 26 treatment:
  floating glass controls, no bar background. Verified by comparing the Words and Learning
  nav bars.

**Verified:** all targets build; **38/38 tests pass**, including the storyboard-driven
`ExerciseScreenAppearanceTests` that drives the modified `WordTest` scene through a real
appearance cycle. All four screens checked on the iOS 26.5 simulator, and button positions
confirmed pixel-identical across successive words. **Not verified:** the iOS 12–14 renderer
(TD-8 — no sub-15 simulator on Xcode 26); the `purpose == .prominent` style is `.tinted()`
rather than `.filled()` because the chooser stacks three of them — one line to flip if a
screen ever earns a single dominant CTA. New `Listen` / direction strings need RU
translations in `Localizable.xcstrings` (same deferral as TD-14).

## TD-21 — Search bar shows through the Words nav bar — **resolved (2026-07-20)**

Seen on the iOS 26 sim while checking bar consistency: text rendered *behind* the
"Настройки" bar button on the Words tab. **The first diagnosis here was wrong** — it was
recorded as a nav *title* colliding with the bar buttons, and no title is set on that
screen. The text was the **search bar placeholder** ("Search words in sets" / "Искать
слова в наборе").

Root cause: `setupSearchController` installed the search bar as `tableView.tableHeaderView`
— the pre-iOS 11 pattern — and hid it by nudging `contentOffset` down by its height. That
worked while navigation bars were opaque. Under iOS 26 the bar is transparent and content
flows beneath it (see TD-19), so the parked search field showed *through* the bar and
collided with the floating "Настройки" / `+` / "Править" capsules.

**Fix:** hand the search bar to `navigationItem.searchController` and replace the offset
hack with `navigationItem.hidesSearchBarWhenScrolling`. UIKit then places and collapses it
— on iOS 26 it gets its own row below the buttons, revealed by pulling down. Both APIs are
iOS 11+, so no availability check at the 12.1 floor, and the `contentOffset` fiddling is
gone. Verified on the sim: bar buttons clear, search legible and functional when revealed.

## TD-22 — Dictionary enrichment: prefill terms from open lexical data

When adding a word, the app could prefill transcription, part of speech, forms, senses
and sense tags. **Not** from the iOS system dictionary: `DCSCopyTextDefinition` is
macOS-only, `UIReferenceLibraryViewController` displays but returns no data, and the
owner's prior experience shows Apple resists reflection-based extraction. Researched
sources (2026-07-23):

- **[kaikki.org](https://kaikki.org/dictionary/rawdata.html) (wiktextract)** — the
  strongest fit: per-language machine-readable Wiktionary extracts (JSON Lines) with
  lemmas, **inflected forms**, translations, **IPA + audio**, senses with topical and
  register annotations — the exact shape of `Term`/`WordForm`/`Tag`. Updated
  weekly; licensed CC BY-SA/GFDL (attribution + share-alike apply to redistributed
  content; owner: not a problem). Downloadable, so enrichment is **offline and
  private** — no query ever leaves the device, which matches the app's privacy
  constraint. **Sense-to-sense (owner question, 2026-07-23): yes** — Wiktionary's
  translation tables are gloss-headed per sense, and wiktextract preserves this: each
  translation entry carries a `sense` field naming the gloss it belongs to, and each
  sense carries `tags` ("colloquial", "chemistry", …) that map straight onto our `Tag`
  rows. Caveat: the linkage is by gloss *text*, not stable IDs, and is occasionally
  broken in the source; DBnary is the same data already modelled as OntoLex-Lemon
  (sense-to-sense `vartrans`) if stricter structure is ever wanted.
- **[Wikimedia REST definition endpoint](https://www.mediawiki.org/wiki/Wikimedia_REST_API)**
  — structured Wiktionary definitions on demand; experimental, en.wiktionary only.
- **[dictionaryapi.dev](https://dictionaryapi.dev/)** — free, keyless, community-run;
  English-centric, no uptime guarantees.
- **[Merriam-Webster API](https://dictionaryapi.com/)** — free non-commercial tier
  (1000 queries/day), English + Spanish; strongest quality for English only.
- **A macOS companion app** (owner's suggestion) — `DCSCopyTextDefinition` is public
  there; enrichment done on the Mac would reach iOS via CloudKit sync. Long-term option.

**Privacy note:** online lookups leak the user's vocabulary to a third party; prefer
the downloadable-dataset route, or make lookups explicitly user-initiated per word.
**Discharge:** when the word-editing UI is built (post-TD-13), start with a kaikki
subset for the user's language pairs; keep the fetch behind a protocol so sources can
be added. Blocked on iteration 2+ of TD-13.

## TD-20 — Exercise screens are triplicated in both code and storyboard

`WordTestViewController`, `WordDictationController` and `WordPhoneticsViewController` are
near-copies: `startRound`, `nextTapped`, `afterAnswer`, `showAnswer`, `askQuestion`,
`prepareForNextQuestion` and both button actions are the same ~120 lines three times, and
each screen has its own storyboard scene repeating the same progress-view / word-label /
button-rows layout. Only ~110 lines are genuinely unique (Phonetics' speech recognition,
Dictation's text matching, the exercise code `"L"`/`"D"`/`"P"`, and which view receives
answer feedback).

**Cost — demonstrated, not theoretical (2026-07-20).** The TD-19 layout pass had to be
applied to three scenes, and the three then failed *differently* on device: overlapping
buttons on Phonetics, buttons under the tab bar on Test and Dictation, clipped text on
Phonetics at the default size, and three different leftover height caps (100/150/200).
A single shared layout would have made one fix cover all three — and would have made one
*bug* obvious instead of three subtly different ones.

**Discharge.**
1. **`ExerciseSession`** — **done (2026-07-20)**. `Model/ExerciseSession.swift` owns the
   round: the shuffled queue, per-exercise scoring, progress, the skip rule and the
   round-end save. The three screens keep only their views — `startRound` is one line,
   `nextTapped` is four, and `afterAnswer` is feedback plus one call. **−53 net lines across
   the three controllers**, and the triplicated logic is gone.
   - **15 new tests** (`ExerciseSessionTests`) run without a storyboard or a view
     controller, which is the point of the extraction. They pin down what the copies only
     implied: `reachedKnownLevel` fires *only* on the crossing answer (so the level-up
     spray can't repeat), skipping never scores, an exercise scores only its own tally,
     and progress is 0 for an empty set rather than the `1.0 / 0` the screens computed.
   - **`Storage.shownWords` removed.** It was a scratch buffer living in the persistence
     protocol — never written to `UserDefaults`, used only by these three screens. With the
     session owning its own `finished` array it was orphaned, so it is gone from
     `WordStore`, `Storage` and `UserDefaultsWordStore`.
   - A latent crash went with it: Dictation and Phonetics indexed `wordsInTest[0]` from
     text-field and speech-recognition callbacks that can outlive the last word;
     `session.currentWord` is an `Optional` and the call sites now guard.
   - **New test-isolation fix:** `.serialized` orders tests *within* a suite, not across
     them, so the new suite raced `WordAndStatTests` over the global
     `maxKnownLevelPreference` — passing alone, failing in the full run. Both now nest
     under one serialized `MaxKnownLevel` parent, which also shares the pinning helper.
2. **One exercise screen** — **done (2026-07-20)**. `Features/Exercise/ExerciseViewController.swift`
   assembles it once, in code: progress view, word, answer surface, utility row, answer row,
   optional accessory, wrapped by `ScrollableContent`. The three storyboard scenes are gone
   entirely, so the layout cannot diverge again. Prompt/answer text and speech languages come
   from `LanguagePair`, so no screen spells out `foreignToNative ? firstWord : secondWord`.

   **Composition, not an abstract base (owner review).** The first cut was an abstract
   `ExerciseViewController` whose subclasses overrode members guarded by
   `fatalError("must override")` — runtime traps for something the compiler can enforce.
   Now the screen is `final` and is *given* what differs:
   - **`ExerciseAnswerSurface`** — how an answer is taken and shown. **`ExerciseScreen`** is
     the narrow back-channel a surface receives (current word, languages, `answer(_:)`,
     `presentAlert`): it can read the question and submit an answer, not drive the round.
   - The three subclasses became **`SelfAssessedAnswerSurface`**, **`TypedAnswerSurface`**,
     **`SpokenAnswerSurface`** — plain objects, so they are testable without a view
     controller, which a subclass never was.
   - `init(exercise:answerSurface:title:)` with `init(coder:)` marked
     `@available(*, unavailable)`. Nothing abstract to instantiate, no `fatalError` override
     guard anywhere.
   - *Why not a protocol with default implementations:* protocol extensions have no stored
     properties, and the screen owns real state (session, languages, container, buttons). A
     protocol could only declare them, pushing them back into each conformer and reinstating
     the triplication. Extension-only members are statically dispatched too, so a conformer
     "overriding" a default would be silently ignored — a worse trap than the one removed.
   - Injection means these screens are no longer storyboard-instantiated (`init(coder:)`
     takes no arguments, and `instantiateViewController(identifier:creator:)` is iOS 13+,
     above the 12.1 floor). The chooser pushes `ExerciseViewController.make(_:)`.
   - **Bug fixed on the way:** the "no words to study" guard lived in `prepare(for:)`, which
     **cannot cancel a segue** — the alert appeared and the empty exercise was pushed
     underneath it anyway. It is an early return in the button action now.
   - Exercise titles and button labels moved from storyboard object-id keys to
     `NSLocalizedString`, so their es/ru units were migrated into `Localizable.xcstrings`
     rather than lost with the scenes.

**Outcome taxonomy adopted (2026-07-20).** `ExerciseSession.answer` now takes a
`ReviewOutcome` (`Model/ReviewOutcome.swift`) rather than `isKnown: Bool` — the exact
"outcome conflation" [ProgressModel](ProgressModel.md) lists as its second hard limit, which
the first cut of the extraction reproduced. The screens already *had* the distinction and
were discarding it: Dictation's live compare is exact (`.correctVerbatim`) while its submit
path runs `match3` (`.correctJudged`), Phonetics' recognition is judged, and the buttons are
self-assessed. Only `isPositive` reaches today's scoring; the rest is carried so TD-13's
event log receives real evidence strength from day one. `sessionID` needs no work —
`ExerciseSession` *is* the sitting.

**`LanguagePair` seam (2026-07-20).** See [Design](Design.md) → "a language pair belongs to a
word set". `Model/LanguagePair.swift` resolves the pair and direction in one place — today
from the global preferences, at TD-13 from the word set. It also gives the exercise screens
`prompt(for:)` / `answer(for:)` / `promptLanguage` / `answerLanguage`, which is what let the
scattered ternaries collapse.

Verified: all targets build; **53/53 tests pass**; a full Learning round played on the iOS
26.5 sim — progress tracks, the round commits and pops back, and the chooser reports the
set unchanged.

## Appendix: feature-first mapping (TD-1) — **executed for source (2026-07-17)**

Target layout per `uikit-app-structure`, now the actual on-disk layout for `.swift` files
(⚠ = shared with Widget/Action; its `membershipExceptions` path was updated). `App/` also
holds `AppRoot.swift` (the shared composition root). Resources are **not** yet moved (see
TD-1 above).

```
LearnWords/
├── App/                     # composition root
│   ├── AppDelegate.swift
│   ├── SceneDelegate.swift
│   └── TabBarControllerHome.swift        # root container
├── Model/                   # value types + domain logic
│   ├── WordsModel.swift ⚠
│   ├── Storage.swift ⚠
│   ├── Settings.swift ⚠
│   └── Translation/AvailableLanguage.swift
├── Controllers/             # shared app logic (one source of truth per concern)
│   ├── SpeechManager.swift          # → rename SpeechController (TD naming pass)
│   └── PermissionManager.swift      # → rename PermissionController
├── Features/
│   ├── WordSets/    WordSetsTableViewController.swift
│   ├── Words/       WordTableViewController.swift, WordTableViewCell.swift
│   ├── Dictation/   WordDictationController.swift
│   ├── Phonetics/   WordPhoneticsViewController.swift
│   ├── Test/        WordTestViewController.swift
│   ├── Search/      SearchWordViewController.swift
│   ├── ExerciseChooser/ ExersizeChooserViewController.swift
│   └── Translation/ TranslationV.swift
├── Shared/
│   ├── DesignSystem/ GradientButton.swift, KDCircularProgress.swift
│   ├── Keyboard/     UnderKeyboardDistrib.swift
│   ├── AppConstants.swift ⚠
│   ├── Debug.swift ⚠
│   ├── General.swift, gotoAppSettings.swift
│   └── Extensions/  String+.swift ⚠, UserDefaults+Codable.swift ⚠,
│                    UIImage+backport.swift, UIContextualAction+ConvenienceInit.swift
├── Resources/       Assets, Settings.bundle, PrivacyInfo.xcprivacy, *.storyboard
└── Info.plist
```

Slice order (build green after each): **App/ → Model/ → Shared/ → Controllers/ → Features/**.
Move the ⚠ shared files last and in isolation, updating their pbxproj exception paths first.

## TD-23 — Dead KDCircularProgress attributes left in the storyboard — **resolved (2026-07-27)**

The word cell's ring view changed `customClass` to `ProgressRing` (TD-13 iteration 5), but
its eight `userDefinedRuntimeAttribute` entries still name KDCircularProgress's
IBInspectables — `angle`, `startAngle`, `progressThickness`, `trackThickness`,
`gradientRotateSpeed`, `glowAmount`, `trackColor`, `IBColor2`. Each one raises
`setValue:forUndefinedKey:` **per cell, on every creation**. **Cost:** eight console lines
per row on every scroll, and the noise hides real messages — the constraint break that
opened TD-17 was found by reading exactly this console. Non-fatal. **Discharged** with the meaning editor: the eight entries are gone from
`Main.storyboard`, and the console is quiet on scroll again.

## TD-24 — Extension bundle versions drift from the app's

`CFBundleVersion` is `1` on the app extensions and `7` on the host app, which
`ValidateEmbeddedBinary` warns about on every build and **App Store Connect rejects at
submission**. **Cost:** invisible until the first upload, then a blocked release.
**Discharge:** drive all four targets' `CURRENT_PROJECT_VERSION` from one place — a shared
`.xcconfig`, or `$(inherited)` from the project level — rather than per-target literals.

## TD-25 — A nil UUID would trap on read, if anything ever inserted one

`@NSManaged var id: UUID` is non-optional Swift over an attribute the model marks optional
(CloudKit's price, TD-13 iteration 4). Reading nil through a non-optional `@NSManaged`
accessor traps, and `StoreDeduplicator` sorts by `id` to elect a convergent winner, so a
nil would also break the ordering that stops two devices deleting each other's survivor.

**Filed initially as "a peer might send nil"; that was overstated** (owner's question,
2026-07-27). CloudKit's import inserts managed objects normally, so `awakeFromInsert` runs
and assigns an id before any record field is applied, and an absent CKRecord field is not
applied over it. Optional in the *schema* does not mean nullable in *practice*: every
insert path in the codebase assigns one.

The concrete way to break it is **`NSBatchInsertRequest`, which bypasses
`awakeFromInsert` entirely.** There is none today — but `Lexicon.addSenses` exists
precisely to make bulk import one transaction, and it is exactly the method someone would
later convert. **Cost:** nil today, crash-grade the day that conversion happens.
**Discharge:** a repair pass in `StoreDeduplicator` — which already runs after every remote
merge — assigning an id to any row missing one before it sorts. That turns a future trap
into self-healing, in the file that already owns post-merge repair. Cheap enough to do
before the two-device test; not urgent enough to block it.

## TD-26 — Orphan collection has no way to run

`deleteOrphanedSenses` and `deleteOrphanedTerms` are "explicit, never automatic" by design
(docs/Design.md), and nothing in the app is that explicit thing: no screen calls either.
Rows accumulate — a meaning removed from its last set, a synonym unlinked in the editor —
and only a test has ever collected them. **Cost:** slow growth of dead rows, which sync
then copies to every device. **Discharge:** one row in Settings ("Clean up unused words"),
reporting how many it removed, so the user chooses rather than the app guessing.

## TD-27 — Constraint break from the system dictionary's own navigation bar

Under iOS 26, opening the system dictionary logs, two or three times per presentation:

```
"…ButtonBarButtonVisualProvider…Button.width <= 67.6667 (active)",
"…'fittingSizeHTarget' …Button.width == 123 (active)"
```

**It is `UIReferenceLibraryViewController`'s own chrome, not ours.** The evidence:

* The break brackets the presentation of `UIReferenceLibraryViewController` in the owner's
  log, and appears nowhere else in the app.
* The screens involved (`Add word to study`, `Translation`) declare **no bar button items**
  — only titles — so no button of ours is being measured.
* It does **not** reproduce on the simulator at any text size in either language, because
  the simulator has no dictionaries installed: `UIReferenceLibraryViewController` shows the
  "Add Dictionaries" prompt instead of the real view, whose bar carries the long "Manage"
  and dictionary-name buttons that overflow iOS 26's floating bar allowance (~62–68 pt
  against a 117–123 pt fitting width).

UIKit breaks the weaker constraint and truncates, so it is cosmetic and self-healing. There
is no API to size another process's bar buttons. **Discharge:** nothing to fix in this app;
if it becomes intolerable, file it with Apple (include that a dictionary must be installed
to reproduce). Halved in practice by fixing the double presentation that logged it twice —
see below.

## TD-28 — `SearchWordViewController` is a massive view controller

~600 lines doing search, suggestion generation, dictionary lookup, language switching,
segue routing and store writes. It is the one screen the TD-13 redesign never reached, and
it shows: the add-word flow's only commit path was the keyboard's Return key until
2026-07-27, because nothing about the screen makes its entry points visible.

**Cost:** every bug found in the add-word flow so far has been a coordination bug hiding in
its size — no `didSelectRowAt`, the dictionary presented twice, three `debugLog` lines per
keystroke. **Discharge:** the `uikit-app-structure` split — suggestions into a data-source
object, dictionary lookup into the shared helper it already half-lives in, store writes
behind `Library`, leaving the view controller to structure navigation and interpret user
action. A fork, not a drive-by.

## TD-29 — A `UISwitch` cannot be driven by the simulator harness

Synthetic taps and drags from the agent's simulator tooling do not operate a `UISwitch`:
the touches reach the window (`shouldSend: 0; systemGestureStateChange: 1` in the UIKit
event log), a drag is claimed by the back gesture, and a switch that predates the change —
"Pronounce answers" — is equally unresponsive. `simctl privacy` has no notifications
service either, so notification permission cannot be granted headlessly.

**Cost:** any feature gated behind a switch is unverifiable end-to-end without a human,
which is how fork G shipped its reminder path proven only to the derivation boundary.
**Discharge:** drive these through a UI test with `XCUIElement.switches[...].tap()`, which
uses a different event path, or expose a launch argument that presets the preference for a
screenshot pass. Until then, say plainly which half of such a feature is verified.

## TD-30 — The ring's Dynamic-Type size is overridden by the cell

`ProgressRing` reports a Dynamic-Type-scaled `intrinsicContentSize`, but the word cell's
fixed 44×44 constraints win, so the ring does not grow with the text (ProgressModel R6,
half-done). **Cost:** an accessibility-size user gets large text beside a fixed-size ring.
**Discharge:** relax the cell's constraints to `greaterThanOrEqual` and let the ring size
itself — belongs with the next rebuild of the words screen, since that is the file that
owns the constraints.
