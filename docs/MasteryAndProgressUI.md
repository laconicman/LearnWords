# Mastery thresholds and progress UI — research

Three owner questions (2026-08-09), researched against the sources already landed in
[ProgressResearch](ProgressResearch.md) plus new reading where those did not reach.
The fourth question of that batch — comma-separated entry — is lexical, and lives in
[LexicalModelResearch](LexicalModelResearch.md) § *Commas at entry*.

**Headline for the schema-anxious: none of these three needs a schema change.** Every
number below is derivable from the `ReviewEvent` log as it already stands — which is the
event-sourcing design paying for itself before CloudKit deploy. The only new persistence
question is a *cache* (§3.4), and a cache is not a schema commitment.

---

## 1. How much repetition makes a term "learned"?

### 1.1 What the app does today, measured

`ScoringPolicy.isLearned` is `mastery >= 1`, and mastery is
`log1p(stability) / log1p(masteryHorizonDays)` — so **learned ⇔ FSRS stability ≥ the
horizon** (the "Remembered for (days)" slider, default 20).

With the shipped FSRS-6 weights, a meaning's *first* graded answer sets stability to
`w[grade-1]`:

| First answer | Initial stability | Mastery at horizon 20 | Learned? |
|---|---|---|---|
| Again | 0.21 d | 0.06 | no |
| Hard | 1.29 d | 0.27 | no |
| Good | 2.31 d | 0.39 | no |
| Easy (fast verbatim) | **8.30 d** | 0.73 | no |

So at the default horizon one pass does **not** mark a term learned. Two things can make
it look as if it does, and they are worth separating:

1. **The queue effect (expected).** One Good answer schedules the next review ~2 days out,
   one Easy ~8. The word leaves *today's* due list immediately. From the learner's chair
   that reads as "done" even though mastery is 0.39.
2. **The horizon floor (a real defect).** Because Easy's initial stability is 8.3 days,
   **any horizon below ~8 days makes a single fast correct answer sufficient for
   `isLearned`** — mastery is clamped at 1. The slider's range starts at 1. At horizon 3,
   one Easy answer = learned, permanently, on a word seen exactly once. → **TD-49.**

### 1.2 What the literature says the dial should be

