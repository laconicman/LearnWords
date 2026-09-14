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

These files are compiled into the **WordWidgetExtension** and/or **ImportAsDictAction** targets via
`membershipExceptions` (paths relative to the synchronized root `LearnWords/`), now at
their post-reorg paths. Since TD-13 iteration 3 the widget list is the store rather than
the old model: `Controllers/Library.swift`, `Model/CoreData/LearnWords.xcdatamodeld`,
`Model/CoreData/LWPersistence.swift`, `Model/CoreData/ManagedObjects.swift`,
`Model/Lexicon/LanguageCode.swift`, `Model/Lexicon/Lexicon.swift`,
`Model/Lexicon/LexiconSeed.swift`,
`Model/Lexicon/LexiconTypes.swift`, `Model/Practice/Exercise.swift`,
`Model/Practice/LanguagePair.swift`, `Model/ReviewOutcome.swift`, `Model/Settings.swift`,
`Shared/AppConstants.swift`, `Shared/Debug.swift`, `Shared/Extensions/String+.swift`,
`Shared/Extensions/UserDefaults+Codable.swift` (the widget target);
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

## TD-4 — Widgets: WidgetKit (iOS 14+) + legacy Today (iOS 12–13) — **implemented (2026-07-18); Today half deleted (2026-09-14)**

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

**The Today half is deleted (2026-09-14).** Its bundle reported `MinimumOSVersion 12.1` in
the 1.2.2 archive and could not stay below the new floor. Raising it was one build setting;
the owner chose deletion instead ([TASK-iOS15-migration](TASK-iOS15-migration.md) § Phase 0),
because `NCWidgetProviding` is deprecated in favour of WidgetKit and the iOS 12–13 devices it
was kept for can no longer install the app. It went working, not broken (TD-60). The six files,
the target and both of its `membershipExceptions` sets are gone; `WordWidgetExtension` is the
only widget, and remaining item (c) goes with the extension.

## TD-4 (historical) — Deprecated Today extension (`Widget/`) — **removed (2026-09-14)**

`TodayViewController` uses `NCWidgetProviding`, deprecated since iOS 14 and unsupported
on modern iOS. **Cost:** dead/again-un-shippable extension; App Store review risk.
**Discharge:** migrate to WidgetKit, or remove the target. **Both, in the end:** WidgetKit
arrived on 2026-07-18, and the target was removed on 2026-09-14 (TD-4 above).

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

## TD-7 — iOS 12 availability audit — **closed by the iOS 15 floor (2026-09-14)**

**Swift code: clean.** A clean build at the 12.1 floor succeeds, and Swift treats any
unguarded newer API as a hard *error* — so a green build proves there are no unguarded
iOS 13+ API uses. (Spot-checked: `.label`, `systemIndigo`, `UIImage(systemName:)` are all
inside `#available`; `systemOrange` is iOS 7+.) No action needed here.

**Closed (2026-09-14).** There is no iOS 12 left to audit. Forty-one live guards gated 15.0
or lower: four went with the dual life cycle and 37 in the sweep after it, and a green build
at 15.0 is this entry's own proof that none of them protected anything newer. Five remain,
gating 16 and 17. The migration brief had counted 45 dead and 11 surviving by text search,
and the gap is TD-60's lesson again: four of its 45 and seven of its 11 sit inside
commented-out code (`SearchWordViewController`, `TranslationV` and `AvailableLanguage` are
commented out whole), and the search never reached `WordWidget/`, where the fifth survivor
is. Commented-out code was left as it is. The proof still covers availability only; TD-46 is
why it says nothing about linkage.

## TD-11 — Storyboard has iOS 13+ UI dependencies that break on iOS 12 — **closed by the iOS 15 floor (2026-09-14)**

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

**One control was not part of that bargain — fixed 2026-09-10.** "Text-only" assumes there
is text. `WordInputViewController`'s dictation button is the field's `leftView`, sized to the
minimum touch target and carrying **no title**, so a `nil` symbol left a 44pt control that
was invisible, unlabelled and indistinguishable from the field's padding — on the
add-a-word screen, which is the first thing a new learner uses. It still worked if you
happened to tap it. It now falls back to a 🎤 when there is no symbol. The accent/grey/red
state stops showing at the floor, since an emoji takes no tint; `accessibilityLabel` already
states that in words and it was a second cue, never the only one.

**And the iOS-12 icon path *is* verifiable, contrary to what TD-8's blanket claim implies.**
Forcing `UIImage.systemImage` down its `else` branch (`if #available(iOS 13, *), false`) and
running on a modern simulator renders exactly what iOS 12 renders for every symbol in the
app, because that branch is what iOS 12 executes. It costs one build and needs no old
toolchain. That is how this defect was found, and it is worth running before any release
that claims the floor: what it cannot check is lifecycle, storyboard semantic colours and
system-control behaviour, which still need the Xcode 15 pass.

**Closed (2026-09-14).** Nothing below iOS 13 can install the app, so nothing in the
storyboard is unsupported anywhere it runs. What this entry built was kept rather than
unwound: the named asset colours resolve on every OS, and the dictation button's 🎤 now stands
in for a symbol name the running OS lacks rather than for an OS without symbols.
`UIImage.systemImage` lost its iOS 12 branch and kept its array form, which falls back across
names that exist only on some OS versions; the word list's reset action depends on that
today. The eleven `.symbolset` assets were not touched: whether any still carries a name the
system does not provide wants its own audit ([TASK-iOS15-migration](TASK-iOS15-migration.md)
§ Phase 0), not a bulk delete.

## TD-8 — iOS 12 path is unverifiable on Xcode 26 — **confirmed against Apple's own numbers (2026-08-02)**

Apple's [Xcode system requirements](https://developer.apple.com/xcode/system-requirements/)
now state it outright: Xcode 26 supports **on-device debugging for iOS 15 or later**, and a
deployment-target range of **iOS 15–26.5**. So the legacy path cannot be run from the
current toolchain at all — not a tooling inconvenience, a stated limit.

**Two consequences worth separating.**

