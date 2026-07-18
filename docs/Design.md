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

## Decision: persistence behind a `WordStore` seam

**Decision.** The app depends on a `WordStore` protocol, not on a concrete store.
`UserDefaultsWordStore` is today's implementation (App-Group `UserDefaults` + Codable);
`Storage` is a thin static facade forwarding to a swappable `Storage.backend: WordStore`.

**Why.** A move to Core Data + `NSPersistentCloudKitContainer` (cross-device sync of word
sets and progress) is planned. With the seam, that migration is a new conformer
(`CoreDataWordStore: WordStore`) plus a one-line `backend` swap and composition-root
injection — not an app-wide rewrite. The abstraction isn't speculative (YAGNI-safe): the
swap is a concrete near-term goal. The injected `UserDefaults` + save executor also make the
current store unit-testable.

**Rejected.** *Full per-VC dependency injection now.* The 73 `Storage.…` call sites run
through storyboard-instantiated view controllers, so proper injection needs the storyboard-DI
work — and it would be thrown away when Core Data replaces this layer. The facade is the
interim; full injection lands with the Core Data migration (TD-13).

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
