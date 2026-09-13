# Review Guidelines

LearnWords is a UIKit vocabulary app on an **iOS 12.1 floor**, with a Core Data store mirrored to
CloudKit and a scoring model replayed from an append-only review log. `docs/` is authoritative:
where a code comment and `docs/` disagree, `docs/` wins.

These rules are the classes this project has actually been bitten by. Generic Swift advice is not
wanted here — it buries them.

## Critical Areas

- Flag any change to the model, store description, or load path in
  `LearnWords/Model/CoreData/LWPersistence.swift` that is not argued against "does a store written
  by the shipped version still open".
- Require a new model version in `LearnWords/Model/CoreData/LearnWords.xcdatamodeld` for any
  rename, type change, or new non-optional attribute. It holds one version today; only additive
  changes migrate automatically.
- Reject a non-optional attribute without a default on any CloudKit-mirrored entity, and reject
  uniqueness constraints outright — see `docs/Design.md`, "optionality is CloudKit's price".
- Require every new scoring input to appear in the invalidation path of
  `LearnWords/Model/Scoring/ProgressCache.swift`. A scoring input it does not watch shows up as a
  stale ring, not as an error.
- Reject preferences captured in `init` in `LearnWords/Model/Scoring/ScoringPolicy.swift`.
  `ScoringPolicy.default` is a `static let`, so a captured value leaves its settings slider dead
  until the next launch.
- Require a `PrivacyInfo.xcprivacy` in every bundle whose executable uses a required-reason API,
  extensions included.
- Flag any entitlement added to `LearnWords/LearnWords.entitlements` without a matching capability
  on the App ID — device signing fails outright.

## Conventions

- Never suggest `CODE_SIGNING_ALLOWED=NO` for building or testing: it strips entitlements and
  CloudKit then traps at launch asking for a container the binary is not entitled to.
- Flag any `NSManagedObject` or `CD…` type in a view controller's signature. Screens are handed
  values — `Sense`, `SenseProgress`, `SetSummary` (`docs/Design.md`, "managed objects never escape
  the store").
- Flag any change that makes a `LearnWords/Model/Lexicon/Lexicon.swift` read asynchronous: a write
  must be visible to the next read, synchronously.
- Require `UUID` for entities referenced from elsewhere; `objectID` is for lookup rows only.
- Reject a stored "permission granted" flag. Notification and microphone state is read at the
  point of use, never remembered.
- Reject any code path that deletes `ReviewEvent` rows — a progress reset appends a marker
  instead.
- Require `LearnWords/Model/Lexicon/PlainText.swift` to round-trip: if `render` can emit
  something `parse` will not read back, the app cannot import its own export.
- Skip parser concerns for `LearnWords/Model/Lexicon/AnkiText.swift` — it is export-only by
  design.
- Require `ru` and `es` entries in `LearnWords/Localizable.xcstrings` in the same commit as a new
  `NSLocalizedString` — `needs_review` is acceptable (TD-33, recurring).
- Reject a copy of the English source marked `translated` in `LearnWords/Localizable.xcstrings`.
- Reject Russian format strings that place `%d` or `%@` behind a preposition (`около %@`, `в %d`):
  the formatter's output does not carry the case the preposition forces.

## Anti-patterns to Flag

- Flag a test in `Unit Testing Bundle/` that cannot fail — one recording through the same API it
  asserts on, or asserting a fixture rather than behaviour.
- Require evidence that a new test fails without its fix.
- Flag `-only-testing` with a bare function name — it matches nothing and reports success.
- Require tests that bucket by calendar day to construct a `Calendar` **and** set `timeZone`.
  `Calendar(identifier:)` alone still inherits `TimeZone.current`.
- Flag fixed `Task.sleep` waits on real animations under `Unit Testing Bundle/`; poll for the
  condition instead (TD-61).
- Flag a view controller that reads `ScoringPolicy.default` or `LWUserDefaults` while rendering.
  Pass the value in with a default argument so a test can pin it.
- Reject references to `ScoringPolicy`, `ProgressCache` or `LearnWords/Features/` from
  `LearnWords/Model/Settings.swift`, `LearnWords/Model/Lexicon/`, `LearnWords/Model/CoreData/` or
  `LearnWords/Shared/` — those are compiled into the widgets too.
- Require an extension build before approving such a change: it breaks `Widget`,
  `WordWidgetExtension` or `ImportAsDictAction`, never the app target.
- Require `-weak_framework` in `OTHER_LDFLAGS` for any `import` of a framework newer than the
  floor (WidgetKit, Core Haptics). Swift autolinks it hard and iOS 12–13 refuse to launch before
  any `#available` runs (TD-46).
- Flag an icon-only control whose image comes from `UIImage.systemImage`: it returns `nil` below
  iOS 13, leaving an invisible button. Require a title or a fallback.
- Flag a context-menu preview that reuses a full screen. A preview does not scroll, so anything
  past the cut is unreachable; it must build shorter content and cap `preferredContentSize`
  (TD-58).
- Flag replacing a table view's swipe actions or a text field's `leftView`/`rightView` without
  saying what the default provided. Adding rename once removed delete; a `rightView` displaced the
  clear button (TD-41).
- Reject `present(` called on a captured parent view controller — UIKit may have removed it from
  the window by then. A screen presents from itself.
- Flag a discarded `try?` or a `catch` that only logs on any path a learner initiated: an import
  or export that fails must say so (TD-59).

## Tests

- Ask which half of a claim is verified and which is reasoned when a PR description asserts
  behaviour it cannot test.
- Require simulator verification when a PR touches wiring under `LearnWords/Features/`: a green
  suite has hidden a dead Save button and an argument silently defaulted at its call site.
- Require "N tests green" in `docs/TechDebt.md` to count **argument-level** Swift Testing cases:
  the per-device `passedTests`, not the function count.

## Performance

- Flag a new call to `ScoringPolicy.progress(replaying:)` on a screen path that does not go
  through `ProgressCache`: scoring costs roughly 370 ms per 1,000 meanings, on the main thread.
- Flag a `Lexicon` read from a background queue — `dispatchPrecondition` traps there.

## Ignore

- Skip `LearnWords.xcodeproj/xcuserdata/**` — breakpoint and scheme state, the noisiest churn in
  the repo.
- Skip pure key **reordering** in `LearnWords/Localizable.xcstrings`; Xcode rewrites the file on
  build. Value, `state` and `extractionState` changes still matter.
- Skip `design/ref/` — screenshots kept as design reference.
