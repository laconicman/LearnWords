# TASK — raise the floor to iOS 15

Written 2026-09-14, the morning App Store Connect refused the 1.2.2 (9) upload. Read
[Roadmap](Roadmap.md) for priority, [TechDebt](TechDebt.md) for the register, and
[Design](Design.md) § *the floor is iOS 15, because Apple stopped accepting anything lower*
for the decision this brief executes. `docs/` is authoritative; when it disagrees with a
code comment, `docs/` wins.

## The forcing function

The upload failed with **one** error, and it was not the 2027 notice everyone quotes:

```
"errors"   : [ { "code": "90068",
                 "description": "This bundle is invalid. The value provided for the key
                                 MinimumOSVersion '12.1' is not acceptable." } ]
"warnings" : [ { "code": "90068",
                 "description": "MinimumOSVersion too low… Starting in Spring 2027, all iOS
                                 apps must have a MinimumOSVersion of 15.0 or later…" } ]
"state"    : "FAILED"
```

Two separate things arriving together: a **hard refusal of 12.1 today**, and a **warning that
15.0 becomes the rule in Spring 2027**. Everything else in that upload succeeded — no ITMS
findings, no entitlement or privacy-manifest complaints, and all four bundles correctly at
`1.2.2 / 9`, so TD-24 is genuinely closed.

