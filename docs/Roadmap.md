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

- **TD-16 adoption (2026-07-19)** — `ExerciseTransition.advance` replaces the six copied
  animator blocks (lifetime-tested); KaPow linked (local SPM, iOS 12 floor); shake/shine/
  level-up-spray wired in all three exercise screens. 36/36 tests green. Manual feel-pass
  pending (see `TASK-TD16-adoption.md` § Verification).

## Next

- **Manual TD-16 pass** — all three exercise screens: transition in/out, wrong-answer shake,
  correct-answer shine, level-up spray; the leave-during-delay scenario on a device.
- **RU strings** for the new settings labels in `Localizable.xcstrings` (deferred by owner).
- Storyboard split (TD-5) is **likely YAGNI** at this size — prefer creator-injection on the
  existing storyboard where a screen needs a dependency; revisit only if the one storyboard
  actually hurts.

## Big rock — Core Data + CloudKit sync (TD-13)

Replace `UserDefaultsWordStore` with `CoreDataWordStore: WordStore` backed by
`NSPersistentCloudKitContainer`, so word sets + progress sync across a user's devices. The
`WordStore` seam is already in place; this migration also finishes the DI deferred in TD-12
(inject the store/context at the composition root, drop the `Storage` facade). Use
`core-data-expert` / `axiom-data`.

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
