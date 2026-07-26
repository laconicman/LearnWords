# Roadmap

Priority-ordered. Rationale lives in [Design](Design.md); debt items in [TechDebt](TechDebt.md).

## Now

- **iOS 12 on-device verification (TD-8) — deferred by owner.** Lifecycle + colors are
  unverified on real iOS 12 until checked on an owner device (visual side-load path in TD-8)
  or Xcode 15. Do before any lifecycle/UI-touching release.

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

- **Two-device CloudKit verification.** Everything about sync is proven against
  constructed duplicates, not a real merge. Needs the `iCloud.club.laconic.LearnWords`
  container in team `WEJF495R4D`, and two devices on one iCloud account. Until then the
  app degrades to a local store and logs why. **The production schema is immutable once
  pushed — initialise it from a development build first.**
- **Push Notifications capability**, for timely sync rather than launch/foreground/
  CloudKit-schedule. `aps-environment` needs the capability on the App ID, so it belongs
  in Xcode's Signing & Capabilities where the App ID updates in the same step — not in a
  hand-edited plist.
- **Spaced repetition and local reminders.** `ScoringPolicy` now yields a due date per
  meaning, but `PracticeSession` still queues the whole set shuffled. Making practice
  due-driven, plus a rolling-window local notification (64-pending cap; a countless daily
  reminder at the 12.1 floor, `BGAppRefreshTask` as the iOS 13+ upgrade).
- **Close the store/UI gap.** `addTerm`, `deleteSense`, `renameWordSet`, `findTerms` and
  `deleteOrphanedSenses` are called from no screen — most visibly, **a user cannot create
  a synonym**; the seed is the only source of one. `PlainText` round-trips synonyms
  lossily too (`render` writes `fox : лиса, лисица`, `parse` reads that as one term).
- **Anki interchange format** — alongside `PlainText`, the shape Anki's file importer
  reads. Reference:
  [Word-Hoarder's flashcard export](https://github.com/itincknell/Word-Hoarder#creating-a-flashcard-file).
  Anki's TTS tag takes an **underscored full locale** (`{{tts en_US:Front}}`) matched by
  exact string equality, so an export must emit the learner's locale preference, not our
  bare `Language.code`, or the card gets no voice.
- **`Variety` rows** — see [Design](Design.md). Its first consumer is either the near-miss
  coefficient in `ScoringPolicy` or enrichment (TD-22).
- **`CSSearchableItemActionType`** — words are indexed in Spotlight, but tapping a result
  does not route into the app.
- **TD-8 device verification** — iOS 12–14 behaviour is unverified since the store change.
- Storyboard split (TD-5) is **likely YAGNI** at this size — prefer creator-injection on the
  existing storyboard where a screen needs a dependency; revisit only if the one storyboard
  actually hurts.

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
