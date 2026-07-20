# Progress research — vocabulary-acquisition science audit

Deliverable of `TASK-vocab-research.md` (2026-07-20). Audits `ProgressModel.md` against the
literature and shipping products; Phase 2 deltas must be applied **before** the TD-13
schema, because the event log is append-only.

## TL;DR

The design is *not* a naive reinvention — it independently arrives at the shape the field
converged on (a full review log as source of truth, scores derived in code). Three verdicts:

1. **The effort/mastery/retention triple is NOT FSRS's D/S/R renamed.** Retention risk *is*
   FSRS Retrievability — adopt FSRS math there outright (official Swift package exists).
   Mastery should be re-grounded in FSRS Stability (the current "recency-weighted evidence"
   double-counts decay). Effort has **no counterpart** in FSRS or any shipping product —
   it is the model's genuine novelty. Keep it.
2. **The evidence hierarchy (verbatim > judged > self-assessed) is confirmed** by the
   judgments-of-learning literature — with one nuance: a "know" tapped *after* attempting
   retrieval is respectable evidence (it is how all of Anki works), while a "know" tapped
   before seeing the answer is a weak prediction. The flow, or a field, must distinguish.
3. **Four schema gaps must be closed now** (append-only = no backfill): prompt **direction**
   (receptive vs productive — the central distinction of vocabulary pedagogy), response
   **latency**, **session** identity, and a snapshot of the **expected answer** (words are
   editable; re-judging needs the target as it was).

---

## Phase 1 — Findings

### 1.1 Spaced repetition: Ebbinghaus → SM-2 → FSRS

