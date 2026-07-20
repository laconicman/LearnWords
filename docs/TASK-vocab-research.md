# TASK — Research: vocabulary-acquisition science for LearnWords (Cowork handoff)

Self-contained brief for a research session. Attach `ProgressModel.md` (same folder)
alongside this file — it is the draft under review.

## Context (all you need to know about the app)

**LearnWords** is a solo-developer iOS vocabulary app: word pairs (foreign ↔ native) in
named sets, practiced through three exercise types — flashcard self-assessment
("know"/"forgot" buttons), typed dictation (answer matched by a tolerant text matcher),
and spoken phonetics (speech recognition). A "Legacy" build supports iOS 12; a modern
rewrite is planned. Persistence is moving to Core Data + CloudKit.

The progress model was just redesigned (see `ProgressModel.md`): an **append-only
ReviewEvent log** (timestamped outcomes per answer — verbatim-correct / judged-close /
self-assessed-known / incorrect / self-assessed-forgot / skipped — with the user's actual
response text kept), from which **derived indexes** are computed: *effort* (invested work,
mistakes count as effort), *mastery* (recency-weighted evidence, verbatim > judged >
self-assessed), *retention risk* (time-decay). An on-device AI judge for near-miss answers
is planned (graded verdicts attach to events; re-judgeable as models improve). Progress
will be shown per-word as a ring (likely double ring: mastery + effort).

**The owner's worry: this may be reinventing things already settled** in educational
standards, academic literature, or shipping products. Your job is to check, correct, and
then build on it.

## Phase 1 — Research (grounded, cited)

Survey authoritative and practitioner sources. Cover at least:

1. **Memory & practice science**: spaced repetition (Ebbinghaus → Leitner → SM-2 →
   **FSRS** and its Difficulty/Stability/Retrievability model); retrieval practice /
   testing effect; desirable difficulties (Bjork); interleaving; recognition vs recall;
   the generation effect; error-based learning and the hypercorrection effect.
2. **Self-assessment reliability**: judgments of learning (JOL), metacognitive accuracy —
   how much should a "know" button be trusted vs a verbatim answer? (The model currently
   weights self-assessment lowest; confirm or refute.)
3. **Vocabulary-specific pedagogy**: Nation's vocabulary-knowledge framework
   (form/meaning/use; receptive vs productive), depth vs breadth, frequency-band
   approaches, CEFR vocabulary levels, the lexical approach.
4. **Shipping products' progress models**: Anki (SM-2/FSRS), SuperMemo, **Duolingo's
   published half-life-regression model**, Memrise, WaniKani's SRS stages, Quizlet,
   Clozemaster — how each tracks/displays mastery; what their known failure modes are
   (gamification criticisms, streak anxiety, "leech" cards).
5. **Partial-credit / near-miss grading**: typo tolerance, partial-knowledge scoring in
   language testing, semantic-similarity answer judging.

For each area: what is *settled*, what is *contested*, and the 2–3 sources that matter.

## Phase 2 — Audit the draft

Read `ProgressModel.md` critically against Phase 1:

- What does the design get right (keep, with citations to back it)?
- What is naive or contradicted (e.g., is the effort/mastery/retention triple just
  FSRS's D/S/R under other names — and if so, should it adopt FSRS outright)?
- What is *missing* that the event log should capture now, because it cannot be
  reconstructed later (the log is append-only; schema gaps are the costly kind)?

Constraints to respect: solo developer; on-device only (privacy — no server); Apple
Foundation Models available iOS 26+ only; the Legacy app floor is iOS 12; small,
implementable increments beat grand systems.

## Phase 3 — Prove your creativity

After (and grounded in) the research, propose **novel mechanics** for LearnWords — not
copies of existing apps. A ranked shortlist (5–8 ideas), each with: the insight it builds
on (cite), what it would feel like for the user, and exactly what data it needs (check
against the ReviewEvent schema — flag any schema additions). Directions worth exploring,
not limiting: making *effort* a first-class visible achievement (most apps hide it);
honest forgetting (what would a UI that respects the forgetting curve look like, without
streak-shame?); the near-miss judge as a teaching moment rather than a grader; what a
single-user event log enables that server-side products can't do privately.

Wild ideas welcome — mark them as such. Separate "ship next quarter" from "north star."

## Deliverable

One Markdown report: Phase 1 findings (cited), Phase 2 audit as a concrete list of
keep/change/add against `ProgressModel.md` (write the changes as edit-ready bullet
points), Phase 3 ranked proposals. The report lands back in this folder as
`ProgressResearch.md`; the owner and the coding session will apply the Phase 2 deltas to
`ProgressModel.md` before the Core Data schema is implemented.
