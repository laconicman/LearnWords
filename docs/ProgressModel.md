# Progress model — learning-history design (pre-TD-13 schema)

Owner requirements (2026-07-20) distilled, and the data design that satisfies them.
This document is the intended **core of the TD-13 Core Data + CloudKit schema**; the
progress ring (TD-17) and future indexes are views over it.

> **Schema update (owner, 2026-07-23).** The TD-13 schema generalized from word pairs to
> the lexical model in [LexicalModelResearch](LexicalModelResearch.md): events attach to a
> **synset** (the practised meaning) rather than a word, `wordID` → the synset's UUID
> (identity semantics unchanged), `direction` is now **receptive/productive** with
> explicit `promptLanguage`/`answerLanguage` snapshots, and two more unbackfillable
> snapshots were added — `promptTermID` (which synonym cued the question) and `wordSetID`
> (which thematic framed it; the different-set answer coefficient needs it). Everything
> else in this document stands.

## Requirements (owner's words, distilled)

- **R1** Negative progress (mistakes, "forgot"/unknown) tracked as its own story —
  never canceling positive history — distinguished by the kind of task.
- **R2** Positive outcomes differ by evidence strength: a *verbatim-correct answer* is not
  the same as tapping *"know"* (self-assessment).
- **R3** Everything eventually scorable into **several weighted indexes**: effort invested
  vs actual success. (Much effort + little progress, and fast effortless progress that is
  soon forgotten, must both be visible — that is the spacing/forgetting effect.)
- **R4** Maybe a Foundation model computes those indexes someday; design must not depend
  on it.
- **R5** Definitely planned: an on-device AI judge for **near-miss answers** (close but not
  verbatim) — and its verdicts must sink into the database.
- **R6** Cell layout: ring and font sizes come from scaled metrics; the progress indicator
  must not drive row height; fonts render at natural size.

## Why the current model cannot do this

`WordAndStat` keeps only capped aggregates: `correct: [task: Int]`, `incorrect: [task: Int]`,
`skiped`. Five hard limits:

1. **Lossy negatives** — `decreaseCorrect` *subtracts from the positive counter*; a mistake
   erases effort evidence (directly violates R1/R3).
2. **Outcome conflation** — the "know" button and a `match3`-judged typed answer both call
   the same `increaseCorrect`; verbatim vs self-assessed is unrecoverable (violates R2).
3. **No time** — no timestamps, so no forgetting-curve/retention modeling ever (violates R3).
4. **No response text** — the user's actual answer is discarded the moment it's judged, so
   no post-hoc AI judging is possible (violates R5).
5. **String identity** — words are identified by `firstWord`; renames/duplicates corrupt
   history, and CloudKit needs stable identity (blocks TD-13). → **TD-18**.

## Design: an append-only review log + derived indexes

