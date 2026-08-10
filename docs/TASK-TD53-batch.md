# TASK — the rest of the learning-design batch: TD-53, TD-50, TD-52, TD-51

Handoff written 2026-08-09, after TD-49 landed and its PR review was answered. Read
[Roadmap](Roadmap.md) for priority, [TechDebt](TechDebt.md) for the register, and
[MasteryAndProgressUI](MasteryAndProgressUI.md) for the research behind all four items.
`docs/` is authoritative; when it disagrees with a code comment, `docs/` wins.

## Where things stand

TD-49 is done: **memory is kept per exercise** (`StrandProgress` inside `SenseProgress`),
`isLearned` means *every engaged exercise is learned* with a two-distinct-day gate, the
horizon preference is floored at 10 days, and `requireProductionForLearned` is the opt-in
stricter rule. 294 tests pass. `ScoringPolicy` is the single place that turns the log into
numbers; nothing is cached yet.

Everything below reads that model. **None of the four needs a schema change** — verified
when they were specced, and still true.

## Do these in order

### TD-53 — comma-separated entry, plus the entry screen the owner asked for
[LexicalModelResearch](LexicalModelResearch.md) § *Commas at entry* has the decision:
**parse, propose, confirm.** Split on comma into editable rows in the editor with a merge
control; default is the owner's rule (comma → separate meanings), because `берег, банк` is
two meanings while `лиса, лисица` is one meaning with two synonyms and no parser can tell.
`Lexicon.addSenses(to:terms:)` already takes `[[Term.Draft]]`.

Two additions the owner asked for on top of the research (2026-08-09):
* **Make commas less necessary.** In the editor, follow each filled input row with an empty
  one — a new row for another synonym, and the same for another meaning, as table sections.
* **Fix the back button.** It currently dismisses the whole stack; it should pop to the
  previous screen (the term), which is how the storyboard-wired app behaved.

**Entry-time only.** A `Synset` owns its `ReviewEvent` log, so splitting an *existing*
meaning would strand its history. Any later split or merge must be explicit and warned.

### TD-50 — per-term statistics, from a long-press context menu
Gesture is settled: `UIContextMenuInteraction` (iOS 13+), `UILongPressGestureRecognizer` +
sheet at the 12.1 floor, and `accessibilityCustomActions` either way. Trailing swipe is
**taken** by rename/delete on the sets screen.

Show **per exercise** — that is the owner's headline ask, and the data now exists:
`progress[.learning] / [.dictation] / [.phonetics]`, each with mastery, retention,
`successfulDays`, `dueAt`, `isEngaged`. Also stability in plain words ("remembered for
about 12 days"), effort, and the receptive/productive split from
`answersByDirection` (graded answers only since the review pass).

### TD-52 — measure, then cache
`ProgressIndex` is already a per-screen cache built from one fetch. Measure on a realistic
library **before** building TD-51's summary, which replays every event for every sense in a
set on every appearance. `ScoringPolicy.version` is 2 — any cache that persists must record
it, which is the whole reason it exists.

### TD-51 — set summary, pivoted by exercise
Distribution over averages (a mean of 0.5 describes two opposite sets); 14-day due forecast;
true retention by maturity; effort totals; the receptive/productive gap. Reference is Anki's
stats screen. The owner wants it **pivoted by exercise** — likely a ring per exercise, and
asked whether **negative progress rings might run in the opposite direction**; that is an
open design question worth a proposal, not a settled decision.

`ReviewSchedule.SetDigest.dueByExercise` already carries per-exercise due counts and wants a
test — it has none, which the review pass flagged and this handoff did not close.

## Also owed, small

* **Settings**: a switch for `requireProductionForLearned` (the preference exists and is
  read; nothing sets it). The horizon slider minimum is already floored from
  `ScoringPolicy.minimumHorizonDays`.
* **TD-24 / XcodeGen**: the owner fixed the extension `CFBundleVersion` mismatch by hand and
  it will return every release. Generating the project is under consideration; if it is
  taken up, it is its own branch and its own PR.

## How to work here

**Build and test — do not pass `CODE_SIGNING_ALLOWED=NO`.** That flag strips entitlements,
and CloudKit then traps at launch asking for a container the binary is not entitled to. It
cost this session an entire wrong diagnosis (TD-54, withdrawn). Use:

```
xcodebuild -project LearnWords.xcodeproj -scheme LearnWords -configuration Debug \
  -destination 'id=<sim>' -derivedDataPath /tmp/lw-dd test
```

iPhone 17 Pro / iOS 26.5 (`651B025B-EF1E-4A7F-AE46-01A3C9F75FBD`) was the working simulator;
294 tests, roughly 90 seconds. Swift Testing failures do not print their message in the
xcodebuild log — read the newest `.xcresult` with
`xcrun xcresulttool get test-results tests --path … --compact`, and mind that `ls -t` can
hand back a *stale* bundle (that cost a wrong conclusion here too).

**The review loop.** Branch, PR against `laconicman/LearnWords` `main`, wait for Devin's
review, answer **every** thread, push fixes, iterate. Its fresh look is worth having: ten
findings on TD-49, of which seven were applied, one was rejected with evidence, and one
retracted a whole commit. Disagreeing is fine when the reasoning is shown — one suggestion
there would have made reminders nag forever, and saying so with the failing test names was
the right answer.

**The golden rule:** for any public repo, consult DeepWiki (`/deepwiki`) before ruling on how
it behaves, minding the indexed commit.

**Conventions:** no AI attribution in commit messages — no `Co-Authored-By`, no "generated
with". Name or derive layout values; a surviving literal must justify itself. Say which half
of a claim is verified and which is reasoned — this project has been bitten repeatedly by
green tests hiding a visual or device-only regression.
