# Roadmap

Priority-ordered. Rationale lives in [Design](Design.md); debt items in [TechDebt](TechDebt.md).

## Now

- **Ship the iOS 12 fix.** The App Store is the only route that reaches an iOS 12 device —
  TestFlight's own minimum is far above it — and the store serves the last compatible build
  to devices that cannot run the current one. Submitting also spends the CloudKit schema
  deploy that TD-48's additions are waiting on, which is why they went in first.
- **iOS 12 *behaviour* is still unverified.** Launch is proven (below); the store changed
  completely under TD-13 and none of it has run on iOS 12. Word list, add/edit a word, all
  three exercises, import/export, the Today widget. TD-8's toolchain works today — its value
  decays as more code lands behind an untested boundary.

## Done (2026-08-04) — iOS 12 launches

Verified by the owner on an iPad running iOS 12: builds on Xcode 15.2 and launches.
Three faults had to be cleared first, none of them visible on any simulator this project can
run — asset formats only Xcode 26 understands (TD-45), a hard link to Core Haptics that
`dyld` refused at launch (TD-46), and a tab bar built twice (TD-47).

## Done (2026-07-17)

- **UIScene dual lifecycle** — iOS 13+ `SceneDelegate`, iOS 12 `AppDelegate`, both through
  `AppRoot`; floor 12.1 (reverses the earlier iOS-15 decision — see [Design](Design.md)).
  Built + launched (light/dark) on a modern sim; TD-7 audit clean.
- **Feature-first reorg of source** (TD-1) — all 30 `.swift` files into
  `App/ Model/ Controllers/ Shared/… Features/*`; `membershipExceptions` updated (TD-2);
  all three targets build; app launches. Resources deferred.
- **Doc consolidation** (TD-9) — obsolete `Documentation.docc` scaffold deleted; `docs/` is
  the single source.
- **iOS 12 storyboard colors** (TD-11) — semantic colors → named asset colors; verified
  light/dark on a modern sim. Icons deferred (text-only on iOS 12).
- **Test seed** (TD-6) — Swift Testing bundle, now 21 passing cases (`WordAndStat` logic,
  `canonicalise`, launch smoke test, `UserDefaultsWordStore`).
- **`WordStore` persistence seam** (TD-12) — `WordStore` protocol + injectable
  `UserDefaultsWordStore` + thin `Storage` facade; 8 store tests; app verified. Sets up the
  Core Data migration (TD-13).

## Done (2026-07-18)

- **Dual widgets** (TD-4) — WidgetKit `WordWidgetExtension` (iOS 14+, floor 14.0, App Group
  entitlement, reads `Storage` via shared membership) + legacy Today extension retained for
  iOS 12–13 (already at the inherited 12.1 floor). Build green, `.appex` embedded. Remaining:
  visual check on home screen; app-side `WidgetCenter` reload nudge.

- **Share-import deep link** (TD-3) — import extracted to `WordImport` (+10 tests), consumed
  idempotently on appear/foreground/deep-link; `AppRoot` selects the tab instead of rebuilding
  the root. Cold path verified on-sim end to end; one manual share-flow run covers the rest.

- **Speech silent until Phonetics** (TD-15, 2026-07-19) — root-caused to the shared
  audio session only ever being configured by the Phonetics screen; `SpeechManager` now
  ensures it on `speak()`. Regression test added (32 total). Owner to confirm by ear.

- **In-app settings replace Settings.bundle** (TD-14, 2026-07-19) — pane deleted; defaults
  code-registered into the App-Group suite (+ one-time migration); new `Features/Settings/`
  screen with live slider values. Build green; test run + visual check pending a
  CoreSimulator restart on the dev machine.

- **Animation crash hotfix** (TD-16, 2026-07-19) — `[unowned self]` → `[weak self]` in all
  six copy-pasted exercise animations; owner confirmed TD-14 settings screen and TD-15
  speech on-device (remaining console lines are benign — see TD-15).

