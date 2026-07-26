# Design

Architecture direction and decision records for LearnWords. Each decision states
what was decided, **why**, and the **alternative rejected**. Authoritative over
code comments where they disagree.

## Target architecture: four-layer MVC (uikit-app-structure)

LearnWords adopts the `uikit-app-structure` model — Manferdini's four-layer MVC,
where MVVM/VIPER are variations on the same pattern:

- **Model** — value types + domain logic (`WordsModel`, `Storage`, `Settings`, `AvailableLanguage`).
- **Controller** — shared app logic, one source of truth per concern (`SpeechManager`, `PermissionManager`, and storage). Injected, not global.
- **Root** — `UIViewController` per screen: navigation, wiring views to controllers, interpreting user actions.
- **View** — `UIView`/cells/storyboards: display + interaction only.

The physical layout that expresses this (feature-first folders) is planned in
[TechDebt](TechDebt.md) TD-1 and executed as build-verified slices, because the
project shares source files across targets (see "Target membership" below).

## Decision: adopt the UIScene lifecycle

**Decision.** Adopt the UIScene lifecycle **as a dual lifecycle** that still supports
iOS 12. On iOS 13+, an `@available(iOS 13.0, *)` `SceneDelegate` owns the `UIWindow`
and builds the root view controller; on iOS 12 the scene manifest is ignored and
`AppDelegate` owns the window (loaded via `UIMainStoryboardFile`). The custom
`learnWords://` URL scheme is handled by `scene(_:openURLContexts:)` on iOS 13+ (and
cold-launch URLs via `willConnectTo`), and by `application(_:open:options:)` on iOS 12.
Both paths route through the shared `AppRoot` composition helper so they cannot drift.

**Why.** Xcode warns that "UIScene lifecycle will soon be required; failure to adopt
will result in an assert" (an assert at the iOS 27 SDK — see the modernization skill).
Adopting scenes is mandatory going forward, but the manifest is simply ignored by
iOS 12, so the two can coexist in one binary via runtime availability checks.

**Rejected.** *Single (scene-only) lifecycle.* That is the cleaner code, and is the
right choice for the eventual modern rewrite, but it would drop iOS 12 — see the
deployment-target decision for why this "Legacy" app keeps it.