**The number to move to is 15.0, not the smallest number that would pass.** Apple publishes no
current MinimumOSVersion floor at all — [upcoming requirements](https://developer.apple.com/news/upcoming-requirements/)
names only the Xcode 26 / iOS 26 SDK rule — so what would be accepted between 12.1 and 15.0 is
undocumented and would have to be discovered by failed uploads. And 13 or 14 would buy nothing
even if accepted: iOS 13, 14 and 15 share the same *device* floor (iPhone 6s / SE 1), a point
already recorded in the superseded 12.1 decision. Only iOS 12 reached further back, and that
tier — iPhone 5s / 6 / 6 Plus, iPod touch 6, iPad Air 1, iPad mini 2–3 — is exactly what Apple
has now made unreachable for new builds.

**This is not a port.** The toolchain never objected: `iPhoneOS26.5.sdk` still declares
`MinimumDeploymentTarget = 12.0`, which is why the archive built clean and nothing warned
locally. Raising the number breaks no code. Of 56 availability guards in the tree, **45 become
dead branches that still compile and still behave correctly**; removing them is cleanup, not
repair. Only two changes are *forced* by the floor itself — see Phase 0.

## Scope decisions (owner, 2026-09-14)

* **The two-app split stays**, but its justification changes. "Legacy" can no longer mean *serves
  2013–14 hardware*, because nothing new can be delivered there. It now means *the UIKit app on a
  stable floor*. The modern app remains a separate future product, justified by **iOS 26+
  capabilities** — on-device ML, the language and translation frameworks — rather than by
  lifecycle tidiness.
* **No SwiftUI rewrite.** Not now, and not as part of this migration. iOS 15 is adopted for
  stability and for **modern concurrency**, which is the part that pays immediately.
* **The unblocking release collapses the iOS 12 surface** rather than shipping the bare bump.

## Phase 0 — the release that can be uploaded

Two of these are forced by the floor; the rest is the deletion `Design.md` has scripted since
the dual lifecycle was introduced.

**Forced.**

1. **Every target to `IPHONEOS_DEPLOYMENT_TARGET = 15.0`.** Project level is 12.1 (both
   configurations); `ImportAsDictAction` is 14 and `WordWidget` is 14.0, and both must rise too —
   the validator reported only the app bundle because it stopped at the first failure, so a bundle
   left below the floor is **expected** to fail the next upload the same way (reasoned, not
   observed).
2. **Delete the Today extension, `Widget/`.** It carries `MinimumOSVersion 12.1` and cannot run at
   a 15 floor at all; Today widgets were removed from iOS after 13. Six files
   (`TodayViewController.swift`, its storyboard, string catalogue, `Info.plist`, entitlements,
   privacy manifest) plus its target and its `membershipExceptions` entries. **This discharges
   TD-60 by deletion** — the widget whose data source disappeared before WidgetKit shipped.

**The collapse, per [Design](Design.md) § *Path to the optimal non-dual modern structure*.**

3. **`AppDelegate`'s iOS 12 surface.** The `window` property and the `if #available(iOS 13.0, *)
   {} else { … }` block that builds it, plus the `@available(iOS 13.0, *)` gate on
   `SceneDelegate`. `AppRoot` and `SceneDelegate`'s use of it stay unchanged — that was the point
   of routing both paths through `AppRoot`. `UIMainStoryboardFile` is already gone.
4. **45 dead availability guards across 23 files.** Densest in
   `LWPersistence.swift` (7), `AppDelegate.swift` (5), `WordTableViewController.swift` (4),
   `SearchWordViewController.swift` (3), `LWButton.swift` (3). **Eleven guards must survive** —
   they gate 16.0/17.0/18.0 APIs, not the floor: `TranslationV.swift` (5), `General.swift` (2),
   and one each in `SearchWordViewController.swift`, `AvailableLanguage.swift`,
   `ReminderScheduler.swift`, `PermissionManager.swift`. Delete by *version*, never by grep for
   `#available`.
5. **The two `-weak_framework` flags in `OTHER_LDFLAGS`** (Core Haptics, WidgetKit). Both
   frameworks are older than a 15 floor, so the hard autolink that TD-46 diagnosed is now correct
   and the flags are noise.
6. **`LearnWords-Xcode15.xcodeproj`.** Its entire purpose was building the iOS 12 path on the one
   toolchain that could verify it (TD-8). With no iOS 12 path there is nothing to verify, and the
   register already records it as stale since 2026-09-10.

**Two traps in this phase.**

* **`UIImage.systemImage` is not only a backport.** Its array form picks the first SF Symbol name
  that resolves, which is how the app survives symbols being renamed across OS versions — the
  1.2.2 build log carries `SF Symbol 'mic' is deprecated, use 'microphone' instead`, exactly that
  case. **Delete the `#available(iOS 13, *)` branch, keep the function**, and keep the 18 call
  sites. The eleven `.symbolset` assets want an audit, not a bulk delete: some may still be
  carrying names the system does not provide.
* **`REVIEW.md` must change in this PR, not before it.** It opens "LearnWords is a UIKit
  vocabulary app on an **iOS 12.1 floor**" and requires `-weak_framework` for frameworks newer
  than the floor. Changing it ahead of the code would steer Devin against a floor that does not
  exist yet; leaving it behind would have review defend deletions this phase makes. Same for
  `.devin/wiki.json`, which tells DeepWiki the repo has two Xcode projects and a `Widget/`
  extension — both false after this phase, and a stale steering file spends its only
  de-emphasis lever on a directory that no longer exists.

**Definition of done:** full suite green on the standard command (no `CODE_SIGNING_ALLOWED=NO`),
an archive whose every bundle reports `MinimumOSVersion 15.0`, and an upload App Store Connect
accepts.

## Phase 1 — what modern concurrency unlocks

The floor was the only reason these were deferred. Each names its own discharge in the register
already; none needs new design.

* **TD-56 — scoring the library is main-thread work.** The register states both discharges and
  says to decide which before building either. The floor has now decided: *"if the floor rises, do
  it once and properly — `Lexicon` reads become `async` over `context.perform`, and the
  callback twin never gets written."* Measured at 369 ms for 1,000 meanings and 1,860 ms for
  2,000, on the thread that draws.
* **TD-62 — the launch rebuild.** `BGTaskScheduler` is iOS 13+, so at this floor the
  `#available` and the iOS 12 fallback path the entry warns about both disappear. See Phase 2 —
  this is the owner's first feature.
* **TD-43 — opening the microphone blocks the main queue**, and **TD-40 — main-queue confinement
  is checked, not proved.** Both are shapes that `async`/actors address directly; both should be
  re-read after TD-56 lands, because TD-56 may change what they even mean.

Do TD-56 first. It is the one with a measurement, it is the one every screen pays for, and the
other three read cleaner once `Lexicon` is async.

## Phase 2 — features, owner-ordered

1. **TD-62 scheduled refresh** (owner's choice, 2026-09-14) — move the reminder rebuild off every
   launch onto a `BGAppRefreshTask`. This is the change that earns the `fetch` background mode;
   declare the mode in the same change as the handler, never before it
   ([Design](Design.md) § *one background mode*).
2. **Two-device CloudKit verification** — still the riskiest unverified thing in the app. The
   schema is deployed as of 2026-09-14, so nothing blocks it but two devices on one account.
3. **Confirm a reminder actually arrives** — schedule → deliver → tap → land on Exercises has
   never been witnessed end to end, and no automated pass can do it.
4. **Enrichment (TD-22)** — the largest item in the register; [Enrichment](Enrichment.md) designs
   it, and its first step is a measurement, not code.

## What this does not change

* **The store, the schema, and sync.** Nothing here touches the Core Data model or CloudKit. The
  Production schema was deployed on 2026-09-14 and stays as it is.
* **Existing users below iOS 15.** The App Store keeps serving them the last compatible build.
  That is not a consequence of this migration — Apple removed the alternative.
* **The UIKit architecture.** Four-layer MVC, storyboards, `AppRoot` as the composition root.
  Modern concurrency is adopted; the UI framework is not replaced.

## Verification, at every phase

```bash
xcodebuild -project LearnWords.xcodeproj -scheme LearnWords -configuration Debug \
  -destination 'id=651B025B-EF1E-4A7F-AE46-01A3C9F75FBD' \
  -derivedDataPath /tmp/lw-dd -resultBundlePath /tmp/lw.xcresult test
```

Never pass `CODE_SIGNING_ALLOWED=NO` — it strips entitlements and CloudKit traps at launch.
Swift Testing failures do not print in the xcodebuild log; read the `.xcresult`. Test counts in
this register are **argument-level** cases, not xcresult's function count.

One thing the simulator cannot tell you in Phase 0: whether the archive is acceptable. That check
is `MinimumOSVersion` in every bundle of the built `.xcarchive`, and then an actual upload.
