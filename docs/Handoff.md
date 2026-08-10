# Handoff — forks A through G, plus word entry and permissions

Where the project stands as of 2026-07-27, what is proven, what is assumed, and what the
next forks should pick up. Read [Roadmap](Roadmap.md) for priority and
[TechDebt](TechDebt.md) for the register; this file is the state of play between them.

## What landed

**TD-13 is done, iterations 1–5, and the app is due-driven.** It runs on a Core Data
lexicon, syncs it to CloudKit, derives progress from an append-only review log, asks what
the schedule says is due, and can remind the learner when work is waiting.

| Fork | Result |
|---|---|
| **A — scoring** | `ScoringPolicy` replaces `InterimMastery`; mastery/retention/effort derived by replaying the log with a port of FSRS-6. `ProgressRing` retires 556 vendored lines. |
| **B — CloudKit** | Host app mirrors on iOS 13+; extensions and iOS 12 stay local. `StoreDeduplicator` repairs what sync duplicates. |
| **C — store/UI gap** | `MeaningEditorViewController`; synonyms, set rename, orphan collectors, inflection-aware search. |
| **D — Anki format** | `AnkiText` exports an Anki-importable file keyed by `Sense.id`, so re-export updates rather than duplicates. |
| **E — enrichment** | [Enrichment](Enrichment.md): kaikki ingestion designed, three schema additions identified. |
| **G — spaced repetition** | `PracticeSession.Scope`, `ReviewSchedule`, `ReminderScheduler`; "Known level" becomes "Remembered for (days)". |
| *(integration)* | `WordInputViewController` with dictation replaces the add-synonym alert; `WordSuggestions` and `DictationController` extracted; permissions re-read rather than stored. |

`217 tests pass, none fail.` Verified on the simulator and, for A–C, on two physical
devices (iOS 26 + iOS 15) syncing through iCloud.

## What is proven, and what is not

Distinguish these when planning — several of the recent bugs came from treating the second
column as the first.