**The count is the wrong dial.** The definitive result is Bahrick, Bahrick, Bahrick &
Bahrick 1993, a nine-year study of 300 word pairs:
[*Maintenance of Foreign Language Vocabulary and the Spacing Effect*](https://gwern.net/doc/psychology/spaced-repetition/1993-bahrick.pdf)
(Psychological Science) — **13 relearning sessions spaced 56 days apart yielded retention
comparable to 26 sessions spaced 14 days apart.** Wider spacing slowed acquisition slightly
and repaid it many times over in retention; session count and spacing contributed
*independently*. Halving the work by spacing it better is the single most robust finding
available on this question, and it says plainly: *"how many repetitions" has no answer
without "at what spacing"*.

That is precisely why FSRS models **stability** (days a memory survives) rather than
counting correct answers, and it is why the app's horizon-in-days framing is already the
research-correct shape. The earlier
[ProgressResearch §1.1](ProgressResearch.md) established the same two-strength basis
(Bjork & Bjork's storage vs retrieval strength).

**But a count-like gate still has a job.** One retrieval, however fast, contains *zero
spacing evidence* — the spacing effect is undefined for a single session. Nothing in the
literature supports declaring a word durably known from one sitting; Bahrick's floor
condition was thirteen. So the honest rule combines the two:

> **learned ⇔ stability ≥ horizon *and* ≥ N successful retrievals on N distinct days.**

N = 2 is the minimum that makes the phrase "spaced" true at all; N = 3 is the conservative
choice. Both are derivable from the log (`sessionID` + `date`), no schema change.

### 1.3 What to expose to the learner

Three candidate dials, in order of how well the research supports them:

1. **Desired retention** — the dial Anki exposes and FSRS is built around
   (`requestRetention`, currently hard-coded 0.9). It means "what chance of recall is good
   enough", and it moves review load in the way the learner actually feels. Principled,
   one number, well-understood defaults (0.85–0.95).
2. **Mastery horizon** (already shipped) — "remembered for N days". Intuitive, and it is
   the definition of `isLearned`. Keep, but floor it (§1.1) and pair it with the
   distinct-day gate.
3. **Raw repetition count** — what the owner's question literally asked for, and the one
   the research argues *against* exposing as the primary control: it invites the learner to
   optimise the metric that Bahrick showed is substitutable by spacing. If it appears at
   all, it should be the N of the distinct-day gate (a small integer, 1–5), not a target.

**Recommendation:** ship the distinct-day gate + horizon floor now (both are a few lines
and remove a real defect), expose desired retention as a second Study slider when there is
appetite, and do not expose a repetition target. A "thoroughness" preset
(Casual / Standard / Thorough) setting horizon + retention + N together would be kinder
than three raw sliders — the same argument that retired the Settings.bundle pane.

### 1.4 What shipped (2026-08-09)

All of the above, plus the per-exercise dimension the owner added: **memory is now kept per
exercise**, and `isLearned` means *every exercise the learner has engaged is learned*
(engagement, not "all three", so nothing already earned was wiped). Failing a new exercise
un-learns the meaning. `requireProductionForLearned` is the opt-in academic dial. Aggregates
report the weakest engaged strand rather than an average. Details and rationale: TD-49's
resolution note in [TechDebt](TechDebt.md).

Two UI debts follow from it, owed by §2/§3's screens: a settings switch for
`requireProductionForLearned`, and the horizon slider's minimum moving 1 → 10 to match the
floor now enforced in code.

---

## 2. Per-term statistics popup

### 2.1 Which gesture — the platform answer

The owner floated double-click, long-click, or right-to-left swipe. Ranked against Apple's
[HIG](https://developer.apple.com/design/human-interface-guidelines/) and this app's
existing gestures:

| Gesture | Verdict |
|---|---|
| **Long press → context menu** (`UIContextMenuInteraction`, iOS 13+) | ✅ **The platform answer.** Purpose-built for "show me more about this item", supports a rich *preview* above the actions, dismisses by tapping away, and is free for VoiceOver via the rotor's Actions. |
| Right-to-left swipe | ❌ **Already taken** — the sets screen uses trailing swipe for rename/delete (and fork C's bug came from exactly that path). Swipe actions are for *acting on* a row, not inspecting it. |
| Double tap | ❌ Not an iOS idiom for inspection (it means zoom in Maps/Photos, and VoiceOver claims it for activation). Undiscoverable, and it fights the single tap. |

**iOS 12 floor:** `UIContextMenuInteraction` is iOS 13+. Fallback is a
`UILongPressGestureRecognizer` presenting the same content as a sheet — same gesture, less
polish, so the mental model is identical across versions. Whatever the fallback, add
`accessibilityCustomActions` on the cell: a bare long-press gesture is invisible to
VoiceOver, and the context-menu path is not.

### 2.2 What to show

The log can answer far more than "how many right". Ranked by value:

- **Stability in plain words** — "remembered for about 12 days" beats a percentage; it is
  the quantity the horizon slider is denominated in.
- **Retention right now** — FSRS retrievability, and the next due date.
- **Receptive vs productive** — two small bars. The `direction` field exists precisely for
  this, and it is [ProgressResearch Phase 3 #3](ProgressResearch.md): "you recognise it /
  you can produce it". No other app in that survey shows the split. **This is the popup's
  reason to exist.**
- **Effort** — attempts, distinct sittings, time on task (`latencyMS`). Never decreases;
  the one number that a bad week cannot take away.
- **Per-exercise breakdown** — which of the three tasks this word actually fails in.
- **Recent history** — the last handful of events as marks on a line, wrong ones included.

Everything above is a replay of the log. No schema change. → **TD-50.**

---

## 3. Set summary statistics

### 3.1 The trap in "some averages"

A mean mastery of 0.5 is produced both by fifty half-learned words and by twenty-five
mastered plus twenty-five untouched — and those two sets need opposite actions. Averages
also hide the shape that matters most in an SRS: *when the work is coming*.

### 3.2 What the reference implementation shows

Anki's statistics screen is the closest thing to a settled answer — Today, **Future Due**,
Calendar, Reviews, **Card Counts** (distribution by maturity), Review Intervals, and
**True Retention** (percentage answered correctly, bucketed by maturity), the metric its
community adopted precisely because it is harder to fool than any average. Duolingo's
counter-example is instructive in the other direction: streaks and XP are averages of
nothing, and [ProgressResearch §1.5](ProgressResearch.md) catalogues the anxiety they
produce.

### 3.3 Proposed set summary

- **Distribution, not a mean** — one stacked bar: untouched / learning / learned, by the
  §1.2 definition. Answers "where is this set" in one glance.
- **Due forecast** — a small 14-day bar chart of what falls due. This is
  [Phase 3 #2](ProgressResearch.md) "honest forgetting": prediction, never a streak.
- **True retention** — of answers given, the share correct, split by young/mature. The
  honest success number.
- **Effort totals** — sittings, attempts, time. The set-level twin of the effort ring.
- **The receptive/productive gap** — one line: "you recognise 80%, you can produce 45%".
  Averages here are *meaningful*, because the two are being compared, not collapsed.
- **The averages as asked** — mean stability and mean retention, shown beside the
  distribution rather than instead of it.

→ **TD-51.**

### 3.4 The cost, and the cache that ProgressModel promised

Both §2 and §3 replay the log — §3 for every sense in the set, and the word list already
wants per-row progress. [ProgressModel](ProgressModel.md) agreed a per-word cache "in
principle, mechanism negotiable" and deferred it to implementation. That debt is now due:
a set summary that replays every event on every appearance will be the first thing to feel
slow on a real library. Measure before optimising, but measure *before shipping the
summary*, not after. → **TD-52.**

---

## Sources

- Bahrick, Bahrick, Bahrick & Bahrick 1993,
  [Maintenance of Foreign Language Vocabulary and the Spacing Effect](https://gwern.net/doc/psychology/spaced-repetition/1993-bahrick.pdf)
  — 13 sessions @ 56 d ≈ 26 sessions @ 14 d; spacing and session count contribute independently.
- Rogers, [Repetition, Retrieval, and Spaced Practice](https://onlinelibrary.wiley.com/doi/10.1002/9781405198431.wbeal20349)
  (Encyclopedia of Applied Linguistics) — repetition-count effects are conditional on spacing and task.
- [ProgressResearch](ProgressResearch.md) §§1.1–1.5 — FSRS/DSR, Bjork two-strength, JOL
  reliability, Nation's receptive/productive split, the shipping-product failure modes.
- Apple HIG — context menus; `UIContextMenuInteraction` (iOS 13+).
- Anki statistics (Future Due, Card Counts, True Retention) as the reference stats screen.
