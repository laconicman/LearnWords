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

## Decision: keep the deployment target at iOS 12.1 (dual lifecycle) — **superseded (2026-09-14)**

**Superseded by the decision below**, and not by a change of mind: App Store Connect refused a
`MinimumOSVersion` of 12.1 outright. Everything this decision weighed was correct at the time and
is kept because the *reasoning* still applies to what 15 costs — only the premise, that an iOS 12
build could be delivered at all, has been removed.

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

## Decision: the floor is iOS 15, because Apple stopped accepting anything lower

**Decision (2026-09-14).** `IPHONEOS_DEPLOYMENT_TARGET = 15.0` for every target. The dual
lifecycle collapses to scene-only. The plan that executes this is
[TASK-iOS15-migration](TASK-iOS15-migration.md).

**Not a choice.** Uploading 1.2.2 (9) failed with `90068`, *"This bundle is invalid. The value
provided for the key MinimumOSVersion '12.1' is not acceptable"*, `state: FAILED`. A second,
softer message in the same response gives Spring 2027 as the date all iOS apps must be at 15.0 or
later. The first blocks today; the second says where this ends.

**Why 15 and not the smallest number that would pass.** Apple publishes no current floor — the
upcoming-requirements page names only the Xcode 26 / iOS 26 SDK rule — so any value between 12.1
and 15.0 would have to be found by failed uploads, and would then have to be raised again before
Spring 2027. And the superseded decision above already did the device arithmetic: iOS 13, 14 and
15 share one device floor, the iPhone 6s / SE 1. Only iOS 12 reached the 2013–14 tier, and that
tier is precisely what can no longer be delivered to.

**What it costs, honestly.** The tier the Legacy floor existed to serve — iPhone 5s / 6 / 6 Plus,
iPod touch 6, iPad Air 1, iPad mini 2–3 — keeps whatever build the store already serves it and
receives nothing further. That is Apple's doing rather than this project's, but it is still the
cost, and the Roadmap's entire "Now" section was written on the assumption it could be avoided.

**What it does not cost: a port.** The toolchain never objected — `iPhoneOS26.5.sdk` declares
`MinimumDeploymentTarget = 12.0` — so raising the number breaks nothing. Of 56 availability
guards, 45 become dead branches that still compile and still behave correctly. Deleting them is
cleanup with a green suite either side of it, not repair.

**The two-app split survives with a new justification** (owner, 2026-09-14). "Legacy" can no
longer mean *serves 2013–14 hardware*. It now means *the UIKit app on a stable floor*, and the
modern app stays a separate future product justified by what iOS 26+ can do — on-device ML, the
language and translation frameworks — rather than by lifecycle tidiness. **No SwiftUI rewrite
comes with this migration.** iOS 15 is adopted for stability and for modern concurrency, which is
what turns TD-56's deferred "if the floor rises, do it properly" branch into the one to build.

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

**That cost was paid once, in 1.2.1 — and does not recur. Verified 2026-09-13.** The decision
above is about the move *from* `UserDefaults`, which shipped in 1.2.1 (29 July 2026). Every model
change since — `f833280` adding `Pronunciation`, `Variety`, `Tag.category` and
`Language.wiktionaryCode` — is additive, and Core Data migrates it automatically even though the
`.xcdatamodeld` carries a single version: the store's own schema is enough for an inferred
lightweight migration, so no old model version has to ship.

Checked two ways rather than argued. A store written with the 1.2.1-era model, holding a row,
opens under today's model with the row intact and the default `shouldMigrateStoreAutomatically` /
`shouldInferMappingModelAutomatically`. And the real app: a 1.2.1-era build installed on a
simulator, two words imported, then the release candidate installed over it — 25 terms, 1 set and
both canary words before and after, `ZPRONUNCIATION` and `ZVARIETY` added, no crash. This matters
because `LWPersistence.configure` calls `fatalError` when the store will not open: a failed
migration is not a silent degradation, it is every existing user crashing at launch.

**What this does not license.** An *incompatible* change — renaming an attribute, changing a
type, adding a non-optional attribute without a default — cannot be inferred, and with one model
version in the bundle there is nothing to migrate from. Such a change needs a new model version
added to the `.xcdatamodeld` **before** it ships, and CloudKit constrains it further: production
record types and fields cannot be deleted or renamed at all.

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

**Amended (2026-07-26, iteration 4).** `Tag`, `Language` and `ErrorTag` *do* now carry a
`UUID`, and the reasoning above is why it took a real cause to add one. Enabling CloudKit
supplied it: `objectID` is device-local, so it cannot order two rows that arrived from
different devices, and merging duplicates requires every device to choose the **same**
survivor. The UUID is a merge tie-breaker, never a lookup key — `code` and `name` remain
the natural keys. The satellites (`Comment`, `Illustration`, `WordForm`) still have none:
they are created only as part of their owner, so two devices never author "the same" one.

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

