# Progress model — learning-history design (pre-TD-13 schema)

Owner requirements (2026-07-20) distilled, and the data design that satisfies them.
This document is the intended **core of the TD-13 Core Data + CloudKit schema**; the
progress ring (TD-17) and future indexes are views over it.

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
| `task` | enum | `.test`, `.dictation`, `.phonetics` (today's "L"/"D"/"P"), extensible |
| `outcome` | enum | see taxonomy below |
| `response` | String? | what the user typed/said — **kept**, fuels R5 |
| `judgment` | struct? | `verdict` (score 0…1), `judge` (id + version), `judgedAt` — attached async, re-judgeable by better models later |

**Outcome taxonomy** (R1 + R2 explicit in the data, not inferred from the task):

- Positive: `.correctVerbatim` · `.correctJudged` (matcher/AI said close enough) ·
  `.selfAssessedKnown` (the "know" button — weakest positive evidence)
- Negative: `.incorrect` (wrong answer given) · `.selfAssessedForgot` (the "forgot" button)
- Neutral: `.skipped` (today's `skiped` counter)

**Derived, never stored as truth: `ScoringPolicy`** — weights live in *code*, not data, so
indexes recompute across the whole log without migration (and an FM-based policy can slot
in later, R4):

- **Effort index** — volume & persistence: events over time, sessions, negatives included
  *positively* (a mistake is effort spent).
- **Mastery index** — recency-weighted positive evidence; verbatim > judged-close >
  self-assessed.
- **Retention risk** — time-decay since last strong evidence. The mature non-AI baseline
  here is FSRS-style spaced-repetition scheduling; the event log (timestamps + outcomes) is
  exactly its required input. An FM can complement, never required.
- `known` (today's number) becomes one more derived value — computed with a compatibility
  policy so existing behavior survives.

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
signature widens to carry outcome + response text) → indexes + ring.

## The near-miss judge (R5)

A pluggable protocol, availability-laddered:

1. **Today**: `match3` (already the de-facto judge in Dictation) → recorded as
   `.correctJudged` with `judge: "match3/v1"`.
2. **All-iOS upgrade**: edit-distance + lemma comparison (NaturalLanguage, iOS 12+).
3. **iOS 26+**: Apple **Foundation Models** on-device judging ("was the user close?" with a
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

## Pending external input

A research pass on vocabulary-acquisition science and shipping products' progress models is
commissioned (`TASK-vocab-research.md`, same folder; report lands as `ProgressResearch.md`).
Its Phase-2 audit may amend this document — **apply the audit before implementing the TD-13
schema**, since the event log is append-only and schema gaps are the expensive kind.
