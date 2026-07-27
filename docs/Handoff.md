# Handoff — forks A, B and C are merged

Where the project stands as of 2026-07-27, what is proven, what is assumed, and what the
next forks should pick up. Read [Roadmap](Roadmap.md) for priority and
[TechDebt](TechDebt.md) for the register; this file is the state of play between them.

## What landed

**TD-13 is done, iterations 1–5.** The app runs on a Core Data lexicon, syncs it to
CloudKit, and derives progress from an append-only review log.

| Fork | Result |
|---|---|
| **A — scoring** | `ScoringPolicy` replaces `InterimMastery`; mastery/retention/effort derived by replaying the log with a port of FSRS-6. `ProgressRing` retires 556 vendored lines. |
| **B — CloudKit** | Host app mirrors on iOS 13+; extensions and iOS 12 stay local. `StoreDeduplicator` repairs what sync duplicates. |
| **C — store/UI gap** | `MeaningEditorViewController`; synonyms, set rename, orphan collectors, inflection-aware search. |
| *(integration)* | Double-seed, live refresh, read-after-write, schema initialisation, log noise. |

`173 tests pass, none fail.` Verified on the simulator and on two physical devices
(iOS 26 + iOS 15) syncing through iCloud.

## What is proven, and what is not

Distinguish these when planning — several of the recent bugs came from treating the second
column as the first.

| Claim | Status |
|---|---|
| Store opens under CloudKit; schema has all ten record types | ✅ measured on device |
| Two devices sync a word set and a word | ✅ observed both directions |
| Deleting a set replicates | ✅ owner-verified |
| Duplicate `Term`/`Language` rows merge after sync | ✅ 10 tests + one real merge (23 rows) |
| Deferred seeding stops the second device seeding | ⚠️ **not verified** — needs a clean install on device 2 |
| Live UI refresh on incoming changes | ⚠️ **not verified on two devices** |
| FSRS-6 port matches upstream | ✅ checked against swift-fsrs' own oracles |
| iOS 12–14 behaviour since the store change | ❌ **unverified** (TD-8; owner has devices) |

## Before shipping anything

1. **Two-device retest** of the deferred seed and live refresh. Delete the app from both
   devices and reset the CloudKit Development environment first, so the double-seeded
   duplicates are not mistaken for a regression.
2. **Deploy Schema Changes** in the CloudKit Console — *after* re-running
   `-LWInitializeCloudKitSchema 1` and confirming the exported schema still lists all ten
   `CD_` types. Irreversible: record types and fields are immutable once in Production.
3. **Push Notifications capability** for timely sync ([CloudKitSetup](CloudKitSetup.md)).
4. **TD-24** — extension `CFBundleVersion` is `1` against the app's `7`. App Store Connect
   rejects that at submission.

## Candidate forks

Ranked by what the project most needs, with the merge surface each owns.

**G — spaced repetition and local reminders.** `ScoringPolicy` yields a due date per
meaning, but `PracticeSession` still queues the whole set shuffled, so nothing is
due-driven yet. Owns `Controllers/`, `Features/Settings/`, `AppRoot`, `Info.plist`. Traps:
the 64-pending-notification cap, and computing a count *before* the app opens
(`BGAppRefreshTask` on iOS 13+, a countless reminder at the 12.1 floor).

**H — `SearchWordViewController` (TD-28).** ~600 lines doing search, suggestions,
dictionary lookup, segue routing and store writes. Every bug found in the add-word flow so
far has been a coordination bug hiding in its size. Owns `Features/Search/` and the
storyboard scenes for it.

**E — enrichment research (TD-22), docs only.** Still unstarted, still zero conflict.
`docs/Enrichment.md`: kaikki/Wiktionary ingestion, where `Variety` lands, licence
attribution. Also the home for the wiktextract re-index request.

**I — settings and housekeeping.** TD-26 (orphan collectors have no UI), TD-24 (bundle
versions), and the reminder settings G will need. Small, and unblocks G.

**D — Anki interchange format.** Still on the roadmap, still unowned. Note Anki's TTS tag
takes an underscored full locale matched by exact string equality, so an export must emit
the learner's locale preference rather than our bare `Language.code`.

## Cross-fork rules that worked, and one that did not

1. **Nobody edits `Roadmap.md` or `TechDebt.md`** — hand back a paragraph, the integrator
   reconciles. This worked; keep it.
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
  `ankitects/anki`, `tatuylonen/wiktextract` are all indexed. Check the staleness warning;
  wiktextract's index was 205 days behind and needed verifying against the live source.
- **Verify on device, not by reasoning.** Three separate bugs this week looked like sync
  failures and were not: a stale UI snapshot, two diverged set selections, and an add-word
  screen whose only commit path was the Return key. In each case the log looked healthy.
  When a Core Data result contradicts the code, print what is actually stored.