**Corrected (2026-07-26, iteration 4) — a UUID can only satisfy the rule by being
optional.** Iteration 1 read `momc`'s acceptance of `defaultValueString` on a UUID as
"defaulted", recorded it as a documented exception, and the schema test carried an
explicit UUID exemption. That was wrong, and switching the container proved it: the store
refused to open.

```
CloudKit integration requires that all attributes be optional, or have a default value
set. The following attributes are marked non-optional but do not have a default value:
ErrorTag: id, Language: id, ReviewEvent: id, ReviewEvent: promptTermID,
ReviewEvent: sessionID, ReviewEvent: wordSetID, Synset: id, Tag: id, Term: id,
WordSet: id
```

Core Data ignores that string — `defaultValue` stays nil — and CloudKit's runtime check
reads `defaultValue`, not the model file. So **every UUID attribute is now `optional`**
and the placeholder defaults are gone; they only ever looked like a guarantee. The Swift
accessors stay non-optional, which is this decision working exactly as written: the code
keeps the promise (`awakeFromInsert`, and the call site that logs an answer), and these
fields exist from v1, so no synced record can arrive without them.

The schema test lost its exemption and now runs CloudKit's rule verbatim, with no
exceptions — it would have caught this.

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

## Decision: language codes are Wiktionary-shaped; variety is its own dimension

**Decision (owner, 2026-07-26).** `Language.code` holds a **bare language subtag in
Wiktionary's spelling** — `en`, `ru`, `zh`, `haw`. Two letters where ISO 639-1 has a code,
three where it does not (BCP 47's shortest-code rule, which is why the set of codes looks
like a mix of lengths). Region and script are **not** part of a language's identity:
`en-US`, `en-GB` and `en` are one language, and so are `zh-Hans` and `zh-Hant`.

**Why Wiktionary rather than Apple's `Locale`.** The corpora we intend to read for
enrichment (TD-22) speak it, and it is internally consistent. `LanguageCode` implements it
with an explicit table, verified against the live registry
(`Module:languages/data/2`, 177 two-letter codes) — which caught two cases where following
`Locale` would have corrupted the store:

* `iw`, `in`, `ji`, `jw`, `mo` are **absent** from Wiktionary, so they must resolve to
  `he`, `id`, `yi`, `jv`, `ro`. Left alone they are *second rows for languages already in
  the store* — a worse instance of the duplicate-row problem than the region case that
  prompted this decision.
* `no`, `nb` and `nn` are **three distinct** Wiktionary languages.
  `Locale.canonicalLanguageIdentifier` maps `no` → `nb`; doing the same here would merge
  two of them.

**Why our own table rather than `Locale` at all.** The stored code is an identity that
syncs between devices, so it must not depend on which OS computed it. `Locale`'s answers
come from the ICU/CLDR data bundled with the system — they vary by OS version, and its
three entry points disagree with each other today. Measured on macOS 15 / iOS 26:

| input | `canonicalLanguageIdentifier` | `components(fromIdentifier:)` | `Locale.Language.languageCode` |
|---|---|---|---|
| `iw` | `he` | `iw` | `iw` |
| `no` | `nb` | `no` | `nb` |
| `zh_CN` | `zh-Hans` | `zh` / `CN` | `zh` |
| `cmn` | `zh` | `cmn` | `cmn` (not ISO) |

`Locale` is for **display names** and **voice lookup**. Identity is decided by us.
(`Locale.Language.maximalIdentifier`, which would resolve `zh-TW` → `zh-Hant-TW`, is
iOS 16+ and unavailable at the floor regardless.)

**Deliberate divergence: `hr`, `sr`, `bs` stay distinct.** Wiktionary folds them into
Serbo-Croatian (`m["sh"]`, `wikimedia_codes = "sh, bs, hr, sr"`). We do not: iOS, the
keyboard and the learner all call them separate languages, and labelling someone's own word
set "Serbo-Croatian" is a worse outcome than a harder enrichment lookup. Wiktionary's own
registry marks the seam — it records `ietf_subtag = "hbs"` because `sh` is ISO-deprecated.
The mapping belongs on the `Language` row when TD-22 lands.