*Verification* needs an older Xcode, and that needs an older Mac. **Xcode 15.2** is the last
release that runs on Ventura (15.3+ requires Sonoma) and it debugs devices back to iOS 12.
It cannot be run on Tahoe: Xcode 15 is unsupported there, and even Xcode 16.2 has
[reported launch failures on 26.0](https://github.com/XcodesOrg/XcodesApp/issues/763). The
Ventura machine is therefore not a convenience — it is the only route.

*The shipped binary is a separate problem.* The project builds at
`IPHONEOS_DEPLOYMENT_TARGET = 12.1` under Xcode 26 and always has, but 12.1 is **below the
range Apple documents for that Xcode**. It is tolerated, not supported — the same situation
reported for Xcode 16 accepting iOS 12 against an official iOS 13 minimum — and Xcode 27
already documents a floor of 15.0. A toolchain update can withdraw it without warning.

**This makes the floor a product decision, not just a debt item.** Either the project keeps
12.1 knowing it rests on undocumented tolerance and an old Mac, or it raises the floor to
iOS 15 and gains Swift Concurrency, `context.perform` async and the actor-based
confinement recorded in [Design](Design.md) — the whole list of things currently deferred
"until the floor allows it". See TD-40 and the concurrency decision.

**The floor now has a measured price** (2026-08-12). TD-52 timed the cost of scoring a
library and every millisecond of it is *main-thread* time: ~370 ms for 1,000 meanings, ~1.9 s
for 2,000. Reads are pinned to the main queue because `async` does not exist at 12.1 —
`LWPersistence.write`'s own comment says so — so the alternatives are a callback twin of the
read API (TD-56) or raising the floor and moving the whole of `Lexicon` to `context.perform`
async, which is the same work done once and properly. This is the first item where the floor
costs the *user* something rather than costing the project verification effort.

Xcode 26 ships no simulator below iOS 15 and won't connect sub-15 devices, so the iOS 12
branch (`AppDelegate` window + `application(_:open:)`, `UIMainStoryboardFile`) **cannot be
run or tested** on the current toolchain. **Cost:** the legacy path can regress silently;
"supports iOS 12" is an unverified claim. **Discharge:** keep an **Xcode 15** install; before
releases that touch launch/lifecycle/URL handling, smoke-test launch + the
`learnWords://shareaction` deep link on an iOS 12 simulator or device there. The modern-SDK
App-Store build (Xcode 26+) and the iOS-12 verification build are two separate steps.

**The Xcode 15 project is stale — found 2026-09-10.** `LearnWords-Xcode15.xcodeproj` has no
synchronized folders (an Xcode 16 feature), so it lists sources one by one, and it lists none
added since 2026-08-07: `ProgressCache`, `SetSummary`, `MemoryWording`, both statistics
screens, `BarStrip`, `SenseEntry`, `Exercise+Title`. Files it *does* compile use those types —
`WordTableViewController` calls `ProgressCache.shared` and builds a
`SenseStatisticsViewController` — so it cannot compile as it stands. **Verified:** the
references exist and the files are absent. **Inferred, not run:** the build failure itself.
Its signing team and weak-link flags were brought in line with the main project anyway (PR #14),
so a resync starts from correct settings. **Discharge:** before any iOS 12 pass, add every
source the main project compiles, or regenerate this project from the main one — keeping it
by hand has now failed silently for five weeks.

## TD-9 — Divergent doc copies — **resolved (2026-07-17)**

Was: `docs/*.md` (current) and `LearnWords/Documentation.docc/*.md` (older, unfilled
TEMPLATE scaffold from 1880e5d) had diverged. The obsolete `Documentation.docc` catalog
was deleted; **`docs/*.md` is the single source of truth.** If a rendered DocC catalog is
wanted later, regenerate it from `docs/` (per `repo-init`) rather than hand-maintaining two.

## TD-10 — ImportAsDictAction targets iOS 14, not 12 — **closed by the iOS 15 floor (2026-09-14)**

*(Corrected 2026-07-18: an earlier version claimed the Widget target was also at 14 — wrong.
The Widget (Today) target sets no explicit deployment target and inherits the project-level
**12.1**; only **ImportAsDictAction** pins `IPHONEOS_DEPLOYMENT_TARGET = 14`.)*

ImportAsDictAction was set to iOS 14 as a deliberate quick fix (owner: no workaround found in
reasonable time), so on iOS 12–13 the share-import flow is unavailable — and with it the
`learnWords://shareaction` deep link (TD-3) below iOS 14. **Cost:** the import feature is
missing on the oldest devices. **Discharge (deferred by owner):** revisit once structure
settles — either find the workaround and lower to 12.1, raise consciously, or accept as-is.

**Closed (2026-09-14).** The floor is 15.0 for every target ([Design](Design.md) § *the floor
is iOS 15*), so the extension now installs everywhere the app does, and share import and the
`shareaction` deep link with it. The workaround was never found and is no longer wanted. The
extension's `IPHONEOS_DEPLOYMENT_TARGET = 14` was deleted rather than raised: it inherits the
project's value, as every shipped target now does, so the next floor change cannot leave one
bundle behind.

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

## TD-20 — Exercise screens are triplicated in both code and storyboard — **resolved (2026-07-20)**

**Reconciled 2026-09-02.** The register said "open" for six weeks after the work landed.
`WordTestViewController`, `WordDictationController` and `WordPhoneticsViewController` no
longer exist; one `ExerciseViewController` composes `ExerciseAnswerSurface`, and the sitting
moved into `PracticeSession` (which replaced the branch's `ExerciseSession` outright — see
its file comment for why the redesign went further than the extraction). Verified rather than
assumed: `git cherry` reports every commit of `feature/button-design-system` as already
present in `main`, and none of the three controllers is in the tree. That branch has been
deleted.

The original entry follows.

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

## TD-24 — Extension bundle versions drift from the app's — **resolved (2026-08-07)**

`CFBundleVersion` is `1` on the app extensions and `7` on the host app, which
`ValidateEmbeddedBinary` warns about on every build and **App Store Connect rejects at
submission**. **Cost:** invisible until the first upload, then a blocked release.
**Discharge:** drive all four targets' `CURRENT_PROJECT_VERSION` from one place — a shared
`.xcconfig`, or `$(inherited)` from the project level — rather than per-target literals.

**It was marked "not reproducible" on 2026-07-29. It reproduced.** An ordinary
`xcodebuild` of the app scheme printed:

```
warning: The CFBundleVersion of an app extension ('8') must match that of its
containing parent app ('9').
```

A debt item recorded as imaginary is worse than one recorded as open: nobody looks again,
and this one only surfaces on upload. Whatever the 07-29 check was, it did not read the
build log of a full app build — the warning comes from `ValidateEmbeddedBinary`, which runs
in the *host app's* target while embedding the `.appex`, so building the extension scheme
alone never shows it.

**Also understated.** The entry named only `CFBundleVersion`; `MARKETING_VERSION` had
drifted too (1.2.1 against 1.2.2), and App Store Connect rejects a
`CFBundleShortVersionString` mismatch just as readily.

**One target was at fault.** Everything else already inherited the project level; only
`WordWidgetExtension` declared its own literals, in both configurations:

| target | `CURRENT_PROJECT_VERSION` | `MARKETING_VERSION` |
|---|---|---|
| project level — app, Widget, ImportAsDictAction | 9 | 1.2.2 |
| `WordWidgetExtension` (before) | 8 | 1.2.1 |
| Unit Testing Bundle | 1 | 1.0 — never submitted, left alone |

**Fixed by deletion, not by re-syncing.** The first pass bumped the literals to 9 / 1.2.2,
which silences today's warning and leaves the debt exactly where it was — two numbers that
must be remembered together, in a file nobody re-reads, drifting again at the next release.
The four overrides are gone, so the extension inherits. Verified: the app scheme builds
with no `ValidateEmbeddedBinary` warning.

**Note for the verification branch:** `LearnWords-Xcode15.xcodeproj` carried the same
overrides and needed the same deletion. Two projects means build-setting fixes land twice
until one of them goes away (TD-45).

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

## TD-26 — Orphan meanings — **resolved (2026-08-01)**

Deleting a word took its meaning out of the set without deleting it, on the reasoning that
its review history was evidence of work done. Nothing collected the orphans, so they
accumulated silently — and the duplicate hint eventually surfaced one, being the first
screen to look words up by *word* rather than by set.

**Resolved by deciding the retention was never justified** (owner). See
[Design](Design.md) § "a meaning nothing can reach is deleted". Removal now deletes when the
set was the last one holding the meaning; `deleteOrphanedSenses` collects what other paths
strand and no longer spares those with history; `Library.prepareForLaunch` runs it once per
launch.

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
action.

**Partially discharged (2026-07-27).** Two of the four responsibilities are out and are now
shared rather than duplicated:

* `WordSuggestions` — completions and per-language recents, as a testable value.
* `WordInputViewController` — the entry screen itself, reused by the meaning editor.

**Remaining:** the controller still owns segue routing, the `SearchedObject` two-mode enum
and store writes, plus roughly 120 lines of commented-out predecessors. The cheaper order
now is to rewrite it *onto* `WordInputViewController` — two pushes of one reusable screen,
one for each half of a pair — rather than cutting more out of it.

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

## TD-31 — Speech recognition left its own audio-session cleanup to callers — **resolved (2026-07-27)**

`DictationController` extracted the recogniser, but `SpokenAnswerSurface` retains its own
copy of the start/stop button logic and its own `AVAudioSession` handling around playback
(TD-15's fix). The two now express the same lifecycle in two places, which is exactly the
condition that produced TD-15 — speech silently dead after a recognition round.

**Cost:** a change to session handling has to be made twice, and the second site is the one
with the history of getting it wrong.

**Closed the same day it was filed, and it had already recurred.** `DictationController.stop`
deactivated the session while leaving the category at `.playAndRecord`. That is exactly the
state `SpeechManager.ensureAudioSession` declines to touch:

```swift
guard session.category != .playback && session.category != .playAndRecord else { return }
```

So nothing would have reactivated it, and the synthesiser would have rendered empty buffers
into a dead session — TD-15's symptom, reintroduced by the extraction meant to prevent it.

`SpokenAnswerSurface` is now 122 lines from 250 and owns no audio state;
`releaseSessionToPlayback` is the single copy of the handoff. The "no test asserts it"
worry is also gone: `AudioSessionHandoffTests` pins the contract, and both of the cases
that matter were **checked to fail against the old code** before being kept — a regression
test that has never been red is only a hope.

## TD-32 — Reminders cannot be tested without waiting for a due date

A correct schedule is often an *empty* one: after a practice round nothing comes due for a
day or two, so no request is created and nothing arrives. Combined with a bug that
suppressed foreground delivery, this made the first device test read as total failure when
half of it was working as designed.

Settings now names the next reminder, which turns silence into information. What is still
missing is a way to see one *arrive* without waiting.

**The manual procedure, using only real features:** reset one word's progress (swipe right
on it in the word list) so something is due now, then set the reminder time a couple of
minutes ahead. A request for today is then created and delivers.

**Cost:** the whole feature is unverifiable in a single sitting without that trick, which
nobody would guess. **Discharge:** a UI test that pins the clock and asserts the pending
requests, which also closes TD-29's inability to drive the switch. Not a debug button —
the app should not grow a control that exists only to prove itself.

## TD-33 — Localization trails features — **recurring; re-opened 2026-07-29**

Absorbs the former TD-35, which described one instance of the same thing. The pattern is
what matters: features land with `NSLocalizedString` correctly in place, Xcode harvests the
keys into the catalogues, and the *translations* are never written — so a Russian or Spanish
learner reads English, or worse, reads a correct translation of a string whose meaning has
since changed.

**Two open instances (2026-07-29):**

* The chooser switch was relabelled from "Include learned words" to "Practise everything,
  due or not" when it stopped filtering inside a scope and started choosing between two. It
  lives in `Main.storyboard`, so `ru` and `es` still describe behaviour the switch no longer
  has — worse than saying nothing.
* Every string added since the reminder work — `"Next reminder: %@."`, the four permission
  footers, `"Add meaning"`, the dictation failures — is in `Localizable.xcstrings` with
  **zero localizations** and falls back to English. Verified rather than assumed:
  `"Next reminder: %@."` is present in the catalogue with an empty `localizations` map.

**The mechanism is not at fault.** `NSLocalizedString` is used throughout and the keys are
being collected; `String(localized:)` and the SwiftUI machinery are unavailable at the 12.1
floor, and nothing about that floor prevents doing this properly. **Discharge:** translate
the outstanding keys, and treat "the catalogue has an untranslated key" as part of finishing
a feature rather than a separate errand — that is the only thing that has ever stopped this
recurring.

**Finding** (audit of `Localizable.xcstrings`): the `es` locale was wrong *and* incomplete.
Eight strings carried the English source verbatim while marked `translated` — so Spanish
users saw "Dictation", "Forgot", "Learning", "Look Up", "Phonetic", untranslated
`WordCount` plurals — plus a typo ("ermiso"), a half-Russian value ("Import удался"), stray
whitespace, and several missing articles / stilted phrasings. A duplicate-of-source marked
`translated` is worse than an absent one: it defeats every completeness signal and drifts
silently as the source changes. All fixed.

**Backfill:** `es` was a **partial** locale (~55 strings to `ru`'s ~83). The ~30 `ru`-only
strings now have Spanish, marked **`needs_review`** (not `translated`) so a reviewer gets an
exact worklist and the honest state is preserved. Ambiguous source keys gained real
localizer comments ("Rate" read as *rating*; "Pitch" / "Speech" / "Study"), in both code and
catalog.

**Open (reviewer):** recognition terminology is not unified — the catalogue mixes
"reconocimiento de voz" / "del habla" / "de habla", and "Voz" vs "habla" for the Speech
section. Pick one and sweep.

**The debt itself:** TD-14 and TD-19 both shipped with "RU translations to be added" —
localization is deferred every feature and paid later in a batch, so strings reach users
untranslated (or, worse, as English marked `translated`) in between. **Discharge:** treat the
string catalogue as part of a feature's definition of done — add `es`/`ru` (or an explicit
`needs_review`) in the same commit as the `NSLocalizedString`, and never mark a
copy-of-source `translated`.

**A third instance, and the sharpest one (owner, 2026-09-02): translations that are correct
word-for-word and wrong as sentences.** Seen in the running app, not read off the catalogue:

* `"Remembered for about %@"` renders in Russian as **"Помнится около 2 дня"**. Two separate
  faults. *Grammatically*, `около` governs the genitive while `DateComponentsFormatter`
  returns a nominative phrase, so no set of plural forms can repair it while the preposition
  and the formatter output are composed by a `%@` template — the string needs recasting, not
  retranslating. *Idiomatically*, `помнится` is read as the parenthetical "as I recall",
  which is close to the opposite of a prediction about the future. Candidates the owner
  raised or that follow from this: `Продержится ≈ %@`, `В памяти ещё ~%@`.
* The same trap caught this session's own new string: `"нужны успехи в 5 разных дней"` was
  written, shipped to the simulator, and read back as wrong. **Fixed in TD-57** by letting
  the numeral govern the noun directly instead of sitting behind a preposition.
* `"Successful days"` was `"Дней с успехом"`, so the row read "Дней с успехом — 1 день":
  label and value disagreeing about what is counted. Now `"Успешных дней"`.

**What this adds to the pattern above.** The existing discharge — "translate the outstanding
keys as part of finishing a feature" — is necessary and not sufficient: every string here was
already translated and marked `translated`. What was missing is *reading the result in the
target language on a device*. A `%@` template that composes a preposition with formatted
output is a structural bug that only shows up rendered, and English never reveals it because
English does not decline. **Added discharge:** for any format string with a `%@` or `%d` in a
prepositional phrase, drive the screen once per language — `simctl launch <udid> <bundle>
-AppleLanguages "(ru)"` — before calling it done.

**Backlog cleared (2026-07-28, second pass).** The remaining 45 source-only keys (no `ru`
and no `es` — reminders/scheduling copy, dictation and meaning-editor strings, the `Animals`
starter set) are now translated into both, marked `needs_review`. The catalogue is
**fully populated**: every key has `ru` + `es`, so nothing falls back to English at runtime.
`needs_review` ships in release exactly like `translated` (the state is editor metadata, not
a build filter); it stays only as the reviewer's worklist. Four more ambiguous comments
enriched in code + catalog (`Reset`/`Rename` said *what?*; `Recent`/`Suggestions` are word-picker
sections). Reviewer scope is now the whole `needs_review` set plus the terminology sweep above.

## TD-34 — Reminder rebuilds now fire on every local save

`storeDidChange` posts after every successful write, and `AppDelegate` rebuilds the whole
reminder window on each one. Correct, and wasteful: importing a file of 500 words rebuilds
it once per transaction, and each rebuild is a full `ReviewSchedule` over the library.

**Cost:** invisible today (imports are one transaction, edits are rare), real once anything
writes in a loop. **Discharge:** coalesce — a short debounce before rebuilding. **Not the
same debouncer as deduplication**, though the same shape: different triggers, different
windows, and the rebuild must be *subordinate* to the repair rather than parallel to it, or
it derives a schedule from half-merged rows. See [Design](Design.md) § "repair and
derivation are two debounces". The overlapping-rebuild race this would otherwise expose is
already closed by a generation counter.

## TD-36 — The exercise screen shows one translation and no transcription

A meaning may hold several words per language and each `Term` may carry a `transcription`,
but the exercise screen shows exactly one answer and never a transcription. The learner is
graded as correct for *any* synonym and then shown only one of them, which is the redesign's
own feature hidden at the moment it would teach something.

**Discharge (owner, 2026-07-29):** below the revealed answer, the remaining synonyms in a
secondary/footnote text style, and — behind a Settings switch — the transcription. Both
follow the `noteLabel` pattern already on that screen: **absent means the view is not there
at all**, never an empty row holding a gap.

## TD-37 — Speech warm-up is unmeasured, and one attempt at it crashed the app

**What it cost before it was caught.** The first version called `AVAudioEngine.prepare()`
during warm-up, with a comment explaining that *not* activating the audio session was the
careful choice. It was the opposite: `prepare` pulls the input node, and with the session
still in `.playback` there is no capture hardware to describe, so the engine cached an
input format of **0 Hz**. That poisoned format survived into `beginRecording`, where
`installTap` rejected it with `IsFormatSampleRateAndChannelCountValid` — an Objective-C
exception, which Swift cannot catch, so the app died on the learner's first dictation.

Two lessons worth keeping:

* **A warm-up must not be able to change behaviour, only timing.** It runs on every
  appearance of a screen whose feature may never be used, so it gets the strictest budget
  of any code in the app.
* **`installTap` is one of the few calls here that can kill the process rather than throw.**
  Its format is now validated, with one `reset()`-and-retry to recover an engine holding a
  stale configuration, and a typed failure when there is genuinely no input.



`DictationController.prewarm` and `SpeechManager.prewarm` do the slow parts of the first
use — building the recogniser, loading a voice, allocating the engine graph, configuring the
session — while a screen appears. The reasoning is sound and the ~1.5s cold start is the
owner's measurement, but **the improvement itself has not been measured**, and warm-ups are
exactly the kind of change that feels effective without being so.

**Discharge:** time from tap to the recording indicator, warm and cold, on a device. If the
gain is small the code should go rather than sit there implying a benefit it does not have.

## TD-38 — Pronunciation has no visual feedback

A spoken answer is now graded by recogniser confidence (`.correctVerbatim` above 0.85,
`.correctJudged` below), but the two look identical on screen: the same shine, the same
advance. The learner is told they were right and never told they were *clear*.

**Cost:** the one signal the exercise has about pronunciation quality is computed and then
thrown away at the point it would be most useful. **Discharge:** a KaPow animation keyed to
confidence — the existing `pulse` then `spray` for a confident match, something visibly weaker for a
hesitant one — plus a colour or a meter on the recognised text. Wants a device to tune,
since the confidence range in real speech is not the range in a quiet room.
Maybe set logging points ask the operator to execute some phonetic exercises and provide their log.

## TD-39 — Duplicate words — **resolved (2026-08-01)**

Both halves landed, as layers rather than alternatives (owner): the hint prevents the
mistake for a learner who is looking, the alert catches the one who is not or who meant to
proceed anyway.

* **The hint.** `WordInputViewController` shows a typed word's existing meanings as an
  unselectable section — translations in footnote, set names in caption2 and allowed to
  truncate. Injected as a closure, so the screen never gains a `Lexicon`. Unselectable on
  the lesson from the old search screen, where a row that looked like a hint was tappable
  and filed the word as its own translation.
* **The add flow** asks *Replace meaning* / *Add as another meaning* / *Cancel*.
* **The meaning editor** asks *Use the existing word* / *Cancel* on a rename that collides.
  Renaming is not offered "add another meaning" because there is no second meaning to
  create — one meaning is being edited, and the only question is which word it should use.
  Forcing symmetry would have offered a choice that does nothing.

The wording lives once, in `DuplicateWordPrompt`; each caller passes the answers that apply.

**A worse defect surfaced while doing it.** `updateTerm` edits a row in place, so renaming
"bruin" to "bear" where "bear" already existed produced **two rows spelled the same** — the
one thing `findOrCreateTerm` prevents everywhere else, and a duplicate at the *term* level
rather than the meaning level. `replaceTerm(_:with:inSense:)` drops the old word and links
the canonical one in a single transaction; tested.

## TD-40 — Main-queue confinement is checked, not proved

`Lexicon.viewContext` now carries `dispatchPrecondition(condition: .onQueue(.main))`, so a
read from the wrong queue traps in debug instead of corrupting silently. That is an
improvement on prose, and still weaker than the guarantee the code deserves: preconditions
fire only where a test or a session happens to reach.

The real fix arrives with the floor. At iOS 13, `Lexicon` can become an `actor` — or hold an
isolated context — and the confinement becomes a compile-time property rather than a runtime
check that has to be *hit* to help. See [Design](Design.md) § "Swift Concurrency, when the
floor allows it".

**Cost:** low today, because every caller is a main-queue view controller. It rises the
moment anything reads off the main queue — an import, an enrichment pass, a background
refresh — which is exactly the work the roadmap is heading towards.

## TD-41 — The dictation button hides the text field's clear button — **resolved (2026-08-02)**

`WordInputViewController` set both `clearButtonMode = .whileEditing` and a dictation
button as the field's `rightView`. They occupy the same place, and the `rightView` wins —
so there was no way to clear the field except selecting and deleting.

**Dictation moved to the field's `leftView`** — the first of the two discharges named here.
The input accessory was the more interesting option and the wrong one: an accessory lives
with the keyboard, and this screen sets `keyboardDismissMode = .interactive`, so swiping the
keyboard away to read the candidate list would take the microphone with it. The button
exists precisely because *"a control in the interface says the capability exists"*; one that
leaves with the keyboard is the keyboard's microphone again, in a costlier form.

The button is now **omitted rather than hidden** where there is no language to recognise it
in. `isHidden` left an installed control that could not act, and raised a question — does a
hidden side view still inset the text? — that not installing it does not.

`WordInputFieldTests` asserts the geometry rather than the assignment: the rects UIKit
reports for the clear button and the dictation button must not intersect. Confirmed to fail
against the old arrangement.

**The screenshot found what the diff could not.** Moving the button revealed that its size
was never chosen: `sizeToFit` grew the button to whatever the symbol happened to be, which
at the default configuration is about **50pt** — a solid accent disc heavier than the Save
button, sitting flush against the word being typed. The glyph is now sized first, with a
`.body` symbol configuration (the field's own text style, since it sits inline with the
word), and the 44pt square around it is both the touch target and the padding. It measures
about 37pt against the system clear button's 33 — an action that reads slightly stronger
than an affordance, which is the right order. Verified on an iOS 26.5 simulator; the iOS 12
rendering is unverified for the usual reason (TD-8), and on that floor there is no SF
Symbol at all — `UIImage.systemImage` returns `nil` below iOS 13, so the button is blank
there. Pre-existing, and its own defect.

## TD-42 — The microphone said "listening" about a second before it was — **resolved (2026-08-02)**

Both dictation surfaces set their state the instant the button was tapped —
`isDictating = true` in `WordInputViewController`, `isRecording = true` in
`SpokenAnswerSurface` — and only then called `DictationController.start`. So the mic went
red, and Phonetics offered "Stop recognition", while the audio session was still being
activated and the engine still being started. The learner was told to speak into a
microphone that was not open, and the first word of what they said was routinely lost.

**Not fixable by making it faster.** TD-37 already asks whether `prewarm` earns its place;
this is the answer from the other direction. `prewarm` deliberately cannot activate the
session or touch the engine — claiming the microphone for a recording that may never happen
is what a warm-up must not do, and pulling the input node early is what made the app crash.
The wait is inherent to the start path, so the only honest fix is to show it.

`DictationController.Activity` (`idle` / `starting` / `listening`) is declared on the
controller, because it is the controller's knowledge and two surfaces render it — a copy
each is how they drift. `start` gained a mandatory `onListening`, called only after
`audioEngine.start()` returns, which is the first moment anything is being captured. It has
no default value on purpose: a caller must decide what to show while `starting` lasts
rather than defaulting back into claiming it is already recording.

Grey for `starting` on both screens — `.lwTextSecondary` on the mic glyph, `LWButton`'s
existing `.utility` purpose in Phonetics — so red keeps meaning *listening* and nothing
else. **Deliberately not a spinner:** `beginRecording` runs on the main queue (TD-43), so an
activity indicator would sit frozen through exactly the wait it was added to describe.

## TD-43 — Opening the microphone blocks the main queue

`DictationController.beginRecording` runs `setCategory`, `setActive`, a possible
`audioEngine.reset()`, `installTap`, `prepare` and `start` synchronously on the main queue.
That is roughly the second TD-42 now labels honestly — but labelling it does not unfreeze
the interface: for that second the screen cannot scroll, the keyboard cannot dismiss, and
the button cannot be tapped.

**Cost:** a visible hang on the two screens that use speech, on every first dictation. It
also hides a smaller defect: between the tap and the permission callback there is one
runloop turn where the interface *is* live, and a tap that lands there calls `stop()` before
`beginRecording` has run — which then starts the recording anyway, opening the microphone
after the learner cancelled. Narrow today because the main queue is busy for the rest of the
window; moving the work off it widens the window and makes the fix mandatory.

**Discharge:** run the session and engine setup on a private queue and hop back to the main
queue for `onListening`, `onTranscription` and `onFailure` — which already promise the main
queue. Needs a cancellation token (a generation counter checked after each await point) so a
`stop()` issued mid-start is honoured rather than overwritten. Best done with the
`AsyncStream` rewrite [Design](Design.md) already sketches for the iOS 13+ floor, rather than
twice.

## TD-44 — The hint could not be looked up — **resolved (2026-08-02)**

The pinned-term slab on the second step of the add-word flow showed the word and offered
nothing to do with it. The ⓘ dictionary lookup is everywhere else in this app — the word
list's long press, the exercise screen's Look Up button, the suggestion rows on this very
screen — and the one place it was missing is the place it is most useful: the learner may
have typed the word without ever looking it up, and this step is where they have to say
what it *means* (owner).

`UIButton(type: .detailDisclosure)` rather than an `info.circle` image, because it is the
one that still draws something at the iOS 12 floor — `UIImage.systemImage` returns `nil`
below iOS 13. It calls the same `lookUp(term:sender:)` as every other caller, so the guard
against double presentation and the comma-splitting are not repeated here.

**The slab stopped being a single accessibility element.** It was `isAccessibilityElement =
true` with a combined label, which would have hidden the button it now contains from
VoiceOver entirely. The caption and the term are one element (they read as one phrase); the
button is its own, labelled "Look up <word>".

### Sizing, and the numbers behind it

Left alone the ⓘ renders about 50pt — twice the one on the rows below, which reads as a
different control rather than the same one. It now takes the same `.body` symbol
configuration as the microphone opposite it: one rule for both controls on the screen,
tracking Dynamic Type rather than a chosen size.

Three literals were retired in the process (owner: *"I try to avoid magic numbers… you must
be sure enough if you yet decide to use one"*):

* `minimumTouchTarget` — 44pt scaled, now the single source for the field's height floor,
  the microphone and this button. Three literals that happen to agree are not one rule, and
  44 is Apple's number, not taste.
* `slabPadding` — one `UIEdgeInsets` in place of the four inset literals it replaced, which
  were never four decisions. The gap between the term and the button is the same token.
* The **padding around each glyph is not a number at all** — it is the difference between
  the touch target and the type-scaled symbol, so it cannot drift out of step with either.

## TD-45 — Asset catalogs use formats the verification toolchain cannot read

TD-8 concluded that the App-Store build (Xcode 26) and the iOS-12 verification build
(Xcode 15.2, Ventura) are two separate steps. This is the first thing that made that split
cost something: the **assets** had quietly become Xcode-26-only, so the verification build
died at `CompileAssetCatalog` before it could get anywhere near iOS 12.

Two causes, both introduced by a newer Xcode's defaults rather than by a decision:

- **The app icon is an Icon Composer file.** `85e9d6b` (2025-11-24) deleted
  `LearnWords/Assets.xcassets/AppIcon.appiconset` and replaced it with `AppIcon.icon` at
  the repo root, leaving `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`. Xcode 26's
  `actool` resolves that name from the `.icon`; Xcode 15.2 predates Icon Composer entirely
  and fails with *"None of the input catalogs contained a matching app icon set named
  AppIcon"*.
- **`WordWidget/Assets.xcassets/AppIcon.appiconset` declared the iOS 18 `tinted`
  luminosity appearance** (Xcode 16+), in a set that carried no image files at all — the
  widget template's placeholder. `WordWidgetExtension` inherited the project-level
  `AppIcon` name, so that set was compiled rather than ignored.

**Resolution.** The widget extension no longer asks for an app icon
(`ASSETCATALOG_COMPILER_APPICON_NAME = ""` on both its configurations) and the empty
placeholder set is deleted — a widget extension never displays one; the gallery uses the
containing app's icon. The app target gets a plain **single-1024 `AppIcon.appiconset`**
back alongside `AppIcon.icon`, which is the format Xcode 14–15 understand and which
`actool` expands to every size at the 12.1 floor.

**Keeping both is free, and that was measured rather than assumed.** Compiling the app's
catalog with and without the restored `.appiconset` produces a **byte-identical**
`Assets.car` (3,416,616 bytes) and an identical `AppIcon60x60@2x.png`, which does *not*
match the legacy PNG — so Xcode 26 uses the Icon Composer file unconditionally and the
`.appiconset` exists purely to give the older toolchain something to compile. That also
means its art never ships while `AppIcon.icon` is present.

**Cost, going forward:** this will recur. Every asset format a future Xcode introduces —
and every placeholder its templates generate — is invisible until someone opens the
project on the Ventura machine. **Discharge:** run the verification build after adding
any asset, and prefer the oldest format that expresses the intent. A catalog is compiled
by whichever toolchain opens it; it has no deployment target of its own.

### Where the older toolchain lives — `chore/xcode-15-project`

TD-8 established that verification needs Xcode 15.2 on the Ventura machine. Xcode 15 has
no synchronized folders (`PBXFileSystemSynchronizedRootGroup`, and `objectVersion = 100`
with it), so it needs a project file written in the older format — which master's cannot
be, without giving up folder membership here.

The rule that keeps this cheap: **the branch only ever *adds* files.** It carries
`LearnWords-Xcode15.xcodeproj` and leaves `LearnWords.xcodeproj` alone, so `git merge
master` has nothing to conflict with. The first attempt rewrote the shared project in
place, which made every sync a ~900-line conflict in generated text whose only honest
resolution was to redo the downgrade. Anything that is *not* purely a file-format
concern — a linker flag, an icon set, a package reference — belongs on **master**, not
here; a fix that only exists on a verification branch is a fix the App Store build does
not get.

**The one manual cost, which no layout removes:** Xcode 15 has no folder membership, so a
source file added on master must be added to the legacy project by hand before the next
verification run. It fails loudly at compile time, which is the right failure mode.

**`Package.resolved` stays untracked, deliberately** (owner). Xcode 16 writes it as
`"version" : 3` with an `originHash`; Xcode 15 cannot read that and refuses the file, so a
tracked copy would have to be deleted by hand on the Ventura machine every single time.
This is the same fault as the asset catalogs above — a file format only the newer
toolchain understands — and the `.gitignore` entry is the fix, not an oversight. The cost
is that a fresh resolve is not pinned; with KaPow now on a remote, note the tag rather than
assuming a build reproduces byte-for-byte. Copying the working directory to Ventura carries
the untracked file along, which is what forces the manual delete — a `git clone` or a
checkout of this branch would not.

The long-term alternative is a generated project (XcodeGen, Tuist): one spec, and since
neither emits synchronized folders, a *single* generated project would open in both
toolchains and this branch would stop existing. The trade is losing Xcode 16+ folder
auto-membership on master in exchange for a spec to maintain. Not taken yet.

## TD-46 — The app hard-linked Core Haptics, so iOS 12 could not launch it

The first iOS 12 run after the Xcode 15.2 build went green died on a `SIGABRT` a moment
after the launch screen, with no usable stack. The instinct was a mis-wired life cycle —
the dual `AppDelegate`/`SceneDelegate` split being the newest thing near launch. It was
not: **nothing in this app had run yet.** The process was killed by `dyld`, before `main`.

`KaPow` — linked into the app for TD-16 — does `import CoreHaptics` in `Support/Haptics.swift`
and `Effects/EffectProxy+Spray.swift`. **Core Haptics is iOS 13+.** A Swift `import` emits an
autolink directive that the linker turns into a plain `LC_LOAD_DYLIB`, and a plain load
command is a *requirement*: `dyld` must find
`/System/Library/Frameworks/CoreHaptics.framework/CoreHaptics` at launch or it terminates
the process. iOS 12 has no such framework.

**This is the hole in TD-7's reasoning.** That entry concluded the Swift code is iOS-12
clean because "a green build proves there are no unguarded iOS 13+ API uses" — true, and
KaPow's guarding is exemplary (`@available(iOS 13.0, *) enum Haptics`, and `playHaptics()`
opens with `guard #available(iOS 13.0, *) else { return }`). **`@available` guards code, not
linkage.** The framework is loaded before a single availability check can run, so no amount
of correct gating inside the module saves it. Compile-time availability and run-time
linkage are separate claims, and only the first one is machine-checked.

**Fix:** `OTHER_LDFLAGS = -weak_framework CoreHaptics` on the app target (both
configurations). Verified with `otool -l`: the load command becomes `LC_LOAD_WEAK_DYLIB`,
so `dyld` binds the missing symbols to null on iOS 12 instead of aborting, and every use
sits behind the existing availability guards. An audit of the remaining hard load commands
found **no other iOS 13+ framework** — `Speech` and `UserNotifications` are iOS 10, the
rest older; `SwiftUI` and `libswiftOSLog` were already weak.

**Remaining:** the flag fixes *this* consumer, not the cause. KaPow declares `.iOS(.v12)`
and its `Package.swift` says outright that "effects that need more (Core Haptics, iOS 13)
guard at the call site" — which is exactly the assumption that does not hold, so **any**
consumer at an iOS 12 floor is broken on launch by taking the dependency. The package-side
discharge is to stop importing Core Haptics from a target that claims iOS 12: move the
haptic burst behind a separate product, or drop the import and reach the API dynamically.
Tracked as KaPow debt.

**Discharge for the register:** when adding a dependency or an `import` at this floor,
check the link, not just the build — `otool -l <binary> | grep -A2 LC_LOAD_DYLIB` and
confirm every named framework predates the deployment target.

## TD-47 — The tab bar was built twice, and iOS 12 got the other one — **resolved (2026-08-04)**

On an iPad running iOS 12 the app showed **three** tabs — "Набор слов", "Элемент",
"Упражнения" — against four on iOS 13+, and the middle one was named after Xcode's default
placeholder. Two independent causes, both invisible on any simulator this project can run.

**Settings was missing because the composition root was not shared.** `AppRoot` opens by
declaring itself "the single place that constructs the app's root UI … so the two code
paths can't drift", and `makeRoot()` is where the Settings tab is appended. But
`Info.plist` still carried `UIMainStoryboardFile = Main` from before the scene split, so on
iOS 12 UIKit instantiated the storyboard and assigned `AppDelegate.window` *before any of
our code ran*. `makeRoot()` was never called on that path. Only `SceneDelegate` used it.

A comment claiming a single source of truth is not one. The second construction site was a
**plist key**, which is why reading the Swift did not reveal it — and why the eventual
`window?.tintColor = .orange` line in `didFinishLaunching`, which only makes sense if
something else already made the window, was the visible symptom nobody read as one.

**Fix:** delete the key; `AppDelegate` now builds the window itself on iOS 12, through
`AppRoot.makeRoot()`, exactly as `SceneDelegate` does on 13+. `AppRootTests` pins the key's
absence, since it is the kind of thing Xcode restores.

**The middle tab was named twice.** `Main.storyboard` declared a `UITabBarItem` on the
Manage Sets navigation controller (`H9N-Y4-X4Z`, Xcode's untouched "Item" placeholder) *and*
another on that controller's root view controller (`EEA-CH-FD5`, the real "Manage Sets" with
its folder symbol). On iOS 13+ a navigation controller forwards `tabBarItem` to its root, so
the placeholder was masked; iOS 12 does not forward, so the placeholder won. The Russian
translators had by then dutifully rendered it as "Элемент".

**Fix:** one declaration, on the navigation controller — where tabs 1 and 3 already kept
theirs. The stale `EEA-CH-FD5.title` entry is gone from `Main.xcstrings` and its
translations moved onto the surviving key.

**Not covered by a test, and the attempt is instructive.** `AppRootTests` now asserts each
tab's title at the index `AppRoot.Tab` routes on. That test was run against the *old*
storyboard and **passed**: the forwarding makes the placeholder unobservable from the object
graph on iOS 13+. A duplicate declaration of this kind is only detectable by reading the
storyboard source or by running iOS 12. The test is still worth having — it pins tab order
against the routing constants — but it does not guard this.

**Remaining: iOS 12 has no tab icons at all.** The storyboard's images are SF Symbols
(`catalog="system"`), which iOS 12 has no notion of, and the eleven `.symbolset` assets
added as fallbacks are themselves an iOS 13 format. `UIImage.systemImage` returns `nil`
below 13 with a standing `TODO: look up in assets`, across 17 call sites. Giving iOS 12 real
icons means PNG `.imageset`s and a backport that consults them — related to TD-45's lesson
that a catalog is compiled by whichever toolchain opens it, and has no deployment target of
its own. Deliberately deferred; a labels-only tab bar is legible, if plain. **Moot since
2026-09-14:** nothing below iOS 13 can install the app.

## TD-48 — The CloudKit removal window closed before anyone noticed it was open

[Enrichment](Enrichment.md) frames three schema additions as a deadline: *"cheapest before
that deploy and permanent after it."* The deploy in question had **already happened**. The
production schema exported from the CloudKit Console contains
`CD_Term.CD_transcription` and its `_ckAsset` sibling, so the thing the deadline protected —
retiring `Term.transcription` once `Pronunciation` supersedes it — was lost before the
sentence was read.

**The asymmetry is only about removal.** CloudKit lets you add record types and fields to a
production schema at any time, for ever; it never lets you delete or retype one. So the
additions were never on a clock. What was on a clock was the deletion, and that clock had
already run out.

**Consequences, deliberately accepted (owner, 2026-08-07).**

1. **`Term.transcription` is permanent in this container.** The cost is two dead columns
   visible in the CloudKit Console and nowhere else: when a migration eventually retires the
   attribute from the Core Data model, mirroring simply stops writing the field, because the
   remote schema only has to be a *superset* of what the model mirrors. It is not a code cost.
2. **The container stays.** A new container identifier is the only way to reset a production
   schema, and with no users that escape hatch is still free — but spending it on two dead
   columns, in the same release as the iOS 12 fix, would be trading a real signing and
   deployment risk for a cosmetic gain.
3. **The additions landed anyway, now rather than at their first consumer** — against
   [Design](Design.md)'s "sequenced, not built yet", and knowingly. The reason is not the
   false deadline: it is that one production schema deploy before submission is worth more
   than a second one later. **The risk taken:** these entities have no consumer yet, so their
   shape is designed from the source format rather than from working code, and CloudKit makes
   *their* mistakes permanent too. Mitigated by keeping every new attribute optional except
   the natural key, so nothing forces a value the ingestion pipeline may turn out not to have.

**A fourth addition was found while doing this** and is not in the Roadmap's list of three:
**`Language.wiktionaryCode`**, for the `hr`/`sr`/`bs` → `sh` bridge that
[Design](Design.md) puts "on the `Language` row when TD-22 lands". Included, for the same
one-deploy reason.

**Discharge:** none needed for the schema. What remains is that
`Term.transcription` and `Term.pronunciations` now both exist and only the first is written
— a second source of truth with a documented reason and no deadline. Retire the attribute
when enrichment gives the rows a writer; until then new code should prefer the row.

**Rule worth carrying:** a document that says "before the deploy" is a trap once the deploy
is history. When a doc states a deadline, check whether it has passed before planning around
it — the CloudKit Console export answers this in one look.

## TD-49 — Learned: per-exercise strands, spacing gate, horizon floor — **resolved (2026-08-09)**

`isLearned` is `mastery >= 1`, i.e. FSRS stability ≥ the "Remembered for (days)" horizon.
A first *Easy* grade (fast verbatim answer) sets initial stability to **8.30 days** under
the shipped FSRS-6 weights, so **any horizon below ~8 days makes one answer sufficient** —
and the slider's range starts at 1. The meaning is then excluded from practice
(`PracticeSession` filters `!isLearned`) on the strength of a single retrieval, which by
definition carries no spacing evidence at all.

Research is unambiguous that spacing, not count, is the dial (Bahrick et al. 1993: 13
sessions @ 56 d ≈ 26 @ 14 d) — but equally that *one* sitting is not a spaced anything.
**Discharge:** add a distinct-day gate — `learned ⇔ stability ≥ horizon AND ≥N successful
retrievals on N distinct days` (N = 2 minimum, 3 conservative) — and floor the horizon
slider above the Easy initial stability. Both derive from the existing log (`sessionID`,
`date`); no schema change. Optionally expose FSRS `requestRetention` (hard-coded 0.9) as
the second Study dial, the way Anki does. Full reasoning:
[MasteryAndProgressUI](MasteryAndProgressUI.md) §1.

## TD-50 — No per-term statistics view — **resolved (2026-08-11)**

The log holds far more than the ring shows — per-direction (receptive vs productive),
per-exercise, effort, latency, next-due — and none of it is reachable from the word list.
**Discharge:** long press → `UIContextMenuInteraction` context menu with a preview
(iOS 13+; `UILongPressGestureRecognizer` + sheet at the iOS 12 floor, plus
`accessibilityCustomActions` either way — a bare gesture is invisible to VoiceOver).
Trailing swipe is **not** available: the sets screen already uses it for rename/delete.
Content and gesture rationale: [MasteryAndProgressUI](MasteryAndProgressUI.md) §2. The
receptive/productive split is the part no surveyed competitor shows. No schema change.

## TD-50 resolution note (2026-08-11)

Implemented, 356 tests green. No schema change, as specced.

**A section per exercise, which is the owner's headline ask and the shape TD-49 gave the
data.** Memory is kept per exercise, so a word can be solid as a flashcard and untouched in
dictation; the ring on the word list shows the weakest engaged strand, which is the right
summary and says nothing about *which* strand is weak. `SenseStatisticsViewController` is
where that goes, plus effort and the receptive/productive split — the part no surveyed
competitor shows, and the reason `ReviewDirection` has been recorded per event since TD-13.

**An exercise never tried says so.** Reporting 0% mastery and "due now" for an exercise the
learner has never opened is three numbers about nothing, and it reads as failure rather than
as absence.

**The gesture is the platform's.** `UIContextMenuInteraction` via the table's own
`contextMenuConfigurationForRowAt` on iOS 13+, with the statistics as the *preview* — which
is the whole reason for preferring it to a sheet — and a `UILongPressGestureRecognizer`
pushing the same screen at the 12.1 floor. Trailing swipe was never available: the sets
screen uses it for rename and delete, and a swipe acts on a row rather than inspecting it.

**Two things the gesture cost, and how they were paid.**

* *Long press already looked a word up.* The context menu carries "Look up" as an action,
  and the statistics screen carries it as a row — so the capability survives on both sides
  of the 12.1 floor, where there is no menu to hang an action on.
* *A long press is invisible to VoiceOver*, and a context menu is reachable only through the
  rotor. Both destinations are `accessibilityCustomActions` on the cell. The action carries
  the **sense id**, not an index path: cells are reused and search re-sorts the rows, so a
  captured position is stale the moment the table reloads.

**`MemoryWording` picks the unit itself.** Left to choose, `DateComponentsFormatter` says
"2 weeks" for twelve days — a 17% overstatement, and worse, incomparable with the horizon
preference the learner has already met, which is denominated in days and floored at ten. So:
days below a month, then weeks, months, years. Above a month the reverse argument holds and
"45 days" is precision nobody has.

**Six things review caught.** The dictionary was asked to open from the *word list* while the
statistics screen sat on top of it, so the lookup could fail to appear at all — a view
controller presents from itself now, and `offersLookUp` is a flag rather than a closure. The
preview instance no longer grows that row: a preview is not interactive, so it was pure extra
height on the one path where height already clips. `preferredContentSize` was an overridden
*getter*, which made the property write-only and forced a layout pass from inside something
UIKit queries during layout — set in `viewDidLayoutSubviews` instead. The iOS 12 long press
ignored edit mode while the menu path guarded it. A sub-day wait read as "Due in about 1 day",
overstating it for exactly the items closest to being forgotten — "Due later today" now. And a
registered cell identifier nothing dequeued has gone, along with a test fixture that made a
five-day-overdue strand report "not due".

**And one the fix for another finding created.** Collapsing the overall section for a meaning
with no *engaged* exercise also collapsed it for a **reset** one — a reset clears every
strand's memory but deliberately keeps effort and the answer counts, as the record of work
done, so the retained totals vanished on exactly the meanings whose history the learner had
just chosen to set aside. Keyed on whether there is anything to report now, not on engagement.

**Known, not fixed:** for a word with history in more than one exercise the context-menu
preview is taller than iOS will show and clips — the last section's header can appear with
its rows cut off. Tapping the preview opens the full screen, which is what a preview
promises, and UIKit clamps tall previews as a matter of course. A shorter preview would mean
a second layout, which is not worth it before TD-51 decides what a summary looks like.

## TD-51 — No set-level summary — **resolved (2026-08-12)**

**Discharge:** a summary screen built on distribution rather than means — stacked
untouched/learning/learned bar, a 14-day due forecast (honest forgetting, not streaks),
true retention split young/mature, effort totals, and the receptive/productive gap; the
requested averages shown *beside* the distribution, never instead of it (a mean of 0.5
describes two opposite sets). Reference implementation is Anki's stats screen.
[MasteryAndProgressUI](MasteryAndProgressUI.md) §3. No schema change.

## TD-51 resolution note (2026-08-12)

Implemented. Twenty-three new tests, 360 green when this branch was written and 386 after
TD-50 and TD-52 merged into it. No schema change.

**Distribution first, averages beside it.** `SetSummary` reports, per exercise, how many
meanings are untouched / learning / learned — plus the mean the owner asked for, printed
next to the distribution that qualifies it rather than instead of it. A mean of 0.5
describes both fifty half-learned words and twenty-five mastered beside twenty-five
untouched, and `theSameMeanDescribesTwoOppositeSets` is the first test in the file for that
reason.

**Pivoted by exercise**, which is only meaningful because TD-49 made memory per exercise: a
set can be solid as flashcards and untouched in dictation, and one bar for the set says
neither.

**The open question is settled: rings fill one way and colour carries the bad news** (owner,
2026-08-12). A ring running backwards for a losing set reads as an animation bug on first
sight, and `ProgressRing` already blends toward red as retention falls — the same message
without a new convention to learn.

**True retention is computed from the log, not from the score**, because it is a statement
about answers already given: a word answered wrong ten times and right once today scores
exactly like one answered right once, and those are not the same learner. Split young/mature
at 21 days of stability, Anki's own boundary.

**One view for both charts.** `BarStrip` laid across is a distribution; laid along it is a
forecast. Two views would have been two sets of rounding and two answers to what a zero
looks like. Plain layers rather than a charting dependency — it is all rectangles, and it
has to run at the 12.1 floor.

**The gesture matches TD-50.** Long press on a word shows how that word stands; long press
on a set shows how the set does. Trailing swipe was unavailable here for the same reason as
there — rename and delete already own it.

**What the tests did not catch.** The forecast read only `dueAt`, which is `nil` for a
meaning never practised, so a new set reported *"Nothing due"* beside nine waiting words —
the same lie PR #1's review found in the chooser, where `dueCount` counted only engaged
strands. Found by opening the screen on the device. Fixed, and pinned by
`meaningsNeverPractisedAreDueToday`.

**Four things review caught.** A **skip** was counted as a wrong answer — `outcome
.skipped.isPositive` is `false`, so passing over a question lowered the set's accuracy, while
everywhere else in the model a skip is excluded rather than penalised. The forecast filed a
**partly practised** meaning on its Learning date even though its other two exercises were
untried and would be asked at once — the same screen was calling them "untouched" in the row
above. The first fix read `SenseProgress.isDue`, which is `strands.isEmpty ||
strands.values.contains(where: \.isDue)` over *engaged* strands only, so it changed nothing in
production and the test passed only because its fixture set `isDue: true` by hand. It now asks
every exercise — `Exercise.allCases.contains { progress[$0].isDue }`, subscripting so a missing
strand reads as `.untouched` and therefore due — which is the same "any exercise" reading
`ReviewSchedule.anyExerciseDueCount` uses. Pinned twice: once on values, once end to end
through `ScoringPolicy`. The summary **fetched the log twice** per long
press, once inside `ProgressIndex` and once for retention; it now fetches once and replays
into `ProgressIndex(scored:)`. And the **maturity split is an approximation of Anki's, not
Anki's** — it buckets every answer by the meaning's *current* stability, so a well-established
word's early struggles are counted as mature and the young bucket empties. Checked against
`ankitects/anki` rather than asserted: `calculate_true_retention` buckets each review by
`revlog.last_interval`, the interval the card held *before that review*, so its split is fully
historical; the 21-day threshold is `MATURE_IVL`. Its *exclusions* match ours by principle —
Anki counts only rated retrievals, dropping manual reschedules and no-reschedule cram reviews,
where we drop `.progressReset` and `.skipped`. Doing the bucketing properly means reading
stability per answer out of a replay; the docstring now says what this does rather than what
Anki does.

**The ring's colour excludes untouched words.** An untouched strand reports retention 1, so
averaging over every word in the set let a mostly-new set paint a healthy ring while its
practised half was overdue — the warning arriving only once few words were left untouched,
which is exactly backwards for a design whose whole premise is that colour carries the bad
news. Checked against `ankitects/anki` rather than reasoned about: retrievability there is
`Option`-typed, every consumer guards on `memory_state.is_some()`, and the "Card
Retrievability" average does not increment its divisor for a new card — excluding unseen items
is the reference behaviour. Reported by review, PR #5.

**A reset word's two figures describe different spans, deliberately.** Retention counts
answers given before a progress reset; the distribution beside it reflects only what survived,
because the replay truncates at the reset marker. Review flagged the mismatch, and Anki makes
the same split: `calculate_true_retention` scans the whole revlog and never checks
`is_reset()`, while `reviews_for_fsrs` and `get_last_revlog_info` — the memory-state and
training paths — break at exactly that marker. Answers given are a fact about the learner; a
reset is a statement about the schedule. Documented rather than changed.

**Debt closed on the way:** `SetDigest.dueByExercise` had no test — flagged by the TD-49
review, left open by the TD-53 handoff, and read by this screen. Three tests now cover it,
including that answering dictation does not quiet the flashcard queue.

## TD-52 — The progress cache ProgressModel deferred is now due — **resolved (2026-08-12)**

[ProgressModel](ProgressModel.md) agreed per-word cached index values "in principle,
mechanism negotiable", deferring the mechanism to implementation; the word list already
replays the log per row, and TD-51's summary would replay it for every sense in a set on
every appearance. **Discharge:** measure first on a realistic library, then cache
per-sense progress invalidated on event append and recomputed off the cell path. Decide
before shipping the summary, not after. Not a schema commitment.

## TD-52 resolution note (2026-08-12)

Measured first, then cached. Thirteen new tests, 350 green when this branch was written and
366 after TD-50 merged into it. No schema change.

### What it cost, before

`ProgressCostTests` seeds a library and times `ProgressIndex`, attaching each sample to the
result bundle. One run, iPhone 17 Pro simulator / iOS 26.5, Debug, `ScoringPolicy.version` 2
— every row below comes from that single run, and every row is produced by a case in the
suite, so it can be reproduced:

| Library | Events | Scoring one pass |
|---|---|---|
| 250 meanings × 12 | 3,000 | 81 ms |
| 300 meanings × 8 | 2,400 | 67 ms |
| 1,000 meanings × 12 | 12,000 | 369 ms |
| 100 meanings × 100 | 10,000 | 288 ms |
| 2,000 meanings × 20 | 40,000 | 1,860 ms |

Linear in *events*, not in meanings — the 100 × 100 case costs about what 1,000 × 12 does.
That is the good news; the bad news is the constant. The word list reloads in
`viewDidAppear`, so a **1,000-word library paid ~370 ms every time the tab was opened**, and
TD-51's summary would have paid it again.

(An earlier draft of this note headlined "~180 ms at 500 × 12" from a run whose case has
since been resized to 300 × 8 as the always-on guard. No test produces a 500 × 12 figure, so
quoting one was unreproducible; the 1,000 × 12 row above is measured. Reported by review,
PR #4.)

Two findings shaped the fix:

* **Release is barely faster than Debug** (161 ms vs 179 ms at 500 × 12). The cost is not
  arithmetic waiting for an optimiser.
* **The fetch and the replay are comparable** — 250 ms vs 222 ms at 1,000 × 12, and the
  ratio wanders between about 1.1× and 1.4× from run to run. Neither half can be optimised
  away, which argues for not doing the work at all when nothing has changed.

### The cache

`ProgressCache` keeps `SenseProgress` per meaning **in memory** and replays only what it
does not already know, fetching the misses in one pass. A warm screen does no work.

*In memory, not in the store*, because a persisted cache would have to record
`ScoringPolicy.version`, live in the CloudKit schema, and sync — a migration and a sync
surface for a number that is always re-derivable. `ProgressModel` said "not a schema
commitment", and this keeps that. A cold start still pays once, which is the case worth
revisiting if a library ever gets large enough to feel it.

*Correctness before speed.* An entry is dropped when the log grows for that meaning
(`Lexicon.didAppendToLog`, posted by `record` and `resetProgress`), the whole cache is
dropped when another device changes the store **or when a scoring preference changes** —
`masteryHorizonDays` reads the horizon slider on every use so that moving it takes effect at
once, and caching the results put it back to doing nothing until the day turned. The horizon is
compared rather than trusting the notification, which fires for every default in the process:
a trip through Settings to change a speech rate should not cost a full replay on the way back.
Only the horizon, because nothing cached depends on `requireProductionForLearned` — `isLearned`
takes it as an argument read at call time and `learnedCount` reads it live, so a stored
`SenseProgress` is the same value whichever way that switch sits. Everything expires when the day turns —
retention decays with the clock, so yesterday's scores answer a question nobody asked.
`ProgressCacheTests` is about those four moments, not about speed: a stale ring tells the
learner something untrue about their own memory, which is worse than a slow one.

**It is not on `Library`**, where it belongs by subject. `Library.swift` is compiled into
the widget extension, which has no scoring layer; putting it there would drag all of scoring
into an extension that only wants a word count. `ProgressCache.shared`, until TD-5 lands
injection.

### Left open: `ReviewSchedule` does not read through the cache

Only the three per-appearance *screens* were routed through `ProgressCache`. The exercise
chooser still calls `setDigest()`, which builds a whole `ReviewSchedule`, which constructs its
own uncached `ProgressIndex` over the same senses on every appearance — so the chooser pays the
full replay TD-52 measured, and now mixes freshly computed due counts with cached learned
counts in one sentence. Reported by review, PR #4.

Deliberately out of scope, because it is not a one-liner: `ReviewSchedule` pins its own `now`
and `policy`, and the reminder scheduler uses it too. A cache keyed on neither would be
answering a different question than the caller asked, which is exactly the class of bug a cache
is supposed to avoid. **Decide before anything else is built on it** — the summary (TD-51)
already computes its own index from one fetch rather than through the cache, and a third
convention would be one too many.

### On the benchmarks themselves

They are opt-in — `TEST_RUNNER_LW_BENCH=1` — with one small guard left in the default suite
to catch a per-row fetch sneaking back in. Left running by default they made
`ExerciseScreenAppearanceTests`, which then slept a fixed time on a real 0.5 s animation,
flaky under load. It polls for the outcome since TD-61.

**Each measurement is an attachment**, not a `print` and not a deliberate failure. Swift
Testing does not forward standard output to the `xcodebuild` log, and failing a test to read
its numbers is the workaround [ST-0009](https://github.com/swiftlang/swift-evolution/blob/main/proposals/testing/0009-attachments.md)
was written to retire — it lies in CI and has to be re-broken for every fresh reading. Each
sample records `ScoringPolicy.version` alongside the number, so a CSV from a run under
different scoring rules cannot be mistaken for a current one. The fetch-versus-replay ratio
is an `Issue.record(severity: .warning)`: worth a human's glance, not worth failing CI over.

```
TEST_RUNNER_LW_BENCH=1 xcodebuild test -project LearnWords.xcodeproj -scheme LearnWords \
  -destination 'id=<sim>' -resultBundlePath /tmp/td52.xcresult \
  -only-testing:"Unit Testing Bundle/ProgressCostTests"
xcrun xcresulttool export attachments --path /tmp/td52.xcresult --output-path /tmp/out
```

Note the explicit `-resultBundlePath`: picking the newest bundle out of DerivedData with
`ls -t` is a documented way to read the wrong run, and this project has been bitten by it.

## TD-53 — Comma-separated entry creates one meaning, not several — **resolved (2026-08-11)**

Typing `берег, банк` for *bank* should create two meanings; today it creates one. But the
same key produces `лиса, лисица`, which is **one** meaning with two synonyms — undecidable
from the text, and the schema is now able to represent both. **Discharge:** split on comma
into editable rows in the editor and let the learner confirm or merge before commit
(default = the owner's rule, comma → separate meanings); `Lexicon.addSenses(to:terms:)`
already accepts `[[Term.Draft]]`. **Entry-time only:** a Synset owns its `ReviewEvent` log,
so retroactively splitting existing meanings would discard their history — any later split
or merge must be an explicit, warned action. Prior art and rejected alternatives (a
punctuation convention; automatic FM splitting):
[LexicalModelResearch](LexicalModelResearch.md) § *Commas at entry*. No schema change.

## TD-53 resolution note (2026-08-11)

Implemented, 337 tests green (was 298). No schema change, as specced.

**The default is synonyms** (owner's pivot, 2026-08-11). `SenseEntry.proposals(_:_:)` splits
each side on commas and returns **one** meaning holding all of them. The first rule was the
opposite — comma → separate meanings — and it is the right reading of `берег, банк` and the
wrong reading of `лиса, лисица`; both are wrong half the time, and the owner's call is that
synonyms are far more often what a learner types, so the wrong guess should be the one that
needs undoing rather than the one that needs confirming.

**Both directions are one tap, and each other's inverse.** `splitting(_:at:)` breaks a
meaning apart — the language with the most words decides how many meanings there are, an
equal-length list is paired in order, and any other language goes into every meaning, so
nothing is guessed where lists cannot be paired. `merging(_:at:)` folds two back together,
dropping duplicates so a shared word does not arrive twice. A round trip through both is
the identity, which is a test.

**The pivot made the whole app agree about a comma.** Entry, `MeaningEditorViewController`
and `PlainText`'s file format now all read one as *synonyms*. In the editor it is not a
default but a rule: that meaning exists and owns its `ReviewEvent` log, so splitting it
would leave every recorded answer on one half. The three stay separate implementations —
TD-55 will change entry again, and a lossless file round trip must not be tied to what the
keyboard means today.

**Two judgment calls worth flagging.**

* *The confirm screen appears only when a comma actually did something* — when the entry has
  synonyms on either side. A single word keeps today's one-tap path. The owner's "make
  commas less necessary" is served from inside the screen — empty trailing rows, an empty
  trailing section — which a learner reaches with one comma, or from "Add another meaning"
  once there.
* *Rows push `WordInputViewController` rather than being inline text fields.* "Input rows"
  reads as inline fields, but inline fields would drop completions, dictionary lookup and
  dictation — the alert-with-a-text-field this codebase already replaced once.

**The duplicate prompt is not asked on the multi-meaning path.** Laying meanings out one
per section *is* the learner saying they are separate. Consequence, unhandled: entering
`bank` / `берег, банк` when `bank`/`банк` already exists creates a second `банк` meaning.
Visible on the confirm screen before Save, but nothing warns. → worth a small follow-up.

**Three more the review found after that.** Renaming a word with a comma stored one word
literally spelled "лиса, лисица" — the add path had been fixed and its sibling had not, and
`PlainText.render` writes synonyms with a comma while `parse` reads them back as two, so an
export and re-import would have disagreed with the store. Cancelling the duplicate prompt
threw the whole entry away silently, newly reachable because the flow is now torn down
before the alert is raised — `resumeEntry` rebuilds both steps, so Cancel means "let me
change it". And the confirm screen's trailing footer counted sections rather than storable
meanings, so it promised "3 meanings will be created" while Save sat greyed out.

**Finishing an entry unwinds the whole flow, not one screen of it.** The review found the
cost of pushing step two instead of replacing it: the single-meaning path popped onto the
*word* step, which greeted the learner with the word they had just filed and a live Save
button, and tapping it filed the entry twice. `unwindToList` is now the single exit, and it
waits on the transition coordinator before raising the duplicate alert — that alert is
presented from the word list, which is two pushes down while the entry is being typed.

**What the tests did not catch — twice.** Making Back pop to the word (the owner's second ask) left
`WordInputViewController.hasCommitted` set from the first commit, so the returned-to screen
had a dead Save button and no way out but Back. Every test was green; it was found by
driving the simulator. `hasCommitted` is now cleared on each appearance, which still closes
the hole it was added for — a double-commit between a commit and the push that follows it.
`WordInputCommitTests` pins both halves, and drives appearance with
`beginAppearanceTransition` because a pushed/popped navigation controller in the test host
does not run its own appearance transitions (a window-based version passed either way).

The second miss is the lesson worth keeping. Having found that defect on the device, this
session then verified only the *comma* path on the device and left the single-word path —
the common one — unwalked, so the same PR shipped the same shape of bug three lines away:
storing a single meaning popped one screen and stranded the learner on "Add word". Review
caught it. **Walking one path on the device is not walking the flow**; the paths that
branch on user input each need driving, and here there are three (single, multi-meaning,
duplicate).

## TD-49 resolution note (2026-08-09)

Implemented, 294 tests green. Three changes, one of them larger than the ticket asked for
because the owner widened it: *"which skill is practiced, and in which direction"*.

**Memory is now per exercise.** `ScoringPolicy` replays the log partitioned by
`ReviewEvent.task`, so every exercise carries its own FSRS state, schedule and due date
(`StrandProgress`). This is Anki's card model — its scheduling unit is note × template, not
the note — and Nation's receptive/productive split says the same thing from the pedagogy
side. `PracticeSession` now asks both of its questions *of the exercise being practised*:
a meaning can be due for dictation while its flashcard strand rests.

**The learned rule.** `isLearned` = every exercise the learner has **engaged** is learned,
and at least one is. Engagement rather than "all three" is deliberate: it is what stops
strands from wiping progress on meanings drilled in one exercise. Failing a *new* exercise
un-learns the meaning, which is true and is the hypercorrection moment worth surfacing.
`requireProductionForLearned` (preference, off by default) additionally demands a typed or
spoken strand — the academically stricter reading, opt-in because it is real extra work.

**The two guards.** Mastery is held below 1 until an exercise has successes on
`minimumSuccessfulDays` (2) **separate days**: one retrieval carries no spacing evidence,
whatever its stability. And the *preference* is floored at `minimumHorizonDays` (10) —
above the 8.2956-day stability a single Easy answer produces. The floor deliberately does
**not** apply to an injected horizon: an initialiser that ignores its argument is a worse
bug than the one it guards against, so the floor protects the slider only.

**Direction is tallied, not forked.** `answersByDirection` is carried for display (TD-50);
memory stays keyed by exercise. Because direction is on every event, a per-direction split
of memory remains computable later without backfill — `ProgressResearch` Change 5's
deferral, still deferred and still cheap.

Aggregates report the **weakest engaged strand**, never an average: an average lets a
strong flashcard strand hide a failing spoken one, and "done" should mean usable.

**Settings UI still owes a switch** for `requireProductionForLearned`, and the slider's
minimum should move from 1 to 10 to match the floor. Both belong to the TD-50/51 screens.

## TD-54 — The launch crash was my build flag, not the app — **withdrawn (2026-08-09)**

**Retracted in full. There was no user-facing bug, and the "fix" was reverted.**

What happened: while trying to run the suite for TD-49, the app crashed at launch on every
simulator, on a thread named `com.apple.coredata.cloudkit.queue` — `NSCloudKitMirroringDelegate`
trapping inside `_performSetupRequest:`. Unmodified HEAD crashed identically, so it was not
TD-49. The conclusion drawn — *"`shouldSync` never checks whether iCloud is available, so any
user not signed into iCloud crashes at launch"* — was wrong, and a guard on
`FileManager.ubiquityIdentityToken` was written and briefly committed.

**Review (PR #1) caught the danger**: this app's entitlement declares
`com.apple.developer.icloud-services = [CloudKit]` with no `CloudDocuments` and no ubiquity
container, and `ubiquityIdentityToken` is the *ubiquity* identity — widely reported nil
without that service. The guard could therefore have disabled CloudKit sync **for every
user**, silently, with the local-store fallback hiding it. Trading a crash nobody had for
the loss of the flagship feature.

Checking that properly turned up the real cause: **every failing build was made with
`CODE_SIGNING_ALLOWED=NO`**, which strips entitlements entirely. Built normally — ad-hoc
"Sign to Run Locally" — the *unmodified* baseline launches and the suite runs green. The
crash is an artefact of unsigned simulator builds asking CloudKit for a container the
binary is not entitled to.

**Resolution:** guard reverted; `LWPersistence` is back to its previous state. Nothing to fix.

**The lesson, which is the part worth keeping:**

> `CODE_SIGNING_ALLOWED=NO` is not a neutral convenience. It strips entitlements, so any
> framework that resolves them — CloudKit above all — can fail in ways that never happen to
> a real build. Verify with a normally signed build before concluding the *app* is broken;
> a crash that only reproduces under an unusual build flag is a fact about the flag.

Two observations from the same review remain open and are worth keeping, neither urgent:

* Sync is decided once, in `LWPersistence`'s `init`, for the life of the process. A learner
  who signs into iCloud after launch — or whose account is unavailable before first unlock —
  keeps a local-only store until relaunch, silently. `NSUbiquityIdentityDidChange` is the
  notification that would let the app notice.
* If an account check is ever genuinely wanted, `CKContainer.accountStatus` is the API
  CloudKit documents for it — asynchronous, so it cannot gate the synchronous store open
  directly; it would have to defer attaching the container or reopen the store afterwards.

## TD-57 — The distinct-day gate was hardcoded, and set too low — **resolved (2026-09-02)**

`ScoringPolicy.minimumSuccessfulDays` has been injectable since TD-49, and **nothing in
production ever injected it**: `ScoringPolicy.default` took the constant, so the gate was 2
for everyone with no way to change it. The Study section of Settings had exactly one row,
the horizon slider, which says *how long* a meaning should stick while saying nothing about
*how much evidence* is enough.

**Two is a floor, not a default** (owner, 2026-09-02). It is the smallest number for which
the word "spaced" means anything, which is why TD-49 picked it, but a learner who answers
correctly on two days has not shown much. The shipped default is now **5**, settable 2…10
beside the horizon.

**Raising it re-opens words already called learned.** That is the intended effect, not a
migration problem: `successfulDays` is replayed from the log and has always been counted, so
nothing is lost and nothing needs rewriting — the same words simply stop claiming a status
they had not earned under the new rule.

**What the change actually touched, and why each part was needed.**

* The preference is read on **every use**, like `masteryHorizonDays`, because
  `ScoringPolicy.default` is a `static let` — capturing it in `init` would leave the slider
  doing nothing until the next launch. This is the defect Devin caught on PR #4 for the
  horizon; the same shape was avoidable here by copying the fix rather than the bug.
* `ProgressCache` now invalidates on **either** scoring preference. It already watched the
  horizon; a cache that ignored the new one would serve scores computed under the old gate.
* The gate footer on the statistics screen said "two separate days" in prose. It now takes
  the number as an **init parameter**, defaulted to the policy in force — which closes
  Devin's PR #3 finding, left then with "there is nothing to read".
* `Model/Settings.swift` compiles into both widget targets and `ScoringPolicy` does not, so
  the clamp lives in the policy and the stored value stays raw. The first attempt put it in
  `LWUserDefaults` and would not build for the widgets.

**A test defect this exposed, worth recording separately.** The first green run was luck.
`LWUserDefaults.standard` is a singleton over the App-Group suite, so the new tests writing
`minimumSuccessfulDaysPreference` raced every suite that read the gate through
`ScoringPolicy.default` — `ScoringPolicyTests` intermittently found five spaced days no
longer enough because a parallel test had set the gate to 9. Fixed properly rather than by
retry: every other suite now **names** the gate it wants (as `ScoringPolicyTests` already
named its horizon, for exactly this reason), and the only tests that mutate the preference
live alone in a `@Suite(.serialized)`. Verified with three consecutive full runs.

388 tests green, from 386.
## TD-58 — The context-menu previews do not share the app's visual language — **resolved (2026-09-13)**

Long press on a word and long press on a set both open a `UIContextMenuConfiguration` whose
*preview* is a view controller. That gesture was chosen over a sheet precisely because it can
show something — and only one of the two does.

`SetSummaryViewController` has the vocabulary: a `ProgressRing` and a stacked `BarStrip` per
exercise, then a forecast strip. `SenseStatisticsViewController` has **none of it** — three
sections of label/detail text, two of which typically read "Not practised yet" — even though
the row the learner just long-pressed carries a ring of its own. The owner's words: it "does
not even leverage the circled progress bar that should be common through the project."

**Two further defects, seen by driving the simulator rather than read off the code.** Both
previews are **clipped**: the word preview cuts off mid-"Overall", the set preview loses its
retention and effort sections. And `WordSetsTableViewController` passes `actionProvider: nil`,
so long-pressing a set produces a floating card with no menu at all — either it deserves
actions or it should not be a context menu.

**Discharge:** a design round, not a patch — the question is what belongs in a glance versus
in the screen it pushes to, and that has to be answered for both previews together or they
will drift again. Briefed in `Design-Research-Brief.md`, with the current state captured in
`design/ref/`. See also TD-30 (the ring's Dynamic-Type size) and TD-16 (the animation system),
which a redesign will touch.
## TD-59 — Import silently deleted hyphenated words — **resolved (2026-09-10)**

Found by importing into the running app rather than by reading the parser. Six lines went
in through the share-extension path; two came out. `well-known | известный` was dropped, and
so was `badger — барсук`.

**Two separate faults behind it.**

`PlainText.parse` split on any of `| : - –` **at once** and required exactly two parts, so
every hyphenated word — "well-known", "e-mail", "up-to-date", "self-esteem" — produced three
and the line was discarded. The behaviour was known and carried as a `FIXME` with a test
named `hyphenatedWordIsSkippedKnownLimitation`; what was not recorded is that it is a
*round-trip* defect, not only an import one. A hyphenated word can always be **typed**, and
`PlainText.render` writes it out verbatim, so exporting a set and importing it back deleted
it — from a file the app itself wrote. `docs/Design.md` leans on "the user can always import
the dictionary" as the reason migration can be dropped; that promise did not hold.

And `—` (em dash) was not a separator at all, only `-` and `–`. It is what iOS and macOS
autocorrect make of `--` and what most pasted prose carries, so a line typed on the phone
could not be read back by it.

**Fix: try separators in order of confidence rather than all at once.** `|` then `:`, which
never occur inside a word; then a dash with whitespace beside it, which is punctuation
*between* the sides; then a bare dash, so `bear-медведь` reads exactly as it always has. A
hyphenated word survives whenever the line says how it is separated — which is every line
this app writes. No previously-parsing line changes meaning; the three new tests fail
against the old parser and `aBareDashStillSeparatesWhenNothingElseDoes` passes against both,
which is what makes it the regression guard.

392 tests green when the parser changed, 396 with the reporting.

**And the silence that hid it — also fixed (owner asked for it, 2026-09-10).**
`importPlainText` returned a bare count and both call sites discarded it, so a file whose
every line was malformed looked exactly like a successful import: `reload()` and no message.
That is what let this defect live. A bare count would not have been enough either — zero
added means "it was all already here" or "none of it was a word", and those want opposite
responses. It now returns an `ImportSummary` of **added / duplicates / unreadable**, whose
`total` accounts for every line in the file, and both paths report through one
`presentImportSummary` so they cannot drift.

Quiet on a clean import, because the list visibly grows behind the alert and a confirmation
nobody needs is a tap nobody wanted. Anything else is the case the learner cannot see for
themselves.

**A regression the review caught, worth recording because ordering caused it.** The first
version tried `|` then `:` and fell through when a separator produced the wrong number of
parts — so `a|b|c : d` failed on pipes, succeeded on the colon, and imported "a|b|c" as a
word. The old all-at-once parser rejected that line outright, so ordering had made a bad
line *worse* rather than better. The first strong separator **present** now settles the
line, including by rejecting it. Reported by review, PR #12.

396 tests green.

## TD-58 resolution note (2026-09-13)

**A preview is a glance, not a smaller copy of the screen** (owner's choice of option B). Both
screens gained a `Presentation` — `.full` for the pushed screen, `.preview` for the context menu
— and the preview builds different sections rather than the same ones at a different size.

*Per word:* the `ProgressRing` the learner just long-pressed, the word, and how long it is
remembered; then one line per **practised** exercise, and a single line naming the untouched
ones. Two sections instead of four or five. The old preview spent a whole section per untouched
exercise saying "Not practised yet", which is what pushed `Overall` off the bottom.

*Per set:* the three rings and distribution bars, with **due now** moved into that section's
footer so the one number anyone acts on survives the forecast being dropped. Retention and
effort belong to the screen a tap away.

**Both now cap what they ask for** at 0.6 of the window height. The per-word screen asked for
its full content height and let the system decide where to cut; the set screen **never set a
preferred size at all**, which is why it lost two of its four sections. A context-menu preview
does not scroll, so anything past the cut is unreachable rather than merely below the fold —
that is what made this a defect and not an aesthetic complaint.

**A green suite proved nothing here, again.** The change was first wired with the set's
`presentation` argument silently dropped — a mis-indented patch — and all 405 tests still
passed, because they construct the screens directly and the parameter defaults to `.full`. It
was caught by long-pressing a set in the simulator. The same shape as the "dead Save button"
and "Nothing due beside waiting words" defects: this project's screen defects do not live where
its tests look.

405 tests green, from 398 — four for the word preview, three for the set summary screen, which
until now had no screen tests at all.

**Not done here, and still true:** `WordSetsTableViewController` passes `actionProvider: nil`,
so a long press on a set offers a card and no actions. Worth an action or two, but it is a
question about *what a set can do*, not about the preview.

## TD-55 — The entry screen should have the structure, not the punctuation (owner, 2026-08-11)

**Recorded, not built.** The owner's decision on 2026-08-11 was to write this down and
implement it after TD-50/52/51. It revises part of TD-53 rather than replacing it.

### The idea

Defining a term becomes a table with **two sections — "Synonyms" and "Meanings" — each
with a growing row list and an input row that is always available.** Adding is a control in
the section header ("Add" is enough), so the learner is never composing structure out of
punctuation. Typing a comma **advances to the next row**, with a control choosing which
kind of row that is — **synonym by default**, because synonyms are the more common entry
(owner; "a subject to consider"). That default landed early, in TD-53 itself: a comma now
proposes synonyms and `splitting(_:at:)` is the undo, so what TD-55 still adds is the
*structure* — sections, always-available input rows, and the comma as a keystroke rather
than as text to parse. **Enter** commits and returns to the screen the flow
started from, which on this path is the word list. On a future macOS port, **Tab** is the
same gesture and keyboard users never reach for the mouse.

### Why it is the better shape, and not merely a workaround

[LexicalModelResearch](LexicalModelResearch.md) § *Commas at entry* found that every source
that gets this right — Apple's `d:entry`, kaikki/wiktextract — **makes the sense boundary
explicit at authoring time rather than inferring it from punctuation.** TD-53 as shipped
still infers and then asks for confirmation. A comma that *performs a structural action*
stops inferring: pressing it is the learner saying which kind of row comes next, which is
the explicit boundary those formats have. It also moves the correction earlier — `лиса,
лисица` is fixed when the second row appears, not one screen later.

**Rejected on the way (owner considered it): blocking comma input with visual feedback.**
Paste, dictation and the share-extension import all still deliver comma text, so the parser
survives either way and the keyboard would merely disagree with the file format. Rejecting
meaningful input is also worse than accepting it and doing the right thing — a comma is not
invalid, only ambiguous.

### What TD-53's work is still for

`SenseEntry` and the parse do not go away: they become the path for text that **arrives
whole** rather than being typed — paste, dictation, and `importPlainText`. The confirm
screen is that path's fallback. Live structure when typing; confirm when text arrives from
elsewhere.

### Open before this can be built

* **What "Synonyms" is scoped to.** A studied-language synonym belongs to a *sense*, not to
  a term: `bank`/`riverbank` are synonyms in the `берег` sense and not in the `банк` one. A
  flat "Synonyms" section next to "Meanings" has to say which meaning it is adding to once
  more than one meaning exists — or the two sections have to nest.
* **Dictation emits commas.** `DictationController` replaces `field.text` wholesale on every
  transcription callback (each carries the whole transcription so far), so a comma rule that
  fires on *typing* must not fire on programmatic text, or one dictated phrase explodes into
  rows.
* **Where the rows live.** TD-53's confirm screen deliberately pushes
  `WordInputViewController` per row rather than editing inline, because completions,
  dictionary lookup and dictation live there and an inline `UITextField` is the
  alert-with-a-text-field this codebase already replaced once. An always-available input row
  is inline by definition, so this needs those three capabilities designed into the row —
  not dropped by omission.
* **Enter today** commits *and* pops one screen (`WordInputViewController.commit`). "Returns
  to the originating screen" is `unwindToList`'s job now, so the two need reconciling rather
  than both popping.

No schema change: synonyms and senses are what the model already stores.

## TD-56 — Scoring the library is main-thread work (2026-08-12)

TD-52 measured what replaying the review log costs and then stopped paying it twice. What it
did **not** change is *where* the remaining pass runs: `Lexicon`'s reads are pinned to the
main queue, so a cold `ProgressIndex` is built on the thread that draws the UI.

| Library | Events | Main-thread time |
|---|---|---|
| 1,000 meanings × 12 | 12,000 | 369 ms |
| 2,000 meanings × 20 | 40,000 | 1,860 ms |

`ProgressCache` (TD-52, immediately above) removes the *repetition* — a warm screen does no
work — so this is a cold-start and first-appearance cost, not a per-appearance one. It is nonetheless a hitch on
the thread that can least afford one, and it grows with the library.

**Why it is pinned.** `Lexicon.viewContext` asserts `dispatchPrecondition(.onQueue(.main))`,
and every read is synchronous because `async` does not back-deploy below iOS 13 while the
floor is 12.1 (see TD-8). The precondition is doing its job — it caught a test calling a read
off the main actor during TD-52 and failed deterministically in setup rather than corrupting
anything.

**The hard part is already done.** No `Lexicon` method returns a managed object: callers get
`Sense`, `Term`, `WordSet` and `ReviewEvent` value types, and identity crosses every boundary
as a `UUID` that each context re-resolves — stronger than `NSManagedObjectID`, which is
store-scoped and has a temporary/permanent state, and which CloudKit does not sync. Passing a
managed object between queues is therefore structurally impossible here, which is exactly the
property that makes background reads safe to add.

**Discharge, at the current floor:** give `ProgressCache` a completion-handler path that
replays the misses on a private-queue context and calls back on main. It already owns "score
what I do not know", the screens already tolerate arriving-later data (the word list reloads
on appearance), and no `async` is required. **Discharge, if the floor rises:** do it once and
properly — `Lexicon` reads become `async` over `context.perform`, and the callback twin never
gets written. Worth deciding which before building either.

Not urgent: a library large enough to feel this does not exist yet, and the seed is nine
words. Recorded now because the measurement exists now, and because it is the first concrete
user-facing cost of the 12.1 floor.

## TD-60 — The iOS 12–13 Today widget has had no data since before WidgetKit shipped — **withdrawn (2026-09-14)**

**Retracted in full. The widget reads the live store and always did; this entry was wrong on the
day it was written.** Caught in review of the iOS 15 migration brief, which had repeated it.

`Widget/TodayViewController.loadCurrentWordSet()` reads `Library.shared`, `selectedSet` and
`lexicon.senses(in:)`, and maps the result into `words`. The
`userDefaultsGroup.stringArray(forKey: "Words")` line the entry below cites is real text in the
file — inside a **commented-out block**, eleven lines above the live read. `widgetPerformUpdate`
calls `loadCurrentWordSet()` and reloads the table, so the data path is whole.

The fix this entry recommends — *"read the store through `Lexicon`, as the WordWidget does"* —
had already landed in **`2933f30`** (2026-07-26, *"refactor(model): move every screen onto the
lexicon and delete the old store"*), six weeks before **`181af42`** (2026-09-10) added the entry.
`git log -S` was run against the *commented* line, and its result was trusted without reading what
surrounded it.

**The lesson, which is why this entry stays in the register rather than being deleted:** a string
search finds text, not a live code path, and a commented-out block answers one exactly like
working code. The register's authority then does the rest — this entry reached a migration plan
and would have justified deleting a working extension on a false premise.

**And the same trap caught the retraction.** Its first draft credited the fix to `343b5dc`
(2025-09-21), which did repair the widget but through the older `Storage` abstraction, not
`Lexicon`. That came from `git log -L '/loadCurrentWordSet/,+8'` — an eight-line window that lands
entirely **inside the commented block**, so it reports whichever commit last touched the dead
code. Caught in review. Read the function.

The extension's fate is now decided on grounds that hold rather than this one: its bundle sits at
`MinimumOSVersion 12.1` and cannot stay below the new floor, `NCWidgetProviding` is deprecated in
favour of WidgetKit, and the iOS 12–13 devices it was kept for can no longer install the app.
**The owner's call, 2026-09-14: delete it** — see [TASK-iOS15-migration](TASK-iOS15-migration.md)
§ Phase 0. It goes because it is deprecated and unreachable, not because it was broken.

---

**The original entry, kept for the record — its first claim is false.**

**Verified:** `Widget/TodayViewController.swift` reads `stringArray(forKey: "Words")` from the
App-Group defaults, and nothing in the tree writes that key — `AppConstants` labels it "Just for
tests". `git log -S` traces the last writer to a line that was *already commented out* when
3d275cd deleted it, the same commit whose subject promises to "keep Today extension for iOS
12-13". **Reasoned, not seen on a device:** the Today widget on iOS 12 and 13 therefore shows an
empty list. The store refactor did not break it; it was already dead, and the refactor was the
moment nobody noticed.

Found while checking what silent CloudKit pushes reach. The WidgetKit widget (iOS 14+) reads
the store through `Lexicon` and is now reloaded on `LWPersistence.storeDidChange`; this one
reads a key that no longer exists, so no reload can help it.

**Not fixed:** the owner's call is that iOS 12 fixes wait for the next release, and iOS 13 shares
the fate because the WidgetKit widget starts at 14. **Discharge:** read the store through
`Lexicon`, as the WordWidget does — `Lexicon.swift` is already in both widget targets'
membership lists — or have the app write a small snapshot of the current set to the App-Group
defaults from the same `storeDidChange` hook the WidgetKit reload now uses.
## TD-61 — The animation tests slept a fixed time, and lost under load — **resolved (2026-09-10)**

A full-suite run on 2026-09-10 failed in one place,
`ExerciseTransitionTests.refreshRunsWhileContainerStaysOnScreen`: `refreshed` was still false
and the container's alpha still 0 when the test's fixed 1.6 s sleep ended. The change under
test passed the suite on the runs either side. Nothing was wrong with `ExerciseTransition` —
the refresh had not happened *yet*. `refreshed` is set by the fade's completion, after a 0.02 s
delay and a 0.5 s fade, so the sleep already allowed three times the nominal cost, and a
simulator running the whole parallel suite took longer still.
`ExerciseScreenAppearanceTests` had the same shape — a fixed 1.5 s for `viewDidAppear` to
reach `show` — and TD-52 had already seen it flake while the benchmarks ran by default.

**A fixed sleep bets that nothing ever delays the completion past its margin**, and that run
lost the bet; a longer sleep raises the stake and charges it to every run that passes. Both
positive tests now **poll for the outcome**: `waitUntil` (`Unit Testing Bundle/WaitUntil.swift`)
checks every 20 ms and gives up after `animationTimeout`, 5 s. It only waits — the original
`#expect`s follow unchanged, so a failure still says which half of the condition was false. A
passing run leaves as soon as the condition holds; only a failure pays the whole 5 s.

**The negative test cannot be polled.** `refreshSkippedWhenScreenIsLeftDuringDelay` has to show
the refresh *never* runs, and until time runs out "not yet" looks exactly like "never". It
keeps a bounded sleep, lengthened from 1.2 s to the whole `animationTimeout` — the budget a
positive trusts an animation to finish in, against 0.8 s of scheduled delay and fade. **What
that does not close** (reasoned, not observed): were the fade's completion ever later than
5 s, the test would pass without the window guard having been exercised at all. A longer sleep
narrows that and cannot remove it; removing it needs the test to see the fade finish, which
`ExerciseTransition` does not expose. Not done here.

`LearnWords-Xcode15.xcodeproj` does not get the new file. Its test target already lacks ten of
the suites and cannot `import Testing` under Xcode 15.2, so there is nothing there to keep in
step.

**Verified, as far as it goes.** Both suites × 20 (`-test-iterations 20`, six runs per
iteration) with 16 busy-loop processes loading the 8-core host for the whole test run: 120 of
120 green. The same under a probe suite that held the main thread for 2 s in every iteration:
120 of 120. One full-suite run with the standard command: 388 tests green, 4 skipped (the
opt-in benchmarks).

**Not reproduced, and still unexplained.** The old sleeps passed both of those loads as well —
120 of 120 each — and so did a fixed 1.6 s deadline placed after a 1.2 s main-thread stall
straight after `advance`, in the same job. None of them is what delayed the 2026-09-10 run,
and nothing found yet does. The change rests on the reasoning above, not on a reproduction: it
cannot say what happened, only that a delay of up to 5 s no longer fails the suite. The probes
were temporary and are not in the tree.

## TD-62 — Every launch rebuilds the reminder window, unconditionally (2026-09-14)

`AppDelegate.didFinishLaunchingWithOptions` calls `rebuildReminders()`, and the same selector is
wired to `didEnterBackground`, `willEnterForeground` and `LWPersistence.storeDidChange`. The launch
call is **not** redundant with the foreground one — `willEnterForeground` is not posted on a cold
launch, so nothing else covers that case — but it is unconditional. In the common case it rebuilds
against state nothing has touched since the `didEnterBackground` rebuild that ran moments before
the app was terminated.

**What it costs, verified from the call graph.** `ReminderScheduler.rebuild` builds a
`ReviewSchedule`, whose designated initialiser fetches the askable senses of every set and then
constructs `ProgressIndex(lexicon:senses:policy:now:)` — the *replaying* initialiser, not
`ProgressIndex(scored:)`. So the rebuild **bypasses `ProgressCache` entirely** and pays the full
replay whether or not a screen has already warmed the cache. It runs on the main queue:
`standing(completion:)` hops back to main before the schedule is built, and `Lexicon`'s reads are
pinned there anyway (TD-56).

**How much that is, borrowed rather than measured.** TD-56 timed that same replay at 369 ms for
1,000 meanings × 12 events and 1,860 ms for 2,000 × 20 — **through `ProgressIndex`, not through
this path**, so it is the order of magnitude and not this call's number. No measurement of the
reminder rebuild itself exists yet; taking one is the first step of any discharge below.

**Cost.** Main-thread work on the launch path, which is the one stretch of the app's life where a
hitch is most visible, and it grows with the library.

**Discharge (owner's intent, 2026-09-14): schedule it rather than doing it at each launch.** A
`BGAppRefreshTask` keeps the window topped up while the app is not running, which demotes the
launch-time rebuild to a fallback. That is the change that earns the `fetch` background mode — see
[Design](Design.md) § *one background mode, and it is the one CloudKit needs* for why the mode is
not declared ahead of its handler.

Three constraints on doing it:

* `BGTaskScheduler` is **iOS 13+** and the floor is 12.1 (TD-8), so it needs `#available` and iOS
  12 keeps the launch rebuild. The launch path gets a condition, not a deletion.
* Registration of every launch handler must complete **before the end of**
  `didFinishLaunchingWithOptions`, and the identifier must also appear in
  `BGTaskSchedulerPermittedIdentifiers` in `LearnWords/Info.plist`. Omitting the plist entry does
  **not** throw: `register(forTaskWithIdentifier:using:launchHandler:)` returns `false`, a result
  nothing obliges the caller to read, so a forgotten entry is indistinguishable from a task the
  system simply chose never to run. The fatal mistake is the other one — registering the same
  identifier twice kills the app (Apple, `BGTaskScheduler.register`).
* The system decides when, and may decide never: background refresh can be off for a user
  (`UIApplication.backgroundRefreshStatus`) and is budgeted for everyone else. This moves *when*
  work happens; it adds no guarantee, so nothing correctness-critical may migrate behind it.

**Cheaper interim, if the scheduled task is not worth its three constraints yet:** make the launch
rebuild conditional instead of removing it. The schedule is derived, never accumulated (`Design.md`
§ *reminders are scheduled, not fired*), so a stored fingerprint of what it was last derived from —
the store's change token, or the review-event count and the reminder-time preference — is enough to
skip a rebuild that would produce the identical 14 requests. Same saving on the launch path, none
of the constraints, and it is what the scheduled version would want underneath it anyway.