**Source of truth: `ReviewEvent`** — one immutable record per answer, appended, never
mutated (except attaching a judgment), never deleted by scoring changes:

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `wordID` | UUID | stable word identity (TD-18) |
| `date` | Date | enables retention/spacing math |
| `sessionID` † | UUID | sitting identity (new UUID when practice starts) — same-sitting retries are effort, not fresh long-term evidence; sittings are the effort index's unit of persistence |
| `task` | enum | `.test`, `.dictation`, `.phonetics` (today's "L"/"D"/"P"), extensible |
| `direction` † | enum | which side was the cue: `.foreignToNative` (receptive) / `.nativeToForeign` (productive) — Nation's receptive/productive split; unrecoverable if not logged |
| `outcome` | enum | see taxonomy below; decoding must tolerate unknown future cases (skip, never crash — the log outlives the code) |
| `response` | String? | what the user typed/said — **kept**, fuels R5 |
| `expected` † | String | target answer snapshot at review time — words are editable, so re-judging (R5) against today's text would corrupt history |
| `prompt` † | String? | cue text snapshot (optional; gives the FM judge its context) |
| `latencyMS` † | Int? | prompt→answer time — retrieval fluency: feeds the Hard/Easy grade split, effort time-on-task, and automaticity display |
| `judgment` | struct? | `verdict` (score 0…1), `judge` (id + version), `judgedAt`, `errorTags: [String]?` † — attached async, re-judgeable by better models later |
| `schemaVersion` † | Int16 | format insurance for a log that will outlive several codebases |

† Added by the research audit (`ProgressResearch.md`, Phase 2) — fields that cannot be
backfilled into an append-only log.

**Outcome taxonomy** (R1 + R2 explicit in the data, not inferred from the task):

- Positive: `.correctVerbatim` · `.correctJudged` (matcher/AI said close enough) ·
  `.selfAssessedKnown` (the "know" button — weakest positive evidence)
- Negative: `.incorrect` (wrong answer given) · `.selfAssessedForgot` (the "forgot" button)
- Neutral: `.skipped` (today's `skiped` counter)

**Self-assessment flow (audit):** the know/forgot buttons are **reveal-then-grade** — the
user attempts retrieval, reveals the answer, then self-grades. That makes
`.selfAssessedKnown` an Anki-grade self-graded retrieval, not a mere prediction; a
pre-reveal "know" would be a JOL-class signal (much weaker — Rhodes & Tauber 2011). If a
pre-reveal grading path ever ships, it must become a distinct outcome or field.

**Derived, never stored as truth: `ScoringPolicy`** — weights live in *code*, not data, so
indexes recompute across the whole log without migration (and an FM-based policy can slot
in later, R4):

- **Effort index** — volume & persistence: events over time, sittings (`sessionID`),
  time-on-task (`latencyMS`), negatives included *positively* (a mistake is effort spent).
  **No FSRS counterpart — this index is ours, and it never decreases.**
- **Mastery index** — a monotone display function of **FSRS stability S** (≈ Bjork's
  storage strength): grows with successful spaced retrieval, unaffected by mere elapsed
  time. Evidence strength (verbatim > judged-close > self-assessed, R2) enters via the
  outcome→grade mapping below — *not* via recency-weighting, which would smuggle decay
  into mastery and make the ring show forgetting twice (decay belongs to retention alone).
- **Retention risk** — **FSRS retrievability** R(elapsed, S). Computed, not invented:
  adopt the official Swift package
  ([open-spaced-repetition/swift-fsrs](https://github.com/open-spaced-repetition/swift-fsrs),
  FSRS-6; alternative: [4rays/swift-fsrs](https://github.com/4rays/swift-fsrs), v5) rather
  than hand-rolling decay math. The event log (timestamps + graded outcomes) is exactly the
  algorithm's required input, and FSRS's optimizer can later fit per-user parameters from
  this same log. An FM can complement, never required.
- `known` (today's number) becomes one more derived value — computed with a compatibility
  policy so existing behavior survives.

**Outcome → FSRS grade mapping** (versioned in `ScoringPolicy`; FSRS consumes ordinal
grades Again/Hard/Good/Easy):

| Outcome | Grade |
|---|---|
| `.incorrect`, `.selfAssessedForgot` | Again |
| `.correctJudged` | Hard (verdict below ~0.9), else Good |
| `.correctVerbatim` | Good; Easy when `latencyMS` is fast |
| `.selfAssessedKnown` | Good (post-reveal self-grade — Anki-equivalent; per-user calibration may scale its weight later) |
| `.skipped` | not fed to the scheduler (exposure, not retrieval) |

Scheduler grades and evidence-tier weights are distinct concerns: the tiers (R2) shape the
mastery display and calibration; the grades shape scheduling. Only the **first attempt per
word per sitting** feeds long-term scheduling — same-sitting retries count as effort only
(`sessionID` makes this exact; FSRS-6's short-term component covers the massed case).

**Memory-state scope (v1, deliberate deferral):** one FSRS state per word — all tasks and
directions feed it through the mapping. Because `direction` is recorded per event, a
per-direction (receptive/productive) split stays computable later without any backfill.

**Display caches (agreed in principle, mechanism negotiable — owner, 2026-07-20)** —
index values must not be recomputed per cell display. Per-word cached index values,
invalidated when an event is appended for that word, recomputed off the cell path (on
append, or lazily on first display after invalidation). In the Core Data schema this is a
small per-word cache entity (or transient attributes recomputed per launch); exact
mechanism decided at TD-13 implementation.

## Why event-sourcing is the right TD-13 shape

Append-only logs are the **CloudKit-friendly** shape: devices append their own records and
sync merges trivially (no conflict resolution on counters — two devices incrementing an
aggregate is exactly the conflict CloudKit is worst at). Derived indexes recompute locally.
This design is therefore not extra work *before* TD-13 — it **is** the TD-13 schema core:
`Word` (id, firstWord, secondWord, set) → one-to-many `ReviewEvent`, plus a per-word cache.

**Do not implement the event log on UserDefaults first** — same rule as TD-12 (don't
polish a layer being replaced). Sequence: agree on this doc → TD-18 identity → TD-13 Core
Data with this schema → screens start appending events (the `afterAnswer(isKnown:)`
signature widens to carry outcome, response text, direction, latency, and session) →
indexes + ring.

## The near-miss judge (R5)

A pluggable protocol, availability-laddered:

1. **Today**: `match3` (already the de-facto judge in Dictation) → recorded as
   `.correctJudged` with `judge: "match3/v1"`.
2. **iOS 12 floor**: Damerau-Levenshtein edit distance + lemma comparison (`NLTagger`,
   iOS 12+).
3. **iOS 13/14+**: semantic near-miss via `NLEmbedding` cosine similarity — word
   embeddings need iOS 13, sentence embeddings iOS 14 (audit correction: this step is
   *not* available at the iOS 12 floor).
4. **iOS 26+**: Apple **Foundation Models** on-device judging ("was the user close?" with a
   graded verdict) — gated `#available`, async post-hoc: the event is stored immediately
   with the cheap verdict, the FM verdict *attaches* when computed. `judge` + `version`
   fields make re-judging the backlog with better models a batch job, not a migration.

## Ring/UI mapping (TD-17, after the model lands)

Several dials become available; a natural mapping for the cell ring (MKRing-style double
ring or in-house): **outer = mastery**, **inner = effort**, color tint = retention risk.
Exact visual design deferred until the indexes exist.

**Layout metrics (R6, applies regardless of ring choice):** the ring's size derives from
the type system — `UIFontMetrics(forTextStyle: .body).scaledValue(for: 44)` — labels keep
their natural Dynamic Type size (no autoshrink), rows stay self-sizing with the `≥`
margins already in place. The indicator follows the text scale; it never drives row height
against the font.

## Resolved questions (owner, 2026-07-20)

1. `.correctJudged` (near-miss) weight: **between verbatim and self-assessed** — confirmed.
2. `.skipped`: **tiny effort weight, zero mastery signal** — confirmed.
3. Know/forgot buttons stay on all screens — **confirmed** (honest self-assessment, now
   distinguishable in data).
4. Legacy aggregates: **NOT migrated** (owner reversed the default). No `legacyPrior`;
   existing `correct`/`incorrect` counts are discarded when TD-13 lands and progress starts
   fresh from the event log. Rationale: backward compatibility isn't worth the code
   complexity at this data scale.

## Research audit — applied (2026-07-20)

The commissioned research pass (`TASK-vocab-research.md`) landed as `ProgressResearch.md`
(same folder) and its Phase-2 audit is incorporated above: indexes re-grounded in FSRS
S/R (mastery = stability, retention = retrievability; effort confirmed as this model's own
contribution with no FSRS counterpart), an explicit outcome→grade mapping added, the
self-assessment flow pinned to reveal-then-grade, the near-miss ladder's availability
claims corrected (NLEmbedding needs iOS 13/14), and the schema extended with the
†-marked fields — additions that could not be backfilled later. See the report for
citations and the Phase-3 mechanics shortlist; the TD-13 schema is now clear to implement
from this document.
