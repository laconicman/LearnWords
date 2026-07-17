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
- **Test seed** (TD-6) — Swift Testing bundle, 13 passing cases (`WordAndStat` logic,
  `canonicalise`, launch smoke test).

## Next

- **Verify / clean the deep link** (TD-3) — the `learnWords://shareaction` handler; note
  ImportAsDictAction targets iOS 14 (TD-10), so it can't fire below that yet.
- **Make `Storage` injectable** (TD-12) — unlocks `Storage` unit tests; DI per
  uikit-app-structure.
- **Today extension** (TD-4) — decide: migrate to WidgetKit vs remove.
- Storyboard split (TD-5) is **likely YAGNI** at this size — prefer creator-injection on the
  existing storyboard where a screen needs a dependency; revisit only if the one storyboard
  actually hurts.

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