- **TD-16 adoption (2026-07-19, fixed 07-20)** — `ExerciseTransition.show`/`advance`
  replace the six copied animator blocks (lifetime-tested); KaPow linked (local SPM,
  iOS 12 floor); shake/shine/level-up-spray wired in all three exercise screens. First
  cut blanked the exercise screens (entry spring-in removed — owner caught it); fixed +
  locked by a storyboard-driven appearance test. 38/38 tests green. Manual feel-pass
  pending (see `TASK-TD16-adoption.md` § Verification).

- **TD-21 + RU strings** (2026-07-20) — the Words tab's search bar moved from
  `tableView.tableHeaderView` to `navigationItem.searchController`, so it no longer shows
  through the transparent iOS 26 nav bar behind the button capsules (the original TD-21
  diagnosis blamed a nav title; there is none). 21 missing Russian strings added — the
  TD-14 settings screen, language names and the permission alerts; `Localizable.xcstrings`
  now has full `ru` coverage. Manual TD-16 feel pass done by owner: animations OK.

- **Word-cell constraint conflict fixed** (TD-17, 2026-07-20) — the per-row unsatisfiable-
  constraints spam (1-pt over-constraint vs the 44-pt ring); pins relaxed to ≥ 4; verified
  clean console + unchanged cells. Ring-replacement research recorded in TD-17.

- **TD-20 complete** (step 2, 2026-07-20) — one `final ExerciseViewController` builds the
  exercise screen in code and is *given* an `ExerciseAnswerSurface`; the three storyboard
  scenes are deleted, so the layout can no longer diverge. Composition rather than an
  abstract base (owner review): requirements are compile-time, not `fatalError` guards, and
  the three surfaces are testable without a view controller. Fixed on the way: the empty-set
  guard sat in `prepare(for:)`, which cannot cancel a segue. Also adopted the
  `ReviewOutcome` taxonomy (verbatim vs judged vs self-assessed — the distinction the screens
  had and discarded) and the `LanguagePair` seam for the per-set-languages decision. 59 tests
  green. **Next up is the big rock**: apply the research audit → TD-18 (word + set identity)
  → TD-13 (Core Data + CloudKit, carrying set languages and the `ReviewEvent` log).

- **`ExerciseSession` extracted** (TD-20 step 1, 2026-07-20) — the round (queue, scoring,
  progress, skip rule, round-end save) lifted out of the three exercise controllers into a
  UIKit-free model type; −53 net lines in the screens, 15 new storyboard-free tests, and
  `Storage.shownWords` retired from the persistence seam. `ReviewEvent` logging for TD-13
  now has one place to land instead of three. Remaining: the shared exercise *layout*, still
  triplicated across three storyboard scenes.