Reference: Apple, *Transitioning to the UIKit scene-based life cycle*
([TN3187](https://developer.apple.com/documentation/technotes/tn3187-migrating-to-the-uikit-scene-based-life-cycle)).

## Decision: keep the deployment target at iOS 12.1 (dual lifecycle)

**Decision.** Keep `IPHONEOS_DEPLOYMENT_TARGET = 12.1` for the main app. Support iOS 12
via the dual lifecycle above. Keep `UIRequiredDeviceCapabilities = arm64` (a bump from
the old `armv7` that is correct even at a 12.1 floor — see below). *This reverses an
earlier decision to raise the floor to iOS 15.*

**Why.** This is the **Legacy** app (bundle display name "Learn Words Legacy"); its
job is to stay available on old hardware. Concretely, an iOS 15 floor already covers
every device back to the iPhone 6s / SE 1 (2015) — iOS 13, 14, and 15 share the *same*
device floor, so lowering to 13 or 14 would buy nothing. Only an iOS **12** floor adds
devices, and exactly this tier: **iPhone 5s / 6 / 6 Plus, iPod touch 6, iPad Air 1,
iPad mini 2–3** (2013–2014, capped at iOS 12.5.7). Keeping them is the whole point of a
legacy build; the modern experience will be a separate from-scratch app.

`armv7` (32-bit: iPhone 5/5c and earlier) is still dead here — those devices top out at
iOS 10 and cannot run iOS 12 — so `arm64` is correct.

**Cost (documented, accepted).** The current toolchain (Xcode 26) *officially* supports
only iOS 15–26: it will still **build** at a 12.1 floor (12.0 is the hard linker
minimum) but ships **no simulator below iOS 15** and refuses to connect devices below
iOS 15. So the iOS 12 code path is **unverifiable in Xcode 26** — it must be smoke-tested
(and, from April 2026, the App-Store build is separate — see below) on **Xcode 15** with
an iOS 12 device/simulator. Tracked as TD-8.

**App-Store note.** From April 2026 the store requires builds made with the iOS 26 SDK
(Xcode 26+). Building with the iOS 26 SDK while deploying to iOS 12 is allowed; the
constraint is purely *testability*, not shippability.

**Rejected.** *iOS 15 floor / scene-only.* Cleaner and fully testable on the current
toolchain, but drops the 2013–2014 device tier this app exists to serve. Adopted for
the modern rewrite instead, not for Legacy.

## Composition root

`AppRoot` (`AppRoot.swift`) is the shared composition root for **both** lifecycles: it
builds the root view controller from `Main.storyboard` (`makeRoot()`) and interprets
`learnWords://` URLs (`handle(_:on:)`). On iOS 13+, `SceneDelegate.scene(_:willConnectTo:)`
creates the window, sets the tint, and calls `AppRoot`; on iOS 12, `AppDelegate` owns the
storyboard-created window and calls the same `AppRoot`. Keeping the construction in one
place is DRY and dependency-inversion in practice, and it is where shared controllers get
injected as the app grows. `AppDelegate` stays thin: appearance in `didFinishLaunching`,
the `@available`-gated `configurationForConnecting`, and the iOS 12 URL fallback.

## Decision: persistence is `Lexicon`, and there is no protocol — **superseded (2026-07-26)**

**Was.** The app depended on a `WordStore` protocol so a Core Data conformer could be
swapped in; `Storage` was a static facade over `Storage.backend: WordStore`, and
`UserDefaultsWordStore` was the implementation.

**Now.** `Lexicon` *is* the store, and there is no protocol. `WordStore`,
`UserDefaultsWordStore`, `Storage` and `WordAndStat` are deleted (TD-13 iteration 3).

**Why the seam went instead of being used.** The protocol was shaped around a flat
`[WordAndStat]` array mutated by index. Mapping senses onto it would have collapsed
synonyms and multilingual tuples back into single pairs — destroying precisely what the
schema redesign was for. A seam whose shape contradicts the new model is not a seam; it is
a second model to keep in sync. So the swap that justified the abstraction never happened:
the abstraction was removed along with the thing behind it.

**Why no protocol now.** There is one implementation and no second in sight, and it is
already testable because `LWPersistence(inMemory:)` injects a throwaway stack. A protocol
here would be speculative generality. Extract one when a real second conformer appears
(Rule of Three).

**Injection.** `Lexicon` takes its `LWPersistence` by initialiser. Above it, `Library`
holds the app's one instance and the selected set. `Library.shared` is a shared instance,
not because a singleton is right but because the screens are still storyboard-instantiated
— TD-5. Every screen reads `Library.shared`, so when TD-5 lands there is exactly one place
to inject from.

## Decision: no migration into Core Data — start fresh

**Decision (owner, 2026-07-20).** TD-13 builds the Core Data model for the *new*
requirements rather than shaping it to fit `UserDefaults`. **Nothing is migrated** — not
progress, not words, not sets. Users re-import their dictionary. TD-18 (stable identity) is
therefore not a separate `UserDefaults` step: identity is *born* with the Core Data model.

**Why.** Owner's words: "I don't care for backwards compatibility. The user can always
import the dictionary. The loss of progress is not an issue here at all." Progress was
already going to start fresh ([ProgressModel](ProgressModel.md) Q4), so the only thing a
migration would carry is the word list — which the import feature already handles. Writing
a UUID migration against a store being deleted would be work done twice, which is the same
rule TD-12 and ProgressModel state: don't polish a layer being replaced.

**Supersedes** the "words and sets migrate from `UserDefaults`" line in
`TASK-TD13-schema.md` §Phase B, and folds its Phase A into Phase B.

**Cost (accepted).** Existing users lose their word sets and all progress on upgrade. The
owner has accepted this explicitly, for themselves as well.

## Decision: the store stays synchronous

**Decision.** Persistence does **not** go async — the open question in
`TASK-TD13-schema.md` §Decisions 2.

**Why.** Not a preference: Swift Concurrency back-deploys only to **iOS 13**
([Xcode 13.2 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-13_2-release-notes)),
so at the 12.1 floor `async`/`await` cannot be used at all. Core Data's
`performAndWait` is the pre-concurrency way to stay on the right queue, and it lets every
call site read and write without an `await` the floor cannot express. Revisit only if
Legacy drops iOS 12.

## Decision: the lexical model — terms, synsets, multilingual sets

**Decision (owner, 2026-07-23).** The TD-13 schema is **not** a word-pair table. It is a
lexical model, researched in [LexicalModelResearch](LexicalModelResearch.md):

- **`Term`** — an atomic word in one language, existing once, carrying transcription,
  part of speech, variant forms (Apple's `d:index` shape), comments and illustrations.
- **`Synset`** — one shared meaning linking any number of terms in any languages — the
  owner's "language tuple". Synonyms are same-language terms in one synset, and each is
  a valid answer. Sense-disambiguation notes live here, not on terms.
- **`WordSet`** — a named collection of synsets declaring its `languageCodes` (two *or
  more*) — without ranking them, because roles are the session's to assign.

All three links are many-to-many: a term serves several senses, a sense several sets.
Translation connects senses, never words — the shape Apple's dictionary format, W3C
OntoLex-Lemon, LMF and BabelNet all converge on, and what Anki's note/card split
approximates. The word-pair schema from the first cut of iteration 1 is **rejected**:
no synonyms, no third language, duplicates across sets (see the research doc's
rejected-alternatives section).

**Naming (owner):** *primary/secondary*, not *native/foreign* — switching practice
direction doesn't switch your native language. `ReviewDirection` records the skill
(*receptive/productive*, Nation's terms); the event's `promptLanguage`/`answerLanguage`
snapshots carry the concrete pair, which direction alone cannot once a synset spans
more than two languages.

**Event-log consequences (append-only, so decided now):** events link to the synset and
snapshot `promptLanguage`, `answerLanguage`, `promptTermID`, `wordSetID`. **Nothing
cascades into the log** — deleting sets, synsets or terms nullifies the link and the
snapshots keep orphan events judgeable ("history heals").

## Decision: identity — `objectID` for lookup rows, `UUID` for referenced entities

**Decision (owner question, 2026-07-23).** Only entities the app *refers to* carry a
`UUID`: `WordSet`, `Synset`, `Term`. Lookup rows (`Tag`, `Language`, `ErrorTag`) and
owned satellites (`Comment`, `Illustration`, `WordForm`) have none — Core Data's
`objectID` is their identity.

**Why not override `objectID` to avoid a second identifier.** It cannot be overridden:
`NSManagedObjectID` is issued by the persistent store coordinator, is *temporary* until
first save, and changes when an object moves between stores. It is also not portable —
a URI containing the store UUID, meaningless on another device, which rules it out for
CloudKit. So a synced identity has to be an attribute.

The rule is therefore about *reach*: a `UUID` exists where something outside the object
graph must name the row — `ReviewEvent` snapshots `promptTermID`/`wordSetID`, and
CloudKit needs stable identity for records the user's other devices resolve. A tag or a
language is only ever reached *through* a relationship, so a second identifier would be
a second source of truth to keep in sync, for nothing. Dedup by natural key (`Tag.name`,
`Language.code`) is store logic — CloudKit forbids unique constraints — and remote
enrichment matches on that natural key: find the row, or create it (owner's note on
kaikki tags).

## Decision: optionality is CloudKit's price, paid once at the boundary

**Decision (owner question, 2026-07-23).** Every attribute is optional in the *model*
because `NSPersistentCloudKitContainer` requires it (attributes optional or defaulted;
relationships optional with an inverse). The app never pays for that: each managed-object
class exposes **non-optional typed accessors** (`term.spelling`, `synset.identifier`,
`event.reviewedAt`), and `awakeFromInsert` assigns identity and timestamps so the
fallbacks are unreachable for objects this app creates. `CoreDataWordStore` then maps to
value types at the seam, so no unwrapping ever escapes `Model/CoreData/`.

**Rejected.** *Non-optional attributes with defaults in the model.* It reads better in
isolation but lies: a default is not "always present", it is "silently zero", and it
would still be `Optional` in the generated Swift for anything CloudKit syncs.

## Decision: managed objects never escape the store

**Decision (owner, 2026-07-23 — "it saved me from many troubles since 2012").**
`NSManagedObject` instances stay inside the persistence layer. The `WordStore`
implementation maps to value types at its boundary; view controllers, sessions and
widgets never see a `CD*` type. Across queues, only `NSManagedObjectID` travels.
Reads happen on the view context; imports and writes run on background contexts
(`performAndWait` at the 12.1 floor). References: Apple, *Using Core Data in the
background*; WWDC 2012 session 214, *Core Data Best Practices*.

**Why.** Managed objects are queue-bound and context-bound; letting them into the UI
couples every screen to Core Data's threading rules and makes a future SwiftData (or
any other) migration app-wide instead of one file. This is the same seam discipline as
TD-12, enforced at the type level.

## Decision: a language pair belongs to a word set, not to the app

*(2026-07-23: generalized by the lexical-model decision above — a set now declares a
language **list**, and the pair is chosen per practice session. The reasoning below
still stands; "native/foreign" naming is superseded by primary/secondary.)*

**Decision (owner, 2026-07-20).** A word set carries its own `native`/`foreign` languages.
The app-wide `nativeLanguagePreference` / `languageToStudyPreference` become a *default* for
new sets, not the truth for every set. Implemented as part of the TD-13 schema, where a word
set gains real identity; until then `LanguagePair` (`Model/LanguagePair.swift`) is the seam
that resolves the pair in one place.

**Why.** The current model has nowhere to put a pair, and the data already shows the strain:
the default set is literally named `"Initial Sample Set (En->Ru)"` — the pair encoded in a
*display string*. Two sets with different pairs cannot both be correct under one global
setting, so today the app can only be used for one language pair at a time.

It is also a correctness problem for the progress model. [ProgressModel](ProgressModel.md) records
`direction` (receptive vs productive) on every `ReviewEvent`, and direction is only meaningful
relative to a pair. With a global pair, switching sets silently reinterprets the direction of
every event already logged — and the log is append-only, so that corruption is permanent.
This must therefore land **with** the TD-13 schema, not after it.

**Rejected.** *Word sets as an entity on `UserDefaults` now.* It would deliver per-set pairs
sooner, but builds a model layer Core Data replaces immediately — the same rule
`ProgressModel` states for the event log, and TD-12 for the store: don't polish a layer that
is being replaced. The seam costs nothing and makes the eventual swap one place.

**Note.** Word sets are keyed by their name string (`wordSets: [String]`), so they have the
same string-identity problem as words (TD-18): renaming a set orphans its contents. Set
identity and set languages are one piece of work, sequenced with TD-18/TD-13.

## Decision: a language is stored by its subtag; region lives in settings

**Decision (2026-07-26).** `Language.code` holds a BCP-47 **language subtag** — `en`, not
`en-US`. `LanguageCode.canonical` normalises every code entering or querying the store.
The full regioned tag survives in preferences, where `SpeechManager` reads it.

**Why.** A voice has a region; a word does not. "bear" is English whether it is read in a
US or a British voice. Settings ship defaults of `en-US`/`ru-RU`, while the seed and every
import write `en`/`ru` — so without normalising, one launch would create `en-US` rows
beside another launch's `en` rows, and "every word in English" would quietly return half
of them. That is the same duplicate-row problem that normalising tags and error tags into
their own tables was meant to end (Codd's information rule: if it will ever appear in a
`WHERE` clause, it is a row — and one row per thing).

**Cost (accepted).** Script is dropped along with region: `zh-Hans` → `zh`. Distinguishing
scripts needs a decision about what counts as one language, and nothing in the app asks
for one yet. Written down in `LanguageCode` so it reads as a choice, not an oversight.

## Decision: a manual reset appends a marker; it never deletes history

**Decision (2026-07-26).** "Reset progress" on a word appends a `ReviewEvent` of kind
`.progressReset` carrying no outcome, no exercise and no prompt. The answers already given
stay in the log. Scoring reads the marker as a **truncation point**: only what came after
counts toward the current level.

**Why.** Checked against the two implementations that have solved this
([DeepWiki consult](https://deepwiki.com/search/two-questions-about-the-review_0078717c-965c-47c8-b307-38e32d1c1b53?mode=deep),
2026-07-26), and they agree:

- **swift-fsrs** — `FSRS.forget()` appends a `ReviewLog` with `rating: .manual` (0, the
  non-answer sentinel). Replay either skips manual entries or, with `skipManual: false`,
  treats one as a reset to a fresh card. `rollback()` refuses to undo one.
- **Anki** — `revlog.type = Manual` with `ease_factor == 0`; `reviews_for_fsrs()` scans
  backwards and **drops all history before that point**. Test:
  `card_reset_drops_all_previous_history`.

Both keep the pre-reset rows permanently, for audit and analytics. That matches this
project's own rule that negative evidence never erases positive
([ProgressModel](ProgressModel.md) R1) and the owner's point that an effort index must not
fall because the learner chose to revisit a word.

**Why a separate axis, not a `ReviewOutcome` case.** A reset carries no grade. Putting it
in the outcome taxonomy would make every `isPositive` switch answer a question about
something that was never asked. `ReviewEventKind` is the column; `ReviewOutcome` stays the
grade — the same split Anki draws between `type` and `ease`.

**Rejected.** *Deleting the events.* It is the obvious implementation and it is wrong:
history is the only record of work done, and the log is append-only by design.

## Path to the optimal non-dual modern structure

The dual lifecycle is a deliberate, *reversible* compromise for Legacy. The target
end-state (for the modern rewrite, or for Legacy if iOS 12 is later dropped) is
**scene-only**, and the code is factored so getting there is a clean deletion, not a
rewrite:

1. **Delete the iOS 12 surface only.** Remove `AppDelegate`'s `window` property, its
   `window?.tintColor` line, and `application(_:open:options:)`; remove
   `UIMainStoryboardFile` from `Info.plist`; remove the `@available(iOS 13.0, *)` gate on
   `SceneDelegate`. `AppRoot` and `SceneDelegate`'s use of it stay **unchanged** — that is
   the payoff of routing both paths through `AppRoot`.
2. **Then modernize structurally** (independent of the lifecycle), per `uikit-app-structure`:
   feature-first folders (TD-1), split the single `Main.storyboard` and inject dependencies
   into view controllers via `instantiateViewController(identifier:creator:)` (TD-5), rename
   `…Manager` → `…Controller` for shared controllers, and replace the deprecated Today
   extension with WidgetKit (TD-4).
3. **Modern rewrite (separate app).** A fresh, iOS-26-floor app for new devices — no dual
   branching, free to adopt async/await, `@Observable`, and Liquid Glass throughout, and to
   embed SwiftUI natively (`swiftui-uikit-interop`) rather than as `@available`-gated islands.

## Target membership (why the reorg is staged, not bulk)

The Xcode project uses **synchronized folders** (`PBXFileSystemSynchronizedRootGroup`,
Xcode 16). Several app files are shared into the **Widget** and **ImportAsDictAction**
targets via `membershipExceptions` in `project.pbxproj`
(`WordsModel.swift`, `Storage.swift`, `Settings.swift`, `AppConstants.swift`,
`String+.swift`, `UserDefaults+Codable.swift`, `Debug.swift`). Moving any of those
files changes their path, which must be reflected in the exception entries — and
verified with a build. This is exactly the "target membership" gotcha the
`uikit-app-structure` skill warns about, so the reorg is executed in verified slices
rather than one blind move.

## See also

- [Roadmap](Roadmap.md) · [TechDebt](TechDebt.md)
- `uikit-app-structure`, `software-development-principles` skills.
