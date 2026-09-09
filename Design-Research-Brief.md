# Design research brief — how progress is shown

**For:** a design-research session (Claude Design or equivalent), working in this repo.
**From:** the implementation session, after the TD-49…TD-53 learning-design batch shipped and
the owner reviewed it with fresh eyes.
**Transient:** consumed into `docs/Design.md` and `docs/MasteryAndProgressUI.md` once answered,
then deleted.

---

## What exists, so you design against reality

A UIKit vocabulary-learning app for iOS, Swift 6, storyboard-and-code, three exercises
(Learning / Dictation / Phonetic) over a spaced-repetition model. It is a **real shipped app
with a real design system**, not a greenfield — the job here is to make an existing visual
language apply consistently, not to invent a second one.

**Screenshots of the app as it stands today are in `design/ref/`.** Look at them first. They
are the "before", and two of them *are* the brief:

| File | What it shows |
|---|---|
| `word-list.png` | The main screen: words with a `ProgressRing` each |
| `word-preview-context-menu.png` | **Problem 1.** Long press on a word |
| `set-preview-context-menu.png` | Long press on a set — the same gesture, done better |
| `word-preview-russian.png` | The same word preview in Russian |
| `settings-study.png` | The two study preferences |

### The design system you must build on, not replace

Everything here is in `LearnWords/Shared/DesignSystem/`:

- **`ProgressRing`** — the app's signature. One ring carries three quantities at once:
  `mastery` (arc length), `effort` (a second track that never falls) and `retention`
  (colour, blending toward red as recall probability drops). It is on every row of the word
  list and in the set summary.
- **`BarStrip`** — one view, two layouts: `.stacked` is a distribution
  (untouched / learning / learned), `.alongside` is a 14-day due forecast.
- **`LWButton` / `LWButtonRow`**, **`LWWordLabel`**, **`ExerciseTransition`**.
- **Colour** is semantic and thin: `lwAccent` (orange), `lwAnswerCorrect` / `lwAnswerWrong` /
  `lwAnswerPending`, `lwTrack`, `lwTextPrimary` / `lwTextSecondary`. Dark and light both
  resolve; the screenshots are dark because that is what the owner runs.

### Constraints that are not negotiable

- **UIKit, not SwiftUI.** Table-view driven screens.
- **Assume an iOS 15 floor.** The project currently builds at 12.1, and raising it is a live
  decision (`docs/TechDebt.md` § TD-8) that this brief assumes will go the modern way. So
  sheet detents, modern context menus and SF Symbols are all fair game. Do **not** assume
  iOS 26-only material.
- **Three languages: en, es, ru.** Russian is roughly 30% longer than English and the owner
  reads the app in it. A layout that only works in English is not done — see
  `word-preview-russian.png`.
- **Dynamic Type and VoiceOver** are already honoured and must stay so. `ProgressRing` has an
  `accessibilityText`; `BarStrip` reads its segments out.
- **The numbers are not yours to invent.** What each quantity means is settled in
  `docs/ProgressModel.md` and `docs/MasteryAndProgressUI.md`. Read those before proposing a
  new metric; propose a new *view* of an existing one instead.

---

## The design questions, in priority order

### 1. The two context-menu previews — the reported defect

Long-pressing a word and long-pressing a set both open a `UIContextMenuConfiguration` with a
view controller as its **preview**. That gesture was chosen over a sheet precisely because it
can *show* something. Right now the two do not look like the same app:

- **The set preview** (`set-preview-context-menu.png`) has the vocabulary: a ring and a
  distribution bar per exercise, then a forecast. It is close to right.
- **The word preview** (`word-preview-context-menu.png`) has **none of it** — three sections
  of label/value text, two of which just say "Not practised yet". No ring, though the very
  row you long-pressed has one. The owner's words: *"look awful and does not even leverage
  the circled progress bar that should be common through the project."*

Two further defects visible in the shots, which a redesign has to solve rather than inherit:

- **Both previews are clipped.** The word preview cuts off mid-"Overall"; the set preview
  loses its retention and effort sections. The preview height comes from `contentSize` after
  layout, and the system caps it.
- **The set preview offers no menu actions at all** (`actionProvider` is `nil`), so a long
  press produces a floating card and nothing to do with it. Either it deserves actions, or
  this should not be a context menu.

**Design the pair as one answer.** What belongs in a preview — which is a *glance*, not a
screen — versus what belongs in the full screen it pushes to. An untried exercise is the
common case for a new word and currently costs a whole section to say nothing.

### 2. The statistics screen itself

The preview shows `SenseStatisticsViewController`, which is also the pushed screen. It is a
grouped table of label/detail rows: "Remembered for about 12 days", "Recall right now 87%",
"Due in about 3 days", "Successful days 4 days", per exercise, then an overall section with
effort and the recognised/produced split.

It is honest and completely flat. Nothing in it uses the ring, the bar, or colour. Ask
whether a glance-able layout can carry the same facts — and whether "per exercise" should be
three sections or one pivot control.

### 3. The entry screen (TD-55, already specified, not yet designed)

Recorded in `docs/TechDebt.md` § TD-55, with the owner's own sketch: a table with **Synonyms**
and **Meanings** sections, an always-available input row in each, "Add" in the section header,
and a comma advancing to the next row rather than being parsed afterwards. Designed so that
Tab lands naturally if this ever ports to macOS.

**This one is genuinely new**, so do not anchor on what ships today — the current confirm
screen (TD-53) is a stopgap the owner already intends to replace.

---

## What to deliver

Follow the sibling repos' convention:

- `.dc.html` boards in `design/`, one per round, plus a **"Shipped today"** board if it helps
  argue the before/after.
- A `DESIGN-HANDOFF.md` at the repo root: decisions settled, open questions marked, a build
  order, and a kick-off prompt for the next code session.
- Anything permanent — a component spec, a colour rule, a motion table — flagged for lifting
  into `docs/Design.md`, which outlives the boards.

**Say which of your proposals need a new component and which reuse `ProgressRing` /
`BarStrip` as they are.** The second kind can ship in a day; the first is a real cost and
should be argued for.
