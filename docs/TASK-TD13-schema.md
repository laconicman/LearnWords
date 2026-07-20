# TASK — TD-18 + TD-13: identity, event log, indexes (Claude Code handoff)

Implementation brief. Design is **settled** — do not redesign it here. Read, in order:

1. [`ProgressModel.md`](ProgressModel.md) — the schema and index definitions (audit applied).
2. [`ProgressResearch.md`](ProgressResearch.md) — why they are what they are (cited); §Phase 2
   is the rationale for every †-marked field, §Phase 3 is the mechanics this unblocks.
3. [`TechDebt.md`](TechDebt.md) — TD-12 (`WordStore` seam), TD-13, TD-17, TD-18.

The event log is **append-only**: a field omitted now cannot be backfilled. That is the one
irreversible risk in this task; everything else is refactorable.

## Context

LearnWords: solo-developer iOS vocabulary app, word pairs in named sets, three exercises —
flashcard self-assessment (know/forgot), typed dictation (`match3` matcher), spoken
phonetics. Legacy build floor **iOS 12.1**. Persistence today is `UserDefaults` behind the
`WordStore` seam built in TD-12; `WordAndStat` keeps capped aggregates
(`correct`/`incorrect`/`skiped` per task) that the new model replaces outright.

## Sequence (each phase ships independently and green)

### Phase A — TD-18: stable word identity

Give `Word` a `UUID`, assigned on creation and during the first migration. `firstWord`
becomes display/search data only. Set membership and all history keying move to the UUID.
**Why first:** renames currently orphan history, duplicates collide across sets, and
CloudKit requires stable record identity. Blocks everything below.

### Phase B — TD-13: Core Data + CloudKit schema

`CoreDataWordStore: WordStore`, swap `Storage.backend`, inject store/context at the
composition root — finishing the DI that TD-12 deliberately deferred. Use the
`core-data-expert` skill.

Entities: `Word` (id, firstWord, secondWord, set) → one-to-many **`ReviewEvent`** exactly as
tabled in `ProgressModel.md` §Design, **including all †-marked fields** — `sessionID`,
`direction`, `expected`, `prompt`, `latencyMS`, `judgment.errorTags`, `schemaVersion` —
plus a per-word index cache entity.

Rules: events are immutable once written (only `judgment` attaches later); `outcome`
decoding tolerates unknown future cases (skip, never crash); words and sets migrate from
`UserDefaults`, **legacy progress aggregates do not** (owner, 2026-07-20 — progress starts
fresh from the log).

### Phase C — write events

Widen `afterAnswer(isKnown:)` to carry outcome, response text, direction, latency, and
session; the three exercise screens start appending. Session: one UUID minted when practice
starts, carried for the sitting. Latency: prompt-shown → answer-submitted.

Keep the know/forgot flow **reveal-then-grade** (retrieve → reveal → self-grade) — the
evidence weighting in the model depends on it (`ProgressResearch.md` §1.3).

### Phase D — indexes + ring (TD-17)

`ScoringPolicy` in code, never in data: effort (monotone; sittings + attempts + time),
mastery (FSRS stability), retention (FSRS retrievability), via the outcome→grade table in
`ProgressModel.md`. Only the **first attempt per word per sitting** feeds long-term
scheduling; same-sitting retries are effort only. Then TD-17's ring — outer mastery, inner
effort, tint retention — per TechDebt's recommended in-house `ProgressRing` (~80 lines,
CAShapeLayer, iOS 12-safe) rather than the 556 vendored `KDCircularProgress` lines.

## Decisions to make before coding (do not silently pick)

1. **FSRS dependency vs the iOS 12.1 floor.** `open-spaced-repetition/swift-fsrs` declares
   `.iOS(.v14)`, swift-tools 5.10, `StrictConcurrency=complete` — it **cannot** be linked
   unconditionally at the Legacy floor. Options: (a) gate FSRS behind `#available(iOS 14)`
   with a simple exponential-decay fallback below; (b) port the FSRS-6 formulas in-house
   (the core math is small and the benchmark repo documents it); (c) declare the event log
   iOS-12-compatible but the FSRS index iOS-14+ only, since the ring degrades gracefully.
   Same question for `4rays/swift-fsrs` — check its platform floor before choosing.
2. **Does `WordStore` go async?** Left open by TD-13's notes; decide before the protocol
   widens, not after.
3. **CloudKit entitlements + App-Group sharing** with the widget and share extensions.
4. **Index cache mechanism** — small per-word cache entity vs transient attributes
   recomputed per launch (`ProgressModel.md` leaves this to implementation).

## Constraints

Solo developer; on-device only (no server — privacy is a feature, and it is what makes the
Phase-3 mechanics possible); Apple Foundation Models are iOS 26+ only and must stay
optional; Legacy floor iOS 12.1; small implementable increments beat grand systems; do not
implement the event log on `UserDefaults` first (same rule as TD-12 — don't polish a layer
being replaced).

Conventions: feature-first layout (`App/ Model/ Controllers/ Shared/ Features/*`), Swift
Testing suite kept green (it is, at every recent commit), DRY / separation of concerns /
low coupling. Relevant skills: `core-data-expert`, `swift-package-manager`,
`swift-testing-expert`, `swift-concurrency`, `software-development-principles`.

## Done when

- A word survives a rename with its history intact (TD-18 regression test).
- Answering on each of the three screens appends a `ReviewEvent` with every field populated
  — assert `direction`, `sessionID`, `latencyMS` and `expected` are non-placeholder.
- Two events in one sitting produce one long-term grade, not two (the retry rule).
- Effort never decreases across any event sequence, including all-wrong ones (R1, property
  test).
- Deleting and recomputing all indexes from the log reproduces identical values (derived,
  not stored).
- Suite green; app builds and launches at the 12.1 floor.

## Not in scope

Phase-3 mechanics from `ProgressResearch.md` (they depend on this schema — build them
after), the modern rewrite, and any near-miss judge beyond recording `match3` verdicts as
`.correctJudged` with `judge: "match3/v1"`.
