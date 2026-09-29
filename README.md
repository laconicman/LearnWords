# LearnWords

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/laconicman/LearnWords)

A UIKit vocabulary app for iOS 15 and later. Words are practised three ways — flashcards,
typed dictation, and spoken pronunciation judged by the system recogniser — and every answer
lands in an append-only review log that an FSRS-based model replays into a schedule. The
Core Data store mirrors to CloudKit. Localised in English, Russian and Spanish; on the App
Store.

## Where things are

- [`docs/`](docs/README.md) is authoritative: [Design](docs/Design.md) holds the decision
  records, [TechDebt](docs/TechDebt.md) the numbered `TD-n` register, [Roadmap](docs/Roadmap.md)
  the priority order, [ProgressModel](docs/ProgressModel.md) the scoring model.
- [`CLAUDE.md`](CLAUDE.md) is the working agreement — build command, deployment floor, how a
  change lands. [`REVIEW.md`](REVIEW.md) steers the code reviewer.
- Tests run locally, signed, on the pinned simulator — there is no CI by decision
  ([why](docs/GitHubWorkflowProposal.md)). What the simulator cannot prove is in the
  [device test plan](docs/DeviceTestPlan.md).

## Building

```bash
xcodebuild -project LearnWords.xcodeproj -scheme LearnWords -configuration Debug \
  -destination 'id=<simulator-udid>' -derivedDataPath /tmp/lw-dd \
  -resultBundlePath /tmp/lw.xcresult test
```

Never pass `CODE_SIGNING_ALLOWED=NO`: it strips the CloudKit entitlement and the app traps at
launch. Swift Testing failures do not print in the `xcodebuild` log — read the `.xcresult`.
