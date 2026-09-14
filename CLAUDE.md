# Working agreement

LearnWords is a UIKit iOS vocabulary app: Core Data mirrored to CloudKit through
`NSPersistentCloudKitContainer`, and a scoring model replayed from an append-only review log.
Four-layer MVC, storyboards, `AppRoot` as the composition root.

**`docs/` is authoritative.** Where a code comment and `docs/` disagree, `docs/` wins.
[Design](docs/Design.md) holds the decision records, [TechDebt](docs/TechDebt.md) the numbered
register (`TD-n`), [Roadmap](docs/Roadmap.md) the priority order. `REVIEW.md` steers Devin Review
and is not a duplicate of this file: it says where a reviewer should look, this says how to work.

## Build and test

```bash
xcodebuild -project LearnWords.xcodeproj -scheme LearnWords -configuration Debug \
  -destination 'id=651B025B-EF1E-4A7F-AE46-01A3C9F75FBD' \
  -derivedDataPath /tmp/lw-dd -resultBundlePath /tmp/lw.xcresult test
```

* **Never pass `CODE_SIGNING_ALLOWED=NO`.** It strips entitlements, and CloudKit then traps at
  launch asking for a container the binary is not entitled to. A green build that skipped signing
  has proved nothing about this app.
* **Swift Testing failures do not print in the `xcodebuild` log.** Pass `-resultBundlePath` and
  read the `.xcresult`, or a failing run looks like a passing one with less output.
* **"N tests green" counts argument-level cases**, not the function count `xcresulttool` reports.
  A parameterised test with twelve arguments is twelve.
* The deployment floor is **iOS 15.0**, set once at project level and inherited by every
  shipped target ([Design](docs/Design.md) § *the floor is iOS 15*). An API newer than the floor
  needs `#available`, and a *framework* newer than the floor needs `-weak_framework` in
  `OTHER_LDFLAGS` (TD-46: an `import` can autolink it as a hard load, and the app then refuses to
  launch before any `#available` can run).
* Targets use Xcode 16 synchronized folders with `membershipExceptions` inclusion lists (TD-2).
  Moving or deleting a shared file means updating those lists; forget one and the file silently
  leaves a target while the build stays green.

## How changes land

* **One PR per change**, against `main`, on the `laconic` remote.
* **Devin Review reads every PR.** Answer its findings on the PR before merging, briefly, on the
  owner's behalf. Treat a finding as right until shown otherwise — it has been right far more
  often than not, including about claims that sounded safe.
* **No AI attribution in commit messages.** No `Co-Authored-By`, no "generated with".
* A commit message says *why*, and what was verified. The register and the decision records are
  written the same way: they are read by people deciding whether to undo the thing they describe.

## Claims

* **Say which half of a claim is verified and which is reasoned.** "The build is green" and "this
  should also fix iOS 12" are different kinds of sentence and must not be written as one.
* **A string search finds text, not a live code path.** A commented-out block answers `git log -S`
  and `git log -L` exactly like working code. TD-60 was wrong for a year because of this, and its
  own retraction repeated the mistake — read the function, not the hit.
* **Do not recall Apple's behaviour; look it up.** Deprecated is not removed, and an availability
  line is a fact rather than an impression.
* Before ruling on a public repository's behaviour, consult its wiki rather than recalling it.

## Things that are load-bearing and look optional

* `LWPersistence.write` merges into the view context **before it returns**. Removing that brings
  back a bug where a second edit to the same field silently does nothing
  ([Design](docs/Design.md) § *a write is visible to the next read, synchronously*).
* `Lexicon` returns value types; no `NSManagedObject` crosses its boundary, and identity travels
  as `UUID`.
* `ReviewEvent` rows are never deleted. A progress reset appends a marker.
* `LWPersistence.configure` calls `fatalError` on a store it cannot open, so **any** model change
  must be checked against a store made by the shipped build, not only against a fresh one.