- **Buttons modernized** (TD-19, 2026-07-20) — `GradientButton` → **`LWButton`**: a button
  states a `Purpose`, the control picks the appearance per OS in **one `#available` check**
  (`UIButton.Configuration` + capsule on iOS 15+, 5pt radius on 12–14). Gradients/borders
  kept as an off-by-default theming seam. Also: exercise button geometry equalized (2×2
  grid, 56pt scaled, `Listen` added to Test), layout made stable across words
  (`fillProportionally` → `fill` + `LWWordLabel` autoshrink), check/x symbols on the answer
  pair, and the cramped Direction segmented control replaced by a swap row. Follow-up pass
  after owner review: semantic `LWColors` replace 14 hard-coded RGB literals across the
  exercise screens (answer text now shares the button's green/red and adapts to dark mode),
  Dynamic Type audited end to end — `LWButtonRow` stacks button pairs vertically at
  accessibility sizes instead of truncating, and the chooser became scrollable so
  "Фонетика" stays reachable — and the new `Listen` button picked up its `es`/`ru` strings.
  38/38 tests green; verified on the iOS 26.5 sim in light/dark, English/Russian, and at
  `accessibility-extra-large`. iOS 12–14 path unverified (TD-8).

- **Progress model designed** (2026-07-20) — [ProgressModel](ProgressModel.md): append-only
  `ReviewEvent` log (verbatim/judged/self-assessed outcomes, negatives never cancel
  positives, response text kept for AI judging), derived effort/mastery/retention indexes,
  pluggable near-miss judge (match3 → NL → Foundation Models iOS 26+). This is the TD-13
  schema core; TD-17's ring displays its indexes.

## Next

- **The learning-design batch (TD-49…TD-53), researched 2026-08-09.** Answers four owner
  questions and, notably, **none of them needs a schema change** — the event log already
  carries what they read. Research: [MasteryAndProgressUI](MasteryAndProgressUI.md) and
  [LexicalModelResearch](LexicalModelResearch.md) § *Commas at entry*.
  - **TD-49 — done (2026-08-09).** Memory is per exercise (`StrandProgress`); learned =
    every *engaged* exercise learned, gated on successes across 2 separate days, with the
    preference floored at 10 days and an opt-in "require production". 294 tests green.
  - **TD-54 — withdrawn.** The launch crash reproduced only under `CODE_SIGNING_ALLOWED=NO`,
    which strips entitlements; a normally signed build of unmodified HEAD is fine. The
    `ubiquityIdentityToken` guard was reverted — review flagged that it could have disabled
    sync for everyone, since this app has no ubiquity entitlement.
  - **TD-53 — done (2026-08-11).** A comma at entry proposes **one meaning with synonyms**
    (the owner's pivot, 2026-08-11), laid out on a confirm screen — a section per meaning, an
    empty row after each language's words, an empty section for another meaning — with
    "These are separate meanings" to split and merge to fold back. The pivot made entry, the
    meaning editor and the file format agree that a comma means synonyms. Back now pops to
    the word instead of leaving the flow, which exposed `hasCommitted` as a one-way door.
    Three review rounds found, among others: a single meaning stranding the learner on "Add
    word", Cancel on the duplicate prompt discarding the entry, and renaming storing a word
    with a comma in it. 337 tests green.
  - **TD-55 — recorded 2026-08-11, to build after this batch.** The owner's revision of the
    comma decision: the entry screen should carry the *structure* — "Synonyms" and "Meanings"
    sections, an always-available input row, "Add" in the header — and a comma should advance
    to the next row rather than be parsed afterwards. Closer to the prior art than the
    confirm screen TD-53 shipped, and it makes Tab natural for a macOS port. TD-53's parse
    stays, as the path for text that arrives whole. Open questions in
    [TechDebt](TechDebt.md) § TD-55.
  - **TD-51 — done (2026-08-12).** A set summary built on *distribution*, pivoted by
    exercise: untouched/learning/learned per exercise with the mean beside it, a 14-day due
    forecast, true retention split young/mature from the log, effort, and the
    receptive/productive gap. Rings fill one way and colour carries the bad news (owner's
    call on the open question). Long press a set, as TD-50 does a word. Closes the
    `dueByExercise` test debt from the TD-49 review. 360 tests green.
  - Remaining: **TD-55**, recorded but not built. The rest of the batch is in flight, one
    branch each; every item's state is its heading in [TechDebt](TechDebt.md), which is
    where to look rather than here. Scope and conventions are in
    [TASK-TD53-batch](TASK-TD53-batch.md) (self-contained: scope, the owner's UI asks, the
    build flag that must not be used, and the review loop). TD-50/51 also owe the settings
    switch for `requireProductionForLearned`; the slider minimum is done.
- **CloudKit account setup — [step-by-step](CloudKitSetup.md).** The container does not
  exist server-side yet (`BadContainer` on device), so the app is running local-only. The
  capability, the container and the development-schema upload are all account-side work.
- **Two-device CloudKit verification.** Everything about sync is proven against
  constructed duplicates, not a real merge. Needs the `iCloud.club.laconic.LearnWords`
  container in team `WEJF495R4D`, and two devices on one iCloud account. Until then the
  app degrades to a local store and logs why. **The production schema is immutable once
  pushed — initialise it from a development build first.**
- **Push Notifications capability**, for timely sync rather than launch/foreground/
  CloudKit-schedule. `aps-environment` needs the capability on the App ID, so it belongs
  in Xcode's Signing & Capabilities where the App ID updates in the same step — not in a
  hand-edited plist. (The `remote-notification` background mode, the other half, is now in
  `Info.plist`.)
- **Pronunciation scoring beyond the system recogniser.** `SFSpeechRecognizer.confidence`
  is a proxy for *what* was said, not *how well* — see
  [ProgressModel](ProgressModel.md) § "Pronunciation quality". `ReviewEvent` already carries
  `judgmentVerdict`/`judgeID`/`judgedAt` so a better judge can re-score history. Worth
  evaluating: forced alignment against a phoneme model, on-device Foundation Models
  (iOS 26+), or a dedicated assessment service.
- **`BGAppRefreshTaskRequest` for word-set enrichment** (owner's note, not scheduled). A
  different scope from the CloudKit push that wakes the app for sync: periodic background
  work to prefill terms from the enrichment corpus (TD-22) rather than to react to a
  change. Noted so it is not confused with the reminder rebuild, which needs no scheduled
  task — only a background-task assertion so its async steps survive suspension.
- **Confirm a reminder actually arrives.** The switch is owner-confirmed to request
  permission, so the first half of the path is proven. What is still unwitnessed is the
  second: schedule → deliver → tap → land on Exercises. No automated pass can do it
  (TD-29), so it wants one evening on a device.
- **`SearchWordViewController`, the rest of TD-28.** Two of its four responsibilities are
  out. Rewriting it onto `WordInputViewController` — two pushes of one reusable screen —
  is now cheaper than cutting more out of it.
- **TD-31** — `SpokenAnswerSurface` still owns a second copy of the audio-session
  lifecycle that `DictationController` now expresses. Same condition that produced TD-15.
- **Enrichment (TD-22) implementation** — [Enrichment](Enrichment.md) designs it. First
  measurement any implementing fork must take is the reduction ratio on one real kaikki
  file; every size estimate downstream is a guess until then. Whether FTS5 exists in the
  system SQLite at the 12.1 floor needs an old device (TD-8 territory).
- ~~**`Variety`, `Pronunciation` and `Tag.category`**~~ — **done (2026-08-07)**, plus
  `Language.wiktionaryCode`, which this list had missed. The framing here was wrong: the
  production deploy had already happened, so `Term.transcription` was vestigial before the
  question was asked, and additions were never on a clock — CloudKit accepts them for ever.
  They went in anyway, to spend one schema deploy rather than two. See
  [TechDebt § TD-48](TechDebt.md). **Still to do:** give the new rows a writer (TD-22
  enrichment), and retire `Term.transcription` from the model once they have one.
- **`SearchWordViewController` (TD-28)** — ~600 lines doing search, suggestions, dictionary
  lookup, segue routing and store writes. Every bug in the add-word flow so far has been a
  coordination bug hiding in its size.
- **`CSSearchableItemActionType`** — words are indexed in Spotlight, but tapping a result
  does not route into the app.
- **TD-8 device verification** — iOS 12–14 behaviour is unverified since the store change.
- **TD-26** — orphan collection still has no way to run; **TD-24** — extension bundle
  versions drift from the app's, which App Store Connect rejects at submission.
- Storyboard split (TD-5) is **likely YAGNI** at this size — prefer creator-injection on the
  existing storyboard where a screen needs a dependency; revisit only if the one storyboard
  actually hurts.

## Done (2026-07-27) — word entry, dictation, and permissions that tell the truth

Adding a synonym is a screen rather than an alert: `WordInputViewController`, with
completions, a dictionary lookup, recents, and a **visible dictation button** — the
keyboard's microphone key is easy to miss and absent with a hardware keyboard. The meaning
editor and, next, the add-word flow use the same screen, so the two entry paths cannot
drift apart again.

Two extractions from the massive controllers made it possible and discharge half of TD-28:
`WordSuggestions` (completions and per-language recents, now testable) and
`DictationController` (the recogniser, ~150 lines that had lived inside Phonetics).

Permissions are now **read, never remembered** — see [Design](Design.md). The reminder
switch had stored its own answer, so revoking notifications in Settings left the app
asserting a capability it no longer had. Four states, four different things said, and every
message names what still works without the permission.

## Done (2026-07-27) — spaced repetition and reminders

Practice is **due-driven**: `PracticeSession.Scope` distinguishes studying from studying
ahead, and when nothing is due the chooser offers "Practise anyway" rather than refusing.
`ReviewSchedule` derives what is waiting across the library; `ReminderScheduler` turns that
into a rolling 14-day window of dated local notifications, one per day that has predicted
work. The "Known level" slider is now "Remembered for (days)", the meaning it took on when
scoring moved to FSRS.

The design is AnkiDroid's inverted: it computes the due count *when the alarm fires* and
stays silent if nothing is due, which iOS cannot do — a local notification's content is
baked in at schedule time. Both of its suppression paths therefore moved to schedule time.
See [Design](Design.md) § *reminders are scheduled, not fired*.

## Done (2026-07-27) — Anki interchange format

`AnkiText` renders a set as an Anki-importable tab-separated file with a `Sense.id` GUID
column, so re-exporting updates the same notes instead of duplicating them, and two
meanings of one word never collide. Export is a format choice; `PlainText` is unchanged.

**Correction to this document's earlier claim:** it said an export must emit the learner's
locale for TTS. A text import cannot carry a notetype or template at all — `#notetype:`
only *selects* an existing one — so the exporter has no influence on TTS. A learner who
builds a speaking notetype points the file at it by editing that line. Verified against
`ankitects/anki` source.

## Done (2026-07-27) — the store/UI gap

`addTerm`, `removeTerm`, `renameWordSet` and `findTerms` are reachable from screens.
`MeaningEditorViewController` adds and removes synonyms per language and edits the note —
the first time a user could create the arrangement the seed had been showing them.
`PlainText` round-trips synonyms losslessly, and `LWPersistence.write` now makes a write
visible to the next read (see [Design](Design.md)). Still open: orphan collection has no UI
(TD-26).

## Big rock — Core Data (TD-13) — **iterations 1–5 done (2026-07-26)**

1. **Schema.** `WordSet`/`Synset`/`Term`/`WordForm`/`Comment`/`Illustration`/`Tag`/
   `Language`/`ErrorTag`/`ReviewEvent`, normalised (tags and languages are rows, not
   `[String]`), indexed, Spotlight-indexed.
2. **`Lexicon`.** The only Core Data consumer; value types in and out, no managed object
   escapes. `WordStore`/`UserDefaultsWordStore`/`Storage`/`WordAndStat` deleted, and with
   them TD-18.
3. **The app on the store.** `PracticeSession` records real `ReviewEvent`s; every screen
   and both widget targets read `Lexicon`; plain-text import/export; a manual reset appends
   a marker rather than deleting history.
4. **CloudKit.** `NSPersistentCloudKitContainer` for the host app on iOS 13+; extensions
   and iOS 12 keep a plain container. **The claim that the model was already authored to
   CloudKit's rules was wrong** — every UUID was non-optional with a `defaultValueString`
   Core Data ignores, so the store refused to open. UUIDs are optional now, and
   `StoreDeduplicator` repairs the duplicate rows sync creates (uniqueness lives in
   `Lexicon` because CloudKit forbids constraints, and that cannot hold across two offline
   devices). See Next for what remains before this ships.
5. **Scoring.** `ScoringPolicy` derives mastery, retention and effort by replaying the log
   with a port of FSRS-6 (ported rather than adopted: `swift-fsrs` declares `.iOS(.v14)`
   and this floor is 12.1; checked against that library's own test oracles). Nothing is
   stored — weights live in code, so revising them re-derives history instead of migrating
   it, and CloudKit devices reach the same answer from the merged log. The ring is
   `ProgressRing`, retiring 556 vendored lines.

## Later

- **Naming pass** — `…Manager` → `…Controller` for shared controllers, now that tests exist.
- Move resources beside features (finishes TD-1), once the storyboard direction settles.
- Promote these docs to a rendered DocC catalog (`repo-init`).

## Someday — the modern rewrite (separate app)

Legacy stays iOS 12. New devices get a **from-scratch** app on a modern floor (iOS 26): no
dual branching, async/await and `@Observable` throughout, SwiftUI embedded natively rather
than as `@available`-gated islands. The "delete the iOS 12 surface" recipe in
[Design → Path to the optimal non-dual modern structure](Design.md) is also how Legacy
would collapse to scene-only if iOS 12 is ever dropped.