**Region is not lost.** `LanguageCode.parse` returns the stripped subtags as `variety`
("US", "Hans", "Latn-RS") in stable BCP-47 casing. Nothing consumes it yet; it is returned
rather than discarded because silently dropping part of the input is how `en-US` and `en`
became two rows in the first place, and because it is what a `Variety` row will be built
from. Speech is unaffected either way — measured:
`AVSpeechSynthesisVoice(language: "en")` resolves to `en-US`, so a bare subtag never
silences playback; it just forfeits the user's chosen accent, which is a *preference*
concern.

## Decision: variety is a lookup row, not a tag

**Decision (owner, 2026-07-26).** US/UK, Simplified/Traditional and similar belong to a
`Variety` entity related to `Term` (and later to pronunciation rows) — **not** to the
existing `Tag` folksonomy, and not to a `Tag.kind` discriminator.

**Why not tags, given that Wiktionary uses them.** wiktextract emits `sounds[].tags:
["UK","US"]`, `senses[].tags: ["UK"]` and `forms[].tags` — region is never a field anywhere
in its schema. But that is an *interchange format*: denormalised JSONL, one line per entry,
every dimension a string array, because a serialisation format has no joins to protect. It
is not a schema recommendation. The consistent position is to speak Wiktionary's vocabulary
**at the boundary** and store it normalised inside — adopting a JSON file's shape as a
database schema is how `tags: [String]` got into this model in the first place.

**Three reasons a typed tag is worse here.**

1. **Wrong owner.** `Tag` attaches to `Synset` — a folksonomy over *meanings* ("slang",
   "domain:medicine"). Variety is a property of the **`Term`** (which spelling) and of a
   pronunciation (which accent). Reusing `Tag` means adding a second many-to-many
   `Tag`↔`Term`, so the "reuse" saves no table and costs the reader clarity.
2. **Closed registry vs open folksonomy.** Tags are deliberately open — invent
   `domain:knitting` and it works. Variety is closed and registry-backed (BCP 47
   region/script subtags). In one table neither can be validated: the open half forbids the
   constraint the closed half needs.
3. **A `kind` column is a discriminated union in a table.** The kinds have different
   owners, different validity rules and different UI. Anki is the cautionary case: one
   space-separated `notes.tags` string holds user tags, `marked`, `leech` and `::`
   hierarchy at once, with prefix conventions as the only structure.

**Built ahead of its consumer (2026-08-07), reversing the sequencing below.** `CDVariety`
and `CDPronunciation` are in the model now, and nothing reads them yet. The reason is
CloudKit, not need: a production schema accepts additions for ever but never removals, so
the choice was one schema deploy before App Store submission or two. See
[TechDebt § TD-48](TechDebt.md) for what that costs — chiefly that these shapes are derived
from wiktextract's format rather than from a working consumer, and are now permanent.

*The original sequencing, kept because it is the right default:* nothing reads a variety
today, so the entity would otherwise wait for its first consumer — the near-miss coefficient
in `ScoringPolicy` (a variety mismatch is `correctJudged` with a note, never `incorrect`) or
enrichment. `LanguageCode.parse` already produces the value it is keyed on.

**One correction to the reasoning above.** Point 2 called variety "closed and
registry-backed" as against the open tag folksonomy. [Enrichment](Enrichment.md) measured
the source: wiktextract carries **2,062** dialect tags, which we can no more ship and
validate against than a folksonomy. `Variety` is find-or-create exactly like `Tag` and
`Language`. The decision stands on point 1 — the wrong-owner argument — which was always
the stronger leg.

**Also under this decision:** `Term.transcription: String?` cannot hold both /ˈskedʒuːl/ and
/ˈʃedjuːl/, so `Pronunciation` is now the child row with a variety, copying wiktextract's
`sounds[]`. The attribute is **superseded but still live** — `Lexicon` reads and writes it,
and it is permanent in the deployed CloudKit schema regardless (TD-48). New writers should
prefer a row; the attribute goes when a migration retires it.

## Decision: a context-menu preview is a glance, not the screen

**Decision (owner, 2026-09-13, TD-58).** The preview behind a long press builds its own, shorter
content — it is not the pushed screen rendered smaller. Both statistics screens take a
`Presentation` and answer `.preview` with a different set of sections.

**Why it is not a sizing problem.** A context-menu preview is **not interactive**: it cannot be
scrolled, so whatever does not fit is unreachable, not merely below the fold. Any screen laid out
for a full screen will therefore lose its last section to a preview, however the height is
computed. The per-word screen measured its content and asked for all of it; the set screen asked
for nothing and took a default. Both were cut, differently.

**What a glance carries:** the ring the learner just pressed, so the preview speaks the same
visual language as the row it came from; the exercises actually practised; and one line naming
the untouched ones rather than a section each. For a set: the rings and bars, plus *due now* —
the only number in it anyone acts on.