| Claim | Status |
|---|---|
| Store opens under CloudKit; schema has all ten record types | ✅ measured on device |
| Two devices sync a word set and a word | ✅ observed both directions |
| Duplicate `Term`/`Language` rows merge after sync | ✅ 10 tests + one real merge (23 rows) |
| FSRS-6 port matches upstream | ✅ checked against swift-fsrs' own oracles |
| Anki export is importable | ✅ bytes read back out of the app container |
| Practice is due-driven; study-ahead offered when nothing is due | ✅ exercised on the simulator |
| Reminder *derivation* — which days, what count, what identifier | ✅ 9 tests, pinned clock |
| The reminder switch requests permission | ✅ owner-confirmed on device |
| **A reminder actually arrives** | ✅ **owner-confirmed on device, 2026-08-09.** Content and timing are a separate matter — the "learned" rule behind what it counts as due is TD-49 |
| Word entry: suggestions, recents, commit | ✅ 10 tests + built |
| **Dictation actually transcribes** | ✅ **owner-confirmed, 2026-08-09** — works on iOS 12 and above |
| Audio session returns to playback after recognition (TD-15's bug) | ✅ 5 tests, two proven to fail against the old code |
| **Speech still audible after a Phonetics round, on a device** | ⚠️ tests pin the session state; the sound itself needs an ear |
| Deferred seeding stops the second device seeding | ⚠️ not verified — needs a clean install on device 2 |
| Live UI refresh on incoming changes | ⚠️ not verified on two devices |
| iOS 12–14 behaviour since the store change | ⚠️ partly — dictation confirmed on iOS 12; the rest **deferred to testers and users after publication** (owner, 2026-08-09), so TD-8 is a beta-feedback item rather than a pre-ship gate |

## Before shipping anything

1. ~~Confirm a reminder arrives and try the dictation button.~~ **Done 2026-08-09** — both
   owner-confirmed on device. What a reminder *says* still depends on the learned rule,
   which TD-49 changes.
2. ~~Decide whether a meaning belongs to one set or many.~~ **Closed 2026-08-09 — many.**
   Not chosen: settled by the deploy that TD-48 found had already happened, since narrowing
   a mirrored relationship's cardinality is exactly what an immutable production schema
   forbids. It landed on the recommended option, so only the optionality was lost.
   `deleteOrphanedSenses` (already given its semantics by TD-26) is now permanent
   architecture rather than a placeholder, and a shared "Hard words" set is unlocked.
   [Design](Design.md) § *a meaning belongs to many sets*.
3. ~~Decide the three schema additions.~~ **Done** — `Variety`, `Pronunciation`,
   `Tag.category` and `Language.wiktionaryCode` landed in `f833280`; `Term.transcription`
   stays as two dead columns in the container, deliberately (TD-48).
4. **Two-device retest** of the deferred seed and live refresh. Delete the app from both
   devices and reset the CloudKit Development environment first, so double-seeded
   duplicates are not mistaken for a regression.
5. **Deploy Schema Changes** in the CloudKit Console — *after* re-running
   `-LWInitializeCloudKitSchema 1` and confirming the exported schema still lists all
   `CD_` types. Irreversible.
6. **Push Notifications capability** for timely sync ([CloudKitSetup](CloudKitSetup.md)).
   Unrelated to the local reminders above, which need no capability.
7. **TD-24** — extension `CFBundleVersion` is `1` against the app's `7`. App Store Connect
   rejects that at submission.

## Candidate forks

Ranked by what the project most needs, with the merge surface each owns.

**H — `SearchWordViewController` (TD-28).** ~600 lines doing search, suggestions,
dictionary lookup, segue routing and store writes. Every bug found in the add-word flow so
far has been a coordination bug hiding in its size. Owns `Features/Search/` and its
storyboard scenes.

**I — enrichment implementation (TD-22).** [Enrichment](Enrichment.md) designs it. First
job is a measurement, not code: the reduction ratio on one real kaikki file. Carries the
three schema additions, so it wants the `.xcdatamodeld` and should be sequenced against
the CloudKit deploy decision.

**J — settings and housekeeping.** TD-26 (orphan collectors have no UI), TD-24 (bundle
versions), TD-30 (the ring's Dynamic-Type size), and a UI-test pass that can actually
drive a switch (TD-29).

**K — `CSSearchableItemActionType`.** Words are indexed in Spotlight; tapping a result does
not route into the app. Small, isolated, owns `AppRoot`.

## Cross-fork rules that worked, and one that did not

1. **Nobody edits `Roadmap.md` or `TechDebt.md`** — hand back a paragraph, the integrator
   reconciles. This worked across six forks; keep it.
2. **`LearnWords.xcdatamodeld` belongs to one fork at a time.**
3. **Run the full suite before handing back.** A fork that hands back red is a fork whose
   work has to be re-verified from scratch.
4. **What did not work: assuming a screen's existing behaviour is intact.** Fork C added a
   rename swipe action to the sets screen and silently removed delete, because
   `trailingSwipeActionsConfigurationForRowAt` replaces the default `commit editingStyle:`
   path. **Exercise the screen you changed, not just the thing you added.**

## Standing conventions

- **No AI attribution in commit messages.** No `Co-Authored-By`, no "generated with".
- **Consult DeepWiki for any public repo** before ruling on how it behaves — `swift-fsrs`,
  `ankitects/anki`, `ankidroid/Anki-Android`, `tatuylonen/wiktextract` are all indexed, as
  is this repo. Check the staleness warning; wiktextract's index was 205 days behind and
  had four numbers wrong, though its structural answers held.
- **Verify on device, not by reasoning.** Bugs this week that looked like sync failures and
  were not: a stale UI snapshot, two diverged set selections, an add-word screen whose only
  commit path was the Return key. When a Core Data result contradicts the code, print what
  is actually stored.
- **Say which half is verified.** Fork B could not test two-device sync; fork G could not
  test a switch. Both said so in the commit rather than implying coverage they did not have.
