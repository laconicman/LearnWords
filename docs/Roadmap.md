# Roadmap

Priority-ordered. Rationale lives in [Design](Design.md); debt items in [TechDebt](TechDebt.md).

## Now

- **UIScene *dual* lifecycle — done (this change).** iOS 13+ via `SceneDelegate`, iOS 12
  via `AppDelegate`, both through `AppRoot`; floor reverted to 12.1. Reverses the earlier
  iOS-15 decision — this Legacy app stays on old hardware (see [Design](Design.md)).
- **Verify green on a modern simulator (Xcode 26):** compiles at the 12.1 floor and the
  scene path launches + the `learnWords://shareaction` deep link works (TD-7).
- **Verify the iOS 12 path on Xcode 15** (TD-8): launch + deep link on an iOS 12 sim/device —
  the only way to exercise the `AppDelegate` branch. Do before any lifecycle-touching release.

## Done (2026-07-17)

- **Feature-first reorg of source** (TD-1) — all 30 `.swift` files moved into
  `App/ Model/ Controllers/ Shared/… Features/*`; shared-file `membershipExceptions`
  updated (TD-2); clean build of all three targets green; app launches. Resources deferred.
- **Doc consolidation** (TD-9) — obsolete `Documentation.docc` scaffold deleted; `docs/` is
  the single source.

## Next

- **iOS 12 availability audit** (TD-7) — grep for unguarded iOS 13+ symbols now that the floor
  is 12.1 again; guard or backport.
- **Split `Main.storyboard` / reduce storyboard centralization** (TD-5), then move resources
  beside their features (finishes TD-1).
- **Verify the ported deep link** (TD-3) against the ImportAsDictAction extension — note the
  extension targets iOS 14, so the deep link can't fire below that yet (TD-10).

## Later

- **Replace the deprecated Today extension** (`NCWidgetProviding`) with WidgetKit (TD-4).
- **Add tests** — unit tests for `Model` (`WordsModel`, `Storage`), a launch smoke test (TD-6).
- **Naming pass** — `…Manager` → `…Controller` for shared controllers, once tests exist.
- Promote these docs to a rendered DocC catalog (`repo-init`).

## Someday — the modern rewrite (separate app)

Legacy stays iOS 12. New devices get a **from-scratch** app on a modern floor (iOS 26): no
dual branching, async/await and `@Observable` throughout, SwiftUI embedded natively rather
than as `@available`-gated islands. The "delete the iOS 12 surface" recipe in
[Design → Path to the optimal non-dual modern structure](Design.md) is also how Legacy
would collapse to scene-only if iOS 12 is ever dropped.
