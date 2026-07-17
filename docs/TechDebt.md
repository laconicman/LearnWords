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

## TD-4 — Deprecated Today extension (`Widget/`)

`TodayViewController` uses `NCWidgetProviding`, deprecated since iOS 14 and unsupported
on modern iOS. **Cost:** dead/again-un-shippable extension; App Store review risk.
**Discharge:** migrate to WidgetKit, or remove the target.

## TD-5 — Storyboard-centric UI

A single `Main.storyboard` drives navigation. **Cost:** merge conflicts, slow loads, no
clean dependency injection into view controllers. **Discharge:** split per feature or go
programmatic; inject via `UIStoryboard.instantiateViewController(identifier:creator:)`.

## TD-6 — No automated tests

No unit or UI test target. **Cost:** refactors (including the reorg above) can't be
verified; regressions ship silently. **Discharge:** add a test target; start with `Model`
(`WordsModel`, `Storage`) and a launch smoke test.

## TD-7 — iOS 12 availability audit

The floor is back at **12.1** (dual lifecycle — see [Design](Design.md)). Any API newer
than 12.1 used **without** an `@available`/`#available` guard is a compile error at this
floor, or a crash if mis-guarded. The code is already heavily guarded (it predates the
brief 15.0 bump), and HEAD compiled at 12.1, so risk is low — but anything added during
the 15.0 window must be re-checked. **Cost:** build breakage / iOS 12 runtime crashes.
**Discharge:** build at 12.1; grep for unguarded iOS 13+ symbols (e.g. `.systemOrange`,
`.label`, `UIImage(systemName:)` outside `UIImage+backport`); guard or backport each.

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

## TD-10 — Extensions still target iOS 14, not 12

The Widget and ImportAsDictAction targets set `IPHONEOS_DEPLOYMENT_TARGET = 14`, so on
iOS 12–13 the app runs but its extensions are unavailable — including the share-import
flow that the ported `learnWords://shareaction` deep link (TD-3) exists to serve, making
that deep link effectively dead below iOS 14. **Cost:** partial/inconsistent iOS 12 support;
the legacy deep link can't actually fire on the oldest devices. **Discharge:** decide
per-extension — lower ImportAsDictAction to 12.1 (after its own availability audit) if the
import feature must work on iOS 12, and resolve the Widget via TD-4 (WidgetKit or removal).

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