**And a cap.** Previews ask for at most 0.6 of the window height, so the cut, if it ever comes,
is ours rather than the system's.

## Decision: CloudKit mirrors in the app only, and duplicates are repaired after the fact

**Decision (2026-07-26, iteration 4).** The host app opens the store through
`NSPersistentCloudKitContainer` on iOS 13+. Extensions and iOS 12 open the same store
through a plain `NSPersistentContainer`.

**Why extensions do not sync.** A widget reads what the app has already pulled down.
Giving an extension its own mirroring engine would have it compete with the app for the
same store, on a schedule nobody controls, to show the same words.

**Why a failure falls back instead of trapping.** A store that will not open is fatal; a
store that will not *sync* is not. `LWPersistence` attempts CloudKit, and on failure logs
the underlying error and opens the same local store the app has always used. A
provisioning mistake should cost the user sync, not their vocabulary. The error is logged
in full rather than swallowed, because "no iCloud container in this environment" and "the
model is not CloudKit-compatible" both land there and mean very different things — that
logging is what turned the second one from a silent fallback into a fixed bug.

**Deduplication is part of enabling sync, not a follow-up.** Four entities are
found-or-created by a natural key — `Language.code`, `Tag.name`, `ErrorTag.name`, and
`Term` by (text, language) — and uniqueness is enforced in `Lexicon`, in code, because
CloudKit forbids unique constraints. That holds inside one store and **cannot** hold
across two: a phone and an iPad, both offline, each correctly find no existing "bear" and
each create one. Unrepaired, `terms(in: "en")` returns the words hanging off one of the
two `en` rows and half a set silently disappears from practice.

`StoreDeduplicator` merges them on the remote-change notification. Two properties matter:

* **The survivor must be chosen identically everywhere.** If one device merges into row A
  while the other merges into row B, each deletes what the other kept, both deletions
  sync, and the row is gone along with everything pointing at it. Lowest `id` wins — the
  one rule a device can apply without coordinating, and the reason the lookup rows gained
  a UUID.
* **`Language` is merged before `Term`**, because a term's natural key includes its
  language; comparing against un-merged language rows would call two identical words
  distinct.

Relationships are re-pointed from the entity description rather than written out per
entity, so a relationship added later is carried automatically.

**Done, 2026-09-13** — and the reasoning above it was half wrong, so it is worth keeping
straight. The Push Notifications capability is enabled on the App ID and `aps-environment` is
in the entitlements. What was *not* needed is any code: Apple's guide to syncing a Core Data
store with CloudKit states that no app code is required, and the system creates the background
task that imports. An earlier version of this project registered for remote notifications and
implemented the delegate handler; both were removed, because completing that handler at once
told the system the work was finished before the import had begun.

## Decision: a write is visible to the next read, synchronously

**Decision (2026-07-27).** `LWPersistence.write` merges its save into the view context
**before it returns**. When a write completes, every subsequent read sees it.

**Why.** `automaticallyMergesChangesFromParent` merges when the did-save notification is
delivered, which for a main-queue view context is the next turn of the run loop. Meanwhile
a fetch returns already-registered objects *without* refreshing their values
(`shouldRefreshRefetchedObjects` is false by default). So a caller that wrote and
immediately re-read got the previous values back — and a second edit to the same field
appeared to do nothing at all, because the screen re-read the stale copy and wrote it
again. Every editor screen reads straight after writing; so does every test.

**How.** The did-save notification is captured and merged *after* `performAndWait` returns,
not inside the observer: the notification fires on the background queue, and hopping to the
main queue from there while the main thread is blocked on that same `performAndWait` would
deadlock.

**Rejected.** *`shouldRefreshRefetchedObjects = true` on each fetch.* It patches the fetch
paths one at a time and says nothing about relationship traversal, where `senses(in:)`
reads. The contract belongs on the write, which is the one place that knows something
changed.

**Found by probing, not reasoning.** Two tests failed in a way the code did not explain;
the answer came from printing what was actually stored across three successive writes.
Worth remembering as the faster route when a Core Data result contradicts the code.

## Decision: reminders are scheduled, not fired

**Decision (2026-07-27).** Local reminders are a **rolling 14-day window of dated
requests, one per day the schedule predicts work**, rebuilt whenever the app can see fresh
state — on backgrounding, on foregrounding, and on `storeDidChangeRemotely`. Days with
nothing due get no request. There is no repeating daily trigger.