**Settled.** The forgetting curve is real and replicated ([Ebbinghaus 1885, replicated by
Murre & Dros 2015, PLOS ONE](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0120644)).
Spacing is among the most robust effects in learning science (Cepeda et al. 2006 meta-analysis;
Cepeda et al. 2008 shows the optimal gap scales with the retention interval, ~10–20%).
The theoretical backbone is a **two-strength model**: Bjork & Bjork's
[new theory of disuse](https://www.researchgate.net/publication/281322665_A_new_theory_of_disuse_and_an_old_theory_of_stimulus_fluctuation)
(1992) separates **storage strength** (durability; only grows) from **retrieval strength**
(current accessibility; decays). SuperMemo's Woźniak formalized the same split as
stability/retrievability ([supermemo.guru: two components of memory](https://supermemo.guru/wiki/Two_components_of_memory)).

**FSRS** (Free Spaced Repetition Scheduler, 2022–) is the modern open standard: a
three-component **DSR model** — Difficulty (item property, 1–10), Stability (days for
recall probability to fall to 90%), Retrievability (probability of recall now) — with ~20
parameters fit per user by gradient descent on the review log
([ABC of FSRS](https://github.com/open-spaced-repetition/awesome-fsrs/wiki/ABC-of-FSRS),
[algorithm overview](https://deepwiki.com/open-spaced-repetition/rs-fsrs/3.1-fsrs-algorithm-overview),
good narrative intro: [Denicola, "Spaced repetition systems have gotten way better"](https://domenic.me/fsrs/)).
On the [srs-benchmark](https://github.com/open-spaced-repetition/srs-benchmark)
(hundreds of millions of real Anki reviews) FSRS predicts recall with ~4% mean error vs
~14% for SM-2, and beats Duolingo's HLR; Anki has shipped it since 23.10, current builds
carry FSRS-6 with a short-term (same-day) memory component
([Anki FAQ](https://faqs.ankiweb.net/what-spaced-repetition-algorithm),
[expertium's benchmark notes](https://expertium.github.io/Benchmark.html)).

**Contested.** The exact forgetting-curve shape (FSRS moved exponential → power); how to
model same-day reviews (FSRS-6's short-term component is new); how much per-user parameter
fitting beats good defaults at small data volumes.

**Sources that matter:** srs-benchmark repo · ABC of FSRS wiki · Bjork & Bjork 1992.

### 1.2 Retrieval practice, desirable difficulties, learning from errors

**Settled.**
- **Testing effect**: retrieval beats restudy, with large meta-analytic effects —
  [Rowland 2014](https://pubmed.ncbi.nlm.nih.gov/25150680/) g ≈ 0.50 across 61 studies;
  [Adesope et al. 2017](https://journals.sagepub.com/doi/abs/10.3102/0034654316689306)
  g ≈ 0.61 across 217; foundational: Roediger & Karpicke 2006. Feedback amplifies the
  effect (Butler & Roediger). A *skip-then-reveal* is mere exposure, not retrieval — it
  earns no testing benefit.
- **Recall > recognition** for durable learning; production is the harder, more potent
  practice. This underwrites the verbatim > judged > self-assessed evidence ordering.
- **Desirable difficulties** (Bjork): conditions that feel harder — spacing, generation,
  testing — build storage strength precisely because retrieval strength is low when you
  succeed ([overview](https://www.unh.edu/teaching-learning-resource-hub/sites/default/files/media/2023-06/itow-introducing-desirable-difficulties-into-practice-and-instruction-bjork-and-bjork.pdf)).
  Corollary (retrieval-effort hypothesis, Pyc & Rawson 2009): *effortful* success > easy success.
- **Errors are productive** when followed by corrective feedback: errorful generation can
  beat errorless study (Kornell, Hays & Bjork 2009; Potts & Shanks 2014), and
  **hypercorrection** — errors committed with high confidence are the *most* correctable —
  is robust ([Butterfield & Metcalfe 2001](https://www.researchgate.net/publication/11641193_Errors_Committed_with_High_Confidence_Are_Hypercorrected);
  persistence over a week: [Butler, Fazio & Marsh 2011](https://link.springer.com/article/10.3758/s13423-011-0173-y);
  review: [Metcalfe 2017, Annual Review of Psychology](https://www.columbia.edu/cu/psychology/metcalfe/PDFs/Learning%20from%20errorsAnnual%20ReviewMetcalfe2016.pdf)).
  A mistake is a learning event, not the absence of one — direct support for R1/R3.

**Contested.** Interleaving clearly helps discrimination/category learning (Rohrer), but
evidence for plain L2 word pairs is mixed — don't build on it for vocab. Errorful-first
learning for absolute beginners is still debated.

**Sources that matter:** Adesope 2017 · Metcalfe 2017 · Bjork & Bjork (any desirable-difficulties chapter).

### 1.3 Self-assessment: how much does a "know" button deserve?

**Settled.** Immediate judgments of learning are poor predictors of later recall; *delayed*
JOLs are dramatically better — the delayed-JOL effect, meta-analyzed by
[Rhodes & Tauber 2011](https://pubmed.ncbi.nlm.nih.gov/21219059/) (45 studies: delaying
improves relative accuracy by g ≈ 0.93; delayed cue-only JOLs reach gamma ≈ .9).
JOLs ride on fluency heuristics and are systematically biased: stability bias (people
project current state forward, ignoring forgetting — Kornell & Bjork), and chronic
overconfidence that measurably impairs learning
([Dunlosky & Rawson 2012](https://www.sciencedirect.com/science/article/pii/S0959475211000685)).

**The nuance that matters for LearnWords:** an SRS "know/forgot" tap taken *after the
user attempted retrieval and saw the answer* is not a prediction — it is a self-graded
retrieval, the very mechanism Anki's entire model rests on. It is noisier and
optimistically biased relative to a typed verbatim answer, but far better than a glance-and-guess.
So the ordering **verbatim > judged > self-assessed is confirmed**, provided the flow
forces retrieval before the reveal; a pre-reveal "know" is the weakest signal in the app
and should be distinguishable in data (→ Phase 2, Change 3).

**Contested.** Whether self-assessment accuracy is trainable; how fast calibration
transfers across materials. (Per-user measurement sidesteps the debate — see Phase 3, #4.)

**Sources that matter:** Rhodes & Tauber 2011 · Dunlosky & Rawson 2012 ·
[Rhodes 2016 JOL chapter](https://pdf.retrievalpractice.org/metacognition/8_Rhodes_2015.pdf).

### 1.4 Vocabulary pedagogy: Nation, CEFR, depth

**Settled.** Knowing a word is multidimensional:
[Nation's framework](https://www.researchgate.net/figure/Components-of-vocabulary-knowledge-Nation-2001-p-27_tbl1_318459532)
(*Learning Vocabulary in Another Language*, 2001/2013) crosses three domains — **form**
(spoken, written, parts), **meaning** (form↔meaning link, concept, associations), **use**
(grammar, collocations, constraints) — each split **receptive vs productive** (18 aspects).
Receptive knowledge precedes and exceeds productive; production lags unless practiced
productively (Laufer). Deliberate pair learning (flashcards) is effective and respectable
for the initial form–meaning link (Nation defends it explicitly) but is
necessary-not-sufficient — depth comes from use in context (the lexical approach, Lewis
1993: language is chunks and collocations, not isolated words). Frequency-first pays:
~3,000 word families cover most speech; ~8–9,000 are needed for 98% written coverage
(Nation 2006; Laufer & Ravenhorst-Kalovski 2010). CEFR levels correlate with vocabulary
size ([Milton & Alexiou](http://www.eurosla.org/monographs/EM01/211-232Milton.pdf):
roughly A1 <1,500 · A2 ~2,000 · B1 ~3,000 · B2 ~3,500 · C1 ~4,500 · C2 ~5,000 lemmas on
a 5k test — estimates, language-dependent; CEFR itself defines no counts).

**Implications for the model:** (a) a single per-word score hides the receptive/productive
split — the *direction* of each review must be recorded; (b) the three tasks (flashcard /
dictation / phonetics) probe different aspects of Nation's grid — that is a feature, and
the log should preserve which aspect was probed; (c) frequency/CEFR tags are word
*metadata*, mutable, not event-schema-critical.

**Sources that matter:** Nation 2001/2013 · Milton (EUROSLA monograph) ·
[VKS, Wesche & Paribakht 1996](https://www.researchgate.net/publication/270844661_The_Vocabulary_Knowledge_Scale_A_Critical_Analysis).

### 1.5 Shipping products: models and failure modes

| Product | Progress model | Display | Known failure modes |
|---|---|---|---|
| **Anki** | SM-2 legacy; **FSRS** opt-in since 23.10, FSRS-6 in 25.x; full **revlog** kept forever | intervals/due counts; no mastery visual | SM-2 **ease hell** (ease sinks to 130% and never recovers → overreview); **leeches** (8+ lapses → suspend = giving up); review-debt avalanches ([issues with SM-2](https://kuroahna.github.io/anki_srs_kai/guide/issuesWithAnkiSM2.html), [Anki FAQ](https://faqs.ankiweb.net/what-spaced-repetition-algorithm)) |
| **SuperMemo** | SM-18; origin of the two-component stability/retrievability model | complex, expert-facing | complexity; closed ecosystem |
| **Duolingo** | published **half-life regression** ([Settles & Meeder, ACL 2016](https://research.duolingo.com/papers/settles.acl16.pdf); 13M-trace [open dataset](https://github.com/duolingo/halflife-regression)); superseded in-app by **Birdbrain** (IRT-style logistic ability×difficulty, v2 neural) ([how we learn how you learn](https://blog.duolingo.com/how-we-learn-how-you-learn/)) | word "strength" retired; streaks, XP, leagues | **streak anxiety** — loss-aversion mechanics make the streak the goal and the language the obstacle; recognition-heavy exercises → weak production ([critique](https://spellings.app/blog/duolingo-effect)) |
| **Memrise** | fixed growth stages (plant→flower ≈ 6 corrects), then "watering" at roughly fixed expanding intervals | garden metaphor | not adaptive; watering ignores actual memory state |
| **WaniKani** | 9 fixed **SRS stages** in 5 named groups (Apprentice×4 → Guru×2 → Master → Enlightened → **Burned**), intervals 4h→4mo; misses drop stages ([SRS stages](https://knowledge.wanikani.com/wanikani/srs-stages/)) | named stages + counts | one-size-fits-all intervals; post-break review avalanches; no per-user adaptation |
| **Quizlet** | Learn-mode rounds; familiar/mastered buckets (≈2 corrects) | round progress | "mastery" claim wildly inflated; recognition-heavy |
| **Clozemaster** | % Mastered = 4 correct plays of a cloze sentence (25% each); manual review intervals | % per sentence | crude counter; but **context-first** is its real lesson |

Cross-product patterns: every serious system keeps the **full review log** (Anki's revlog
is literally what FSRS was trained on — validating the ReviewEvent design); **named
stages** communicate better than raw percentages (WaniKani); a **retirement state**
("Burned") gives closure that Anki's infinite queue lacks; **fixed schedules and streak
gamification are the two recurring failure modes**.

### 1.6 Partial credit and near-miss grading

**Settled practice.** Typo tolerance via token + string edit distance, ignoring
case/punctuation/accents, penalizing omissions more than typos — this is Duolingo's
documented approach, with partial credit in the Duolingo English Test's graded item types
([DET official guide](https://englishtest-static.duolingo.com/media/resources/test-taker-guide/DET%20Official%20Guide%202024%20English.pdf)).
Language testing scores partial knowledge with polytomous models (Rasch **Partial Credit
Model**, Masters 1982) and instruments like the **Vocabulary Knowledge Scale** (Wesche &
Paribakht 1996): five levels from "never seen" to "can use in a sentence" — a validated
precedent for *graded* verdicts rather than binary marks. Semantic-similarity judging by
embedding distance is feasible fully on-device via `NLEmbedding`
(word embeddings iOS 13+, sentence embeddings iOS 14+ —
[Natural Language framework](https://developer.apple.com/videos/play/wwdc2020/10657/));
LLM rubric graders (the iOS 26 Foundation Models step) are the current state of the art.
A public benchmark for exactly this task exists:
[MuLVE, a multi-language vocabulary evaluation dataset](https://arxiv.org/pdf/2201.06286).

**Contested.** How generous to be with synonyms/semantic equivalents in *deliberate* vocab
drills (too generous → the target form is never learned); and how a continuous 0…1 verdict
should map onto an ordinal scheduler grade — that mapping is a design decision, not
settled science (→ Phase 2, Change 2).

---

## Phase 2 — Audit of `ProgressModel.md`

### The planted question first: is effort/mastery/retention just FSRS's D/S/R renamed?

**No — and the differences are the interesting part.**

| ProgressModel | FSRS | Verdict |
|---|---|---|
| Retention risk (time-decay) | **Retrievability R** | Same thing. Don't reinvent — compute it *as* FSRS R. |
| Mastery (recency-weighted evidence) | **Stability S** (≈ Bjork storage strength) | Overlapping but mis-specified: recency-weighting smuggles decay into mastery, so the double ring would show forgetting **twice**. Re-ground mastery in S: durability that grows with successful spaced retrieval and does not sag day-to-day. |
| Effort (invested work, mistakes count) | *(nothing)* — Difficulty D is an **item** property (how hard the card is), not invested work | **No counterpart in FSRS or any shipping product.** This is the model's genuine contribution. Keep, unchanged. |

**Should LearnWords adopt FSRS outright?** Adopt it as the *retention engine inside
`ScoringPolicy`* — not as the whole progress model. FSRS gives R and S from exactly the
data the event log holds (timestamped graded outcomes), is benchmark-proven, and has an
official Swift package ([open-spaced-repetition/swift-fsrs](https://github.com/open-spaced-repetition/swift-fsrs),
FSRS-6; alternative: [4rays/swift-fsrs](https://github.com/4rays/swift-fsrs), v5, ships
separate short-term/long-term schedulers) — per project preference for good libraries,
use one rather than hand-rolling decay math. But FSRS alone has no effort concept, no
evidence-strength tiers, no judge pipeline, no direction awareness: the ReviewEvent log is
a *superset* of FSRS's input. The right relationship: **FSRS is one derived index
implementation; the log remains the truth.** (Bonus: FSRS's optimizer can later fit
per-user parameters from this very log — a thing aggregates could never do, which
independently vindicates the no-migration decision.)

### Keep (validated by Phase 1)

- **Append-only ReviewEvent log as source of truth** — the revlog pattern; it is what made
  FSRS trainable at all (§1.1, §1.5). Also the CloudKit-friendly shape, as the doc argues.
- **Outcome taxonomy** separating `.correctVerbatim` / `.correctJudged` /
  `.selfAssessedKnown` — the recall > recognition > self-report ordering is confirmed
  (§1.2, §1.3). No shipping product records evidence strength this cleanly.
- **Negatives never cancel positives (R1)** — storage strength only grows (Bjork & Bjork
  1992); errors followed by feedback are learning events (Metcalfe 2017). Scientifically
  grounded, not sentimental.
- **Response text kept (R5)** — required for any re-judging; it is also what makes the log
  a MuLVE-style evaluation dataset of one's own learning.
- **Weights in code (`ScoringPolicy`), not data** — mirrors FSRS: versioned parameters in
  code, immutable history in data; recompute without migration.
- **Judgment attached async with `judge` id+version** — the same shape that lets Anki
  re-schedule old logs with newer FSRS versions.
- **`.skipped` = tiny effort, zero mastery** — correct: no retrieval attempt → no testing
  effect (§1.2); it is exposure, not evidence.
- **No migration of legacy aggregates** — independently justified: per-review history is
  the currency; aggregates cannot seed an FSRS state meaningfully.
- **Double ring mastery+effort with retention tint** — maps cleanly onto the two-strength
  theory (storage vs retrieval strength), *after* Change 1 below.

### Change (edit-ready)

1. **Redefine the indexes section** (`Derived, never stored as truth`):
   - *Retention risk* → "computed as **FSRS retrievability** R(elapsed, S) via the
     swift-fsrs package; the event log is exactly the algorithm's required input."
   - *Mastery index* → "a monotone display function of **FSRS stability S** (≈ storage
     strength): grows with successful spaced retrieval, unaffected by mere elapsed time.
     Evidence strength (verbatim > judged > self-assessed) enters through the
     outcome→grade mapping, not through an ad-hoc recency window." Delete
     "recency-weighted" — decay lives in retention only, or the ring shows forgetting twice.
   - *Effort index* → unchanged (explicitly note: no FSRS counterpart; ours).
2. **Add an explicit outcome→grade mapping table to `ScoringPolicy`** (FSRS consumes
   ordinal grades Again/Hard/Good/Easy): `.incorrect`/`.selfAssessedForgot` → Again ·
   `.correctJudged` → Hard (verdict below ~0.9) or Good · `.correctVerbatim` → Good, Easy
   when latency is fast (needs Add 2) · `.selfAssessedKnown` → Good (Anki-equivalent
   self-grade; per-user calibration can adjust later, Phase 3 #4). Mapping is versioned
   policy, in code.
3. **Pin down the self-assessment flow (§1.3):** the "know/forgot" tap must come *after*
   an attempted retrieval (prompt shown, user recalls, reveals, then grades). If the UI
   ever allows grading before reveal, record which flow produced the event — pre-reveal
   self-assessment is a JOL-grade signal, materially weaker. One sentence in the doc +
   a flow decision; no schema change if the flow is fixed to reveal-then-grade.
4. **Correct the near-miss ladder's availability claim:** step 2 "edit-distance + lemma
   (NaturalLanguage, iOS 12+)" is right for `NLTagger` lemmatization, but **semantic
   similarity needs `NLEmbedding`: word embeddings iOS 13+, sentence embeddings iOS 14+**.
   Ladder becomes: iOS 12 floor = Damerau-Levenshtein + lemma · iOS 13/14+ = + embedding
   cosine · iOS 26+ = Foundation Models graded verdict.
5. **Note the per-task memory question without over-engineering it:** the three tasks probe
   different aspects of Nation's grid (§1.4); v1 keeps **one FSRS state per word** (all
   directions feed it via the grade mapping), but *because direction is recorded* (Add 1),
   a per-direction split remains computable later. State this as a deliberate deferral.

### Add — schema gaps (append-only: cannot backfill; ranked by cost of omission)

1. **`direction`** (enum: which side was the cue — e.g. `.foreignToNative` /
   `.nativeToForeign`) — receptive vs productive is *the* organizing distinction of
   vocabulary knowledge (§1.4); flashcards can run either way, and without this field
   recognition and production mastery are forever indistinguishable in the log.
2. **`latencyMS`** (Int?, prompt→answer) — retrieval fluency separates effortful from
   automatic success: feeds the Hard/Easy grade split (Change 2), the effort index
   (time-on-task), and automaticity displays (WaniKani's Enlightened/Burned distinction is
   exactly "answer comes with little-to-no effort", §1.5). Anki logs per-review time for
   the same reason.
3. **`sessionID`** (UUID per sitting) — distinguishes massed same-session retries
   (short-term memory; must **not** count as independent long-term evidence — FSRS-6 has a
   separate short-term component for these) from spaced retrievals; defines "sittings" for
   effort and enables streak-free persistence stats. Timestamp clustering is a lossy
   heuristic; the ID is free at write time.
4. **`expected`** (String — the target answer as it was at review time; optionally also
   `prompt`) — words are editable, so re-judging (R5) against *today's* text corrupts
   history. Also improves FM judging ("given cue X, was Y close to Z?"). Trivial storage
   cost at this scale.
5. **`judgment.errorTags`** ([String]?, optional) — room for the judge to say *what kind*
   of miss (accent, article/gender, word order…), fueling the teaching-moment mechanic
   (Phase 3 #5). Lower risk since judgments are re-attachable, but reserve the field now
   to avoid struct churn.
6. **`schemaVersion`** (Int16 on event) — cheap forensic insurance for a log that will
   outlive several codebases; pair with unknown-case-tolerant decoding of the `outcome`
   enum so old builds skip unknown future outcomes instead of crashing.

Considered and rejected: device identifier (CloudKit record metadata already carries it);
per-event mood/context (YAGNI); storing computed scores in events (violates the
derived-in-code principle the doc already gets right).

---

## Phase 3 — Novel mechanics (ranked)

Each: the insight it builds on → what it feels like → data it needs (checked against the
ReviewEvent schema + Phase 2 additions). *Ship* = next-quarter realistic for a solo dev;
*North star* = direction, not commitment.

### 1. The effort ring: work that cannot be lost — *Ship*

**Insight.** Storage strength only grows (Bjork & Bjork 1992); errors with feedback are
learning events (Metcalfe 2017). Every shipping product hides effort — Anki shows debt,
Duolingo shows streaks; nobody shows *accumulated work as an achievement*.
**Feel.** The inner ring is monotone: it only ever fills (log-scaled lifetime attempts ×
sittings). A failed dictation visibly ticks it up — the app's quiet message: *that attempt
counted*. After a month away, mastery tint may fade, but the effort ring is untouched —
returning users are greeted by what they built, not by what they lost.
**Data.** Outcome counts ✓ (in schema) · sittings → `sessionID` (Add 3) · time-on-task →
`latencyMS` (Add 2). No further schema needs.

### 2. Honest forgetting: a retention forecast instead of a streak — *Ship*

**Insight.** The forgetting curve is lawful (Ebbinghaus; Murre & Dros 2015) and FSRS
predicts it per word (§1.1); streak mechanics convert habit into loss-aversion anxiety and
make the metric the goal (§1.5 failure modes).
**Feel.** No streaks anywhere. Instead, honest prediction: "12 words likely slipped below
70% — five minutes rescues them." Skipping a week is *modeled*, never punished; nothing
is zeroed. The ring's mastery size holds (stability), only its tint cools as
retrievability drops. Forgetting is presented as physics, not failure — the anti-Duolingo.
**Data.** Timestamps + outcomes ✓ → FSRS R per word. Nothing new.

### 3. Receptive and productive as visible strands — *Ship*

**Insight.** Nation's receptive/productive split (§1.4): recognizing a word and being able
to produce it are different knowledge, and production lags. Apps collapse both into one
number; users then wonder why "mastered" words won't come out of their mouths.
**Feel.** Word detail shows two small bars — "you recognize it / you can produce it" —
and practice auto-offers the lagging direction (a flashcard shown foreign-side vs
native-side; dictation is inherently productive). The ring's mastery = the *weaker* strand,
so "done" means usable, not just recognizable.
**Data.** **Requires `direction` (Add 1)** — the flagship reason that field must exist
before TD-13. Everything else derivable.

### 4. Personal calibration of the "know" button — *Ship (small); novel*

**Insight.** JOL accuracy is measurable and personal (§1.3). Research says "trust
self-assessment less" — but a private full event log can answer *how much less, for this
user*: compare `selfAssessedKnown` claims against subsequent objective outcomes
(typed/spoken within N days) — a per-user hit rate no server product computes.
**Feel.** A quiet stat: "Your 'know' taps proved right 84% of the time when tested within
a week." And it acts: `ScoringPolicy` scales the weight of self-assessed evidence by
measured calibration — the know button *earns* trust. Overclaimers get gently more typed
follow-ups; well-calibrated users get their taps honored.
**Data.** Event pairs per word ✓ + `direction` (Add 1) to compare like with like. Pure
derived computation — a `ScoringPolicy` feature, no schema change beyond Add 1.

### 5. The near-miss autopsy: judge as teacher — *Ship (diff); FM part North star*

**Insight.** Hypercorrection (§1.2): errors — especially confident ones — followed by
immediate, specific feedback are the most correctable; feedback quality drives the testing
effect (Butler & Roediger). A grader that only says "wrong" wastes the moment.
**Feel.** On a near-miss, a one-line micro-diff shows *what* was off (missing umlaut,
wrong article, transposed letters) with the differing span highlighted; on iOS 26+ the FM
names it ("gender: der→die") and offers a one-tap immediate retry. The retry logs in the
same sitting — extra effort, not fresh mastery evidence (Add 3 semantics).
**Data.** `response` ✓ · **`expected` snapshot (Add 4)** for a truthful diff even after
edits · `judgment.errorTags` (Add 5) · `sessionID` (Add 3) for retry semantics.

### 6. Stubborn-word coach: leeches get a strategy, not a suspension — *Ship*

**Insight.** Anki's leech handling is surrender (8 lapses → suspend, §1.5). Pedagogy says
stalling pairs need *different encoding*, not more of the same: context, collocation,
sound (Nation's depth dimensions, lexical approach §1.4).
**Feel.** When effort is high and mastery flat (both indexes exist ✓), a kind card:
"This one resists flashcards. Hear it? Type it in a phrase? Mnemonic?" — the app switches
task type instead of repeating the failing one. Effort spent on a stubborn word is framed
as the word being hard, not the user being bad (attribution matters for persistence).
**Feel bonus.** The stubborn list is quietly prestigious — hardest-won words.
**Data.** Effort/mastery per word ✓ · task variety per event ✓. No schema change.

### 7. The desirable-difficulty ladder — *North star (mechanically simple)*

**Insight.** Effortful retrieval strengthens more (Pyc & Rawson 2009); difficulty should
arrive when the learner can afford it (Bjork's desirable difficulties, §1.2). The three
task types already form a natural difficulty gradient: recognition flashcard → typed
production → spoken production.
**Feel.** Words climb an evidence ladder as stability grows: fresh words get the gentle
task, stable words *automatically* get promoted to harder proof — each success on a higher
rung visibly worth more (ring texture/badge per tier, WaniKani-style named stages without
the fixed schedule). "Burned"-like closure exists: verbatim spoken + high stability =
a word can retire (resurrectable), giving the queue an end — the thing Anki never grants.
**Data.** Stability (derived ✓) · `task` + `direction` per event (✓ + Add 1). No new fields.

### 8. "History heals": retroactive re-judging as a visible, kind event — *North star; wild*

**Insight.** Only a private, append-only, single-user log can afford to *re-score the
past*: server products never revisit old grades (cost, churn); LearnWords' judgments are
attachable-later by design, with judge id+version already in the schema.
**Feel.** After a judge upgrade (better FM model), a quiet note: "3 answers from March
were re-examined — two were closer than we knew. Mastery adjusted upward." Your record
gets *fairer over time*; mistakes can be posthumously vindicated. Companion mechanic: a
weekly on-device narrative ("you rescued 7 words from <40% retention; hardest-won word
this month: …") — competence feedback in the self-determination-theory sense, replacing
extrinsic streaks.
**Data.** `judgment` re-attachment ✓ · **`expected` snapshot (Add 4)** — without it,
re-judging edited words is corrupt · `sessionID` (Add 3) for the narrative. FM optional.

### Ranking rationale

1–3 are the identity of the app (effort visible, forgetting honest, production real) and
are cheap once the Phase 2 fields exist; 4 is the highest novelty-per-line-of-code (it
turns the JOL literature into a personal, private measurement); 5–6 convert the two
classic failure modes (dumb graders, leech surrender) into teaching moments; 7–8 are the
long arc. Note the dependency pattern: **every mechanic above runs on the four Add-fields
— direction, latency, session, expected — which is exactly why they must land in the
TD-13 schema now.**

---

## Source index

Memory & SRS: [srs-benchmark](https://github.com/open-spaced-repetition/srs-benchmark) ·
[ABC of FSRS](https://github.com/open-spaced-repetition/awesome-fsrs/wiki/ABC-of-FSRS) ·
[Anki algorithm FAQ](https://faqs.ankiweb.net/what-spaced-repetition-algorithm) ·
[Denicola on FSRS](https://domenic.me/fsrs/) ·
[Bjork & Bjork 1992](https://www.researchgate.net/publication/281322665_A_new_theory_of_disuse_and_an_old_theory_of_stimulus_fluctuation) ·
[supermemo.guru](https://supermemo.guru/wiki/Two_components_of_memory) ·
[Murre & Dros 2015](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0120644) ·
[swift-fsrs (official)](https://github.com/open-spaced-repetition/swift-fsrs) · [4rays/swift-fsrs](https://github.com/4rays/swift-fsrs)

Retrieval, difficulty, errors: [Rowland 2014](https://pubmed.ncbi.nlm.nih.gov/25150680/) ·
[Adesope et al. 2017](https://journals.sagepub.com/doi/abs/10.3102/0034654316689306) ·
[Bjork & Bjork, desirable difficulties](https://www.unh.edu/teaching-learning-resource-hub/sites/default/files/media/2023-06/itow-introducing-desirable-difficulties-into-practice-and-instruction-bjork-and-bjork.pdf) ·
[Butterfield & Metcalfe 2001](https://www.researchgate.net/publication/11641193_Errors_Committed_with_High_Confidence_Are_Hypercorrected) ·
[Butler, Fazio & Marsh 2011](https://link.springer.com/article/10.3758/s13423-011-0173-y) ·
[Metcalfe 2017](https://www.columbia.edu/cu/psychology/metcalfe/PDFs/Learning%20from%20errorsAnnual%20ReviewMetcalfe2016.pdf)

Self-assessment: [Rhodes & Tauber 2011](https://pubmed.ncbi.nlm.nih.gov/21219059/) ·
[Rhodes 2016 chapter](https://pdf.retrievalpractice.org/metacognition/8_Rhodes_2015.pdf) ·
[Dunlosky & Rawson 2012](https://www.sciencedirect.com/science/article/pii/S0959475211000685)

Pedagogy: [Nation's framework (table)](https://www.researchgate.net/figure/Components-of-vocabulary-knowledge-Nation-2001-p-27_tbl1_318459532) ·
[Milton, vocabulary across CEFR](http://www.eurosla.org/monographs/EM01/211-232Milton.pdf) ·
[VKS critical analysis](https://www.researchgate.net/publication/270844661_The_Vocabulary_Knowledge_Scale_A_Critical_Analysis)

Products & grading: [Settles & Meeder 2016 (HLR)](https://research.duolingo.com/papers/settles.acl16.pdf) ·
[HLR dataset](https://github.com/duolingo/halflife-regression) ·
[Duolingo Birdbrain](https://blog.duolingo.com/how-we-learn-how-you-learn/) ·
[Duolingo pedagogy critique](https://spellings.app/blog/duolingo-effect) ·
[WaniKani SRS stages](https://knowledge.wanikani.com/wanikani/srs-stages/) ·
[SM-2 failure modes](https://kuroahna.github.io/anki_srs_kai/guide/issuesWithAnkiSM2.html) ·
[DET official guide](https://englishtest-static.duolingo.com/media/resources/test-taker-guide/DET%20Official%20Guide%202024%20English.pdf) ·
[MuLVE dataset](https://arxiv.org/pdf/2201.06286) ·
[Natural Language framework (WWDC20)](https://developer.apple.com/videos/play/wwdc2020/10657/)

