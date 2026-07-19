# TASK — TD-16 adoption: shared exercise transitions + KaPow effects

> **Status: executed 2026-07-19.** Steps 1–3 done (`ExerciseTransition.advance`, KaPow
> linked as a local package, mapping wired in all three screens); 36/36 tests green incl.
> the leave-during-delay lifetime test. Open: the manual pass in § Verification.

Handoff from the KaPow porting sessions (2026-07-19). Read
`AnimationSystem.md` (this folder) first — research, options, and the
decision record. This task executes steps 1 and 3 of its "C-lite" plan.

## Context

- **KaPow** — the UIKit port of Pow (Shake, Jump, Shine, Spray; iOS 12
  floor; all effects tested and verified side-by-side against the original)
  lives **outside this repo** at `/Users/paul/Documents/Code/Animations/KaPow`.
  Its DocC catalog (`Sources/KaPow/KaPow.docc/`) is authoritative for the
  port's design. Read `Design.md` § "Coexistence with UIKit's animation
  system" before wiring effects — it defines the one rule that matters here.
- The comparison app is `/Users/paul/Documents/Code/Animations/KaPowShowcase`
  (XcodeGen; shows the calling patterns for every effect).

## Step 1 — DRY the exercise transitions (do this first)

The same two `UIViewPropertyAnimator` blocks are copy-pasted across all
three exercise screens (six blocks, all `[weak self]` since the hotfix):

- `LearnWords/Features/Test/WordTestViewController.swift:223`
- `LearnWords/Features/Dictation/WordDictationController.swift:231`
- `LearnWords/Features/Phonetics/WordPhoneticsViewController.swift:303`

Spring-in: duration 0.5, dampingRatio 0.5, alpha/transform reset, delayed
start 0.1 s. Shrink-fade-out: scale 0.8, easeInOut, `askQuestion()`
completion, delayed start 2 s — that delay outliving the screen was the
original TD-16 crash.

Extract **one** shared `ExerciseTransitionAnimator` (Controller/DesignSystem
layer per `uikit-app-structure`) with lifetime-safe completion semantics —
the completion must not capture the view controller. Keep
`UIViewPropertyAnimator`: it is the right tool for predetermined one-shot
curves.

Success criteria: six blocks become three call sites of one animator; build
green; leaving a screen during the 2 s delay is provably safe (test it).

## Step 2 — add the KaPow package

Local SPM package reference to `/Users/paul/Documents/Code/Animations/KaPow`.
Floor is iOS 12, so no availability gating is needed at 12.1.

## Step 3 — product mapping (from AnimationSystem.md)

- Wrong answer → `answerView.kapow.shake()`
- Correct answer → `answerView.kapow.shine()` (owner leaned Shine; Jump is
  ported too if it fits better in place)
- Word reaches known level → `view.kapow.spray(images:)` (SF-symbol particle;
  see the showcase for the tinting pattern)

**Rule:** transitions animate the exercise *container*; KaPow effects fire on
*child* views (answer label/field). Never both on the same view's same
property — the KaPow Design doc explains why they don't compose.

## Constraints

- KaPow effects already respect Reduce Motion and never capture the VC —
  don't wrap them in extra lifetime machinery.
- Spray's haptic burst is not ported yet (KaPow TD-4); fine to ship without,
  revisit on a physical device.

## Verification

- Build + existing tests green.
- Manual pass on all three exercise screens: transition in/out, wrong-answer
  shake, correct-answer shine, level-up spray.
- The TD-16 crash scenario: answer, then leave the screen within the 2 s
  delay — no crash, no leak.