**Why, and why not AnkiDroid's design.** AnkiDroid sets a plain daily alarm and computes
the due count *at fire time*: a `BroadcastReceiver` wakes, opens the collection, and only
then decides whether to post — staying silent when the count is under a threshold, or when
the learner already studied today. **iOS cannot do this.** A `UNNotificationRequest` has
its content baked in at schedule time and runs no code at delivery; only a *remote* push
can be rewritten in flight by a service extension. So both suppression paths have to move
to schedule time, and that is the whole design.
([DeepWiki consult](https://deepwiki.com/search/how-does-ankidroid-remind-user_8f0745fe-717a-4d87-a999-f41dacfa7ff3?mode=deep),
`ankidroid/Anki-Android`, 2026-07-27.)

**Rejected: one repeating daily trigger.** It is what the consult recommended for iOS, and
it is simpler — one pending request, immune to the 64-request cap. It also fires whether or
not anything is due, which is exactly the nagging AnkiDroid added a threshold and an
"only if no reviews today" switch to prevent. Scheduling per-day lets us keep both.

**Rejected: scheduling from the next due date alone.** FSRS intervals grow exponentially, so
a single next-due reminder can go quiet for a month while other words come due tomorrow.

**The count is a prediction, bounded three ways.** A meaning's `dueAt` is fixed by its last
answer, so between rebuilds a date can only *arrive*, never retreat — the count can only
under-state. Practising happens with the app open, which rebuilds. The one case that can
over-state is another device doing the work, which is why a remote change rebuilds too.

**Cost (accepted).** After a fortnight of silence the window runs out and reminders stop.
Deliberate: once a day is missed everything stays overdue, so a lapsed learner is reminded
daily for two weeks and then left alone. An app that nags forever gets deleted.

## Decision: one background mode, and it is the one CloudKit needs

**Decision (2026-09-14).** `LearnWords/Info.plist` declares `UIBackgroundModes` =
`remote-notification`, and nothing else. `fetch` and `processing` are not declared, and nothing
registers work with `BGTaskScheduler`.

**Background modes are not entitlements**, which is what misleads here — the app has four
entitlements files and none of them says anything about background execution. `UIBackgroundModes`
is an Info.plist array; Xcode's Background Modes capability edits that plist and no `.entitlements`
file, and no App ID capability corresponds to it. Nothing is missing from the entitlements.

**The one background API in the tree needs no mode.** `ReminderScheduler.rebuild` takes a task
assertion — `beginBackgroundTask(withName:expirationHandler:)` — so its chain of async round trips
to `UNUserNotificationCenter` survives being backgrounded halfway through, which is the difference
between a rebuilt window and a half-rebuilt one that stays wrong until the next launch. A task
assertion is available to every app: Apple's documentation names no background-mode prerequisite
for it, and points at the Background Tasks framework only "for background tasks requiring more
time". It
extends a run already under way and can never start one, so it is not a weaker version of a
scheduled task — it is the other thing, and neither substitutes for the other.

**A mode with no handler behind it buys nothing.** `fetch` and `processing` pair with
`BGAppRefreshTask` and `BGProcessingTask`; with nothing registered and no
`BGTaskSchedulerPermittedIdentifiers` in the plist, the system has nothing to launch the app into,
so declaring them changes no behaviour at all. They are not free either — an unused background mode
is a standing App Review rejection line.

**Why the reminder window does not need `fetch` today.** The obvious worry is the 14-day horizon
above running dry while the app is never opened. The rebuild fires at launch, on
`didEnterBackground`, on `willEnterForeground`, and on `LWPersistence.storeDidChange` — and that
last one covers a CloudKit import, because `remote-notification` already lets a silent push wake
the app and Core Data's own background task do the import. Running out therefore takes a fortnight
with no launch *and* no change from any device, and the accepted cost above says that learner
should be left alone anyway.

**What would change this, and the rule for changing it.** Moving the per-launch rebuild onto a
schedule (TD-62) earns `fetch`; fetching audio for `Pronunciation.audioURLString` — long,
discretionary, best done plugged in and idle — earns `processing`. Declare either **in the same
change as its handler**, never ahead of it: a mode added early is indistinguishable from a mode
added by mistake, and the plist is the half of that pair App Review can see without running
anything.

## Decision: practice is due-driven, with studying ahead as a deliberate choice

**Decision (2026-07-27).** `PracticeSession.Scope` splits `.due` from `.everything`. The
exercise buttons use `.due`; when nothing is due the chooser offers **"Practise anyway"**
rather than refusing. Answers are recorded identically either way.

**Why.** It is Anki's own split — `StudyOptionsState.Congrats` turns the Study button into
*Custom Study*, whose "Review ahead" builds a filtered deck of not-yet-due cards that the
scheduler then reschedules through the normal path. No separate recording path, there or
here: practising early is worth less, and the model already expresses that through FSRS
stability rather than through a second kind of event.

**Ordering within a sitting** is most-overdue-first, never-seen last, with an explicit
random tiebreak. The tiebreak is a field rather than `shuffled().sorted()` because Swift's
sort is not stable, so relying on it to carry a prior shuffle through ties would be relying
on unspecified behaviour — and without it a fresh set, where everything ties at "never
seen", would be asked in insertion order every single time.

## Decision: a permission is read, never remembered

**Decision (owner, 2026-07-27).** The app never stores its own copy of whether a system
permission was granted. Every feature that needs one re-reads the live status at the point
of use *and* whenever the screen showing it appears, and says what still works without it.

**Why.** Apple's guidance is explicit, and the app was breaking it:
*"Always check your app's authorization status before scheduling local notifications.
People can change your app's authorization settings at any time."*
([Asking permission to use notifications](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications).)
The reminder switch had stored its own answer, so revoking notifications in Settings left
the preference reading "on", the switch drawing "on", and nothing ever arriving.

**A preference and a permission are different things, and both are kept.** The preference
records what the learner *wants*; the permission records what the system currently
*allows*. When the two disagree the UI follows the permission — but the preference is not
overwritten, because re-allowing notifications in Settings should restore the reminders
they asked for rather than requiring them to ask twice.

**Authorized is not the same as visible.** A notification can be authorized while alert,
sound and Notification Center are all disabled: scheduling succeeds and nothing is ever
seen. `UNNotificationSettings` exposes those separately and they must be read separately —
`ReminderScheduler.Standing.silenced` is that case, and a bare `authorizationStatus` check
misses it.

**Not every refusal is a trip to Settings.** A first decline can simply be asked again next
time; only a *revoked* grant needs the Settings app. Sending someone to Settings for a
decision they have not been asked to reconsider is a dead end dressed as help, so
`DictationController.Failure` distinguishes the two and only one offers the button.

**Applies to all three permissions the app uses** — notifications, speech recognition,
microphone. `DictationController` re-reads the latter two on every start for the same
reason.

## Decision: repair and derivation are two debounces, chained not merged

**Decision (2026-07-28).** The store has two coalescing layers and they stay separate:

| | Deduplication | Schedule rebuild |
|---|---|---|
| Trigger | `NSPersistentStoreRemoteChange` only | any write, local or remote |
| Work | **repairs** rows sync duplicated | **derives** an index from rows |
| Window | 2s — an initial sync posts many notifications | short; nothing is visibly wrong meanwhile |
| If skipped | duplicate rows persist | reminders are stale until the next trigger |

Merging them into one debouncer would be DRY at the level of *mechanism* and wrong at the
level of *policy*: one is triggered by a subset of the other's triggers, they have different
windows, and one must complete before the other starts.

**Ordering is the part that matters.** A derivation must never read the store mid-repair.
Today's arrangement gets this right only by accident — dedup posts `storeDidChange` when it
finishes, but a *local* write posts immediately, so a rebuild can overlap a repair in
flight. The intended reading of `storeDidChange` is **"the store is quiescent"**, not "a
save happened"; when the rebuild debounce lands (TD-34) it should be subordinate to the
repair rather than parallel to it. Recorded here because the current code does not yet say
this out loud.

**The boundary is the mechanism, not a convention.** `Lexicon` returns value types and its
`viewContext` is `private` for one reason: a managed object outside it is a managed object
whose queue nobody is tracking. That was breached once, by an `internal fetchTerms` returning
`[CDTerm]` so a query in another file could reach the context — Swift's `private` being
file-scoped makes that the tempting shortcut. The query moved to where the context is
instead. **If a read needs the context, the read belongs inside `Lexicon`.**

**What is protected today, and what is not.** Core Data's own confinement is sound: writes
go through `performAndWait` on a private-queue context, reads are main-queue, `pendingDedup`
is touched only on `dedupQueue`. The *derived* layer was not: `ReminderScheduler.rebuild`
has four triggers and four async hops, and two overlapping runs would resurrect reminders
the newer one had correctly dropped — fixed with a generation counter, not by serialising,
because nobody wants the previous schedule applied late.

## Decision: Swift Concurrency, when the floor allows it

**Not available today.** Swift Concurrency back-deploys only to **iOS 13**, and the floor is
12.1. This records what changes when that moves, so the current callback code is understood
as a deferral rather than a preference.

**At iOS 13** — `async`/`await`, actors, `AsyncStream`:

- `ReminderScheduler` becomes an **`actor`**, and the generation counter above stops being
  necessary: overlapping rebuilds become impossible by construction rather than by a
  discipline someone has to remember. This is the single largest win, because it converts a
  class of bug into a compile-time property.
- The two debouncers become one generic type over an `AsyncStream`, with the difference in
  *policy* (window, trigger, ordering) expressed as parameters rather than duplicated code —
  the DRY that merging them today would not achieve.
- `DictationController`'s two closures become one `AsyncStream<Heard>`; `isStopping` becomes
  actor state instead of a flag touched from a recogniser callback and the main queue.
- `Sendable` costs almost nothing here: `Sense`, `Term` and `ReviewEvent` are already value
  types precisely because managed objects never escape the store. That decision, made for
  threading discipline, turns out to be the migration's prerequisite.

**At iOS 15** — `NSManagedObjectContext.perform` gains an async form, so `LWPersistence.write`
becomes `async throws -> T` and drops `performAndWait`; `UNUserNotificationCenter` gains
`notificationSettings()`, `pendingNotificationRequests()` and `add(_:)`, collapsing
`rebuild`'s four nested callbacks into straight-line code where the background-task
assertion is a plain `defer`.

**What does not change.** The synchronous `Lexicon` API is a *floor* constraint, not a
design one — the read/write boundary and the value types either side of it stay exactly as
they are. Migration is mechanical, which is the point of having drawn the boundary there.

## Decision: a meaning nothing can reach is deleted, not kept

**Decision (owner, 2026-08-01).** Removing a word from its last set **deletes** the meaning.
Meanings stranded by other paths are collected at launch, whether or not they carry history.

**What this reverses.** The earlier rule kept them, reasoning that a review history is
evidence of work done and the effort index must not fall because a set was reorganised. The
flaw is that such a meaning is **unreachable**: nothing in the app can list, practise,
search or restore it, and every index is built from the meanings *in a set*, so it
contributes to nothing. Keeping it preserved no work — it leaked rows, and eventually leaked
one into the duplicate hint.

**The owner's argument, which is the deciding one:** even in principle the retained history
could not be justified, because there is nothing left to say *which definition* the work was
against. Effort you cannot attribute is not effort you can report.

**The log is not what is being deleted.** `ReviewEvent.synset` is a **nullify** relationship
and every event carries text snapshots of the prompt, the answer and both languages — the
decisions in *"a manual reset appends a marker"* and *"the lexical model"* were made for
exactly this. The record that the work happened survives; only its attribution to a meaning
goes.

**Cost (accepted).** A learner who deletes a word and re-adds it starts its history over.
That was already true in practice — nothing could reattach an orphan — so the change makes
the store honest about it rather than changing what the learner experiences.

## Decision: a meaning belongs to many sets — **closed by the deploy (2026-08-09)**

> **Resolved, and not by choosing.** The model ships `Synset.sets` ↔ `WordSet.synsets` as
> many-to-many, and TD-48 established that the production CloudKit schema was deployed
> before anyone read the deadline protecting this choice. Narrowing to to-one would change
> the cardinality of a relationship that is already mirrored in an immutable production
> schema — the same add-only rule that made `Term.transcription` permanent. The window
> that the section below says is "free today" had already shut when it was written.
>
> **The outcome is the one this section recommends**, so the loss is the optionality, not
> the design: many-to-many was the argued preference, and it is what is deployed. Two
> consequences are now permanent rather than provisional:
>
> 1. **`deleteOrphanedSenses` is architecture, not a stopgap.** Reference counting is the
>    one rule Core Data's four deletion rules cannot express, so with many-to-many
>    permanent, the sweep is permanent too — it will never be retired by a narrowing
>    migration. TD-26 already gave it the right semantics (removal deletes when the last
>    set lets go; the collector catches what other paths strand, history or not); what
>    changes is only its status: a fixed part of the design rather than a placeholder.
> 2. **A shared "Hard words" set is unlocked** — the feature that justified many-to-many
>    can be built whenever wanted, with one history rather than a forked duplicate.
>
> A new container identifier remains the only way to reset a production schema, and with no
> users it is still free (TD-48) — but spending it here would buy a *worse* model, so it is
> moot. Verified in passing: the code is already many-to-many-correct — `Lexicon` iterates
> `sense.sets`, orphan detection is `sets.isEmpty`, and the word editor already displays a
> meaning's several set names. No single-set assumptions to unpick.

The original analysis, kept because the reasoning still explains the design:

**Why it is open.** `deleteOrphanedSenses` exists because Core Data cannot express the rule
we want. Its four deletion rules are No Action, Nullify, Cascade and Deny; none of them is
*reference counting*. `Cascade` on `WordSet.synsets` deletes a meaning when **any** holding
set is deleted, even if another set still holds it — so with a many-to-many, "delete when
the last set lets go" cannot be a schema rule and something has to sweep.

**Unless the relationship is to-one.** If a meaning belonged to exactly one set,
`Cascade` would do the entire job in the schema: the explicit delete in `removeSense` and
the collector would both disappear, and orphans would become unrepresentable rather than
merely collected.

| | Many-to-many (today) | To-one |
|---|---|---|
| Orphans | swept, by code that must keep working | impossible by construction |
| "Favourites"/"Hard words" holding a meaning already in another set | natural | needs a duplicate meaning, with split history |
| Cost of being wrong | a sweep runs forever for nothing | a feature needs a schema change after deploy |

**What is actually shared today.** The redesign specified sharing the *`Term`* — the atomic
word — which stays many-to-many with meanings and is doing real work. A whole *meaning* in
two sets is a different claim, and **nothing in the app yet creates one**: the branch is
reachable only through a CloudKit merge.

**Recommendation: keep many-to-many, keep the collector.** A set like "Hard words" holding
the same meaning as "Animals", sharing one history rather than forking it, is the obvious
next feature and the many-to-many is what makes it possible. The collector is eight lines
run once per launch — a small, visible price for a model that can say what it means.

~~**But decide deliberately, and decide now.**~~ *(Superseded — see the decision above. The
deploy this sentence planned around had already happened; the choice was settled by it, on
the recommended option.)*

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

## Decision: two export formats, and only one of them comes back

**Decision (2026-07-27).** `PlainText` stays the app's own format and is **symmetric** —
`parse` and `render` are inverses, which is what makes "the user can always import the
dictionary" a real answer to dropping migration. `AnkiText` is **export only**: it
implements a foreign application's contract, and nothing reads it back. The export button
asks which, because neither is the obvious default and a single button would have to
silently pick one.

**Why the contract was read from source rather than the manual.** The Anki manual documents
the import *dialog*; what matters is what the parser does. Checked against `ankitects/anki`
([DeepWiki consult](https://deepwiki.com/search/i-want-to-generate-a-text-file_0d3f96ff-c839-45e0-a6ab-4d09401cba0c),
2026-07-27), which settled four things guesswork would have got wrong:

- **`#` is the record reader's comment character**, not just a header marker. An unquoted
  row beginning with `#` is dropped in silence, so a word like "#hashtag" must be quoted.
- **Metadata columns are excluded from field mapping.** `#tags column:` / `#guid column:`
  are removed before fields are assigned, so a four-column row still fills the two-field
  `Basic` notetype correctly. Without that guarantee the layout below would put a UUID on
  the front of every card.
- **`#html:false` makes Anki do the escaping** — it escapes `<`, `>`, `&` and turns each
  newline into `<br>`. So this exporter writes **no markup at all**: there is no escaping
  of ours to get wrong, and no way for a word to inject markup into a card.
- **A text import cannot carry a notetype or its card templates.** `#notetype:` only
  selects an existing one, and silently falls back to the user's last-used notetype when
  the name is unknown.

**Correction.** An earlier roadmap note said the exporter had to emit the learner's locale
so `{{tts en_US:Front}}` would work. That was wrong: templates live in the notetype, a text
file cannot carry one, and there is nothing the exporter can do about TTS. A user who
builds a speaking notetype can point the file at it by editing one header line.

**Column order is a compatibility decision.** `front, back, tags, guid` — metadata last.
The `#` directives only exist in Anki 2.1.54 (Nov 2022) and later; older versions drop
every `#` line. With metadata trailing, an old importer that ignores columns beyond the
notetype's field count still gets front and back in the right places.

**Why a GUID column.** It makes the export *re-importable*. Anki otherwise identifies a
note by its first field, so a second export after an edit would either duplicate or
overwrite by accident — and two meanings of one word ("bear" the animal, "bear" the verb)
would collide into a single note. A GUID bypasses first-field matching entirely, and Anki
accepts any non-empty string. `Sense.id` is already a stable UUID that survives edits and
the deletion of the words themselves (TD-18), so it is exactly the right key. Paired with
`#if matches:update current`, not `keep both` — under `keep both` a GUID match is *skipped*
rather than duplicated, because a GUID match is an identity match, not a content collision.

**The disambiguation note goes on the front**, where the app itself shows it: a question
that does not say which "bear" it means cannot be answered.

**Not attempted: `.apkg`.** A real Anki package is a zipped SQLite collection, and writing
one would mean implementing Anki's schema, its media database and its compression — for a
format the owner's own reference
([Word-Hoarder](https://github.com/itincknell/Word-Hoarder#creating-a-flashcard-file))
does not use either. Text is what the file importer reads, and it is what a vocabulary
list needs.

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
