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
their post-reorg paths: `Model/WordsModel.swift`, `Model/Storage.swift`,
`Model/Settings.swift`, `Shared/AppConstants.swift`, `Shared/Debug.swift`,
`Shared/Extensions/String+.swift`, `Shared/Extensions/UserDefaults+Codable.swift`
(Widget); `Shared/AppConstants.swift` (ImportAsDictAction); plus the `Settings.bundle`
resource (Widget). **Cost:** moving any of them silently drops them from those targets
unless the exception path is updated — the TD-1 reorg had to update all of these in
lockstep. **Discharge:** when relocating a shared file, update its `membershipExceptions`
entry and build all three targets. Longer term, extract the shared core into a local
Swift package with explicit membership so the coupling is compiler-enforced, not
path-string-enforced.

## TD-3 — Ported deep-link handler is unverified

`learnWords://shareaction` was moved from `AppDelegate.application(_:open:)` (which was
flagged `// FIXME: unused for now`) to `SceneDelegate`. The port rebuilds the home tab
bar as root, mirroring the old behavior. **Cost:** may be dead code, or may need to
select a specific tab index the old code left commented out. **Discharge:** exercise the
share flow from ImportAsDictAction; confirm the intended landing screen; delete if unused.

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

## TD-13 — Core Data + CloudKit migration (planned direction)

Owner intends to move persistence to Core Data with `NSPersistentCloudKitContainer` so word
sets and learning progress sync across a user's devices. The `WordStore` seam (TD-12) is built
for exactly this: write `CoreDataWordStore: WordStore`, swap `Storage.backend`, and inject the
store/context at the composition root (finishing the DI that TD-12 deferred). Use the
`core-data-expert` / `axiom-data` skills. Open considerations: the object model (Word, WordSet,
per-exercise stats), CloudKit schema + entitlements and App-Group sharing with the extensions,
migrating existing `UserDefaults` data, and whether the `WordStore` API should go async (CloudKit
sync is background).

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
